// Feature 041 — Shift-Closing Safe-Transaction Idempotency by globalId.
//
// Pins the deterministic UUIDv5 helper and the layered dedup inside
// `_closeShiftSafes`. Before the Route-B.1 fix the same logical (shift, safe)
// pair produced two distinct random UUIDv7 globalIds (one per close path —
// /api/shifts/close and /api/safes/transaction mirror), bypassing the
// existing `(safeId, referenceType, referenceId)` check because the two
// callers used the CLIENT's vs the SERVER's local shift id respectively.
//
// Post-fix:
//   1. `UuidV7.deriveShiftClosingGlobalId(shiftGlobalId, safeGlobalId)`
//      returns the SAME UUID across independent invocations.
//   2. `_closeShiftSafes` will skip the insert when a `shift_closing` row
//      with the deterministic globalId already exists for that safe,
//      regardless of `referenceId` value.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/utils/uuid_v7.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('UuidV7.deriveShiftClosingGlobalId', () {
    test('returns the same UUID for the same (shift, safe) inputs', () {
      const shiftGid = 'shift-gid-A';
      const safeGid = 'safe-gid-B';

      final a = UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: shiftGid,
        safeGlobalId: safeGid,
      );
      final b = UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: shiftGid,
        safeGlobalId: safeGid,
      );

      expect(a, b,
          reason: 'Determinism is the load-bearing property — both client and '
              'server must derive the same UUID without coordination.');
      expect(UuidV7.isValid(a), isTrue, reason: 'Must be a canonical UUID.');
    });

    test('produces different UUIDs for different (shift, safe) pairs', () {
      final ab = UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: 'shift-A',
        safeGlobalId: 'safe-B',
      );
      final ac = UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: 'shift-A',
        safeGlobalId: 'safe-C',
      );
      final db = UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: 'shift-D',
        safeGlobalId: 'safe-B',
      );

      expect(ab, isNot(ac),
          reason: 'Different safe globalId must yield distinct UUID.');
      expect(ab, isNot(db),
          reason: 'Different shift globalId must yield distinct UUID.');
      expect(ac, isNot(db));
    });

    test('argument order matters — namespaced derivation is not commutative',
        () {
      final ab = UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: 'X',
        safeGlobalId: 'Y',
      );
      final ba = UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: 'Y',
        safeGlobalId: 'X',
      );
      expect(ab, isNot(ba));
    });
  });

  group('_closeShiftSafes layered dedup', () {
    late AppDatabase db;
    late int userId;
    late int branchId;
    late int safeId;
    late String safeGlobalId;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();

      branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'BR-041',
              globalId: const Value('gid-br-041'),
            ),
          );

      final roleId = await db.into(db.roles).insert(
            RolesCompanion.insert(
              name: 'cashier-041',
              isSystemRole: const Value(false),
            ),
          );
      userId = await db.createUser(
        username: 'cashier_041',
        password: 'pw',
        displayName: 'F041',
        roleId: roleId,
      );
      await db.into(db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: userId, branchId: branchId),
          );

      safeGlobalId = 'gid-safe-041';
      safeId = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'cash-041',
              branchId: Value(branchId),
              balance: const Value(0),
              safeType: const Value('cash'),
              globalId: Value(safeGlobalId),
            ),
          );
    });

    tearDown(() async => db.close());

    test('the deterministic globalId of the produced shift_closing row '
        'matches UuidV7.deriveShiftClosingGlobalId', () async {
      const shiftGlobalId = 'gid-shift-041-A';
      final shiftId = await db.openShift(userId, 0, globalId: shiftGlobalId);

      // Drive a small positive cash balance so _closeShiftSafes actually
      // inserts a row (skips when |balance| < 0.001).
      await db.createReceiptVoucher(
        amount: 5.0,
        category: 'sales',
        safeId: safeId,
        userId: userId,
      );

      await db.closeShiftWithAudit(shiftId, 5.0);

      final row = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.safeId.equals(safeId) &
                t.referenceType.equals('shift_closing')))
          .getSingle();

      final expected = UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: shiftGlobalId,
        safeGlobalId: safeGlobalId,
      );
      expect(row.globalId, expected,
          reason: 'Both close paths must converge on the deterministic UUIDv5.');
    });

    test('simulating the "server inserted under a different referenceId first" '
        'race — the second close path produces no duplicate row', () async {
      // Reproduce the field condition that drove the v122 NEG-BAL incident:
      //   - Server's /api/shifts/close already wrote a `shift_closing` row
      //     for the safe under the SERVER's local shift id (here: 999).
      //   - The CLIENT mirror now arrives via /api/safes/transaction with a
      //     `referenceId = CLIENT's local shift id` (different integer).
      //
      // Pre-fix: the (safeId, refType, refId) check missed (different id),
      // each side minted its own random UUIDv7, so the row was inserted a
      // second time → safe balance ended up -2× actual. Post-fix: both
      // sides compute the same deterministic globalId, the new globalId
      // check inside _closeShiftSafes catches the duplicate even with a
      // mismatched referenceId.
      const shiftGlobalId = 'gid-shift-041-B';
      final shiftId = await db.openShift(userId, 0, globalId: shiftGlobalId);

      await db.createReceiptVoucher(
        amount: 7.0,
        category: 'sales',
        safeId: safeId,
        userId: userId,
      );

      // Pre-seed the row that "the other side" already wrote, mirroring the
      // server-first ordering. referenceId is intentionally a different
      // integer than `shiftId` — that is exactly the divergence that
      // bypassed the old idempotency check.
      final deterministicGid = UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: shiftGlobalId,
        safeGlobalId: safeGlobalId,
      );
      await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'PRE-SEED-${DateTime.now().millisecondsSinceEpoch}',
              safeId: safeId,
              transactionType: 'withdrawal',
              category: 'shift_closing',
              amount: 7.0,
              balanceAfter: 0,
              referenceType: const Value('shift_closing'),
              // Different from shiftId — simulating server-vs-client id divergence.
              referenceId: const Value(999),
              globalId: Value(deterministicGid),
            ),
          );

      // Run the close — _closeShiftSafes should detect the pre-seeded row
      // via the new globalId check and NOT insert a duplicate.
      await db.closeShiftWithAudit(shiftId, 7.0);

      final rows = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.safeId.equals(safeId) &
                t.referenceType.equals('shift_closing')))
          .get();
      expect(rows.length, 1,
          reason: 'Only the pre-seeded row may exist; the second close path '
              'must skip the insert by deterministic globalId.');
      expect(rows.first.globalId, deterministicGid);
    });

    test('legacy path: shift with null globalId still closes (fallback mint)',
        () async {
      // Some pre-v119 shifts may exist with NULL globalId. Close still has
      // to succeed for them — falling back to a fresh UuidV7 is acceptable
      // because there is no "other side" expected to dedup against legacy
      // rows (the duplicate-source path was added by 035).
      final shiftId = await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              startTime: DateTime.now(),
              userId: userId,
              status: 'open',
              // intentionally no globalId
            ),
          );
      await db.createReceiptVoucher(
        amount: 3.0,
        category: 'sales',
        safeId: safeId,
        userId: userId,
      );

      await db.closeShiftWithAudit(shiftId, 3.0);

      final row = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.safeId.equals(safeId) &
                t.referenceType.equals('shift_closing')))
          .getSingle();
      expect(row.globalId, isNotNull);
      expect(UuidV7.isValid(row.globalId), isTrue);
    });
  });
}
