// ═══════════════════════════════════════════════════════════════════════════
// Spec 136 — server→local party-FK remap (item 7)
// ═══════════════════════════════════════════════════════════════════════════
//
// Two layers exercise the same concern — a transaction row arriving from the
// server carries the SERVER's party id, which may differ from this device's
// LOCAL party id; storing the server id raw makes getPartyStatement (filters
// by the local id) come up empty for that party:
//
//   1. SyncStrategy.resolveLocalPartyId — the fullSync (Tier-3) path, extracted
//      into the base class in this spec (items 3 + 6a).
//   2. DeltaPullService._upsertRow — the REAL inbound path on mirror/client.
//      Driven here via the @visibleForTesting upsertRowForTest hook so the
//      remap runs without a server / ServerProxy.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/delta_pull_service.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

import '../helpers/v195_reservations_db.dart';

/// Minimal concrete strategy so the abstract base's resolveLocalPartyId can be
/// exercised directly.
class _TestStrategy extends SyncStrategy {
  _TestStrategy(super.db);
  @override
  String get tableName => 'test';
  @override
  String get apiEndpoint => '/test';
  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {}
  @override
  Future<int> syncIncremental(DateTime since) async => 0;
  @override
  Future<void> upsert(Insertable record) async {}
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  group('SyncStrategy.resolveLocalPartyId', () {
    test('null / 0 pass through unchanged (no party)', () async {
      final s = _TestStrategy(db);
      expect(await s.resolveLocalPartyId(null), isNull);
      expect(await s.resolveLocalPartyId(0), 0);
    });

    test('direct hit: a server id that exists locally is kept as-is', () async {
      final s = _TestStrategy(db);
      await db.into(db.parties).insert(
            // (id 50, not 5: the seed now holds the J3 system parties too.)
            PartiesCompanion.insert(name: 'Direct', id: const Value(50)),
          );
      expect(await s.resolveLocalPartyId(50), 50);
    });

    test('mapping hit: server id remaps to the local party id', () async {
      final s = _TestStrategy(db);
      // Local party lives under id 5000; server stored it as id 7.
      await db.into(db.parties).insert(
            PartiesCompanion.insert(name: 'Local', id: const Value(5000)),
          );
      await db.storeFkMapping(
        tableName: 'parties',
        localId: 5000,
        remoteId: 7,
        globalId: 'p-uuid',
      );
      expect(await s.resolveLocalPartyId(7), 5000);
    });

    test('unresolved: no local party and no mapping → server id passes through',
        () async {
      final s = _TestStrategy(db);
      expect(await s.resolveLocalPartyId(999), 999);
    });
  });

  group('DeltaPull _upsertRow party-FK remap (safe_transactions)', () {
    test('rewrites a server party_id to the local party id on insert',
        () async {
      DeltaPullService.instance.initialize(db);

      // Local party lives under id 5000; the server stored it as id 7.
      await db.into(db.parties).insert(
            PartiesCompanion.insert(name: 'Supplier', id: const Value(5000)),
          );
      await db.storeFkMapping(
        tableName: 'parties',
        localId: 5000,
        remoteId: 7,
        globalId: 'p-uuid',
      );
      // The safe the voucher points at (auto id — the test DB already seeds
      // a default safe at id 1).
      final safeId =
          await db.into(db.safes).insert(SafesCompanion.insert(name: 'Cash'));

      // Server delta row carries the SERVER party id (7), which doesn't exist
      // locally — only its remote→local mapping does.
      await DeltaPullService.instance.upsertRowForTest('safe_transactions', {
        'id': 9001,
        'voucher_number': 'PV-T1',
        'safe_id': safeId,
        'transaction_type': 'payment',
        'category': 'purchase',
        'amount': 100.0,
        'balance_after': 0.0,
        'party_id': 7,
        'created_at': 1700000000,
        'global_id': 'st-uuid-1',
      });

      final row = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(9001)))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(
        row!.partyId,
        5000,
        reason: 'server party_id 7 must be remapped to local 5000 so '
            'getPartyStatement (filters by local id) finds the voucher',
      );
    });

    test('D-2: table_reservations.party_id is remapped via remote_id_mappings',
        () async {
      DeltaPullService.instance.initialize(db);
      await db.into(db.parties).insert(
            PartiesCompanion.insert(name: 'Cust', id: const Value(5000)),
          );
      await db.storeFkMapping(
        tableName: 'parties',
        localId: 5000,
        remoteId: 7,
        globalId: 'p-uuid-res',
      );
      final tid = await insertTestTable(db, 'T-D2');

      await DeltaPullService.instance.upsertRowForTest('table_reservations', {
        'id': 9101,
        'table_id': tid,
        'customer_name': 'Cust',
        'reservation_time': 1900000000,
        'party_id': 7, // host id — exists locally only through the mapping
        'created_at': 1700000000,
        'global_id': 'res-uuid-1',
      });

      expect((await rowOf(db, 'table_reservations', 9101))['party_id'], 5000);
    });

    test('D-2: bookings.party_id is remapped via remote_id_mappings', () async {
      DeltaPullService.instance.initialize(db);
      await db.into(db.parties).insert(
            PartiesCompanion.insert(name: 'Cust', id: const Value(5001)),
          );
      await db.storeFkMapping(
        tableName: 'parties',
        localId: 5001,
        remoteId: 8,
        globalId: 'p-uuid-bk',
      );
      final svc = await insertTestServiceId(db);

      await DeltaPullService.instance.upsertRowForTest('bookings', {
        'id': 9102,
        'customer_name': 'Cust',
        'party_id': 8,
        'service_id': svc,
        'starts_at': 1900000000,
        'ends_at': 1900001800,
        'global_id': 'bk-uuid-1',
      });

      expect((await rowOf(db, 'bookings', 9102))['party_id'], 5001);
    });

    test('D-2: a reservation party_id that exists locally is not remapped',
        () async {
      DeltaPullService.instance.initialize(db);
      await db.into(db.parties).insert(
            PartiesCompanion.insert(name: 'Cust', id: const Value(60)),
          );
      final tid = await insertTestTable(db, 'T-D2b');
      await DeltaPullService.instance.upsertRowForTest('table_reservations', {
        'id': 9103,
        'table_id': tid,
        'customer_name': 'Cust',
        'reservation_time': 1900000000,
        'party_id': 60,
        'created_at': 1700000000,
        'global_id': 'res-uuid-2',
      });
      expect((await rowOf(db, 'table_reservations', 9103))['party_id'], 60);
    });

    test('a server party_id that already matches locally is left unchanged',
        () async {
      DeltaPullService.instance.initialize(db);

      await db.into(db.parties).insert(
            PartiesCompanion.insert(name: 'Supplier', id: const Value(42)),
          );
      final safeId =
          await db.into(db.safes).insert(SafesCompanion.insert(name: 'Cash'));

      await DeltaPullService.instance.upsertRowForTest('safe_transactions', {
        'id': 9002,
        'voucher_number': 'PV-T2',
        'safe_id': safeId,
        'transaction_type': 'payment',
        'category': 'purchase',
        'amount': 50.0,
        'balance_after': 0.0,
        'party_id': 42,
        'created_at': 1700000000,
        'global_id': 'st-uuid-2',
      });

      final row = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(9002)))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.partyId, 42,
          reason: 'a party id that resolves directly must not be remapped');
    });
  });
}
