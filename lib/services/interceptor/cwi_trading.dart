part of '../client_write_interceptor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Trading module — Sales · Inventory · Commercial Papers · Safe Operations
//                  Stock Transfers · Purchase Auto-Push
//
// Part of the ClientWriteInterceptor library.
// ═══════════════════════════════════════════════════════════════════════════

/// شكل الـpayload المخزّن في الطابور لتحويل بين الخزائن.
///
/// ── ليه دالة منفصلة ─────────────────────────────────────────────────────────
/// الـ`globalId` لازم يكون **جزء من الـpayload** مش يتولّد وقت الإرسال: إعادة
/// الإرسال من الطابور بتقرا نفس الـpayload المخزّن، فلو الـid بيتولّد في كل
/// محاولة كانت كل واحدة هتاخد قيمة جديدة والـdedup بلا معنى. ده جوهر الفرق
/// بين «مفتاح idempotency» و«هوية العملية».
@visibleForTesting
Map<String, dynamic> safeTransferPayload({
  required int fromSafeId,
  required int toSafeId,
  required double amount,
  int? userId,
  String? description,
  required String globalId,
}) =>
    {
      'fromSafeId': fromSafeId,
      'toSafeId': toSafeId,
      'amount': amount,
      'userId': userId,
      'description': description,
      'globalId': globalId,
    };

class _CwiTrading {
  _CwiTrading._();

  // ── Sales ─────────────────────────────────────────────────────────────────

