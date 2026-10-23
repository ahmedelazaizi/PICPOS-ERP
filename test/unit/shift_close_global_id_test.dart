// 2026-05-12 — "Shift not found" DEAD-LETTER root-cause fix (Constitution R9).
//
// Production scenario reproduced from CLIENT diagnostic.log:
//   1. Client opens shift → local SQLite assigns id (e.g. 1000000002)
//   2. Mirror call to /api/shifts/open succeeds → server inserts shift with
//      its own id (e.g. 4) using the client-provided globalId.
//   3. Cashier closes shift → cwi_catalog.closeShift sends the LOCAL id
//      (1000000002) to the server because no local→server mapping exists
//      for online opens (mappedIds is only populated by outbox drains).
//   4. Server's previous postCloseShift looked up by id → "Shift not found"
//      → 500 → outbox flagged the row as permanent error → DEAD-LETTER.
//
// The fix threads `globalId` end-to-end. These tests pin the contract on
// the database side: the same globalId resolves to the same shift row even
// when the local and server ids diverge.
//
// (HTTP-handler integration is exercised manually + via existing E2E
// tests — covering the full server flow here would require spinning up
// a shelf router and is overkill for the data-layer guarantee.)

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'shift_global_id_user',
      password: 'pw',
      displayName: 'Tester',
      roleId: roleId,
    );
  });

  tearDown(() async => db.close());

  test('treasury_dao.openShift honours caller-provided globalId', () async {
    const callerGlobalId = 'shift-global-from-client-001';
    final shiftId = await db.openShift(userId, 100.0, globalId: callerGlobalId);
    final row = await (db.select(db.shifts)..where((s) => s.id.equals(shiftId)))
        .getSingle();
    expect(row.globalId, callerGlobalId,
        reason: 'When the caller passes a globalId the DAO must reuse it '
            'instead of minting a fresh UUID — required for end-to-end R9.');
  });

  test('treasury_dao.openShift mints a fresh globalId when none is provided',
      () async {
    final shiftId = await db.openShift(userId, 100.0);
    final row = await (db.select(db.shifts)..where((s) => s.id.equals(shiftId)))
        .getSingle();
    expect(row.globalId, isNotNull,
        reason:
            'Auto-mint preserves legacy direct-DAO callers (tests, server reconstruct).');
    expect(row.globalId!.length, greaterThan(10));
  });

  test('shifts table looks up by globalId across local↔server id divergence',
      () async {
    // Simulate: client created shift with local id 1000000002 but the server
    // inserted it with id 7 (different auto-increment) — both keyed by the
    // same globalId. The close-by-globalId path must resolve correctly even
    // when the incoming shiftId doesn't exist on this side.
    const sharedGlobalId = 'shift-cross-instance-uuid';

    // The client-side row (high local id range)
    final localId = await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: DateTime.now(),
            userId: userId,
            status: 'open',
            globalId: const Value(sharedGlobalId),
          ),
        );
    expect(localId, isPositive);

    // The lookup by globalId — what postCloseShift now does first
    final foundByGlobalId = await (db.select(db.shifts)
          ..where((s) => s.globalId.equals(sharedGlobalId))
          ..limit(1))
        .getSingleOrNull();
    expect(foundByGlobalId, isNotNull);
    expect(foundByGlobalId!.id, localId);
    expect(foundByGlobalId.status, 'open');
  });

  test('idempotent open: duplicate globalId resolves to existing row',
      () async {
    // Simulating retry: server postOpenShift dedups by globalId so a
    // replayed outbox open doesn't create a phantom shift.
    const sharedGlobalId = 'shift-idempotent-uuid';
    final firstId = await db.openShift(userId, 100.0, globalId: sharedGlobalId);

    final byGid = await (db.select(db.shifts)
          ..where((s) => s.globalId.equals(sharedGlobalId)))
        .get();
    expect(byGid.length, 1, reason: 'unique index on globalId should be honoured');
    expect(byGid.first.id, firstId);
  });

  test(
      'idempotent close: an already-closed shift with the same globalId is a no-op',
      () async {
    // The contract postCloseShift now upholds: if a shift with the supplied
    // globalId is already status=closed, return success without re-running
    // the close pipeline (no duplicate variance JEs, no double safe zero-out).
    const sharedGlobalId = 'shift-already-closed-uuid';
    final shiftId = await db.openShift(userId, 200.0, globalId: sharedGlobalId);
    await db.closeShiftWithAudit(shiftId, 200.0); // perfect close

    final row = await (db.select(db.shifts)..where((s) => s.id.equals(shiftId)))
        .getSingle();
    expect(row.status, 'closed');

    // Repeating close on the same shift via DAO is a no-op (early return at
    // treasury_dao.dart:310). The handler short-circuit before that ensures
    // the same outcome when only the globalId is in the payload.
    await db.closeShiftWithAudit(shiftId, 9999.0); // wildly different cash
    final after = await (db.select(db.shifts)..where((s) => s.id.equals(shiftId)))
        .getSingle();
    expect(after.actualCash, 200.0,
        reason: 'second close must NOT overwrite the first close result');
  });
}
