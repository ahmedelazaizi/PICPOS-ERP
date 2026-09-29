import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_surface.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/dashboard_filter_provider.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../../../../core/constants/app_constants.dart';
import '../widgets/branch_chip.dart';
import '../widgets/common/common.dart';

/// Analytics Dashboard Screen - لوحة التحليلات والذكاء التجاري
class AnalyticsDashboardScreen extends ConsumerStatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  ConsumerState<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState
    extends ConsumerState<AnalyticsDashboardScreen> {
  String _selectedPeriod = 'today';
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  int? _selectedCostCenterId;
  int? _selectedBranchId;
  List<int>? _branchWarehouseIds;

  // Spec 149 B12-5b (FIL-2): the logged-in user's branch authorization scope.
  // null = full access (admin/financial-manager/mirror) → no restriction.
  // NOT the same thing as _selectedBranchId above — that's a user-facing
  // KPI filter; this is an auth-level restriction enforced on top of it.
  // Mirrors tax_report_screen.dart's B12-2 wiring. Set both in build() AND
  // at the top of the imperative loaders (_loadKPIs/_loadQuickStats), since
  // those run from FutureBuilders built inside this screen's own subtree —
  // re-resolving there closes any race where a loader could run before
  // build() has observed branchScopeProvider.
  Set<int>? _allowedBranchIds;

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  @override
  void initState() {
    super.initState();
    _setDefaultDates();
    Future.microtask(() async {
      // Feature 058: seed _selectedBranchId from the device's active branch
      // BEFORE the dashboard's first KPI query (FR-001 + FR-002). Then
      // resolve branch warehouses so all child widgets pick up the scope.
      if (_selectedBranchId == null) {
        final activeBranchId = await ref.read(activeBranchIdProvider.future);
        if (!mounted) return;
        if (activeBranchId != null) {
          setState(() => _selectedBranchId = activeBranchId);
          await _resolveBranchWarehouses(activeBranchId);
        } else if (!_noBranchNoticeShown) {
          _noBranchNoticeShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar( SnackBar(
              content: Text(tr('لم يتم تعيين فرع لهذا المستخدم — يتم عرض كل الفروع')),
              duration: const Duration(seconds: 6),
            ));
          });
        }
      }
    });
  }

  /// Resolve branch → warehouse IDs for filtering
  Future<void> _resolveBranchWarehouses(int? branchId) async {
    if (branchId == null) {
      setState(() => _branchWarehouseIds = null);
      _syncGlobalFilter();
      return;
    }
    // ISS-06: Route through branchWarehouseIdsProvider instead of direct DB access
    final warehouseIds = await ref.read(branchWarehouseIdsProvider(branchId).future);
    if (mounted) {
      setState(() => _branchWarehouseIds = warehouseIds);
      _syncGlobalFilter();
    }
  }

  /// Spec 136 (field 2026-06-11): push the current selection into the shared
  /// dashboard filter so the main dashboard cards (sales / count / profit /
  /// safes) reflect the SAME branch + cost-center + period chosen here.
  void _syncGlobalFilter() {
    ref.read(dashboardFilterProvider.notifier).update(
          branchId: _selectedBranchId,
          warehouseIds: _branchWarehouseIds,
          costCenterId: _selectedCostCenterId,
          from: _fromDate,
          to: _toDate,
        );
  }

  void _setDefaultDates() {
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  void _onPeriodChanged(String period) {
    final now = DateTime.now();
    setState(() {
      _selectedPeriod = period;
      switch (period) {
        case 'yesterday':
          _fromDate = DateTime(now.year, now.month, now.day - 1);
          _toDate = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
          break;
        case 'week':
          _fromDate = now.subtract(const Duration(days: 7));
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'month':
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'year':
          _fromDate = DateTime(now.year, 1, 1);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'today':
        default:
          _fromDate = DateTime(now.year, now.month, now.day);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
    });
    _syncGlobalFilter();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      locale: const Locale('ar'),
      builder: (context, child) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: AppColors.primary),
            ),
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedPeriod = 'custom';
        _fromDate = picked.start;
        _toDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
      _syncGlobalFilter();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Spec 149 B12-5b (FIL-2): resolve the auth-level branch scope BEFORE any
    // KPI/report query runs. Reports MUST NOT render (even a flash) while the
    // scope is unknown — a restricted user briefly seeing an unscoped
    // dashboard is itself the leak this fix closes. Mirrors tax_report_screen.
    final scopeAsync = ref.watch(branchScopeProvider);
    if (scopeAsync.isLoading) {
      return const Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (scopeAsync.hasError) {
      return Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(
          body: Center(child: Text(tr('تعذر تحديد صلاحيات الفرع: {p0}', {'p0': scopeAsync.error}))),
        ),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title:  Text(tr('التحليلات والتقارير')),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDateFilter(),
              const SizedBox(height: 16),
              _buildKPICards(),
              const SizedBox(height: 24),
              _buildChartsRow(),
              const SizedBox(height: 24),
              _buildBottomSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateFilter() {
    final dateFormat =
        '${_fromDate.year}/${_fromDate.month.toString().padLeft(2, '0')}/${_fromDate.day.toString().padLeft(2, '0')}';
    final toFormat =
        '${_toDate.year}/${_toDate.month.toString().padLeft(2, '0')}/${_toDate.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Date range display with calendar button
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: context.picposHairline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$dateFormat - $toFormat',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          const VerticalDivider(width: 1, thickness: 1),
          const SizedBox(width: 16),
          // Quick period buttons
          _buildPeriodButton('today', tr('اليوم')),
          const SizedBox(width: 8),
          _buildPeriodButton('yesterday', tr('أمس')),
          const SizedBox(width: 8),
          _buildPeriodButton('month', tr('الشهر')),
          const SizedBox(width: 8),
          _buildPeriodButton('year', tr('السنة')),
          const Spacer(),
          // GAP-04: Cost Center filter
          SizedBox(
            width: 160,
            child: FutureBuilder<List<CostCenter>>(
              future: ref.read(accountingRepositoryProvider).getActiveCostCenters(),
              builder: (ctx, snap) {
                final ccList = snap.data ?? [];
                if (ccList.isEmpty) return const SizedBox.shrink();
                return DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _selectedCostCenterId,
                    isExpanded: true,
                    hint:  Text(tr('مركز التكلفة'), style: const TextStyle(fontSize: 12)),
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    items: [
                       DropdownMenuItem<int?>(value: null, child: Text(tr('الكل'))),
                      ...ccList.map((cc) => DropdownMenuItem<int?>(value: cc.id, child: Text(cc.name))),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedCostCenterId = v);
                      _syncGlobalFilter();
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // GAP-04: Branch filter
          SizedBox(
            width: 160,
            child: FutureBuilder<List<Branche>>(
              future: ref.read(branchRepositoryProvider).getBranches(),
              builder: (ctx, snap) {
                final branches = snap.data ?? [];
                if (branches.isEmpty) return const SizedBox.shrink();
                return DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _selectedBranchId,
                    isExpanded: true,
                    hint:  Text(tr('الفرع'), style: const TextStyle(fontSize: 12)),
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    items: [
                       DropdownMenuItem<int?>(value: null, child: Text(tr('الكل'))),
                      // Feature 004 — branch chips in the analytics filter
                      // dropdown so the operator picks a branch by colour,
                      // not by reading the name. Same colour mapping as
                      // every other Feature 004 surface.
                      ...branches.map((b) => DropdownMenuItem<int?>(
                            value: b.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BranchChip(branchId: b.id, compact: true),
                                const SizedBox(width: 6),
                                Flexible(child: Text(b.name)),
                              ],
                            ),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _selectedBranchId = v;
                        _branchWarehouseIds = null; // reset until resolved
                      });
                      _resolveBranchWarehouses(v);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String period, String label) {
    final isSelected = _selectedPeriod == period;
    return InkWell(
      onTap: () => _onPeriodChanged(period),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : context.picposField,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : context.picposHairline,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            // الأبيضُ للمحدَّدِ صحيحٌ — نصٌّ على `primary`. وغيرُ المحدَّدِ
            // يقع على سطحِ البطاقة، فيتبع الوضعَ وإلّا صار داكناً على داكن.
            color: isSelected ? Colors.white : context.picposText,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildKPICards() {
    final reportRepo = ref.watch(reportingRepositoryProvider);
    // Key changes when date range or filter changes to force FutureBuilder rebuild
    final dateKey =
        '${_fromDate.millisecondsSinceEpoch}_${_toDate.millisecondsSinceEpoch}_${_selectedCostCenterId}_$_selectedBranchId';

    return FutureBuilder(
      key: ValueKey(dateKey),
      future: _loadKPIs(reportRepo),
      builder: (context, snapshot) {
        final kpis = snapshot.data ?? _defaultKPIs;
        return AppKpiGrid(
          itemHeight: 78,
          children: kpis
              .map((k) => AppKpiCard(
                    icon: k.icon,
                    label: k.label,
                    value: k.value,
                    subtitle: k.subtitle,
                    trend: k.trend,
                    color: k.color,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildChartsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildSalesChart()),
        const SizedBox(width: 20),
        Expanded(child: _buildTopProductsList()),
      ],
    );
  }

  Widget _buildSalesChart() {
    final reportRepo = ref.watch(reportingRepositoryProvider);

    return Container(
      height: 350,
      padding: const EdgeInsets.all(20),
      // ...
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FutureBuilder<List<DailySalesSummaryRow>>(
        key: ValueKey(
          'chart_${_fromDate.millisecondsSinceEpoch}_${_toDate.millisecondsSinceEpoch}_${_selectedCostCenterId}_$_selectedBranchId',
        ),
        future: reportRepo.getDailySalesForRange(
          from: _fromDate,
          to: _toDate,
          costCenterId: _selectedCostCenterId,
          warehouseIds: _branchWarehouseIds,
          allowedBranchIds: _allowedBranchIds,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(tr('خطأ: {p0}', {'p0': snapshot.error})));
          }

          final data = snapshot.data ?? [];
          if (data.isEmpty) {
            return  Center(child: Text(tr('لا توجد بيانات مبيعات')));
          }

          // Chart title based on period
          String chartTitle = tr('المبيعات اليومية');
          if (_selectedPeriod == 'today') {
            chartTitle = tr('مبيعات اليوم');
          } else if (_selectedPeriod == 'yesterday') {
            chartTitle = tr('مبيعات أمس');
          } else if (_selectedPeriod == 'month') {
            chartTitle = tr('مبيعات الشهر');
          } else if (_selectedPeriod == 'year') {
            chartTitle = tr('مبيعات السنة');
          } else {
            chartTitle = tr('المبيعات للفترة المحددة');
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    chartTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(child: _buildSimpleBarChart(data)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSimpleBarChart(List<DailySalesSummaryRow> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    final values = data.map((e) => e.total).toList();
    final labels = data.map((e) => e.date.split('-').last).toList();

    final maxValue = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxValue * 1.15,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${values[group.x.toInt()].toStringAsFixed(0)} ${AppConstants.currencySymbol}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labels[idx], style: const TextStyle(fontSize: 10)),
                );
              },
              reservedSize: 24,
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(values.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i],
                width: data.length > 15 ? 12 : 22,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFF64B5F6)],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ],
          );
        }),
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildTopProductsList() {
    final reportRepo = ref.watch(reportingRepositoryProvider);
    return Container(
      height: 350,
      padding: const EdgeInsets.all(20),
      // ... same decoration
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FutureBuilder<List<TopSellingProductRow>>(
        key: ValueKey(
          'products_${_fromDate.millisecondsSinceEpoch}_${_toDate.millisecondsSinceEpoch}_${_selectedCostCenterId}_$_selectedBranchId',
        ),
        future: reportRepo.getTopSellingProducts(
          limit: 5,
          from: _fromDate,
          to: _toDate,
          costCenterId: _selectedCostCenterId,
          warehouseIds: _branchWarehouseIds,
          allowedBranchIds: _allowedBranchIds,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return  Center(child: Text(tr('لا توجد مبيعات')));
          }

          final maxSales = products
              .map((e) => e.totalSales)
              .reduce((a, b) => a > b ? a : b);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(
                tr('الأكثر مبيعاً'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final p = products[index];
                    final total = p.totalSales;
                    final percentage = maxSales > 0
                        ? (total / maxSales) * 100
                        : 0.0;

                    return _buildProductItem(
                      index + 1,
                      p.name,
                      p.totalQuantity.toInt(),
                      percentage,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProductItem(
    int rank,
    String name,
    int count,
    double percentage,
  ) {
    final colors = [
      Colors.amber,
      Colors.grey.shade400,
      Colors.brown.shade300,
      Colors.blue,
      Colors.purple,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: colors[rank - 1],
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(colors[rank - 1]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildPeakHoursCard()),
            const SizedBox(width: 20),
            Expanded(child: _buildPaymentMethodsCard()),
            const SizedBox(width: 20),
            Expanded(child: _buildQuickStatsCard()),
          ],
        ),
        const SizedBox(height: 24),
        _buildExpensesCard(),
      ],
    );
  }

  Widget _buildExpensesCard() {
    // ISS-06: Route through monthlyExpenseSummaryProvider instead of direct DB access
    final expenseRange = (from: _fromDate, to: _toDate);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(
          'expenses_${_fromDate.millisecondsSinceEpoch}_${_toDate.millisecondsSinceEpoch}',
        ),
        future: ref.read(monthlyExpenseSummaryProvider(expenseRange).future),
        builder: (context, snapshot) {
          final categories = snapshot.data ?? [];
          final activeCategories = categories
              .where((c) => ((c['total_amount'] as num?)?.toDouble() ?? 0) > 0)
              .toList();
          final totalExpenses = activeCategories.fold<double>(
            0.0,
            (sum, c) => sum + ((c['total_amount'] as num?)?.toDouble() ?? 0.0),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(PhosphorIconsBold.coins, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                   Text(
                    tr('تفصيل المصروفات'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tr('الإجمالي: {p0} {p1}', {'p0': totalExpenses.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}),
                      style: const TextStyle(
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!snapshot.hasData)
                const Center(child: CircularProgressIndicator())
              else if (activeCategories.isEmpty)
                 Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      tr('لا توجد مصروفات في هذه الفترة'),
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 3.5,
                  ),
                  itemCount: activeCategories.length,
                  itemBuilder: (context, index) {
                    final cat = activeCategories[index];
                    final name = (cat['name'] as String?) ?? tr('مصروف');
                    final amount = (cat['total_amount'] as num?)?.toDouble() ?? 0.0;
                    final count = (cat['entry_count'] as num?)?.toInt() ?? 0;
                    final pct = totalExpenses > 0 ? (amount / totalExpenses * 100) : 0.0;

                    final colors = [
                      Colors.deepOrange,
                      AppColors.error,
                      Colors.amber.shade700,
                      Colors.brown,
                      Colors.indigo,
                      Colors.teal,
                      Colors.pink,
                    ];
                    final color = colors[index % colors.length];

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  tr('{count} قيد', {'count': count}),
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                amount.toStringAsFixed(AppConstants.decimalPlaces),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                              Text(
                                '${pct.toStringAsFixed(0)}%',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPeakHoursCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Row(
            children: [
              const Icon(PhosphorIconsBold.clock, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                tr('ساعات الذروة'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPeakHourRow('12:00 - 14:00', 0.85, tr('الغداء')),
          _buildPeakHourRow('18:00 - 20:00', 0.72, tr('العشاء')),
          _buildPeakHourRow('09:00 - 11:00', 0.58, tr('الفطور')),
        ],
      ),
    );
  }

  Widget _buildPeakHourRow(String time, double value, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(time, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: value,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsCard() {
    final reportRepo = ref.watch(reportingRepositoryProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FutureBuilder<List<PaymentMethodStatRow>>(
        future: reportRepo.getPaymentMethodStats(costCenterId: _selectedCostCenterId, from: _fromDate, to: _toDate, allowedBranchIds: _allowedBranchIds),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // H14 · الطيُّ إلى قنوات **قبل** الرسم. الاستعلامُ يجمع بالقيمة
          // الخام (`card` · `transfer` · `bank` ثلاثةُ صفوف) والعرضُ يسمّيها
          // كلَّها «بطاقة/تحويل» — فكانت الفطيرةُ تُظهر نفسَ الاسم ثلاثَ
          // مرّاتٍ بثلاث نسبٍ لا يستطيع القارئ جمعَها بعينه.
          final stats = foldPaymentChannels(snapshot.data ?? []);
          final totalAll = stats.fold<double>(
            0, (sum, item) => sum + item.total,
          );

          // Build sections and legend
          final sections = <PieChartSectionData>[];
          final legends = <Widget>[];

          for (final s in stats) {
            final amount = s.total;
            final percent = totalAll > 0 ? (amount / totalAll * 100) : 0.0;
            final (Color color, String label) = switch (s.channel) {
              PaymentChannel.cash => (Colors.green, tr('نقدي')),
              PaymentChannel.card => (Colors.blue, tr('بطاقة/تحويل')),
              PaymentChannel.click => (const Color(0xFF7E57C2), tr('كليك')),
              PaymentChannel.credit => (Colors.orange, tr('آجل')),
              PaymentChannel.multiple => (Colors.purple, tr('متعدد')),
              PaymentChannel.other => (Colors.grey, tr('أخرى')),
            };

            sections.add(PieChartSectionData(
              color: color,
              value: amount,
              title: '${percent.toStringAsFixed(0)}%',
              radius: 40,
              titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ));
            legends.add(_buildPaymentRow(label, percent.toInt(), color));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Row(
                children: [
                  const Icon(PhosphorIconsBold.creditCard, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(tr('طرق الدفع'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              if (stats.isEmpty)
                 Text(tr('لا توجد بيانات'))
              else ...[              
                SizedBox(
                  height: 120,
                  child: PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 24,
                      sectionsSpace: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...legends,
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildPaymentRow(String method, int percentage, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(method)),
          Text(
            '$percentage%',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatsCard() {
    final reportRepo = ref.watch(reportingRepositoryProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(
          'quickstats_${_fromDate.millisecondsSinceEpoch}_${_toDate.millisecondsSinceEpoch}_${_selectedCostCenterId}_$_selectedBranchId',
        ),
        future: _loadQuickStats(reportRepo, warehouseIds: _branchWarehouseIds),
        builder: (context, snapshot) {
          final stats =
              snapshot.data ??
              {'avgInvoice': 0.0, 'customerCount': 0, 'returnRate': 0.0};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Row(
                children: [
                  const Icon(PhosphorIconsBold.lightning, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    tr('إحصائيات سريعة'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildQuickStatRow(
                tr('متوسط الفاتورة'),
                '${(stats['avgInvoice'] as double).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              ),
              _buildQuickStatRow(tr('عدد العملاء'), '${stats['customerCount']}'),
              _buildQuickStatRow(
                tr('نسبة الإرجاع'),
                '${(stats['returnRate'] as double).toStringAsFixed(1)}%',
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _loadQuickStats(
    IReportingRepository reportRepo, {
    List<int>? warehouseIds,
  }) async {
    try {
      // Spec 149 B12-5b (FIL-2): re-resolve the auth-level branch scope here
      // too — this loader runs from a FutureBuilder built inside this
      // screen's own subtree (after build()'s gate), but re-resolving
      // closes any race were it ever invoked before build() settles.
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) {
        return {'avgInvoice': 0.0, 'customerCount': 0, 'returnRate': 0.0};
      }
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      // Use getSalesAnalytics (which honors costCenter + warehouseIds)
      // instead of the old getTotalSales / getSalesCount pair — those
      // returned company-wide totals regardless of the dashboard's
      // selected cost center, which made the avg-invoice and return-
      // rate quick-stats inconsistent with the rest of the screen.
      final analytics = await reportRepo.getSalesAnalytics(
        _fromDate,
        _toDate,
        costCenterId: _selectedCostCenterId,
        warehouseIds: warehouseIds,
        allowedBranchIds: _allowedBranchIds,
      );
      final totalSales = analytics.totalSales;
      final invoiceCount = analytics.invoiceCount;
      final customerCount = await reportRepo.getNewCustomersCount(
        from: _fromDate,
        to: _toDate,
        costCenterId: _selectedCostCenterId,
        allowedBranchIds: _allowedBranchIds,
      );

      // Calculate average invoice
      final avgInvoice = invoiceCount > 0 ? totalSales / invoiceCount : 0.0;

      // Calculate real return rate from DB.
      // Spec 151 D-02: returns analytics ARE branch-scoped now. safe_transactions
      // has no branch_id, but branch is reachable via safe_id → safes.branch_id,
      // so getSalesReturnsAnalytics joins safes and applies the same auth scope
      // as the sales/purchase KPIs beside it. Restricted users no longer see
      // company-wide return totals.
      final salesReturns = await reportRepo.getSalesReturnsAnalytics(
        from: _fromDate,
        to: _toDate,
        costCenterId: _selectedCostCenterId,
        warehouseIds: warehouseIds,
        allowedBranchIds: _allowedBranchIds,
      );
      final returnTotal = salesReturns.total;
      final returnRate = totalSales > 0 ? (returnTotal / totalSales) * 100 : 0.0;

      return {
        'avgInvoice': avgInvoice,
        'customerCount': customerCount,
        'returnRate': returnRate,
      };
    } catch (e) {
      return {'avgInvoice': 0.0, 'customerCount': 0, 'returnRate': 0.0};
    }
  }

  Widget _buildQuickStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Future<List<KPIData>> _loadKPIs(IReportingRepository reportRepo) async {
    // Use the user-selected date range from state
    final from = _fromDate;
    final to = _toDate;

    try {
      // Spec 149 B12-5b (FIL-2): re-resolve the auth-level branch scope here
      // too — this loader runs from a FutureBuilder built inside this
      // screen's own subtree (after build()'s gate), but re-resolving
      // closes any race were it ever invoked before build() settles.
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return _defaultKPIs;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      debugPrint('Analytics KPI: Loading from $from to $to');

      // Get full sales analytics including actual profit from cost prices
      final analytics = await reportRepo.getSalesAnalytics(from, to, costCenterId: _selectedCostCenterId, warehouseIds: _branchWarehouseIds, allowedBranchIds: _allowedBranchIds);
      final activeCustomers = await reportRepo.getNewCustomersCount(
        from: from,
        to: to,
        costCenterId: _selectedCostCenterId,
        allowedBranchIds: _allowedBranchIds,
      );

      // Load returns analytics.
      // Spec 151 D-02: now branch-scoped via safe_transactions.safe_id →
      // safes.branch_id (see the return-rate site above). Restricted users see
      // only their own branches' return totals.
      final salesReturns = await reportRepo.getSalesReturnsAnalytics(
        from: from,
        to: to,
        costCenterId: _selectedCostCenterId,
        warehouseIds: _branchWarehouseIds,
        allowedBranchIds: _allowedBranchIds,
      );
      final purchaseReturns = await reportRepo.getPurchaseReturnsAnalytics(
        from: from,
        to: to,
        costCenterId: _selectedCostCenterId,
        warehouseIds: _branchWarehouseIds,
        allowedBranchIds: _allowedBranchIds,
      );

      // Load purchases analytics — routed through repo for filter support
      final purchasesAnalytics = await reportRepo.getPurchasesReportAnalytics(
        from,
        to,
        costCenterId: _selectedCostCenterId,
        warehouseIds: _branchWarehouseIds,
        allowedBranchIds: _allowedBranchIds,
      );

      // Spec 136 (field 2026-06-11): revenue / COGS / net profit now come from
      // the GL income statement (قائمة الدخل) — the single source of truth —
      // scoped by the SAME period + cost-center + branch as the grid. Fixes:
      // output-VAT wrongly treated as a cost in profit, the expense leg
      // ignoring the branch/cost-center filter, and COGS/returns diverging from
      // the posted ledger. (VAT is a liability — never revenue/expense; returns
      // are GL contra-revenue; expenses are GL-posted — all handled correctly.)
      // B11 REP-1 (spec 149): confirmed this already satisfies "صافي الربح
      // must be GL-sourced" — the headline KPI below (label 'صافي الربح')
      // reads glNetProfit, not the ad-hoc analytics.totalNetProfit/
      // totalProfit. The getSalesAnalytics call above is used ONLY for
      // invoiceCount / trend — its profit fields are never displayed here.
      final incomeStmt = await reportRepo.getIncomeStatement(
        from, to,
        costCenterId: _selectedCostCenterId,
        branchId: _selectedBranchId,
        allowedBranchIds: _allowedBranchIds,
      );
      final glRevenue = (incomeStmt['totalRevenue'] as num?)?.toDouble() ?? 0.0;
      final glCOGS = (incomeStmt['totalCOGS'] as num?)?.toDouble() ?? 0.0;
      final glExpenses = (incomeStmt['totalExpenses'] as num?)?.toDouble() ?? 0.0;
      final glNetProfit = (incomeStmt['netProfit'] as num?)?.toDouble() ?? 0.0;

      // Calculate trend by comparing with equivalent previous period
      final periodDuration = to.difference(from);
      final prevFrom = from.subtract(periodDuration);
      final prevTo = from.subtract(const Duration(seconds: 1));

      final prevAnalytics = await reportRepo.getSalesAnalytics(prevFrom, prevTo, costCenterId: _selectedCostCenterId, warehouseIds: _branchWarehouseIds, allowedBranchIds: _allowedBranchIds);
      final prevCustomers = await reportRepo.getNewCustomersCount(
        from: prevFrom,
        to: prevTo,
        costCenterId: _selectedCostCenterId,
        allowedBranchIds: _allowedBranchIds,
      );
      final prevPurchases = await reportRepo.getPurchasesReportAnalytics(
        prevFrom,
        prevTo,
        costCenterId: _selectedCostCenterId,
        warehouseIds: _branchWarehouseIds,
        allowedBranchIds: _allowedBranchIds,
      );

      // Previous-period GL figures for apples-to-apples trend %.
      final prevIncomeStmt = await reportRepo.getIncomeStatement(
        prevFrom, prevTo,
        costCenterId: _selectedCostCenterId,
        branchId: _selectedBranchId,
        allowedBranchIds: _allowedBranchIds,
      );
      final prevGlRevenue = (prevIncomeStmt['totalRevenue'] as num?)?.toDouble() ?? 0.0;
      final prevGlCOGS = (prevIncomeStmt['totalCOGS'] as num?)?.toDouble() ?? 0.0;
      final prevGlNetProfit = (prevIncomeStmt['netProfit'] as num?)?.toDouble() ?? 0.0;

      double calcTrend(double current, double previous) {
        if (previous == 0) return current > 0 ? 100.0 : 0.0;
        return ((current - previous) / previous) * 100;
      }

      final salesTrend = calcTrend(glRevenue, prevGlRevenue);
      final countTrend = calcTrend(
        analytics.invoiceCount.toDouble(),
        prevAnalytics.invoiceCount.toDouble(),
      );
      final profitTrend = calcTrend(glNetProfit, prevGlNetProfit);
      final customerTrend = calcTrend(
        activeCustomers.toDouble(),
        prevCustomers.toDouble(),
      );
      final purchaseTrend = calcTrend(
        purchasesAnalytics.totalPurchases,
        prevPurchases.totalPurchases,
      );

      return [
        KPIData(
          icon: PhosphorIconsBold.currencyCircleDollar,
          // REP-5 (spec 149 B15): value is GL income-statement revenue (net of
          // VAT + returns), so «صافي الإيراد» not «إجمالي المبيعات» — same
          // disambiguation spec 142 applied to dashboard_screen.
          label: tr('صافي الإيراد'),
          value:
              '${glRevenue.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          trend: salesTrend,
          color: AppColors.primary,
          subtitle: tr('إيراد دفتر الأستاذ — صافي الضريبة والمردودات'),
        ),
        KPIData(
          icon: PhosphorIconsBold.receipt,
          label: tr('عدد الفواتير'),
          value: '${analytics.invoiceCount}',
          trend: countTrend,
          color: Colors.blue,
        ),
        KPIData(
          icon: PhosphorIconsBold.coins,
          label: tr('تكلفة البضاعة المباعة'),
          value:
              '${glCOGS.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          trend: calcTrend(glCOGS, prevGlCOGS),
          color: const Color(0xFFD97706),
          subtitle: tr('من دفتر الأستاذ (حساب التكلفة)'),
        ),
        KPIData(
          icon: PhosphorIconsBold.trendUp,
          label: tr('صافي الربح'),
          value:
              '${glNetProfit.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          trend: profitTrend,
          color: glNetProfit >= 0 ? Colors.green : AppColors.error,
          subtitle: tr('هامش الربح: {p0}% | مصروفات: {p1}', {'p0': glRevenue > 0 ? ((glNetProfit / glRevenue) * 100).toStringAsFixed(1) : '0.0', 'p1': glExpenses.toStringAsFixed(AppConstants.decimalPlaces)}),
        ),
        KPIData(
          icon: PhosphorIconsBold.shoppingCart,
          label: tr('إجمالي المشتريات'),
          value:
              '${purchasesAnalytics.totalPurchases.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          trend: purchaseTrend,
          color: const Color(0xFF0891B2),
          subtitle: tr('عدد: {p0} | متوسط: {p1}', {'p0': purchasesAnalytics.invoiceCount, 'p1': purchasesAnalytics.averagePurchaseValue.toStringAsFixed(AppConstants.decimalPlaces)}),
        ),
        KPIData(
          icon: PhosphorIconsBold.usersThree,
          label: tr('عملاء نشطين'),
          value: '$activeCustomers',
          trend: customerTrend,
          color: Colors.purple,
        ),
        KPIData(
          icon: PhosphorIconsBold.arrowUUpLeft,
          label: tr('مرتجع المبيعات'),
          value:
              '${salesReturns.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          trend: 0,
          color: Colors.orange,
          subtitle: tr('عدد: {p0}', {'p0': salesReturns.count}),
        ),
        KPIData(
          icon: PhosphorIconsBold.arrowUDownLeft,
          label: tr('مرتجع المشتريات'),
          value:
              '${purchaseReturns.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          trend: 0,
          color: AppColors.error,
          subtitle: tr('عدد: {p0}', {'p0': purchaseReturns.count}),
        ),
      ];
    } catch (e) {
      debugPrint('Error loading KPIs: $e');
      return _defaultKPIs;
    }
  }

  List<KPIData> get _defaultKPIs => [
    KPIData(
      icon: PhosphorIconsBold.currencyCircleDollar,
      label: tr('صافي الإيراد'), // REP-5: matches the live GL-net-revenue card above
      value: '0.00 ${AppConstants.currencySymbolEn}',
      trend: 0,
      color: AppColors.primary,
    ),
    KPIData(
      icon: PhosphorIconsBold.receipt,
      label: tr('عدد الفواتير'),
      value: '0',
      trend: 0,
      color: Colors.blue,
    ),
    KPIData(
      icon: PhosphorIconsBold.coins,
      label: tr('تكلفة البضاعة المباعة'),
      value: '0.00 ${AppConstants.currencySymbolEn}',
      trend: 0,
      color: const Color(0xFFD97706),
    ),
    KPIData(
      icon: PhosphorIconsBold.trendUp,
      label: tr('صافي الربح'),
      value: '0.00 ${AppConstants.currencySymbolEn}',
      trend: 0,
      color: Colors.green,
    ),
    KPIData(
      icon: PhosphorIconsBold.shoppingCart,
      label: tr('إجمالي المشتريات'),
      value: '0.00 ${AppConstants.currencySymbolEn}',
      trend: 0,
      color: const Color(0xFF0891B2),
    ),
    KPIData(
      icon: PhosphorIconsBold.usersThree,
      label: tr('عملاء'),
      value: '0',
      trend: 0,
      color: Colors.purple,
    ),
    KPIData(
      icon: PhosphorIconsBold.arrowUUpLeft,
      label: tr('مرتجع المبيعات'),
      value: '0.00 ${AppConstants.currencySymbolEn}',
      trend: 0,
      color: Colors.orange,
    ),
    KPIData(
      icon: PhosphorIconsBold.arrowUDownLeft,
      label: tr('مرتجع المشتريات'),
      value: '0.00 ${AppConstants.currencySymbolEn}',
      trend: 0,
      color: AppColors.error,
    ),
  ];
}

/// KPI Data model
class KPIData {
  final IconData icon;
  final String label;
  final String value;
  final double trend;
  final Color color;
  final String? subtitle;

  KPIData({
    required this.icon,
    required this.label,
    required this.value,
    required this.trend,
    required this.color,
    this.subtitle,
  });
}
