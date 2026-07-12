import '../../data/database/database.dart';

abstract class ISalesOrdersRepository {
  /// Watch all sales orders
  Stream<List<SalesOrderData>> watchSalesOrders();

  /// Watch sales orders by status
  Stream<List<SalesOrderData>> watchSalesOrdersByStatus(String status);

  /// Get single SO by ID
  Future<SalesOrderData?> getSalesOrderById(int id);

  /// Get items for a sales order
  Future<List<SalesOrderItem>> getSalesOrderItems(int orderId);

  /// Create a new sales order
  Future<int> createSalesOrder({
    int? customerId,
    required int warehouseId,
    required DateTime orderDate,
    DateTime? expectedDate,
    String? notes,
    int? costCenterId,
    required List<SalesOrderItemsCompanion> items,
  });

  /// Update SO status
  Future<void> updateSalesOrderStatus(int orderId, String newStatus);

  /// Delete a draft SO
  Future<void> deleteSalesOrder(int orderId);

  /// Convert SO to Sales Invoice
  Future<int> convertSOToInvoice(int orderId);
}
