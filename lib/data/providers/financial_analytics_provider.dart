// Financial Intelligence — thin read-only provider. Loads the existing
// accounting report maps for a period and its prior period, classifies the
// chart of accounts by CODE / mapping purpose (never by name), reads the
// budget, then hands everything to the pure ratio engine. No writes.
//
// ── Consistency with the existing reports (see test/data/analytics) ─────────
// * revenue / cogs / grossProfit / netIncome / totalAssets / totalLiabilities /
//   equity come straight from `getIncomeStatement` / `getBalanceSheet` with the
//   same `allowedBranchIds`, so they are identical by construction. The
//   account-level SQL here uses the same posted-only AND `is_deleted = false`
//   filter as the trial balance, income statement, balance sheet and cash-flow
//   statement (C-2): a soft-deleted posted entry moves none of them.
// * cash is the GL balance of the same cash/bank subtree the cash-flow
//   statement uses (parent group of the `cash`/`bank` accounts, so per-safe
//   sub-accounts and deposits count); the mapped-account bucket is only the
//   fallback when neither purpose resolves. It equals the statement's
//   closingBalance: the statement counts entries whose reference_type is
//   NULL (manual / approved-draft entries) as operating activity, so it agrees
//   with the GL (and with its own opening balance) for every cash entry.
// * receivables / payables are GL balances of the mapped accounts (branch
//   scoped like the balance sheet); getAgedReceivables/Payables are only the
//   fallback. They are the party sub-ledger (invoice-dated up to `to`; when a
//   branch/region/scope filter is active they total only that scope's open
//   invoices), so they match the GL only while the sub-ledger is in sync with
//   it. The engine keeps following the GL for every scope.
//
// ── Scope limits ────────────────────────────────────────────────────────────
// * Budgets are company-wide: `Budgets` has a cost-centre column but NO branch
//   column. For a branch-restricted view (`allowedBranchIds` that does not
//   cover every branch) the budget is reported as unavailable
//   (`budgetAvailable == false`, all targets null) instead of showing a wrong
//   company-wide target. Per account and fiscal year, company-wide budget rows
//   (cost centre null) win; cost-centre rows are summed only when the account
//   has no company-wide row, so a split budget is never double counted.
// * Mapping purposes are resolved GLOBALLY (`account_mappings.cost_center_id IS
//   NULL`), exactly like the report DAOs (which call `getMappedAccountCode`
//   without a cost centre). The posting engine's cost-centre → parent
//   cost-centre → global walk applies only to cost-centre-scoped postings;
//   this provider has no cost-centre parameter, so cost-centre-scoped views
//   and overrides are NOT supported and override rows are ignored.
// * SQL is dialect-neutral: `?` placeholders, `dateVar` epoch-second binds and
//   `sqlBool` literals only (the same constructs the report DAOs use on
//   PostgreSQL); the fiscal-year lookup uses drift's typed query builder.
import 'package:drift/drift.dart' show BooleanExpressionOperators, ComparableExpr, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/analytics/account_classifier.dart';
import '../../domain/analytics/budget_calendar.dart';
import '../../domain/analytics/budget_targets.dart';
import '../../domain/analytics/financial_snapshot.dart';
import '../../domain/analytics/kpi_comparison.dart';
import '../../domain/analytics/ratio_engine.dart';
import 'providers.dart';

typedef FinancialAnalyticsParams = ({DateTime from, DateTime to});

class FinancialAnalyticsResult {
  const FinancialAnalyticsResult({
    required this.current,
    required this.prior,
    required this.ratios,
    this.budget = const BudgetTargets.none(),
    this.priorBudget = const BudgetTargets.none(),
    this.budgetAvailable = true,
    this.comparisons = const [],
  });
  final FinancialSnapshot current;
  final FinancialSnapshot prior;

  /// Ratios for the current period, including growth versus [prior].
  final List<Ratio> ratios;

  /// Budget for the window (null members = no budget row maps to them).
  final BudgetTargets budget;

  /// Budget for the prior period (same length, ending the day before the
  /// window). Same availability rules as [budget].
  final BudgetTargets priorBudget;

  /// False when budgets cannot be shown for this view (branch-restricted
  /// scope: budgets are company-wide). [budget] and [priorBudget] are then
  /// empty.
  final bool budgetAvailable;

  /// `revenue` and `net_income` against prior period and budget.
  final List<KpiComparison> comparisons;
}

/// The prior period: same number of calendar days, ending (at end of day) the
/// day before [from]. Calendar-date arithmetic only (no Duration: DST-safe).
FinancialAnalyticsParams priorPeriod(DateTime from, DateTime to) {
  final days = DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays +
      1;
  return (
    from: DateTime(from.year, from.month, from.day - days),
    to: DateTime(from.year, from.month, from.day - 1, 23, 59, 59, 999),
  );
}

