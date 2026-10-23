import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('bulk warehouse stock equals the former per-warehouse sum', () async {
    final p1 = await db.into(db.products).insert(ProductsCompanion.insert(
          code: 'EQ-1',
          name: 'صنف 1',
          costPrice: const Value(10),
          salePrice: const Value(20),
        ));
    final p2 = await db.into(db.products).insert(ProductsCompanion.insert(
          code: 'EQ-2',
          name: 'صنف 2',
          costPrice: const Value(7),
          salePrice: const Value(11),
        ));
    final w1 = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن 1'));
    final w2 = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن 2'));
    await db.batch((batch) {
      batch.insert(
        db.inventoryBalances,
        InventoryBalancesCompanion.insert(
          productId: p1,
          warehouseId: w1,
          quantity: const Value(2),
        ),
      );
      batch.insert(
        db.inventoryBalances,
        InventoryBalancesCompanion.insert(
          productId: p1,
          warehouseId: w2,
          quantity: const Value(3),
        ),
      );
      batch.insert(
        db.inventoryBalances,
        InventoryBalancesCompanion.insert(
          productId: p2,
          warehouseId: w2,
          quantity: const Value(4),
        ),
      );
    });

    final former = <int, double>{};
    for (final warehouseId in [w1, w2]) {
      final map = await db.getWarehouseStockMap(warehouseId);
      for (final entry in map.entries) {
        former[entry.key] = (former[entry.key] ?? 0) + entry.value;
      }
    }
    final bulk = await db.getWarehouseStockMapForWarehouses([w1, w2]);

    expect(bulk, equals(former));
    expect(bulk, equals({p1: 5.0, p2: 4.0}));

    final analytics = await db.getInventoryReportAnalytics(
      warehouseIds: [w1, w2],
    );
    expect(analytics.totalCostValue, closeTo(78.0, 0.001));
    expect(analytics.totalSaleValue, closeTo(144.0, 0.001));
    expect(analytics.itemsCount, closeTo(9.0, 0.001));
  });
}
