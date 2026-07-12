// ═══════════════════════════════════════════════════════════════════════════
// SEED IDEMPOTENCY TEST
// ═══════════════════════════════════════════════════════════════════════════
//
// Guards the property we rely on for self-healing existing installs:
// calling `seedInitialDataPostgresAtomic()` twice on the same DB must not
// create duplicates and must not throw.
//
// Runs against SQLite in-memory via `AppDatabase.forTesting()`. The seeder's
// helpers are dialect-agnostic (plain Drift APIs + one raw INSERT for the
// chart of accounts), so the idempotency guarantees verified here hold on
// PostgreSQL as well.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:ural_erp/data/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  group('seedInitialDataPostgresAtomic — idempotency', () {
    test('baseline is present after atomic seed', () async {
      // `AppDatabase.forTesting()` already runs the SQLite seeder in
      // beforeOpen, so the baseline is present before we even call the
      // atomic seeder. Still, the atomic seeder must not throw and must
      // leave the DB in a valid state.
      await db.seedInitialDataPostgresAtomic();

      final users = await db.select(db.users).get();
      expect(users.length, greaterThanOrEqualTo(1));
      expect(users.any((u) => u.username == 'admin'), isTrue);

      final branches = await db.select(db.branches).get();
      expect(branches.length, greaterThanOrEqualTo(1));

      final warehouses = await db.select(db.warehouses).get();
      expect(warehouses.length, greaterThanOrEqualTo(1));

      final cats = await db.select(db.categories).get();
      expect(cats.any((c) => c.name == 'عام'), isTrue);

      final acct = await db.select(db.accounts).get();
      expect(acct.length, greaterThan(50),
          reason: 'chart of accounts should be populated');
    });

    test('second run is a no-op — no duplicates', () async {
      // First seed populates (or confirms already-populated state).
      final first = await db.seedInitialDataPostgresAtomic();

      // Since forTesting() already ran the SQLite seeder, expected inserts
      // from the atomic seeder are 0.
      expect(first.admin, 0,
          reason: 'admin already exists from forTesting() beforeOpen');

      // Capture counts after first atomic seed.
      final countsBefore = {
        'users': (await db.select(db.users).get()).length,
        'branches': (await db.select(db.branches).get()).length,
        'warehouses': (await db.select(db.warehouses).get()).length,
        'categories': (await db.select(db.categories).get()).length,
        'units': (await db.select(db.units).get()).length,
        'safes': (await db.select(db.safes).get()).length,
        'accounts': (await db.select(db.accounts).get()).length,
        'settings': (await db.select(db.settings).get()).length,
      };

      // Second seed must not create duplicates and must not throw.
      final second = await db.seedInitialDataPostgresAtomic();
      expect(second.admin, 0,
          reason: 'admin already exists — no insert should happen');
      expect(second.branch, 0);
      expect(second.warehouse, 0);
      expect(second.category, 0);
      expect(second.units, 0);
      expect(second.safes, 0);
      expect(second.accounts, 0,
          reason: 'chart of accounts already populated — skip');

      // Counts after second seed must match counts after first.
      final countsAfter = {
        'users': (await db.select(db.users).get()).length,
        'branches': (await db.select(db.branches).get()).length,
        'warehouses': (await db.select(db.warehouses).get()).length,
        'categories': (await db.select(db.categories).get()).length,
        'units': (await db.select(db.units).get()).length,
        'safes': (await db.select(db.safes).get()).length,
        'accounts': (await db.select(db.accounts).get()).length,
        'settings': (await db.select(db.settings).get()).length,
      };
      expect(countsAfter, countsBefore,
          reason: 'running the atomic seeder twice must be idempotent');
    });

    test('third run after a manual data mutation still is stable', () async {
      // Seed once.
      await db.seedInitialDataPostgresAtomic();

      // Simulate the user editing a setting — the seeder should NOT overwrite
      // their edit on the next run.
      await db.customStatement(
        "UPDATE settings SET value = ? WHERE key = 'company_name'",
        ['My Custom Company'],
      );

      // Run again.
      await db.seedInitialDataPostgresAtomic();

      final row = await db.customSelect(
        "SELECT value FROM settings WHERE key = 'company_name'",
      ).getSingle();
      expect(row.data['value'], 'My Custom Company',
          reason: 'user-edited settings must be preserved across re-seeds');
    });

    test('verifyPostgresBaseline returns ok after a full seed', () async {
      await db.seedInitialDataPostgresAtomic();
      final check = await db.verifyPostgresBaseline();
      expect(check.ok, isTrue,
          reason: 'baseline check should pass after seeding. '
              'missing=${check.missing}');
    });

    test('verifyPostgresBaseline flags an empty DB', () async {
      // Note: AppDatabase.forTesting() triggers the full beforeOpen
      // lifecycle, which on SQLite runs `seedInitialData()` — so the DB is
      // not actually empty. We verify by wiping a table and checking.
      await db.seedInitialDataPostgresAtomic();

      // Wipe branches to simulate a broken baseline.
      await db.customStatement('DELETE FROM branches');

      final check = await db.verifyPostgresBaseline();
      expect(check.ok, isFalse);
      expect(check.missing.any((m) => m.startsWith('branches')), isTrue);
    });
  });
}
