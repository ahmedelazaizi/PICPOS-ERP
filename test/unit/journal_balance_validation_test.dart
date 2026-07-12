// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNTING JOURNAL VALIDATION — Unit Tests (PIR Sprint 6)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

/// Tests for debit = credit validation logic (PIR F6).
///
/// The actual validation is in accounting_dao.dart:19-25.
/// These tests validate the pure comparison logic.
void main() {
  group('Journal Entry Balance Validation (PIR F6)', () {
    test('PASS: balanced entry', () {
      expect(_isBalanced(debit: 1000, credit: 1000), isTrue);
    });

    test('PASS: balanced within tolerance (0.001)', () {
      expect(_isBalanced(debit: 1000, credit: 1000.0005), isTrue);
    });

    test('FAIL: debit > credit', () {
      expect(_isBalanced(debit: 1000, credit: 900), isFalse);
    });

    test('FAIL: credit > debit', () {
      expect(_isBalanced(debit: 900, credit: 1000), isFalse);
    });

    test('PASS: zero entry', () {
      expect(_isBalanced(debit: 0, credit: 0), isTrue);
    });

    test('PASS: large balanced entry', () {
      expect(_isBalanced(debit: 1000000.50, credit: 1000000.50), isTrue);
    });

    test('FAIL: small but significant imbalance', () {
      expect(_isBalanced(debit: 100.01, credit: 100.02), isFalse);
    });

    test('Error message Arabic', () {
      final error = _getImbalanceError(debit: 1000, credit: 950);
      expect(error, isNotNull);
      expect(error!, contains('القيد'));
      expect(error, contains('1000'));
      expect(error, contains('950'));
    });
  });
}

/// Mirrors accounting_dao.dart:23 validation
bool _isBalanced({required double debit, required double credit}) {
  return (debit - credit).abs() <= 0.001;
}

String? _getImbalanceError({required double debit, required double credit}) {
  if ((debit - credit).abs() > 0.001) {
    return 'خطأ في توازن القيد: المدين ($debit) لا يساوي الدائن ($credit)';
  }
  return null;
}
