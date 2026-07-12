// ignore_for_file: avoid_dynamic_calls
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
import '../../../../../../core/constants/app_constants.dart';
import '../../widgets/branch_warehouse_filter.dart';
import '../../widgets/report_components.dart' show DateRangeFilter;
import '../../widgets/report_filter_bar.dart';

class TopProductsReportScreen extends ConsumerStatefulWidget {
  const TopProductsReportScreen({super.key});

  @override
  ConsumerState<TopProductsReportScreen> createState() =>
      _TopProductsReportScreenState();
}

class _TopProductsReportScreenState
    extends ConsumerState<TopProductsReportScreen> {
  // Spec 065: defaults are full-day-inclusive (D3-006).
  DateTime _fromDate = DateRangeFilter.normalizeStart(
      DateTime.now().subtract(const Duration(days: 30)));
  DateTime _toDate = DateRangeFilter.normalizeEnd(DateTime.now());
  bool _orderByValue = true;
  final int _limit = 10;
  final _currencyFormat = intl.NumberFormat.currency(
    symbol: '',
    decimalDigits: AppConstants.decimalPlaces,
  );
  bool _isLoading = false;
  List<TopProductRow>? _data;
  int? _selectedRegionId; // Feature 017
  int? _selectedBranchId;
  int? _selectedWarehouseId;
  Set<int>? _branchWarehouseIds;
  Set<int>? _regionWarehouseIds;

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
        ref.read(activityLoggerProvider).logReportView(user?.id ?? 0, user?.displayName ?? 'مجهول', 'الأصناف الأكثر مبيعاً');
      } catch (_) {}
      _loadData();
    });
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
      // Feature 017 — region branch added to the warehouseIds resolution.
      List<int>? warehouseIds;
      if (_selectedWarehouseId != null) {
        warehouseIds = [_selectedWarehouseId!];
      } else if (_branchWarehouseIds != null) {
        warehouseIds = _branchWarehouseIds!.toList();
      } else if (_regionWarehouseIds != null) {
        warehouseIds = _regionWarehouseIds!.toList();
      }
      final data = await repo.getTopProductsReport(
        from: _fromDate,
        to: _toDate,
        limit: _limit,
        orderByValue: _orderByValue,
        warehouseIds: warehouseIds,
        allowedBranchIds: _allowedBranchIds,
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
        title: const Text('الأصناف الأكثر مبيعاً'),
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
          // Spec 076: unified two-row filter bar.
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
              ToggleButtons(
                isSelected: [_orderByValue, !_orderByValue],
                onPressed: (index) {
                  setState(() {
                    _orderByValue = index == 0;
                  });
                  _loadData();
                },
                borderRadius: BorderRadius.circular(8),
                constraints: const BoxConstraints(
                  minWidth: 100,
                  minHeight: 40,
                ),
                children: const [Text('حسب القيمة'), Text('حسب الكمية')],
              ),
            ],
          ),
          const Divider(height: 1),

          // Report List
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
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _data!.length,
                        itemBuilder: (context, index) {
                          final item = _data![index];
                          final rank = index + 1;
                          final value = item.totalValue;
                          final qty = item.totalQty;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: rank <= 3
                                    ? Colors.amber
                                    : Colors.grey.withValues(alpha: 0.1),
                                child: Text(
                                  '$rank',
                                  style: TextStyle(
                                    color: rank <= 3 ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                item.name.isEmpty ? 'منتج غير معروف' : item.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'الكمية المباعة: ${qty.toStringAsFixed(0)}',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${_currencyFormat.format(value)} ${AppConstants.currencySymbolEn}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const Text(
                                    'إجمالي القيمة',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToExcel() async {
    if (_data == null || _data!.isEmpty) {
      AppToast.show(context, 'لا توجد بيانات للتصدير', type: ToastType.error);
      return;
    }
    final service = ref.read(excelServiceProvider);
    final path = await service.exportReport(
      title: 'الأصناف الأكثر مبيعاً',
      headers: [
        'الترتيب',
        'اسم المنتج',
        'الكمية المباعة',
        'إجمالي القيمة',
      ],
      rows: _data!.asMap().entries.map<List<dynamic>>((entry) {
        final item = entry.value;
        return [
          entry.key + 1,
          item.name.isEmpty ? 'منتج غير معروف' : item.name,
          item.totalQty.toStringAsFixed(0),
          item.totalValue,
        ];
      }).toList(),
    );
    if (path != null && mounted) {
      AppToast.show(context, 'تم تصدير التقرير بنجاح: \$path', type: ToastType.success);
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportExport(user?.id ?? 0, user?.displayName ?? 'مجهول', 'الأصناف الأكثر مبيعاً', 'Excel');
      } catch (_) {}
    }
  }
}