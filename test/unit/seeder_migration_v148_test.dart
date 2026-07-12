// Spec 129 F6 / T050 — v148 backfill: earliest-id wins.
//
// Simulates a pre-v148 install that already has multiple rows with the same
// canonical name (e.g. two branches named "الفرع الرئيسي" from a botched
// sync, ids 1 and 5) and one user-renamed row (id 3). After v148 ships, the
// migration's backfill query
//   UPDATE branches SET is_system_default = 1
//   WHERE id = (SELECT MIN(id) FROM branches WHERE name = ?)
// flags ONLY the earliest-id matching row. User-renamed rows and later
// duplicates stay false.
//
// We exercise the migration SQL directly via customStatement against an
// in-memory database to keep the test fast and harness-free.
//
// Run: `flutter test test/unit/seeder_migration_v148_test.dart`

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart';

void main() {
  group('Spec 129 F6 / v148 migration — earliest-id wins backfill', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
      // `AppDatabase.forTesting()` runs the standard seeder on first open,
      // so the branches/parties tables are NOT empty. Wipe them so each
      // test starts from a known pristine state and the migration's
      // MIN(id) result is fully owned by the test data we insert.
      await db.delete(db.branches).go();
      await db.delete(db.parties).go();
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertBranch(String name, {bool flagged = false}) async {
      return db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: name,
              isSystemDefault: Value(flagged),
            ),
          );
    }

    test('two duplicates + one renamed → earliest-id wins; renamed stays false',
        () async {
      // Simulate pre-v148 chaos: two rows with the canonical seeded name plus
      // a user-renamed survivor.
      final id1 = await insertBranch('الفرع الرئيسي');
      final id2 = await insertBranch('إدارة عامة');   // user-renamed
      final id3 = await insertBranch('الفرع الرئيسي'); // botched duplicate

      // Apply the backfill query verbatim from
      // lib/data/database/migrations/epoch_3.dart §v148.
      await db.customStatement(
        'UPDATE branches SET is_system_default = 1 '
        'WHERE id = (SELECT MIN(id) FROM branches WHERE name = ?)',
        ['الفرع الرئيسي'],
      );

      final rows = await db.select(db.branches).get();
      final byId = {for (final r in rows) r.id: r};
      expect(byId[id1]!.isSystemDefault, isTrue,
          reason: 'earliest-id canonical row gets the flag');
      expect(byId[id2]!.isSystemDefault, isFalse,
          reason: 'user-renamed row keeps the flag false');
      expect(byId[id3]!.isSystemDefault, isFalse,
          reason: 'later duplicate keeps the flag false (only MIN(id) wins)');
    });

    test('no row matches the canonical name → no flag is set anywhere',
        () async {
      await insertBranch('شيء مخصص');
      await insertBranch('فرع آخر');

      await db.customStatement(
        'UPDATE branches SET is_system_default = 1 '
        'WHERE id = (SELECT MIN(id) FROM branches WHERE name = ?)',
        ['الفرع الرئيسي'],
      );

      final flagged = await (db.select(db.branches)
            ..where((b) => b.isSystemDefault.equals(true)))
          .get();
      expect(flagged, isEmpty,
          reason:
              'no canonical-name row exists → migration leaves all flags 0');
    });

    test('parties backfill is filtered by is_delivery_company=true', () async {
      // A regular customer who happens to be named "طلبات" must NOT be
      // accidentally promoted by the migration.
      final regularId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'طلبات', // same name, but NOT a delivery company
              isCustomer: const Value(true),
              isDeliveryCompany: const Value(false),
            ),
          );
      final deliveryId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'طلبات',
              isCustomer: const Value(true),
              isDeliveryCompany: const Value(true),
            ),
          );

      // Backfill query verbatim from the v148 migration.
      await db.customStatement(
        'UPDATE parties SET is_system_default = 1 '
        'WHERE id = (SELECT MIN(id) FROM parties '
        '            WHERE name = ? AND is_delivery_company = 1)',
        ['طلبات'],
      );

      final regular = await (db.select(db.parties)
            ..where((p) => p.id.equals(regularId)))
          .getSingle();
      final delivery = await (db.select(db.parties)
            ..where((p) => p.id.equals(deliveryId)))
          .getSingle();
      expect(regular.isSystemDefault, isFalse,
          reason: 'is_delivery_company=false → not promoted');
      expect(delivery.isSystemDefault, isTrue,
          reason: 'is_delivery_company=true → promoted');
    });
  });
}
