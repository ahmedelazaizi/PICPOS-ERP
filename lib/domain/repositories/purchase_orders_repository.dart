import 'package:picpos_erp/data/database/database.dart';

/// Repository interface for Purchase Order management.
///
/// Abstracts the `PurchaseOrdersDao` extension to follow Clean Architecture.
/// Status flow: draft → sent → confirmed → received → (converted to invoice)
///            ↘ cancelled
abstract class PurchaseOrdersRepository {
  // ── Watch / Read ──────────────────────────────────────────────────────

  /// Watch all purchase orders, sorted by newest first.
  Stream<List<PurchaseOrderData>> watchPurchaseOrders();

  /// Watch purchase orders filtered by status.
  Stream<List<PurchaseOrderData>> watchPurchaseOrdersByStatus(String status);

  /// Get single PO by ID.
  Future<PurchaseOrderData?> getPurchaseOrderById(int id);

  /// Get items for a purchase order.
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId);

  /// Watch items for a purchase order.
  Stream<List<PurchaseOrderItem>> watchPurchaseOrderItems(int orderId);

  // ── Create / Update / Delete ──────────────────────────────────────────

  /// Create a new purchase order with items.
  Future<int> createPurchaseOrder({
    required int supplierId,
    required int warehouseId,
    required DateTime orderDate,
    DateTime? expectedDate,
    String? notes,
    int? costCenterId,
    required List<PurchaseOrderItemsCompanion> items,
  });

  /// Update PO status.
  Future<void> updatePurchaseOrderStatus(int orderId, String newStatus);

  /// Delete a draft PO (only drafts can be deleted).
  Future<void> deletePurchaseOrder(int orderId);

  /// Convert PO to Purchase Invoice. Returns the new invoice ID.
  Future<int> convertPOToInvoice(int orderId);
}
