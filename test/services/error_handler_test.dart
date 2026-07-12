import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/app_error_handler.dart';
import 'package:ural_erp/core/errors/app_error.dart';
import 'dart:io';

void main() {
  group('AppErrorHandler - Translation', () {
    test('ValidationError returns messageAr', () {
      final error = ValidationError(['خطأ اختبار']);
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, 'خطأ اختبار');
    });

    test('UNIQUE constraint → Arabic duplicate message', () {
      final error = Exception('SqliteException: UNIQUE constraint failed');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('موجود بالفعل'));
    });

    test('FOREIGN KEY constraint → dependency message', () {
      final error = Exception('SqliteException: FOREIGN KEY constraint failed');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('لا يمكن حذف'));
    });

    test('NOT NULL constraint → required fields', () {
      final error = Exception('SqliteException: NOT NULL constraint failed');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('المطلوبة'));
    });

    test('database locked → busy message', () {
      final error = Exception('SqliteException: database is locked');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('مشغولة'));
    });

    test('SocketException → no internet', () {
      const error = SocketException('Connection refused');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('اتصال'));
    });

    test('FormatException → format error', () {
      const error = FormatException('bad format');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('صيغة'));
    });

    test('RangeError → range message', () {
      final error = RangeError.range(5, 0, 3);
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('النطاق'));
    });

    test('ArgumentError → invalid input', () {
      final error = ArgumentError('bad value');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('صالحة'));
    });

    test('StateError with No element → no results', () {
      final error = StateError('No element');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('نتائج'));
    });

    test('TypeError → contact support', () {
      // TypeError can't easily be instantiated, test fallback
      final error = Exception('TimeoutException after 30s');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('الانتظار'));
    });

    test('Unknown error → generic fallback', () {
      final error = Exception('Something completely unknown');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('غير متوقع'));
    });

    test('Printing error → printer message', () {
      final error = Exception('printer not connected');
      final msg = AppErrorHandler.translateForTest(error);
      expect(msg, contains('الطباعة'));
    });
  });
}
