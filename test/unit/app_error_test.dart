// ═══════════════════════════════════════════════════════════════════════════
// APP ERROR HIERARCHY — Unit Tests (PIR Sprint 6)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/errors/app_error.dart';

void main() {
  group('AppError Sealed Hierarchy', () {
    test('ValidationError — single error', () {
      final e = ValidationError(['حقل مطلوب']);
      expect(e.messageAr, 'حقل مطلوب');
      expect(e.messageTech, contains('Validation failed'));
      expect(e.toString(), 'حقل مطلوب');
      expect(e, isA<AppError>());
    });

    test('ValidationError — multiple errors joined by newline', () {
      final e = ValidationError(['خطأ 1', 'خطأ 2']);
      expect(e.messageAr, 'خطأ 1\nخطأ 2');
      expect(e.errors.length, 2);
    });

    test('SplitPaymentError — contains amounts', () {
      final e = SplitPaymentError(cashPaid: 50, bankPaid: 30, expectedTotal: 100);
      expect(e.messageAr, contains('50'));
      expect(e.messageAr, contains('30'));
      expect(e.messageAr, contains('100'));
      expect(e.messageTech, contains('mismatch'));
    });

    test('FiscalPeriodError — contains year name', () {
      final e = FiscalPeriodError(
        date: DateTime(2025, 6, 15),
        fiscalYearName: '2025',
      );
      expect(e.messageAr, contains('مقفلة'));
      expect(e.messageAr, contains('2025'));
      expect(e.messageTech, contains('closed'));
    });

    test('UnbalancedJournalError — shows debit/credit', () {
      final e = UnbalancedJournalError(totalDebit: 1000, totalCredit: 950);
      expect(e.messageAr, contains('1000'));
      expect(e.messageAr, contains('950'));
      expect(e.messageAr, contains('غير متوازن'));
    });

    test('InsufficientStockError — shows product and quantities', () {
      final e = InsufficientStockError(
        productId: 42,
        productName: 'تفاح',
        available: 5,
        requested: 10,
      );
      expect(e.messageAr, contains('تفاح'));
      expect(e.messageAr, contains('10'));
      expect(e.messageAr, contains('5'));
      expect(e.messageTech, contains('42'));
    });

    test('ExcessReturnError — shows max returnable', () {
      final e = ExcessReturnError(productId: 7, requested: 8, maxReturnable: 5);
      expect(e.messageAr, contains('8'));
      expect(e.messageAr, contains('5'));
      expect(e.messageAr, contains('أكبر'));
    });

    test('ReconciliationError — shows cached vs calculated', () {
      final e = ReconciliationError(
        entityType: 'account',
        entityId: 1,
        cachedValue: 100,
        calculatedValue: 90,
      );
      expect(e.messageAr, contains('فرق'));
      expect(e.messageAr, contains('100'));
      expect(e.messageAr, contains('90'));
      expect(e.messageTech, contains('mismatch'));
    });

    test('PermissionDeniedError — with name', () {
      final e = PermissionDeniedError(
        permissionCode: 'pos.return',
        permissionName: 'مرتجعات المبيعات',
      );
      expect(e.messageAr, contains('مرتجعات المبيعات'));
      expect(e.messageTech, contains('pos.return'));
    });

    test('PermissionDeniedError — without name falls back to code', () {
      final e = PermissionDeniedError(permissionCode: 'admin.delete');
      expect(e.messageAr, contains('admin.delete'));
    });

    test('All 8 error types implement AppError', () {
      final errors = <AppError>[
        ValidationError(['test']),
        SplitPaymentError(cashPaid: 50, bankPaid: 30, expectedTotal: 100),
        FiscalPeriodError(date: DateTime.now(), fiscalYearName: '2025'),
        UnbalancedJournalError(totalDebit: 100, totalCredit: 90),
        InsufficientStockError(productId: 1, productName: 'X', available: 0, requested: 1),
        ExcessReturnError(productId: 1, requested: 5, maxReturnable: 3),
        ReconciliationError(entityType: 'safe', entityId: 1, cachedValue: 100, calculatedValue: 90),
        PermissionDeniedError(permissionCode: 'test'),
      ];
      expect(errors.length, 8);
      for (final e in errors) {
        expect(e.messageAr, isNotEmpty);
        expect(e.messageTech, isNotEmpty);
      }
    });
  });
}
