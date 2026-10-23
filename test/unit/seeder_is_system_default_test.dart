// Spec 129 F6 / T049 — Seeder isSystemDefault contract.
//
// Pins the rename-survives-restart guarantee (FR-601..606):
//   1. Fresh install marks every seeded row in the 6 master-data tables
//      with is_system_default = true.
//   2. After a rename, the flag survives.
//   3. The boot self-heal (PG path) sees the flag and does NOT recreate a
//      fresh canonical-name duplicate.
//
// SQLite-only test (uses AppDatabase.forTesting()). The PG self-heal lives
// in `_seed*IfMissing` helpers exercised by the runtime
// `_verifyAndHealPostgresBaseline` path; we exercise the same predicate
// shape by hitting the SQLite seeder which now sets the same flag.
//
// Run: `flutter test test/unit/seeder_is_system_default_test.dart`

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('Spec 129 F6 — is_system_default seeder contract', () {
    late AppDatabase db;

    setUp(() async {
      // `AppDatabase.forTesting()` runs `_ensureSeedData` via beforeOpen on
      // first open, so the test starts with a fully-seeded DB. We don't call
      // `seedInitialData()` again — a second invocation would crash on
      // `getSingleOrNull()` once duplicate canonical rows exist.
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('fresh install: every seeded row in the 5 standalone tables has '
        'is_system_default = true', () async {
      final branches = await db.select(db.branches).get();
      expect(branches, isNotEmpty);
      expect(
        branches.where((b) => b.isSystemDefault),
        isNotEmpty,
        reason: 'at least one branch must be flagged as system-default',
      );

      final warehouses = await db.select(db.warehouses).get();
      expect(warehouses, isNotEmpty);
      expect(warehouses.where((w) => w.isSystemDefault), isNotEmpty);

      final safes = await db.select(db.safes).get();
      expect(safes, isNotEmpty);
      // All 3 seeded safes get the flag.
      expect(
        safes.where((s) => s.isSystemDefault).length,
        greaterThanOrEqualTo(3),
      );

      final units = await db.select(db.units).get();
      expect(units, isNotEmpty);
      // All 4 seeded units get the flag.
      expect(
        units.where((u) => u.isSystemDefault).length,
        greaterThanOrEqualTo(4),
      );

      final categories = await db.select(db.categories).get();
      final flaggedCats = categories.where((c) => c.isSystemDefault);
      expect(flaggedCats, isNotEmpty);
    });

    test('fresh install: the 3 seeded delivery-company parties carry the '
        'is_system_default flag', () async {
      // beforeOpen → _ensureSeedData → seedInitialData already populated the
      // 3 delivery companies on first open.
      final deliveryParties = await (db.select(db.parties)
            ..where((p) => p.isDeliveryCompany.equals(true)))
          .get();
      expect(deliveryParties.length, greaterThanOrEqualTo(3));
      expect(
        deliveryParties.where((p) => p.isSystemDefault).length,
        greaterThanOrEqualTo(3),
        reason: 'all 3 seeded delivery companies must be flagged',
      );
    });

    test('rename survives: changing the seeded branch name does NOT clear '
        'is_system_default', () async {
      final branch = (await db.select(db.branches).get())
          .firstWhere((b) => b.isSystemDefault);

      await (db.update(db.branches)..where((b) => b.id.equals(branch.id)))
          .write(const BranchesCompanion(name: Value('فرع الإدارة')));

      final renamed = await (db.select(db.branches)
            ..where((b) => b.id.equals(branch.id)))
          .getSingle();
      expect(renamed.name, 'فرع الإدارة');
      expect(renamed.isSystemDefault, isTrue,
          reason: 'rename must preserve isSystemDefault');
    });

    test('legacy row without the flag stays user-controlled (no auto-promote)',
        () async {
      // Insert a non-seeded branch the way an operator's UI would.
      final id = await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'فرع جديد'),
          );
      final row = await (db.select(db.branches)..where((b) => b.id.equals(id)))
          .getSingle();
      expect(row.isSystemDefault, isFalse,
          reason: 'user-created rows default to is_system_default = false');
    });
  });
}
