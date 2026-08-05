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

  /// Exclusive upper bound of [date]'s day — midnight of the following day.
  ///
  /// Why this exists: a half-open window `[startOfDay(from), startOfNextDay(to))`
  /// is the ONLY formulation that yields the same window whether the caller
  /// hands over a midnight `end` (native `showDateRangePicker`) or a
  /// 23:59:59.999 one (`DateRangeFilter.normalizeRange`). Queries that instead
  /// did `end.add(Duration(days: 1))` silently stretched an already-normalized
  /// end across the WHOLE next day — «اليوم» included tomorrow. Snapping to the
  /// day boundary first makes the call idempotent, so both conventions agree.
  ///
  /// Mirrors `dayWindowFor`'s `endExclusive` in sales_invoices_controller.dart,
  /// which is the same contract for the sales screen.
  static DateTime startOfNextDay(DateTime date) {
    return DateTime(date.year, date.month, date.day + 1);
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
