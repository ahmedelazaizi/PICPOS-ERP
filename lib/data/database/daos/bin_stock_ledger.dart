part of '../database.dart';

/// Keeps the DEFAULT bin as a projection of the warehouse and lot ledgers.
/// Called inside the posting transaction, never posts its own stock or GL.
extension BinStockLedger on AppDatabase {
  /// Consume one lot across active bins in bin-code order, then location id.
  /// Unlocated stock uses the null-batch row; shortages abort the posting.
  Future<void> deductIssuedBinStock(
      int productId, int warehouseId, int? batchId, double quantity) async {
    final rows = await customSelect(
      'SELECT s.id, s.quantity FROM location_stock s '
      'JOIN warehouse_locations l ON l.id = s.location_id '
      'WHERE s.product_id = ? AND s.warehouse_id = ? '
      'AND ${batchId == null ? 's.batch_id IS NULL' : 's.batch_id = ?'} '
      'AND l.is_active = 1 AND s.quantity > 0 '
      'ORDER BY l.bin_code, l.id',
      variables: [Variable<int>(productId), Variable<int>(warehouseId),
        if (batchId != null) Variable<int>(batchId)],
    ).get();
    var remaining = quantity;
    for (final row in rows) {
      if (remaining <= 0.000001) break;
      final available = (row.data['quantity'] as num).toDouble();
      final taken = remaining < available ? remaining : available;
      await customUpdate(
        'UPDATE location_stock SET quantity = quantity - ?, '
        'updated_at = ?, last_modified_at = ?, row_version = row_version + 1 '
        'WHERE id = ?',
        variables: [Variable<double>(taken), Variable<int>(_dmNow()),
          Variable<int>(_dmNow()), Variable<int>((row.data['id'] as num).toInt())],
      );
      remaining -= taken;
    }
    if (remaining > 0.000001) {
      throw StateError('رصيد المواقع للدفعة لا يكفي للصرف.');
    }
  }

  Future<void> syncDefaultBinStock(int productId, int warehouseId) async {
    final location = await customSelect(
      'SELECT id FROM warehouse_locations WHERE warehouse_id = ? '
      'AND is_default = 1 LIMIT 1',
      variables: [Variable<int>(warehouseId)],
    ).getSingleOrNull();
    final locationId = location == null
        ? await _dmInsert('warehouse_locations', {
            'warehouse_id': warehouseId,
            'bin_code': 'DEFAULT',
            'barcode': 'BIN-$warehouseId-DEFAULT',
            'is_default': 1,
          })
        : (location.data['id'] as num).toInt();
    final balance = await customSelect(
      'SELECT quantity, reserved_quantity FROM inventory_balances '
      'WHERE product_id = ? AND warehouse_id = ?',
      variables: [Variable<int>(productId), Variable<int>(warehouseId)],
    ).getSingleOrNull();
    if (balance == null) return;
    final batches = await customSelect(
      'SELECT id, quantity FROM product_batches WHERE product_id = ? '
      'AND warehouse_id = ? AND quantity <> 0',
      variables: [Variable<int>(productId), Variable<int>(warehouseId)],
    ).get();
    final current = await customSelect(
      'SELECT id, batch_id FROM location_stock WHERE product_id = ? '
      'AND warehouse_id = ? AND location_id = ?',
      variables: [Variable<int>(productId), Variable<int>(warehouseId), Variable<int>(locationId)],
    ).get();
    final otherBins = await customSelect(
      'SELECT batch_id, SUM(quantity) AS quantity FROM location_stock '
      'WHERE product_id = ? AND warehouse_id = ? AND location_id <> ? '
      'GROUP BY batch_id',
      variables: [Variable<int>(productId), Variable<int>(warehouseId), Variable<int>(locationId)],
    ).get();
    final outside = <int?, double>{
      for (final row in otherBins)
        (row.data['batch_id'] as num?)?.toInt():
            (row.data['quantity'] as num).toDouble(),
    };
    final batchQuantities = <int?, double>{
      for (final batch in batches)
        (batch.data['id'] as num).toInt():
            (batch.data['quantity'] as num).toDouble() -
            (outside[(batch.data['id'] as num).toInt()] ?? 0),
    };
    batchQuantities[null] = (balance.data['quantity'] as num).toDouble() -
        batches.fold<double>(0, (sum, batch) =>
            sum + (batch.data['quantity'] as num).toDouble()) -
        (outside[null] ?? 0);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final row in current) {
      final batchId = (row.data['batch_id'] as num?)?.toInt();
      final quantity = batchQuantities.remove(batchId) ?? 0;
      await customUpdate(
        'UPDATE location_stock SET quantity = ?, reserved_quantity = ?, '
        'updated_at = ?, last_modified_at = ?, row_version = row_version + 1 '
        'WHERE id = ?',
        variables: [
          Variable<double>(quantity),
          Variable<double>(batchId == null
              ? (balance.data['reserved_quantity'] as num).toDouble() : 0),
          Variable<int>(now), Variable<int>(now),
          Variable<int>((row.data['id'] as num).toInt()),
        ],
      );
    }
    for (final entry in batchQuantities.entries) {
      if (entry.value == 0) continue;
      await _dmInsert('location_stock', {
        'product_id': productId,
        'warehouse_id': warehouseId,
        'location_id': locationId,
        'batch_id': entry.key,
        'quantity': entry.value,
        'reserved_quantity': entry.key == null
            ? (balance.data['reserved_quantity'] as num).toDouble() : 0.0,
        'updated_at': now,
      });
    }
  }
}
