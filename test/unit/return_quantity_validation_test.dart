// ═══════════════════════════════════════════════════════════════════════════
// RETURN QUANTITY VALIDATION — Unit Tests (PIR Sprint 4)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

/// Tests for the return quantity validation logic (PIR F9).
///
/// The actual validation in ReturnsRepositoryImpl checks:
///   requestedReturn ≤ (originalQty - alreadyReturned) + 0.001
///
/// These tests validate the pure comparison logic without DB dependency.
void main() {
  group('Return Quantity Validation (PIR F9)', () {
    test('PASS: return exactly what was sold', () {
      expect(_isReturnAllowed(originalQty: 10, alreadyReturned: 0, requestedReturn: 10), isTrue);
    });

    test('PASS: partial return within limit', () {
      expect(_isReturnAllowed(originalQty: 10, alreadyReturned: 0, requestedReturn: 5), isTrue);
    });

    test('PASS: second partial return within remaining', () {
      expect(_isReturnAllowed(originalQty: 10, alreadyReturned: 5, requestedReturn: 5), isTrue);
    });

    test('PASS: return with floating point tolerance', () {
      expect(_isReturnAllowed(originalQty: 10, alreadyReturned: 0, requestedReturn: 10.0009), isTrue);
    });

    test('FAIL: return more than sold', () {
      expect(_isReturnAllowed(originalQty: 10, alreadyReturned: 0, requestedReturn: 11), isFalse);
    });

    test('FAIL: return more than remaining after previous return', () {
      expect(_isReturnAllowed(originalQty: 10, alreadyReturned: 8, requestedReturn: 3), isFalse);
    });

    test('FAIL: return when already fully returned', () {
      expect(_isReturnAllowed(originalQty: 10, alreadyReturned: 10, requestedReturn: 1), isFalse);
    });

    test('PASS: zero return always allowed', () {
      expect(_isReturnAllowed(originalQty: 10, alreadyReturned: 10, requestedReturn: 0), isTrue);
    });

    test('PASS: fractional quantities (weight-based items)', () {
      expect(_isReturnAllowed(originalQty: 2.5, alreadyReturned: 1.0, requestedReturn: 1.5), isTrue);
    });

    test('FAIL: fractional quantities exceeding limit', () {
      expect(_isReturnAllowed(originalQty: 2.5, alreadyReturned: 1.0, requestedReturn: 1.6), isFalse);
    });

    test('Error message contains Arabic text', () {
      final error = _getErrorMessage(originalQty: 10, alreadyReturned: 8, requestedReturn: 3);
      expect(error, isNotNull);
      expect(error!, contains('الكمية المطلوب إرجاعها'));
      expect(error, contains('أكبر من المتاح للإرجاع'));
    });
  });
}

/// Mirrors the validation logic from ReturnsRepositoryImpl.processSalesReturn
bool _isReturnAllowed({
  required double originalQty,
  required double alreadyReturned,
  required double requestedReturn,
}) {
  if (requestedReturn <= 0) return true;
  final maxReturnable = originalQty - alreadyReturned;
  return requestedReturn <= maxReturnable + 0.001;
}

/// Returns the error message if validation fails, null otherwise
String? _getErrorMessage({
  required double originalQty,
  required double alreadyReturned,
  required double requestedReturn,
}) {
  if (requestedReturn <= 0) return null;
  final maxReturnable = originalQty - alreadyReturned;
  if (requestedReturn > maxReturnable + 0.001) {
    return 'الكمية المطلوب إرجاعها (${requestedReturn.toStringAsFixed(2)}) '
        'أكبر من المتاح للإرجاع (${maxReturnable.toStringAsFixed(2)}) '
        'للصنف رقم 1';
  }
  return null;
}
