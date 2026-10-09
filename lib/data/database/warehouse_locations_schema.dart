part of 'database.dart';

/// Raw-SQL bin projection. Warehouse balances remain the posting authority.
extension WarehouseLocationsSchema on AppDatabase {
  Future<void> ensureWarehouseLocationsSchema({bool backfill = true}) async {
    for (final sql in _isPostgres ? _warehousePgSql : _warehouseSqliteSql) {
      await customStatement(sql);
    }
    await _dmAddColumns('stock_movements', const [
      'location_id INTEGER',
      'batch_id INTEGER',
    ]);
    if (backfill) await backfillWarehouseLocations();
  }

  Future<void> createDefaultWarehouseLocation(int warehouseId) async {
    final existing = await customSelect(
      'SELECT id FROM warehouse_locations WHERE warehouse_id = ? '
      'AND is_default = 1 LIMIT 1',
      variables: [Variable<int>(warehouseId)],
    ).getSingleOrNull();
    if (existing != null) return;
    await _dmInsert('warehouse_locations', {
      'warehouse_id': warehouseId,
      'bin_code': 'DEFAULT',
      'barcode': 'BIN-$warehouseId-DEFAULT',
      'is_default': 1,
    });
  }

  Future<void> backfillWarehouseLocations() async {
    await transaction(() async {
      final warehouses = await customSelect('SELECT id FROM warehouses').get();
      for (final warehouse in warehouses) {
        final warehouseId = (warehouse.data['id'] as num).toInt();
        await createDefaultWarehouseLocation(warehouseId);
      }
      final balances = await customSelect(
        'SELECT product_id, warehouse_id FROM inventory_balances',
      ).get();
      for (final balance in balances) {
        await syncDefaultBinStock(
          (balance.data['product_id'] as num).toInt(),
          (balance.data['warehouse_id'] as num).toInt(),
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> warehouseBinDiscrepancies() async {
    final rows = await customSelect('''
      SELECT b.product_id, b.warehouse_id, p.name AS product_name,
        w.name AS warehouse_name, b.quantity AS warehouse_quantity,
        COALESCE((SELECT SUM(s.quantity) FROM location_stock s
          WHERE s.product_id = b.product_id AND s.warehouse_id = b.warehouse_id), 0) AS bin_quantity,
        COALESCE((SELECT SUM(p.quantity) FROM product_batches p
          WHERE p.product_id = b.product_id AND p.warehouse_id = b.warehouse_id), 0) AS batch_quantity,
        COALESCE((SELECT SUM(s.quantity) FROM location_stock s
          WHERE s.product_id = b.product_id AND s.warehouse_id = b.warehouse_id
          AND s.batch_id IS NOT NULL), 0) AS located_batch_quantity
      FROM inventory_balances b
      JOIN products p ON p.id = b.product_id
      JOIN warehouses w ON w.id = b.warehouse_id
      WHERE ABS(b.quantity - COALESCE((SELECT SUM(s.quantity) FROM location_stock s
          WHERE s.product_id = b.product_id AND s.warehouse_id = b.warehouse_id), 0)) > 0.000001
        OR ABS(COALESCE((SELECT SUM(p.quantity) FROM product_batches p
          WHERE p.product_id = b.product_id AND p.warehouse_id = b.warehouse_id), 0) -
          COALESCE((SELECT SUM(s.quantity) FROM location_stock s
          WHERE s.product_id = b.product_id AND s.warehouse_id = b.warehouse_id
          AND s.batch_id IS NOT NULL), 0)) > 0.000001
        OR COALESCE((SELECT SUM(p.quantity) FROM product_batches p
          WHERE p.product_id = b.product_id AND p.warehouse_id = b.warehouse_id), 0) > b.quantity + 0.000001
    ''').get();
    return [for (final row in rows) row.data];
  }

  Future<void> enableWarehouseBins() async {
    await backfillWarehouseLocations();
    if ((await warehouseBinDiscrepancies()).isNotEmpty) {
      throw StateError('توجد فروقات في مواقع التخزين؛ راجع التسوية أولاً.');
    }
    await setSetting('warehouse_bins_enabled', 'true');
  }
}

const _warehouseSqliteSql = <String>[
  '''CREATE TABLE IF NOT EXISTS warehouse_locations (
    id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
    aisle TEXT, rack TEXT, shelf TEXT, bin_code TEXT NOT NULL,
    barcode TEXT NOT NULL UNIQUE, is_default INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
    last_modified_at INTEGER, deleted_at INTEGER, origin_client_id TEXT,
    row_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE(warehouse_id, bin_code))''',
  '''CREATE TABLE IF NOT EXISTS location_stock (
    id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
    location_id INTEGER NOT NULL REFERENCES warehouse_locations(id),
    batch_id INTEGER REFERENCES product_batches(id),
    quantity REAL NOT NULL DEFAULT 0, reserved_quantity REAL NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
    last_modified_at INTEGER, deleted_at INTEGER, origin_client_id TEXT,
    row_version INTEGER NOT NULL DEFAULT 0)''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_location_stock_key ON location_stock(product_id, warehouse_id, location_id, COALESCE(batch_id, 0))',
  'CREATE INDEX IF NOT EXISTS idx_location_stock_batch ON location_stock(batch_id)',
];

const _warehousePgSql = <String>[
  '''CREATE TABLE IF NOT EXISTS warehouse_locations (
    id SERIAL PRIMARY KEY, global_id TEXT UNIQUE,
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
    aisle TEXT, rack TEXT, shelf TEXT, bin_code TEXT NOT NULL,
    barcode TEXT NOT NULL UNIQUE, is_default INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
    last_modified_at BIGINT, deleted_at BIGINT, origin_client_id TEXT,
    row_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE(warehouse_id, bin_code))''',
  '''CREATE TABLE IF NOT EXISTS location_stock (
    id SERIAL PRIMARY KEY, global_id TEXT UNIQUE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(id),
    location_id INTEGER NOT NULL REFERENCES warehouse_locations(id),
    batch_id INTEGER REFERENCES product_batches(id),
    quantity DOUBLE PRECISION NOT NULL DEFAULT 0,
    reserved_quantity DOUBLE PRECISION NOT NULL DEFAULT 0,
    updated_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
    last_modified_at BIGINT, deleted_at BIGINT, origin_client_id TEXT,
    row_version INTEGER NOT NULL DEFAULT 0)''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_location_stock_key ON location_stock(product_id, warehouse_id, location_id, COALESCE(batch_id, 0))',
  'CREATE INDEX IF NOT EXISTS idx_location_stock_batch ON location_stock(batch_id)',
];
