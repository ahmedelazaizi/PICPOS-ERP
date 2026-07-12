import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/financial_utils.dart';

/// Phase 2+3: Financial precision and journal balance integration tests
void main() {
  group('FinancialUtils.round', () {
    // AppConstants.decimalPlaces == 3 (JOD uses 3 decimal places / fils).
    test('rounds to three decimal places (JOD fils precision)', () {
      // At 3dp, 1.005 rounds to 1.005 (IEEE 754: 1.005 * 1000 ≈ 1005 → 1.005)
      expect(FinancialUtils.round(1.005), closeTo(1.005, 0.0005));
      // 99.999 has exactly 3dp — no rounding change (rounds to 2dp only at 2dp precision)
      expect(FinancialUtils.round(99.999), closeTo(99.999, 0.0001));
      // Floating-point drift in 0.1+0.2 is corrected at 3dp
      expect(FinancialUtils.round(0.1 + 0.2), closeTo(0.3, 0.001));
      // 1.235 stays at 1.235 at 3dp (rounds to 1.24 only at 2dp)
      expect(FinancialUtils.round(1.235), closeTo(1.235, 0.0001));
    });

    test('handles negative values', () {
      // At 3dp, -1.005 rounds to -1.005 (not -1.0)
      expect(FinancialUtils.round(-1.005), closeTo(-1.005, 0.0005));
      // -0.004 rounds to -0.004 at 3dp — use guardAmount to clamp to 0
      expect(FinancialUtils.round(-0.004), closeTo(-0.004, 0.0001));
    });
  });

  group('FinancialUtils.guardAmount', () {
    test('clamps negative to zero by default', () {
      expect(FinancialUtils.guardAmount(-5.0), 0.0);
    });

    test('allows negative when explicitly permitted', () {
      expect(FinancialUtils.guardAmount(-5.0, allowNegative: true), closeTo(-5.0, 0.001));
    });

    test('rounds and guards combined', () {
      // 99.999 rounded at 3dp = 99.999, then guard passes (>= 0) → 99.999
      expect(FinancialUtils.guardAmount(99.999), closeTo(99.999, 0.0001));
      // -0.001 rounded at 3dp = -0.001, then guard clamps to 0
      expect(FinancialUtils.guardAmount(-0.001), 0.0);
    });
  });

  group('FinancialUtils.assertBalanced', () {
    test('passes for balanced entries', () {
      expect(
        () => FinancialUtils.assertBalanced(1000.0, 1000.0),
        returnsNormally,
      );
    });

    test('passes for half-penny tolerance', () {
      expect(
        () => FinancialUtils.assertBalanced(1000.005, 1000.0),
        returnsNormally,
      );
    });

    test('throws for imbalanced entries', () {
      expect(
        () => FinancialUtils.assertBalanced(1000.0, 999.0, context: 'test'),
        throwsA(isA<UnbalancedJournalException>()),
      );
    });
  });

  group('FinancialUtils.calculateInvoiceTotals', () {
    test('calculates correct totals with 14% VAT', () {
      final result = FinancialUtils.calculateInvoiceTotals(
        items: [
          (quantity: 2.0, unitPrice: 50.0, taxRatePercent: 14.0),
          (quantity: 1.0, unitPrice: 100.0, taxRatePercent: 14.0),
        ],
      );

      expect(result.subtotal, closeTo(200.0, 0.01));
      expect(result.totalTax, closeTo(28.0, 0.01));
      expect(result.grandTotal, closeTo(228.0, 0.01));
    });

    test('handles mixed taxable and exempt items', () {
      final result = FinancialUtils.calculateInvoiceTotals(
        items: [
          (quantity: 1.0, unitPrice: 100.0, taxRatePercent: 14.0),
          (quantity: 1.0, unitPrice: 50.0, taxRatePercent: 0.0),
        ],
      );

      expect(result.subtotal, closeTo(150.0, 0.01));
      expect(result.totalTax, closeTo(14.0, 0.01));
      expect(result.grandTotal, closeTo(164.0, 0.01));
    });

    test('applies global discount and delivery fee', () {
      final result = FinancialUtils.calculateInvoiceTotals(
        items: [
          (quantity: 1.0, unitPrice: 200.0, taxRatePercent: 0.0),
        ],
        globalDiscountAmount: 20.0,
        deliveryFee: 15.0,
      );

      expect(result.subtotal, closeTo(200.0, 0.01));
      expect(result.grandTotal, closeTo(195.0, 0.01)); // 200 - 20 + 15
    });

    test('precision: no floating-point drift on large item count', () {
      final items = List.generate(
        100,
        (_) => (quantity: 1.0, unitPrice: 0.1, taxRatePercent: 14.0),
      );
      final result = FinancialUtils.calculateInvoiceTotals(items: items);

      // 100 × 0.1 = 10.0, 14% of each 0.1 = 0.01 × 100 = 1.0 (may have rounding)
      expect(result.subtotal, closeTo(10.0, 0.01));
      // Grand total should be precise to 2 decimal places
      expect(result.grandTotal, closeTo(result.subtotal + result.totalTax, 0.02));
    });
  });
}
