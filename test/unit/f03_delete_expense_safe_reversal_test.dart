// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — F-03 (MAJOR): OperationalExpensesDao.deleteExpense must reverse
// the TREASURY leg, not only the GL.
// ═══════════════════════════════════════════════════════════════════════════
//
// Bug (before the fix): deleteExpense ran inside transaction() and reversed
// the GL (deleted the 'op_expense' journal entry + its lines, recomputed the
// affected GL account balances, deleted the op_expenses row) — but NEVER
// deleted the expense's `safe_transactions` row nor restored `safes.balance`.
// The create side (recordAndPostOperationalExpense) inserts that safe_tx
// (referenceType 'op_expense', referenceId = expenseId) and DEBITS the cash
// safe for a CASH expense in standalone/server mode. Net effect of a delete:
// GL cash restored, but safes.balance stayed DOWN and an orphan safe_tx kept
// surfacing in reports → the cash subledger diverged from the GL on every
// opex-tab delete.
//
// Fix: inside the SAME transaction, deleteExpense now reads the expense's
// 'op_expense' safe_transactions rows, restores each safe's balance by its own
// recorded amount (opposite of the original debit), then deletes those rows.
// It is existence-driven: a client-mode or 'bank' expense recorded no safe_tx,
// so nothing is reversed and no safe is wrongly credited.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  Future<int> seedCategory(String name) => db.createExpenseCategory(name: name);

  group('F-03 — deleteExpense reverses the treasury leg atomically', () {
    test(
        'CASH expense: deleteExpense reverses the GL AND removes the '
        'op_expense safe_transaction AND restores safes.balance to the '
        'pre-expense value', () async {
      final categoryId = await seedCategory('فئة F-03 (نقدي)');
      final defaultSafe = await db.getDefaultSafeByType('cash');
      expect(defaultSafe, isNotNull,
          reason: 'forTesting() must seed a default cash safe');
      final balanceBefore = defaultSafe!.balance;
      final accountBalancesBefore = {
        for (final account in await db.select(db.accounts).get())
          account.id: account.balance,
      };

      final expenseId = await db.recordAndPostOperationalExpense(
        categoryId: categoryId,
        amount: 150.0,
        expenseDate: DateTime.now(),
        description: 'مصروف F-03 نقدي',
        expenseAccountCode: '6214',
        userId: 1,
      );

      // Pre-conditions: the create side moved GL + safe as expected.
      final safeTxnsBefore = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('op_expense') &
                t.referenceId.equals(expenseId)))
          .get();
      expect(safeTxnsBefore, hasLength(1),
          reason: 'a CASH op-expense must record exactly one safe_tx');
      final safeAfterCreate = await db.getSafeById(defaultSafe.id);
      expect(safeAfterCreate!.balance, balanceBefore - 150.0,
          reason: 'create side debited the safe by the amount');

      final jeBefore = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('op_expense') &
                e.referenceId.equals(expenseId)))
          .getSingle();
      final jeId = jeBefore.id;

      // Act.
      final rowsDeleted = await OperationalExpensesDao(db).deleteExpense(expenseId);
      expect(rowsDeleted, 1, reason: 'the op_expenses row was deleted');

      // (a) GL reversal is additive: the posted source JE remains auditable
      // and a distinct reversal JE offsets its lines.
      final jeAfter = await (db.select(db.journalEntries)
            ..where((e) =>
                (e.referenceType.equals('op_expense') &
                    e.referenceId.equals(expenseId)) |
                (e.referenceType.equals('reversal') &
                    e.referenceId.equals(jeId))))
          .get();
      expect(jeAfter, hasLength(2));
      expect(jeAfter.any((entry) => entry.id == jeId), isTrue);
      expect(jeAfter.any((entry) => entry.referenceType == 'reversal'), isTrue);
      final linesAfter = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(jeId)))
          .get();
      expect(linesAfter, isNotEmpty, reason: 'the original JE remains posted');
      final accountBalancesAfter = {
        for (final account in await db.select(db.accounts).get())
          account.id: account.balance,
      };
      expect(accountBalancesAfter, accountBalancesBefore,
          reason: 'source plus reversal must net every account to its prior balance');

      // (b) the op_expense safe_transaction row is gone (no orphan child).
      final safeTxnsAfter = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('op_expense') &
                t.referenceId.equals(expenseId)))
          .get();
      expect(safeTxnsAfter, isEmpty,
          reason: 'the op_expense safe_transaction must be deleted, not orphaned');

      // (c) safes.balance restored EXACTLY to the pre-expense value.
      final safeAfterDelete = await db.getSafeById(defaultSafe.id);
      expect(safeAfterDelete!.balance, balanceBefore,
          reason: 'the safe balance must return to its pre-expense value');

      // (d) the op_expenses row itself is gone.
      final expenseRow = await (db.select(db.opExpenses)
            ..where((e) => e.id.equals(expenseId)))
          .get();
      expect(expenseRow, isEmpty);
    });

    test(
        'NON-CASH (bank) expense: no safe_tx was ever recorded, so '
        'deleteExpense reverses the GL only and does NOT wrongly credit any '
        'safe', () async {
      final categoryId = await seedCategory('فئة F-03 (بنكي)');
      final defaultSafe = await db.getDefaultSafeByType('cash');
      final balanceBefore = defaultSafe!.balance;
      final accountBalancesBefore = {
        for (final account in await db.select(db.accounts).get())
          account.id: account.balance,
      };

      final expenseId = await db.recordAndPostOperationalExpense(
        categoryId: categoryId,
        amount: 90.0,
        expenseDate: DateTime.now(),
        description: 'مصروف F-03 بنكي',
        expenseAccountCode: '6214',
        userId: 1,
        paymentMethod: 'bank', // isCashExpense == false → NO safe movement
      );

      // Pre-condition: a bank expense records NO op_expense safe_tx and does
      // not touch the cash safe — but it DOES post a GL entry.
      final safeTxnsBefore = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('op_expense') &
                t.referenceId.equals(expenseId)))
          .get();
      expect(safeTxnsBefore, isEmpty,
          reason: 'a bank op-expense must NOT record a safe_tx');
      final safeAfterCreate = await db.getSafeById(defaultSafe.id);
      expect(safeAfterCreate!.balance, balanceBefore,
          reason: 'a bank expense must not touch the cash safe');
      final jeBefore = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('op_expense') &
                e.referenceId.equals(expenseId)))
          .get();
      expect(jeBefore, hasLength(1), reason: 'the bank expense still posts a GL JE');

      // Act.
      await OperationalExpensesDao(db).deleteExpense(expenseId);

      // GL reversal retains the source and creates a reversal.
      final sourceJeId = jeBefore.single.id;
      final jeAfter = await (db.select(db.journalEntries)
            ..where((e) =>
                (e.referenceType.equals('op_expense') &
                    e.referenceId.equals(expenseId)) |
                (e.referenceType.equals('reversal') &
                    e.referenceId.equals(sourceJeId))))
          .get();
      expect(jeAfter, hasLength(2));
       final accountBalancesAfter = {
         for (final account in await db.select(db.accounts).get())
           account.id: account.balance,
       };
       expect(accountBalancesAfter, accountBalancesBefore,
           reason: 'source plus reversal must net every account to its prior balance');

      // The safe balance is UNCHANGED — the fix must not credit a safe that
      // was never debited (would corrupt the drawer in client/bank flows).
      final safeAfterDelete = await db.getSafeById(defaultSafe.id);
      expect(safeAfterDelete!.balance, balanceBefore,
          reason: 'no safe_tx existed to reverse — the safe must be untouched');

      final expenseRow = await (db.select(db.opExpenses)
            ..where((e) => e.id.equals(expenseId)))
          .get();
      expect(expenseRow, isEmpty);
    });
  });
}
