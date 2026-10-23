import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/utils/app_error_handler.dart';

/// PIR Integration Test 3: Error Handler Pattern Matching (PIR-010)
/// Verifies that all error types produce user-friendly Arabic messages.
void main() {
  group('PIR-010: Error Handler Translation', () {
    test('Database unique constraint → Arabic message', () {
      final message = AppErrorHandler.translateForTest(
        Exception('SqliteException: UNIQUE constraint failed: products.code'),
      );
      expect(message, contains('موجود بالفعل'));
    });

    test('Foreign key violation → Arabic message', () {
      final message = AppErrorHandler.translateForTest(
        Exception('SqliteException: FOREIGN KEY constraint failed'),
      );
      expect(message, contains('لا يمكن حذف'));
    });

    test('NOT NULL violation → Arabic message', () {
      final message = AppErrorHandler.translateForTest(
        Exception('SqliteException: NOT NULL constraint failed: safes.name'),
      );
      expect(message, contains('الحقول المطلوبة'));
    });

    test('FormatException → Arabic message', () {
      final message = AppErrorHandler.translateForTest(
        const FormatException('Invalid number format'),
      );
      expect(message, contains('صيغة'));
    });

    test('StateError No element → Arabic message', () {
      final message = AppErrorHandler.translateForTest(
        StateError('No element'),
      );
      expect(message, contains('لا توجد'));
    });

    test('Unknown error → Generic Arabic fallback', () {
      final message = AppErrorHandler.translateForTest(
        Exception('Some random unknown error xyz123'),
      );
      expect(message, contains('غير متوقع'));
    });

    test('Database locked → Arabic message', () {
      final message = AppErrorHandler.translateForTest(
        Exception('SqliteException: database is locked'),
      );
      expect(message, contains('مشغولة'));
    });
  });
}
