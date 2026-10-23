// ═══════════════════════════════════════════════════════════════════════════
// Spec 149 pre-deploy batch B12-1 — S-FIL (FIL-2 branch-scope read-leak)
// ═══════════════════════════════════════════════════════════════════════════
//
// FIL-2: the financial-statement report methods in accounting_reports_dao.dart
// (getTrialBalance, getIncomeStatement, getBalanceSheet, getCashFlowStatement,
// getTaxReport, getHierarchicalTrialBalance, getAgedPayables/Receivables,
// getPostingReconciliation) never intersected the logged-in user's
// user_branch_access scope — a branch-restricted user could pull ALL
// branches' data through the financial-statements screen. Fixed via a new
// `_buildAuthScopeFilter` helper, ANDed on top of the existing dropdown/
// region `_buildBranchFilter` in every one of those queries. Contract
// (mirrors BranchScope in lib/data/providers/branch_scope_provider.dart):
//   allowedBranchIds == null  → no restriction (full access)
//   allowedBranchIds == {}    → match NOTHING (defensive)
//   allowedBranchIds == {ids} → branch_id IN (ids) OR branch_id IS NULL
//
// This test exercises getTrialBalance only (representative — every other
// touched method threads the SAME `_buildAuthScopeFilter` helper the same
// way; see accounting_reports_dao.dart for the full list).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int cashId;
  late int revenueId;
  late int branch1;
  late int branch2;
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    cashId = (await db.getAccountByCode('1111'))!.id; // asset
    revenueId = (await db.getAccountByCode('4121'))!.id; // revenue

    branch1 = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع 1 — B12',
            globalId: const Value('gid-br1-b12'),
          ),
        );
    branch2 = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع 2 — B12',
            globalId: const Value('gid-br2-b12'),
          ),
        );

    // Branch 1: cash debited 100
    await db.createJournalEntry(
      description: 'إيراد فرع 1 — B12',
      date: DateTime(2026, 2, 1),
      branchId: branch1,
      lines: [
        JournalLine(accountId: cashId, debit: 100),
        JournalLine(accountId: revenueId, credit: 100),
      ],
    );
    // Branch 2: cash debited 200
    await db.createJournalEntry(
      description: 'إيراد فرع 2 — B12',
      date: DateTime(2026, 2, 2),
      branchId: branch2,
      lines: [
        JournalLine(accountId: cashId, debit: 200),
        JournalLine(accountId: revenueId, credit: 200),
      ],
    );
    // Global (head-office) entry — genuinely NULL branch_id. Must stay visible
    // under BranchScope.isAllowed(null) == true for EVERY scoped user.
    // NOTE: createJournalEntry auto-resolves a fallback branch when branchId is
    // null (Spec 108 lowest-active), so it can NOT produce a NULL-branch row.
    // Insert the JE + lines directly to keep branch_id NULL and actually
    // exercise the "global rows stay visible under a restricted scope" contract.
    final globalJe = await db.into(db.journalEntries).insert(
          JournalEntriesCompanion.insert(
            entryNumber: 'JE-GLOBAL-B12',
            entryDate: DateTime(2026, 2, 3),
            isPosted: const Value(true),
          ),
        );
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: globalJe, accountId: cashId, debit: const Value(50)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: globalJe, accountId: revenueId, credit: const Value(50)));
  });

  tearDown(() => db.close());

  group('Spec 149 B12 FIL-2 branch-scope read-leak', () {
    test(
        'allowedBranchIds={branch1} → branch-1 + NULL amounts only '
        '(branch-2 excluded)', () async {
      final result =
          await db.getTrialBalance(from, to, allowedBranchIds: {branch1});
      final cashRow = result.firstWhere((r) => r['id'] == cashId);

      // branch1 (100) + global (50) = 150. Branch 2's 200 must NOT leak in.
      expect(cashRow['movementDebit'], closeTo(150, 0.01));
    });

    test('allowedBranchIds=null → full access, reflects ALL three entries',
        () async {
      final result = await db.getTrialBalance(from, to);
      final cashRow = result.firstWhere((r) => r['id'] == cashId);

      expect(cashRow['movementDebit'], closeTo(350, 0.01));
    });

    test(
        'allowedBranchIds={} (empty set) → matches nothing, account '
        'movement is zero / no branch rows', () async {
      final result =
          await db.getTrialBalance(from, to, allowedBranchIds: <int>{});
      final cashRows = result.where((r) => r['id'] == cashId);

      expect(cashRows, isEmpty,
          reason: 'empty scope must AND 1=0 — zero-activity accounts are '
              'skipped from the result entirely (defensive: a '
              'misconfigured zero-scope user sees nothing, not everything)');
      final totals = result.last;
      expect(totals['movementDebit'], 0.0);
      expect(totals['movementCredit'], 0.0);
    });

    // Committee BLOCK fix: getPostingReconciliation must scope the DRIVING
    // invoice tables (si/pi), not just the JE side of the LEFT JOIN — else a
    // restricted user still reads every branch's invoice rows.
    test(
        'getPostingReconciliation — restricted user sees only own-branch + '
        'global invoices (branch-2 excluded)', () async {
      // FK is off in the in-memory test DB (NativeDatabase.memory sets no
      // foreign_keys pragma), so bare invoice rows suffice.
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'SI-B1', warehouseId: 1, userId: 1,
            invoiceDate: DateTime(2026, 2, 5),
            branchId: Value(branch1), total: const Value(100)));
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'SI-B2', warehouseId: 1, userId: 1,
            invoiceDate: DateTime(2026, 2, 6),
            branchId: Value(branch2), total: const Value(200)));
      // Global (NULL-branch) invoice — must stay visible under every scope.
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'SI-G', warehouseId: 1, userId: 1,
            invoiceDate: DateTime(2026, 2, 7), total: const Value(50)));

      final scoped =
          await db.getPostingReconciliation(from, to, allowedBranchIds: {branch1});
      final scopedNums = scoped
          .where((r) => r['sourceType'] == 'sale')
          .map((r) => r['invoiceNumber'])
          .toSet();
      expect(scopedNums, contains('SI-B1'));
      expect(scopedNums, contains('SI-G'), reason: 'NULL-branch stays visible');
      expect(scopedNums, isNot(contains('SI-B2')),
          reason: 'branch-2 invoice must NOT leak to a branch-1 user');

      final full = await db.getPostingReconciliation(from, to);
      final fullNums = full
          .where((r) => r['sourceType'] == 'sale')
          .map((r) => r['invoiceNumber'])
          .toSet();
      expect(fullNums, containsAll(<String>['SI-B1', 'SI-B2', 'SI-G']));
    });
  });
}
