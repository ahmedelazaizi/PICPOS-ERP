// Financial Intelligence — thin read-only provider. Loads the existing
// accounting report maps for a period and its prior period, classifies the
// chart of accounts by CODE / mapping purpose (never by name), reads the
// budget, then hands everything to the pure ratio engine. No writes.
import 'package:drift/drift.dart' show BooleanExpressionOperators, ComparableExpr, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/analytics/account_classifier.dart';
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
    this.comparisons = const [],
  });
  final FinancialSnapshot current;
  final FinancialSnapshot prior;

  /// Ratios for the current period, including growth versus [prior].
  final List<Ratio> ratios;

  /// Budget for the window (null members = no budget row maps to them).
  final BudgetTargets budget;

  /// `revenue` and `net_income` against prior period and budget.
  final List<KpiComparison> comparisons;
}

/// The prior period: same length, ending the day before [from].
FinancialAnalyticsParams priorPeriod(DateTime from, DateTime to) {
  final days = to.difference(from).inDays + 1;
  final priorTo = from.subtract(const Duration(days: 1));
  return (from: priorTo.subtract(Duration(days: days - 1)), to: priorTo);
}

/// Fraction (0..1) of calendar [month] of [year] covered by the inclusive
/// day range [from]..[to]. Budget lines are monthly (BudgetingDao uses
/// calendar month `m` of the fiscal year's start year), so a partial month is
/// pro-rated by days.
double budgetMonthFraction(int year, int month, DateTime from, DateTime to) {
  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 1);
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
  final lo = start.isAfter(monthStart) ? start : monthStart;
  final hi = end.isBefore(monthEnd) ? end : monthEnd;
  if (!hi.isAfter(lo)) return 0.0;
  final overlap = hi.difference(lo).inHours / 24.0;
  final length = monthEnd.difference(monthStart).inHours / 24.0;
  return (overlap / length).clamp(0.0, 1.0);
}

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
Future<Map<String, int>> loadPurposeMap(AppDatabase db) async {
  final rows = await (db.select(db.accountMappings)
        ..where((m) => m.costCenterId.isNull()))
      .get();
  rows.sort((x, y) => x.id.compareTo(y.id)); // later rows win
  return {for (final m in rows) m.purpose: m.accountId};
}

/// Budget rows for [from]..[to]: every fiscal year overlapping the window,
/// every budget (all statuses and cost centres), monthly planned amounts
/// pro-rated by [budgetMonthFraction], summed per account.
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
    for (final b in budgets) {
      final lines = await db.getBudgetLines(b.id);
      for (final l in lines) {
        final f = budgetMonthFraction(fy.startDate.year, l.month, from, to);
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
    return FinancialSnapshot.fromReports(
      from: from,
      to: to,
      incomeStatement: income,
      balanceSheet: balance,
      cashFlow: cash,
      agedReceivables: ar,
      agedPayables: ap,
      buckets: classifyAccounts(accounts, purposes),
    );
  }

  final prev = priorPeriod(params.from, params.to);
  final current = await load(params.from, params.to);
  final prior = await load(prev.from, prev.to);

  final accounts = await loadAccountRecords(db, params.from, params.to,
      allowedBranchIds: allowedBranchIds);
  final budget = aggregateBudget(
    accounts,
    await loadBudgetEntries(db, params.from, params.to),
  );

  return FinancialAnalyticsResult(
    current: current,
    prior: prior,
    ratios: RatioEngine.computeAll(current, prior: prior),
    budget: budget,
    comparisons: [
      KpiComparison(
        key: 'revenue',
        actual: current.revenue,
        direction: GoodDirection.higherBetter,
        prior: prior.revenue,
        budget: budget.revenue,
      ),
      KpiComparison(
        key: 'net_income',
        actual: current.netIncome,
        direction: GoodDirection.higherBetter,
        prior: prior.netIncome,
        budget: budget.netIncome,
      ),
    ],
  );
}

final financialAnalyticsProvider = FutureProvider.family<
    FinancialAnalyticsResult, FinancialAnalyticsParams>((ref, params) async {
  final db = ref.watch(databaseProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  return computeFinancialAnalytics(db, params,
      allowedBranchIds: scope.allowedBranchIds);
});
