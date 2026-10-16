// Financial Intelligence — budget targets for KpiComparison.
//
// Pure Dart. The budget model (Budgets / BudgetLines) is PER ACCOUNT: each
// budget row has an accountId and 12 monthly planned amounts. Targets are
// derived from the account's TYPE and CODE, never from its name:
//
//   revenue   : revenue-type accounts under code prefix 41 (sales revenue),
//               minus group 42 (returns & discounts, always subtracted by
//               magnitude). This mirrors the income statement's
//               `totalRevenue`, which excludes the "other income" group 43.
//   expenses  : every expense-type account (COGS 5x, opex 6x, tax 73...).
//   netIncome : revenue-type budgets (all groups, 4x) minus expense budgets.
//               Only produced when BOTH a revenue and an expense budget exist
//               — otherwise the figure would be misleadingly one-sided.
//
// A revenue / net-income target is null when no budget row maps to it, so
// KpiComparison shows "unknown" rather than a variance against zero.
import 'account_classifier.dart';

/// One budget row aggregated to the report window (see the provider for the
/// month → period pro-rating). [amount] is positive in the budget's natural
/// direction; contra-revenue accounts (type revenue, code prefix 42) are
/// subtracted from revenue.
class BudgetEntry {
  const BudgetEntry({required this.accountId, required this.amount});
  final int accountId;
  final double amount;
}

class BudgetTargets {
  const BudgetTargets({this.revenue, this.expenses, this.netIncome});
  const BudgetTargets.none()
      : revenue = null,
        expenses = null,
        netIncome = null;

  final double? revenue;
  final double? expenses;
  final double? netIncome;

  bool get isEmpty => revenue == null && expenses == null && netIncome == null;
}

BudgetTargets aggregateBudget(
  List<AccountRecord> accounts,
  List<BudgetEntry> entries,
) {
  final byId = {for (final a in accounts) a.id: a};
  double? sales;
  double? allRevenue;
  double? expenses;
  for (final e in entries) {
    final a = byId[e.accountId];
    if (a == null || !e.amount.isFinite) continue;
    if (a.accountType == 'revenue' || a.accountType == 'contra_revenue') {
      final contra = a.accountType == 'contra_revenue' || a.code.startsWith('42');
      final signed = contra ? -e.amount.abs() : e.amount;
      allRevenue = (allRevenue ?? 0) + signed;
      if (a.code.startsWith('41') || contra) {
        sales = (sales ?? 0) + signed;
      }
    } else if (a.accountType == 'expense') {
      expenses = (expenses ?? 0) + e.amount;
    }
  }
  return BudgetTargets(
    revenue: sales,
    expenses: expenses,
    netIncome: (allRevenue != null && expenses != null)
        ? allRevenue - expenses
        : null,
  );
}
