import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:ural_erp/core/constants/app_constants.dart';

/// Number utility functions
class NumberUtils {
  NumberUtils._();

  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'ar_JO',
    symbol: AppConstants.currencySymbol,
    decimalDigits: AppConstants.decimalPlaces,
  );
  static final NumberFormat _quantityFormat = NumberFormat(
    '#,##0.###',
    'ar_EG',
  );

  /// Format as currency (e.g., "1,234.56 JOD")
  static String formatCurrency(double amount, {String? symbol}) {
    final format = NumberFormat.currency(
      locale: 'ar_JO',
      symbol: symbol ?? AppConstants.currencySymbol,
      decimalDigits: AppConstants.decimalPlaces,
    );
    return format.format(amount);
  }

  /// Format as currency without symbol
  static String formatAmount(double value) {
    return _currencyFormat.format(value);
  }

  /// Format as quantity (e.g., "1,234.5")
  static String formatQuantity(double value) {
    // Remove trailing zeros for whole numbers
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return _quantityFormat.format(value);
  }

  /// Format as percentage (e.g., "15%")
  static String formatPercent(double value) {
    return '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}%';
  }

  /// Round to decimal places
  static double round(double value, int decimalPlaces) {
    final mod = math.pow(10, decimalPlaces);
    return (value * mod).roundToDouble() / mod;
  }

  /// Round currency (to configured decimal places)
  static double roundCurrency(double value) => round(value, AppConstants.decimalPlaces);

  /// Parse a number entered in an Arabic locale (BUG-U14/U25).
  /// Accepts Arabic-Indic digits (٠-٩) and a comma (',' / '،') or the Arabic
  /// decimal mark ('٫') as the decimal separator. Returns null if not parseable.
  static double? tryParseLocale(String? value) {
    if (value == null) return null;
    var s = value.trim();
    if (s.isEmpty) return null;
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      final idx = arabicDigits.indexOf(ch);
      buf.write(idx >= 0 ? '$idx' : ch);
    }
    s = buf
        .toString()
        .replaceAll('٫', '.') // Arabic decimal mark
        .replaceAll('،', '.') // Arabic comma
        .replaceAll(',', '.');
    s = s.replaceAll(RegExp(r'[^\d.\-]'), ''); // keep digits, dot, minus
    return double.tryParse(s);
  }

  /// Parse number from string safely
  static double? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    // Remove currency symbols and spaces
    final cleaned = value.replaceAll(RegExp(r'[^\d.-]'), '');
    return double.tryParse(cleaned);
  }

  /// Parse number with default
  static double parseOr(String? value, double defaultValue) {
    return tryParse(value) ?? defaultValue;
  }

  /// Calculate percentage of total
  static double percentOf(double value, double total) {
    if (total == 0) return 0;
    return (value / total) * 100;
  }

  /// Apply percentage discount
  /// BUG-L01: round at currency precision so callers don't propagate float tails.
  static double applyDiscount(double price, double discountPercent) {
    return roundCurrency(price * (1 - discountPercent / 100));
  }

  /// Calculate discount amount
  static double discountAmount(double price, double discountPercent) {
    return roundCurrency(price * (discountPercent / 100));
  }

  /// Calculate tax amount
  static double taxAmount(double price, double taxPercent) {
    return roundCurrency(price * (taxPercent / 100));
  }

  /// Add tax to price
  static double addTax(double price, double taxPercent) {
    return roundCurrency(price * (1 + taxPercent / 100));
  }

  /// Check if value is effectively zero
  static bool isZero(double value, {double epsilon = 0.001}) {
    return value.abs() < epsilon;
  }

  /// Clamp value between min and max
  static double clamp(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
