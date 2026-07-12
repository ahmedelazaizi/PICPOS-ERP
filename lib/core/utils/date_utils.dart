import 'package:intl/intl.dart';

/// Date utility functions
class DateUtils {
  DateUtils._();

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _timeFormat = DateFormat('HH:mm:ss');
  static final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final DateFormat _displayDateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _displayTimeFormat = DateFormat('hh:mm a');

  /// Format date for storage/API
  static String formatDate(DateTime date) => _dateFormat.format(date);

  /// Format time for storage/API
  static String formatTime(DateTime time) => _timeFormat.format(time);

  /// Format datetime for storage/API
  static String formatDateTime(DateTime dateTime) =>
      _dateTimeFormat.format(dateTime);

  /// Format date for display (Arabic style)
  static String formatDisplayDate(DateTime date) =>
      _displayDateFormat.format(date);

  /// Format time for display
  static String formatDisplayTime(DateTime time) =>
      _displayTimeFormat.format(time);

  /// Format datetime for display
  static String formatDisplayDateTime(DateTime dateTime) {
    return '${formatDisplayDate(dateTime)} ${formatDisplayTime(dateTime)}';
  }

  /// Parse date from string
  static DateTime? parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return _dateFormat.parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  /// Get start of day
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get end of day
  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  /// Get start of month
  static DateTime startOfMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  /// Get end of month
  static DateTime endOfMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0, 23, 59, 59, 999);
  }

  /// Check if date is today
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Get days between two dates
  static int daysBetween(DateTime from, DateTime to) {
    final fromDate = DateTime(from.year, from.month, from.day);
    final toDate = DateTime(to.year, to.month, to.day);
    return toDate.difference(fromDate).inDays;
  }

  /// Check if date is expired
  static bool isExpired(DateTime? expiryDate) {
    if (expiryDate == null) return false;
    return expiryDate.isBefore(DateTime.now());
  }

  /// Check if expiring within days
  static bool isExpiringSoon(DateTime? expiryDate, int days) {
    if (expiryDate == null) return false;
    final warningDate = DateTime.now().add(Duration(days: days));
    return expiryDate.isBefore(warningDate) && !isExpired(expiryDate);
  }
}
