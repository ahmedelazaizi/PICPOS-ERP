// ═══════════════════════════════════════════════════════════════════════════
// PIR PHASE 3 — AccountingValidator Unit Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests for pure validation methods: invoice totals, split payment,
// cost price, shift close variance, currency rounding, fiscal period.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/accounting_validator.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';

// Minimal stubs
class _StubAcctRepo implements IAccountingRepository {
  @override dynamic noSuchMethod(Invocation i) => null;
}
class _StubPartiesRepo implements IPartiesRepository {
  @override dynamic noSuchMethod(Invocation i) => null;
}
class _StubTreasuryRepo implements ITreasuryRepository {
  @override dynamic noSuchMethod(Invocation i) => null;
}
class _StubProductRepo implements IProductRepository {
  @override dynamic noSuchMethod(Invocation i) => null;
}
class _StubInventoryRepo implements InventoryRepository {
  @override dynamic noSuchMethod(Invocation i) => null;
}
class _StubSettingsRepo implements ISettingsRepository {
  @override dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  late AccountingValidator validator;

  setUp(() {
    validator = AccountingValidator(
      _StubAcctRepo(),
      _StubPartiesRepo(),
      _StubTreasuryRepo(),
      _StubProductRepo(),
      _StubInventoryRepo(),
      _StubSettingsRepo(),
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // Invoice Totals Validation
  // ───────────────────────────────────────────────────────────────────────
  group('validateInvoiceTotals', () {
    test('accepts matching totals', () {
      final result = validator.validateInvoiceTotals(
        subtotal: 100, discount: 10, tax: 12.6, total: 102.6, paid: 102.6,
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('rejects mismatched total', () {
      final result = validator.validateInvoiceTotals(
        subtotal: 100, discount: 0, tax: 14, total: 120, paid: 120,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('غير متطابق'));
    });

    test('warns when paid > total', () {
      final result = validator.validateInvoiceTotals(
        subtotal: 100, discount: 0, tax: 0, total: 100, paid: 120,
      );
      expect(result.isValid, isTrue);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('رصيد دائن'));
    });

    test('rejects negative values', () {
      final result = validator.validateInvoiceTotals(
        subtotal: -100, discount: 0, tax: 0, total: -100, paid: 0,
      );
      expect(result.isValid, isFalse);
    });

    test('rejects discount > subtotal', () {
      final result = validator.validateInvoiceTotals(
        subtotal: 100, discount: 150, tax: 0, total: -50, paid: 0,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('الخصم')), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Split Payment Validation (PIR F8)
  // ───────────────────────────────────────────────────────────────────────
  group('validateSplitPayment', () {
    test('accepts balanced split', () {
      final result = validator.validateSplitPayment(
        paid: 200, cashPaid: 100, bankPaid: 100, paymentMethod: 'multiple',
      );
      expect(result.isValid, isTrue);
    });

    test('rejects unbalanced split', () {
      final result = validator.validateSplitPayment(
        paid: 200, cashPaid: 100, bankPaid: 50, paymentMethod: 'multiple',
      );
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('≠'));
    });

    test('accepts balanced split with click', () {
      final result = validator.validateSplitPayment(
        paid: 300, cashPaid: 100, bankPaid: 100, clickPaid: 100,
        paymentMethod: 'mixed',
      );
      expect(result.isValid, isTrue);
    });

    test('rejects negative payment values', () {
      final result = validator.validateSplitPayment(
        paid: 100, cashPaid: -50, bankPaid: 150, paymentMethod: 'multiple',
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('سالبة')), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Cost Price Validation (PIR F4)
  // ───────────────────────────────────────────────────────────────────────
  group('validateCostPrices', () {
    test('warns on zero cost price for tracked items', () {
      final result = validator.validateCostPrices(items: [
        {'name': 'مادة أ', 'costPrice': 0, 'trackInventory': true},
      ]);
      expect(result.isValid, isTrue); // Warnings only, not errors
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('بدون سعر تكلفة'));
    });

    test('no warning for non-tracked items with zero cost', () {
      final result = validator.validateCostPrices(items: [
        {'name': 'خدمة', 'costPrice': 0, 'trackInventory': false},
      ]);
      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('no warning for items with valid cost price', () {
      final result = validator.validateCostPrices(items: [
        {'name': 'منتج', 'costPrice': 50.0, 'trackInventory': true},
      ]);
      expect(result.warnings, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Shift Close Validation (PIR F10)
  // ───────────────────────────────────────────────────────────────────────
  group('validateShiftClose', () {
    test('OK when within tolerance', () {
      final result = validator.validateShiftClose(
        expectedCash: 1000, actualCash: 1000.5, tolerance: 1.0,
      );
      expect(result.severity, 'OK');
      expect(result.isOk, isTrue);
      expect(result.isCritical, isFalse);
    });

    test('WARNING when variance > tolerance but ≤ 5× tolerance', () {
      final result = validator.validateShiftClose(
        expectedCash: 1000, actualCash: 997, tolerance: 1.0,
      );
      expect(result.severity, 'WARNING');
      expect(result.isOk, isFalse);
      expect(result.isCritical, isFalse);
    });

    test('CRITICAL when variance > 5× tolerance', () {
      final result = validator.validateShiftClose(
        expectedCash: 1000, actualCash: 980, tolerance: 1.0,
      );
      expect(result.severity, 'CRITICAL');
      expect(result.isCritical, isTrue);
    });

    test('surplus is positive variance', () {
      final result = validator.validateShiftClose(
        expectedCash: 1000, actualCash: 1010, tolerance: 1.0,
      );
      expect(result.variance, 10.0);
      expect(result.message, contains('فائض'));
    });

    test('shortage is negative variance', () {
      final result = validator.validateShiftClose(
        expectedCash: 1000, actualCash: 990, tolerance: 1.0,
      );
      expect(result.variance, -10.0);
      expect(result.message, contains('عجز'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Currency Rounding
  // ───────────────────────────────────────────────────────────────────────
  group('Currency rounding', () {
    // Spec 137 BUG-H03: JOD precision is 3dp, not 2dp.
    test('roundCurrency rounds to 3 decimals (JOD)', () {
      expect(AccountingValidator.roundCurrency(10.5555), 10.556);
      expect(AccountingValidator.roundCurrency(10.5544), 10.554);
      expect(AccountingValidator.roundCurrency(0.0001), 0.0);
    });

    test('roundToQuarter rounds to nearest 0.25', () {
      expect(AccountingValidator.roundToQuarter(10.12), 10.0);
      expect(AccountingValidator.roundToQuarter(10.13), 10.25);
      expect(AccountingValidator.roundToQuarter(10.37), 10.25);
      expect(AccountingValidator.roundToQuarter(10.38), 10.5);
    });

    test('formatCurrency includes symbol', () {
      final formatted = AccountingValidator.formatCurrency(1234.5);
      expect(formatted, contains('1234.50'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Fiscal Period Check (sync)
  // ───────────────────────────────────────────────────────────────────────
  group('isWithinFiscalPeriod', () {
    test('returns true for date within period', () {
      expect(
        validator.isWithinFiscalPeriod(
          DateTime(2026, 6, 15),
          fiscalStart: DateTime(2026, 1, 1),
          fiscalEnd: DateTime(2026, 12, 31),
        ),
        isTrue,
      );
    });

    test('returns false for date before period', () {
      expect(
        validator.isWithinFiscalPeriod(
          DateTime(2025, 6, 15),
          fiscalStart: DateTime(2026, 1, 1),
          fiscalEnd: DateTime(2026, 12, 31),
        ),
        isFalse,
      );
    });

    test('returns false for date after period', () {
      expect(
        validator.isWithinFiscalPeriod(
          DateTime(2027, 3, 1),
          fiscalStart: DateTime(2026, 1, 1),
          fiscalEnd: DateTime(2026, 12, 31),
        ),
        isFalse,
      );
    });
  });
}
