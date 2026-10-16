// Financial Intelligence — KPI comparison against prior period / budget.
import 'ratio_engine.dart' show GoodDirection, safeDiv;

enum Favourability { favourable, unfavourable, neutral, unknown }

/// Variance of [actual] against one [baseline].
class Variance {
  const Variance({
    required this.baseline,
    required this.amount,
    required this.percent,
    required this.favourability,
  });

  final double? baseline;

  /// actual - baseline (null when no baseline).
  final double? amount;

  /// (actual - baseline) / |baseline| x 100 (null when baseline is 0/absent).
  final double? percent;
  final Favourability favourability;
}

/// Computes a variance. Equal values are [Favourability.neutral]; otherwise
/// the sign of the change is judged against [direction].
Variance computeVariance(
  double actual,
  double? baseline,
  GoodDirection direction,
) {
  if (baseline == null || !baseline.isFinite || !actual.isFinite) {
    return const Variance(
      baseline: null,
      amount: null,
      percent: null,
      favourability: Favourability.unknown,
    );
  }
  final diff = actual - baseline;
  final pct = safeDiv(diff, baseline.abs());
  final Favourability f;
  if (diff == 0) {
    f = Favourability.neutral;
  } else if (direction == GoodDirection.higherBetter) {
    f = diff > 0 ? Favourability.favourable : Favourability.unfavourable;
  } else {
    f = diff < 0 ? Favourability.favourable : Favourability.unfavourable;
  }
  return Variance(
    baseline: baseline,
    amount: diff,
    percent: pct == null ? null : pct * 100,
    favourability: f,
  );
}

/// A KPI value compared with prior period and budget.
class KpiComparison {
  KpiComparison({
    required this.key,
    required this.actual,
    required this.direction,
    double? prior,
    double? budget,
  })  : vsPrior = computeVariance(actual, prior, direction),
        vsBudget = computeVariance(actual, budget, direction);

  final String key;
  final double actual;
  final GoodDirection direction;
  final Variance vsPrior;
  final Variance vsBudget;
}
