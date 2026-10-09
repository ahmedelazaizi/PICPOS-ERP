part of '../database.dart';

/// Moves lot provenance after both warehouse legs of a legacy immediate bond.
/// The enclosing transfer transaction owns rollback and accounting.
extension BinTransferLots on AppDatabase {
  Future<void> carryTransferLots({
    required int productId,
    required int fromWarehouseId,
    required int toWarehouseId,
    required double quantity,
  }) async {
    final deductions = await consumeBatchesForIssue(
      productId: productId, warehouseId: fromWarehouseId, quantity: quantity,
    );
    for (final deduction in deductions) {
      final existing = await (select(productBatches)
            ..where((lot) =>
                lot.productId.equals(productId) &
                lot.warehouseId.equals(toWarehouseId) &
                lot.batchNumber.equals(deduction['batchNumber'] as String) &
                lot.expiryDate.equals(deduction['expiryDate'] as DateTime))
            ..limit(1))
          .getSingleOrNull();
      final moved = (deduction['quantity'] as num).toDouble();
      if (existing == null) {
        await insertBatch(ProductBatchesCompanion.insert(
          productId: productId,
          warehouseId: toWarehouseId,
          batchNumber: deduction['batchNumber'] as String,
          expiryDate: deduction['expiryDate'] as DateTime,
          quantity: Value(moved),
          initialQuantity: Value(moved),
          unitCost: Value((deduction['unitCost'] as num).toDouble()),
        ));
      } else {
        await (update(productBatches)..where((lot) => lot.id.equals(existing.id)))
            .write(ProductBatchesCompanion(
          quantity: Value(existing.quantity + moved),
          initialQuantity: Value(existing.initialQuantity + moved),
          status: const Value('active'),
        ));
      }
    }
    await syncDefaultBinStock(productId, fromWarehouseId);
    await syncDefaultBinStock(productId, toWarehouseId);
  }
}
