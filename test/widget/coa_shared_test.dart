import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/screens/coa/coa_shared.dart';

/// Tests for the extracted COA shared types and utilities.
void main() {
  group('AccountTypeInfo', () {
    test('kAccountTypeConfig contains all 5 account types', () {
      expect(kAccountTypeConfig.length, 5);
      expect(kAccountTypeConfig.containsKey('asset'), true);
      expect(kAccountTypeConfig.containsKey('liability'), true);
      expect(kAccountTypeConfig.containsKey('equity'), true);
      expect(kAccountTypeConfig.containsKey('revenue'), true);
      expect(kAccountTypeConfig.containsKey('expense'), true);
    });

    test('asset type has correct Arabic label', () {
      final asset = kAccountTypeConfig['asset']!;
      expect(asset.label, 'الأصول');
      expect(asset.range, '1xxx');
    });

    test('liability type has correct Arabic label', () {
      final liability = kAccountTypeConfig['liability']!;
      expect(liability.label, 'الخصوم');
      expect(liability.range, '2xxx');
    });

    test('equity type has correct Arabic label', () {
      final equity = kAccountTypeConfig['equity']!;
      expect(equity.label, 'حقوق الملكية');
      expect(equity.range, '3xxx');
    });

    test('revenue type has correct Arabic label', () {
      final revenue = kAccountTypeConfig['revenue']!;
      expect(revenue.label, 'الإيرادات');
      expect(revenue.range, '4xxx');
    });

    test('expense type has correct Arabic label', () {
      final expense = kAccountTypeConfig['expense']!;
      expect(expense.label, 'المصروفات');
      expect(expense.range, '5xxx');
    });
  });

  group('formatAccountAmount', () {
    // AppConstants.decimalPlaces == 3 (JOD uses 3 decimal places / fils).
    // All expectations use 3 dp; near-zero guard is an early-return at |x| < 0.01.
    test('formats positive amount correctly', () {
      expect(formatAccountAmount(1234.56), '1234.560');
    });

    test('formats zero as 0.00', () {
      expect(formatAccountAmount(0.0), '0.00');
    });

    test('treats near-zero amount as 0.00', () {
      expect(formatAccountAmount(0.005), '0.00');
      expect(formatAccountAmount(-0.005), '0.00');
    });

    test('formats negative amount correctly', () {
      expect(formatAccountAmount(-500.75), '-500.750');
    });

    test('rounds to three decimal places (JOD fils precision)', () {
      // 99.9999 → rounds up to 100.000 at 3 dp
      expect(formatAccountAmount(99.9999), '100.000');
      // 99.999 already has 3 dp — no rounding change
      expect(formatAccountAmount(99.999), '99.999');
    });
  });
}
