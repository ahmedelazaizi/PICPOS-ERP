// ServerProxy - sales, purchases, inventory and trading-document writes.
part of '../server_proxy.dart';

/// Sales, purchases, inventory, stock transfers, orders/quotations, price lists,
/// landed cost, manufacturing and bookings writes of [ServerProxy].
extension ServerProxyTradingWrites on ServerProxy {
  // ═══════════════════════════════════════════════════════════════
  // Sales
  // ═══════════════════════════════════════════════════════════════

  // PHASE-3 FIX: Critical financial write paths use _postWithRetry for resilience
  Future<int?> submitSale(Map<String, dynamic> saleData, {String? idempotencyKey}) async {
    final result = await _postWithRetry('/api/sales', saleData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<int?> submitSalesReturn(Map<String, dynamic> returnData, {String? idempotencyKey}) async {
    final result = await post('/api/sales/return', returnData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// الاستبدال — حمولةٌ واحدةٌ يفكّها الخادمُ إلى مستندَين في معاملةٍ واحدة.
  ///
  /// لا مسارَين مرتبطَين: مسارٌ واحدٌ يعني أن نصفَ الاستبدال لا يصل وحدَه،
  /// فلا نافذةَ يبقى فيها العميلُ دائناً ببضاعةٍ أخذها.
  Future<int?> submitExchange(Map<String, dynamic> exchangeData,
      {String? idempotencyKey}) async {
    final result = await post('/api/sales/exchange', exchangeData,
        idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<int?> submitHeldOrder(Map<String, dynamic> orderData, {String? idempotencyKey}) async {
    final result = await post('/api/sales/held', orderData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// FIX 3.4: idempotencyKey added so outbox replay prevents double-deletes
  Future<void> deleteHeldOrder(int id, {String? idempotencyKey}) async {
    await delete('/api/sales/held/$id', idempotencyKey: idempotencyKey);
  }

  /// FIX 3.4: idempotencyKey added so outbox replay prevents double-deletes
  Future<void> deleteSalesInvoice(int id, {String? idempotencyKey}) async {
    await delete('/api/sales/$id', idempotencyKey: idempotencyKey);
  }

  Future<void> updateSalesInvoice(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/sales/$id', data, idempotencyKey: idempotencyKey);
  }

  /// C-02 (Spec 151) — submit a sales-invoice void to the server. The server
  /// resolves the invoice (globalId → invoiceNumber → id) and performs the
  /// authoritative stock/treasury/JE reversal; the client only caches a light
  /// local marker. Mirrors [submitVoidPurchase]. See
  /// `ApiSalesHandler.postVoidSale`.
  Future<int?> submitVoidSale(Map<String, dynamic> voidData, {String? idempotencyKey}) async {
    final result = await post('/api/sales/void', voidData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// Spec 151 C-05 — submit a customer COLLECTION to the server. The server
  /// resolves the invoice (globalId → invoiceNumber → id), advances
  /// invoice.paid and posts the authoritative Dr Safe / Cr Customer receipt + JE
  /// + safe move; the client caches only a light local paid marker. The
  /// collection is additive, so the server dedups on the incoming globalId. See
  /// `ApiSalesHandler.postSalesPayment`.
  Future<int?> submitSalesPayment(Map<String, dynamic> paymentData, {String? idempotencyKey}) async {
    final result = await post('/api/sales/payment', paymentData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  // ═══════════════════════════════════════════════════════════════
  // Purchases
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPurchase(Map<String, dynamic> purchaseData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases', purchaseData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<void> updatePurchase(int id, Map<String, dynamic> purchaseData, {String? idempotencyKey}) async {
    await put('/api/purchases/$id', purchaseData, idempotencyKey: idempotencyKey);
  }

  Future<void> deletePurchase(int id, {String? idempotencyKey}) async {
    await delete('/api/purchases/$id', idempotencyKey: idempotencyKey);
  }

  Future<int?> submitPurchaseReturn(Map<String, dynamic> returnData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases/return', returnData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// Feature 015 — submit a purchase-return edit (atomic reverse + recreate)
  /// to the server. Same payload shape as [submitPurchaseReturn] plus the
  /// caller's globalId for idempotency on retry.
  Future<int?> submitPurchaseReturnEdit(Map<String, dynamic> editData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases/return/edit', editData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// PR-2 (pre-deploy batch B6) — submit a purchase-invoice void to the
  /// server. The server resolves the invoice (globalId → invoiceNumber →
  /// id) and performs the authoritative stock/AP/treasury/JE reversal;
  /// the client only caches a light local marker. See
  /// `ApiPurchaseHandler.postVoidPurchase`.
  Future<int?> submitVoidPurchase(Map<String, dynamic> voidData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases/void', voidData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// Spec 151 C-03 — submit a purchase-invoice PAYMENT to the server. The
  /// server resolves the invoice (globalId → invoiceNumber → id), advances
  /// invoice.paid and posts the authoritative Dr AP / Cr cash JE + safe move;
  /// the client caches only a light local paid marker. The payment is additive,
  /// so the server dedups on the incoming globalId. See
  /// `ApiPurchaseHandler.postPurchasePayment`.
  Future<int?> submitPurchasePayment(Map<String, dynamic> paymentData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases/payment', paymentData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  // ═══════════════════════════════════════════════════════════════
  // Inventory
  // ═══════════════════════════════════════════════════════════════

  Future<void> adjustStock({
    required int productId,
    required int warehouseId,
    required double quantity,
    String? type,
    String? notes,
    String? productGlobalId,
    String? warehouseGlobalId, // Spec 136 ISS-26 #2 — robust warehouse routing
    String? adjustmentEventGid, // Spec 135 BUG-A
    String? idempotencyKey,
  }) async {
    await post('/api/inventory/adjust', {
      'productId': productId,
      'productGlobalId': productGlobalId,
      'warehouseId': warehouseId,
      if (warehouseGlobalId != null && warehouseGlobalId.isNotEmpty)
        'warehouseGlobalId': warehouseGlobalId,
      'quantity': quantity,
      'type': type,
      'notes': notes,
      if (adjustmentEventGid != null && adjustmentEventGid.isNotEmpty)
        'adjustmentEventGid': adjustmentEventGid,
    }, idempotencyKey: idempotencyKey);
  }

  Future<int?> submitInventoryBond(Map<String, dynamic> bondData, {String? idempotencyKey}) async {
    final result = await post('/api/inventory/bond', bondData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  // ═══════════════════════════════════════════════════════════════
  // Landed Cost — تطبيقُ ورقة تحميل (Client → Server) · v166
  // ═══════════════════════════════════════════════════════════════

  /// يُرسل **المستندَ كاملاً** (‏الورقةُ وبنودُها وتوزيعاتُها) ليطبّقه
  /// الخادمُ بنفسه.
  ///
  /// والمفاتيحُ الخارجيّةُ تُمرَّر بمعرّفاتٍ **عالميّة** لا بأرقامٍ محلّيّة:
  /// أرقامُ العميل والخادم تتباعد بالتصميم (‏`DeltaPull` يُبقي الرقمَ
  /// المحلّيَّ ويسجّل خريطةً)، فتمريرُ رقمٍ محلّيٍّ قد يعيد بناءَ مستندٍ
  /// **آخر** على الخادم — وهو عينُ العطب الذي أُلغيت لأجله بوّابةُ تعديل
  /// المشتريات (‏`purchases_repository_impl.dart` ح-٦).
  Future<void> submitLandedCostApply(
    Map<String, dynamic> document, {
    String? idempotencyKey,
  }) async {
    await post('/api/landed-costs/apply', document,
        idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Manufacturing (Client → Server) · v166
  // ═══════════════════════════════════════════════════════════════

  /// حدثٌ على أمرِ إنتاجٍ قائم: `start` · `complete` · `reverse` ·
  /// `add_cost`. الأمرُ يُدعى بهويّته العالميّة لا برقمه المحلّيّ.
  Future<void> submitManufacturingAction(
    Map<String, dynamic> request, {
    String? idempotencyKey,
  }) async {
    await post('/api/manufacturing/action', request,
        idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Bookings (Client → Server) · v167
  // ═══════════════════════════════════════════════════════════════

  /// إطفاءُ التزامِ عربونٍ على فاتورة. الحجزُ والفاتورةُ يُدعيان
  /// بهويّتهما العالميّة لا برقمهما المحلّيّ.
  Future<void> submitBookingDepositApplication(
    Map<String, dynamic> request, {
    String? idempotencyKey,
  }) async {
    await post('/api/bookings/apply-deposit', request,
        idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Stock Transfers (Client → Server)
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitStockTransfer({
    required int fromWarehouseId,
    required int toWarehouseId,
    required List<Map<String, dynamic>> items,
    int? userId,
    String? notes,
    String? globalId,
    String? idempotencyKey,
  }) async {
    await post('/api/inventory/transfer', {
      'fromWarehouseId': fromWarehouseId,
      'toWarehouseId': toWarehouseId,
      'items': items,
      'userId': userId,
      'notes': notes,
      // Spec 129 F4 — caller-minted UUIDv7. Server dedups against this.
      if (globalId != null && globalId.isNotEmpty) 'globalId': globalId,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Purchase Orders
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPurchaseOrder(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/purchase-orders', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updatePurchaseOrderStatus(
    int id,
    String status, {
    String? idempotencyKey,
  }) async {
    await put('/api/purchase-orders/$id/status', {'status': status},
        idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deletePurchaseOrder(int id, {String? idempotencyKey}) async {
    await delete('/api/purchase-orders/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Sales Orders
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createSalesOrder(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/sales-orders', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updateSalesOrderStatus(
    int id,
    String status, {
    String? idempotencyKey,
  }) async {
    await put('/api/sales-orders/$id/status', {'status': status},
        idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deleteSalesOrder(int id, {String? idempotencyKey}) async {
    await delete('/api/sales-orders/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Quotations
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createQuotation(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/quotations', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updateQuotationStatus(
    int id,
    String status, {
    int? convertedInvoiceId,
    String? idempotencyKey,
  }) async {
    await put('/api/quotations/$id/status', {
      'status': status,
      'convertedToInvoiceId': ?convertedInvoiceId,
    }, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> updateQuotation(
    int id,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await put('/api/quotations/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deleteQuotation(int id, {String? idempotencyKey}) async {
    await delete('/api/quotations/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Price Lists
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPriceList(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/price-lists', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updatePriceList(
    int id,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await put('/api/price-lists/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> setPriceListItem(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await post('/api/price-list-items', data, idempotencyKey: idempotencyKey);
    return true;
  }
}
