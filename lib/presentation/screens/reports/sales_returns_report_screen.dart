// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/report_components.dart';
import '../../widgets/report_filter_bar.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/branch_warehouse_filter.dart';
import 'report_export_guard.dart';

class SalesReturnsReportScreen extends ConsumerStatefulWidget {
  const SalesReturnsReportScreen({super.key});

  @override
  ConsumerState<SalesReturnsReportScreen> createState() => _SalesReturnsReportScreenState();
}

class _SalesReturnsReportScreenState extends ConsumerState<SalesReturnsReportScreen> {
  // Spec 065: default range is full-day-inclusive [00:00, 23:59:59.999] (D3-006).
  DateTimeRange _dateRange = DateRangeFilter.normalizeRange(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
    DateTime.now(),
  );

  bool _isLoading = false;
  List<SalesInvoiceData> _returns = [];
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);
  Map<int, String> _userNames = {};
  int? _selectedRegionId; // Feature 017
  int? _selectedBranchId;
  int? _selectedWarehouseId;
  Set<int>? _branchWarehouseIds;
  Set<int>? _regionWarehouseIds;

  // Spec 151 Track-3: the logged-in user's branch authorization scope — an
  // AUTH CAP distinct from the user-chosen warehouse/branch/region filter
  // above. null = full access (admin/financial-manager/mirror/userId=1) → no
  // restriction. Resolved in BOTH build() and _loadData() (mirrors
  // sales_report_screen) so no imperative fetch can race ahead of the scope.
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
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Spec 151 Track-3: resolve the auth-level branch scope BEFORE the query
      // runs, on every call (closes the race where the initState microtask
      // could otherwise fetch unrestricted).
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final returnsRepo = ref.read(returnsRepositoryProvider);
      final reportingRepo = ref.read(reportingRepositoryProvider);

      final returns = await returnsRepo.getSalesReturnHistory(
        fromDate: _dateRange.start,
        toDate: _dateRange.end,
        allowedBranchIds: _allowedBranchIds,
      );

      // Load user names
      final users = await reportingRepo.watchAllUsers().first;
      final userMap = <int, String>{};
      for (final u in users) {
        userMap[u.user.id] = u.user.displayName;
      }

      setState(() {
        var filtered = returns;
        // Feature 017 — scope cascade: warehouse > branch > region.
        if (_selectedWarehouseId != null) {
          filtered = filtered.where((r) => r.warehouseId == _selectedWarehouseId).toList();
        } else if (_branchWarehouseIds != null) {
          filtered = filtered.where((r) => _branchWarehouseIds!.contains(r.warehouseId)).toList();
        } else if (_regionWarehouseIds != null) {
          filtered = filtered.where((r) => _regionWarehouseIds!.contains(r.warehouseId)).toList();
        }
        _returns = filtered;
        _userNames = userMap;
      });
      
      // Log report view
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(
          user?.id ?? 0, 
          user?.displayName ?? 'مجهول', 
          'تقرير مردودات المبيعات'
        );
      } catch (_) {}
      
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في تحميل البيانات: $e', type: ToastType.error);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Spec 151 Track-3: resolve the auth-level branch scope BEFORE the report
    // renders. The report MUST NOT render (even a flash) while the scope is
    // unknown — a restricted user briefly seeing an unscoped report is itself
    // the leak this fix closes. Mirrors sales_report_screen.
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
          body: Center(child: Text('تعذر تحديد صلاحيات الفرع: ${scopeAsync.error}')),
        ),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تقرير مردودات المبيعات'),
          actions: [
            buildReportExportAction(onExport: _returns.isEmpty ? null : _exportToExcel),
            buildReportPrintAsExportAction(onExport: _returns.isEmpty ? null : _printReport),
            IconButton(
              icon: const Icon(PhosphorIconsBold.calendar),
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  initialDateRange: _dateRange,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() => _dateRange = picked);
                  _loadData();
                }
              },
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              onPressed: _loadData,
            ),
          ],
        ),
        body: Column(
          children: [
            // Spec 076: unified two-row filter bar.
            ReportFilterBar(
              selectedRange: _dateRange,
              onRangeChanged: (start, end) {
                setState(
                  () => _dateRange = DateTimeRange(start: start, end: end),
                );
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
              ],
            ),
            Expanded(
              child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Summary Cards
                        Row(
                          children: [
                            Expanded(
                              child: ReportKpiCard(
                                title: 'إجمالي المردودات',
                                value: '${_currencyFormat.format(_returns.fold(0.0, (sum, item) => sum + item.total.abs()))} ${AppConstants.currencySymbolEn}',
                                icon: PhosphorIconsBold.arrowUUpLeft,
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ReportKpiCard(
                                title: 'عدد المستندات',
                                value: _returns.length.toString(),
                                icon: PhosphorIconsBold.hash,
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Table
                        Expanded(
                          child: Card(
                            child: _returns.isEmpty
                                ? const Center(child: Text('لا توجد مردودات في هذه الفترة'))
                                : SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SingleChildScrollView(
                                      child: DataTable(
                                        columns: const [
                                          DataColumn(label: Text('رقم الفاتورة')),
                                          DataColumn(label: Text('التاريخ')),
                                          DataColumn(label: Text('المستخدم')),
                                          DataColumn(label: Text('المبلغ')),
                                          DataColumn(label: Text('الحالة')),
                                        ],
                                        rows: _returns.map((r) {
                                          return DataRow(
                                            cells: [
                                              DataCell(Text(r.invoiceNumber)),
                                              DataCell(Text(_dateFormat.format(r.invoiceDate))),
                                              DataCell(Text(_userNames[r.userId] ?? 'مستخدم #${r.userId}')),
                                              DataCell(Text(_currencyFormat.format(r.total.abs()))),
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.error.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text('مرتجع', style: TextStyle(color: AppColors.error, fontSize: 12)),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportToExcel() async {
    if (_returns.isEmpty) return;
    try {
      final service = ref.read(excelServiceProvider);
      final path = await service.exportReport(
        title: 'تقرير مردودات المبيعات',
        headers: ['رقم الفاتورة', 'التاريخ', 'المستخدم', 'المبلغ'],
        rows: _returns.map<List<dynamic>>((r) => [
          r.invoiceNumber,
          _dateFormat.format(r.invoiceDate),
          _userNames[r.userId] ?? 'مستخدم',
          r.total.abs(),
        ]).toList(),
      );
      if (path != null && mounted) {
        AppToast.show(context, 'تم تصدير التقرير بنجاح', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في التصدير: $e', type: ToastType.error);
    }
  }

  Future<void> _printReport() async {
    // Use Excel export as print for now (same pattern as shifts_report)
    await _exportToExcel();
  }
}