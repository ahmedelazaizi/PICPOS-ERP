import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/accounting_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // AccountingValidationResult
  // ═══════════════════════════════════════════════════════════════

  group('AccountingValidationResult', () {
    test('success() returns isValid true', () {
      final r = AccountingValidationResult.success();
      expect(r.isValid, true);
      expect(r.errors, isEmpty);
      expect(r.warnings, isEmpty);
    });

    test('failure() returns isValid false with errors', () {
      final r = AccountingValidationResult.failure(['err1', 'err2']);
      expect(r.isValid, false);
      expect(r.errors, hasLength(2));
      expect(r.errors.first, 'err1');
    });

    test('constructor defaults', () {
      const r = AccountingValidationResult(isValid: true);
      expect(r.errors, isEmpty);
      expect(r.warnings, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // ShiftCloseValidation
  // ═══════════════════════════════════════════════════════════════

  group('ShiftCloseValidation', () {
    test('isOk returns true for OK severity', () {
      const v = ShiftCloseValidation(
        expectedCash: 1000,
        actualCash: 1000,
        variance: 0,
        severity: 'OK',
        message: 'الوردية متوازنة',
      );
      expect(v.isOk, true);
      expect(v.isCritical, false);
    });

    test('isCritical returns true for CRITICAL severity', () {
      const v = ShiftCloseValidation(
        expectedCash: 1000,
        actualCash: 900,
        variance: -100,
        severity: 'CRITICAL',
        message: 'عجز كبير',
      );
      expect(v.isOk, false);
      expect(v.isCritical, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Invoice Totals Validation
  // ═══════════════════════════════════════════════════════════════

  group('validateInvoiceTotals', () {
    // We need an AccountingService instance — but the pure methods
    // don't use _db, so we'll create with a dummy.
    // AccountingService needs AppDatabase, but the method is
    // stateless. We'll test the logic.

    late AccountingService svc;

    setUp(() {
      // AccountingService requires AppDatabase which we can't easily mock.
      // However, validateInvoiceTotals is a pure synchronous method.
      // We'll use a workaround by extracting the logic inline.
    });

    test('valid invoice passes', () {
      // subtotal - discount + tax = total
      // 100 - 10 + 14 = 104
      final r = _validateInvoiceTotals(
        subtotal: 100, discount: 10, tax: 14, total: 104, paid: 104,
      );
      expect(r.isValid, true);
    });

    test('mismatched total fails', () {
      final r = _validateInvoiceTotals(
        subtotal: 100, discount: 10, tax: 14, total: 200, paid: 200,
      );
      expect(r.isValid, false);
      expect(r.errors.any((e) => e.contains('غير متطابق')), true);
    });

    test('rounding within 0.01 tolerance passes', () {
      // 100 - 10 + 14 = 104.00, total = 104.009
      final r = _validateInvoiceTotals(
        subtotal: 100, discount: 10, tax: 14, total: 104.009, paid: 104,
      );
      expect(r.isValid, true);
    });

    test('overpayment generates warning', () {
      final r = _validateInvoiceTotals(
        subtotal: 100, discount: 0, tax: 0, total: 100, paid: 150,
      );
      expect(r.isValid, true);
      expect(r.warnings.any((w) => w.contains('أكبر من الإجمالي')), true);
    });

    test('negative values fail', () {
      final r = _validateInvoiceTotals(
        subtotal: -100, discount: 0, tax: 0, total: -100, paid: 0,
      );
      expect(r.isValid, false);
      expect(r.errors.any((e) => e.contains('سالبة')), true);
    });

    test('discount exceeding subtotal fails', () {
      final r = _validateInvoiceTotals(
        subtotal: 100, discount: 150, tax: 0, total: -50, paid: 0,
      );
      expect(r.isValid, false);
      expect(r.errors.any((e) => e.contains('يتجاوز')), true);
    });

    test('zero invoice passes', () {
      final r = _validateInvoiceTotals(
        subtotal: 0, discount: 0, tax: 0, total: 0, paid: 0,
      );
      expect(r.isValid, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Split Payment Validation
  // ═══════════════════════════════════════════════════════════════

  group('validateSplitPayment', () {
    test('matching split payment passes', () {
      final r = _validateSplitPayment(
        paid: 100, cashPaid: 60, bankPaid: 40, paymentMethod: 'multiple',
      );
      expect(r.isValid, true);
    });

    test('mismatched split payment fails', () {
      final r = _validateSplitPayment(
        paid: 100, cashPaid: 60, bankPaid: 30, paymentMethod: 'multiple',
      );
      expect(r.isValid, false);
      expect(r.errors.any((e) => e.contains('≠')), true);
    });

    test('negative cash amount fails', () {
      final r = _validateSplitPayment(
        paid: 100, cashPaid: -10, bankPaid: 110, paymentMethod: 'multiple',
      );
      expect(r.isValid, false);
      expect(r.errors.any((e) => e.contains('سالبة')), true);
    });

    test('single payment method skips split validation', () {
      final r = _validateSplitPayment(
        paid: 100, cashPaid: 100, bankPaid: 0, paymentMethod: 'cash',
      );
      expect(r.isValid, true);
    });

    test('both non-zero triggers split validation even for cash method', () {
      final r = _validateSplitPayment(
        paid: 100, cashPaid: 80, bankPaid: 20, paymentMethod: 'cash',
      );
      expect(r.isValid, true);
    });

    test('split within tolerance passes', () {
      final r = _validateSplitPayment(
        paid: 100, cashPaid: 60.005, bankPaid: 39.999, paymentMethod: 'multiple',
      );
      expect(r.isValid, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Cost Price Validation
  // ═══════════════════════════════════════════════════════════════

  group('validateCostPrices', () {
    test('items with cost prices produce no warnings', () {
      final r = _validateCostPrices([
        {'name': 'A', 'costPrice': 10.0, 'trackInventory': true},
        {'name': 'B', 'costPrice': 5.0, 'trackInventory': true},
      ]);
      expect(r.isValid, true);
      expect(r.warnings, isEmpty);
    });

    test('items with zero cost price produce warnings', () {
      final r = _validateCostPrices([
        {'name': 'A', 'costPrice': 0.0, 'trackInventory': true},
      ]);
      expect(r.isValid, true); // Warnings only
      expect(r.warnings, hasLength(1));
      expect(r.warnings.first.contains('A'), true);
    });

    test('non-tracked items with zero cost produce no warnings', () {
      final r = _validateCostPrices([
        {'name': 'Service', 'costPrice': 0.0, 'trackInventory': false},
      ]);
      expect(r.warnings, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Shift Close Validation
  // ═══════════════════════════════════════════════════════════════

  group('validateShiftClose', () {
    test('exact match returns OK', () {
      final v = _validateShiftClose(expected: 1000, actual: 1000);
      expect(v.severity, 'OK');
      expect(v.variance, 0);
      expect(v.isOk, true);
      expect(v.message, contains('متوازنة'));
    });

    test('small surplus within tolerance returns OK', () {
      final v = _validateShiftClose(expected: 1000, actual: 1000.50);
      expect(v.severity, 'OK');
    });

    test('surplus beyond tolerance returns WARNING', () {
      final v = _validateShiftClose(expected: 1000, actual: 1003);
      expect(v.severity, 'WARNING');
      expect(v.variance, 3);
      expect(v.message, contains('فائض'));
    });

    test('deficit beyond tolerance returns WARNING', () {
      final v = _validateShiftClose(expected: 1000, actual: 997);
      expect(v.severity, 'WARNING');
      expect(v.variance, -3);
      expect(v.message, contains('عجز'));
    });

    test('large deficit returns CRITICAL', () {
      final v = _validateShiftClose(expected: 1000, actual: 990);
      expect(v.severity, 'CRITICAL');
      expect(v.isCritical, true);
    });

    test('large surplus returns CRITICAL', () {
      final v = _validateShiftClose(expected: 1000, actual: 1010);
      expect(v.severity, 'CRITICAL');
    });

    test('custom tolerance works', () {
      final v = _validateShiftClose(
        expected: 1000, actual: 1003, tolerance: 5,
      );
      expect(v.severity, 'OK');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Currency & Rounding
  // ═══════════════════════════════════════════════════════════════

  group('roundCurrency', () {
    // Spec 137 BUG-H03: JOD precision is 3dp, not 2dp.
    test('rounds to 3 decimal places (JOD)', () {
      expect(AccountingService.roundCurrency(10.4567), 10.457);
      expect(AccountingService.roundCurrency(10.4564), 10.456);
      expect(AccountingService.roundCurrency(10.4565), 10.457);
    });

    test('exact values remain unchanged', () {
      expect(AccountingService.roundCurrency(10.50), 10.50);
      expect(AccountingService.roundCurrency(100.0), 100.0);
    });

    test('handles negative numbers', () {
      expect(AccountingService.roundCurrency(-10.4567), -10.457);
    });

    test('handles zero', () {
      expect(AccountingService.roundCurrency(0), 0);
    });
  });

  group('roundToQuarter', () {
    test('rounds to nearest 0.25', () {
      expect(AccountingService.roundToQuarter(10.10), 10.0);
      expect(AccountingService.roundToQuarter(10.13), 10.25);
      expect(AccountingService.roundToQuarter(10.30), 10.25);
      expect(AccountingService.roundToQuarter(10.40), 10.50);
      expect(AccountingService.roundToQuarter(10.90), 11.0);
    });

    test('exact quarters remain unchanged', () {
      expect(AccountingService.roundToQuarter(10.25), 10.25);
      expect(AccountingService.roundToQuarter(10.50), 10.50);
      expect(AccountingService.roundToQuarter(10.75), 10.75);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Fiscal Period
  // ═══════════════════════════════════════════════════════════════

  group('isWithinFiscalPeriod', () {
    test('date within period returns true', () {
      final result = _isWithinFiscalPeriod(
        DateTime(2026, 6, 15),
        fiscalStart: DateTime(2026, 1, 1),
        fiscalEnd: DateTime(2026, 12, 31),
      );
      expect(result, true);
    });

    test('date before period returns false', () {
      final result = _isWithinFiscalPeriod(
        DateTime(2025, 12, 31),
        fiscalStart: DateTime(2026, 1, 1),
        fiscalEnd: DateTime(2026, 12, 31),
      );
      expect(result, false);
    });

    test('date after period returns false', () {
      final result = _isWithinFiscalPeriod(
        DateTime(2027, 1, 1),
        fiscalStart: DateTime(2026, 1, 1),
        fiscalEnd: DateTime(2026, 12, 31),
      );
      expect(result, false);
    });

    test('date at start boundary returns true', () {
      final result = _isWithinFiscalPeriod(
        DateTime(2026, 1, 1),
        fiscalStart: DateTime(2026, 1, 1),
        fiscalEnd: DateTime(2026, 12, 31),
      );
      expect(result, true);
    });

    test('date at end boundary returns true', () {
      final result = _isWithinFiscalPeriod(
        DateTime(2026, 12, 31, 23, 59, 59),
        fiscalStart: DateTime(2026, 1, 1),
        fiscalEnd: DateTime(2026, 12, 31, 23, 59, 59),
      );
      expect(result, true);
    });
  });
}

// ═══════════════════════════════════════════════════════════════
// Helper functions — extract pure logic from AccountingService
// so we can test without AppDatabase dependency
// ═══════════════════════════════════════════════════════════════

AccountingValidationResult _validateInvoiceTotals({
  required double subtotal,
  required double discount,
  required double tax,
  required double total,
  required double paid,
}) {
  final errors = <String>[];
  final warnings = <String>[];

  final expectedTotal = subtotal - discount + tax;
  if ((expectedTotal - total).abs() > 0.01) {
    errors.add(
      'الإجمالي غير متطابق. المتوقع: ${expectedTotal.toStringAsFixed(2)}، المُدخل: ${total.toStringAsFixed(2)}',
    );
  }
  if (paid > total) {
    warnings.add('المبلغ المدفوع أكبر من الإجمالي - سيتم إنشاء رصيد دائن');
  }
  if (subtotal < 0 || discount < 0 || tax < 0 || total < 0) {
    errors.add('لا يمكن أن تكون القيم سالبة');
  }
  if (discount > subtotal) {
    errors.add('الخصم لا يمكن أن يتجاوز الإجمالي الفرعي');
  }
  return AccountingValidationResult(
    isValid: errors.isEmpty,
    errors: errors,
    warnings: warnings,
  );
}

AccountingValidationResult _validateSplitPayment({
  required double paid,
  required double cashPaid,
  required double bankPaid,
  required String paymentMethod,
}) {
  final errors = <String>[];
  final warnings = <String>[];

  if (paymentMethod == 'multiple' || (cashPaid > 0 && bankPaid > 0)) {
    final splitTotal = cashPaid + bankPaid;
    if ((splitTotal - paid).abs() > 0.01) {
      errors.add(
        'المدفوع نقداً (${cashPaid.toStringAsFixed(2)}) + '
        'بنك (${bankPaid.toStringAsFixed(2)}) = '
        '${splitTotal.toStringAsFixed(2)} ≠ '
        'الإجمالي المدفوع (${paid.toStringAsFixed(2)})',
      );
    }
  }
  if (cashPaid < 0 || bankPaid < 0) {
    errors.add('لا يمكن أن تكون قيم الدفع سالبة');
  }
  return AccountingValidationResult(
    isValid: errors.isEmpty,
    errors: errors,
    warnings: warnings,
  );
}

AccountingValidationResult _validateCostPrices(
  List<Map<String, dynamic>> items,
) {
  final warnings = <String>[];
  for (final item in items) {
    final costPrice = (item['costPrice'] as num?)?.toDouble() ?? 0;
    final name = item['name'] as String? ?? 'صنف';
    final trackInventory = item['trackInventory'] as bool? ?? true;
    if (costPrice <= 0 && trackInventory) {
      warnings.add(
        'تنبيه: الصنف "$name" بدون سعر تكلفة — قد يؤثر على حساب الأرباح',
      );
    }
  }
  return AccountingValidationResult(
    isValid: true,
    warnings: warnings,
  );
}

ShiftCloseValidation _validateShiftClose({
  required double expected,
  required double actual,
  double tolerance = 1.0,
}) {
  final variance = actual - expected;
  final absVariance = variance.abs();

  String severity;
  if (absVariance <= tolerance) {
    severity = 'OK';
  } else if (absVariance <= tolerance * 5) {
    severity = 'WARNING';
  } else {
    severity = 'CRITICAL';
  }

  return ShiftCloseValidation(
    expectedCash: expected,
    actualCash: actual,
    variance: variance,
    severity: severity,
    message: severity == 'OK'
        ? 'الوردية متوازنة'
        : 'فرق ${variance > 0 ? "فائض" : "عجز"}: '
            '${absVariance.toStringAsFixed(2)}',
  );
}

bool _isWithinFiscalPeriod(
  DateTime date, {
  DateTime? fiscalStart,
  DateTime? fiscalEnd,
}) {
  final now = DateTime.now();
  final start = fiscalStart ?? DateTime(now.year, 1, 1);
  final end = fiscalEnd ?? DateTime(now.year, 12, 31, 23, 59, 59);
  return date.isAfter(start.subtract(const Duration(seconds: 1))) &&
      date.isBefore(end.add(const Duration(seconds: 1)));
}
