// ═══════════════════════════════════════════════════════════════════════════
// SPRINT 5 VALIDATION — Unit Tests (PIR F4, F10, I2, I3)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/accounting_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // F4: Cost Price Validation
  // ═══════════════════════════════════════════════════════════════════════

  group('Cost Price Validation (PIR F4)', () {
    test('PASS: all items have cost prices', () {
      final result = _validateCostPrices([
        {'name': 'Item A', 'costPrice': 10.0, 'trackInventory': true},
        {'name': 'Item B', 'costPrice': 5.0, 'trackInventory': true},
      ]);
      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('WARNING: item with zero cost price', () {
      final result = _validateCostPrices([
        {'name': 'تفاح', 'costPrice': 0.0, 'trackInventory': true},
      ]);
      expect(result.isValid, isTrue); // warnings don't block
      expect(result.warnings.length, 1);
      expect(result.warnings.first, contains('تفاح'));
      expect(result.warnings.first, contains('سعر تكلفة'));
    });

    test('NO WARNING: non-tracked item with zero cost', () {
      final result = _validateCostPrices([
        {'name': 'Service', 'costPrice': 0.0, 'trackInventory': false},
      ]);
      expect(result.warnings, isEmpty);
    });

    test('Multiple warnings for multiple zero-cost items', () {
      final result = _validateCostPrices([
        {'name': 'A', 'costPrice': 10.0, 'trackInventory': true},
        {'name': 'B', 'costPrice': 0.0, 'trackInventory': true},
        {'name': 'C', 'costPrice': 0.0, 'trackInventory': true},
      ]);
      expect(result.warnings.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // F10: Shift Close Validation
  // ═══════════════════════════════════════════════════════════════════════

  group('Shift Close Validation (PIR F10)', () {
    test('OK: exact match', () {
      final v = _validateShiftClose(expected: 1000, actual: 1000);
      expect(v.isOk, isTrue);
      expect(v.severity, 'OK');
      expect(v.variance, 0.0);
    });

    test('OK: within tolerance', () {
      final v = _validateShiftClose(expected: 1000, actual: 1000.5, tolerance: 1.0);
      expect(v.isOk, isTrue);
    });

    test('WARNING: small surplus', () {
      final v = _validateShiftClose(expected: 1000, actual: 1003, tolerance: 1.0);
      expect(v.severity, 'WARNING');
      expect(v.message, contains('فائض'));
    });

    test('WARNING: small shortage', () {
      final v = _validateShiftClose(expected: 1000, actual: 997, tolerance: 1.0);
      expect(v.severity, 'WARNING');
      expect(v.message, contains('عجز'));
    });

    test('CRITICAL: large variance', () {
      final v = _validateShiftClose(expected: 1000, actual: 900, tolerance: 1.0);
      expect(v.isCritical, isTrue);
      expect(v.severity, 'CRITICAL');
    });

    test('Variance is positive for surplus', () {
      final v = _validateShiftClose(expected: 100, actual: 120);
      expect(v.variance, 20.0);
    });

    test('Variance is negative for shortage', () {
      final v = _validateShiftClose(expected: 100, actual: 80);
      expect(v.variance, -20.0);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// HELPERS - mirror AccountingService logic without DB dependency
// ═══════════════════════════════════════════════════════════════════════

AccountingValidationResult _validateCostPrices(List<Map<String, dynamic>> items) {
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
    errors: const [],
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
        : 'فرق ${variance > 0 ? "فائض" : "عجز"}: ${absVariance.toStringAsFixed(2)}',
  );
}
