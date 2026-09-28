import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../core/constants/app_constants.dart';
import '../widgets/branch_chip.dart';

/// A3 — Branch Performance Comparison Dashboard
/// Compares sales, profit, inventory, and invoice count across all branches.
class BranchPerformanceScreen extends ConsumerStatefulWidget {
  const BranchPerformanceScreen({super.key});

  @override
  ConsumerState<BranchPerformanceScreen> createState() =>
      _BranchPerformanceScreenState();
}

class _BranchPerformanceScreenState
    extends ConsumerState<BranchPerformanceScreen> {
  String _period = 'month';
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  bool _isLoading = false;
  List<_BranchData> _branchData = [];

  @override
  void initState() {
    super.initState();
    _onPeriodChanged('month');
  }

  void _onPeriodChanged(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() => _period = period);
    switch (period) {
      case 'today':
        _from = today;
        _to = today.add(const Duration(days: 1));
        break;
      case 'week':
        _from = today.subtract(Duration(days: today.weekday - 6)); // Saturday
        _to = now;
        break;
      case 'month':
        _from = DateTime(now.year, now.month, 1);
        _to = now;
        break;
      case 'year':
        _from = DateTime(now.year, 1, 1);
        _to = now;
        break;
    }
    _loadData();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      locale: const Locale('ar', 'EG'),
    );
    if (picked != null) {
      setState(() {
        _period = 'custom';
        _from = picked.start;
        _to = picked.end;
      });
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final branchRepo = ref.read(branchRepositoryProvider);
      var branches = await branchRepo.getBranches();

      // Spec 151 Track-3: cap the comparison to the branches this user may
      // read. getBranches() returns ALL branches with no permission filter, so
      // a branch-restricted user could otherwise see every branch's sales,
      // profit, invoices and inventory. null allowedBranchIds = full access
      // (admin/financial-manager/mirror/userId=1) → keep all branches.
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      if (!scope.hasFullAccess) {
        final allowed = scope.allowedBranchIds!;
        branches = branches.where((b) => allowed.contains(b.id)).toList();
      }

      final List<_BranchData> result = [];

      for (final branch in branches) {
        final summary =
            await branchRepo.getBranchSalesSummary(branch.id, from: _from, to: _to);
        final inventoryValue = await branchRepo.getBranchInventoryValue(branch.id);
        result.add(_BranchData(
          id: branch.id,
          name: branch.name,
          totalSales: summary.totalSales,
          totalProfit: summary.totalProfit,
          invoiceCount: summary.invoiceCount,
          avgInvoice: summary.averageInvoiceValue,
          inventoryValue: inventoryValue,
        ));
      }

      // Sort by total sales descending
      result.sort((a, b) => b.totalSales.compareTo(a.totalSales));

      if (mounted) setState(() => _branchData = result);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'ar_EG');
    final fmtInt = NumberFormat('#,##0', 'ar_EG');
    final dateFmt = DateFormat('yyyy/MM/dd', 'ar_EG');

    // Totals
    final totalSales = _branchData.fold(0.0, (s, b) => s + b.totalSales);
    final totalInvoices = _branchData.fold(0, (s, b) => s + b.invoiceCount);
    final totalInventory =
        _branchData.fold(0.0, (s, b) => s + b.inventoryValue);
    final avgInvoice = totalInvoices > 0 ? totalSales / totalInvoices : 0.0;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        body: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: const Border(
                    bottom: BorderSide(color: AppColors.border, width: 1)),
              ),
              child: Row(
                children: [
                  // Spec 057: back button — only when pushed onto navigator
                  // (e.g. from reports launcher); hidden when reached via the
                  // sidebar where canPop is false.
                  if (Navigator.canPop(context)) ...[
                    IconButton(
                      tooltip: 'رجوع',
                      icon: const Icon(PhosphorIconsBold.caretRight, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(PhosphorIconsBold.chartBar,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('مقارنة أداء الفروع',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('تحليل ومقارنة الأداء عبر جميع الفروع',
                          style:
                              TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                  const Spacer(),
                  // Period filter
                  ..._buildPeriodButtons(),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(PhosphorIconsBold.calendarBlank, size: 16),
                    label: Text(
                      _period == 'custom'
                          ? '${dateFmt.format(_from)} → ${dateFmt.format(_to)}'
                          : 'فترة مخصصة',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      side: BorderSide(
                          color: _period == 'custom'
                              ? AppColors.primary
                              : AppColors.border),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _loadData,
                    icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 18),
                    tooltip: 'تحديث',
                  ),
                ],
              ),
            ),

            // ── Summary Cards ──
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  _buildSummaryCard(
                    'إجمالي المبيعات',
                    '${fmt.format(totalSales)} ${AppConstants.currencySymbol}',
                    PhosphorIconsBold.shoppingCart,
                    AppColors.primary,
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    'عدد الفواتير',
                    fmtInt.format(totalInvoices),
                    PhosphorIconsBold.fileText,
                    AppColors.info,
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    'متوسط الفاتورة',
                    '${fmt.format(avgInvoice)} ${AppConstants.currencySymbol}',
                    PhosphorIconsBold.chartLine,
                    AppColors.warning,
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    'قيمة المخزون',
                    '${fmt.format(totalInventory)} ${AppConstants.currencySymbol}',
                    PhosphorIconsBold.warehouse,
                    AppColors.success,
                  ),
                ],
              ),
            ),

            // ── Table ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _branchData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsBold.buildings,
                                  size: 48,
                                  color: Colors.grey.withValues(alpha: 0.3)),
                              const SizedBox(height: 12),
                              const Text('لا توجد فروع',
                                  style:
                                      TextStyle(color: AppColors.textMuted)),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildComparisonTable(fmt, fmtInt),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPeriodButtons() {
    const periods = {
      'today': 'اليوم',
      'week': 'الأسبوع',
      'month': 'الشهر',
      'year': 'السنة',
    };
    return periods.entries.map((e) {
      final isActive = _period == e.key;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 4),
        child: ChoiceChip(
          label: Text(e.value, style: const TextStyle(fontSize: 12)),
          selected: isActive,
          selectedColor: AppColors.primary.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            color: isActive ? AppColors.primary : AppColors.textMuted,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) => _onPeriodChanged(e.key),
          side: BorderSide(
              color: isActive ? AppColors.primary : AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      );
    }).toList();
  }

  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonTable(NumberFormat fmt, NumberFormat fmtInt) {
    final bestSales = _branchData.isNotEmpty ? _branchData.first : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.03),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.trophy,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                const Text('ترتيب الفروع حسب المبيعات',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                Text('${_branchData.length} فرع',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Column headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: Theme.of(context).cardColor,
            child: const Row(
              children: [
                SizedBox(width: 40, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12))),
                Expanded(flex: 3, child: Text('الفرع', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12))),
                Expanded(flex: 2, child: Text('المبيعات', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12), textAlign: TextAlign.center)),
                Expanded(flex: 1, child: Text('الفواتير', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('متوسط الفاتورة', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('قيمة المخزون', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12), textAlign: TextAlign.center)),
                Expanded(flex: 1, child: Text('الحصة %', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 12), textAlign: TextAlign.center)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Rows
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _branchData.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final b = _branchData[index];
                final totalSales =
                    _branchData.fold(0.0, (s, x) => s + x.totalSales);
                final sharePercent =
                    totalSales > 0 ? (b.totalSales / totalSales * 100) : 0.0;
                final isBest = b == bestSales && b.totalSales > 0;
                final isLast =
                    index == _branchData.length - 1 && _branchData.length > 1;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  color: isBest
                      ? AppColors.success.withValues(alpha: 0.04)
                      : isLast
                          ? AppColors.error.withValues(alpha: 0.03)
                          : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: _buildRankBadge(index + 1),
                      ),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            // Feature 004 — branch chip mirrors the visual
                            // identity used on JE/sales/treasury screens so
                            // the operator gets the same colour for the same
                            // branch everywhere.
                            BranchChip(branchId: b.id, compact: true),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(b.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            if (isBest) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.success
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('الأفضل',
                                    style: TextStyle(
                                        color: AppColors.success,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(fmt.format(b.totalSales),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isBest ? AppColors.success : null,
                            )),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(fmtInt.format(b.invoiceCount),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(fmt.format(b.avgInvoice),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(fmt.format(b.inventoryValue),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Expanded(
                        flex: 1,
                        child: _buildShareBar(sharePercent),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    Color bg;
    Color fg;
    if (rank == 1) {
      bg = const Color(0xFFFFD700).withValues(alpha: 0.2);
      fg = const Color(0xFFB8860B);
    } else if (rank == 2) {
      bg = const Color(0xFFC0C0C0).withValues(alpha: 0.3);
      fg = const Color(0xFF808080);
    } else if (rank == 3) {
      bg = const Color(0xFFCD7F32).withValues(alpha: 0.2);
      fg = const Color(0xFF8B4513);
    } else {
      bg = AppColors.border.withValues(alpha: 0.3);
      fg = AppColors.textMuted;
    }
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Text('$rank',
          style:
              TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildShareBar(double percent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${percent.toStringAsFixed(1)}%',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textMuted)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: percent / 100,
            backgroundColor: AppColors.border,
            color: percent > 40
                ? AppColors.success
                : percent > 20
                    ? AppColors.warning
                    : AppColors.error,
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

/// Internal data model for branch comparison
class _BranchData {
  final int id;
  final String name;
  final double totalSales;
  final double totalProfit;
  final int invoiceCount;
  final double avgInvoice;
  final double inventoryValue;

  const _BranchData({
    required this.id,
    required this.name,
    required this.totalSales,
    required this.totalProfit,
    required this.invoiceCount,
    required this.avgInvoice,
    required this.inventoryValue,
  });
}
