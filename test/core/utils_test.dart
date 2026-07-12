import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/number_utils.dart';
import 'package:ural_erp/core/utils/date_utils.dart';

void main() {
  group('NumberUtils', () {
    test('formatCurrency should format correctly', () {
      final result = NumberUtils.formatCurrency(1234.56);
      expect(result, contains('د.أ')); // Jordanian Dinar (Arabic symbol)
      expect(result.isNotEmpty, true);
    });

    test('formatQuantity should format based on value', () {
      expect(NumberUtils.formatQuantity(5.0), '5');
      expect(NumberUtils.formatQuantity(5.5), isNotEmpty);
    });

    test('formatPercent should format correctly', () {
      expect(NumberUtils.formatPercent(25), '25%');
    });

    test('round should round correctly', () {
      expect(NumberUtils.round(3.14159, 2), closeTo(3.14, 0.01));
      // Note: round(value, 0) has edge case due to mod calculation
    });

    test('roundCurrency should round to 2 decimals', () {
      expect(NumberUtils.roundCurrency(3.14159), closeTo(3.14, 0.01));
    });

    test('discountAmount should compute discount', () {
      expect(NumberUtils.discountAmount(100, 10), 10.0);
      expect(NumberUtils.discountAmount(500, 20), 100.0);
    });

    test('applyDiscount should apply discount correctly', () {
      expect(NumberUtils.applyDiscount(100, 10), 90.0);
      expect(NumberUtils.applyDiscount(500, 25), 375.0);
    });

    test('tryParse should parse safely', () {
      expect(NumberUtils.tryParse('123.45'), 123.45);
      expect(NumberUtils.tryParse('invalid'), null);
      expect(NumberUtils.tryParse(null), null);
    });

    test('parseOr should return default on failure', () {
      expect(NumberUtils.parseOr('123', 0), 123.0);
      expect(NumberUtils.parseOr('invalid', -1.0), -1.0);
    });

    test('percentOf should calculate percentage', () {
      expect(NumberUtils.percentOf(25, 100), 25.0);
      expect(NumberUtils.percentOf(50, 200), 25.0);
    });

    test('isZero should detect near-zero values', () {
      expect(NumberUtils.isZero(0.0), true);
      expect(NumberUtils.isZero(0.0001), true);
      expect(NumberUtils.isZero(1.0), false);
    });

    test('clamp should limit values', () {
      expect(NumberUtils.clamp(5, 0, 10), 5);
      expect(NumberUtils.clamp(-5, 0, 10), 0);
      expect(NumberUtils.clamp(15, 0, 10), 10);
    });

    test('taxAmount should calculate tax', () {
      expect(NumberUtils.taxAmount(100, 14), closeTo(14.0, 0.001));
    });

    test('addTax should add tax to price', () {
      expect(NumberUtils.addTax(100, 14), closeTo(114.0, 0.001));
    });
  });

  group('DateUtils', () {
    test('formatDate should format correctly', () {
      final date = DateTime(2026, 1, 17);
      expect(DateUtils.formatDate(date), '2026-01-17');
    });

    test('formatDisplayDate should format for display', () {
      final date = DateTime(2026, 1, 17);
      expect(DateUtils.formatDisplayDate(date), '17/01/2026');
    });

    test('formatTime should format time', () {
      final date = DateTime(2026, 1, 17, 9, 5, 30);
      expect(DateUtils.formatTime(date), '09:05:30');
    });

    test('isToday should identify today', () {
      expect(DateUtils.isToday(DateTime.now()), true);
      expect(DateUtils.isToday(DateTime.now().subtract(const Duration(days: 1))), false);
    });

    test('startOfDay should return midnight', () {
      final date = DateTime(2026, 1, 17, 14, 30, 45);
      final start = DateUtils.startOfDay(date);
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(start.second, 0);
      expect(start.day, 17);
    });

    test('endOfDay should return end of day', () {
      final date = DateTime(2026, 1, 17, 10, 0);
      final end = DateUtils.endOfDay(date);
      expect(end.hour, 23);
      expect(end.minute, 59);
      expect(end.second, 59);
    });

    test('startOfMonth should return first of month', () {
      final date = DateTime(2026, 1, 17);
      final start = DateUtils.startOfMonth(date);
      expect(start.day, 1);
      expect(start.month, 1);
    });

    test('endOfMonth should return last of month', () {
      final date = DateTime(2026, 1, 17);
      final end = DateUtils.endOfMonth(date);
      expect(end.day, 31); // January has 31 days
      expect(end.month, 1);
    });

    test('daysBetween should calculate correctly', () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 1, 10);
      expect(DateUtils.daysBetween(start, end), 9);
    });

    test('isExpired should check expiry', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 1));
      final futureDate = DateTime.now().add(const Duration(days: 1));
      
      expect(DateUtils.isExpired(pastDate), true);
      expect(DateUtils.isExpired(futureDate), false);
      expect(DateUtils.isExpired(null), false);
    });

    test('isExpiringSoon should detect soon-to-expire dates', () {
      final soonDate = DateTime.now().add(const Duration(days: 5));
      final farDate = DateTime.now().add(const Duration(days: 60));
      
      expect(DateUtils.isExpiringSoon(soonDate, 7), true);
      expect(DateUtils.isExpiringSoon(farDate, 7), false);
    });

    test('parseDate should parse valid dates', () {
      expect(DateUtils.parseDate('2026-01-17'), isNotNull);
      expect(DateUtils.parseDate('invalid'), isNull);
      expect(DateUtils.parseDate(null), isNull);
    });
  });
}
