// Feature 012 / Issue C-SHIFT-LOOP — ShiftSyncStrategy id-collision
// regression guard.
//
// The bug: client/mirror devices auto-increment `shifts.id` locally,
// independent of the server's auto-increment. When the two id spaces
// happened to land on the same value for two DIFFERENT logical shifts
// (one local-open + one server-closed), the old strategy's
// `insertOnConflictUpdate(id: serverId)` SILENTLY OVERWROTE the local
// open shift → `getCurrentOpenShift(userId)` returned null →
// the cashier's shift-open dialog re-fired mid-sale.
//
// The fix: three-tier match (globalId → (userId, startTime) → id with
// sanity check) plus an explicit "insert at fresh local id" fallback
// when the id targets a row owned by a DIFFERENT logical shift.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/strategies/shift_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late ShiftSyncStrategy strategy;

  setUp(() async {
    db = AppDatabase.forTesting();
    strategy = ShiftSyncStrategy(db);
    // shifts.user_id FKs to users — seed the shift owners referenced below
    // (only the admin user 1 is seeded). FK is enforced in tests now.
    for (final uid in [5, 7, 10, 99, 888, 999]) {
      await db.into(db.users).insert(UsersCompanion.insert(
          id: Value(uid),
          username: 'usr$uid',
          passwordHash: 'x',
          displayName: 'U$uid'));
    }
  });

  tearDown(() => db.close());

  group('ShiftSyncStrategy id-collision protection', () {
    test('id-collision with a DIFFERENT logical shift inserts at a fresh '
        'local id instead of overwriting the cashier\'s open shift', () async {
      // Cashier (userId=10) opens a shift locally. Local auto-increment
      // happens to give id=1.
      const cashierId = 10;
      final cashierStart = DateTime(2026, 5, 6, 9, 0, 0);
      final cashierShiftId = await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              startTime: cashierStart,
              userId: cashierId,
              openingBalance: const Value(100.0),
              status: 'open',
            ),
          );
      expect(cashierShiftId, 1,
          reason: 'sanity: a fresh DB starts ids at 1');

      // Server pulls back a shift with id=1 belonging to a DIFFERENT
      // user (userId=99) and CLOSED status. The naive upsertById would
      // overwrite the cashier's open shift here.
      await strategy.syncFromJson({
        'shifts': [
          {
            'id': 1,
            'userId': 99,
            'startTime': '2026-05-05T08:00:00.000',
            'endTime': '2026-05-05T16:00:00.000',
            'openingBalance': 0.0,
            'status': 'closed',
          },
        ],
      });

      // Cashier's open shift MUST still be there with status='open'.
      final cashierShift = await (db.select(db.shifts)
            ..where((t) =>
                t.userId.equals(cashierId) & t.status.equals('open')))
          .getSingleOrNull();
      expect(cashierShift, isNotNull,
          reason: 'cashier\'s open shift must NOT be overwritten by an '
              'unrelated server shift that happens to share id=1');
      expect(cashierShift!.openingBalance, 100.0);
      expect(cashierShift.startTime, cashierStart);

      // The unrelated server shift was inserted at a fresh local id.
      final allShifts = await db.select(db.shifts).get();
      expect(allShifts, hasLength(2),
          reason: 'both the cashier shift AND the server shift must coexist');
      final serverShift =
          allShifts.firstWhere((s) => s.userId == 99);
      expect(serverShift.id, isNot(1),
          reason: 'server shift must have been inserted at a fresh local id');
      expect(serverShift.status, 'closed');
    });

    test('matches by (userId, startTime) when globalId is null on local row',
        () async {
      // Cashier opens a shift locally; no globalId yet (waiting for
      // server to mint and echo back).
      const cashierId = 5;
      final cashierStart = DateTime(2026, 5, 6, 10, 0, 0);
      final localId = await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              startTime: cashierStart,
              userId: cashierId,
              openingBalance: const Value(50.0),
              status: 'open',
            ),
          );

      // Server later echoes back the same logical shift with a server-
      // assigned id and a globalId. Tier 2 match (userId, startTime)
      // must collapse it onto the local row instead of inserting a new
      // one.
      await strategy.syncFromJson({
        'shifts': [
          {
            'id': 4242, // server's id space — different from local
            'globalId': '019dfc99-aaaa-bbbb-cccc-000000000099',
            'userId': cashierId,
            'startTime': cashierStart.toIso8601String(),
            'openingBalance': 50.0,
            'status': 'open',
          },
        ],
      });

      final shifts = await (db.select(db.shifts)
            ..where((t) => t.userId.equals(cashierId)))
          .get();
      expect(shifts, hasLength(1),
          reason: 'tier-2 match (userId, startTime) must collapse the '
              'server echo onto the local row');
      expect(shifts.first.id, localId,
          reason: 'local id must be preserved so dependent FKs stay valid');
      expect(shifts.first.globalId, '019dfc99-aaaa-bbbb-cccc-000000000099',
          reason: 'globalId must be backfilled from the server row');
      expect(shifts.first.status, 'open');
    });

    test('preserves the cashier\'s open status after a delta-pull that '
        'would have closed it', () async {
      // The end-to-end concern from the bug report: a delta-pull MUST
      // NOT transition a locally-open shift to closed unless the server
      // truly closed THAT shift (matched via globalId or natural key).
      const cashierId = 7;
      final cashierStart = DateTime(2026, 5, 6, 11, 30, 0);
      await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              startTime: cashierStart,
              userId: cashierId,
              openingBalance: const Value(75.0),
              status: 'open',
            ),
          );

      // A delta pull returns OTHER users' closed shifts that happen to
      // share the same id space. None of them target this cashier.
      await strategy.syncFromJson({
        'shifts': [
          {
            'id': 1, // collides with the cashier's local id
            'userId': 999,
            'startTime': '2026-04-01T00:00:00.000',
            'endTime': '2026-04-01T08:00:00.000',
            'openingBalance': 0.0,
            'status': 'closed',
          },
          {
            'id': 2,
            'userId': 888,
            'startTime': '2026-04-02T00:00:00.000',
            'endTime': '2026-04-02T08:00:00.000',
            'openingBalance': 0.0,
            'status': 'closed',
          },
        ],
      });

      final cashierStill = await (db.select(db.shifts)
            ..where((t) =>
                t.userId.equals(cashierId) & t.status.equals('open')))
          .getSingleOrNull();
      expect(cashierStill, isNotNull,
          reason: 'cashier\'s open shift must survive an unrelated delta-pull');
    });
  });
}