  static Future<int?> submitSale(Map<String, dynamic> saleData) async {
    if (!SyncInterceptor.isClientMode) {
      debugPrint('[ClientInterceptor] ⚠️ submitSale SKIPPED: isClientMode=false '
          '(instance=${SyncInterceptor.instance != null})');
      // Also surface this in the persistent diagnostic log — the user
      // reported invoices saving locally but never reaching the server,
      // and a release-mode debugPrint is invisible. If isClientMode is
      // false here, the sale will NEVER push to the server (no outbox,
      // no retry); the operator needs to see why.
      unawaited(DiagnosticLogger.log('SALE-SYNC',
          '⚠ submitSale SKIPPED — SyncInterceptor.isClientMode=false '
          '(invoice=${saleData['invoiceNumber']}, '
          'instance=${SyncInterceptor.instance != null})'));
      return null;
    }
    debugPrint('[ClientInterceptor] Routing sale to server '
        '(branchId=${saleData['branchId']}, wh=${saleData['warehouseId']})');

    if (!saleData.containsKey('customerGlobalId')) {
      final cid = saleData['customerId'];
      final customerGlobalId = await ClientWriteInterceptor._lookupPartyGlobalId(
        cid is int ? cid : (cid is num ? cid.toInt() : null),
      );
      if (customerGlobalId != null) saleData['customerGlobalId'] = customerGlobalId;
    }
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(saleData);

    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'sales',
      operation: 'insert',
      payload: saleData,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitSale(saleData, idempotencyKey: reqIdemKey),
    );
  }

  static Future<int?> submitHeldOrder(Map<String, dynamic> orderData) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing held order to server');
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(orderData);
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'held_orders',
      operation: 'insert',
      payload: orderData,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitHeldOrder(orderData, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deleteHeldOrder(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing held order delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'held_orders',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.deleteHeldOrder(id);
      },
    );
  }

  static Future<int?> submitSalesReturn(Map<String, dynamic> returnData) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing sales return to server');

    if (!returnData.containsKey('customerGlobalId')) {
      final cid = returnData['customerId'];
      final customerGlobalId = await ClientWriteInterceptor._lookupPartyGlobalId(
        cid is int ? cid : (cid is num ? cid.toInt() : null),
      );
      if (customerGlobalId != null) returnData['customerGlobalId'] = customerGlobalId;
    }
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(returnData);

    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'sales_returns',
      operation: 'insert',
      payload: returnData,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitSalesReturn(returnData, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deleteSalesInvoice(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing sales invoice delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'sales',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.deleteSalesInvoice(id);
      },
    );
  }

  static Future<bool> updateSalesInvoice(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing sales invoice update to server');
    if (!data.containsKey('customerGlobalId') && data.containsKey('customerId')) {
      final cid = data['customerId'];
      final customerGlobalId = await ClientWriteInterceptor._lookupPartyGlobalId(
        cid is int ? cid : (cid is num ? cid.toInt() : null),
      );
      if (customerGlobalId != null) {
        data = {...data, 'customerGlobalId': customerGlobalId};
      }
    }
    final payload = {'id': id, ...data};
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    if (payload['items'] is List) {
      data = {...data, 'items': payload['items']};
    }
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'sales',
      operation: 'update',
      payload: payload,
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .updateSalesInvoice(id, data, idempotencyKey: reqIdemKey);
      },
    );
  }

  /// C-02 (Spec 151, R4/R9) — submit a sales-invoice void to the server.
  /// Mirrors [submitVoidPurchase] exactly: the server (SSoT) resolves the
  /// invoice by globalId → invoiceNumber → id and performs the authoritative
  /// stock/treasury/JE reversal; the caller (sales_repository_impl.dart) only
  /// writes a light local status marker, never the full reversal.
  ///
  /// [globalId] is the SAME deterministic id the caller derived for the local
  /// reversal-JE globalId; threading it here lets the server's reversal JE
  /// converge on the same identity instead of minting its own (R9). The outbox
  /// row uses tableName 'sales' so an offline replay hits the `case 'sales'`
  /// / operation 'void' branch in OfflineSyncWorker.
  static Future<bool> submitVoidSalesInvoice({
    required int salesId,
    String? salesGlobalId,
    String? invoiceNumber,
    String? reason,
    required String globalId,
    int? userId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing sales void to server');
    final payload = <String, dynamic>{
      'salesId': salesId,
      if (salesGlobalId != null && salesGlobalId.isNotEmpty)
        'salesGlobalId': salesGlobalId,
      'invoiceNumber': invoiceNumber,
      'reason': reason,
      'globalId': globalId,
      'userId': ?userId,
    };
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'sales',
      operation: 'void',
      payload: payload,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitVoidSale(payload, idempotencyKey: reqIdemKey),
    );
  }

  /// Spec 151 C-05 — client/mirror customer-COLLECTION submit. TWIN of
  /// [submitVoidSalesInvoice] / [_CwiTrading.submitPurchasePayment]: the server
  /// (SSoT) resolves the invoice (globalId → invoiceNumber → id), advances
  /// invoice.paid server-side and posts the authoritative Dr Safe / Cr Customer
  /// receipt + balanced JE + safe move; the caller only caches a light local
  /// paid marker (never the money/GL). [globalId] is the deterministic PER-EVENT
  /// id the caller minted for the collection's safe_transaction — threading it
  /// lets the server dedup a replay/re-submit on the same id, so an additive
  /// collection is never applied twice (R9). [amount] is the DELTA collected
  /// this event (the repository computed newPaid - invoice.paid). The outbox row
  /// uses tableName 'sales' so an offline replay hits the `case 'sales'` /
  /// operation 'payment' branch in OfflineSyncWorker.
  static Future<bool> submitSalesPayment({
    required int salesId,
    String? salesGlobalId,
    String? invoiceNumber,
    required double amount,
    required String globalId,
    int? userId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing sales payment to server');
    final payload = <String, dynamic>{
      'salesId': salesId,
      if (salesGlobalId != null && salesGlobalId.isNotEmpty)
        'salesGlobalId': salesGlobalId,
      'invoiceNumber': invoiceNumber,
      'amount': amount,
      'globalId': globalId,
      'userId': ?userId,
    };
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'sales',
      operation: 'payment',
      payload: payload,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitSalesPayment(payload, idempotencyKey: reqIdemKey),
    );
  }

  // ── Inventory ─────────────────────────────────────────────────────────────

  static Future<bool> adjustStock({
    required int productId,
    required int warehouseId,
    required double quantity,
    String? type,
    String? notes,
    String? adjustmentEventGid, // Spec 135 BUG-A: per-event gid (caller-minted)
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing stock adjustment to server');

    final db = ClientWriteInterceptor._db;
    String? productGlobalId;
    if (db != null) {
      try {
        final p = await (db.select(db.products)
              ..where((c) => c.id.equals(productId))
              ..limit(1))
            .getSingleOrNull();
        if (p != null) {
          productGlobalId = p.globalId;
          if (productGlobalId == null || productGlobalId.isEmpty) {
            productGlobalId = const Uuid().v7();
            try {
              await (db.update(db.products)
                    ..where((c) => c.id.equals(productId)))
                  .write(ProductsCompanion(globalId: Value(productGlobalId)));
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint(
            '[ClientInterceptor] product lookup for adjustStock failed (non-fatal): $e');
      }
    }

    // Spec 136 ISS-26 (#2 hardening / Spec 132) — thread the warehouse globalId
    // so the server resolves to its OWN warehouse id even when the mirror/client
    // local warehouse ids diverge. Without it, the raw warehouseId could miss on
    // the server ("Strict Mapping Violation") or land the stock movement in the
    // wrong warehouse — so opening-stock/adjustments wouldn't show on the branch.
    String? warehouseGlobalId;
    if (db != null) {
      try {
        final w = await (db.select(db.warehouses)
              ..where((c) => c.id.equals(warehouseId))
              ..limit(1))
            .getSingleOrNull();
        warehouseGlobalId = w?.globalId;
      } catch (e) {
        debugPrint(
            '[ClientInterceptor] warehouse lookup for adjustStock failed (non-fatal): $e');
      }
    }

    final payload = {
      'productId': productId,
      'productGlobalId': productGlobalId,
      'warehouseId': warehouseId,
      'warehouseGlobalId': warehouseGlobalId,
      'quantity': quantity,
      'type': type,
      'notes': notes,
      // Spec 135 BUG-A: carry the event gid in the outbox payload too, so an
      // offline replay re-sends the SAME id (idempotent on the server).
      'adjustmentEventGid': adjustmentEventGid,
    };
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'inventory',
      operation: 'adjust',
      payload: payload,
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.adjustStock(
          productId: productId,
          warehouseId: warehouseId,
          quantity: quantity,
          type: type,
          notes: notes,
          productGlobalId: productGlobalId,
          warehouseGlobalId: warehouseGlobalId,
          adjustmentEventGid: adjustmentEventGid,
          idempotencyKey: reqIdemKey,
        );
      },
    );
  }

  /// One-shot reconciliation of local `inventory_balances` → server.
  /// Runs on client startup. Fails soft — never throws, never blocks startup.
  static Future<int> reconcileOpeningStocks() async {
    if (!SyncInterceptor.isClientMode) return 0;
    final db = ClientWriteInterceptor._db;
    if (db == null) return 0;

    try {
      final allBalances = await db.select(db.inventoryBalances).get();
      final balances = allBalances.where((b) => b.quantity > 0).toList();
      if (balances.isEmpty) return 0;

      debugPrint('[Reconcile] pushing ${balances.length} local inventory '
          'balance(s) to server as opening_stock (server will skip duplicates)');

      int pushed = 0;
      for (final bal in balances) {
        try {
          await adjustStock(
            productId: bal.productId,
            warehouseId: bal.warehouseId,
            quantity: bal.quantity,
            type: 'opening_stock',
            notes: 'Startup reconcile — materialise missing server balance',
          );
          pushed++;
        } catch (e) {
          debugPrint('[Reconcile] balance push failed for product=${bal.productId} '
              'warehouse=${bal.warehouseId}: $e');
        }
      }
      debugPrint('[Reconcile] pushed $pushed / ${balances.length} balance(s)');
      return pushed;
    } catch (e) {
      debugPrint('[Reconcile] reconcileOpeningStocks failed (non-fatal): $e');
      return 0;
    }
  }

  // ── Commercial Papers ─────────────────────────────────────────────────────

  static Future<int?> createCommercialPaper({
    required String paperNumber,
    required String type,
    required String direction,
    required int partyId,
    required double amount,
    required DateTime issueDate,
    required DateTime dueDate,
    String? bankName,
    int? safeId,
    String? accountNumber,
    String? notes,
    // Cluster 030 / Bug D — caller mints the globalId once and passes
    // it to BOTH this interceptor and the local DAO so mirror + server
    // converge on the same identity. Without this, the next status
    // update from the mirror failed with "Commercial paper not found"
    // because the server's auto-minted globalId didn't match the
    // mirror's local one.
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing commercial paper create to server');

    // Feature 044 — thread `partyGlobalId` + `partyName` so the server
    // resolves the party via `resolvePartyId`. Field log:
    //   commercial_papers_party_id_fkey: Key (party_id)=(1000000006) is not
    //   present in table "parties"
    // The high autoincrement offset on the mirror's local `parties.id`
    // does not exist on the server. globalId is the cross-instance-stable
    // identifier; name is the fallback when the party row never reached
    // the server via DeltaPush yet.
    final partyGlobalId =
        await ClientWriteInterceptor._lookupPartyGlobalId(partyId);
    final partyName = await ClientWriteInterceptor._lookupPartyName(partyId);

    final payload = <String, dynamic>{
      'paperNumber': paperNumber,
      'type': type,
      'direction': direction,
      'partyId': partyId,
      'partyGlobalId': ?partyGlobalId,
      'partyName': ?partyName,
      'amount': amount,
      'issueDate': issueDate.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'bankName': bankName,
      'safeId': safeId,
      'accountNumber': accountNumber,
      'notes': notes,
      'globalId': globalId,
    };
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'commercial_papers',
      operation: 'insert',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createCommercialPaper(payload),
    );
  }

  static Future<bool> updateCommercialPaperStatus(
    int id,
    String status, {
    int? changedBy,
    String? notes,
    // Feature 048 (v130) — user-chosen contra leg for the JE. Resolved
    // to the server's account id via globalId remap inside the handler
    // (same pattern as partyGlobalId in Feature 044) so the JE posts
    // on the same account the cashier saw in the dropdown.
    int? counterAccountId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing paper status update to server '
        '(counterAccountId=${counterAccountId ?? "null"})');
    // Feature 014 / Issue 3 — the client's `id` here is the LOCAL row id,
    // which does NOT generally match the server's auto-increment.
    // Previously we sent the local id and the server returned 404
    // ("Commercial paper not found: 2"). Fix: resolve the local row's
    // globalId and forward it; the server (api_data_handler.dart's
    // putCommercialPaperStatus) now accepts an optional `globalId` body
    // field that takes precedence over the path id when resolving the
    // target row.
    String? globalId;
    // Feature 042 (Bug 5) — also resolve the changing user's USERNAME on
    // the client so the server can remap the local user_id to its own
    // user table. Without this the server's `paper_status_history`
    // INSERT hit FK violation 23503 ("Key (changed_by)=(1) is not
    // present in table users") on every status change from the mirror,
    // because client and server hold independently-numbered `users.id`
    // sequences. Username is the cross-instance-stable identifier.
    String? changedByUsername;
    // Feature 048 — also resolve the counter account's globalId so the
    // server can remap to its own accounts.id even when client/server
    // chart-of-accounts auto-increments diverge (same divergence
    // pattern that party-id / user-id remap handles).
    String? counterAccountGlobalId;
    try {
      final db = ClientWriteInterceptor._db;
      if (db != null) {
        final row = await (db.select(db.commercialPapers)
              ..where((p) => p.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
        globalId = row?.globalId;

        if (changedBy != null) {
          final u = await (db.select(db.users)
                ..where((x) => x.id.equals(changedBy))
                ..limit(1))
              .getSingleOrNull();
          changedByUsername = u?.username;
        }

        if (counterAccountId != null) {
          final acct = await (db.select(db.accounts)
                ..where((a) => a.id.equals(counterAccountId))
                ..limit(1))
              .getSingleOrNull();
          counterAccountGlobalId = acct?.globalId;
        }
      }
    } catch (e) {
      debugPrint('[ClientInterceptor] paper globalId/username/account '
          'lookup failed: $e');
    }
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'update_status',
      payload: {
        'id': id,
        'globalId': globalId,
        'status': status,
        'changedBy': changedBy,
        'changedByUsername': changedByUsername,
        'notes': notes,
        'counterAccountId': counterAccountId,
        if (counterAccountGlobalId != null && counterAccountGlobalId.isNotEmpty)
          'counterAccountGlobalId': counterAccountGlobalId,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .updateCommercialPaperStatus(id,
              globalId: globalId,
              status: status,
              changedBy: changedBy,
              changedByUsername: changedByUsername,
              notes: notes,
              counterAccountId: counterAccountId,
              counterAccountGlobalId: counterAccountGlobalId),
    );
  }

  static Future<bool> renewCommercialPaper(
    int id,
    DateTime newDueDate, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing paper renew to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'renew',
      payload: {
        'id': id,
        'newDueDate': newDueDate.toIso8601String(),
        'changedBy': changedBy,
        'notes': notes,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.renewCommercialPaper(
        id,
        newDueDate: newDueDate.toIso8601String(),
        changedBy: changedBy,
        notes: notes,
      ),
    );
  }

  static Future<bool> partialCollectPaper(
    int id,
    double amount, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing partial collection to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'partial_collect',
      payload: {'id': id, 'amount': amount, 'changedBy': changedBy, 'notes': notes},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.partialCollectPaper(
        id, amount: amount, changedBy: changedBy, notes: notes),
    );
  }

  static Future<bool> endorseCommercialPaper(
    int id,
    int toPartyId, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing paper endorse to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'endorse',
      payload: {
        'id': id,
        'status': 'endorsed',
        'endorsedToPartyId': toPartyId,
        'changedBy': changedBy,
        'notes': notes,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.updateCommercialPaperStatus(
        id,
        status: 'endorsed',
        changedBy: changedBy,
        notes: notes,
        endorsedToPartyId: toPartyId,
      ),
    );
  }

  static Future<bool> depositPaperForCollection(
    int id,
    int bankSafeId, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing deposit for collection to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'deposit',
      payload: {'id': id, 'bankSafeId': bankSafeId, 'changedBy': changedBy, 'notes': notes},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.depositPaperForCollection(
        id, bankSafeId: bankSafeId, changedBy: changedBy, notes: notes),
    );
  }

  static Future<bool> reissueCommercialPaper(
    int id,
    int newPartyId, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing paper reissue to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'reissue',
      payload: {
        'id': id,
        'newPartyId': newPartyId,
        'changedBy': changedBy,
        'notes': notes,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.reissuePaper(
        id, newPartyId: newPartyId, changedBy: changedBy, notes: notes),
    );
  }

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
    };
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
