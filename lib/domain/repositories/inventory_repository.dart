import '../../data/database/database.dart' as db;
import '../entities/stock_requisition_entity.dart';
import '../entities/stock_requisition_item_entity.dart';

/// Inventory repository interface
///
/// Defines contract for inventory operations. Implementations in data layer.
abstract class InventoryRepository {
  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Adjust stock for a product.
  ///
  /// [adjustmentEventGid] (Spec 135 BUG-A): caller-minted UUIDv7 for the
  /// adjustment event, threaded into the local JE + the server submit so
  /// both sides converge on one JE id. Null ⇒ DAO mints a fresh one.
  Future<void> adjustStock({
    required int productId,
    required int warehouseId,
    required double quantity,
    String? type,
    String? notes,
    String? adjustmentEventGid,
  });

  /// Get current stock for a product
  Future<double> getProductStock(int productId, {int? warehouseId});

  /// Issue 5 (Feature 021): true if a previous opening_stock movement exists
  /// for the product+warehouse pair. Used by the Excel importer to skip
  /// duplicate opening balances on re-import.
  Future<bool> hasOpeningStockMovement({
    required int productId,
    required int warehouseId,
  });

  /// Watch stock movements for a product
  Stream<List<StockMovementData>> watchProductMovements(int productId);

  /// Get stock movements by date range
  Future<List<StockMovementData>> getMovementsByDateRange(
    DateTime from,
    DateTime to,
  );

  /// Watch all stock movements
  Stream<List<StockMovementData>> watchAllStockMovements({int limit = 100});

  // ═══════════════════════════════════════════════════════════════════════════
  // WAREHOUSE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Watch all warehouses
  Stream<List<WarehouseData>> watchWarehouses();

  /// Get warehouse by ID
  Future<WarehouseData?> getWarehouseById(int id);

  /// Get default warehouse
  Future<WarehouseData?> getDefaultWarehouse();

  /// Transfer stock between warehouses
  Future<void> transferStock({
    required int productId,
    required int fromWarehouseId,
    required int toWarehouseId,
    required double quantity,
    String? notes,
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH & EXPIRY MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get product batches
  Future<List<ProductBatchData>> getProductBatches(int productId);

  /// Get expired batches
  Future<List<ProductBatchData>> getExpiredBatches();

  /// Get batches expiring within N days
  Future<List<ProductBatchData>> getExpiringBatches(int days);

  // ═══════════════════════════════════════════════════════════════════════════
  // REPORTS & ANALYTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get low stock products
  Future<List<LowStockProductData>> getLowStockProducts();

  /// Get inventory valuation
  Future<InventoryValuation> getInventoryValuation({int? warehouseId});

  // ═══════════════════════════════════════════════════════════════════════════
  // POS & AUDIT SUPPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Watch held orders
  Stream<List<db.HeldOrder>> watchHeldOrders();

  /// Watch open audit
  Stream<List<db.StockAudit>> watchOpenAudit();

  /// Check if there is an active stock audit in progress
  Future<bool> hasActiveStockAudit();

  /// Get audit items
  Future<List<db.StockAuditItem>> getAuditItems(int auditId);

  /// Create a new stock audit
  Future<int> createStockAudit({int? userId});

  /// Save or update an audit item
  Future<void> saveAuditItem({
    required int auditId,
    required int productId,
    required double expectedQuantity,
    required double actualQuantity,
  });

  /// Finalize audit and adjust stock
  Future<void> finalizeAudit(int auditId);

  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK REQUISITIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Watch all stock requisitions
  Stream<List<StockRequisitionEntity>> watchAllStockRequisitions({DateTime? startDate, DateTime? endDate});

  /// Get stock requisition by ID
  Future<StockRequisitionEntity?> getStockRequisitionById(int id);

  /// Get stock requisition items
  Future<List<StockRequisitionItemEntity>> getStockRequisitionItems(int requisitionId);

  /// Create a new stock requisition
  Future<int> createStockRequisition(StockRequisitionEntity requisition, List<StockRequisitionItemEntity> items);

  /// Update stock requisition status
  Future<void> updateStockRequisitionStatus(int id, String status);

  /// Delete a draft stock requisition
  Future<void> deleteStockRequisition(int id);

  /// Get stock movements for a specific reference (PIR Architecture)
  Future<List<StockMovementData>> getStockMovementsByReference(String referenceType, int referenceId);

  /// Get warehouse-specific average cost for a product (PIR-009)
  /// Returns the average cost from inventory_balances, falling back to 0.
  Future<double> getProductWarehouseCost(int productId, int warehouseId);

  /// Delete a specific stock movement (PIR Architecture)
  Future<void> deleteStockMovement(int id);
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Stock movement data
class StockMovementData {
  final int id;
  final int productId;
  final int warehouseId;
  final String movementType;
  final double quantity;
  final double balanceAfter;
  final double unitCost;
  final String? productName;
  final String? warehouseName;
  final String? referenceType;
  final int? referenceId;
  final String? notes;
  final DateTime createdAt;

  const StockMovementData({
    required this.id,
    required this.productId,
    required this.warehouseId,
    required this.movementType,
    required this.quantity,
    required this.balanceAfter,
    this.unitCost = 0.0,
    this.productName,
    this.warehouseName,
    this.referenceType,
    this.referenceId,
    this.notes,
    required this.createdAt,
  });
}

/// Warehouse data
class WarehouseData {
  final int id;
  final String name;
  final String? location;
  final bool isDefault;
  final String type; // 'general', 'raw_materials', 'finished_goods', 'retail'
  final int? costCenterId;
  final int? branchId;

  const WarehouseData({
    required this.id,
    required this.name,
    this.location,
    required this.isDefault,
    this.type = 'general',
    this.costCenterId,
    this.branchId,
  });
}

/// Product batch data (for FEFO tracking)
class ProductBatchData {
  final int id;
  final int productId;
  final String? batchNumber;
  final DateTime? expiryDate;
  final double quantity;
  final double costPrice;
  final DateTime createdAt;

  const ProductBatchData({
    required this.id,
    required this.productId,
    this.batchNumber,
    this.expiryDate,
    required this.quantity,
    required this.costPrice,
    required this.createdAt,
  });

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());

  int? get daysUntilExpiry => expiryDate?.difference(DateTime.now()).inDays;
}

/// Low stock product data
class LowStockProductData {
  final int productId;
  final String productName;
  final double currentStock;
  final double minimumStock;
  final double shortage;

  const LowStockProductData({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.minimumStock,
    required this.shortage,
  });
}

/// Inventory valuation summary
class InventoryValuation {
  final double totalCostValue;
  final double totalSaleValue;
  final double potentialProfit;
  final int itemCount;

  const InventoryValuation({
    required this.totalCostValue,
    required this.totalSaleValue,
    required this.potentialProfit,
    required this.itemCount,
  });

  double get profitMargin =>
      totalSaleValue > 0 ? (potentialProfit / totalSaleValue) * 100 : 0;
}
