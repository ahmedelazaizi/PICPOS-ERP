// Spec 150 — BUG 5a: duplicate "الفرع الرئيسي" / "المخزن الرئيسي" creation
// prevention.
//
// Two regressions this pins (see specs/150-field-fixes/diagnosis.md):
//   1. Seeder heal — the FIL-4 (spec 149) gate inserted a fresh canonical
//      branch whenever no row carried is_system_default=true, even if an
//      unflagged row with the same name already existed (flag lost via
//      rename / trailing-space / a v148 backfill exact-name miss).
//      seedDefaultBranchAndWarehouse() now re-flags that row instead of
//      inserting a second one.
//   2. Display dedup — getBranches() (the DAO read the branch pickers use)
//      now collapses same-name duplicates defensively, preferring the
//      isSystemDefault row.
//
// Deliberately does NOT call seedInitialData() a second time:
// seedRolesAndPermissions() has no existence guard, so a second full
// invocation duplicates every role and crashes the later getSingleOrNull()
// role lookups (see seeder_is_system_default_test.dart's comment).
// seedDefaultBranchAndWarehouse() is the isolated entry point instead.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('Spec 150 BUG 5a — duplicate main branch prevention', () {
    late AppDatabase db;

    setUp(() async {
      // AppDatabase.forTesting() runs the full seeder via beforeOpen on
      // first open, so we already start with a flagged "الفرع الرئيسي".
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('heals an unflagged main branch instead of inserting a duplicate',
        () async {
      // Simulate the FIL-4 regression: the flag is lost (rename /
      // trailing-space / backfill miss) but the row itself survives.
      await (db.update(db.branches)
            ..where((b) => b.name.equals('الفرع الرئيسي')))
          .write(const BranchesCompanion(isSystemDefault: Value(false)));

      await db.seedDefaultBranchAndWarehouse();

      final mainBranches = await (db.select(db.branches)
            ..where((b) => b.name.equals('الفرع الرئيسي')))
          .get();

      expect(mainBranches, hasLength(1),
          reason:
              'the gate must heal the existing row, not insert a second one');
      expect(mainBranches.single.isSystemDefault, isTrue);
    });

    test(
        'getBranches collapses same-name duplicates, preferring the flagged row',
        () async {
      final flagged = await (db.select(db.branches)
            ..where((b) => b.name.equals('الفرع الرئيسي')))
          .getSingle();
      expect(flagged.isSystemDefault, isTrue); // sanity: auto-seed flagged it

      // Simulate the BUG 5 duplicate directly — an unflagged second row
      // sharing the same (trimmed) name, e.g. from the wizard blind-create
      // this spec also fixes.
      await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'الفرع الرئيسي'),
          );

      final picked = await db.getBranches();
      final mains = picked.where((b) => b.name.trim() == 'الفرع الرئيسي');

      expect(mains, hasLength(1));
      expect(mains.single.id, flagged.id);
      expect(mains.single.isSystemDefault, isTrue);
    });
  });
}
