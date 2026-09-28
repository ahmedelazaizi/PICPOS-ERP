part of '../client_write_interceptor.dart';

// ignore_for_file: avoid_dynamic_calls

// ═══════════════════════════════════════════════════════════════════════════
// Sync module — SyncInterceptor interface implementations
//               Party Groups · Purchase Orders · Sales Orders
//               Quotations · Price Lists · Printers
//
// Part of the ClientWriteInterceptor library.
// All methods here back the @override stubs on ClientWriteInterceptor.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiSyncOrders {
  _CwiSyncOrders._();

  // ── Journal Entries ───────────────────────────────────────────────────────


  // ── Purchase Orders ───────────────────────────────────────────────────────

  static Future<int?> createPurchaseOrder(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing purchase order create to server');
    final payload = {...data, 'items': items};
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'purchase_orders',
      operation: 'insert',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createPurchaseOrder(payload, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updatePurchaseOrderStatus(int id, String status) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase order status update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchase_orders',
      operation: 'update',
      payload: {'id': id, 'status': status},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .updatePurchaseOrderStatus(id, status, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deletePurchaseOrder(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase order delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchase_orders',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deletePurchaseOrder(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Sales Orders ──────────────────────────────────────────────────────────

  static Future<int?> createSalesOrder(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing sales order create to server');
    final payload = {...data, 'items': items};
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'sales_orders',
      operation: 'insert',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createSalesOrder(payload, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updateSalesOrderStatus(int id, String status) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing sales order status update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'sales_orders',
      operation: 'update',
      payload: {'id': id, 'status': status},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .updateSalesOrderStatus(id, status, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deleteSalesOrder(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing sales order delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'sales_orders',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deleteSalesOrder(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Quotations ────────────────────────────────────────────────────────────

  static Future<int?> createQuotation(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing quotation create to server');
    final payload = {...data, 'items': items};
    if (!payload.containsKey('customerGlobalId')) {
      final cid = payload['customerId'];
      final customerGlobalId = await ClientWriteInterceptor._lookupPartyGlobalId(
        cid is int ? cid : (cid is num ? cid.toInt() : null),
      );
      if (customerGlobalId != null) payload['customerGlobalId'] = customerGlobalId;
    }
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'quotations',
      operation: 'insert',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createQuotation(payload, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updateQuotationStatus(
    int id,
    String status, {
    int? convertedInvoiceId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing quotation status update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'quotations',
      operation: 'update',
      payload: {
        'id': id,
        'status': status,
        'convertedToInvoiceId': ?convertedInvoiceId,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .updateQuotationStatus(id, status, convertedInvoiceId: convertedInvoiceId),
    );
  }

  static Future<bool> updateQuotation(
    int id,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing quotation full update to server');
    final payload = {...data, 'id': id, 'items': items};
    if (!payload.containsKey('customerGlobalId')) {
      final cid = payload['customerId'];
      final customerGlobalId = await ClientWriteInterceptor._lookupPartyGlobalId(
        cid is int ? cid : (cid is num ? cid.toInt() : null),
      );
      if (customerGlobalId != null) payload['customerGlobalId'] = customerGlobalId;
    }
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'quotations',
      operation: 'update',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.updateQuotation(id, payload, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deleteQuotation(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing quotation delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'quotations',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deleteQuotation(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Price Lists ───────────────────────────────────────────────────────────

  static Future<int?> createPriceList(Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing price list create to server');
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'price_lists',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createPriceList(data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updatePriceList(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing price list update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'price_lists',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.updatePriceList(id, data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> setPriceListItem(Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing price list item upsert to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'price_list_items',
      operation: 'upsert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.setPriceListItem(data, idempotencyKey: reqIdemKey),
    );
  }

  // ── Activity Logs ─────────────────────────────────────────────────────────

  /// Push a single activity log entry to the server.
  /// Non-blocking: queued in outbox when server is unreachable.
  static Future<bool> pushActivityLog(Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'activity_logs',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.pushActivityLog(data, idempotencyKey: reqIdemKey),
    );
  }

  // ── Printers ──────────────────────────────────────────────────────────────

  static Future<int?> createPrinter(Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing printer create to server');
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'printers',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createPrinter(data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updatePrinter(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing printer update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'printers',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.updatePrinter(id, data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deletePrinter(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing printer delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'printers',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deletePrinter(id, idempotencyKey: reqIdemKey),
    );
  }
}
