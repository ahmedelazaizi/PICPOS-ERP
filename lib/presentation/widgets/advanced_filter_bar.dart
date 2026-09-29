// ═══════════════════════════════════════════════════════════════════════════
// Advanced Filter Bar Widget (U-04)
// Reusable multi-column filter bar with date range, type, and text search
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/compact_date_picker.dart';

/// Filter chip options
class FilterOption {
  final String value;
  final String label;
  final IconData? icon;

  const FilterOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Unified advanced filter bar — date range, chips, and search.
///
/// Usage:
/// ```dart
/// AdvancedFilterBar(
///   dateFrom: _from,
///   dateTo: _to,
///   onDateRangeChanged: (from, to) => setState(() { _from = from; _to = to; }),
///   searchQuery: _query,
///   onSearchChanged: (q) => setState(() => _query = q),
///   searchHint: 'بحث...',
///   filterOptions: [
///     FilterOption(value: 'all', label: 'الكل'),
///     FilterOption(value: 'sale', label: 'مبيعات'),
///   ],
///   selectedFilter: _filter,
///   onFilterChanged: (f) => setState(() => _filter = f),
/// )
/// ```
class AdvancedFilterBar extends StatelessWidget {
  /// Start of date range
  final DateTime dateFrom;

  /// End of date range
  final DateTime dateTo;

  /// Callback when date range changes
  final void Function(DateTime from, DateTime to) onDateRangeChanged;

  /// Text in search box
  final String searchQuery;

  /// Callback as user types in search box
  final ValueChanged<String> onSearchChanged;

  /// Placeholder for search box
  final String searchHint;

  /// Optional: chip-style filter options
  final List<FilterOption>? filterOptions;

  /// Currently selected filter value
  final String? selectedFilter;

  /// Callback when filter chip is tapped
  final ValueChanged<String>? onFilterChanged;

  /// Optional: additional trailing widgets
  final List<Widget>? trailing;

  const AdvancedFilterBar({
    super.key,
    required this.dateFrom,
    required this.dateTo,
    required this.onDateRangeChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    this.searchHint = 'بحث...',
    this.filterOptions,
    this.selectedFilter,
    this.onFilterChanged,
    this.trailing,
  });

  static final _fmt = DateFormat('yyyy/MM/dd');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
      ),
      child: Column(
        children: [
          // Row 1: Search + Date Range
          Row(
            children: [
              // Search field
              Expanded(
                flex: 3,
                child: _buildSearchField(context),
              ),
              const SizedBox(width: 10),
              // Date range
              Expanded(
                flex: 2,
                child: _buildDateRangeButton(context),
              ),
              if (trailing != null) ...trailing!.map((w) => Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: w,
              )),
            ],
          ),
          // Row 2: Filter chips (if any)
          if (filterOptions != null && filterOptions!.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: filterOptions!.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, index) {
                  final opt = filterOptions![index];
                  final isSelected = opt.value == selectedFilter;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (opt.icon != null) ...[
                          Icon(opt.icon, size: 14, color: isSelected ? Colors.white : AppColors.textMuted),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          opt.label,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: Theme.of(context).cardColor,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : AppColors.textPrimary),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) => onFilterChanged?.call(opt.value),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: searchHint,
        hintStyle: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted),
        prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16, color: AppColors.primary),
        suffixIcon: searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(PhosphorIconsBold.x, size: 14),
                onPressed: () => onSearchChanged(''),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            : null,
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).inputDecorationTheme.fillColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      style: GoogleFonts.cairo(fontSize: 12),
    );
  }

  Widget _buildDateRangeButton(BuildContext context) {
    return InkWell(
      onTap: () async {
        final range = await CompactDatePicker.showCompactRange(
          context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDateRange: DateTimeRange(start: dateFrom, end: dateTo),
        );
        if (range != null) {
          onDateRangeChanged(range.start, range.end);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(PhosphorIconsBold.calendar, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${_fmt.format(dateFrom)} — ${_fmt.format(dateTo)}',
                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
