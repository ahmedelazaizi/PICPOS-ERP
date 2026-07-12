// ═══════════════════════════════════════════════════════════════════════════
// PIR-014: ZeroCostPolicy Unit Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests the configurable zero-cost guard in JournalEntryFactory.
// Verifies all three policy modes: block, warn, allow.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/journal_entry_factory.dart';

void main() {
  group('ZeroCostPolicy', () {
    test('enum has all three values', () {
      expect(ZeroCostPolicy.values, hasLength(3));
      expect(ZeroCostPolicy.values, contains(ZeroCostPolicy.block));
      expect(ZeroCostPolicy.values, contains(ZeroCostPolicy.warn));
      expect(ZeroCostPolicy.values, contains(ZeroCostPolicy.allow));
    });

    test('default policy string representations', () {
      expect(ZeroCostPolicy.block.name, 'block');
      expect(ZeroCostPolicy.warn.name, 'warn');
      expect(ZeroCostPolicy.allow.name, 'allow');
    });
  });

  group('ZeroCostException', () {
    test('contains product ID and invoice number', () {
      final exception = ZeroCostException(42, 'INV-2026-001');
      expect(exception.productId, 42);
      expect(exception.invoiceNumber, 'INV-2026-001');
    });

    test('toString includes Arabic guidance', () {
      final exception = ZeroCostException(42, 'INV-2026-001');
      final str = exception.toString();
      expect(str, contains('42'));
      expect(str, contains('INV-2026-001'));
      expect(str, contains('تكلفة صفر'));
      expect(str, contains('الإعدادات'));
    });
  });

  group('MissingAccountException', () {
    test('contains purpose', () {
      final exception = MissingAccountException('cash');
      expect(exception.purpose, 'cash');
    });

    test('toString includes setup guidance', () {
      final exception = MissingAccountException('cash');
      final str = exception.toString();
      expect(str, contains('cash'));
      expect(str, contains('ربط الحسابات'));
    });
  });

  group('UnbalancedJournalException', () {
    test('contains debit, credit, and context', () {
      final exception = UnbalancedJournalException(100.0, 99.0, 'test invoice');
      expect(exception.totalDebit, 100.0);
      expect(exception.totalCredit, 99.0);
      expect(exception.context, 'test invoice');
    });

    test('toString shows difference', () {
      final exception = UnbalancedJournalException(100.0, 99.0, 'test');
      final str = exception.toString();
      expect(str, contains('غير متوازن'));
      expect(str, contains('100.0'));
      expect(str, contains('99.0'));
      expect(str, contains('فرق'));
    });
  });

  group('PeriodLockedException', () {
    test('contains date', () {
      final date = DateTime(2026, 3, 16);
      final exception = PeriodLockedException(date);
      expect(exception.date, date);
    });

    test('toString includes date', () {
      final exception = PeriodLockedException(DateTime(2026, 3, 16));
      final str = exception.toString();
      expect(str, contains('مغلقة'));
    });
  });
}
