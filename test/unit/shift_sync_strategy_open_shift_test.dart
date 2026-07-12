// Spec 029 / US3 Bug B — `ShiftSyncStrategy` open-shift protection.
//
// Production observed: client logs in, opens a shift; the next
// DeltaPull contains a stale `status='closed'` row for that shift (or
// no row at all but the strategy's id-collision branch still
// overwrites). The local row's status flips to closed, the
// `getCurrentOpenShift` lookup returns null, and the SHIFT-GUARD's
// `suppressed re-prompt` warning fires on the next login.
//
// Three scenarios pin the contract:
//   1. open_shift_survives_stale_server_close
//      Local OPEN, server says CLOSED with older lastModifiedAt
//      → local stays OPEN. SHIFT-SYNC warn line is logged.
//   2. closed_shift_accepts_server_newer_close
//      Local OPEN, server says CLOSED with newer lastModifiedAt
//      → local becomes CLOSED (server wins, lastWriteWins).
//   3. new_server_shift_inserted_unchanged
//      Empty local, server pushes one new shift
//      → row inserted as today (no-conflict path unchanged).
//
// See specs/029-sync-regression-hardening/contracts/bug-b-shift-sync.md.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/strategies/shift_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late ShiftSyncStrategy strategy;

  setUp(() async {
    db = AppDatabase.forTesting();
    strategy = ShiftSyncStrategy(db);
    DiagnosticLogger.enableTestMode();
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertLocalShift({
    required int userId,
    required DateTime startTime,
    required String status,
    DateTime? lastModifiedAt,
    String? globalId,
  }) async {
    return db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: startTime,
            userId: userId,
            status: status,
            lastModifiedAt: Value(lastModifiedAt),
            globalId: Value(globalId),
          ),
        );
  }

  test(
    'open_shift_survives_stale_server_close — local OPEN, server says '
    'CLOSED with older lastModifiedAt → local stays OPEN',
    () async {
      final start = DateTime(2026, 5, 10, 9);
      final localId = await insertLocalShift(
        userId: 5,
        startTime: start,
        status: 'open',
        lastModifiedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        globalId: 'shift-global-1',
      );

      // Server's pull: same logical shift, claims closed, with an OLDER
      // lastModifiedAt than the local row.
      await strategy.syncFromJson({
        'shifts': [
          {
            'id': 999, // server id (irrelevant — globalId match wins)
            'globalId': 'shift-global-1',
            'userId': 5,
            'startTime': start.toIso8601String(),
            'endTime':
                DateTime(2026, 5, 10, 17).toIso8601String(),
            'status': 'closed',
            'openingBalance': 0,
            'lastModifiedAt': DateTime.now()
                .subtract(const Duration(minutes: 10))
                .toIso8601String(),
          }
        ],
      });

      final after = await (db.select(db.shifts)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      expect(after, isNotNull);
      expect(
        after!.status,
        equals('open'),
        reason:
            'open local shift must NOT be overwritten by a stale closed '
            'server row within the operator-active carve-out window',
      );
      expect(
        DiagnosticLogger.testLog.any(
          (line) => line.contains('SHIFT-SYNC') &&
              line.contains('preserving local OPEN shift'),
        ),
        isTrue,
        reason:
            'expected a [SHIFT-SYNC] preserving local OPEN shift '
            'diagnostic line for field debuggability',
      );
    },
  );

  test(
    'closed_shift_accepts_server_newer_close — local OPEN with old '
    'lastModifiedAt, server CLOSED newer → local becomes CLOSED',
    () async {
      final start = DateTime(2026, 5, 10, 9);
      final localId = await insertLocalShift(
        userId: 5,
        startTime: start,
        status: 'open',
        // Local was modified an hour ago — outside the 5-minute carve-out.
        lastModifiedAt: DateTime.now().subtract(const Duration(hours: 1)),
        globalId: 'shift-global-2',
      );

      // Server's row is freshly closed.
      await strategy.syncFromJson({
        'shifts': [
          {
            'id': 999,
            'globalId': 'shift-global-2',
            'userId': 5,
            'startTime': start.toIso8601String(),
            'endTime':
                DateTime(2026, 5, 10, 17).toIso8601String(),
            'status': 'closed',
            'openingBalance': 0,
            'lastModifiedAt':
                DateTime.now().toIso8601String(),
          }
        ],
      });

      final after = await (db.select(db.shifts)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      expect(after, isNotNull);
      expect(
        after!.status,
        equals('closed'),
        reason:
            'when the local row is older than the server row AND not in '
            'the open-shift carve-out, the server wins (lastWriteWins)',
      );
    },
  );

  test(
    'new_server_shift_inserted_unchanged — empty local, server pushes '
    'one new shift → row inserted as today',
    () async {
      final start = DateTime(2026, 5, 10, 9);
      await strategy.syncFromJson({
        'shifts': [
          {
            'id': 42,
            'globalId': 'shift-global-3',
            'userId': 7,
            'startTime': start.toIso8601String(),
            'status': 'open',
            'openingBalance': 100,
            'lastModifiedAt': DateTime.now().toIso8601String(),
          }
        ],
      });

      final all = await db.select(db.shifts).get();
      expect(all, hasLength(1));
      expect(all.first.userId, equals(7));
      expect(all.first.status, equals('open'));
      expect(all.first.globalId, equals('shift-global-3'));
    },
  );
}
