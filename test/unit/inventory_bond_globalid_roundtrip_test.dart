// Spec 129 F4 / T036 — Inventory-bond globalId dedup contract.
//
// Contract (specs/129-mirror-broadcast-discipline/contracts/globalid-schema.md §1):
//   1. The caller (inventory_service.dart) mints ONE UUIDv7 per bond.
//   2. The local DAO accepts it via InventoryBondsCompanion.globalId.
//   3. The server-side postInventoryBond handler dedups against it: if a row
//      with the same globalId already exists, it returns success without
//      re-inserting (idempotent retry).
//
// This test exercises (2) + the dedup half of (3) using an in-memory DB —
// the actual server-handler dedup-by-select is verified by inserting two
// rows with the same globalId and asserting the unique index rejects the
// second.
//
// A full mirror → server → DeltaPull roundtrip (writes on a mirror, forces
// `DeltaPullService.pullTable('inventory_bonds')`, asserts ONE local row) is
// out of scope here because `inventory_bonds` is not currently in
// DeltaPullService.pullTables. The dedup target column + unique index are
// the structural piece that an eventual pull strategy will rely on.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('Spec 129 F4 — inventory_bonds.globalId dedup', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertWarehouseAndBranch() async {
      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'Branch X'),
          );
      final warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'WH X',
              branchId: Value(branchId),
            ),
          );
      return warehouseId;
    }

    test('bond row persists the supplied globalId', () async {
      final warehouseId = await insertWarehouseAndBranch();
      const gid = '0190c4e8-7c6d-7a2e-b9a3-4f6b8c0d1e2f';

      final bondId = await db.createInventoryBond(
        InventoryBondsCompanion.insert(
          bondNumber: 'BND-TEST-1',
          type: const Value('in'),
          warehouseId: warehouseId,
          globalId: const Value(gid),
        ),
      );

      final fetched = await (db.select(db.inventoryBonds)
            ..where((b) => b.id.equals(bondId)))
          .getSingle();
      expect(fetched.globalId, gid);
    });

    test('second insert with the same globalId is rejected (unique constraint)',
        () async {
      final warehouseId = await insertWarehouseAndBranch();
      const gid = '0190c4e8-7c6d-7a2e-b9a3-4f6b8c0d1e30';

      await db.createInventoryBond(
        InventoryBondsCompanion.insert(
          bondNumber: 'BND-TEST-2A',
          type: const Value('in'),
          warehouseId: warehouseId,
          globalId: const Value(gid),
        ),
      );

      // Retried submit on the server must hit the dedup precheck before this
      // INSERT ever runs. If the precheck is bypassed, the unique index is the
      // last line of defence.
      expect(
        () => db.createInventoryBond(
          InventoryBondsCompanion.insert(
            bondNumber: 'BND-TEST-2B',
            type: const Value('in'),
            warehouseId: warehouseId,
            globalId: const Value(gid),
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('two bonds with no globalId both coexist (backward compat)', () async {
      final warehouseId = await insertWarehouseAndBranch();

      final id1 = await db.createInventoryBond(
        InventoryBondsCompanion.insert(
          bondNumber: 'BND-LEGACY-1',
          type: const Value('in'),
          warehouseId: warehouseId,
        ),
      );
      final id2 = await db.createInventoryBond(
        InventoryBondsCompanion.insert(
          bondNumber: 'BND-LEGACY-2',
          type: const Value('in'),
          warehouseId: warehouseId,
        ),
      );

      expect(id1, isNot(equals(id2)));
      final rows = await (db.select(db.inventoryBonds)
            ..where((b) => b.globalId.isNull()))
          .get();
      expect(rows.length, greaterThanOrEqualTo(2));
    });
  });
}
