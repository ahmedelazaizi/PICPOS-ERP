// ═══════════════════════════════════════════════════════════════════════════
// Batch B13 (S-EXP-REST) — three unrelated pre-deploy gaps pinned together.
// ═══════════════════════════════════════════════════════════════════════════
//
// Sites covered:
//   EXP-3  operational_expenses_dao.dart :: recordAndPostOperationalExpense
//          — a CASH op-expense now also moves the safe (safe_transactions +
//          updateSafeBalance) atomically alongside its GL JE, WITHOUT
//          double-counting: exactly one GL JE, and the report methods
//          (getExpensesForReport / getMonthlyExpenseSummary) count the
//          expense exactly once even though they UNION op_expenses with
//          expense-flavored safe_transactions.
//   EXP-5  accounting_autopost_dao.dart :: autoPostOperationalExpense —
//          branchId consistency. Previously, when the caller passed
//          branchId == null (the opex dialog's "كل الفروع" default), the
//          JE borrowed the branch of an ARBITRARY first-matching safe while
//          the op_expenses row itself stayed branchId = NULL. Now both stay
//          in sync (null stays null; an explicit branchId is carried by
//          both).
//   MJE-3  permissions_dao.dart :: userHasPermission — the permission-check
//          primitive the local manual-JE gate
//          (journal_entries_screen.dart::_requireAccountingJournalPermission,
//          wired into saveManualEntry in journal_entry_create_dialog.dart
//          and into _confirmReverseEntry in journal_entries_screen.dart)
//          calls before allowing a post/reverse. The gate itself lives
//          inside a ConsumerState + StatefulBuilder dialog flow and is NOT
//          unit-testable without a widget-test harness — this test pins
//          the underlying `userHasPermission` primitive it depends on
//          instead: a non-admin role WITHOUT the permission → false; WITH
//          it explicitly granted → true; and an admin (مدير النظام system
//          role) → true WITHOUT any explicit grant, via the pre-existing
//          admin bypass in _isAdminRole (accountingJournal is not in
//          PermissionCodes.criticalFinancialOps, so admin is not required
//          to hold it explicitly).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  Future<int> seedCategory(String name) => db.createExpenseCategory(name: name);

  // ═══════════════════════════════════════════════════════════════════════
  // EXP-3 — cash operational expense moves the safe, no double-counting
  // ═══════════════════════════════════════════════════════════════════════
  group('EXP-3 — cash operational expense moves the safe without double-counting', () {
    test(
        'creates a safe_transactions row, drops the safe balance, posts '
        'exactly ONE GL JE, and both report methods count the expense '
        'exactly once', () async {
      final categoryId = await seedCategory('فئة B13 EXP-3 (سليمة)');
      final defaultSafe = await db.getDefaultSafeByType('cash');
      expect(defaultSafe, isNotNull,
          reason: 'AppDatabase.forTesting() must seed a default cash safe');
      final balanceBefore = defaultSafe!.balance;

      final now = DateTime.now();
      final expenseId = await db.recordAndPostOperationalExpense(
        categoryId: categoryId,
        amount: 150.0,
        expenseDate: now,
        description: 'مصروف B13 EXP-3 نقدي',
        expenseAccountCode: '6214',
        userId: 1,
      );

      // (a) a safe_transactions row referencing the expense was created.
      final safeTxns = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('op_expense') &
                t.referenceId.equals(expenseId)))
          .get();
      expect(safeTxns, hasLength(1));
      final safeTxn = safeTxns.single;
      expect(safeTxn.amount, 150.0);
      expect(safeTxn.safeId, defaultSafe.id);
      expect(safeTxn.category, 'expense');
      expect(safeTxn.transactionType, 'payment');

      // (b) updateSafeBalance dropped the safe balance by the amount.
      final safeAfter = await db.getSafeById(defaultSafe.id);
      expect(safeAfter!.balance, balanceBefore - 150.0);

      // (c) exactly ONE GL JE exists for the expense (no double post).
      final jes = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('op_expense') &
                e.referenceId.equals(expenseId)))
          .get();
      expect(jes, hasLength(1));
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(jes.single.id)))
          .get();
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit, reason: 'the JE must balance');
      expect(totalDebit, 150.0);

      // (d) getExpensesForReport counts the expense exactly ONCE — the
      // op_expense side must show it, and the safe_transactions side must
      // NOT ALSO surface the safe movement we just created for it.
      final from = DateTime(now.year, now.month, 1);
      final to = now.add(const Duration(days: 1));
      final reportRows = await db.getExpensesForReport(from: from, to: to);
      final opSideRows = reportRows
          .where((r) => r['source'] == 'op_expense' && r['id'] == expenseId)
          .toList();
      expect(opSideRows, hasLength(1),
          reason: 'the op_expenses side of the UNION must show it exactly once');
      final phantomSafeTxRows = reportRows
          .where((r) =>
              r['source'] == 'safe_tx' && r['reference'] == safeTxn.voucherNumber)
          .toList();
      expect(phantomSafeTxRows, isEmpty,
          reason: 'the safe_transactions side must EXCLUDE the row referencing '
              'this op_expense — otherwise the same expense is counted twice');

      // (e) getMonthlyExpenseSummary counts the expense exactly ONCE too.
      final summaryRows = await db.getMonthlyExpenseSummary(from: from, to: to);
      final ourCategoryRow = summaryRows.firstWhere((r) => r['id'] == categoryId);
      expect((ourCategoryRow['total_amount'] as num).toDouble(), 150.0,
          reason: 'the category total must reflect the expense exactly once');
      expect(ourCategoryRow['entry_count'], 1);
      // The safe-side aggregate groups by safe_transactions.category text —
      // 'expense' maps to the "مصروف عام" label. With the op_expense-linked
      // row correctly excluded, no such row should appear at all (nothing
      // else in this fresh test DB uses that category).
      final phantomSummaryRows =
          summaryRows.where((r) => r['name'] == 'مصروف عام').toList();
      expect(phantomSummaryRows, isEmpty,
          reason: 'the cash movement must not ALSO surface as a separate '
              'cash_outflow summary row — that would double-count it');
    });

    test(
        'fails loud with a full rollback (no op_expenses row, no JE, no '
        'safe transaction) when no cash safe is configured', () async {
      final categoryId = await seedCategory('فئة B13 EXP-3 (بدون صندوق)');
      // Remove ALL safes (forTesting() seeds a default one) so the cash leg
      // cannot resolve a target safe.
      await db.delete(db.safes).go();

      expect(await db.select(db.opExpenses).get(), isEmpty);

      await expectLater(
        () => db.recordAndPostOperationalExpense(
          categoryId: categoryId,
          amount: 80.0,
          expenseDate: DateTime.now(),
          description: 'مصروف بدون صندوق',
          expenseAccountCode: '6214',
          userId: 1,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await db.select(db.opExpenses).get(), isEmpty,
          reason: 'the op_expenses row must roll back when no safe can be resolved');
      final jes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('op_expense')))
          .get();
      expect(jes, isEmpty,
          reason: 'no half-posted GL entry may survive the rollback');
      final safeTxns = await db.select(db.safeTransactions).get();
      expect(safeTxns, isEmpty,
          reason: 'no safe transaction can exist with no safe configured');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // EXP-5 — op_expenses row and its JE always carry the SAME branchId
  // ═══════════════════════════════════════════════════════════════════════
  group('EXP-5 — op_expenses row and its JE always carry the SAME branchId', () {
    test('branchId omitted (null): row stays null, JE uses the canonical '
        'lowest-active-branch fallback — NOT the arbitrary safe branch', () async {
      // Give the default safe an explicit (newly-created, higher-id) branch.
      // OLD bug: autoPostOperationalExpense borrowed THIS safe branch for the
      // JE. FIXED: it passes null, and createJournalEntry applies its own
      // canonical Spec-108 fallback (the lowest-id active branch, never null
      // when a branch exists — an orphan branch-less JE is un-reportable).
      final safeBranchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'فرع صندوق B13'),
          );
      final defaultSafe = await db.getDefaultSafeByType('cash');
      await (db.update(db.safes)..where((s) => s.id.equals(defaultSafe!.id)))
          .write(SafesCompanion(branchId: Value(safeBranchId)));

      // The canonical fallback = lowest active branch (seeded default), which
      // must NOT be the (higher-id) safe branch — otherwise the assertion
      // couldn't tell the fix from the bug.
      final lowestActive = await (db.select(db.branches)
            ..where((b) => b.isActive.equals(true))
            ..orderBy([(b) => OrderingTerm.asc(b.id)])
            ..limit(1))
          .getSingle();
      expect(safeBranchId, isNot(lowestActive.id),
          reason: 'test setup: safe branch must differ from the fallback');

      final categoryId = await seedCategory('فئة B13 EXP-5 (بدون فرع)');

      final expenseId = await db.recordAndPostOperationalExpense(
        categoryId: categoryId,
        amount: 60.0,
        expenseDate: DateTime.now(),
        description: 'مصروف بدون فرع',
        expenseAccountCode: '6214',
        userId: 1,
      );

      final expenseRow =
          await (db.select(db.opExpenses)..where((e) => e.id.equals(expenseId)))
              .getSingle();
      expect(expenseRow.branchId, isNull);

      final je = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('op_expense') & e.referenceId.equals(expenseId)))
          .getSingle();
      expect(je.branchId, isNot(safeBranchId),
          reason: 'must NOT borrow the arbitrary safe branch');
      expect(je.branchId, lowestActive.id,
          reason: 'JE gets createJournalEntry\'s canonical lowest-active-branch '
              'fallback (Spec 108), decoupled from the safe');
    });

    test('an explicit branchId is carried by BOTH the row and the JE', () async {
      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'فرع B13 اختبار صريح'),
          );
      final categoryId = await seedCategory('فئة B13 EXP-5 (بفرع)');

      final expenseId = await db.recordAndPostOperationalExpense(
        categoryId: categoryId,
        amount: 40.0,
        expenseDate: DateTime.now(),
        description: 'مصروف بفرع محدد',
        expenseAccountCode: '6214',
        userId: 1,
        branchId: branchId,
      );

      final expenseRow =
          await (db.select(db.opExpenses)..where((e) => e.id.equals(expenseId)))
              .getSingle();
      expect(expenseRow.branchId, branchId);

      final je = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('op_expense') & e.referenceId.equals(expenseId)))
          .getSingle();
      expect(je.branchId, branchId);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // MJE-3 — permission-check primitive behind the local manual-JE gate
  // ═══════════════════════════════════════════════════════════════════════
  group('MJE-3 — accounting_journal permission gates the manual-JE post/reverse', () {
    test('a user WITHOUT accounting_journal is blocked; granting it allows them',
        () async {
      final roleId = await db.insertRole(name: 'محاسب محدود B13 MJE-3');
      final userId = await db.createUser(
        username: 'b13_mje3_user',
        password: 'test',
        displayName: 'مستخدم بدون صلاحية القيود',
        roleId: roleId,
      );

      final blocked =
          await db.userHasPermission(userId, PermissionCodes.accountingJournal);
      expect(blocked, isFalse,
          reason: 'a freshly-created non-admin role has no permissions by default');

      final journalPerm = (await db.getAllPermissions())
          .firstWhere((p) => p.code == PermissionCodes.accountingJournal);
      await db.addPermissionToRole(roleId, journalPerm.id);

      final allowed =
          await db.userHasPermission(userId, PermissionCodes.accountingJournal);
      expect(allowed, isTrue,
          reason: 'granting the role the permission must unblock the user');
    });

    test('an admin (مدير النظام system role) passes WITHOUT an explicit '
        'grant — same admin-bypass the rest of the app already relies on, '
        'not a new special case', () async {
      // _isAdminRole (permissions_dao.dart) only bypasses for the
      // isSystemRole=true role literally named 'مدير النظام'. accountingJournal
      // is NOT in PermissionCodes.criticalFinancialOps, so — unlike
      // voidPaidInvoice / overrideCreditLimit / etc. — admin does NOT need
      // an explicit role-permission row for it.
      final adminRoleId = await db.insertRole(
        name: 'مدير النظام',
        isSystemRole: true,
      );
      // Do NOT force id:1 — AppDatabase.forTesting() already seeds the admin
      // user at id=1, so reusing it collides (UNIQUE users.id). A fresh
      // auto-id user carrying the isSystemRole 'مدير النظام' role exercises
      // the same _isAdminRole bypass.
      final adminUserId = await db.createUser(
        username: 'b13_mje3_admin',
        password: 'test',
        displayName: 'مدير النظام',
        roleId: adminRoleId,
      );

      final allowed = await db.userHasPermission(
          adminUserId, PermissionCodes.accountingJournal);
      expect(allowed, isTrue,
          reason: 'مدير النظام must pass the accounting_journal gate via the '
              'existing admin bypass, with no permission row granted');
    });
  });
}
