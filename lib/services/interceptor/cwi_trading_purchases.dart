part of '../client_write_interceptor.dart';


// ═══════════════════════════════════════════════════════════════════════════
// Trading module — Sales · Inventory · Commercial Papers · Safe Operations
//                  Stock Transfers · Purchase Auto-Push
//
// Part of the ClientWriteInterceptor library.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiTradingPurchases {
  _CwiTradingPurchases._();

  // ── Sales ─────────────────────────────────────────────────────────────────


  // ── Safe Operations ───────────────────────────────────────────────────────

  static Future<bool> submitSafeTransfer({
    required int fromSafeId,
    required int toSafeId,
    required double amount,
    int? userId,
    String? description,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing safe transfer to server');
    // هوية العملية بتتسك هنا مرة واحدة وبتتخزن في الـpayload، فالمحاولة
    // الأولى وإعادة الإرسال من الطابور بيحملوا نفس القيمة. من غير كده كان
    // تحويل ١٠,٠٠٠ + timeout بيتنفّذ مرتين: الدرج ‎-٢٠,٠٠٠ والبنك ‎+٢٠,٠٠٠
    // و٤ سندات بدل ٢.
    final transferGid = const Uuid().v7();
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'safe_transfers',
      operation: 'insert',
      payload: safeTransferPayload(
        fromSafeId: fromSafeId,
        toSafeId: toSafeId,
        amount: amount,
        userId: userId,
        description: description,
        globalId: transferGid,
      ),
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.submitSafeTransfer(
        fromSafeId: fromSafeId,
        toSafeId: toSafeId,
        amount: amount,
        userId: userId,
        description: description,
        globalId: transferGid,
      ),
    );
  }

  static Future<bool> submitSetDefaultSafe({required int safeId}) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing set default safe to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'safes',
      operation: 'update',
      payload: {'id': safeId, 'isDefault': true},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitSetDefaultSafe(safeId: safeId, idempotencyKey: reqIdemKey),
    );
  }

  // ── Stock Transfers ───────────────────────────────────────────────────────

  static Future<bool> submitStockTransfer({
    required int fromWarehouseId,
    required int toWarehouseId,
    required List<Map<String, dynamic>> items,
    int? userId,
    String? notes,
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing stock transfer to server');
    final payload = {
      'fromWarehouseId': fromWarehouseId,
      'toWarehouseId': toWarehouseId,
      'items': items,
      'userId': userId,
      'notes': notes,
      // Spec 129 F4 — globalId threaded so server dedups against mirror's
      // local bond row identity. No-op if caller didn't supply one.
      if (globalId != null && globalId.isNotEmpty) 'globalId': globalId,
    };
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'stock_transfers',
      operation: 'insert',
      payload: payload,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.submitStockTransfer(
        fromWarehouseId: fromWarehouseId,
        toWarehouseId: toWarehouseId,
        items: items,
        userId: userId,
        notes: notes,
        globalId: globalId,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  // ── Purchase Auto-Push ────────────────────────────────────────────────────

  static Future<bool> submitPurchase({
    required int supplierId,
    required int warehouseId,
    required List<Map<String, dynamic>> items,
    required double paid,
    String paymentMethod = 'cash',
    String? supplierInvoiceNumber,
    String? notes,
    int? costCenterId,
    int? branchId,
    int? safeId,
    String? globalId,
    int? userId,
    String? createdByUsername,
    // ح-1 (2026-07-25): invoice-level discount. Omitting it made the server
    // store the GROSS total for a discounted client invoice.
    double discount = 0,
    // المرحلة ٨ — لقطةُ العملة ووسمُ الاستيراد.
    int? currencyId,
    double? exchangeRate,
    ImportDocumentFields? importDetails,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase to server');
    final supplierGlobalId =
        await ClientWriteInterceptor._lookupPartyGlobalId(supplierId);
    final supplierName =
        await ClientWriteInterceptor._lookupPartyName(supplierId);
    final data = {
      if (globalId != null && globalId.isNotEmpty) 'globalId': globalId,
      'supplierId': supplierId,
      'supplierGlobalId': ?supplierGlobalId,
      'supplierName': ?supplierName,
      'warehouseId': warehouseId,
      'branchId': ?branchId,
      'items': items,
      'paid': paid,
      'discount': discount,
      'paymentMethod': paymentMethod,
      'supplierInvoiceNumber': supplierInvoiceNumber,
      'notes': notes,
      'costCenterId': ?costCenterId,
      'safeId': ?safeId,
      'userId': ?userId,
      if (createdByUsername != null && createdByUsername.isNotEmpty)
        'createdByUsername': createdByUsername,
      // 🔴 **ولقطةُ العملة تسافر مع الفاتورة لا بعدَها.** الخادمُ هو مَن
      //    يُنشئ الصفَّ المعتمَد، وسحبُ الدلتا يستبدل صفَّ العميل به. فعملةٌ
      //    تُكتَب محلّيّاً ولا تصل الخادمَ **تُمحى عند أوّل سحب**، فتُقرأ
      //    فاتورةُ الدولار على أنّها محلّيّةٌ ولا أثرَ يقول إنّها لم تكن.
      'currencyId': ?currencyId,
      'exchangeRate': ?exchangeRate,
    };
    if (importDetails != null) {
      // ⚠️ **ورقمُ وكيلِ التخليص لا يسافر — معرِّفُه العالميُّ يسافر.**
      //    أرقامُ العميل والخادم تتباعد بالتصميم، فرقمٌ محلّيٌّ قد يُطابِق
      //    طرفاً آخرَ تماماً على الخادم فيُنسَب التخليصُ إلى مورّدٍ لا
      //    علاقةَ له. و`null` هنا ليس إهمالاً: طرفٌ لم يُزامَن بعدُ لا
      //    معرِّفَ عالميَّ له، والخادمُ ينشئ بديلاً باسمه بدل أن يخمّن.
      data['importDetails'] = importDocumentToJson(importDetails);
      final agentId = importDetails.clearingAgentPartyId;
      if (agentId != null) {
        data['clearingAgentGlobalId'] =
            await ClientWriteInterceptor._lookupPartyGlobalId(agentId);
        data['clearingAgentName'] =
            await ClientWriteInterceptor._lookupPartyName(agentId);
      }
    }
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(data);
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchases',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.createPurchase(data),
    );
  }

  static Future<bool> submitPurchaseReturn(Map<String, dynamic> returnData) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase return to server');
    // Stamp globalId for idempotency: if the network times out after the server
    // processes the request but before we get the response, the outbox replay
    // will use the same globalId so the server can detect the duplicate.
    if (!returnData.containsKey('globalId') ||
        (returnData['globalId'] as String?)?.isEmpty != false) {
      returnData = {...returnData, 'globalId': const Uuid().v7()};
    }
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(returnData);
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchase_returns',
      operation: 'insert',
      payload: returnData,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitPurchaseReturn(returnData, idempotencyKey: reqIdemKey),
    );
  }

  /// Feature 015 — purchase-return edit (atomic reverse + recreate on the
  /// server). Same payload shape as [submitPurchaseReturn]; the server's
  /// /api/purchases/return/edit handler reads the current return state
  /// from its own ledger and replaces it with the new items.
  static Future<bool> submitPurchaseReturnEdit(Map<String, dynamic> editData) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase return edit to server');
    if (!editData.containsKey('globalId') ||
        (editData['globalId'] as String?)?.isEmpty != false) {
      editData = {...editData, 'globalId': const Uuid().v7()};
    }
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(editData);
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchase_returns',
      operation: 'edit',
      payload: editData,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitPurchaseReturnEdit(editData, idempotencyKey: reqIdemKey),
    );
  }

  /// PR-2 (pre-deploy batch B6, R4/R8/R9) — submit a purchase-invoice void
  /// to the server. Mirrors [submitPurchaseReturn]'s shape exactly: the
  /// server (SSoT) performs the authoritative stock/AP/treasury/JE
  /// reversal; the caller (purchases_repository_impl.dart) only writes a
  /// light local status marker, never the full reversal.
  ///
  /// [globalId] is the SAME deterministic id the caller derived for the
  /// local reversal-JE globalId (see PurchasesRepositoryImpl._voidOrDelete);
  /// threading it here lets the server's reversal JE converge on the same
  /// identity instead of minting its own (R9).
  static Future<bool> submitVoidPurchase({
    required int purchaseId,
    String? purchaseGlobalId,
    String? invoiceNumber,
    String? reason,
    required String globalId,
    int? userId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase void to server');
    final payload = <String, dynamic>{
      'purchaseId': purchaseId,
      if (purchaseGlobalId != null && purchaseGlobalId.isNotEmpty)
        'purchaseGlobalId': purchaseGlobalId,
      'invoiceNumber': invoiceNumber,
      'reason': reason,
      'globalId': globalId,
      'userId': ?userId,
    };
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchase_invoices',
      operation: 'void',
      payload: payload,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitVoidPurchase(payload, idempotencyKey: reqIdemKey),
    );
  }

  /// Spec 151 C-03 — client/mirror purchase-PAYMENT submit. Mirrors
  /// [submitVoidPurchase]: the server (SSoT) resolves the invoice
  /// (globalId → invoiceNumber → id), advances invoice.paid server-side and
  /// posts the authoritative Dr AP / Cr cash JE + safe move; the caller only
  /// caches a light local paid marker (never the money/GL). [globalId] is the
  /// deterministic PER-EVENT id the caller minted for the payment's
  /// safe_transaction — threading it lets the server dedup a replay/re-submit
  /// on the same id, so an additive payment is never applied twice (R9).
  static Future<bool> submitPurchasePayment({
    required int purchaseId,
    String? purchaseGlobalId,
    String? invoiceNumber,
    required double amount,
    required String globalId,
    int? userId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase payment to server');
    final payload = <String, dynamic>{
      'purchaseId': purchaseId,
      if (purchaseGlobalId != null && purchaseGlobalId.isNotEmpty)
        'purchaseGlobalId': purchaseGlobalId,
      'invoiceNumber': invoiceNumber,
      'amount': amount,
      'globalId': globalId,
      'userId': ?userId,
    };
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchase_invoices',
      operation: 'payment',
      payload: payload,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitPurchasePayment(payload, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> submitInventoryBond(Map<String, dynamic> bondData) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing inventory bond to server');
    // Spec 109 — thread productGlobalId per item so the server resolves by
    // UUID when client/server product ids drift.
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(bondData);
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'inventory_bonds',
      operation: 'insert',
      payload: bondData,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitInventoryBond(bondData, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> closeSafe(int safeId, {int? userId, double? cashAmount, double? bankAmount, String? notes, String? closeEventGid}) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing closeSafe to server (safeId=$safeId)');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'safes',
      operation: 'close',
      // Spec 135: thread the amounts so the server posts the IDENTICAL closing
      // JE (previously it received only safeId → routed everything to the
      // same-type account, diverging from the client's split), and carry the
      // closeEventGid so an offline replay re-sends the SAME deterministic id.
      payload: {
        'safeId': safeId,
        'userId': userId,
        'cashAmount': cashAmount,
        'bankAmount': bankAmount,
        'notes': notes,
        'closeEventGid': closeEventGid,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.closeSafe(
        safeId,
        userId: userId,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        notes: notes,
        closeEventGid: closeEventGid,
        idempotencyKey: reqIdemKey,
      ),
    );
  }
}
