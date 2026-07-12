/// Spec 003 — Sync & Dedup Regression Tests
///
/// Regression coverage for:
///   - ClientFirstSyncService (happy path, failure, idempotency)
///   - BranchSyncStrategy (3-tier dedup + new-row insert)
///   - PartySyncStrategy (Tier A name+phone, Tier B delivery priceLevel,
///     name-only no-merge guard)
///
/// All tests run against AppDatabase.forTesting() (in-memory SQLite).
/// No network calls. DiagnosticLogger is set to test mode so SYNC-WARN
/// entries are captured in-memory instead of being written to disk.
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/client_first_sync_service.dart';
import 'package:ural_erp/services/sync/strategies/branch_sync_strategy.dart';
import 'package:ural_erp/services/sync/strategies/party_sync_strategy.dart';
import 'package:ural_erp/services/sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test doubles
// ─────────────────────────────────────────────────────────────────────────────

/// Minimal SyncService subclass with a controllable fullSync() return value.
/// Declared here so it is never shipped to production.
class _FakeSyncService extends SyncService {
  final SyncResult _result;

  _FakeSyncService(AppDatabase db, {required SyncResult result})
      : _result = result,
        super(serverUrl: 'http://fake-server', localDb: db);

  @override
  Future<SyncResult> fullSync() async => _result;
}

/// SyncService variant that always throws on fullSync().
class _ThrowingSyncService extends SyncService {
  _ThrowingSyncService(AppDatabase db)
      : super(serverUrl: 'http://fake-server', localDb: db);

