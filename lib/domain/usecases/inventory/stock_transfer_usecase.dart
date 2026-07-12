import '../../repositories/inventory_repository.dart';

/// Use case: Inter-warehouse stock transfer.
///
/// Validates source warehouse has sufficient stock, then creates matching
/// outbound and inbound movements atomically.
class StockTransferUseCase {
  final InventoryRepository _repo;

  const StockTransferUseCase(this._repo);

  /// Transfers [quantity] units of product from source to target warehouse.
  Future<void> execute({
    required int productId,
    required int sourceWarehouseId,
    required int targetWarehouseId,
    required double quantity,
    String? notes,
  }) async {
    // Validation
    if (quantity <= 0) {
      throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');
    }
    if (sourceWarehouseId == targetWarehouseId) {
      throw ArgumentError('لا يمكن التحويل من وإلى نفس المخزن');
    }

    // Source balance check is done at the repository level
    await _repo.transferStock(
      productId: productId,
      fromWarehouseId: sourceWarehouseId,
      toWarehouseId: targetWarehouseId,
      quantity: quantity,
      notes: notes,
    );
  }
}
