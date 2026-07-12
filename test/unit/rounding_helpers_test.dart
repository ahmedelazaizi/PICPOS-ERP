import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/number_utils.dart';
import 'package:ural_erp/services/accounting_validator.dart';

/// Spec 137 Phase 2 — rounding helpers must use JOD 3dp precision
/// (BUG-H03, BUG-L01).
void main() {
  group('NumberUtils discount/tax helpers round to 3dp (L01)', () {
    test('taxAmount rounds to 3dp', () {
      // 33.333 * 3% = 0.99999 -> 1.000
      expect(NumberUtils.taxAmount(33.333, 3), 1.0);
    });

    test('applyDiscount rounds to 3dp', () {
      // 10 * (1 - 33.333/100) = 6.66670 -> 6.667
      expect(NumberUtils.applyDiscount(10, 33.333), 6.667);
    });

    test('discountAmount rounds to 3dp', () {
      // 33.333 * 3% = 0.99999 -> 1.000
      expect(NumberUtils.discountAmount(33.333, 3), 1.0);
    });

    test('addTax rounds to 3dp', () {
      // 10 * (1 + 33.333/100) = 13.3333 -> 13.333
      expect(NumberUtils.addTax(10, 33.333), 13.333);
    });
  });

  group('AccountingValidator.roundCurrency uses 3dp (H03)', () {
    test('keeps the third decimal place', () {
      expect(AccountingValidator.roundCurrency(1.234), 1.234);
      expect(AccountingValidator.roundCurrency(1.2344), 1.234);
    });
  });
}
