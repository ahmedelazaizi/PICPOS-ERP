import 'dart:async';
import '../../data/database/database.dart';
import '../../domain/repositories/i_sales_orders_repository.dart';

class DriftSalesOrdersRepository implements ISalesOrdersRepository {
  final AppDatabase _db;

  DriftSalesOrdersRepository(this._db);

  @override
  Stream<List<SalesOrderData>> watchSalesOrders() {
    return _db.watchSalesOrders();
  }

  @override
  Stream<List<SalesOrderData>> watchSalesOrdersByStatus(String status) {
    return _db.watchSalesOrdersByStatus(status);
  }

  @override
  Future<SalesOrderData?> getSalesOrderById(int id) {
    return _db.getSalesOrderById(id);
  }

  @override
  Future<List<SalesOrderItem>> getSalesOrderItems(int orderId) {
    return _db.getSalesOrderItems(orderId);
  }

  @override
  Future<int> createSalesOrder({
    int? customerId,
    required int warehouseId,
    required DateTime orderDate,
    DateTime? expectedDate,
    String? notes,
    int? costCenterId,
    required List<SalesOrderItemsCompanion> items,
  }) {
    return _db.createSalesOrder(
      customerId: customerId,
      warehouseId: warehouseId,
      orderDate: orderDate,
      expectedDate: expectedDate,
      notes: notes,
      costCenterId: costCenterId,
      items: items,
    );
  }

  @override
  Future<void> updateSalesOrderStatus(int orderId, String newStatus) {
    return _db.updateSalesOrderStatus(orderId, newStatus);
  }

  @override
  Future<void> deleteSalesOrder(int orderId) {
    return _db.deleteSalesOrder(orderId);
  }

  @override
  Future<int> convertSOToInvoice(int orderId) {
    return _db.convertSOToInvoice(orderId);
  }
}
