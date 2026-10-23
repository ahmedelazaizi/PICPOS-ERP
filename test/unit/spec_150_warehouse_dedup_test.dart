// Spec 150 / BUG 5b — WarehouseDedupExtension regression guard. Mirrors
// branch_dedup_test.dart: reproduces the legacy mirror/client state (one
// seeded "المخزن الرئيسي" row plus a server-pulled duplicate with no
// globalId) and asserts that [mergeDuplicateWarehouses] collapses them to
// a single survivor while migrating every dependent FK without losing data.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/warehouse_dedup_extension.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  group('WarehouseDedupExtension', () {
    test('dryRun returns empty when no duplicates exist', () async {
      final groups = await db.dryRunDuplicateWarehouseGroups();
      expect(groups, isEmpty);
    });

    test('merge is a no-op when no duplicates exist', () async {
      final removed = await db.mergeDuplicateWarehouses();
      expect(removed, 0);
    });

    test(
        'merges two "المخزن الرئيسي" rows, survivor is the globalId row, '
        'and a dependent stock_movements row is repointed', () async {
      // Seeded DB already has "المخزن الرئيسي" with a deterministic globalId.
      final seeded = await (db.select(db.warehouses)
            ..where((w) => w.name.equals('المخزن الرئيسي')))
          .getSingle();
      expect(seeded.globalId, isNotNull,
          reason: 'sanity: seeded default warehouse carries a globalId');

      // Simulate a server-pulled duplicate with no globalId — the BUG 5b
      // state that accumulates before the sync-time natural-key fallback.
      final dupId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'المخزن الرئيسي',
              globalId: const Value(null),
            ),
          );
      expect(dupId, isNot(seeded.id),
          reason: 'sanity: duplicate must have a different id');

      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(code: 'P-DEDUP', name: 'صنف اختبار'),
          );

      // Plant a dependent row pointing at the DUPLICATE so the merge has
      // something to migrate. `stock_movements.warehouse_id` is a plain FK.
      final movementId = await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              productId: productId,
              warehouseId: dupId,
              movementType: 'purchase',
              quantity: 5,
              balanceAfter: 5,
            ),
          );

      final groups = await db.dryRunDuplicateWarehouseGroups();
      expect(groups, hasLength(1));
      expect((groups.first['ids'] as List).cast<int>().toSet(),
          {seeded.id, dupId});

      final removed = await db.mergeDuplicateWarehouses();
      expect(removed, 1, reason: 'exactly one duplicate row should be deleted');

      final remaining = await (db.select(db.warehouses)
            ..where((w) => w.name.equals('المخزن الرئيسي')))
          .get();
      expect(remaining, hasLength(1),
          reason: 'exactly one "المخزن الرئيسي" should remain after merge');
      expect(remaining.first.id, seeded.id,
          reason: 'survivor must be the seeded row (it carries a globalId)');

      // Dependent stock_movements row must now point at the survivor — no
      // orphan left behind.
      final movement = await (db.select(db.stockMovements)
            ..where((t) => t.id.equals(movementId)))
          .getSingle();
      expect(movement.warehouseId, seeded.id,
          reason:
              'stock_movements FK must have been migrated to the survivor');
    });

    test('merge is idempotent — second call removes nothing', () async {
      await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'المخزن الرئيسي',
              globalId: const Value(null),
            ),
          );
      final firstRemoved = await db.mergeDuplicateWarehouses();
      expect(firstRemoved, 1);

      final secondRemoved = await db.mergeDuplicateWarehouses();
      expect(secondRemoved, 0,
          reason: 'second call on a clean DB must be a no-op');
    });

    test(
        'colliding inventory_balances: survivor value is kept, dup row dropped, '
        'no orphan left', () async {
      final survivor = await (db.select(db.warehouses)
            ..where((w) => w.name.equals('المخزن الرئيسي')))
          .getSingle();
      final dupId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'المخزن الرئيسي',
              globalId: const Value(null),
            ),
          );

      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(code: 'P-COLLIDE', name: 'صنف تصادم'),
          );

      // Same product stocked on BOTH warehouses — the dup's balance
      // collides with the survivor's on the UNIQUE(product_id, warehouse_id)
      // key, so INSERT OR IGNORE keeps the survivor's row and the dup's
      // value is (documented) discarded.
      await db.into(db.inventoryBalances).insert(
            InventoryBalancesCompanion.insert(
              productId: productId,
              warehouseId: survivor.id,
              quantity: const Value(7),
            ),
          );
      await db.into(db.inventoryBalances).insert(
            InventoryBalancesCompanion.insert(
              productId: productId,
              warehouseId: dupId,
              quantity: const Value(99),
            ),
          );

      final removed = await db.mergeDuplicateWarehouses();
      expect(removed, 1);

      final balances = await (db.select(db.inventoryBalances)
            ..where((b) => b.productId.equals(productId)))
          .get();
      expect(balances, hasLength(1),
          reason: 'exactly one balance survives for the (product, survivor)');
      expect(balances.single.warehouseId, survivor.id,
          reason: 'survivor keeps its own balance row');
      expect(balances.single.quantity, 7,
          reason: 'survivor value is kept; the dup value is discarded');

      final orphans = await (db.select(db.inventoryBalances)
            ..where((b) => b.warehouseId.equals(dupId)))
          .get();
      expect(orphans, isEmpty,
          reason: 'no balance row may remain pointing at the deleted dup');
    });
  });
}
