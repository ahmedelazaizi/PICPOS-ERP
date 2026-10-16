// Financial Intelligence — Phase 1 (read-only analytics).
//
// An immutable, plain-Dart picture of one period's financial position,
// built from the Map<String,dynamic> results of AccountingReportsDao.
// No database, no Flutter: everything here is testable with literals.
// Cash/inventory/receivables/debt/... come from [ClassifiedBuckets]
// (account code / mapping purpose), never from account names.

import 'account_classifier.dart';

/// Bilingual text (Arabic first). [text] follows the active UI locale.
class Bilingual {
  const Bilingual(this.ar, this.en);
  final String ar;
  final String en;

  /// Picks by locale code (`'en'` → English, anything else → Arabic).
  String resolve(String localeCode) => localeCode == 'en' ? en : ar;
}

double _num(Object? v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : 0.0;
  }
  return 0.0;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

class FinancialSnapshot {
  const FinancialSnapshot({
    this.periodDays = 0,
    this.revenue = 0,
    this.cogs = 0,
    this.grossProfit = 0,
    this.opex = 0,
    this.depreciation = 0,
    this.interest = 0,
    this.tax = 0,
    this.netIncome = 0,
    this.currentAssets = 0,
    this.inventory = 0,
    this.receivables = 0,
    this.cash = 0,
    this.totalAssets = 0,
    this.currentLiabilities = 0,
    this.payables = 0,
    this.totalLiabilities = 0,
    this.equity = 0,
    this.debt = 0,
    this.operatingCashFlow = 0,
    this.investingCashFlow = 0,
    this.financingCashFlow = 0,
  });

  /// Number of days in the income-statement window (for DSO/DPO/DIO).
  final int periodDays;

  // Income statement
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double opex;
  final double depreciation;
  final double interest;
  final double tax;
  final double netIncome;

  // Balance sheet
  final double currentAssets;
  final double inventory;
  final double receivables;
  final double cash;
  final double totalAssets;
  final double currentLiabilities;
  final double payables;
  final double totalLiabilities;
  final double equity;
  final double debt;

  // Cash flow
  final double operatingCashFlow;
  final double investingCashFlow;
  final double financingCashFlow;

  /// Earnings before interest and tax.
  double get ebit => netIncome + interest + tax;

  /// Earnings before interest, tax, depreciation and amortisation.
  double get ebitda => ebit + depreciation;

  /// Builds a snapshot from the existing report maps. Every input is
  /// optional; absent keys, nulls and non-finite numbers become 0.
  ///
  /// Sources (keys as returned by `AccountingReportsDao`):
  /// * [incomeStatement] — `totalRevenue`, `totalCOGS`, `grossProfit`,
  ///   `totalExpenses`, `totalDepreciation`, `netProfit`.
  /// * [balanceSheet] — `totalAssets`, `totalLiabilities`, `totalEquity`.
  /// * [cashFlow] — `operating.net`, `investing.net`, `financing.net`,
  ///   `closingBalance` (cash fallback when no cash account is classified).
  /// * [agedReceivables] / [agedPayables] — sum of `totalBalance`.
  /// * [buckets] — identity-based classification (account code / mapping
  ///   purpose) from `classifyAccounts`. Account names are never inspected.
  ///
  /// Precedence per figure: explicit argument > matched [buckets] value >
  /// documented fallback > 0.
  /// * cash: closing balance of the cash-flow statement.
  /// * receivables / payables: aged reports.
  /// * depreciation: `totalDepreciation` of the income statement.
  /// * currentAssets: cash + inventory + receivables.
  /// * currentLiabilities: totalLiabilities (conservative).
  /// * inventory, debt, interest, tax: 0.
  factory FinancialSnapshot.fromReports({
    required DateTime from,
    required DateTime to,
    Map<String, dynamic>? incomeStatement,
    Map<String, dynamic>? balanceSheet,
    Map<String, dynamic>? cashFlow,
    List<Map<String, dynamic>>? agedReceivables,
    List<Map<String, dynamic>>? agedPayables,
    ClassifiedBuckets? buckets,
    double? inventory,
    double? cash,
    double? receivables,
    double? payables,
    double? currentAssets,
    double? currentLiabilities,
    double? debt,
    double? interest,
    double? tax,
    double? depreciation,
  }) {
    final is_ = incomeStatement ?? const <String, dynamic>{};
    final bs = balanceSheet ?? const <String, dynamic>{};
    final cf = cashFlow ?? const <String, dynamic>{};
    final b = buckets ?? const ClassifiedBuckets.empty();

    final days = to.difference(from).inDays + 1;

    double sumAged(List<Map<String, dynamic>> rows) {
      var t = 0.0;
      for (final r in rows) {
        t += _num(r['totalBalance']);
      }
      return t;
    }

    final cashV =
        cash ?? b.orNull(AccountBucket.cash) ?? _num(cf['closingBalance']);
    final invV = inventory ?? b.orNull(AccountBucket.inventory) ?? 0.0;
    final recV = receivables ??
        b.orNull(AccountBucket.receivables) ??
        (agedReceivables != null ? sumAged(agedReceivables) : 0.0);
    final payV = payables ??
        b.orNull(AccountBucket.payables) ??
        (agedPayables != null ? sumAged(agedPayables) : 0.0);
    final totalLiab = _num(bs['totalLiabilities']);

    return FinancialSnapshot(
      periodDays: days < 0 ? 0 : days,
      revenue: _num(is_['totalRevenue']),
      cogs: _num(is_['totalCOGS']),
      grossProfit: _num(is_['grossProfit']),
      opex: _num(is_['totalExpenses']),
      depreciation: depreciation ??
          b.orNull(AccountBucket.depreciation) ??
          _num(is_['totalDepreciation']),
      interest: interest ?? b.orNull(AccountBucket.interestExpense) ?? 0.0,
      tax: tax ?? b.orNull(AccountBucket.taxExpense) ?? 0.0,
      netIncome: _num(is_['netProfit']),
      currentAssets: currentAssets ??
          b.orNull(AccountBucket.currentAssets) ??
          (cashV + invV + recV),
      inventory: invV,
      receivables: recV,
      cash: cashV,
      totalAssets: _num(bs['totalAssets']),
      currentLiabilities: currentLiabilities ??
          b.orNull(AccountBucket.currentLiabilities) ??
          totalLiab,
      payables: payV,
      totalLiabilities: totalLiab,
      equity: _num(bs['totalEquity']),
      debt: debt ?? b.orNull(AccountBucket.debt) ?? 0.0,
      operatingCashFlow: _num(_map(cf['operating'])['net']),
      investingCashFlow: _num(_map(cf['investing'])['net']),
      financingCashFlow: _num(_map(cf['financing'])['net']),
    );
  }
}
