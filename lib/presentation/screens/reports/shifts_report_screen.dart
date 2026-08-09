// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/report_components.dart';
import '../../widgets/report_filter_bar.dart';
import '../../../../../../core/constants/app_constants.dart';
import '../../widgets/branch_warehouse_filter.dart';
import 'report_export_guard.dart';

class ShiftsReportScreen extends ConsumerStatefulWidget {
  const ShiftsReportScreen({super.key});

  @override
  ConsumerState<ShiftsReportScreen> createState() => _ShiftsReportScreenState();
}

class _ShiftsReportScreenState extends ConsumerState<ShiftsReportScreen> {
  // Spec 065: default range is full-day-inclusive [00:00, 23:59:59.999] (D3-006).
  DateTimeRange _dateRange = DateRangeFilter.normalizeRange(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
    DateTime.now(),
  );

  bool _isLoading = false;
  List<ShiftReportDto> _shifts = [];
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);
  int? _selectedUserId;
  // 072 (D3-004 + D3-005): cost-center and safe dropdowns dropped — the
  // Shifts table carries neither field, so the controls were silent
  // no-ops. Re-introducing them needs a "shifts that touched
  // safe/cost-center via safe_transactions" sub-query (own future spec).
  List<UserWithRole> _allUsers = [];
  int? _selectedRegionId; // Feature 017
  int? _selectedBranchId;
  int? _selectedWarehouseId;
  Set<int>? _regionBranchIds; // resolved when a region is picked

  // Spec 151 Track-3: the logged-in user's branch authorization scope — an
  // AUTH CAP distinct from the user-chosen branch/region filter above. null =
  // full access (admin/financial-manager/mirror/userId=1). Resolved in BOTH
  // build() and _loadData() so no imperative fetch races ahead of the scope.
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
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير الورديات');
      } catch (_) {}
    });
  }

  // 072: _loadFilters removed — its only consumers were the deleted
  // cost-center + safe dropdowns. Active-branch resolution is handled
  // inline in initState (Feature 058 path, lines above).

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Spec 151 Track-3: resolve the auth-level branch scope BEFORE the query
      // runs, on every call (closes the initState-microtask race).
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final repo = ref.read(reportingRepositoryProvider);

      // Load user names for filter
      final users = await repo.watchAllUsers().first;

      // Fetch shifts. Spec 151 Track-3: the auth cap is applied in SQL so the
      // `limit: 100` page is already branch-scoped (fixes the prior bug where
      // the page was fetched across ALL branches then filtered client-side).
      final shifts = await repo.getShiftsReportPaginated(
        startDate: _dateRange.start,
        endDate: _dateRange.end,
        userId: _selectedUserId,
        limit: 100, // Load top 100 for now
        allowedBranchIds: _allowedBranchIds,
      );

      // Feature 017 — branch / region scope filter (client-side because the
      // DAO query doesn't take branchId; shifts.branchId is on the row).
      var filtered = shifts;
      if (_selectedBranchId != null) {
        filtered = filtered.where((s) => s.branchId == _selectedBranchId).toList();
      } else if (_regionBranchIds != null && _regionBranchIds!.isNotEmpty) {
        filtered = filtered
            .where((s) => s.branchId != null && _regionBranchIds!.contains(s.branchId))
            .toList();
      }

      setState(() {
        _shifts = filtered;
        _allUsers = users;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Spec 151 Track-3: resolve the auth-level branch scope BEFORE the report
    // renders. The report MUST NOT render (even a flash) while the scope is
    // unknown — a restricted user briefly seeing an unscoped report is itself
    // the leak this fix closes.
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('تقرير الورديات المطول'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            buildReportExportAction(onExport: _exportToExcel),
            buildReportPrintAsExportAction(onExport: _printReport),
            const SizedBox(width: 8),
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
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedUserId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المستخدم / الكاشير',
                      isDense: true,
                      prefixIcon: Icon(PhosphorIconsBold.user, size: 16),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('الكل'),
                      ),
                      ..._allUsers.map(
                        (u) => DropdownMenuItem<int?>(
                          value: u.user.id,
                          child: Text(
                            u.user.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedUserId = v);
                      _loadData();
                    },
                  ),
                ),
                // 072 (D3-004 + D3-005): cost-center + safe dropdowns
                // removed — the Shifts table carries neither field, so the
                // controls were silent no-ops. Reintroducing them needs a
                // "shifts that touched safe/cost-center via safe_transactions"
                // sub-query (own future spec).
                BranchWarehouseFilterBar(
                  selectedRegionId: _selectedRegionId,
                  selectedBranchId: _selectedBranchId,
                  selectedWarehouseId: _selectedWarehouseId,
                  onRegionChanged: (v) async {
                    _selectedRegionId = v;
                    _selectedBranchId = null;
                    _selectedWarehouseId = null;
                    if (v != null) {
                      // Spec 079b b142 hotfix: call DAO directly. The
                      // `regionBranchesProvider(v).future` path was throwing
                      // a "disposed during loading" error in field smoke,
                      // leaving `_regionBranchIds` null and silently
                      // disabling the client-side filter on shifts.
                      final db = ref.read(databaseProvider);
                      final regionBranches = await db.getBranchesByRegion(v);
                      _regionBranchIds = regionBranches.map((b) => b.id).toSet();
                      // Spec 079b (B2): empty branch set means the region
                      // has no branches assigned — common after a region
                      // is created without wiring branches yet. Without
                      // this signal the operator just sees an empty
                      // shifts table and can't tell why.
                      if (_regionBranchIds!.isEmpty) {
                        unawaited(DiagnosticLogger.log(
                          'FILTER-WARN',
                          'Region $v selected on shifts report but no '
                          'branches linked. Check that branches in this '
                          'region have a regionId set.',
                        ));
                      }
                    } else {
                      _regionBranchIds = null;
                    }
                    _loadData();
                  },
                  onBranchChanged: (v) {
                    setState(() {
                      _selectedBranchId = v;
                      _selectedWarehouseId = null;
                    });
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
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: ShimmerLoading.list(itemCount: 6),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'سجل الورديات',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: AppColors.border),
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  Theme.of(context).cardColor,
                                ),
                                columns: const [
                                  DataColumn(label: Text('# الوردية')),
                                  DataColumn(label: Text('المستخدم')),
                                  DataColumn(label: Text('بداية الشفت')),
                                  DataColumn(label: Text('نهاية الشفت')),
                                  DataColumn(label: Text('رصيد الإفتتاح')),
                                  DataColumn(
                                    label: Text('نقدي النظام (متوقع)'),
                                  ),
                                  DataColumn(label: Text('نقدي فعلي (مُدخل)')),
                                  DataColumn(
                                    label: Text('الفرق (العجز/الزيادة)'),
                                  ),
                                  DataColumn(label: Text('الحالة')),
                                ],
                                rows: _shifts.map((s) {
                                  final varColor = s.variance == null
                                      ? null
                                      : (s.variance!.abs() < 0.001
                                            ? AppColors.success
                                            : (s.variance! < 0
                                                  ? AppColors.error
                                                  : AppColors.warning));
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        InkWell(
                                          onTap: () => _viewShiftDetails(s),
                                          child: Text(
                                            s.id.toString(),
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(s.userName)),
                                      DataCell(
                                        Text(_dateFormat.format(s.startTime)),
                                      ),
                                      DataCell(
                                        Text(
                                          s.endTime != null
                                              ? _dateFormat.format(s.endTime!)
                                              : '---',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          _currencyFormat.format(
                                            s.openingBalance,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          s.expectedCash != null
                                              ? _currencyFormat.format(
                                                  s.expectedCash!,
                                                )
                                              : '---',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          s.actualCash != null
                                              ? _currencyFormat.format(
                                                  s.actualCash!,
                                                )
                                              : '---',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          s.variance != null
                                              ? _currencyFormat.format(
                                                  s.variance!,
                                                )
                                              : '---',
                                          style: TextStyle(
                                            color: varColor,
                                            fontWeight:
                                                s.variance != null &&
                                                    s.variance!.abs() > 0.001
                                                ? FontWeight.bold
                                                : null,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: s.status == 'closed'
                                                ? AppColors.success.withValues(
                                                    alpha: 0.1,
                                                  )
                                                : AppColors.warning.withValues(
                                                    alpha: 0.1,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            s.status == 'closed'
                                                ? 'مغلق'
                                                : 'مفتوح',
                                            style: TextStyle(
                                              color: s.status == 'closed'
                                                  ? AppColors.success
                                                  : AppColors.warning,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
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

  void _viewShiftDetails(ShiftReportDto shift) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text('تفاصيل الوردية #${shift.id}'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الكاشير: ${shift.userName}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text('البداية: ${_dateFormat.format(shift.startTime)}'),
                if (shift.endTime != null)
                  Text('النهاية: ${_dateFormat.format(shift.endTime!)}'),
                const Divider(),
                if (shift.status == 'closed') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('النقدي المتوقع (نظام):'),
                      Text(
                        '${_currencyFormat.format(shift.expectedCash ?? 0)} ${AppConstants.currencySymbolEn}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('النقدي الفعلي (مُدخل):'),
                      Text(
                        '${_currencyFormat.format(shift.actualCash ?? 0)} ${AppConstants.currencySymbolEn}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الفرق:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_currencyFormat.format(shift.variance ?? 0)} ${AppConstants.currencySymbolEn}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: shift.variance == null
                              ? Colors.black
                              : (shift.variance!.abs() < 0.001
                                    ? AppColors.success
                                    : (shift.variance! < 0
                                          ? AppColors.error
                                          : AppColors.warning)),
                        ),
                      ),
                    ],
                  ),
                  if (shift.notes != null && shift.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'الملاحظات / تفاصيل بطاقات الدفع:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(shift.notes!),
                  ],
                ] else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'الوردية ما زالت مفتوحة',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportToExcel() async {
    if (_shifts.isEmpty) {
      AppToast.show(context, 'لا توجد بيانات للتصدير', type: ToastType.error);
      return;
    }
    final service = ref.read(excelServiceProvider);
    final path = await service.exportReport(
      periodFrom: _dateRange.start,
      periodTo: _dateRange.end,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
      title: 'تقرير الورديات',
      headers: [
        '# الوردية',
        'المستخدم',
        'بداية الشفت',
        'نهاية الشفت',
        'رصيد الإفتتاح',
        'نقدي متوقع',
        'نقدي فعلي',
        'الفرق',
        'الحالة',
      ],
      rows: _shifts.map<List<dynamic>>((s) => [
        s.id,
        s.userName,
        _dateFormat.format(s.startTime),
        s.endTime != null ? _dateFormat.format(s.endTime!) : '---',
        s.openingBalance,
        s.expectedCash ?? 0,
        s.actualCash ?? 0,
        s.variance ?? 0,
        s.status == 'closed' ? 'مغلق' : 'مفتوح',
      ]).toList(),
    );
    if (path != null && mounted) {
      AppToast.show(context, 'تم تصدير التقرير بنجاح: \$path', type: ToastType.success);
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportExport(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير الورديات', 'Excel');
      } catch (_) {}
    }
  }

  Future<void> _printReport() async {
    if (_shifts.isEmpty) {
      AppToast.show(context, 'لا توجد بيانات للطباعة', type: ToastType.error);
      return;
    }
    // Use the same Excel export as a workaround for print — the user can open and print the file
    await _exportToExcel();
  }
}