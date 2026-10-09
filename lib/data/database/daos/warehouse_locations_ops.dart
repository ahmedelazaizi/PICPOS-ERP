part of '../database.dart';

extension WarehouseLocationsOps on AppDatabase {
  Future<List<Map<String, dynamic>>> warehouseLocations(int warehouseId) async {
    final rows = await customSelect(
      'SELECT * FROM warehouse_locations WHERE warehouse_id = ? '
      'AND deleted_at IS NULL ORDER BY is_default DESC, bin_code',
      variables: [Variable<int>(warehouseId)],
    ).get();
    return [for (final row in rows) row.data];
  }

  Future<int> saveWarehouseLocation({
    required int warehouseId,
    required String binCode,
    String? aisle,
    String? rack,
    String? shelf,
  }) async {
    final code = binCode.trim();
    if (code.isEmpty) throw ArgumentError.value(binCode, 'binCode');
    return _dmInsert('warehouse_locations', {
      'warehouse_id': warehouseId,
      'bin_code': code,
      'aisle': aisle?.trim(),
      'rack': rack?.trim(),
      'shelf': shelf?.trim(),
      'barcode': 'BIN-${UuidV7.generate()}',
    });
  }

  Future<void> editWarehouseLocation({
    required int locationId,
    required String binCode,
    String? aisle,
    String? rack,
    String? shelf,
  }) async {
    if (binCode.trim().isEmpty) throw ArgumentError.value(binCode, 'binCode');
    await customUpdate(
      'UPDATE warehouse_locations SET bin_code = ?, aisle = ?, rack = ?, shelf = ?, '
      'last_modified_at = ?, row_version = row_version + 1 '
      'WHERE id = ? AND is_default = 0',
      variables: [Variable<String>(binCode.trim()), Variable<String>(aisle?.trim()),
        Variable<String>(rack?.trim()), Variable<String>(shelf?.trim()),
        Variable<int>(_dmNow()), Variable<int>(locationId)],
    );
  }

  Future<List<Map<String, dynamic>>> warehouseLocationStock(int warehouseId) async {
    final rows = await customSelect(
      'SELECT s.*, p.name AS product_name, b.batch_number FROM location_stock s '
      'JOIN products p ON p.id = s.product_id '
      'LEFT JOIN product_batches b ON b.id = s.batch_id '
      'WHERE s.warehouse_id = ? AND ABS(s.quantity) > 0.000001 '
      'ORDER BY s.location_id, p.name, b.batch_number',
      variables: [Variable<int>(warehouseId)],
    ).get();
    return [for (final row in rows) row.data];
  }

  Future<void> deactivateWarehouseLocation(int locationId) async {
    await transaction(() async {
      final occupied = await customSelect(
        'SELECT 1 FROM location_stock WHERE location_id = ? '
        'AND (ABS(quantity) > 0.000001 OR reserved_quantity > 0) LIMIT 1',
        variables: [Variable<int>(locationId)],
      ).getSingleOrNull();
      if (occupied != null) throw StateError('انقل رصيد الموقع قبل تعطيله.');
      await customUpdate(
        'UPDATE warehouse_locations SET is_active = 0, '
        'last_modified_at = ?, row_version = row_version + 1 '
        'WHERE id = ? AND is_default = 0',
        variables: [Variable<int>(_dmNow()), Variable<int>(locationId)],
      );
    });
  }

  Future<void> moveStockBetweenBins({
    required int fromLocationId,
    required int toLocationId,
    required int productId,
    required double quantity,
    int? batchId,
  }) async {
    if (quantity <= 0) throw ArgumentError.value(quantity, 'quantity');
    if (await getSettingValue('warehouse_bins_enabled') != 'true') {
      throw StateError('فعّل مواقع التخزين بعد تسوية الفروقات أولاً.');
    }
    await transaction(() async {
      final locations = await customSelect(
        'SELECT id, warehouse_id, is_active FROM warehouse_locations '
        'WHERE id IN (?, ?)',
        variables: [Variable<int>(fromLocationId), Variable<int>(toLocationId)],
      ).get();
      if (locations.length != 2 || fromLocationId == toLocationId ||
          locations.any((row) => row.data['is_active'] != 1)) {
        throw StateError('موقع تخزين غير صالح.');
      }
      final warehouseId = (locations.first.data['warehouse_id'] as num).toInt();
      if (locations.any((row) => row.data['warehouse_id'] != warehouseId)) {
        throw StateError('نقل المواقع لا يغير المخزن.');
      }
      final source = await customSelect(
        'SELECT id, quantity FROM location_stock WHERE location_id = ? '
        'AND product_id = ? AND ${batchId == null ? 'batch_id IS NULL' : 'batch_id = ?'}',
        variables: [Variable<int>(fromLocationId), Variable<int>(productId),
          if (batchId != null) Variable<int>(batchId)],
      ).getSingleOrNull();
      if (source == null || (source.data['quantity'] as num).toDouble() < quantity) {
        throw StateError('رصيد الموقع لا يكفي للنقل.');
      }
      final target = await customSelect(
        'SELECT id FROM location_stock WHERE location_id = ? '
        'AND product_id = ? AND ${batchId == null ? 'batch_id IS NULL' : 'batch_id = ?'}',
        variables: [Variable<int>(toLocationId), Variable<int>(productId),
          if (batchId != null) Variable<int>(batchId)],
      ).getSingleOrNull();
      final now = _dmNow();
      await customUpdate(
        'UPDATE location_stock SET quantity = quantity - ?, '
        'updated_at = ?, last_modified_at = ?, row_version = row_version + 1 '
        'WHERE id = ?',
        variables: [Variable<double>(quantity), Variable<int>(now),
          Variable<int>(now), Variable<int>((source.data['id'] as num).toInt())],
      );
      if (target == null) {
        await _dmInsert('location_stock', {
          'product_id': productId, 'warehouse_id': warehouseId,
          'location_id': toLocationId, 'batch_id': batchId,
          'quantity': quantity, 'updated_at': now,
        });
      } else {
        await customUpdate(
          'UPDATE location_stock SET quantity = quantity + ?, '
          'updated_at = ?, last_modified_at = ?, row_version = row_version + 1 '
          'WHERE id = ?',
          variables: [Variable<double>(quantity), Variable<int>(now),
            Variable<int>(now), Variable<int>((target.data['id'] as num).toInt())],
        );
      }
      final balance = await customSelect(
        'SELECT quantity FROM inventory_balances WHERE product_id = ? '
        'AND warehouse_id = ?',
        variables: [Variable<int>(productId), Variable<int>(warehouseId)],
      ).getSingle();
      for (final (locationId, signed) in
          [(fromLocationId, -quantity), (toLocationId, quantity)]) {
        final movementId = await createStockMovement(
          StockMovementsCompanion.insert(
            productId: productId, warehouseId: warehouseId,
            movementType: 'bin_move', quantity: signed,
            balanceAfter: (balance.data['quantity'] as num).toDouble(),
          ),
        );
        await customUpdate(
          'UPDATE stock_movements SET location_id = ?, batch_id = ? WHERE id = ?',
          variables: [Variable<int>(locationId), Variable<int>(batchId),
            Variable<int>(movementId)],
        );
      }
    });
  }
}
