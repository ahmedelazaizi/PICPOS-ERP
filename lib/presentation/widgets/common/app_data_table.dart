import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// جدول بيانات موحّد لكل شاشات النظام.
///
/// يلفّ `DataTable` القياسي بحدود ناعمة، صف رأس ملوّن، تظليل صفوف بالتناوب
/// (zebra stripes)، scroll أفقي + عمودي تلقائي، ومسافات منتظمة.
///
/// كل أعمدة الشاشات تستخدم نفس مظهر الرأس والصفوف بدون تكرار للأكواد.
///
/// الاستخدام:
/// ```dart
/// AppDataTable(
///   columns: const [
///     DataColumn(label: Text('رقم الفاتورة')),
///     DataColumn(label: Text('العميل')),
///   ],
///   rows: invoices.map((inv) => DataRow(cells: [...])).toList(),
/// )
/// ```
class AppDataTable extends StatelessWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final bool showCheckboxColumn;
  final ValueChanged<bool?>? onSelectAll;
  final double? minWidth;
  final EdgeInsetsGeometry margin;
  final bool zebra;
  final bool showHeader;
  final Widget? emptyState;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.showCheckboxColumn = false,
    this.onSelectAll,
    this.minWidth,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.zebra = true,
    this.showHeader = true,
    this.emptyState,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && emptyState != null) {
      return Container(
        margin: margin,
        decoration: _containerDecoration(context),
        padding: const EdgeInsets.all(32),
        child: Center(child: emptyState),
      );
    }

    final styledRows = zebra ? _applyZebraStripes(rows) : rows;

    // Cluster 024 / Issue 1 (perf) — switch from Flutter's stock DataTable
    // to DataTable2 (data_table_2 package). Stock DataTable builds every
    // row eagerly inside SingleChildScrollView, so screens with hundreds
    // of rows (inventory, products, parties, journal lines, reports)
    // stuttered on scroll and froze the UI thread for seconds. DataTable2
    // wraps rows in a virtualized ListView.builder — only the visible
    // window is built. Keeps the existing column / cell API so every
    // screen using AppDataTable benefits with no per-screen change.
    final table = DataTable2(
      showCheckboxColumn: showCheckboxColumn,
      onSelectAll: onSelectAll,
      headingRowColor: WidgetStateProperty.all(
        AppColors.primary.withValues(alpha: 0.06),
      ),
      headingRowHeight: showHeader ? 44 : 0,
      dataRowHeight: 44,
      dividerThickness: 0.6,
      horizontalMargin: 16,
      columnSpacing: 24,
      // Always-visible scroll thumbs so the operator can grab and drag
      // through long lists. Without this, Issue 1's "scroll is hard to
      // control" complaint persists even after virtualization.
      isVerticalScrollBarVisible: true,
      isHorizontalScrollBarVisible: true,
      minWidth: minWidth,
      empty: emptyState,
      columns: showHeader ? columns.map(_styleColumn).toList() : columns,
      rows: styledRows,
    );

    return Container(
      margin: margin,
      decoration: _containerDecoration(context),
      clipBehavior: Clip.antiAlias,
      // DataTable2 expects a bounded height (it virtualizes its own
      // ListView). Wrap in Expanded-friendly defaults via SizedBox; the
      // parent Card / Expanded provides the actual height.
      child: table,
    );
  }

  BoxDecoration _containerDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.cardDark : AppColors.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isDark ? AppColors.borderDark : AppColors.border,
        width: 0.8,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// يضيف تظليل بالتناوب لتمييز الصفوف. لا يتجاوز أي تظليل اختاره المستخدم
  /// (الصفوف المختارة تحتفظ بلونها الأصلي).
  List<DataRow> _applyZebraStripes(List<DataRow> source) {
    return List<DataRow>.generate(source.length, (i) {
      final row = source[i];
      // إذا الصف عنده color مخصص (مثل تمييز الصفوف الملغية) سيبه على حاله
      if (row.color != null) return row;
      if (i.isOdd) return row;
      return DataRow(
        key: row.key,
        selected: row.selected,
        onSelectChanged: row.onSelectChanged,
        onLongPress: row.onLongPress,
        color: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) return null;
          if (states.contains(WidgetState.hovered)) {
            return AppColors.primary.withValues(alpha: 0.04);
          }
          return AppColors.surface.withValues(alpha: 0.5);
        }),
        cells: row.cells,
      );
    });
  }

  DataColumn _styleColumn(DataColumn col) {
    final original = col.label;
    return DataColumn(
      tooltip: col.tooltip,
      numeric: col.numeric,
      onSort: col.onSort,
      label: DefaultTextStyle.merge(
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.primaryDark,
          fontSize: 13,
        ),
        child: original,
      ),
    );
  }
}
