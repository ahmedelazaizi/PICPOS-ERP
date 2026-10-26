import '../database/database.dart';
import '../database/sync_interceptor.dart';
import '../../services/client_write_interceptor.dart';
import '../../domain/repositories/purchase_orders_repository.dart';

/// Implementation of [PurchaseOrdersRepository] using Drift DAO.
class PurchaseOrdersRepositoryImpl implements PurchaseOrdersRepository {
  final AppDatabase _db;

  PurchaseOrdersRepositoryImpl(this._db);

  @override
  Stream<List<PurchaseOrderData>> watchPurchaseOrders() =>
      _db.watchPurchaseOrders();

  @override
  Stream<List<PurchaseOrderData>> watchPurchaseOrdersByStatus(String status) =>
      _db.watchPurchaseOrdersByStatus(status);

  @override
  Future<PurchaseOrderData?> getPurchaseOrderById(int id) =>
      _db.getPurchaseOrderById(id);

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) =>
      _db.getPurchaseOrderItems(orderId);

  @override
  Stream<List<PurchaseOrderItem>> watchPurchaseOrderItems(int orderId) =>
      _db.watchPurchaseOrderItems(orderId);

  @override
  Future<int> createPurchaseOrder({
    required int supplierId,
    required int warehouseId,
    required DateTime orderDate,
    DateTime? expectedDate,
    String? notes,
    int? costCenterId,
    required List<PurchaseOrderItemsCompanion> items,
  }) =>
      _db.createPurchaseOrder(
        supplierId: supplierId,
        warehouseId: warehouseId,
        orderDate: orderDate,
        expectedDate: expectedDate,
        notes: notes,
        costCenterId: costCenterId,
        items: items,
      );

  @override
  Future<void> updatePurchaseOrderStatus(int orderId, String newStatus) =>
      _db.updatePurchaseOrderStatus(orderId, newStatus);

  @override
  Future<void> deletePurchaseOrder(int orderId) =>
      _db.deletePurchaseOrder(orderId);

  @override
  Future<int> convertPOToInvoice(int orderId) async {
    if (!SyncInterceptor.isClientMode) return _db.convertPOToInvoice(orderId);
    // WH-001: a client/mirror never invoices a purchase order from its OWN
    // (possibly stale) copy. The invoice is submitted to the host with the
    // order's GLOBAL id; the host consumes the order in the same transaction
    // and refuses an order that has phone receipts or was already consumed.
    final po = await _db.getPurchaseOrderById(orderId);
    if (po == null) throw Exception('أمر شراء غير موجود');
    final gid = po.globalId;
    if (gid == null || gid.isEmpty) {
      throw Exception('أمر الشراء لم يُزامَن بعد');
    }
    final items = await _db.getPurchaseOrderItems(orderId);
    await ClientWriteInterceptor.dispatchWrite(
      () => ClientWriteInterceptor.submitPurchase(
        supplierId: po.supplierId,
        warehouseId: po.warehouseId,
        items: [
          for (final i in items)
            {
              'productId': i.productId,
              'quantity': i.quantity,
              'unitCost': i.unitCost,
              'total': i.total,
              'discount': i.discount,
            },
        ],
        paid: 0,
        paymentMethod: 'credit',
        notes: 'تم التحويل من أمر شراء ${po.orderNumber}',
        userId: SyncInterceptor.currentUserId,
        sourceOrderGlobalId: gid,
      ),
      tag: 'PO-CONVERT',
    );
    return 0;
  }
}
