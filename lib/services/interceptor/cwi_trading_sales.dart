part of '../client_write_interceptor.dart';


// ═══════════════════════════════════════════════════════════════════════════
// Trading module — Sales · Inventory · Commercial Papers · Safe Operations
//                  Stock Transfers · Purchase Auto-Push
//
// Part of the ClientWriteInterceptor library.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiTradingSales {
  _CwiTradingSales._();

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

    // نطاقُ الاستبدال — اقرأ نظيرَه في `submitSalesReturn` تحت.
    final exchangeCollector = ClientWriteInterceptor.activeExchangeCollector;
    if (exchangeCollector != null) {
      exchangeCollector.setSale(saleData);
      return null;
    }
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

    // نطاقُ الاستبدال: تُلتقَط الحمولةُ **بعد إثرائها** ولا تُرسَل وحدَها —
    // يرسلها `submitExchange` مع شقِّ البيع في حمولةٍ واحدة. والوسمُ المختلط
    // يمرّ من هنا مرّتين، فتُجمَع الحمولتان لا تُستبدل إحداهما بالأخرى.
    final exchangeCollector = ClientWriteInterceptor.activeExchangeCollector;
    if (exchangeCollector != null) {
      exchangeCollector.addReturnLeg(returnData);
      return null;
    }
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'sales_returns',
      operation: 'insert',
      payload: returnData,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitSalesReturn(returnData, idempotencyKey: reqIdemKey),
    );
  }

  /// يرسل الاستبدالَ **حمولةً واحدة** يفكّها الخادمُ إلى مستندَين في معاملةٍ
  /// واحدة (‏قرارُ المالك ٥).
  ///
  /// و`tableName: 'sales_exchanges'` جدولٌ **منطقيٌّ** لا صفَّ له في القاعدة —
  /// هو مفتاحُ التوزيع في طابور `offline_sync_worker`. ونوعٌ بلا فرعٍ هناك
  /// يسقط صامتاً من الطابور (وقع مع `void` من قبل)، فالفرعُ مضافٌ معه.
  static Future<int?> submitExchange(Map<String, dynamic> exchangeData) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing exchange to server '
        '(key=${exchangeData['exchangeKey']})');
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'sales_exchanges',
      operation: 'insert',
      payload: exchangeData,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitExchange(exchangeData, idempotencyKey: reqIdemKey),
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
}
