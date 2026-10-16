import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/analytics/kpi_comparison.dart';
import 'package:ural_erp/domain/analytics/ratio_engine.dart';

void main() {
  test('prior-period budget: prior vs its own target and target change', () {
    final k = KpiComparison(
      key: 'revenue',
      actual: 120,
      direction: GoodDirection.higherBetter,
      prior: 80,
      budget: 110,
      priorBudget: 100,
    );
    expect(k.vsBudget.amount, 10);
    expect(k.priorVsBudget.amount, -20); // prior missed its own 100 target
    expect(k.priorVsBudget.favourability, Favourability.unfavourable);
    expect(k.budgetChange.amount, 10); // target raised 100 -> 110
    expect(k.budgetChange.baseline, 100);
  });

  test('missing inputs make the prior-budget variances unknown', () {
    final noPriorBudget = KpiComparison(
      key: 'revenue',
      actual: 1,
      direction: GoodDirection.higherBetter,
      prior: 1,
      budget: 1,
    );
    expect(noPriorBudget.priorVsBudget.favourability, Favourability.unknown);
    expect(noPriorBudget.budgetChange.favourability, Favourability.unknown);
    final noPrior = KpiComparison(
      key: 'revenue',
      actual: 1,
      direction: GoodDirection.higherBetter,
      budget: 1,
      priorBudget: 1,
    );
    expect(noPrior.priorVsBudget.favourability, Favourability.unknown);
    expect(noPrior.budgetChange.favourability, Favourability.neutral);
  });
}
