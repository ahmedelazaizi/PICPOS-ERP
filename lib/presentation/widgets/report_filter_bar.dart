// ═══════════════════════════════════════════════════════════════════════════
// Spec 076 — Responsive Report Filter Bar (Unified Two-Row Layout)
// ═══════════════════════════════════════════════════════════════════════════
//
// Field bug (2026-05-15): every report screen built its own
// `Row(children: [DateRangeFilter(...), dropdown1, dropdown2, ...])` for the
// top filter region. With 7 dropdowns + the DateRangeFilter (~520 px) the
// total exceeded even a 1920×1080 desktop. The Flutter debug indicator
// "OVERFLOWED BY 274" covered the date chips — operators could neither see
// nor click them, blocking the manual smoke for Spec 065's date-preset fix.
//
// This widget owns the canonical two-row pattern that every report screen
// with a date-range filter should adopt:
//
//   ┌─────────────────────────────────────────────────────────────┐
//   │  [اليوم] [أمس] [الشهر] [السنة]  |  2026/05/15 - 2026/01/01  │ ← top row
//   ├─────────────────────────────────────────────────────────────┤
//   │  ▾ مركز التكلفة  ▾ المخزن  ▾ الفرع                          │ ← bottom row
//   │  ▾ المنطقة  ▾ نوع البيع  ▾ طريقة الدفع  ▾ المستخدم          │   (reflows
//   └─────────────────────────────────────────────────────────────┘    via Wrap)
//
// Top row: forwards selectedRange/onRangeChanged into the existing
// DateRangeFilter (Spec 065). Wrapped in a horizontal scroll so even an
// exceptionally narrow window can't clip it.
//
// Bottom row: plain Wrap of caller-provided trailing widgets. Wrap reflows
// to multiple lines when the row would otherwise overflow. Polish (2026-05-15
// feedback): the previous Scrollbar + SingleChildScrollView wrapper was
// rendering a permanently-visible horizontal scrollbar under the filter
// region even when Wrap already handled the overflow — operators found the
// scrollbar cluttered and unnecessary. Wrap alone covers the common case;
// a single child wider than the viewport (rare) will visually clip but won't
// throw a RenderFlex exception (Wrap computes its own runs).
//
// Reuses (Constitution II): DateRangeFilter (Spec 065). No other dependency
// beyond Flutter's stdlib.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:picpos_erp/core/config/brand.dart';
import '../picpos_shell/picpos_report_bar.dart';
import 'report_components.dart' show DateRangeFilter;

class ReportFilterBar extends StatefulWidget {
  /// Currently-displayed date range. Forwarded to the embedded
  /// [DateRangeFilter] so its chips can reflect "is this preset selected?".
  final DateTimeRange selectedRange;

  /// Fires whenever a preset chip is tapped OR the custom-range picker emits.
  /// The values are already normalized by Spec 065's [DateRangeFilter] —
  /// start at 00:00:00.000, end at 23:59:59.999.
  final void Function(DateTime start, DateTime end) onRangeChanged;

  /// Variable-count dropdowns / autocompletes / buttons rendered in the
  /// second row. Reflows via [Wrap] on narrow widths.
  final List<Widget> trailing;

  /// Outer container padding. Defaults to the existing report-screen filter
  /// padding so adoption is visually neutral.
  final EdgeInsetsGeometry? padding;

  const ReportFilterBar({
    super.key,
    required this.selectedRange,
    required this.onRangeChanged,
    required this.trailing,
    this.padding,
  });

  @override
  State<ReportFilterBar> createState() => _ReportFilterBarState();
}

class _ReportFilterBarState extends State<ReportFilterBar> {
  // Explicit controller for the date row's horizontal scroll. The bottom
  // row no longer scrolls horizontally (Wrap handles overflow on its own),
  // so it doesn't need a controller.
  final ScrollController _topCtrl = ScrollController();

  @override
  void dispose() {
    _topCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ═══ فرعُ هويّة PicPos ═══
    //
    // ⚠️ **هذا السطرُ يُلبس ثلاثَ عشرةَ شاشةَ تقريرٍ الهويّةَ دفعةً**، لأنّها
    //    كلَّها تمرّ من هنا. وحوارُ UralCash تحته لا يتبدّل فيه بايت.
    if (Brand.isPicPos) {
      return PicPosReportFilterBar(
        selectedRange: widget.selectedRange,
        onRangeChanged: widget.onRangeChanged,
        trailing: widget.trailing,
        padding: widget.padding,
      );
    }

    final effectivePadding = widget.padding ??
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8);

    return Container(
      width: double.infinity,
      padding: effectivePadding,
      color: Theme.of(context).cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── TOP ROW: date presets + custom-range button ──────────────────
          // SingleChildScrollView guarantees the preset row is never clipped,
          // even on exceptionally narrow windows. No visible scrollbar — the
          // row is short and a scrollbar would just be visual noise.
          SingleChildScrollView(
            controller: _topCtrl,
            scrollDirection: Axis.horizontal,
            child: DateRangeFilter(
              selectedRange: widget.selectedRange,
              onRangeChanged: widget.onRangeChanged,
            ),
          ),
          if (widget.trailing.isNotEmpty) ...[
            // Visual separator between the date row and the dropdowns row —
            // operators on 2026-05-15 reported the two rows reading as one
            // crowded block.
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 10),
            // ── BOTTOM ROW: variable filters ──────────────────────────────
            // Plain Wrap — reflows children to a second/third line on narrow
            // widths. No horizontal Scrollbar (the previous one rendered as
            // permanent visual clutter; operators preferred clean reflow).
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.start,
              children: widget.trailing,
            ),
          ],
        ],
      ),
    );
  }
}
