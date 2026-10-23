import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart' as core_date_utils;

/// A card for displaying key performance indicators in reports
///
/// Spec 076 polish (2026-05-15): defaults shrunk so 5 KPI cards fit in a
/// single Row on standard 1280-px desktop. Field feedback: operators saw
/// 3 + 2 wrap layout that broke the eye-line across the dashboard.
class ReportKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final List<Color>? gradient;

  /// Optional percentage change compared to previous period.
  /// Positive = improvement (green ↑), negative = decline (red ↓), null = hidden.
  final double? changePercent;

  const ReportKpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    this.color = AppColors.primary,
    this.gradient,
    this.changePercent,
  });

  @override
  Widget build(BuildContext context) {
    // Polish v2 (2026-05-15): operators reported cards still felt big and 5
    // didn't fit one row at ~1280px. Further compaction.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 15,
                            color: color,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    if (changePercent != null) ...[
                      const SizedBox(width: 4),
                      _buildChangeBadge(changePercent!),
                    ],
                  ],
                ),
                // Subtitle inline (kept visible — Tooltip alone was invisible
                // on desktop hover). Tiny font + ellipsis for narrow cards.
                if (subtitle != null)
                  Tooltip(
                    message: subtitle!,
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 9,
                        color: color.withValues(alpha: 0.7),
                        height: 1.15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeBadge(double percent) {
    final isPositive = percent >= 0;
    final badgeColor = isPositive ? AppColors.success : AppColors.error;
    final arrow = isPositive ? '↑' : '↓';
    final displayPercent = percent.abs().toStringAsFixed(1);

    return Container(
      // Polish (spec 076): smaller badge to fit the compact card.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            arrow,
            style: TextStyle(
              fontSize: 10,
              color: badgeColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            '$displayPercent%',
            style: TextStyle(
              fontSize: 9,
              color: badgeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A filter bar for selecting date ranges in reports
class DateRangeFilter extends StatelessWidget {
  final Function(DateTime start, DateTime end) onRangeChanged;
  final DateTimeRange selectedRange;

  const DateRangeFilter({
    super.key,
    required this.onRangeChanged,
    required this.selectedRange,
  });

  /// Spec 065 (D3-001/D3-006): every emission from this widget — preset chips
  /// or custom picker — runs through this helper so the consumer always sees a
  /// full-day-inclusive window: start at 00:00:00.000, end at 23:59:59.999.
  ///
  /// The native [showDateRangePicker] returns midnight values for both ends,
  /// which would otherwise clip the final day to a zero-duration instant —
  /// invisible-to-the-operator data loss.
  static DateTimeRange normalizeRange(DateTime start, DateTime end) {
    return DateTimeRange(
      start: core_date_utils.DateUtils.startOfDay(start),
      end: core_date_utils.DateUtils.endOfDay(end),
    );
  }

  /// Spec 065: shorthand for screens that hold `_fromDate` / `_toDate` as
  /// separate `DateTime` fields (instead of a `DateTimeRange`). Same contract
  /// as [normalizeRange], split for caller convenience.
  static DateTime normalizeStart(DateTime d) =>
      core_date_utils.DateUtils.startOfDay(d);
  static DateTime normalizeEnd(DateTime d) =>
      core_date_utils.DateUtils.endOfDay(d);

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd');
    final rangeText =
        '${dateFormat.format(selectedRange.start)} - ${dateFormat.format(selectedRange.end)}';
    final ps = presets();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            PhosphorIconsBold.calendar,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          // Spec 065: every preset window is normalized to full-day-inclusive
          // [00:00:00.000, 23:59:59.999] via normalizeRange so the chip click
          // matches what the operator expects.
          for (var i = 0; i < ps.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _buildFilterChip(context, ps[i].label, ps[i].range),
          ],
          const SizedBox(width: 16),
          Container(
            width: 1,
            height: 24,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(width: 16),
          InkWell(
            onTap: () => _showCustomRangePicker(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    rangeText,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(PhosphorIconsBold.caretDown, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Spec 065: preset helpers — each returns a normalized window so the
  // emission and the "is this chip selected?" check use the same values.
  static DateTimeRange _todayRange() {
    final now = DateTime.now();
    return normalizeRange(now, now);
  }

  static DateTimeRange _yesterdayRange() {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return normalizeRange(y, y);
  }

  static DateTimeRange _monthToDateRange() {
    final now = DateTime.now();
    return normalizeRange(DateTime(now.year, now.month, 1), now);
  }

  static DateTimeRange _yearToDateRange() {
    final now = DateTime.now();
    return normalizeRange(DateTime(now.year, 1, 1), now);
  }

  /// الفتراتُ الجاهزةُ وحدودُها بترتيبها.
  ///
  /// ⚠️ **مصدرٌ واحدٌ لشريطَي المرشِّحات.** شريطُ PicPos يرسم الفتراتِ بشكلٍ
  /// آخر، ولو حسب حدودَها بنفسه لأمكن أن يعني «الشهر» في أحدهما شيئاً وفي
  /// الآخر شيئاً آخر — والتقريرُ كلُّه يُحسَب من هذه الحدود، فالانحرافُ هنا
  /// أرقامٌ خاطئةٌ لا اختلافُ شكل.
  static List<({String label, DateTimeRange range})> presets() => [
        (label: tr('اليوم'), range: _todayRange()),
        (label: tr('أمس'), range: _yesterdayRange()),
        (label: tr('الشهر'), range: _monthToDateRange()),
        (label: tr('السنة'), range: _yearToDateRange()),
      ];

  /// هل [range] هو المدى المعروض حاليّاً؟ مقارنةُ **يومٍ** لا لحظة.
  static bool isPresetSelected(DateTimeRange selected, DateTimeRange range) =>
      _sameDay(selected.start, range.start) &&
      _sameDay(selected.end, range.end);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// منتقي المدى المخصّص — يستدعيه الشريطان.
  ///
  /// و‏Spec 065 محفوظٌ هنا: `showDateRangePicker` يُرجع منتصفَ الليل للطرفين،
  /// فيُسوّى المدى كي يدخل اليومُ الأخيرُ كاملاً.
  static Future<void> pickCustomRange(
    BuildContext context,
    DateTimeRange current,
    void Function(DateTime start, DateTime end) onRangeChanged,
  ) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: current,
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: Colors.white,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
              child: child!,
            ),
          ),
        );
      },
    );
    if (range != null) {
      final normalized = normalizeRange(range.start, range.end);
      onRangeChanged(normalized.start, normalized.end);
    }
  }

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    DateTimeRange range,
  ) {
    final isSelected = isPresetSelected(selectedRange, range);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) onRangeChanged(range.start, range.end);
      },
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        fontSize: 13,
      ),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _showCustomRangePicker(BuildContext context) =>
      pickCustomRange(context, selectedRange, onRangeChanged);
}
