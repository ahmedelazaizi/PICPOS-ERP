import '../../../data/database/database.dart';

/// Input for creating a production order
class ProductionOrderInput {
  final int bomId;
  final double orderedQty;
  final int warehouseId;
  final DateTime startDate;
  final String? notes;

  ProductionOrderInput({
    required this.bomId,
    required this.orderedQty,
    required this.warehouseId,
    required this.startDate,
    this.notes,
  });
}

/// Result of production operations
class ProductionResult {
  final bool isSuccess;
  final int? orderId;
  final String? error;
  
  ProductionResult.success([this.orderId]) : isSuccess = true, error = null;
  ProductionResult.failure(this.error) : isSuccess = false, orderId = null;
}

/// Use case: Full production order lifecycle (create → start → complete)
class ExecuteProductionUseCase {
  final AppDatabase _db;

  ExecuteProductionUseCase(this._db);

  /// Create a production order
  Future<ProductionResult> createOrder(ProductionOrderInput input) async {
    if (input.orderedQty <= 0) {
      return ProductionResult.failure('الكمية المطلوبة يجب أن تكون أكبر من صفر');
    }

    try {
      final orderId = await _db.createManufacturingOrder(
        bomId: input.bomId,
        orderedQty: input.orderedQty,
        warehouseId: input.warehouseId,
        startDate: input.startDate,
        notes: input.notes,
      );
      return ProductionResult.success(orderId);
    } catch (e) {
      return ProductionResult.failure(e.toString());
    }
  }

  /// Start production — deducts raw materials from inventory
  Future<ProductionResult> startProduction(int orderId) async {
    try {
      await _db.startProduction(orderId);
      return ProductionResult.success(orderId);
    } catch (e) {
      return ProductionResult.failure(e.toString());
    }
  }

  /// Complete production — adds finished product to inventory
  Future<ProductionResult> completeProduction(
    int orderId, {
    double? actualProducedQty,
    int? costCenterId,
  }) async {
    try {
      await _db.completeProduction(
        orderId,
        actualProducedQty: actualProducedQty,
        costCenterId: costCenterId,
      );
      return ProductionResult.success(orderId);
    } catch (e) {
      return ProductionResult.failure(e.toString());
    }
  }
}
