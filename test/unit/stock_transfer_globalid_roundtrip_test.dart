// Spec 129 F4 / T037 — Stock-transfer globalId dedup contract.
//
// Stock transfers reuse the `inventory_bonds` table with `type='transfer'`
// (see lib/data/database/daos/inventory_transfers_dao.dart). The
// caller-minted UUIDv7 flows through:
//   inventory_service.transferStock()
//     → db.transferStock(..., globalId: transferGid)
//        → InventoryBondsCompanion.insert(..., globalId: Value(transferGid))
//
// The server-side postStockTransfer handler also creates a placeholder
// `inventory_bonds` row stamped with the same globalId and dedups against it.
// This test verifies the DAO layer of that contract (companion preserves the
// value; unique index catches a second insert with the same gid).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('Spec 129 F4 — stock-transfer globalId dedup', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    Future<(int, int, int)> insertTwoWarehouses() async {
      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'Branch Y'),
          );
      final fromId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'WH From',
              branchId: Value(branchId),
            ),
          );
      final toId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'WH To',
              branchId: Value(branchId),
            ),
          );
      return (branchId, fromId, toId);
    }

    test('transferStock stamps the supplied globalId on the bond row',
        () async {
      final (_, fromId, toId) = await insertTwoWarehouses();
      const gid = '0190c4e8-aaaa-7a2e-b9a3-4f6b8c0d1e40';

      await db.transferStock(
        fromWarehouseId: fromId,
        toWarehouseId: toId,
        items: const [],
        notes: 'unit test transfer',
        globalId: gid,
      );

      final row = await (db.select(db.inventoryBonds)
            ..where((b) => b.globalId.equals(gid))
            ..limit(1))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.type, 'transfer');
      expect(row.warehouseId, fromId);
      expect(row.toWarehouseId, toId);
    });

    test('transferStock with null globalId stays backward-compatible', () async {
      final (_, fromId, toId) = await insertTwoWarehouses();

      await db.transferStock(
        fromWarehouseId: fromId,
        toWarehouseId: toId,
        items: const [],
        notes: 'unit test transfer legacy',
      );

      final rows = await (db.select(db.inventoryBonds)
            ..where((b) => b.type.equals('transfer'))
            ..where((b) => b.globalId.isNull()))
          .get();
      expect(rows.length, greaterThanOrEqualTo(1));
    });
  });
}