  @override
  Future<SyncResult> fullSync() async =>
      throw Exception('Simulated sync failure');
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared state
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    DiagnosticLogger.enableTestMode();
  });

  tearDown(() async {
    SyncService.clearInstance();
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ClientFirstSyncService — Happy Path
  // ═══════════════════════════════════════════════════════════════════════════

  group('ClientFirstSyncService — happy path', () {
    test('wipe → sync → sets flag and returns tablesSynced', () async {
      // Seed a branch row to represent locally-seeded data that should be
      // wiped by performFirstSync before the pull from the server.
      await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'الفرع المحلي المؤقت'),
          );

      final svc = ClientFirstSyncService(db: db);
      final fakeSyncSvc = _FakeSyncService(
        db,
        result: SyncResult(success: true, message: 'ok', itemsSynced: 3),
      );

      final result = await svc.performFirstSync(syncService: fakeSyncSvc);

      expect(result.tablesSynced, equals(3));
      final flag = await db.getSettingValue('client_first_sync_completed');
      expect(flag, equals('true'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ClientFirstSyncService — Failure Mode
  // ═══════════════════════════════════════════════════════════════════════════

  group('ClientFirstSyncService — failure', () {
    test('sync throws → FirstSyncException rethrown, flag stays unset',
        () async {
      final svc = ClientFirstSyncService(db: db);
      final throwingSvc = _ThrowingSyncService(db);

      await expectLater(
        () => svc.performFirstSync(syncService: throwingSvc),
        throwsA(isA<FirstSyncException>()),
      );

      final flag = await db.getSettingValue('client_first_sync_completed');
      expect(flag, isNot(equals('true')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ClientFirstSyncService — Idempotency
  // ═══════════════════════════════════════════════════════════════════════════

  group('ClientFirstSyncService — idempotency', () {
    test('isFirstSyncPending returns false when flag is true', () async {
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'client_first_sync_completed',
              value: const Value('true'),
            ),
          );

      final svc = ClientFirstSyncService(db: db);
      expect(await svc.isFirstSyncPending(), isFalse);
    });

    test('reset() flips flag back so isFirstSyncPending returns true',
        () async {
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'client_first_sync_completed',
              value: const Value('true'),
            ),
          );

      final svc = ClientFirstSyncService(db: db);
      await svc.reset();
      expect(await svc.isFirstSyncPending(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BranchSyncStrategy — Tier 1 globalId (no SYNC-WARN)
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchSyncStrategy — Tier 1 globalId', () {
    test('matches by globalId, produces single row, no SYNC-WARN', () async {
      await db.delete(db.branches).go();
      await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'الفرع الرئيسي',
              globalId: const Value('local-g1'),
            ),
          );

      await BranchSyncStrategy(db).syncFromJson({
        'branches': [
          {
            'id': 5,
            'globalId': 'local-g1',
            'name': 'الفرع الرئيسي',
            'isActive': true,
          }
        ]
      });

      final rows = await db.select(db.branches).get();
      expect(rows, hasLength(1));
      expect(
        DiagnosticLogger.testLog.any((e) => e.contains('SYNC-WARN')),
        isFalse,
        reason: 'Tier 1 match must not emit SYNC-WARN',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BranchSyncStrategy — Tier 2 name fallback (SYNC-WARN required)
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchSyncStrategy — Tier 2 name fallback', () {
    test('matches by name when globalIds differ, emits SYNC-WARN', () async {
      await db.delete(db.branches).go();
      await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'الفرع الرئيسي',
              globalId: const Value('local-g1'),
            ),
          );

      await BranchSyncStrategy(db).syncFromJson({
        'branches': [
          {
            'id': 5,
            'globalId': 'server-g5',
            'name': 'الفرع الرئيسي', // same name, different globalId
            'isActive': true,
          }
        ]
      });

      final rows = await db.select(db.branches).get();
      expect(rows, hasLength(1),
          reason: 'Name-fallback dedup must not create a duplicate row');
      expect(
        DiagnosticLogger.testLog
            .any((e) => e.contains('SYNC-WARN') && e.contains('name')),
        isTrue,
        reason: 'Tier 2 name match must emit SYNC-WARN',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BranchSyncStrategy — Tier 3 serverId fallback (SYNC-WARN required)
  // ═══════════════════════════════════════════════════════════════════════════

  group('BranchSyncStrategy — Tier 3 serverId fallback', () {
    test('matches by serverId when globalId and name both miss, emits SYNC-WARN',
        () async {
      // Insert a row with the same numeric id as the server will use,
      // but different globalId and name so Tier 1 + Tier 2 both miss.
      await db.delete(db.branches).go();
      await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'اسم قديم',
              globalId: const Value(null),
            ),
          );
      // Get the auto-assigned id
      final seeded = await (db.select(db.branches)
            ..where((b) => b.name.equals('اسم قديم')))
          .getSingle();

      await BranchSyncStrategy(db).syncFromJson({
        'branches': [
          {
            'id': seeded.id, // same numeric id → Tier 3 match
            'globalId': 'server-g9',
            'name': 'اسم جديد', // different name → Tier 2 misses
            'isActive': true,
          }
        ]
      });

      final rows = await db.select(db.branches).get();
      expect(rows, hasLength(1),
          reason: 'ServerId fallback must not create a duplicate row');
      expect(
        DiagnosticLogger.testLog
            .any((e) => e.contains('SYNC-WARN') && e.contains('serverId')),
        isTrue,
        reason: 'Tier 3 serverId match must emit SYNC-WARN',
      );
    });

    test('inserts a new row when no tier matches', () async {
      await db.delete(db.branches).go();
      await BranchSyncStrategy(db).syncFromJson({
        'branches': [
          {
            'id': 99,
            'globalId': 'brand-new-g99',
            'name': 'فرع جديد تماماً',
            'isActive': true,
          }
        ]
      });

      final rows = await db.select(db.branches).get();
      expect(rows, hasLength(1));
      expect(rows.first.name, equals('فرع جديد تماماً'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PartySyncStrategy — Tier A name+phone fallback (SYNC-WARN required)
  // ═══════════════════════════════════════════════════════════════════════════

  group('PartySyncStrategy — Tier A name+phone', () {
    test('matches by name+phone when globalId absent, emits SYNC-WARN',
        () async {
      await db.delete(db.parties).go();
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'أحمد',
              phone: const Value('0501234567'),
              isCustomer: const Value(true),
            ),
          );

      await PartySyncStrategy(db).syncFromJson({
        'parties': [
          {
            'id': 10,
            'globalId': 'server-g10',
            'name': 'أحمد',
            'phone': '0501234567',
            'isCustomer': true,
            'isSupplier': false,
            'isDeliveryCompany': false,
            'isActive': true,
            'priceLevel': 'default',
          }
        ]
      });

      final rows = await (db.select(db.parties)
            ..where((p) => p.name.equals('أحمد')))
          .get();
      expect(rows, hasLength(1),
          reason: 'Tier A must not create a duplicate party');
      expect(rows.first.globalId, equals('server-g10'),
          reason: 'globalId must be updated to server value after merge');
      expect(
        DiagnosticLogger.testLog
            .any((e) => e.contains('SYNC-WARN') && e.contains('name+phone')),
        isTrue,
        reason: 'Tier A match must emit SYNC-WARN',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PartySyncStrategy — Tier B delivery priceLevel (SYNC-WARN required)
  // ═══════════════════════════════════════════════════════════════════════════

  group('PartySyncStrategy — Tier B delivery priceLevel', () {
    test(
        'matches delivery company by priceLevel regardless of name change, emits SYNC-WARN',
        () async {
      await db.delete(db.parties).go();
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'طلبات',
              isDeliveryCompany: const Value(true),
              priceLevel: const Value('talabat'),
            ),
          );

      await PartySyncStrategy(db).syncFromJson({
        'parties': [
          {
            'id': 11,
            'globalId': 'server-g11',
            'name': 'شركة توصيل طلبات', // different name — Tier A misses
            'phone': null,
            'isCustomer': false,
            'isSupplier': false,
            'isDeliveryCompany': true,
            'isActive': true,
            'priceLevel': 'talabat',
          }
        ]
      });

      final rows = await (db.select(db.parties)
            ..where((p) => p.priceLevel.equals('talabat')))
          .get();
      expect(rows, hasLength(1),
          reason: 'Tier B must not create a duplicate delivery party');
      expect(
        DiagnosticLogger.testLog.any((e) =>
            e.contains('SYNC-WARN') &&
            (e.contains('priceLevel') ||
                e.contains('delivery-priceLevel'))),
        isTrue,
        reason: 'Tier B priceLevel match must emit SYNC-WARN',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PartySyncStrategy — no-merge guard (name only, no phone)
  // ═══════════════════════════════════════════════════════════════════════════

  group('PartySyncStrategy — no-merge guard (name only, no phone)', () {
    test('inserts new row when name matches but both sides lack phone',
        () async {
      await db.delete(db.parties).go();
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'أحمد',
              isCustomer: const Value(true),
            ),
          );

      await PartySyncStrategy(db).syncFromJson({
        'parties': [
          {
            'id': 20,
            'globalId': 'server-g20',
            'name': 'أحمد', // same name
            'phone': null, // no phone on either side
            'isCustomer': true,
            'isSupplier': false,
            'isDeliveryCompany': false,
            'isActive': true,
            'priceLevel': 'default',
          }
        ]
      });

      final rows = await (db.select(db.parties)
            ..where((p) => p.name.equals('أحمد')))
          .get();
      expect(rows, hasLength(2),
          reason:
              'Name-only match without phone must insert a new row, not merge');
      expect(
        DiagnosticLogger.testLog.any((e) => e.contains('SYNC-WARN')),
        isFalse,
        reason: 'No SYNC-WARN when no fallback tier fired',
      );
    });
  });
}
