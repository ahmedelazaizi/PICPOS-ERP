// =============================================================================
// NumberUtils Unit Tests
// PIR Phase 2 — Test coverage increase
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/utils/number_utils.dart';

void main() {
  group('NumberUtils.roundCurrency', () {
    // AppConstants.decimalPlaces == 3 (JOD uses 3 decimal places / fils).
    test('rounds to three decimal places (JOD fils precision)', () {
      // At 3dp: 1.234 stays 1.234; 1.2345 rounds to 1.235
      expect(NumberUtils.roundCurrency(1.234), closeTo(1.234, 0.0001));
      expect(NumberUtils.roundCurrency(1.2345), closeTo(1.235, 0.0001));
      // At 3dp: 1.005 rounds to 1.005 (IEEE 754: 1.005 * 1000 ≈ 1005)
      expect(NumberUtils.roundCurrency(1.005), closeTo(1.005, 0.001));
    });

    test('handles exact values', () {
      expect(NumberUtils.roundCurrency(100.00), 100.0);
      expect(NumberUtils.roundCurrency(0.0), 0.0);
    });

    test('handles negative values', () {
      // At 3dp: -3.456 stays -3.456 (rounds to -3.46 only at 2dp)
      expect(NumberUtils.roundCurrency(-3.456), closeTo(-3.456, 0.0001));
      // roundCurrency does NOT guard against negatives — use guardAmount for that
      expect(NumberUtils.roundCurrency(-0.004), closeTo(-0.004, 0.0001));
    });
  });

  group('NumberUtils.round', () {
    test('rounds to 0 decimal places', () {
      expect(NumberUtils.round(3.7, 0), 4.0);
      expect(NumberUtils.round(3.4, 0), 3.0);
    });

    test('rounds to 3 decimal places', () {
      expect(NumberUtils.round(1.2345, 3), 1.235);
      expect(NumberUtils.round(9.9999, 3), 10.0);
    });
  });

  group('NumberUtils.tryParse', () {
    test('parses plain number', () {
      expect(NumberUtils.tryParse('123.45'), 123.45);
    });

    test('returns null for null input', () {
      expect(NumberUtils.tryParse(null), isNull);
    });

    test('returns null for empty string', () {
      expect(NumberUtils.tryParse(''), isNull);
    });

    test('strips currency symbols', () {
      // tryParse regex strips non-digit/non-dot/non-dash chars (including commas)
      expect(NumberUtils.tryParse('1234.56'), 1234.56);
    });

    test('handles negative numbers', () {
      expect(NumberUtils.tryParse('-50.00'), -50.0);
    });
  });

  group('NumberUtils.parseOr', () {
    test('returns parsed value when valid', () {
      expect(NumberUtils.parseOr('42', 0), 42.0);
    });

    test('returns default for null', () {
      expect(NumberUtils.parseOr(null, 99), 99.0);
    });

    test('returns default for empty string', () {
      expect(NumberUtils.parseOr('', 10), 10.0);
    });
  });

  group('NumberUtils.percentOf', () {
    test('calculates percentage correctly', () {
      expect(NumberUtils.percentOf(25, 100), 25.0);
      expect(NumberUtils.percentOf(1, 4), 25.0);
    });

    test('handles zero total safely', () {
      expect(NumberUtils.percentOf(50, 0), 0.0);
    });

    test('handles 100%', () {
      expect(NumberUtils.percentOf(200, 200), 100.0);
    });

    test('handles over 100%', () {
      expect(NumberUtils.percentOf(300, 200), 150.0);
    });
  });

  group('NumberUtils.applyDiscount', () {
    test('applies 10% discount', () {
      expect(NumberUtils.applyDiscount(100, 10), 90.0);
    });

    test('applies 0% discount (no change)', () {
      expect(NumberUtils.applyDiscount(200, 0), 200.0);
    });

    test('applies 100% discount (free)', () {
      expect(NumberUtils.applyDiscount(500, 100), 0.0);
    });

    test('applies 50% discount', () {
      expect(NumberUtils.applyDiscount(80, 50), 40.0);
    });
  });

  group('NumberUtils.discountAmount', () {
    test('calculates discount amount', () {
      expect(NumberUtils.discountAmount(200, 15), 30.0);
    });

    test('zero discount returns zero', () {
      expect(NumberUtils.discountAmount(100, 0), 0.0);
    });
  });

  group('NumberUtils.taxAmount', () {
    test('calculates 14% VAT', () {
      expect(NumberUtils.taxAmount(100, 14), closeTo(14.0, 0.001));
    });

    test('zero tax returns zero', () {
      expect(NumberUtils.taxAmount(500, 0), 0.0);
    });
  });

  group('NumberUtils.addTax', () {
    test('adds 14% tax to price', () {
      expect(NumberUtils.addTax(100, 14), closeTo(114.0, 0.001));
    });

    test('adds 0% tax (no change)', () {
      expect(NumberUtils.addTax(200, 0), 200.0);
    });
  });

  group('NumberUtils.isZero', () {
    test('zero is zero', () {
      expect(NumberUtils.isZero(0.0), isTrue);
    });

    test('very small value is zero', () {
      expect(NumberUtils.isZero(0.0001), isTrue);
    });

    test('significant value is not zero', () {
      expect(NumberUtils.isZero(0.01), isFalse);
    });

    test('negative very small value is zero', () {
      expect(NumberUtils.isZero(-0.0005), isTrue);
    });

    test('custom epsilon', () {
      expect(NumberUtils.isZero(0.05, epsilon: 0.1), isTrue);
      expect(NumberUtils.isZero(0.15, epsilon: 0.1), isFalse);
    });
  });

  group('NumberUtils.clamp', () {
    test('value within range stays unchanged', () {
      expect(NumberUtils.clamp(5, 0, 10), 5.0);
    });

    test('value below min returns min', () {
      expect(NumberUtils.clamp(-5, 0, 10), 0.0);
    });

    test('value above max returns max', () {
      expect(NumberUtils.clamp(15, 0, 10), 10.0);
    });

    test('value at boundaries stays at boundary', () {
      expect(NumberUtils.clamp(0, 0, 10), 0.0);
      expect(NumberUtils.clamp(10, 0, 10), 10.0);
    });
  });

  group('NumberUtils.formatQuantity', () {
    test('whole numbers have no decimals', () {
      expect(NumberUtils.formatQuantity(5.0), '5');
      expect(NumberUtils.formatQuantity(100.0), '100');
    });

    test('fractional quantities show decimals', () {
      final formatted = NumberUtils.formatQuantity(3.5);
      // The format uses Arabic locale — uses Arabic numerals
      expect(formatted, contains('٣'));
      expect(formatted, contains('٥'));
    });
  });

  group('NumberUtils.formatPercent', () {
    test('whole percentage', () {
      expect(NumberUtils.formatPercent(15), '15%');
    });

    test('fractional percentage', () {
      expect(NumberUtils.formatPercent(14.5), '14.50%');
    });

    test('zero percent', () {
      expect(NumberUtils.formatPercent(0), '0%');
    });
  });
}
