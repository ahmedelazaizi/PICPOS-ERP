// Use case for adjusting product stock
//
// Handles stock adjustments:
// 1. Validate adjustment amount
// 2. Update product stock
// 3. Record stock movement with reason

import '../../../domain/repositories/inventory_repository.dart';

class AdjustStockUseCase {
  final InventoryRepository _repository;

  AdjustStockUseCase(this._repository);

  /// Execute stock adjustment
  Future<StockAdjustmentResult> execute(StockAdjustmentRequest request) async {
    // 1. Validate request
    final validation = _validate(request);
    if (!validation.isValid) {
      return StockAdjustmentResult.failure(validation.error!);
    }

    try {
      // Delegate to repository — handles stock update + movement recording
      await _repository.adjustStock(
        productId: request.productId,
        warehouseId: request.warehouseId,
        quantity: request.quantity,
        type: request.adjustmentType,
        notes: request.reason,
      );

      // Get updated stock level
      final newStock = await _repository.getProductStock(request.productId);

      return StockAdjustmentResult.success(
        productId: request.productId,
        newStock: newStock,
        adjustment: request.quantity,
      );
    } catch (e) {
      return StockAdjustmentResult.failure('فشل في تعديل المخزون: $e');
    }
  }

  ValidationResult _validate(StockAdjustmentRequest request) {
    if (request.productId <= 0) {
      return const ValidationResult.invalid('منتج غير صحيح');
    }

    if (request.quantity == 0) {
      return const ValidationResult.invalid('كمية التعديل لا يمكن أن تكون صفر');
    }

    if (request.reason.isEmpty) {
      return const ValidationResult.invalid('يرجى إدخال سبب التعديل');
    }

    return const ValidationResult.valid();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REQUEST / RESPONSE CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Stock adjustment request
class StockAdjustmentRequest {
  final int productId;
  final int warehouseId;
  final double quantity; // Positive = add, Negative = subtract
  final String adjustmentType; // count, damage, return, transfer
  final String reason;
  final int? batchId;

  const StockAdjustmentRequest({
    required this.productId,
    this.warehouseId = 1,
    required this.quantity,
    required this.adjustmentType,
    required this.reason,
    this.batchId,
  });
}

/// Stock adjustment result
sealed class StockAdjustmentResult {
  const StockAdjustmentResult();

  factory StockAdjustmentResult.success({
    required int productId,
    required double newStock,
    required double adjustment,
  }) = StockAdjustmentSuccess;

  factory StockAdjustmentResult.failure(String error) = StockAdjustmentFailure;

  bool get isSuccess => this is StockAdjustmentSuccess;
  bool get isFailure => this is StockAdjustmentFailure;
}

class StockAdjustmentSuccess extends StockAdjustmentResult {
  final int productId;
  final double newStock;
  final double adjustment;

  const StockAdjustmentSuccess({
    required this.productId,
    required this.newStock,
    required this.adjustment,
  });
}

class StockAdjustmentFailure extends StockAdjustmentResult {
  final String error;
  const StockAdjustmentFailure(this.error);
}

/// Validation result
class ValidationResult {
  final bool isValid;
  final String? error;

  const ValidationResult.valid() : isValid = true, error = null;
  const ValidationResult.invalid(this.error) : isValid = false;
}
