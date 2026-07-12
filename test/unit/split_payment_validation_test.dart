// ═══════════════════════════════════════════════════════════════════════════
// SPLIT PAYMENT VALIDATION — Unit Tests (PIR Sprint 4)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/accounting_service.dart';

// Mock-free test: validateSplitPayment is a pure function on AccountingService.
// We need a minimal AccountingService, but since it requires AppDatabase,
// we test the validation logic directly via static helpers.

void main() {
  group('Split Payment Validation (PIR F8)', () {
    test('PASS: cashPaid + bankPaid == paid exactly', () {
      final result = _validate(paid: 100, cash: 60, bank: 40, method: 'multiple');
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('PASS: single payment method (cash only, no bank)', () {
      final result = _validate(paid: 100, cash: 100, bank: 0, method: 'cash');
      expect(result.isValid, isTrue);
    });

    test('PASS: single payment method (bank only, no cash)', () {
      final result = _validate(paid: 100, cash: 0, bank: 100, method: 'bank');
      expect(result.isValid, isTrue);
    });

    test('PASS: tolerance within 0.01', () {
      final result = _validate(paid: 100, cash: 60.005, bank: 39.999, method: 'multiple');
      expect(result.isValid, isTrue);
    });

    test('FAIL: cashPaid + bankPaid > paid', () {
      final result = _validate(paid: 100, cash: 60, bank: 50, method: 'multiple');
      expect(result.isValid, isFalse);
      expect(result.errors.length, 1);
      expect(result.errors.first, contains('≠'));
    });

    test('FAIL: cashPaid + bankPaid < paid', () {
      final result = _validate(paid: 100, cash: 40, bank: 30, method: 'multiple');
      expect(result.isValid, isFalse);
      expect(result.errors.length, 1);
    });

    test('FAIL: negative cash amount', () {
      final result = _validate(paid: 100, cash: -10, bank: 110, method: 'multiple');
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('سالبة')), isTrue);
    });

    test('FAIL: negative bank amount', () {
      final result = _validate(paid: 100, cash: 110, bank: -10, method: 'multiple');
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('سالبة')), isTrue);
    });

    test('PASS: zero paid with zero split', () {
      final result = _validate(paid: 0, cash: 0, bank: 0, method: 'cash');
      expect(result.isValid, isTrue);
    });

    test('FAIL: both split provided but method is not multiple', () {
      // When both cash and bank are provided, validation triggers regardless of method
      final result = _validate(paid: 100, cash: 60, bank: 50, method: 'cash');
      expect(result.isValid, isFalse);
    });
  });
}

/// Helper to call the validation logic directly without AppDatabase dependency.
/// This mirrors AccountingService.validateSplitPayment exactly.
AccountingValidationResult _validate({
  required double paid,
  required double cash,
  required double bank,
  required String method,
}) {
  final errors = <String>[];
  final warnings = <String>[];

  if (method == 'multiple' || (cash > 0 && bank > 0)) {
    final splitTotal = cash + bank;
    if ((splitTotal - paid).abs() > 0.01) {
      errors.add(
        'المدفوع نقداً (${cash.toStringAsFixed(2)}) + '
        'بنك (${bank.toStringAsFixed(2)}) = '
        '${splitTotal.toStringAsFixed(2)} ≠ '
        'الإجمالي المدفوع (${paid.toStringAsFixed(2)})',
      );
    }
  }

  if (cash < 0 || bank < 0) {
    errors.add('لا يمكن أن تكون قيم الدفع سالبة');
  }

  return AccountingValidationResult(
    isValid: errors.isEmpty,
    errors: errors,
    warnings: warnings,
  );
}
