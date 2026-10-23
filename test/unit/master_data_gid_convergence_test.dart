// ═══════════════════════════════════════════════════════════════════════════
// Spec 136 ISS-1 + ISS-2 — Master-data globalId convergence guards.
//
// Completes Spec 132 (master-data globalId threading). Pre-fix every seeder
// minted a fresh random UuidV7.generate() gid per seeded default, so the PG
// server and the SQLite client held DIFFERENT gids for the same logical row
// ("الفرع الرئيسي": server 019e821e… vs client 019e8209…). The sync layer's
// Tier-1 globalId match therefore always missed → name fallback → the server-
// side duplicate guard tripped (ISS-1). fiscal_years were worse: NULL on both
// sides.
//
// These tests pin the fix:
//   1. deriveSeedGlobalId / deriveFiscalYearGlobalId are deterministic — two
//      independent installs derive the SAME gid for the same logical row.
//   2. Two freshly-seeded in-memory databases (server-sim + client-sim)
//      converge: their seeded branch / warehouse / safe / fiscal-year gids are
//      EQUAL and non-null.
//   3. The NULL-only backfill contract: a NULL gid is healed to the
//      deterministic value; a non-null gid is never overwritten (FR-011).
//   4. Structural: seeded system-default sites no longer use the random
//      generate() gid.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/utils/uuid_v7.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Spec 136 — deterministic gid derivation', () {
    test('deriveSeedGlobalId is deterministic for the same (table, seedKey)',
        () {
      final a = UuidV7.deriveSeedGlobalId(
          table: 'branches', seedKey: 'الفرع الرئيسي');
      final b = UuidV7.deriveSeedGlobalId(
          table: 'branches', seedKey: 'الفرع الرئيسي');
      expect(a, equals(b),
          reason: 'server + client must derive the SAME gid for one row');
      expect(UuidV7.isValid(a), isTrue, reason: 'must be a valid UUID');
    });

    test('deriveSeedGlobalId differs per table and per seedKey', () {
      final branchMain = UuidV7.deriveSeedGlobalId(
          table: 'branches', seedKey: 'الفرع الرئيسي');
      final whMain = UuidV7.deriveSeedGlobalId(
          table: 'warehouses', seedKey: 'الفرع الرئيسي');
      final branchOther =
          UuidV7.deriveSeedGlobalId(table: 'branches', seedKey: 'فرع آخر');
      expect(branchMain, isNot(equals(whMain)),
          reason: 'same key, different table → different gid');
      expect(branchMain, isNot(equals(branchOther)),
          reason: 'same table, different key → different gid');
    });

    test('deriveFiscalYearGlobalId is deterministic for the same natural key',
        () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 12, 31, 23, 59, 59);
      final a = UuidV7.deriveFiscalYearGlobalId(
          name: 'السنة المالية 2026', startDate: start, endDate: end);
      final b = UuidV7.deriveFiscalYearGlobalId(
          name: 'السنة المالية 2026', startDate: start, endDate: end);
      expect(a, equals(b));
      expect(UuidV7.isValid(a), isTrue);
      // A different year (different natural key) must differ.
      final c = UuidV7.deriveFiscalYearGlobalId(
          name: 'السنة المالية 2027',
          startDate: DateTime(2027, 1, 1),
          endDate: DateTime(2027, 12, 31, 23, 59, 59));
      expect(a, isNot(equals(c)));
    });

    test('fiscal-year gid ignores time-of-day — seed and close-year paths '
        'converge (review P1-1/P1-2)', () {
      // Seeder builds Jan-1 00:00:00 .. Dec-31 23:59:59.
      final seedPath = UuidV7.deriveFiscalYearGlobalId(
          name: 'السنة المالية 2027',
          startDate: DateTime(2027, 1, 1),
          endDate: DateTime(2027, 12, 31, 23, 59, 59));
      // closeFiscalYear builds nextStart = endDate(+1 day) = Jan-1 23:59:59
      // and nextEnd = Dec-31 00:00:00. With date-component keying both paths
      // MUST derive the same gid (was epoch-based → diverged).
      final closeYearPath = UuidV7.deriveFiscalYearGlobalId(
          name: 'السنة المالية 2027',
          startDate: DateTime(2027, 1, 1, 23, 59, 59),
          endDate: DateTime(2027, 12, 31));
      expect(seedPath, equals(closeYearPath),
          reason: 'close-year and seed FY for the same year must converge on '
              'one deterministic gid regardless of time-of-day.');
    });

    test('close-year path uses the canonical "السنة المالية" name (review P1-1)',
        () {
      final src = File('lib/data/database/daos/accounting_fiscal_dao.dart')
          .readAsStringSync();
      expect(src, contains(r"'السنة المالية ${nextStart.year}'"),
          reason: 'a bare year-number name would derive a different gid + '
              'Tier-2 key than the seeded FY for the same year.');
    });
  });

  group('Spec 136 — two installs converge on seeded gids', () {
    late AppDatabase server;
    late AppDatabase client;

    setUp(() async {
      // Two independent in-memory databases — each runs its own seeder on
      // first access, exactly as a fresh server and a fresh standalone would.
      server = AppDatabase.forTesting();
      client = AppDatabase.forTesting();
    });

    tearDown(() async {
      await server.close();
      await client.close();
    });

    Future<String?> seededBranchGid(AppDatabase db) async {
      final row = await (db.select(db.branches)
            ..where((b) => b.name.equals('الفرع الرئيسي'))
            ..limit(1))
          .getSingleOrNull();
      return row?.globalId;
    }

    test('seeded main branch gids are EQUAL and non-null across installs',
        () async {
      final s = await seededBranchGid(server);
      final c = await seededBranchGid(client);
      expect(s, isNotNull, reason: 'seeded branch must carry a gid');
      expect(c, isNotNull);
      expect(s, equals(c),
          reason: 'deterministic seed gid must converge server↔client '
              '(this is what makes sync Tier-1 match instead of name fallback)');
      // And it equals the pure-derivation value.
      expect(
          s,
          equals(UuidV7.deriveSeedGlobalId(
              table: 'branches', seedKey: 'الفرع الرئيسي')));
    });

    test('seeded safe gids converge across installs', () async {
      Future<String?> cashSafe(AppDatabase db) async {
        final row = await (db.select(db.safes)
              ..where((x) => x.safeType.equals('cash'))
              ..limit(1))
            .getSingleOrNull();
        return row?.globalId;
      }

      final s = await cashSafe(server);
      final c = await cashSafe(client);
      expect(s, isNotNull);
      expect(s, equals(c));
    });

    test('seeded fiscal year gids converge across installs', () async {
      Future<String?> fyGid(AppDatabase db) async {
        final row = await (db.select(db.fiscalYears)..limit(1))
            .getSingleOrNull();
        return row?.globalId;
      }

      final s = await fyGid(server);
      final c = await fyGid(client);
      expect(s, isNotNull,
          reason: 'fiscal year must carry a gid (was NULL/NULL in the field)');
      expect(s, equals(c));
    });
  });

  group('Spec 136 — NULL-only backfill contract', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('a NULL gid is healed to the deterministic value; non-null untouched',
        () async {
      // Force a NULL gid on the seeded fiscal year (simulating a pre-globalId
      // upgraded row), then replay the backfill's NULL-only UPDATE.
      final fy = await (db.select(db.fiscalYears)..limit(1)).getSingle();
      await (db.update(db.fiscalYears)..where((f) => f.id.equals(fy.id)))
          .write(const FiscalYearsCompanion(globalId: Value(null)));
      final cleared =
          await (db.select(db.fiscalYears)..where((f) => f.id.equals(fy.id)))
              .getSingle();
      expect(cleared.globalId, isNull);

      // The backfill's exact contract: UPDATE ... WHERE global_id IS NULL.
      final gid = UuidV7.deriveFiscalYearGlobalId(
          name: cleared.name,
          startDate: cleared.startDate,
          endDate: cleared.endDate);
      await db.customStatement(
        'UPDATE fiscal_years SET global_id = ? WHERE id = ? AND global_id IS NULL',
        [gid, cleared.id],
      );
      final healed =
          await (db.select(db.fiscalYears)..where((f) => f.id.equals(fy.id)))
              .getSingle();
      expect(healed.globalId, equals(gid),
          reason: 'NULL row must be healed to the deterministic gid');

      // Re-running must NOT change a now-non-null gid (idempotent + FR-011).
      await db.customStatement(
        'UPDATE fiscal_years SET global_id = ? WHERE id = ? AND global_id IS NULL',
        ['DIFFERENT-VALUE', healed.id],
      );
      final reread =
          await (db.select(db.fiscalYears)..where((f) => f.id.equals(fy.id)))
              .getSingle();
      expect(reread.globalId, equals(gid),
          reason: 'non-null gid must never be overwritten (Spec 132 FR-011)');
    });
  });

  group('Spec 136 — structural: seeders use deterministic gids', () {
    test('both seeders reference deriveSeedGlobalId', () {
      for (final path in const [
        'lib/data/database/database_seeder.dart',
        'lib/data/database/database_seeder_postgres.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('deriveSeedGlobalId'), isTrue,
            reason: '$path must derive seeded gids deterministically');
      }
    });

    test('seeded system-default sites no longer mint random generate() gids',
        () {
      // Only the out-of-scope identity rows may still use generate():
      //   database_seeder.dart       → admin user (1)
      //   database_seeder_postgres   → roles + admin user (2)
      // Any increase means a seeded master-data default regressed back to a
      // per-install random gid — which is exactly the ISS-2 root cause.
      final sqlite =
          File('lib/data/database/database_seeder.dart').readAsStringSync();
      final pg = File('lib/data/database/database_seeder_postgres.dart')
          .readAsStringSync();
      final reGen = RegExp(r'UuidV7\.generate\(\)');
      expect(reGen.allMatches(sqlite).length, lessThanOrEqualTo(1),
          reason: 'database_seeder.dart should only use generate() for the '
              'admin user');
      expect(reGen.allMatches(pg).length, lessThanOrEqualTo(2),
          reason: 'database_seeder_postgres.dart should only use generate() '
              'for roles + admin user');
    });
  });
}