/// Fraction (0..1) of calendar [month] of [year] covered by the inclusive
/// day range [from]..[to] (partial months are pro-rated by days). Budget lines
/// themselves are mapped with `budgetPeriod` from the fiscal year's real start.
double budgetMonthFraction(int year, int month, DateTime from, DateTime to) =>
    periodFraction(
      BudgetPeriod(DateTime(year, month, 1), DateTime(year, month + 1, 1)),
      from,
      to,
    );

const _plTypes = "('revenue', 'expense', 'contra_revenue')";

/// Accounts with their OWN posted balance: balance-sheet types cumulative up
/// to [to]; revenue/expense types for [from]..[to] only. Signed toward the
/// natural side (see `account_classifier.dart`). Same posted-only and
/// branch-scope rules as `AccountingReportsDao`.
Future<List<AccountRecord>> loadAccountRecords(
  AppDatabase db,
  DateTime from,
  DateTime to, {
  Set<int>? allowedBranchIds,
}) async {
  var scope = '';
  final scopeVars = <Variable>[];
  if (allowedBranchIds != null) {
    if (allowedBranchIds.isEmpty) {
      scope = ' AND 1 = 0';
    } else {
      final ph = allowedBranchIds.map((_) => '?').join(', ');
      scope = ' AND (e.branch_id IN ($ph) OR e.branch_id IS NULL)';
      scopeVars.addAll(allowedBranchIds.map((i) => Variable<int>(i)));
    }
  }
  final rows = await db.customSelect(
    '''
    SELECT l.account_id AS account_id, SUM(l.debit - l.credit) AS net
    FROM journal_entry_lines l
    JOIN journal_entries e ON l.entry_id = e.id
    JOIN accounts a ON l.account_id = a.id
    WHERE e.is_posted = ${db.sqlBool(true)}
      AND e.is_deleted = ${db.sqlBool(false)}
      AND ((a.account_type IN $_plTypes AND e.entry_date BETWEEN ? AND ?)
        OR (a.account_type NOT IN $_plTypes AND e.entry_date <= ?))
      $scope
    GROUP BY l.account_id
    ''',
    variables: [
      db.dateVar(from),
      db.dateVar(to),
      db.dateVar(to),
      ...scopeVars,
    ],
    readsFrom: {db.accounts, db.journalEntryLines, db.journalEntries},
  ).get();
  final net = {
    for (final r in rows)
      r.read<int>('account_id'): (r.data['net'] as num?)?.toDouble() ?? 0.0,
  };

  final accts = await (db.select(db.accounts)
        ..where((a) => a.deletedAt.isNull()))
      .get();
  return [
    for (final a in accts)
      AccountRecord(
        id: a.id,
        code: a.code,
        name: a.name,
        accountType: a.accountType,
        parentId: a.parentId,
        balance: _naturalSign(a.accountType) * (net[a.id] ?? 0.0),
      ),
  ];
}

double _naturalSign(String type) =>
    (type == 'asset' || type == 'contra_asset' || type == 'expense')
        ? 1.0
        : -1.0;

/// Global (non cost-centre) purpose → account id from `account_mappings`.
/// Cost-centre override rows are intentionally ignored (see file header).
Future<Map<String, int>> loadPurposeMap(AppDatabase db) async {
  final rows = await (db.select(db.accountMappings)
        ..where((m) => m.costCenterId.isNull()))
      .get();
  rows.sort((x, y) => x.id.compareTo(y.id)); // later rows win
  return {for (final m in rows) m.purpose: m.accountId};
}

/// The cash & bank subtree, resolved exactly like `getCashFlowStatement`:
/// the PARENT group of the account mapped to `cash` and of the one mapped to
/// `bank` (mapping, else the seeded default code), with all descendants — so
/// per-safe sub-accounts and deposit/bank siblings count. Empty when neither
/// purpose resolves to an account.
Future<Set<int>> loadCashTreeIds(AppDatabase db) async {
  final ids = <int>{};
  for (final purpose in const ['cash', 'bank']) {
    final acc = await db.accountingDao.getAccountByPurpose(purpose);
    if (acc == null) continue;
    ids.addAll(await db.accountSubtreeIds(acc.parentId ?? acc.id));
    ids.add(acc.id);
  }
  return ids;
}

/// True when [allowedBranchIds] narrows the view below the whole company:
/// non-null AND not covering every branch row. (null = unrestricted.)
Future<bool> isBranchRestricted(
  AppDatabase db,
  Set<int>? allowedBranchIds,
) async {
  if (allowedBranchIds == null) return false;
  final all = await (db.select(db.branches)
        ..where((b) => b.deletedAt.isNull()))
      .get();
  if (all.isEmpty) return allowedBranchIds.isEmpty;
  return !allowedBranchIds.containsAll(all.map((b) => b.id));
}

