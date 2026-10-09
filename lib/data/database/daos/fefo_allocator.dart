part of '../database.dart';

/// Selects source-warehouse lots without changing stock; the caller consumes
/// these rows inside its existing posting transaction.
extension FefoAllocator on AppDatabase {
  Future<List<ProductBatch>> allocatableLots({
    required int productId,
    required int warehouseId,
  }) async {
    final expiryRow = await (selectOnly(products)
          ..addColumns([products.trackExpiry])
          ..where(products.id.equals(productId)))
        .getSingle();
    final tracksExpiry = expiryRow.read(products.trackExpiry) ?? false;
    final lots = await getBatchesForIssue(productId, warehouseId: warehouseId);
    if (!tracksExpiry ||
        await getSettingValue('warehouse_bins_enabled') != 'true' ||
        await getSettingValue('block_issue_without_valid_batch') != 'true') {
      return lots;
    }
    final today = DateTime.now();
    final valid = lots.where((lot) => lot.expiryDate.isAfter(today)).toList();
    valid.sort((first, second) {
      final expiryOrder = first.expiryDate.compareTo(second.expiryDate);
      if (expiryOrder != 0) return expiryOrder;
      final creationOrder = first.createdAt.compareTo(second.createdAt);
      return creationOrder != 0 ? creationOrder : first.id.compareTo(second.id);
    });
    return valid;
  }

  Future<void> requireValidLotCoverage({
    required int productId,
    required int warehouseId,
    required double quantity,
    required List<ProductBatch> lots,
  }) async {
    final enabled = await getSettingValue('warehouse_bins_enabled') == 'true';
    final block = await getSettingValue('block_issue_without_valid_batch');
    if (!enabled || block != 'true') return;
    final expiryRow = await (selectOnly(products)
          ..addColumns([products.trackExpiry])
          ..where(products.id.equals(productId)))
        .getSingle();
    if (expiryRow.read(products.trackExpiry) != true) return;
    final coverage = lots.fold<double>(0, (sum, lot) => sum + lot.quantity);
    if (coverage + 0.000001 < quantity) {
      throw StateError('لا توجد دفعات صالحة كافية للصنف في المخزن المصدر.');
    }
  }
}
