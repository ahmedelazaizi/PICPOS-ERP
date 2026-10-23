import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/analytics/financial_snapshot.dart';
import 'package:picpos_erp/domain/analytics/kpi_comparison.dart';
import 'package:picpos_erp/domain/analytics/ratio_engine.dart';

// Hand-computed fixture: 30-day period.
const snap = FinancialSnapshot(
  periodDays: 30,
  revenue: 1000,
  cogs: 600,
  grossProfit: 400,
  opex: 200,
  depreciation: 50,
  interest: 20,
  tax: 30,
  netIncome: 100,
  currentAssets: 500,
  inventory: 150,
  receivables: 100,
  cash: 250,
  totalAssets: 1000,
  currentLiabilities: 250,
  payables: 120,
  totalLiabilities: 400,
  equity: 600,
  debt: 200,
  operatingCashFlow: 180,
  investingCashFlow: -80,
);

Map<String, Ratio> byKey(List<Ratio> l) => {for (final r in l) r.key: r};

void main() {
  final all = byKey(RatioEngine.computeAll(snap,
      prior: const FinancialSnapshot(
          revenue: 800, grossProfit: 320, netIncome: 80, totalAssets: 500)));

  void expectVal(String k, double v, RatioStatus st) {
    expect(all[k]!.value, closeTo(v, 1e-9), reason: k);
    expect(all[k]!.status, st, reason: k);
  }

  test('liquidity', () {
    expectVal('current_ratio', 2.0, RatioStatus.good);
    expectVal('quick_ratio', 1.4, RatioStatus.good);
    expectVal('cash_ratio', 1.0, RatioStatus.good);
  });

  test('profitability', () {
    expectVal('gross_margin', 40, RatioStatus.good);
    expectVal('net_margin', 10, RatioStatus.good);
    expectVal('roa', 10, RatioStatus.good);
    expectVal('roe', 100 / 600 * 100, RatioStatus.good);
    // EBITDA = 100 + 20 + 30 + 50 = 200
    expectVal('ebitda_margin', 20, RatioStatus.good);
  });

  test('efficiency', () {
    expectVal('inventory_turnover', 4, RatioStatus.good);
    expectVal('dso', 3, RatioStatus.good); // 100/1000*30
    expectVal('dpo', 6, RatioStatus.bad); // 120/600*30 = 6 (< 15)
    expectVal('asset_turnover', 1, RatioStatus.good);
    expectVal('cash_conversion_cycle', 4.5, RatioStatus.good); // 7.5+3-6
  });

  test('leverage', () {
    expectVal('debt_to_equity', 1 / 3, RatioStatus.good);
    expectVal('debt_to_assets', 0.2, RatioStatus.good);
    expectVal('interest_coverage', 7.5, RatioStatus.good); // 150/20
  });

  test('cash flow', () {
    expectVal('ocf_margin', 18, RatioStatus.good);
    expectVal('ocf_to_current_liabilities', 0.72, RatioStatus.good);
    expectVal('cash_flow_to_net_income', 1.8, RatioStatus.good);
    expectVal('free_cash_flow_margin', 10, RatioStatus.good);
  });

  test('growth vs prior', () {
    expectVal('revenue_growth', 25, RatioStatus.good);
    expectVal('gross_profit_growth', 25, RatioStatus.good);
    expectVal('net_income_growth', 25, RatioStatus.good);
    expectVal('asset_growth', 100, RatioStatus.good);
  });

  test('growth omitted without prior; all groups covered', () {
    final noPrior = RatioEngine.computeAll(snap);
    expect(noPrior.any((r) => r.group == RatioGroup.growth), isFalse);
    expect(RatioEngine.computeAll(snap, prior: snap).map((r) => r.group).toSet(),
        RatioGroup.values.toSet());
  });

  test('zero snapshot yields null values, unknown status, never NaN/Infinity',
      () {
    const zero = FinancialSnapshot();
    for (final r in RatioEngine.computeAll(zero, prior: zero)) {
      expect(r.value, isNull, reason: r.key);
      expect(r.status, RatioStatus.unknown, reason: r.key);
    }
  });

  test('single zero denominators', () {
    const s = FinancialSnapshot(revenue: 100, cogs: 50, interest: 0, netIncome: 10);
    final m = byKey(RatioEngine.computeAll(s));
    expect(m['interest_coverage']!.value, isNull);
    expect(m['inventory_turnover']!.value, isNull);
    expect(m['gross_margin']!.value, 0); // numerator 0, denominator 100
    // CCC needs all three legs
    expect(m['cash_conversion_cycle']!.value, isNull);
  });

  test('status thresholds: warning and bad, lower-better', () {
    expect(gradeValue(1.2, GoodDirection.higherBetter, 1.5, 1.0),
        RatioStatus.warning);
    expect(gradeValue(0.9, GoodDirection.higherBetter, 1.5, 1.0), RatioStatus.bad);
    expect(gradeValue(45, GoodDirection.lowerBetter, 30, 60), RatioStatus.warning);
    expect(gradeValue(90, GoodDirection.lowerBetter, 30, 60), RatioStatus.bad);
    expect(gradeValue(-1, GoodDirection.lowerBetter, 1, 2, negativeIsBad: true),
        RatioStatus.bad);
  });

  test('negative equity makes debt/equity bad', () {
    const s = FinancialSnapshot(debt: 100, equity: -50);
    final r = byKey(RatioEngine.leverage(s))['debt_to_equity']!;
    expect(r.value, -2);
    expect(r.status, RatioStatus.bad);
  });

  // C-7: two negatives must not grade "good". Convention: a negative
  // denominator keeps the value but is graded bad.
  test('ROE with a loss and negative equity is bad, not good', () {
    const s = FinancialSnapshot(netIncome: -10, equity: -50);
    final r = byKey(RatioEngine.profitability(s))['roe']!;
    expect(r.value, closeTo(20, 1e-9)); // (-10 / -50) x 100: the trap value
    expect(r.status, RatioStatus.bad);
  });

  test('ROE with a profit and negative equity is bad', () {
    const s = FinancialSnapshot(netIncome: 10, equity: -50);
    expect(byKey(RatioEngine.profitability(s))['roe']!.status, RatioStatus.bad);
  });

  test('ROE with positive equity is graded as before', () {
    const s = FinancialSnapshot(netIncome: 15, equity: 100);
    expect(byKey(RatioEngine.profitability(s))['roe']!.status, RatioStatus.good);
  });

  test('ROE with zero equity stays unknown', () {
    const s = FinancialSnapshot(netIncome: 15, equity: 0);
    final r = byKey(RatioEngine.profitability(s))['roe']!;
    expect(r.value, isNull);
    expect(r.status, RatioStatus.unknown);
  });

  test('OCF / net income with a net loss is bad even when both are negative',
      () {
    const s = FinancialSnapshot(operatingCashFlow: -20, netIncome: -10);
    final r = byKey(RatioEngine.cashFlow(s))['cash_flow_to_net_income']!;
    expect(r.value, closeTo(2, 1e-9)); // (-20 / -10): would grade "good"
    expect(r.status, RatioStatus.bad);
  });

  test('OCF / net income with positive profit is graded as before', () {
    const s = FinancialSnapshot(operatingCashFlow: 12, netIncome: 10);
    expect(byKey(RatioEngine.cashFlow(s))['cash_flow_to_net_income']!.status,
        RatioStatus.good);
  });

  test('safeDiv', () {
    expect(safeDiv(1, 0), isNull);
    expect(safeDiv(double.nan, 2), isNull);
    expect(safeDiv(1, double.infinity), isNull);
    expect(safeDiv(1, 4), 0.25);
  });

  test('growth uses |prior| so a loss shrinking is positive', () {
    const cur = FinancialSnapshot(netIncome: -50);
    const prev = FinancialSnapshot(netIncome: -100);
    final g = byKey(RatioEngine.growth(cur, prev))['net_income_growth']!;
    expect(g.value, 50);
  });

  test('labels and formulas are present', () {
    for (final r in all.values) {
      expect(r.label.ar, isNotEmpty);
      expect(r.label.en, isNotEmpty);
      expect(r.formula, isNotEmpty);
      expect(r.interpretation.ar, isNotEmpty);
    }
  });

  group('FinancialSnapshot.fromReports', () {
    test('maps report keys', () {
      final s = FinancialSnapshot.fromReports(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 30),
        incomeStatement: {
          'totalRevenue': 1000.0,
          'totalCOGS': 600.0,
          'grossProfit': 400.0,
          'totalExpenses': 200.0,
          'totalDepreciation': 50.0,
          'netProfit': 100.0,
        },
        balanceSheet: {
          'totalAssets': 1000.0,
          'totalLiabilities': 400.0,
          'totalEquity': 600.0,
        },
        cashFlow: {
          'operating': {'net': 180.0},
          'investing': {'net': -80.0},
          'financing': {'net': 0.0},
        },
        agedReceivables: [
          {'totalBalance': 60.0},
          {'totalBalance': 40.0},
        ],
        agedPayables: [
          {'totalBalance': 120.0},
        ],
        // Identity-based figures replace the old name-keyword matching.
        inventory: 150,
        cash: 250,
        debt: 200,
        interest: 20,
      );
      expect(s.periodDays, 30);
      expect(s.revenue, 1000);
      expect(s.interest, 20);
      expect(s.cash, 250);
      expect(s.inventory, 150);
      expect(s.receivables, 100);
      expect(s.payables, 120);
      expect(s.debt, 200);
      expect(s.currentAssets, 500); // 250 + 150 + 100
      expect(s.currentLiabilities, 400);
      expect(s.operatingCashFlow, 180);
      expect(s.investingCashFlow, -80);
      expect(s.ebitda, 170); // 100 + 20 interest + 0 tax + 50 dep
      expect(s.tax, 0);
    });

    test('missing/invalid values default to 0 and overrides win', () {
      final s = FinancialSnapshot.fromReports(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 1),
        incomeStatement: {'totalRevenue': null, 'netProfit': double.nan},
        inventory: 7,
        currentLiabilities: 9,
      );
      expect(s.periodDays, 1);
      expect(s.revenue, 0);
      expect(s.netIncome, 0);
      expect(s.inventory, 7);
      expect(s.currentLiabilities, 9);
      expect(s.cash, 0);
    });
  });

  group('KpiComparison', () {
    test('higher-better: increase favourable', () {
      final c = KpiComparison(
          key: 'rev', actual: 120, direction: GoodDirection.higherBetter,
          prior: 100, budget: 150);
      expect(c.vsPrior.amount, 20);
      expect(c.vsPrior.percent, closeTo(20, 1e-9));
      expect(c.vsPrior.favourability, Favourability.favourable);
      expect(c.vsBudget.amount, -30);
      expect(c.vsBudget.percent, closeTo(-20, 1e-9));
      expect(c.vsBudget.favourability, Favourability.unfavourable);
    });

    test('lower-better: increase unfavourable, decrease favourable', () {
      final up = KpiComparison(
          key: 'dso', actual: 50, direction: GoodDirection.lowerBetter,
          prior: 40, budget: 60);
      expect(up.vsPrior.favourability, Favourability.unfavourable);
      expect(up.vsBudget.favourability, Favourability.favourable);
      expect(up.vsBudget.percent, closeTo(-1 / 6 * 100, 1e-9));
    });

    test('equal is neutral; zero baseline gives null percent; none unknown', () {
      final c = KpiComparison(
          key: 'x', actual: 10, direction: GoodDirection.higherBetter,
          prior: 10, budget: 0);
      expect(c.vsPrior.favourability, Favourability.neutral);
      expect(c.vsBudget.amount, 10);
      expect(c.vsBudget.percent, isNull);
      expect(c.vsBudget.favourability, Favourability.favourable);
      final n = KpiComparison(
          key: 'x', actual: 10, direction: GoodDirection.higherBetter);
      expect(n.vsPrior.favourability, Favourability.unknown);
      expect(n.vsPrior.amount, isNull);
    });

    test('negative baseline uses |baseline| for percent', () {
      final c = KpiComparison(
          key: 'np', actual: -50, direction: GoodDirection.higherBetter,
          prior: -100);
      expect(c.vsPrior.amount, 50);
      expect(c.vsPrior.percent, closeTo(50, 1e-9));
      expect(c.vsPrior.favourability, Favourability.favourable);
    });
  });
}