/// Budget rows for [from]..[to]: every fiscal year overlapping the window,
/// every budget status, monthly planned amounts placed on the calendar by
/// `budgetPeriod` (month N = N-th month from the fiscal year's real start),
/// pro-rated by days, summed per account. Company-wide rows win over
/// cost-centre rows for the same account and year (see file header).
Future<List<BudgetEntry>> loadBudgetEntries(
  AppDatabase db,
  DateTime from,
  DateTime to,
) async {
  final years = await (db.select(db.fiscalYears)
        ..where((f) =>
            f.startDate.isSmallerOrEqual(Variable(to)) &
            f.endDate.isBiggerOrEqual(Variable(from))))
      .get();
  final perAccount = <int, double>{};
  for (final fy in years) {
    final budgets = await db.getBudgetsForYear(fy.id);
    final companyWide = {
      for (final b in budgets)
        if (b.costCenterId == null) b.accountId,
    };
    for (final b in budgets) {
      if (b.costCenterId != null && companyWide.contains(b.accountId)) continue;
      final lines = await db.getBudgetLines(b.id);
      for (final l in lines) {
        final p = budgetPeriod(fy.startDate, fy.endDate, l.month);
        final f = periodFraction(p, from, to);
        if (f == 0) continue;
        perAccount[b.accountId] =
            (perAccount[b.accountId] ?? 0) + l.plannedAmount * f;
      }
    }
  }
  return [
    for (final e in perAccount.entries)
      BudgetEntry(accountId: e.key, amount: e.value),
  ];
}

/// Everything the provider does, with an explicit database (testable).
Future<FinancialAnalyticsResult> computeFinancialAnalytics(
  AppDatabase db,
  FinancialAnalyticsParams params, {
  Set<int>? allowedBranchIds,
}) async {
  final purposes = await loadPurposeMap(db);
  final cashTree = await loadCashTreeIds(db);

  Future<FinancialSnapshot> load(DateTime from, DateTime to) async {
    final income = await db.getIncomeStatement(from, to,
        allowedBranchIds: allowedBranchIds);
    final balance =
        await db.getBalanceSheet(to, allowedBranchIds: allowedBranchIds);
    final cash = await db.getCashFlowStatement(from, to,
        allowedBranchIds: allowedBranchIds);
    final ar =
        await db.getAgedReceivables(to, allowedBranchIds: allowedBranchIds);
    final ap =
        await db.getAgedPayables(to, allowedBranchIds: allowedBranchIds);
    final accounts = await loadAccountRecords(db, from, to,
        allowedBranchIds: allowedBranchIds);
    final cashBalance = cashTree.isEmpty
        ? null
        : accounts
            .where((a) => cashTree.contains(a.id))
            .fold<double>(0, (t, a) => t + a.balance);
    return FinancialSnapshot.fromReports(
      from: from,
      to: to,
      incomeStatement: income,
      balanceSheet: balance,
      cashFlow: cash,
      agedReceivables: ar,
      agedPayables: ap,
      buckets: classifyAccounts(accounts, purposes),
      cash: cashBalance,
    );
  }

  Future<BudgetTargets> budgetFor(DateTime from, DateTime to) async {
    final accounts = await loadAccountRecords(db, from, to);
    return aggregateBudget(accounts, await loadBudgetEntries(db, from, to));
  }

  final prev = priorPeriod(params.from, params.to);
  final current = await load(params.from, params.to);
  final prior = await load(prev.from, prev.to);

  final budgetAvailable = !await isBranchRestricted(db, allowedBranchIds);
  final budget = budgetAvailable
      ? await budgetFor(params.from, params.to)
      : const BudgetTargets.none();
  final priorBudget = budgetAvailable
      ? await budgetFor(prev.from, prev.to)
      : const BudgetTargets.none();

  return FinancialAnalyticsResult(
    current: current,
    prior: prior,
    ratios: RatioEngine.computeAll(current, prior: prior),
    budget: budget,
    priorBudget: priorBudget,
    budgetAvailable: budgetAvailable,
    comparisons: [
      KpiComparison(
        key: 'revenue',
        actual: current.revenue,
        direction: GoodDirection.higherBetter,
        prior: prior.revenue,
        budget: budget.revenue,
        priorBudget: priorBudget.revenue,
      ),
      KpiComparison(
        key: 'net_income',
        actual: current.netIncome,
        direction: GoodDirection.higherBetter,
        prior: prior.netIncome,
        budget: budget.netIncome,
        priorBudget: priorBudget.netIncome,
      ),
    ],
  );
}

// autoDispose (C-8): recomputed when re-listened instead of staying stale after
// a journal entry is posted (finIndicatorsProvider, the screen's, already is).
final financialAnalyticsProvider = FutureProvider.autoDispose.family<
    FinancialAnalyticsResult, FinancialAnalyticsParams>((ref, params) async {
  final db = ref.watch(databaseProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  return computeFinancialAnalytics(db, params,
      allowedBranchIds: scope.allowedBranchIds);
});
