// ═══════════════════════════════════════════════════════════════════════════
// Spec 136 ISS-8 — Shift close drains only THIS shift's net (supersedes the
// Spec 107 / Feature 006 "Full Drain — zero every branch safe" model)
// ═══════════════════════════════════════════════════════════════════════════
//
// Field report: closing one user's shift drained the ENTIRE cumulative safe
// balance — sweeping every active branch safe and zeroing it — so it absorbed
// cash earned by OTHER users' still-open shifts and residuals from previously-
// unclosed shifts. The operator wants the close to settle ONLY the closing
// user's current shift.
//
// New model: _closeShiftSafes touches ONLY the safes this shift actually moved
// cash in/out of, transfers each safe's NET shift contribution
// (sum(receipts) - sum(payments|withdrawals)) to HQ, and leaves the remaining
// balance (opening float + other shifts' contributions) in the till. Untouched
// branch safes and sister-branch safes are never swept.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;
  late int userInBranchA;
  late int cashSafeA;
  late int bankSafeA;
  late int clickSafeA;
  late int cashSafeB;

  Future<int> seedBranch(String name) => db.into(db.branches).insert(
        BranchesCompanion.insert(
          name: name,
          globalId: Value('gid-br-$name'),
        ),
      );

  Future<int> seedUser(String username, int branchId) async {
    final id = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: 'hash',
            displayName: username,
          ).copyWith(globalId: Value('gid-$username')),
        );
    await db.into(db.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(userId: id, branchId: branchId),
        );
    return id;
  }

  Future<int> seedSafe(String name, int branchId, double opening, {String type = 'cash'}) {
    return db.into(db.safes).insert(
          SafesCompanion.insert(
            name: name,
            branchId: Value(branchId),
            balance: Value(opening),
            safeType: Value(type),
            globalId: Value('gid-safe-$name'),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchA = await seedBranch('A');
    branchB = await seedBranch('B');
    userInBranchA = await seedUser('cashierA', branchA);

    cashSafeA = await seedSafe('cash-A', branchA, 0);
    bankSafeA = await seedSafe('bank-A', branchA, 1500, type: 'bank');
    clickSafeA = await seedSafe('click-A', branchA, 750, type: 'bank');
    cashSafeB = await seedSafe('cash-B', branchB, 99999);
  });

  tearDown(() => db.close());

  test('closeShiftWithAudit drains ONLY this shift\'s net per touched safe — '
      'untouched branch safes and sister-branch safes keep their balance '
      '(Spec 136 ISS-8)', () async {
    // Open a shift for the cashier in branch A and run a single sale-style
    // receipt only against the cash safe — bank and click are untouched.
    final shiftId = await db.openShift(userInBranchA, 0);
    await db.createSafeTransaction(
      SafeTransactionsCompanion.insert(
        voucherNumber: 'TST-1',
        safeId: cashSafeA,
        transactionType: 'receipt',
        category: 'sale',
        amount: 200,
        balanceAfter: 200,
        userId: Value(userInBranchA),
      ),
    );

    // Sanity: bank and click started with stale balances; cash has 200.
    final pre = await db.select(db.safes).get();
    expect(pre.firstWhere((s) => s.id == cashSafeA).balance, 200);
    expect(pre.firstWhere((s) => s.id == bankSafeA).balance, 1500);
    expect(pre.firstWhere((s) => s.id == clickSafeA).balance, 750);
    expect(pre.firstWhere((s) => s.id == cashSafeB).balance, 99999);

    await db.closeShiftWithAudit(shiftId, 200);

    final post = await db.select(db.safes).get();
    // cash-A: this shift's net (+200) is drained → 0 (it opened with a 0 float).
    expect(post.firstWhere((s) => s.id == cashSafeA).balance, 0);
    // bank-A / click-A: this shift never moved them → balances stay intact
    // (NO full-drain).
    expect(post.firstWhere((s) => s.id == bankSafeA).balance, 1500,
        reason: 'untouched branch safe must keep its balance');
    expect(post.firstWhere((s) => s.id == clickSafeA).balance, 750,
        reason: 'untouched branch safe must keep its balance');
    // Branch-B safe is untouched — sister-branch funds stay intact.
    expect(post.firstWhere((s) => s.id == cashSafeB).balance, 99999,
        reason: 'safes outside the shift owner\'s branch must NOT be swept');
  });

  test('shift close records a withdrawal txn ONLY for safes this shift moved, '
      'draining each safe\'s net and leaving the residual (Spec 136 ISS-8)',
      () async {
    final shiftId = await db.openShift(userInBranchA, 0);
    // This shift moves cash into cash-A (net +200) and bank-A (net +300).
    // click-A is never touched.
    await db.createSafeTransaction(SafeTransactionsCompanion.insert(
      voucherNumber: 'TST-C',
      safeId: cashSafeA,
      transactionType: 'receipt',
      category: 'sale',
      amount: 200,
      balanceAfter: 200,
      userId: Value(userInBranchA),
    ));
    await db.createSafeTransaction(SafeTransactionsCompanion.insert(
      voucherNumber: 'TST-B',
      safeId: bankSafeA,
      transactionType: 'receipt',
      category: 'sale',
      amount: 300,
      balanceAfter: 1800,
      userId: Value(userInBranchA),
    ));

    await db.closeShiftWithAudit(shiftId, 200);

    final closingTxns = await (db.select(db.safeTransactions)
          ..where((t) => t.referenceType.equals('shift_closing')))
        .get();

    final closedSafeIds = closingTxns.map((t) => t.safeId).toSet();
    // Only the safes this shift moved get a closing txn.
    expect(closedSafeIds, containsAll([cashSafeA, bankSafeA]));
    // click-A was non-zero but untouched by this shift — NOT swept.
    expect(closedSafeIds, isNot(contains(clickSafeA)),
        reason: 'untouched branch safe is not swept under per-shift drain');
    // cash-B is in a different branch — never swept.
    expect(closedSafeIds, isNot(contains(cashSafeB)));
    // Drained amount == this shift's net per safe.
    expect(closingTxns.firstWhere((t) => t.safeId == cashSafeA).amount, 200);
    expect(closingTxns.firstWhere((t) => t.safeId == bankSafeA).amount, 300);
    // bank-A keeps its 1500 residual (1800 − 300 net).
    final post = await db.select(db.safes).get();
    expect(post.firstWhere((s) => s.id == bankSafeA).balance, 1500);
  });

  test('idempotent: closing an already-closed shift is a no-op', () async {
    final shiftId = await db.openShift(userInBranchA, 0);
    await db.closeShiftWithAudit(shiftId, 0);

    final firstPassBalances = {
      for (final s in await db.select(db.safes).get()) s.id: s.balance,
    };

    await db.closeShiftWithAudit(shiftId, 0); // second call

    final secondPassBalances = {
      for (final s in await db.select(db.safes).get()) s.id: s.balance,
    };

    expect(secondPassBalances, firstPassBalances);
  });
}
