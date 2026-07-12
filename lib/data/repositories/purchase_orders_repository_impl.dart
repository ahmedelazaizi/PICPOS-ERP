import '../database/database.dart';
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
  Future<int> convertPOToInvoice(int orderId) =>
      _db.convertPOToInvoice(orderId);
}
