import 'package:flutter/material.dart';

/// Compact date picker utilities
/// Wraps Material date pickers with a constrained dialog
/// to prevent full-screen rendering on desktop
class CompactDatePicker {
  CompactDatePicker._();

  /// A builder that constrains the date picker dialog size
  /// Use this as the `builder` parameter for showDatePicker / showDateRangePicker
  static Widget Function(BuildContext, Widget?) get compactBuilder {
    return (context, child) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 400,
            maxHeight: 560,
          ),
          child: child,
        ),
      );
    };
  }

  /// A builder for date range picker — slightly wider to accommodate two months
  static Widget Function(BuildContext, Widget?) get compactRangeBuilder {
    return (context, child) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 460,
            maxHeight: 520,
          ),
          child: child,
        ),
      );
    };
  }

  /// Show a compact date picker dialog
  static Future<DateTime?> showCompact(
    BuildContext context, {
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    String? helpText,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
      builder: compactBuilder,
    );
  }

  /// Show a compact date range picker dialog
  static Future<DateTimeRange?> showCompactRange(
    BuildContext context, {
    required DateTime firstDate,
    required DateTime lastDate,
    DateTimeRange? initialDateRange,
    String? helpText,
  }) {
    return showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialDateRange,
      helpText: helpText,
      builder: compactRangeBuilder,
    );
  }
}
