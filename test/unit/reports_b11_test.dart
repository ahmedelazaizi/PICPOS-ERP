// ═══════════════════════════════════════════════════════════════════════════
// Spec 149 pre-deploy batch B11 — S-REPORTS (REP-1, REP-2)
// ═══════════════════════════════════════════════════════════════════════════
//
// REP-2 fix 1 (accounting_reports_dao.dart getBalanceSheet, equity section):
// the "صافي الأرباح (دوري)" net-income add-on resolved the P&L window via
// getCurrentFiscalYear() — whichever fiscal year has isCurrent=true —
// regardless of the balance sheet's own [atDate]. Running the balance sheet
// for a PRIOR/closed year therefore fed getIncomeStatement a window starting
// at the CURRENT year's fyStart, which is AFTER atDate for a prior-year
// report: an inverted BETWEEN range that silently returns 0/garbage net
// income (and an unbalanced sheet, since assets/equity accounts ARE scoped
// correctly by atDate). Fixed to resolve the fiscal year that CONTAINS
// atDate via getFiscalYearByDate(atDate).
//
// REP-2 fix 2: getBalanceSheet accepts branchIds (plural) and its own
// equity-account aggregation honors it, but the call to getIncomeStatement
// only forwarded the singular branchId — so a multi-branch call scoped
// equity ACCOUNTS to specific branches while net income leaked in
// company-wide. Fixed to forward branchIds too.
//
// REP-1 (label + GL-routing on 4 presentation screens) is presentation-only
// — no DAO math changed — so it isn't unit-tested screen-by-screen here.
// The one DAO-level contract REP-1 relies on (screens that DO route to GL
// read getIncomeStatement(...)['netProfit']) is exercised indirectly by
// every test below, since getBalanceSheet's fix depends on the SAME
// getIncomeStatement call being correct.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int cashId;
  late int revenueId;
  late int expenseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    cashId = (await db.getAccountByCode('1111'))!.id; // asset
    revenueId = (await db.getAccountByCode('4121'))!.id; // revenue
    expenseId = (await db.getAccountByCode('6214'))!.id; // expense (not COGS/depreciation)
  });

  tearDown(() => db.close());

  /// Seeds two fiscal years: 2025 (PRIOR, not current) and 2026 (CURRENT).
  /// Mirrors the real-world shape that triggers the REP-2 bug: whoever asks
  /// for a balance sheet dated in 2025 must NOT get 2026's fyStart.
  Future<void> seedFiscalYears() async {
    await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            name: 'السنة المالية 2025 (B11)',
            startDate: DateTime(2025, 1, 1),
            endDate: DateTime(2025, 12, 31),
            isCurrent: const Value(false),
            globalId: const Value('gid-fy2025-b11'),
          ),
        );
    await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            name: 'السنة المالية 2026 (B11)',
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 12, 31),
            isCurrent: const Value(true),
            globalId: const Value('gid-fy2026-b11'),
          ),
        );
  }

  group('REP-2 — balance sheet resolves the FY CONTAINING atDate', () {
    test(
        'balance sheet dated in the PRIOR year reflects the PRIOR year\'s '
        'net income, not 0 from the current-FY window', () async {
      await seedFiscalYears();

      // Revenue + expense posted in the PRIOR year (2025) while isCurrent
      // points at 2026. Net income for 2025 = 1000 (revenue) − 400 (expense)
      // = 600.
      await db.createJournalEntry(
        description: 'إيراد 2025 — B11',
        date: DateTime(2025, 6, 15),
        lines: [
          JournalLine(accountId: cashId, debit: 1000),
          JournalLine(accountId: revenueId, credit: 1000),
        ],
      );
      await db.createJournalEntry(
        description: 'مصروف 2025 — B11',
        date: DateTime(2025, 7, 15),
        lines: [
          JournalLine(accountId: expenseId, debit: 400),
          JournalLine(accountId: cashId, credit: 400),
        ],
      );

      final bs = await db.getBalanceSheet(DateTime(2025, 12, 31));

      // Pre-fix: getCurrentFiscalYear() → FY2026, fyStart=2026-01-01, which
      // is AFTER atDate=2025-12-31 → inverted BETWEEN range in
      // getIncomeStatement → netProfit 0 → equity line 0 → sheet does NOT
      // balance (assets=600 vs liabilities+equity=0).
      final equityDetails = (bs['equityDetails'] as List)
          .cast<Map<String, dynamic>>();
      final netProfitLine = equityDetails
          .firstWhere((e) => e['name'] == 'صافي الأرباح (دوري)');

      expect(netProfitLine['balance'], closeTo(600, 0.01),
          reason: 'must reflect FY2025 net income (1000 revenue − 400 '
              'expense), not 0 from the mis-scoped current-FY window');
      expect(bs['totalEquity'], closeTo(600, 0.01));
      expect(bs['totalAssets'], closeTo(600, 0.01),
          reason: 'sanity: cash after the two JEs is 1000 − 400 = 600');
      expect(bs['isBalanced'], isTrue,
          reason: 'assets (600) must equal liabilities(0) + equity(600) '
              'once net income is scoped to the fiscal year containing '
              'atDate instead of whichever FY is flagged isCurrent');
    });

    test(
        'balance sheet dated in the CURRENT year still resolves correctly '
        '(regression guard — the fix must not break the common case)',
        () async {
      await seedFiscalYears();
      await db.createJournalEntry(
        description: 'إيراد 2026 — B11',
        date: DateTime(2026, 3, 1),
        lines: [
          JournalLine(accountId: cashId, debit: 500),
          JournalLine(accountId: revenueId, credit: 500),
        ],
      );

      final bs = await db.getBalanceSheet(DateTime(2026, 6, 30));
      expect(bs['totalEquity'], closeTo(500, 0.01));
      expect(bs['isBalanced'], isTrue);
    });
  });

  group('REP-2 — branch scope forwarded consistently to getIncomeStatement',
      () {
    test('single-branch balance sheet still balances after the fix',
        () async {
      await seedFiscalYears();
      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرع B11',
              globalId: const Value('gid-br-b11-single'),
            ),
          );

      await db.createJournalEntry(
        description: 'إيراد فرع — B11',
        date: DateTime(2026, 2, 1),
        branchId: branchId,
        lines: [
          JournalLine(accountId: cashId, debit: 700),
          JournalLine(accountId: revenueId, credit: 700),
        ],
      );

      final bs = await db.getBalanceSheet(DateTime(2026, 12, 31),
          branchId: branchId);
      expect(bs['totalEquity'], closeTo(700, 0.01));
      expect(bs['isBalanced'], isTrue);
    });

    test(
        'multi-branch (branchIds) equity net-income matches ONLY the '
        'requested branches, not company-wide', () async {
      await seedFiscalYears();
      final branchA = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرع A — B11',
              globalId: const Value('gid-br-a-b11'),
            ),
          );
      final branchB = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرع B — B11',
              globalId: const Value('gid-br-b-b11'),
            ),
          );

      await db.createJournalEntry(
        description: 'إيراد فرع A — B11',
        date: DateTime(2026, 2, 1),
        branchId: branchA,
        lines: [
          JournalLine(accountId: cashId, debit: 1000),
          JournalLine(accountId: revenueId, credit: 1000),
        ],
      );
      await db.createJournalEntry(
        description: 'إيراد فرع B — B11',
        date: DateTime(2026, 2, 2),
        branchId: branchB,
        lines: [
          JournalLine(accountId: cashId, debit: 300),
          JournalLine(accountId: revenueId, credit: 300),
        ],
      );

      // Branch A only: equity net-income must be 1000, NOT 1300 (company-
      // wide). Pre-fix, getBalanceSheet(branchIds:[A]) scoped the equity
      // ACCOUNT balances to branch A (correctly) but forwarded only the
      // (unset) singular branchId to getIncomeStatement, so netProfit came
      // back company-wide (1300) — equity(1000 base + 1300 netProfit)
      // wouldn't even match assets(1000), i.e. NOT balanced.
      final bsA = await db.getBalanceSheet(DateTime(2026, 12, 31),
          branchIds: [branchA]);
      expect(bsA['totalEquity'], closeTo(1000, 0.01),
          reason: 'equity net-income must reflect ONLY branch A (1000)');
      expect(bsA['totalAssets'], closeTo(1000, 0.01));
      expect(bsA['isBalanced'], isTrue);

      final bsBoth = await db.getBalanceSheet(DateTime(2026, 12, 31),
          branchIds: [branchA, branchB]);
      expect(bsBoth['totalEquity'], closeTo(1300, 0.01));
      expect(bsBoth['isBalanced'], isTrue);
    });
  });

  group('REP-1 — GL net-profit accessor sanity', () {
    test(
        'getIncomeStatement netProfit (the value GL-routed screens read) is '
        'revenue minus expense for the requested window', () async {
      await seedFiscalYears();
      await db.createJournalEntry(
        description: 'إيراد — B11 REP-1',
        date: DateTime(2026, 4, 10),
        lines: [
          JournalLine(accountId: cashId, debit: 2000),
          JournalLine(accountId: revenueId, credit: 2000),
        ],
      );
      await db.createJournalEntry(
        description: 'مصروف — B11 REP-1',
        date: DateTime(2026, 4, 15),
        lines: [
          JournalLine(accountId: expenseId, debit: 750),
          JournalLine(accountId: cashId, credit: 750),
        ],
      );

      final income = await db.getIncomeStatement(
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
      );

      expect(income['totalRevenue'], closeTo(2000, 0.01));
      expect(income['totalExpenses'], closeTo(750, 0.01));
      expect(income['netProfit'], closeTo(1250, 0.01));

      // The same figure getBalanceSheet's equity add-on now uses for a
      // same-year atDate — cross-checks the two DAO methods agree.
      final bs = await db.getBalanceSheet(DateTime(2026, 12, 31));
      expect(bs['totalEquity'], closeTo(income['netProfit'] as double, 0.01));
    });
  });
}
