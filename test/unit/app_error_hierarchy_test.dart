import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/errors/app_error.dart';

/// Tests for the AppError hierarchy — ISS-07
///
/// These tests verify that all AppError subtypes correctly produce
/// Arabic user-facing messages and English technical messages.
void main() {
  // ═══════════════════════════════════════════════════════════════
  // ValidationError
  // ═══════════════════════════════════════════════════════════════

  group('ValidationError', () {
    test('single error produces correct message', () {
      final e = ValidationError(['الاسم مطلوب']);
      expect(e.messageAr, 'الاسم مطلوب');
      expect(e.messageTech, contains('Validation failed'));
      expect(e.toString(), 'الاسم مطلوب');
    });

    test('multiple errors joined with newline', () {
      final e = ValidationError(['الاسم مطلوب', 'السعر مطلوب']);
      expect(e.messageAr, 'الاسم مطلوب\nالسعر مطلوب');
    });

    test('empty errors list produces empty message', () {
      final e = ValidationError([]);
      expect(e.messageAr, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SplitPaymentError
  // ═══════════════════════════════════════════════════════════════

  group('SplitPaymentError', () {
    test('produces correct Arabic message with amounts', () {
      final e = SplitPaymentError(
        cashPaid: 60,
        bankPaid: 30,
        expectedTotal: 100,
      );
      expect(e.messageAr, contains('60'));
      expect(e.messageAr, contains('30'));
      expect(e.messageAr, contains('100'));
      expect(e.messageAr, contains('≠'));
    });

    test('technical message contains English description', () {
      final e = SplitPaymentError(
        cashPaid: 60,
        bankPaid: 30,
        expectedTotal: 100,
      );
      expect(e.messageTech, contains('Split payment mismatch'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // FiscalPeriodError
  // ═══════════════════════════════════════════════════════════════

  group('FiscalPeriodError', () {
    test('produces correct Arabic message', () {
      final e = FiscalPeriodError(
        date: DateTime(2025, 6, 15),
        fiscalYearName: '2025',
      );
      expect(e.messageAr, contains('المقفلة'));
      expect(e.messageAr, contains('2025'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // UnbalancedJournalError
  // ═══════════════════════════════════════════════════════════════

  group('UnbalancedJournalError', () {
    test('produces correct Arabic message', () {
      final e = UnbalancedJournalError(
        totalDebit: 1000,
        totalCredit: 950,
      );
      expect(e.messageAr, contains('غير متوازن'));
      expect(e.messageAr, contains('1000'));
      expect(e.messageAr, contains('950'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // InsufficientStockError
  // ═══════════════════════════════════════════════════════════════

  group('InsufficientStockError', () {
    test('produces correct Arabic message', () {
      final e = InsufficientStockError(
        productId: 42,
        productName: 'حليب',
        available: 5,
        requested: 10,
      );
      expect(e.messageAr, contains('حليب'));
      expect(e.messageAr, contains('10'));
      expect(e.messageAr, contains('5'));
    });

    test('technical message contains product ID', () {
      final e = InsufficientStockError(
        productId: 42,
        productName: 'حليب',
        available: 5,
        requested: 10,
      );
      expect(e.messageTech, contains('42'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // ExcessReturnError
  // ═══════════════════════════════════════════════════════════════

  group('ExcessReturnError', () {
    test('produces correct Arabic message', () {
      final e = ExcessReturnError(
        productId: 7,
        requested: 5,
        maxReturnable: 3,
      );
      expect(e.messageAr, contains('5'));
      expect(e.messageAr, contains('3'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // ReconciliationError
  // ═══════════════════════════════════════════════════════════════

  group('ReconciliationError', () {
    test('produces correct Arabic message', () {
      final e = ReconciliationError(
        entityType: 'خزنة',
        entityId: 1,
        cachedValue: 5000,
        calculatedValue: 4800,
      );
      expect(e.messageAr, contains('خزنة'));
      expect(e.messageAr, contains('5000'));
      expect(e.messageAr, contains('4800'));
      expect(e.messageAr, contains('≠'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // PermissionDeniedError
  // ═══════════════════════════════════════════════════════════════

  group('PermissionDeniedError', () {
    test('shows permission name when provided', () {
      final e = PermissionDeniedError(
        permissionCode: 'delete_invoice',
        permissionName: 'حذف الفواتير',
      );
      expect(e.messageAr, contains('حذف الفواتير'));
    });

    test('shows permission code when name is null', () {
      final e = PermissionDeniedError(
        permissionCode: 'delete_invoice',
      );
      expect(e.messageAr, contains('delete_invoice'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Type Safety Checks
  // ═══════════════════════════════════════════════════════════════

  group('AppError type safety', () {
    test('all subtypes are AppError instances', () {
      final errors = <AppError>[
        ValidationError(['test']),
        SplitPaymentError(cashPaid: 0, bankPaid: 0, expectedTotal: 0),
        FiscalPeriodError(date: DateTime.now(), fiscalYearName: 'FY26'),
        UnbalancedJournalError(totalDebit: 100, totalCredit: 90),
        InsufficientStockError(productId: 1, productName: 'x', available: 0, requested: 1),
        ExcessReturnError(productId: 1, requested: 5, maxReturnable: 3),
        ReconciliationError(entityType: 'safe', entityId: 1, cachedValue: 100, calculatedValue: 90),
        PermissionDeniedError(permissionCode: 'test'),
      ];

      for (final error in errors) {
        expect(error, isA<AppError>());
        expect(error, isA<Exception>());
        expect(error.messageAr, isNotEmpty);
        expect(error.messageTech, isNotEmpty);
      }
    });
  });
}
