import '../../data/database/database.dart';

/// Inventory-specific reporting interface
abstract class IInventoryReportingRepository {
  Future<List<Product>> getLowStockProducts();
  Future<List<ProductBatch>> getExpiredBatches();
  Future<List<ProductBatch>> getExpiringBatches(int days);
  Future<InventoryAnalytics> getInventoryReportAnalytics({
    List<int>? warehouseIds,
  });

  /// قيمةُ المخزون بالتكلفة بتاريخٍ ماضٍ — مقامُ معدّل الدوران.
  Future<double> getInventoryCostValueAt(
    DateTime at, {
    List<int>? warehouseIds,
  });
}
