import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/analytics/budget_calendar.dart';

void main() {
  group('addMonthsClamped', () {
    test('keeps the day and rolls the year', () {
      expect(addMonthsClamped(DateTime(2025, 7, 1), 6), DateTime(2026, 1, 1));
      expect(addMonthsClamped(DateTime(2025, 7, 1), 12), DateTime(2026, 7, 1));
    });
    test('clamps to the target month length', () {
      expect(addMonthsClamped(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonthsClamped(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
    });
  });

  group('budgetPeriod', () {
    final start = DateTime(2025, 7, 1);
    final end = DateTime(2026, 6, 30);

    test('January fiscal year: month N is calendar month N', () {
      final p = budgetPeriod(DateTime(2026, 1, 1), DateTime(2026, 12, 31), 3);
      expect(p.start, DateTime(2026, 3, 1));
      expect(p.endExclusive, DateTime(2026, 4, 1));
    });

    test('July fiscal year: month 1 = July, month 12 = June next year', () {
      expect(budgetPeriod(start, end, 1).start, DateTime(2025, 7, 1));
      expect(budgetPeriod(start, end, 7).start, DateTime(2026, 1, 1));
      final last = budgetPeriod(start, end, 12);
      expect(last.start, DateTime(2026, 6, 1));
      expect(last.endExclusive, DateTime(2026, 7, 1));
    });

    test('mid-month start shifts every boundary', () {
      final p = budgetPeriod(DateTime(2025, 7, 15), DateTime(2026, 7, 14), 2);
      expect(p.start, DateTime(2025, 8, 15));
      expect(p.endExclusive, DateTime(2025, 9, 15));
    });

    test('the last period is capped at the fiscal year end', () {
      final p = budgetPeriod(DateTime(2026, 1, 1), DateTime(2026, 3, 15), 3);
      expect(p.endExclusive, DateTime(2026, 3, 16));
      // a month entirely after the year is empty
      expect(budgetPeriod(DateTime(2026, 1, 1), DateTime(2026, 3, 15), 4).isEmpty,
          isTrue);
    });

    test('months outside 1..12 are empty', () {
      expect(budgetPeriod(start, end, 0).isEmpty, isTrue);
      expect(budgetPeriod(start, end, 13).isEmpty, isTrue);
    });
  });

  group('periodFraction', () {
    final jan = BudgetPeriod(DateTime(2026, 1, 1), DateTime(2026, 2, 1));
    test('full, partial and disjoint windows', () {
      expect(periodFraction(jan, DateTime(2026, 1, 1), DateTime(2026, 1, 31)), 1);
      expect(periodFraction(jan, DateTime(2026, 1, 1), DateTime(2026, 1, 15)),
          closeTo(15 / 31, 1e-12));
      expect(periodFraction(jan, DateTime(2025, 12, 1), DateTime(2026, 3, 1)), 1);
      expect(periodFraction(jan, DateTime(2026, 2, 1), DateTime(2026, 2, 28)), 0);
      expect(periodFraction(jan, DateTime(2025, 12, 1), DateTime(2025, 12, 31)),
          0);
    });
    test('an empty period is 0', () {
      final e = BudgetPeriod(DateTime(2026, 1, 1), DateTime(2026, 1, 1));
      expect(periodFraction(e, DateTime(2026, 1, 1), DateTime(2026, 1, 31)), 0);
    });
  });
}
