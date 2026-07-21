// ignore_for_file: avoid_dynamic_calls
import 'package:ural_erp/core/constants/app_constants.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' as intl;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/branch_warehouse_filter.dart';
import '../../widgets/report_components.dart' show DateRangeFilter;
import '../../widgets/report_filter_bar.dart';

class CategoryProfitReportScreen extends ConsumerStatefulWidget {
  const CategoryProfitReportScreen({super.key});

  @override
  ConsumerState<CategoryProfitReportScreen> createState() =>
      _CategoryProfitReportScreenState();
}

class _CategoryProfitReportScreenState
    extends ConsumerState<CategoryProfitReportScreen> {
  // Spec 065: defaults are full-day-inclusive — start of (today-30) at 00:00,
  // end of today at 23:59:59.999 (D3-006).
  DateTime _fromDate = DateRangeFilter.normalizeStart(
      DateTime.now().subtract(const Duration(days: 30)));
  DateTime _toDate = DateRangeFilter.normalizeEnd(DateTime.now());
  final _currencyFormat = intl.NumberFormat.currency(
    symbol: '',
    decimalDigits: AppConstants.decimalPlaces,
  );
  bool _isLoading = false;
  List<CategoryProfitRow>? _data;
  int? _selectedRegionId; // Feature 017 — wire region filter to data load
  int? _selectedBranchId;
  int? _selectedWarehouseId;
  Set<int>? _branchWarehouseIds;
  Set<int>? _regionWarehouseIds;
  int? _selectedCostCenterId; // cost-center isolation filter
  List<CostCenter> _costCenters = [];

  // Spec 149 B12-5b (FIL-2): the logged-in user's branch authorization scope.
  // null = full access (admin/financial-manager/mirror) → no restriction.
  // Mirrors tax_report_screen.dart's B12-2 wiring. Set both here (build())
  // AND at the top of _loadData() — this screen fetches imperatively from
  // initState()'s microtask, which can run before build() ever resolves
  // branchScopeProvider; _loadData() re-resolves the scope itself so the
  // very first fetch can never race ahead unrestricted.
  Set<int>? _allowedBranchIds;

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // Feature 058: seed _selectedBranchId from the device's active branch
      // BEFORE the first data fetch (FR-001 + FR-002).
      if (_selectedBranchId == null) {
        final activeBranchId = await ref.read(activeBranchIdProvider.future);
        if (!mounted) return;
        if (activeBranchId != null) {
          setState(() => _selectedBranchId = activeBranchId);
        } else if (!_noBranchNoticeShown) {
          _noBranchNoticeShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('لم يتم تعيين فرع لهذا المستخدم — يتم عرض كل الفروع'),
              duration: Duration(seconds: 6),
            ));
          });
        }
      }
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(user?.id ?? 0, user?.displayName ?? 'مجهول', 'أرباح التصنيفات');
      } catch (_) {}
      _loadCostCenters();
      _loadData();
    });
  }

  Future<void> _loadCostCenters() async {
    try {
      final centers =
          await ref.read(accountingRepositoryProvider).getActiveCostCenters();
      if (mounted) setState(() => _costCenters = centers);
    } catch (_) {/* non-fatal — the CC filter just stays hidden */}
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Spec 149 B12-5b (FIL-2): resolve the auth-level branch scope BEFORE
      // the report query runs, on every call. _loadData is invoked both from
      // initState's microtask and from the filter-bar onChanged callbacks,
      // so re-resolving here (rather than relying solely on build()'s
      // ref.watch) closes the race where the FIRST load could otherwise run
      // before build() ever observes branchScopeProvider.
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final repo = ref.read(reportingRepositoryProvider);
      // Feature 017 — resolve filter scope: warehouse > branch > region.
      // Without the region branch the dropdown was a silent no-op.
      List<int>? warehouseIds;
      if (_selectedWarehouseId != null) {
        warehouseIds = [_selectedWarehouseId!];
      } else if (_branchWarehouseIds != null) {
        warehouseIds = _branchWarehouseIds!.toList();
      } else if (_regionWarehouseIds != null) {
        warehouseIds = _regionWarehouseIds!.toList();
      }
      final data = await repo.getCategoryProfitReport(
        from: _fromDate,
        to: _toDate,
        warehouseIds: warehouseIds,
        allowedBranchIds: _allowedBranchIds,
        costCenterId: _selectedCostCenterId,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
    );
    if (picked != null) {
      setState(() {
        _fromDate = DateRangeFilter.normalizeStart(picked.start);
        _toDate = DateRangeFilter.normalizeEnd(picked.end); // FIL-6: end-of-day
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Spec 149 B12-5b (FIL-2): resolve the auth-level branch scope BEFORE any
    // report query runs. Reports MUST NOT render (even a flash) while the
    // scope is unknown — a restricted user briefly seeing an unscoped
    // report is itself the leak this fix closes. Mirrors tax_report_screen.
    // This screen has no Directionality wrapper of its own (RTL comes from
    // the app-level MaterialApp), so the gate widgets match that — bare
    // Scaffold, no Directionality.
    final scopeAsync = ref.watch(branchScopeProvider);
    if (scopeAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (scopeAsync.hasError) {
      return Scaffold(
        body: Center(child: Text('تعذر تحديد صلاحيات الفرع: ${scopeAsync.error}')),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('أرباح التصنيفات'),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.fileXls),
            onPressed: _exportToExcel,
            tooltip: 'تصدير Excel',
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.printer),
            onPressed: _exportToExcel,
            tooltip: 'طباعة',
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.calendar),
            onPressed: _selectDateRange,
            tooltip: 'تغيير الفترة',
          ),
        ],
      ),
      body: Column(
        children: [
          // Spec 076: unified two-row filter bar. Field-pair _fromDate/_toDate
          // adapted into a DateTimeRange on read; split back on emit.
          ReportFilterBar(
            selectedRange: DateTimeRange(start: _fromDate, end: _toDate),
            onRangeChanged: (start, end) {
              setState(() {
                _fromDate = start;
                _toDate = end;
              });
              _loadData();
            },
            trailing: [
              BranchWarehouseFilterBar(
                selectedRegionId: _selectedRegionId,
                selectedBranchId: _selectedBranchId,
                selectedWarehouseId: _selectedWarehouseId,
                onRegionChanged: (v) async {
                  _selectedRegionId = v;
                  _selectedBranchId = null;
                  _selectedWarehouseId = null;
                  _branchWarehouseIds = null;
                  if (v != null) {
                    _regionWarehouseIds =
                        await BranchWarehouseFilterBar.getRegionWarehouseIds(ref, v);

                    // Spec 079 / B1+FR-003: warn when region selection yields zero

                    // warehouses (data-integrity hint for the operator).

                    final regionIdsCheck = _regionWarehouseIds;

                    if (regionIdsCheck != null && regionIdsCheck.isEmpty) {

                      unawaited(DiagnosticLogger.log(

                        'FILTER-WARN',

                        'Region \$v selected but no warehouses linked. '

                        'Check that branches in this region have a regionId, '

                        'and their warehouses have branchId set.',

                      ));

                    }

                  } else {
                    _regionWarehouseIds = null;
                  }
                  _loadData();
                },
                onBranchChanged: (v) async {
                  _selectedBranchId = v;
                  _selectedWarehouseId = null;
                  if (v != null) {
                    _branchWarehouseIds = await BranchWarehouseFilterBar.getBranchWarehouseIds(ref, v);
                  } else {
                    _branchWarehouseIds = null;
                  }
                  _loadData();
                },
                onWarehouseChanged: (v) {
                  setState(() => _selectedWarehouseId = v);
                  _loadData();
                },
              ),
              // Cost-center isolation (self + descendants). Hidden when the
              // system has no cost centers configured.
              if (_costCenters.isNotEmpty)
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<int?>(
                    value: _selectedCostCenterId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'مركز التكلفة',
                      isDense: true,
                      prefixIcon: Icon(PhosphorIconsBold.target, size: 18),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('كل المراكز'),
                      ),
                      ..._costCenters.map((cc) => DropdownMenuItem<int?>(
                            value: cc.id,
                            child: Text(cc.name, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedCostCenterId = v);
                      _loadData();
                    },
                  ),
                ),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(PhosphorIconsBold.arrowsClockwise),
                label: const Text('تحديث'),
              ),
            ],
          ),
          const Divider(height: 1),

          // Report Table
          Expanded(
            child: _isLoading
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: ShimmerLoading.list(itemCount: 6),
                  )
                : _data == null || _data!.isEmpty
                    ? const Center(
                        child: Text('لا توجد بيانات لهذه الفترة'),
                      )
                    : _buildReportContent(_data!),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent(List<CategoryProfitRow> data) {
    final totalSales = data.fold<double>(0, (sum, item) => sum + item.totalSales);
    final totalCost = data.fold<double>(0, (sum, item) => sum + item.totalCost);
    final totalProfit = totalSales - totalCost;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              _SummaryCard(
                title: 'إجمالي المبيعات',
                value: totalSales,
                color: Colors.blue,
              ),
              const SizedBox(width: 16),
              _SummaryCard(
                title: 'إجمالي التكلفة',
                value: totalCost,
                color: Colors.orange,
              ),
              const SizedBox(width: 16),
              // B11 REP-1 (spec 149): totalProfit here is a category-level
              // sales-minus-cost figure (no operating expenses attributed
              // per category) — not the company's GL-sourced net profit.
              // A per-category "net profit" has no GL equivalent to route
              // to (getIncomeStatement is company/branch/cost-center
              // scoped, not by product category), so this is relabel-only.
              // True net profit lives on the dashboard/financial statements.
              _SummaryCard(
                title: 'مجمل ربح المبيعات',
                value: totalProfit,
                color: Colors.green,
              ),
            ],
          ),
        ),
        Expanded(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('التصنيف')),
                  DataColumn(label: Text('المبيعات'), numeric: true),
                  DataColumn(label: Text('التكلفة'), numeric: true),
                  DataColumn(label: Text('الربح'), numeric: true),
                  DataColumn(label: Text('الهامش %'), numeric: true),
                ],
                rows: data.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(Text(
                        item.categoryName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      )),
                      DataCell(Text(_currencyFormat.format(item.totalSales))),
                      DataCell(Text(_currencyFormat.format(item.totalCost))),
                      DataCell(Text(
                        _currencyFormat.format(item.profit),
                        style: TextStyle(
                          color: item.profit >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      )),
                      DataCell(Text('${item.margin.toStringAsFixed(1)}%')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _exportToExcel() async {
    if (_data == null || _data!.isEmpty) {
      AppToast.show(context, 'لا توجد بيانات للتصدير', type: ToastType.error);
      return;
    }
    final service = ref.read(excelServiceProvider);
    final path = await service.exportReport(
      title: 'تقرير أرباح التصنيفات',
      headers: [
        'التصنيف',
        'المبيعات',
        'التكلفة',
        'الربح',
        'الهامش %',
      ],
      rows: _data!.map<List<dynamic>>((item) => [
        item.categoryName,
        item.totalSales,
        item.totalCost,
        item.profit,
        '${item.margin.toStringAsFixed(1)}%',
      ]).toList(),
    );
    if (path != null && mounted) {
      AppToast.show(context, 'تم تصدير التقرير بنجاح: \$path', type: ToastType.success);
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportExport(user?.id ?? 0, user?.displayName ?? 'مجهول', 'أرباح التصنيفات', 'Excel');
      } catch (_) {}
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              intl.NumberFormat.currency(
                symbol: '',
                decimalDigits: AppConstants.decimalPlaces,
              ).format(value),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}