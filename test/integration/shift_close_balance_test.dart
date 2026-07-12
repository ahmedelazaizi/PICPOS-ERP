// ═══════════════════════════════════════════════════════════════════════════
// Spec 136 ISS-8 — Shift close transfers only THIS shift's NET to HQ
// (supersedes Spec 107 Model A "full balance drain")
// ═══════════════════════════════════════════════════════════════════════════
//
// Accounting model: a shift close settles ONLY the closing user's own shift.
// It transfers each touched safe's NET shift contribution
// (sum(receipts) − sum(payments)) to HQ and leaves the remaining balance —
// the opening float, pre-shift manual receipts, and any other shift's
// contribution — in the till. Money that did not move during this shift's
// window (or was moved by another user/shift) is NEVER swept by this close.
//
// Variance attribution still lives in `_settleShift` (Spec 104), which scopes
// its expectation calc to the shift period — so a pre-shift manual receipt
// neither inflates the cashier's variance NOR is drained at this close.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int branchId;
  late int cashSafeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'BR-107',
            globalId: const Value('gid-br-107'),
          ),
        );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier-107',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'cashier_107',
      password: 'pw',
      displayName: 'F107',
      roleId: roleId,
    );
    await db.into(db.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(userId: userId, branchId: branchId),
        );

    cashSafeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'cash-107',
            branchId: Value(branchId),
            safeType: const Value('cash'),
            balance: const Value(0),
            globalId: const Value('gid-safe-107-cash'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> postReceipt(int safeId, double amount,
      {required DateTime at, String? voucherNo}) async {
    final current = await db.getSafeById(safeId);
    final newBal = (current?.balance ?? 0) + amount;
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNo ?? 'RCT-${at.microsecondsSinceEpoch}',
            safeId: safeId,
            transactionType: 'receipt',
            category: 'sale',
            amount: amount,
            balanceAfter: newBal,
            userId: Value(userId),
            createdAt: Value(at),
          ),
        );
    await db.adjustSafeBalance(safeId, amount);
  }

  Future<void> postPayment(int safeId, double amount,
      {required DateTime at, String? voucherNo}) async {
    final current = await db.getSafeById(safeId);
    final newBal = (current?.balance ?? 0) - amount;
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNo ?? 'PAY-${at.microsecondsSinceEpoch}',
            safeId: safeId,
            transactionType: 'payment',
            category: 'expense',
            amount: amount,
            balanceAfter: newBal,
            userId: Value(userId),
            createdAt: Value(at),
          ),
        );
    await db.adjustSafeBalance(safeId, -amount);
  }

  Future<void> stampShiftStart(int shiftId, DateTime at) async {
    await (db.update(db.shifts)..where((s) => s.id.equals(shiftId)))
        .write(ShiftsCompanion(startTime: Value(at)));
  }

  test('Scenario A1 — pre-shift manual receipt is NOT drained; only the '
      'shift\'s net sale is transferred (Spec 136 ISS-8)', () async {
    final t0 = DateTime(2025, 1, 15, 8, 0, 0);
    final t1 = DateTime(2025, 1, 15, 9, 0, 0);
    final t2 = DateTime(2025, 1, 15, 10, 0, 0);

    // Manual receipt of 50 before the shift starts (e.g. supplier settlement
    // captured by the cashier-as-treasurer) — OUTSIDE this shift's window.
    await postReceipt(cashSafeId, 50, at: t0, voucherNo: 'MANUAL-50');

    final shiftId = await db.openShift(userId, 50);
    await stampShiftStart(shiftId, t1);

    // Cashier sells 100 cash during the shift.
    await postReceipt(cashSafeId, 100, at: t2, voucherNo: 'SALE-100');

    expect((await db.getSafeById(cashSafeId))!.balance, 150);

    // actualCash counts the drawer = 50 (pre-shift) + 100 (sale) = 150.
    await db.closeShiftWithAudit(shiftId, 150);

    // Per-shift: only the in-shift net (100) is transferred; the pre-shift 50
    // stays in the till.
    final closingTxns = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('shift_closing') &
              t.safeId.equals(cashSafeId)))
        .get();
    expect(closingTxns, hasLength(1));
    expect(closingTxns.single.amount, 100,
        reason: 'only this shift\'s net sale is moved to HQ');
    expect(closingTxns.single.balanceAfter, 50,
        reason: 'the pre-shift manual receipt remains in the till');

    expect((await db.getSafeById(cashSafeId))!.balance, 50,
        reason: 'pre-shift money is not swept by this shift\'s close');
  });

  test('Scenario A2 — shift with refund and expense voucher', () async {
    final t1 = DateTime(2025, 1, 15, 9, 0, 0);
    final t2 = DateTime(2025, 1, 15, 9, 30, 0);
    final t3 = DateTime(2025, 1, 15, 10, 0, 0);
    final t4 = DateTime(2025, 1, 15, 10, 30, 0);

    final shiftId = await db.openShift(userId, 0);
    await stampShiftStart(shiftId, t1);

    await postReceipt(cashSafeId, 80, at: t2, voucherNo: 'SALE-80');
    await postPayment(cashSafeId, 20, at: t3, voucherNo: 'RFND-20');
    await postPayment(cashSafeId, 10, at: t4, voucherNo: 'EXP-10');

    // safe balance now = 50 (80 in − 20 refund − 10 expense)
    expect((await db.getSafeById(cashSafeId))!.balance, 50);

    await db.closeShiftWithAudit(shiftId, 50);

    final closingTxns = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('shift_closing') &
              t.safeId.equals(cashSafeId)))
        .get();
    expect(closingTxns.single.amount, 50);
    expect((await db.getSafeById(cashSafeId))!.balance, 0);
  });

  test('Scenario A3 — empty shift leaves a pre-existing leftover intact '
      '(Spec 136 ISS-8)', () async {
    // Leftover 30 from before — a manual receipt, or residue from a previous
    // shift. A shift that moved NO cash of its own must not sweep it.
    final t0 = DateTime(2025, 1, 15, 8, 0, 0);
    final t1 = DateTime(2025, 1, 15, 9, 0, 0);

    await postReceipt(cashSafeId, 30, at: t0, voucherNo: 'LEFTOVER-30');

    final shiftId = await db.openShift(userId, 30);
    await stampShiftStart(shiftId, t1);
    // No in-shift activity at all → this shift's net is zero.
    await db.closeShiftWithAudit(shiftId, 30);

    final closingTxns = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('shift_closing') &
              t.safeId.equals(cashSafeId)))
        .get();
    expect(closingTxns, isEmpty,
        reason: 'a shift with zero net movement transfers nothing');
    expect((await db.getSafeById(cashSafeId))!.balance, 30,
        reason: 'the pre-existing leftover stays for its own shift to settle');
  });

  test('Scenario A4 — variance JE separate from close transfer JE',
      () async {
    // Decoupling check: a manual receipt of 50 before the shift increases
    // safe.balance but is OUTSIDE the cashier's shift window. Spec 104
    // variance calc must not flag this as a surplus.
    final t0 = DateTime(2025, 1, 15, 8, 0, 0);
    final t1 = DateTime(2025, 1, 15, 9, 0, 0);
    final t2 = DateTime(2025, 1, 15, 10, 0, 0);

    await postReceipt(cashSafeId, 50, at: t0, voucherNo: 'PRE-50');

    final shiftId = await db.openShift(userId, 50);
    await stampShiftStart(shiftId, t1);

    await postReceipt(cashSafeId, 100, at: t2, voucherNo: 'SHIFT-100');

    // Cashier counts the drawer correctly: 150. No real discrepancy.
    await db.closeShiftWithAudit(shiftId, 150);

    // (1) Close transfer = this shift's net (100); the pre-shift 50 stays.
    final closing = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('shift_closing') &
              t.safeId.equals(cashSafeId)))
        .get();
    expect(closing.single.amount, 100);

    // (2) Variance recorded on the shift = 0 (Spec 104 scopes its expected
    //     cash to the shift period: openingBalance 50 + in-shift receipts
    //     100 = 150; actualCash 150 → variance 0).
    final shift = await (db.select(db.shifts)
          ..where((s) => s.id.equals(shiftId)))
        .getSingle();
    expect(shift.variance ?? 0, closeTo(0, 0.001),
        reason: 'Spec 104: no surplus flagged for legitimate pre-shift cash');
  });

  test('Scenario A5 — zero-balance safe produces NO closing txn', () async {
    final t1 = DateTime(2025, 1, 15, 9, 0, 0);

    final shiftId = await db.openShift(userId, 0);
    await stampShiftStart(shiftId, t1);
    // No activity, balance stays 0.
    await db.closeShiftWithAudit(shiftId, 0);

    final closing = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('shift_closing') &
              t.safeId.equals(cashSafeId)))
        .get();
    expect(closing, isEmpty,
        reason: 'zero balance → no JE noise (the |balance| > 0.001 guard)');
  });
}
