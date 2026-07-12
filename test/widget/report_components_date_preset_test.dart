// ═══════════════════════════════════════════════════════════════════════════
// Spec 065 — DateRangeFilter chip + picker emission normalization
// ═══════════════════════════════════════════════════════════════════════════
//
// Pins the FR-001 / FR-002 / FR-008 contract from spec 065:
//   - chip "اليوم"   → emission start at 00:00:00.000 / end at 23:59:59.999
//   - chip "أمس"    → emission spans prior calendar day, fully
//   - chip "الشهر"   → emission starts at month day 1 / ends at end-of-today
//   - chip "السنة"   → emission starts at Jan 1 / ends at end-of-today
//   - normalizeRange → start-of-day + end-of-day regardless of input time
//
// Regression guard for QA finding D3-001 (P0).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/widgets/report_components.dart';

DateTime? capturedStart;
DateTime? capturedEnd;

Widget _wrap(DateTimeRange initial) {
  capturedStart = null;
  capturedEnd = null;
  return MaterialApp(
    locale: const Locale('ar'),
    home: Scaffold(
      // The widget renders an inline horizontal Row that exceeds the default
      // 800px test surface; wrap in a horizontal scroller so chips remain
      // hit-testable.
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DateRangeFilter(
          selectedRange: initial,
          onRangeChanged: (s, e) {
            capturedStart = s;
            capturedEnd = e;
          },
        ),
      ),
    ),
  );
}

void main() {
  group('DateRangeFilter chip emissions (Spec 065 / FR-001)', () {
    testWidgets('"اليوم" emits start-of-today and end-of-today',
        (tester) async {
      final initial = DateTimeRange(
        start: DateTime(2020, 1, 1),
        end: DateTime(2020, 1, 1),
      );
      await tester.pumpWidget(_wrap(initial));
      await tester.tap(find.widgetWithText(ChoiceChip, 'اليوم'));
      await tester.pump();

      final now = DateTime.now();
      expect(capturedStart, isNotNull, reason: 'chip must emit a range');
      expect(capturedStart!.year, now.year);
      expect(capturedStart!.month, now.month);
      expect(capturedStart!.day, now.day);
      expect(capturedStart!.hour, 0);
      expect(capturedStart!.minute, 0);
      expect(capturedStart!.second, 0);

      expect(capturedEnd!.year, now.year);
      expect(capturedEnd!.month, now.month);
      expect(capturedEnd!.day, now.day);
      expect(capturedEnd!.hour, 23);
      expect(capturedEnd!.minute, 59);
      expect(capturedEnd!.second, 59);
      expect(capturedEnd!.millisecond, 999);
    });

    testWidgets('"أمس" emits start-of-yesterday and end-of-yesterday',
        (tester) async {
      final initial = DateTimeRange(
        start: DateTime(2020, 1, 1),
        end: DateTime(2020, 1, 1),
      );
      await tester.pumpWidget(_wrap(initial));
      await tester.tap(find.widgetWithText(ChoiceChip, 'أمس'));
      await tester.pump();

      final yesterday =
          DateTime.now().subtract(const Duration(days: 1));
      expect(capturedStart, isNotNull);
      expect(capturedStart!.year, yesterday.year);
      expect(capturedStart!.month, yesterday.month);
      expect(capturedStart!.day, yesterday.day);
      expect(capturedStart!.hour, 0);
      expect(capturedStart!.minute, 0);

      expect(capturedEnd!.day, yesterday.day);
      expect(capturedEnd!.hour, 23);
      expect(capturedEnd!.minute, 59);
      expect(capturedEnd!.second, 59);
      expect(capturedEnd!.millisecond, 999);
    });

    testWidgets('"الشهر" emits month-day-1 and end-of-today (MTD)',
        (tester) async {
      final initial = DateTimeRange(
        start: DateTime(2020, 1, 1),
        end: DateTime(2020, 1, 1),
      );
      await tester.pumpWidget(_wrap(initial));
      await tester.tap(find.widgetWithText(ChoiceChip, 'الشهر'));
      await tester.pump();

      final now = DateTime.now();
      expect(capturedStart, isNotNull);
      expect(capturedStart!.year, now.year);
      expect(capturedStart!.month, now.month);
      expect(capturedStart!.day, 1);
      expect(capturedStart!.hour, 0);

      expect(capturedEnd!.year, now.year);
      expect(capturedEnd!.month, now.month);
      expect(capturedEnd!.day, now.day);
      expect(capturedEnd!.hour, 23);
      expect(capturedEnd!.minute, 59);
      expect(capturedEnd!.second, 59);
      expect(capturedEnd!.millisecond, 999);
    });

    testWidgets('"السنة" emits Jan-1 and end-of-today (YTD)',
        (tester) async {
      final initial = DateTimeRange(
        start: DateTime(2020, 1, 1),
        end: DateTime(2020, 1, 1),
      );
      await tester.pumpWidget(_wrap(initial));
      await tester.tap(find.widgetWithText(ChoiceChip, 'السنة'));
      await tester.pump();

      final now = DateTime.now();
      expect(capturedStart, isNotNull);
      expect(capturedStart!.year, now.year);
      expect(capturedStart!.month, 1);
      expect(capturedStart!.day, 1);
      expect(capturedStart!.hour, 0);

      expect(capturedEnd!.year, now.year);
      expect(capturedEnd!.month, now.month);
      expect(capturedEnd!.day, now.day);
      expect(capturedEnd!.hour, 23);
      expect(capturedEnd!.minute, 59);
      expect(capturedEnd!.second, 59);
      expect(capturedEnd!.millisecond, 999);
    });
  });

  group('DateRangeFilter.normalizeRange (Spec 065 / FR-002 / FR-008)', () {
    test('normalizes a midnight-emitting picker range to full-day-inclusive',
        () {
      // Native showDateRangePicker returns midnight values; we must extend the
      // end to end-of-day so reports include the full final day.
      final range = DateRangeFilter.normalizeRange(
        DateTime(2026, 5, 1, 0, 0, 0),
        DateTime(2026, 5, 15, 0, 0, 0),
      );

      expect(range.start, DateTime(2026, 5, 1, 0, 0, 0, 0));
      expect(range.end, DateTime(2026, 5, 15, 23, 59, 59, 999));
    });

    test('normalizes mid-day inputs to calendar-day boundaries', () {
      final range = DateRangeFilter.normalizeRange(
        DateTime(2026, 5, 1, 14, 30, 17),
        DateTime(2026, 5, 15, 9, 45, 0),
      );

      expect(range.start, DateTime(2026, 5, 1, 0, 0, 0, 0));
      expect(range.end, DateTime(2026, 5, 15, 23, 59, 59, 999));
    });
  });
}
