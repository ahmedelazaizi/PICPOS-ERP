// Cluster 035 Issue 2 + W1 hardening — PartySyncStrategy regression guards.
//
// Locks in three guarantees added in the 2026-05-12 hardening pass:
//
//   1. Tier C re-link by KNOWN SEED NAMES catches the
//      "delivery-company duplicate after first sync" symptom:
//      a locally-seeded 'اشيائي' (no phone, fresh local globalId from
//      migration v30) MUST collapse onto the server's row instead of
//      producing two rows visible in the customers screen.
//
//   2. lastWriteWins (R5) — when the local row carries a newer
//      `lastModifiedAt` than the server payload, the strategy MUST keep
//      the local version. Otherwise a cashier's recent phone-number edit
//      is silently overwritten on the next sync pass.
//
//   3. lastWriteWins (R5) — when the server is newer, the update applies.
//
// All three are ENGINEERING_GUIDELINES.md R5 invariants. A regression in any of them
// equals silent data loss across multi-branch deployments.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/strategies/party_sync_strategy.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

void main() {
  late AppDatabase db;
  late PartySyncStrategy strategy;

  setUp(() async {
    db = AppDatabase.forTesting();
    strategy = PartySyncStrategy(db);
    // The test DB pre-seeds 'طلبات' / 'كريم' / 'اشيائي' via
    // `seedDeliveryCompanyParties` during DB open. Each test below
    // controls its own row layout, so wipe parties first to avoid
    // colliding with the seeded rows.
    await db.delete(db.parties).go();
  });

  tearDown(() => db.close());

  group('PartySyncStrategy — conflict policy declaration', () {
    test('declares lastWriteWins (R5 — multi-branch party edits)', () {
      expect(strategy.conflictPolicy, ConflictPolicy.lastWriteWins);
    });
  });

  group('Tier C — known-seed-name dedup (Cluster 035 / Issue 2)', () {
    test(
        'collapses local seeded "اشيائي" onto server row with different globalId',
        () async {
      // Plant a local seeded delivery_company (mimics what migration v30
      // does on the client) with NO phone and a local-only globalId.
      final localId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'اشيائي',
              isDeliveryCompany: const Value(true),
              priceLevel: const Value('ashyae'),
              globalId: const Value('local-only-uuid-A'),
            ),
          );

      // Server sends its OWN copy with a DIFFERENT globalId and
      // priceLevel='default' (so Tier B priceLevel match misses).
      await strategy.syncFromJson({
        'parties': [
          {
            'id': 42, // server id (must NOT become the local id)
            'globalId': 'server-uuid-B',
            'name': 'اشيائي',
            'phone': null,
            'isCustomer': true,
            'isDeliveryCompany': true,
            'priceLevel': 'default',
            'isActive': true,
            'balance': 0,
            'creditLimit': 999999,
            'fixedDiscount': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
        ],
      });

      // Expect EXACTLY ONE row named 'اشيائي' — local id preserved, the
      // server's globalId is now stamped onto it.
      final rows = await (db.select(db.parties)
            ..where((p) => p.name.equals('اشيائي')))
          .get();
      expect(rows, hasLength(1),
          reason: 'Tier C must collapse seeded duplicate onto local row');
      expect(rows.single.id, localId,
          reason: 'Local id must be preserved (existing FKs still valid)');
      expect(rows.single.globalId, 'server-uuid-B',
          reason: 'Server globalId now wins via the in-place update');
    });

    test('Tier C does NOT touch non-seeded delivery companies', () async {
      // Plant a delivery_company with a non-seed name (merchant-created).
      final localId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'شركة توصيل مخصصة',
              isDeliveryCompany: const Value(true),
              priceLevel: const Value('default'),
              globalId: const Value('local-custom-uuid'),
            ),
          );

      // Server sends a different delivery_company with the same name — but
      // since the name is NOT in the known-seed set, Tier C must NOT fire.
      // Expectation: a SECOND row is inserted (the strategy fell through
      // to the genuine-new-party branch).
      await strategy.syncFromJson({
        'parties': [
          {
            'id': 99,
            'globalId': 'server-custom-uuid',
            'name': 'شركة توصيل مخصصة',
            'phone': null,
            'isCustomer': true,
            'isDeliveryCompany': true,
            'priceLevel': 'default',
            'isActive': true,
            'balance': 0,
            'creditLimit': 0,
            'fixedDiscount': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
        ],
      });

      final rows = await (db.select(db.parties)
            ..where((p) => p.name.equals('شركة توصيل مخصصة')))
          .get();
      // Two rows — the original local + the server one. Tier C is
      // intentionally restricted to known seed names to avoid
      // accidentally merging two legitimately different parties.
      expect(rows, hasLength(2),
          reason: 'non-seed names must NOT trigger Tier C re-link');
      expect(rows.map((r) => r.id), containsAll([localId, isNot(localId)]));
    });
  });

  group('lastWriteWins (R5)', () {
    test('keeps local row when local lastModifiedAt is newer than server',
        () async {
      final localUpdated = DateTime.utc(2026, 5, 12, 10);
      final serverUpdated = DateTime.utc(2026, 5, 12, 9); // older

      final localId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'أحمد محمد',
              globalId: const Value('shared-uuid'),
              phone: const Value('0501234567'), // local edit (newer)
              lastModifiedAt: Value(localUpdated),
            ),
          );

      await strategy.syncFromJson({
        'parties': [
          {
            'id': 50,
            'globalId': 'shared-uuid',
            'name': 'أحمد محمد',
            'phone': '0500000000', // older value
            'isCustomer': true,
            'isDeliveryCompany': false,
            'priceLevel': 'default',
            'isActive': true,
            'balance': 0,
            'creditLimit': 0,
            'fixedDiscount': 0,
            'updatedAt': serverUpdated.toIso8601String(),
          },
        ],
      });

      final row = await (db.select(db.parties)
            ..where((p) => p.id.equals(localId)))
          .getSingle();
      expect(row.phone, '0501234567',
          reason:
              'lastWriteWins: local newer edit MUST NOT be overwritten by older server snapshot');
    });

    test('applies server row when server is newer', () async {
      final localUpdated = DateTime.utc(2026, 5, 12, 9);
      final serverUpdated = DateTime.utc(2026, 5, 12, 10); // newer

      final localId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'سعيد علي',
              globalId: const Value('shared-uuid-2'),
              phone: const Value('0509999999'),
              lastModifiedAt: Value(localUpdated),
            ),
          );

      await strategy.syncFromJson({
        'parties': [
          {
            'id': 51,
            'globalId': 'shared-uuid-2',
            'name': 'سعيد علي',
            'phone': '0507777777', // newer
            'isCustomer': true,
            'isDeliveryCompany': false,
            'priceLevel': 'default',
            'isActive': true,
            'balance': 0,
            'creditLimit': 0,
            'fixedDiscount': 0,
            'updatedAt': serverUpdated.toIso8601String(),
          },
        ],
      });

      final row = await (db.select(db.parties)
            ..where((p) => p.id.equals(localId)))
          .getSingle();
      expect(row.phone, '0507777777',
          reason: 'lastWriteWins: server newer edit MUST be applied');
    });
  });
}
