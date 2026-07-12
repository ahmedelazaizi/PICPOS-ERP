// Feature 036 — `ShiftSyncStrategy` reverse-direction carve-out
// (the "respect local close" rule).
//
// Production observed (Beta Round 9 / Cluster 034 Issue 1): cashier
// closes a shift, opens a new one; a stale DeltaPull then arrives with
// the OLD shift still marked `status='open'` server-side AND with a
// newer `lastModifiedAt` (server processed an unrelated update on the
// row after the local close). The strategy's `lastWriteWins`
// fall-through clobbered the local CLOSED row back to OPEN, the next
// `getCurrentOpenShift` returned the old shift, and the closing report
// bundled BOTH shifts' invoices on the same drawer-count.
//
// Three scenarios pin the reverse carve-out:
//   1. closed_shift_survives_stale_server_open
//      Local CLOSED within carve-out window, server says OPEN newer →
//      local stays CLOSED. SHIFT-SYNC diagnostic line is logged.
//   2. ancient_closed_shift_accepts_server_open
//      Local CLOSED outside carve-out (e.g. 5h old close), server says
//      OPEN newer → server wins (lastWriteWins) so very-old offline
//      drift can still resolve.
//   3. closed_shift_accepts_server_closed_update
//      Local CLOSED, server also CLOSED (with updated notes / variance)
//      → server wins (no reverse carve-out involvement).

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
    DateTime? endTime,
    DateTime? lastModifiedAt,
    String? globalId,
  }) async {
    return db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: startTime,
            userId: userId,
            status: status,
            endTime: Value(endTime),
            lastModifiedAt: Value(lastModifiedAt),
            globalId: Value(globalId),
          ),
        );
  }

  test(
    'closed_shift_survives_stale_server_open — local CLOSED ~10min ago, '
    'server says OPEN with NEWER lastModifiedAt → local stays CLOSED',
    () async {
      final start = DateTime(2026, 5, 10, 9);
      final closedAt = DateTime.now().subtract(const Duration(minutes: 10));
      final localId = await insertLocalShift(
        userId: 5,
        startTime: start,
        status: 'closed',
        endTime: closedAt,
        // Local stamp is OLDER than the server's, so without the carve-out
        // the lastWriteWins fall-through would flip status back to open.
        lastModifiedAt: closedAt,
        globalId: 'shift-closed-carve-1',
      );

      await strategy.syncFromJson({
        'shifts': [
          {
            'id': 999,
            'globalId': 'shift-closed-carve-1',
            'userId': 5,
            'startTime': start.toIso8601String(),
            'endTime': null,
            'status': 'open',
            'openingBalance': 0,
            // 1-minute-ago — strictly newer than the local close.
            'lastModifiedAt':
                DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
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
        reason: 'a freshly-closed local shift must NOT be flipped back '
            'to open by a stale server pull — the close is the load-bearing '
            'financial event and its time window scopes the next shift\'s '
            'aggregation, so reverting it cascades into the report bug',
      );
      expect(
        DiagnosticLogger.testLog.any(
          (line) => line.contains('SHIFT-SYNC') &&
              line.contains('preserving local CLOSED shift'),
        ),
        isTrue,
        reason: 'expected the new [SHIFT-SYNC] preserving local CLOSED '
            'diagnostic for field debuggability',
      );
    },
  );

  test(
    'ancient_closed_shift_accepts_server_open — local CLOSED 5h ago '
    '(past the 4h carve-out), server says OPEN newer → server wins',
    () async {
      final start = DateTime(2026, 5, 10, 9);
      // 5 hours ago — outside the 4h reverse-carve-out window.
      final closedAt = DateTime.now().subtract(const Duration(hours: 5));
      final localId = await insertLocalShift(
        userId: 5,
        startTime: start,
        status: 'closed',
        endTime: closedAt,
        lastModifiedAt: closedAt,
        globalId: 'shift-closed-carve-2',
      );

      await strategy.syncFromJson({
        'shifts': [
          {
            'id': 999,
            'globalId': 'shift-closed-carve-2',
            'userId': 5,
            'startTime': start.toIso8601String(),
            'endTime': null,
            'status': 'open',
            'openingBalance': 0,
            'lastModifiedAt': DateTime.now().toIso8601String(),
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
        reason: 'beyond the carve-out lastWriteWins re-engages so genuine '
            'multi-day-offline drift can still resolve toward server truth',
      );
    },
  );

  test(
    'closed_shift_accepts_server_closed_update — local CLOSED, server '
    'also CLOSED (different notes / variance) → server wins',
    () async {
      final start = DateTime(2026, 5, 10, 9);
      final closedAt = DateTime.now().subtract(const Duration(minutes: 10));
      final localId = await insertLocalShift(
        userId: 5,
        startTime: start,
        status: 'closed',
        endTime: closedAt,
        lastModifiedAt: closedAt,
        globalId: 'shift-closed-carve-3',
      );

      // Server's row is also closed but freshly modified by someone (e.g.
      // notes edited on the server). The reverse carve-out doesn't fire
      // because both sides are CLOSED.
      await strategy.syncFromJson({
        'shifts': [
          {
            'id': 999,
            'globalId': 'shift-closed-carve-3',
            'userId': 5,
            'startTime': start.toIso8601String(),
            'endTime': closedAt.toIso8601String(),
            'status': 'closed',
            'openingBalance': 0,
            'notes': 'edited on server',
            'lastModifiedAt': DateTime.now().toIso8601String(),
          }
        ],
      });

      final after = await (db.select(db.shifts)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      expect(after, isNotNull);
      expect(after!.status, equals('closed'));
      expect(
        after.notes,
        equals('edited on server'),
        reason: 'when both sides are CLOSED the reverse carve-out is '
            'irrelevant and the regular lastWriteWins pull applies — '
            'server-side notes edits must reach the mirror',
      );
    },
  );
}
