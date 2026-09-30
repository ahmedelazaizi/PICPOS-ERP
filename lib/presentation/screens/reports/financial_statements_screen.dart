import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/design_system/typography.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import 'report_export_guard.dart';

import 'package:intl/intl.dart' hide TextDirection;

import '../../../data/providers/providers.dart';
import '../../../data/providers/manufacturing_providers.dart';
import '../../../services/invoice_generator.dart';
import '../../../services/network_service.dart';
import '../../../data/database/sync_interceptor.dart';
import '../../../services/sync/sync_worker.dart';
import '../../../../../../core/constants/app_constants.dart';
import '../../widgets/report_components.dart' show DateRangeFilter;
import '../../../domain/entities/accounting_entities.dart' show BranchCostCenterRepairReport;

class FinancialStatementsScreen extends ConsumerStatefulWidget {
  /// Optional tab to open on startup. 5 = مطابقة الترحيل (used by sync badge).
  final int initialTabIndex;
  const FinancialStatementsScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<FinancialStatementsScreen> createState() =>
      _FinancialStatementsScreenState();
}

class _FinancialStatementsScreenState
    extends ConsumerState<FinancialStatementsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Spec 065: defaults are full-day-inclusive — month-day-1 (already at 00:00)
  // and end-of-today at 23:59:59.999 (D3-006).
  DateTime _fromDate = DateRangeFilter.normalizeStart(
      DateTime(DateTime.now().year, DateTime.now().month, 1));
  DateTime _toDate = DateRangeFilter.normalizeEnd(DateTime.now());
  int _refreshKey = 0;
  int? _selectedCostCenterId; // null = all cost centers
  int? _selectedRegionId; // null = all regions
  int? _selectedBranchId; // null = all branches
  bool _showReceivables = true; // toggle for aged receivables vs payables

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  // FIL-2 (spec 149 B12): the logged-in user's branch authorization scope.
  // null = full access (admin/financial-manager/mirror) → no restriction.
  // Populated at the top of build() from branchScopeProvider and read by
  // every report call-site (export/print/render) below so a restricted
  // user can never pull another branch's financial data through this
  // screen, regardless of what they pick in the branch dropdown.
  Set<int>? _allowedBranchIds;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 5),
    );
    Future.microtask(() async {
      // Feature 058: seed _selectedBranchId from the device's active branch
      // so the FIRST tab fetch (driven by the build path's repo calls) sees
      // the active-branch filter (FR-001 + FR-002). _refreshKey is bumped so
      // any FutureBuilders keyed by it pick up the new value.
      if (_selectedBranchId == null) {
        final activeBranchId = await ref.read(activeBranchIdProvider.future);
        if (!mounted) return;
        if (activeBranchId != null) {
          setState(() {
            _selectedBranchId = activeBranchId;
            _refreshKey++;
          });
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

  @override
  Widget build(BuildContext context) {
    // FIL-2 (spec 149 B12): resolve the auth-level branch scope BEFORE any
    // report query runs. Reports MUST NOT render (even a flash) while the
    // scope is unknown — a restricted user briefly seeing an unscoped
    // report is itself the leak this fix closes.
    final scopeAsync = ref.watch(branchScopeProvider);
    if (scopeAsync.isLoading) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (scopeAsync.hasError) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(child: Text(tr('تعذر تحديد صلاحيات الفرع: {p0}', {'p0': scopeAsync.error}))),
        ),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:  Text(tr('القوائم المالية والتقارير الختامية')),
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs:  [
              Tab(text: tr('ميزان المراجعة'), icon: const Icon(PhosphorIconsBold.scales)),
              Tab(
                text: tr('قائمة الدخل (P&L)'),
                icon: const Icon(PhosphorIconsBold.chartLineUp),
              ),
              Tab(
                text: tr('الميزانية العمومية'),
                icon: const Icon(PhosphorIconsBold.bank),
              ),
              Tab(
                text: tr('التدفقات النقدية'),
                icon: const Icon(PhosphorIconsBold.currencyCircleDollar),
              ),
              Tab(
                text: tr('تقادم الذمم'),
                icon: const Icon(PhosphorIconsBold.hourglass),
              ),
              Tab(
                text: tr('مطابقة الترحيل'),
                icon: const Icon(PhosphorIconsBold.checkSquareOffset),
              ),
            ],
          ),
          actions: [
            // Region Filter
            Consumer(
              builder: (context, ref, _) {
                final regionsAsync = ref.watch(allRegionsProvider);
                return regionsAsync.when(
                  data: (regions) {
                    if (regions.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: regions.any((r) => r.id == _selectedRegionId) ? _selectedRegionId : null,
                          hint:  Text(tr('المنطقة'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          dropdownColor: AppColors.primary,
                          iconEnabledColor: Colors.white70,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: [
                             DropdownMenuItem<int?>(value: null, child: Text(tr('كل المناطق'))),
                            ...regions.map((r) => DropdownMenuItem<int?>(value: r.id, child: Text(r.name))),
                          ],
                          onChanged: (v) => setState(() { _selectedRegionId = v; _selectedBranchId = null; _refreshKey++; }),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                );
              },
            ),
            // Branch Filter (filtered by region when a region is selected)
            Consumer(
              builder: (context, ref, _) {
                final branchesAsync = _selectedRegionId != null
                    ? ref.watch(regionBranchesProvider(_selectedRegionId!))
                    : ref.watch(branchListProvider);
                return branchesAsync.when(
                  data: (branches) {
                    // FIL-2: defense-in-depth — a restricted user shouldn't
                    // even be offered other branches in the dropdown. The
                    // real enforcement is server-side (auth-scope filter on
                    // every report query above); this just keeps the UI
                    // honest. `scope` is the same BranchScope resolved at
                    // the top of build(). With auth-scope enforced, "كل
                    // الفروع" (null) now means "all MY branches", not the
                    // whole company.
                    final visibleBranches = scope.hasFullAccess
                        ? branches
                        : branches.where((b) => scope.allowedBranchIds!.contains(b.id)).toList();
                    if (visibleBranches.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: visibleBranches.any((b) => b.id == _selectedBranchId) ? _selectedBranchId : null,
                          hint:  Text(tr('الفرع'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          dropdownColor: AppColors.primary,
                          iconEnabledColor: Colors.white70,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: [
                             DropdownMenuItem<int?>(value: null, child: Text(tr('كل الفروع'))),
                            ...visibleBranches.map((b) => DropdownMenuItem<int?>(value: b.id, child: Text(trData(b.name)))),
                          ],
                          onChanged: (v) => setState(() { _selectedBranchId = v; _refreshKey++; }),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                );
              },
            ),
            // Cost Center Filter
            FutureBuilder<List<CostCenter>>(
              future: ref.read(accountingRepositoryProvider).getActiveCostCenters(),
              builder: (context, snap) {
                final centers = snap.data ?? [];
                if (centers.isEmpty) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedCostCenterId,
                      hint:  Text(tr('مركز التكلفة'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      dropdownColor: AppColors.primary,
                      iconEnabledColor: Colors.white70,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: [
                         DropdownMenuItem<int?>(value: null, child: Text(tr('الكل'))),
                        ...centers.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(trData(c.name)))),
                      ],
                      onChanged: (v) => setState(() { _selectedCostCenterId = v; _refreshKey++; }),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              onPressed: () => setState(() => _refreshKey++),
              tooltip: tr('تحديث البيانات'),
            ),
            buildReportExportAction(onExport: _exportToExcel),
            IconButton(
              icon: const Icon(PhosphorIconsBold.printer),
              onPressed: _printReport,
              tooltip: tr('طباعة/PDF'),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.calendar),
              onPressed: _selectDateRange,
            ),
            // Remediation Button (PIR Remediation)
            IconButton(
              icon: const Icon(PhosphorIconsBold.magicWand, color: Colors.orangeAccent),
              tooltip: tr('إصلاح فروقات التقارير والمراكز'),
              onPressed: () => _showRemediationDialog(),
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildTrialBalanceTab(),
            _buildIncomeStatementTab(),
            _buildBalanceSheetTab(),
            _buildCashFlowTab(),
            _buildAgingReportTab(),
            _buildReconciliationTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        // FIL-1: normalize to start-of-day / end-of-day so entries posted
        // after 00:00 on the selected end day are not dropped from the
        // Trial Balance / Income Statement / Balance Sheet (entry_date carries
        // real time-of-day; the picker returns midnight).
        _fromDate = DateRangeFilter.normalizeStart(picked.start);
        _toDate = DateRangeFilter.normalizeEnd(picked.end);
        _refreshKey++;
      });
    }
  }

  Future<void> _exportToExcel() async {
    final repo = ref.read(reportingRepositoryProvider);
    final service = ref.read(excelServiceProvider);

    try {
      switch (_tabController.index) {
        case 0: // Trial Balance
          final data = await repo.getTrialBalance(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: tr('ميزان المراجعة من {p0} إلى {p1}', {'p0': _fromDate.toString().split(' ')[0], 'p1': _toDate.toString().split(' ')[0]}),
            headers: [
              tr('كود الحساب'),
              tr('اسم الحساب'),
              tr('رصيد أول مدين'),
              tr('رصيد أول دائن'),
              tr('حركة الفترة مدين'),
              tr('حركة الفترة دائن'),
              tr('رصيد نهائي مدين'),
              tr('رصيد نهائي دائن'),
            ],
            rows: data
                .map<List<dynamic>>(
                  (row) => [
                    row['code'],
                    row['name'],
                    row['openingDebit'],
                    row['openingCredit'],
                    row['movementDebit'],
                    row['movementCredit'],
                    row['closingDebit'],
                    row['closingCredit'],
                  ],
                )
                .toList(),
          );
          break;
        case 1: // Income Statement
          final data = await repo.getIncomeStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          final List<List<dynamic>> rows = [];
          for (final item in (data['revenueDetails'] as List)) {
            rows.add([tr('إيراد'), item['name'], item['amount']]);
          }
          for (final item in (data['expenseDetails'] as List)) {
            rows.add([tr('مصروف'), item['name'], item['amount']]);
          }
          rows.add(['', tr('صافي الربح'), data['netProfit']]);
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: tr('قائمة الدخل'),
            headers: [tr('النوع'), tr('البيان'), tr('المبلغ')],
            rows: rows,
          );
          break;
        case 2: // Balance Sheet
          final data = await repo.getBalanceSheet(_toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          final List<List<dynamic>> rows = [];
          for (final item in (data['assetDetails'] as List)) {
            rows.add([tr('أصل'), item['name'], item['balance']]);
          }
          for (final item in (data['liabilityDetails'] as List)) {
            rows.add([tr('التزام'), item['name'], item['balance']]);
          }
          for (final item in (data['equityDetails'] as List)) {
            rows.add([tr('حقوق ملكية'), item['name'], item['balance']]);
          }
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: tr('الميزانية العمومية'),
            headers: [tr('النوع'), tr('البيان'), tr('الرصيد')],
            rows: rows,
          );
          break;
        case 3: // Cash Flow
          final data = await ref.read(accountingRepositoryProvider).getCashFlowStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          final op = data['operating'] as Map<String, dynamic>;
          final inv = data['investing'] as Map<String, dynamic>;
          final fin = data['financing'] as Map<String, dynamic>;
          final List<List<dynamic>> rows = [
            [tr('تشغيلي'), tr('إيرادات المبيعات النقدية'), op['salesCash']],
            [tr('تشغيلي'), tr('مدفوعات المشتريات'), op['purchasesCash']],
            [tr('تشغيلي'), tr('الرواتب'), op['salaries']],
            [tr('تشغيلي'), tr('المصاريف التشغيلية'), op['expenses']],
            [tr('تشغيلي'), tr('صافي النشاط التشغيلي'), op['net']],
            [tr('استثماري'), tr('شراء أصول'), inv['assetPurchases']],
            [tr('استثماري'), tr('بيع أصول'), inv['assetDisposals']],
            [tr('استثماري'), tr('صافي النشاط الاستثماري'), inv['net']],
            [tr('تمويلي'), tr('شيكات محصلة'), fin['checksCollected']],
            [tr('تمويلي'), tr('شيكات مصدرة'), fin['checksIssued']],
            [tr('تمويلي'), tr('صافي النشاط التمويلي'), fin['net']],
            ['', tr('الرصيد الافتتاحي'), data['openingBalance']],
            ['', tr('صافي التغير'), data['netChange']],
            ['', tr('الرصيد الختامي'), data['closingBalance']],
          ];
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: tr('قائمة التدفقات النقدية'),
            headers: [tr('النشاط'), tr('البيان'), tr('المبلغ')],
            rows: rows,
          );
          break;
        case 4: // Aged Receivables/Payables
          final accountingRepo = ref.read(accountingRepositoryProvider);
          final List<Map<String, dynamic>> agingData;
          final String title;
          if (_showReceivables) {
            agingData = await accountingRepo.getAgedReceivables(_toDate, costCenterId: _selectedCostCenterId, allowedBranchIds: _allowedBranchIds);
            title = tr('تقادم الذمم المدينة (العملاء)');
          } else {
            agingData = await accountingRepo.getAgedPayables(_toDate, costCenterId: _selectedCostCenterId, allowedBranchIds: _allowedBranchIds);
            title = tr('تقادم الذمم الدائنة (الموردين)');
          }
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: title,
            headers: [tr('الاسم'), tr('الإجمالي'), tr('0-30 يوم'), tr('31-60 يوم'), tr('61-90 يوم'), tr('+90 يوم')],
            rows: agingData.map<List<dynamic>>((r) => [
              r['name'], r['totalBalance'], r['current'],
              r['days31_60'], r['days61_90'], r['over90'],
            ]).toList(),
          );
          break;
      }

      if (mounted) {
        AppToast.show(
          context,
          tr('تم تصدير التقرير بنجاح'),
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ في التصدير: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  Future<void> _printReport() async {
    final repo = ref.read(reportingRepositoryProvider);

    try {
      switch (_tabController.index) {
        case 0: // Trial Balance
          final data = await repo.getTrialBalance(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await InvoiceGenerator.printFinancialStatement(
            title: tr('ميزان المراجعة'),
            data: data,
            statementType: 'trial_balance',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
        case 1: // Income Statement
          final data = await repo.getIncomeStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await InvoiceGenerator.printFinancialStatement(
            title: tr('قائمة الدخل'),
            data: [data],
            statementType: 'income_statement',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
        case 2: // Balance Sheet
          final data = await repo.getBalanceSheet(_toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await InvoiceGenerator.printFinancialStatement(
            title: tr('الميزانية العمومية'),
            data: [data],
            statementType: 'balance_sheet',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
        case 3: // Cash Flow
          final data = await ref.read(accountingRepositoryProvider).getCashFlowStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await InvoiceGenerator.printFinancialStatement(
            title: tr('قائمة التدفقات النقدية'),
            data: [data],
            statementType: 'cash_flow',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
        case 4: // Aged Receivables/Payables
          final accountingRepo = ref.read(accountingRepositoryProvider);
          final List<Map<String, dynamic>> agingData;
          final String title;
          if (_showReceivables) {
            agingData = await accountingRepo.getAgedReceivables(_toDate, costCenterId: _selectedCostCenterId, allowedBranchIds: _allowedBranchIds);
            title = tr('تقادم الذمم المدينة');
          } else {
            agingData = await accountingRepo.getAgedPayables(_toDate, costCenterId: _selectedCostCenterId, allowedBranchIds: _allowedBranchIds);
            title = tr('تقادم الذمم الدائنة');
          }
          await InvoiceGenerator.printFinancialStatement(
            title: title,
            data: agingData,
            statementType: 'aging_report',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ في الطباعة: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  Widget _buildTrialBalanceTab() {
    final repo = ref.read(reportingRepositoryProvider);
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('trial_${_refreshKey}_${_fromDate}_${_toDate}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: repo.getTrialBalance(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;

        return Column(
          children: [
            _buildReportHeader(
              tr('ميزان المراجعة من {p0} إلى {p1}', {'p0': _fromDate.toString().split(' ')[0], 'p1': _toDate.toString().split(' ')[0]}),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 16,
                    horizontalMargin: 12,
                    columns:  [
                      DataColumn(label: Text(tr('كود'), style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text(tr('اسم الحساب'), style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text(tr('رصيد أول\nمدين'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text(tr('رصيد أول\nدائن'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text(tr('حركة الفترة\nمدين'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text(tr('حركة الفترة\nدائن'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text(tr('رصيد نهائي\nمدين'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text(tr('رصيد نهائي\nدائن'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                    ],
                    rows: data.map((row) {
                      final isTotal = row['type'] == 'total';
                      final style = TextStyle(
                        fontWeight: isTotal ? FontWeight.w900 : FontWeight.normal,
                        fontFamily: AppTypography.mono,
                        fontSize: isTotal ? 13 : 12,
                      );
                      final nameStyle = TextStyle(
                        fontWeight: isTotal ? FontWeight.w900 : FontWeight.w500,
                        fontSize: isTotal ? 13 : 12,
                      );

                      String fmt(double v) => v == 0 ? '-' : v.toStringAsFixed(AppConstants.decimalPlaces);

                      return DataRow(
                        color: isTotal
                            ? WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08))
                            : null,
                        cells: [
                          DataCell(Text(row['code'] ?? '', style: style)),
                          DataCell(Text(
                            isTotal ? tr('الإجمالي') : trData(row['name'] as String?),
                            style: nameStyle,
                          )),
                          DataCell(Text(fmt(row['openingDebit'] as double), style: style)),
                          DataCell(Text(fmt(row['openingCredit'] as double), style: style)),
                          DataCell(Text(fmt(row['movementDebit'] as double), style: style)),
                          DataCell(Text(fmt(row['movementCredit'] as double), style: style)),
                          DataCell(Text(fmt(row['closingDebit'] as double), style: style)),
                          DataCell(Text(fmt(row['closingCredit'] as double), style: style)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIncomeStatementTab() {
    final repo = ref.read(reportingRepositoryProvider);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('income_${_refreshKey}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: repo.getIncomeStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;
        final netProfit = data['netProfit'] as double;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              _buildReportHeader(
                tr('قائمة الدخل للفترة من {p0} إلى {p1}', {'p0': _fromDate.toString().split(' ')[0], 'p1': _toDate.toString().split(' ')[0]}),
              ),
              // Revenue Section
              _buildSectionTitle(tr('الإيرادات والمبيعات')),
              ...(data['revenueDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['amount']),
              ),
              const Divider(thickness: 2),
              _buildReportLine(
                tr('إجمالي الإيرادات'),
                data['totalRevenue'],
                isBold: true,
              ),
              const SizedBox(height: 16),
              // COGS Section
              if ((data['totalCOGS'] as double) > 0) ...[
                _buildSectionTitle(tr('تكلفة البضاعة المباعة')),
                ...(data['cogsDetails'] as List? ?? []).map(
                  (d) => _buildReportLine(d['name'], d['amount']),
                ),
                const Divider(),
                _buildReportLine(
                  tr('إجمالي تكلفة البضاعة المباعة'),
                  data['totalCOGS'],
                  isBold: true,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _buildReportLine(
                    tr('مجمل الربح'),
                    data['grossProfit'],
                    isBold: true,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Operating & Other Expenses
              _buildSectionTitle(tr('المصاريف والتكاليف')),
              ...(data['expenseDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['amount']),
              ),
              const Divider(thickness: 2),
              _buildReportLine(
                tr('إجمالي المصاريف التشغيلية'),
                data['totalExpenses'] as double,
                isBold: true,
              ),
              const SizedBox(height: 8),
              // Operating Profit (before depreciation)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildReportLine(
                  tr('الربح التشغيلي (قبل الإهلاك)'),
                  data['operatingProfit'] as double,
                  isBold: true,
                ),
              ),
              const SizedBox(height: 16),
              // Item 10: Depreciation Section
              if ((data['totalDepreciation'] as double) > 0) ...[
                _buildSectionTitle(tr('الإهلاك والاستهلاك (IAS 16)')),
                ...(data['depreciationDetails'] as List).map(
                  (d) => _buildReportLine(d['name'], d['amount']),
                ),
                const Divider(),
                _buildReportLine(
                  tr('إجمالي مصاريف الإهلاك'),
                  data['totalDepreciation'] as double,
                  isBold: true,
                ),
                const SizedBox(height: 16),
              ],
              // البند 1 — «إيرادات/مصروفات أخرى» (غير تشغيلية). These were
              // computed but rendered NOWHERE, so the statement did not foot on
              // screen: the reader added Revenue − COGS − Expenses and got a
              // different number from the printed «صافي الربح». That is the
              // exact "can't reconcile by hand" complaint, so leaving them
              // hidden after re-classifying purchase discounts and cash
              // surpluses into this bucket would have made it worse.
              if ((data['otherIncome'] as double? ?? 0) != 0 ||
                  (data['otherExpense'] as double? ?? 0) != 0) ...[
                _buildSectionTitle(tr('إيرادات ومصروفات أخرى (غير تشغيلية)')),
                ...((data['otherIncomeDetails'] as List?) ?? const []).map(
                  (d) => _buildReportLine(d['name'], d['amount']),
                ),
                ...((data['otherExpenseDetails'] as List?) ?? const []).map(
                  (d) => _buildReportLine(d['name'], -(d['amount'] as num)),
                ),
                const Divider(),
                _buildReportLine(
                  tr('صافي الإيرادات الأخرى'),
                  (data['otherIncome'] as double? ?? 0) -
                      (data['otherExpense'] as double? ?? 0),
                  isBold: true,
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 16),
              // Net Profit
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: netProfit >= 0
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: netProfit >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
                child: _buildReportLine(
                  netProfit >= 0 ? tr('صافي الربح') : tr('صافي الخسارة'),
                  netProfit.abs(),
                  isBold: true,
                  large: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBalanceSheetTab() {
    final repo = ref.read(reportingRepositoryProvider);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('balance_${_refreshKey}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: repo.getBalanceSheet(_toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              _buildReportHeader(
                tr('الميزانية العمومية كما في {p0}', {'p0': _toDate.toString().split(' ')[0]}),
              ),
              _buildSectionTitle(tr('الأصول (Assets)')),
              ...(data['assetDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['balance']),
              ),
              const Divider(thickness: 2),
              _buildReportLine(
                tr('إجمالي الأصول'),
                data['totalAssets'],
                isBold: true,
              ),
              const SizedBox(height: 24),
              // ─── Liabilities Section (IAS 1.54) ───
              _buildSectionTitle(tr('الالتزامات (Liabilities)')),
              ...(data['liabilityDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['balance']),
              ),
              const Divider(),
              _buildReportLine(
                tr('إجمالي الالتزامات'),
                data['totalLiabilities'],
                isBold: true,
              ),
              const SizedBox(height: 16),
              // ─── Equity Section (IAS 1.54) ───
              _buildSectionTitle(tr('حقوق الملكية (Equity)')),
              ...(data['equityDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['balance']),
              ),
              const Divider(),
              _buildReportLine(
                tr('إجمالي حقوق الملكية'),
                data['totalEquity'],
                isBold: true,
              ),
              const SizedBox(height: 16),
              const Divider(thickness: 2),
              _buildReportLine(
                tr('إجمالي الالتزامات وحقوق الملكية'),
                data['totalLiabilities'] + data['totalEquity'],
                isBold: true,
              ),
              const SizedBox(height: 24),
              if (!data['isBalanced'])
                 Card(
                  color: AppColors.error,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      tr('تحذير: الميزانية غير متزنة! يرجى مراجعة القيود.'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCashFlowTab() {
    final accountingRepo = ref.read(accountingRepositoryProvider);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('cashflow_${_refreshKey}_${_fromDate}_${_toDate}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: accountingRepo.getCashFlowStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;
        final op = data['operating'] as Map<String, dynamic>;
        final inv = data['investing'] as Map<String, dynamic>;
        final fin = data['financing'] as Map<String, dynamic>;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              _buildReportHeader(
                tr('قائمة التدفقات النقدية — IAS 7\nمن {p0} إلى {p1}', {'p0': _fromDate.toString().split(' ')[0], 'p1': _toDate.toString().split(' ')[0]}),
              ),
              const SizedBox(height: 8),

              // ─── Opening Balance ───
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildReportLine(tr('الرصيد النقدي الافتتاحي'), data['openingBalance'] as double, isBold: true),
              ),
              const SizedBox(height: 16),

              // ─── Operating Activities (IAS 7.14) ───
              _buildSectionTitle(tr('أولاً: الأنشطة التشغيلية')),
              _buildReportLine(tr('إيرادات المبيعات النقدية'), (op['salesCash'] as num).toDouble()),
              _buildReportLine(tr('متحصلات أخرى من العملاء'), (op['receiptsFromCustomers'] as num).toDouble()),
              _buildReportLine(tr('مدفوعات المشتريات'), -(op['purchasesCash'] as num).toDouble()),
              _buildReportLine(tr('مدفوعات للموردين'), -(op['paymentsToSuppliers'] as num).toDouble()),
              _buildReportLine(tr('الرواتب والأجور'), -(op['salaries'] as num).toDouble()),
              _buildReportLine(tr('المصاريف التشغيلية'), -(op['expenses'] as num).toDouble()),
              const Divider(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: (op['net'] as num).toDouble() >= 0
                      ? AppColors.success.withValues(alpha: 0.06)
                      : AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildReportLine(tr('صافي التدفق التشغيلي'), (op['net'] as num).toDouble(), isBold: true),
              ),
              const SizedBox(height: 16),

              // ─── Investing Activities (IAS 7.16) ───
              _buildSectionTitle(tr('ثانياً: الأنشطة الاستثمارية')),
              _buildReportLine(tr('شراء أصول ثابتة'), -(inv['assetPurchases'] as num).toDouble()),
              _buildReportLine(tr('حصيلة بيع أصول'), (inv['assetDisposals'] as num).toDouble()),
              const Divider(),
              _buildReportLine(tr('صافي التدفق الاستثماري'), (inv['net'] as num).toDouble(), isBold: true),
              const SizedBox(height: 16),

              // ─── Financing Activities (IAS 7.17) ───
              _buildSectionTitle(tr('ثالثاً: الأنشطة التمويلية')),
              _buildReportLine(tr('شيكات محصلة'), (fin['checksCollected'] as num).toDouble()),
              _buildReportLine(tr('شيكات مصدرة'), -(fin['checksIssued'] as num).toDouble()),
              const Divider(),
              _buildReportLine(tr('صافي التدفق التمويلي'), (fin['net'] as num).toDouble(), isBold: true),
              const SizedBox(height: 24),

              // ─── Net Change & Closing ───
              const Divider(thickness: 2),
              _buildReportLine(tr('صافي التغير في النقدية'), (data['netChange'] as num).toDouble(), isBold: true),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary),
                ),
                child: _buildReportLine(
                  tr('الرصيد النقدي الختامي'),
                  (data['closingBalance'] as num).toDouble(),
                  isBold: true,
                  large: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAgingReportTab() {
    final accountingRepo = ref.read(accountingRepositoryProvider);
    final future = _showReceivables
        ? accountingRepo.getAgedReceivables(
            _toDate,
            costCenterId: _selectedCostCenterId,
            branchId: _selectedBranchId,
            regionId: _selectedRegionId,
            allowedBranchIds: _allowedBranchIds,
          )
        : accountingRepo.getAgedPayables(
            _toDate,
            costCenterId: _selectedCostCenterId,
            branchId: _selectedBranchId,
            regionId: _selectedRegionId,
            allowedBranchIds: _allowedBranchIds,
          );

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(
        'aging_${_refreshKey}_${_showReceivables}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}',
      ),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsBold.warning, size: 48, color: AppColors.error.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(tr('خطأ في تحميل البيانات'), style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(PhosphorIconsBold.arrowClockwise),
                  label:  Text(tr('إعادة المحاولة')),
                  onPressed: () => setState(() => _refreshKey++),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;
        final currFmt = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);

        return Column(
          children: [
            // Toggle between receivables and payables
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildReportHeader(
                    _showReceivables ? tr('تقادم الذمم المدينة (العملاء)') : tr('تقادم الذمم الدائنة (الموردين)'),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments:  [
                      ButtonSegment(value: true, label: Text(tr('العملاء')), icon: const Icon(PhosphorIconsBold.user, size: 16)),
                      ButtonSegment(value: false, label: Text(tr('الموردين')), icon: const Icon(PhosphorIconsBold.truck, size: 16)),
                    ],
                    selected: {_showReceivables},
                    onSelectionChanged: (v) => setState(() { _showReceivables = v.first; _refreshKey++; }),
                  ),
                ],
              ),
            ),
            if (data.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsBold.checkCircle, size: 64, color: AppColors.success.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text(
                        _showReceivables ? tr('لا توجد ذمم مدينة مستحقة') : tr('لا توجد ذمم دائنة مستحقة'),
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 20,
                      columns:  [
                        DataColumn(label: Text(tr('الطرف'), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text(tr('إجمالي الرصيد'), style: const TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                        DataColumn(label: Text(tr('0-30 يوم'), style: const TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                        DataColumn(label: Text(tr('31-60 يوم'), style: const TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                        DataColumn(label: Text(tr('61-90 يوم'), style: const TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                        DataColumn(label: Text(tr('+90 يوم'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)), numeric: true),
                      ],
                      rows: data.map((row) {
                        final over90 = (row['over90'] as num?)?.toDouble() ?? 0;
                        return DataRow(cells: [
                          DataCell(Text(row['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500))),
                          DataCell(Text(currFmt.format(row['totalBalance'] ?? 0), style: const TextStyle(fontFamily: AppTypography.mono, fontWeight: FontWeight.bold))),
                          DataCell(Text(currFmt.format(row['current'] ?? 0), style: const TextStyle(fontFamily: AppTypography.mono))),
                          DataCell(Text(currFmt.format(row['days31_60'] ?? 0), style: const TextStyle(fontFamily: AppTypography.mono))),
                          DataCell(Text(currFmt.format(row['days61_90'] ?? 0), style: const TextStyle(fontFamily: AppTypography.mono))),
                          DataCell(Text(
                            currFmt.format(over90),
                            style: TextStyle(
                              fontFamily: AppTypography.mono,
                              fontWeight: over90 > 0 ? FontWeight.bold : FontWeight.normal,
                              color: over90 > 0 ? AppColors.error : null,
                            ),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildReportHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildReportLine(
    String label,
    dynamic amount, {
    bool isBold = false,
    bool large = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            trData(label),
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: large ? 18 : 14,
            ),
          ),
          Text(
            '${(amount as double).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: large ? 18 : 14,
              fontFamily: AppTypography.mono,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tab 6: مطابقة الترحيل (Posting Reconciliation)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildReconciliationTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('reconciliation_${_refreshKey}_${_fromDate}_${_toDate}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: ref.read(accountingRepositoryProvider)
          .getPostingReconciliation(_fromDate, _toDate, branchId: _selectedBranchId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsBold.warning, size: 48, color: AppColors.error.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(tr('خطأ في تحميل البيانات'), style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Text('${snapshot.error}', style: const TextStyle(fontSize: 11, color: AppColors.error)),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(PhosphorIconsBold.arrowClockwise),
                  label:  Text(tr('إعادة المحاولة')),
                  onPressed: () => setState(() => _refreshKey++),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;
        if (data.isEmpty && !SyncInterceptor.isClientMode) {
          return  Center(child: Text(tr('لا توجد فواتير في هذه الفترة')));
        }

        // Summary stats
        final matched = data.where((d) => d['statusCode'] == 'matched').length;
        final missing = data.where((d) => d['statusCode'] == 'missing').length;
        final draft = data.where((d) => d['statusCode'] == 'draft').length;
        final mismatch = data.where((d) => d['statusCode'] == 'mismatch').length;
        final orphan = data.where((d) => d['statusCode'] == 'orphan').length;

        return Column(
          children: [
            // ── Sync Outbox Panel (Client mode only) ──────────────────────
            if (NetworkService.instance.isClient) // keep-isClient: outbox
              _buildSyncOutboxPanel(),
            // Summary Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _reconcileStat(tr('مطابق'), matched, Colors.green),
                  _reconcileStat(tr('غير مرحل'), missing, AppColors.error),
                  _reconcileStat(tr('مسودة'), draft, Colors.orange),
                  _reconcileStat(tr('فرق قيمة'), mismatch, Colors.purple),
                  _reconcileStat(tr('قيد يتيم'), orphan, Colors.blueGrey),
                ],
              ),
            ),
            // Data Table
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 20,
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    dataTextStyle: const TextStyle(fontSize: 11),
                    columns:  [
                      DataColumn(label: Text(tr('النوع'))),
                      DataColumn(label: Text(tr('رقم الفاتورة'))),
                      DataColumn(label: Text(tr('التاريخ'))),
                      DataColumn(label: Text(tr('المبلغ')), numeric: true),
                      DataColumn(label: Text(tr('رقم القيد'))),
                      DataColumn(label: Text(tr('مدين قيد')), numeric: true),
                      DataColumn(label: Text(tr('دائن قيد')), numeric: true),
                      DataColumn(label: Text(tr('الحالة'))),
                    ],
                    rows: data.map((row) {
                      final statusCode = row['statusCode'] as String;
                      final statusColor = switch (statusCode) {
                        'matched' => Colors.green,
                        'missing' => AppColors.error,
                        'draft' => Colors.orange,
                        'mismatch' => Colors.purple,
                        'orphan' => Colors.blueGrey,
                        _ => Colors.grey,
                      };
                      final dateVal = row['invoiceDate'];
                      String dateStr;
                      if (dateVal is DateTime) {
                        dateStr = DateFormat('yyyy-MM-dd').format(dateVal);
                      } else if (dateVal is String) {
                        dateStr = dateVal.length > 10 ? dateVal.substring(0, 10) : dateVal;
                      } else {
                        dateStr = '-';
                      }
                      return DataRow(
                        color: WidgetStateProperty.resolveWith((states) {
                          if (statusCode == 'missing') return AppColors.error.withValues(alpha: 0.08);
                          if (statusCode == 'orphan') return Colors.blue.withValues(alpha: 0.08);
                          if (statusCode == 'mismatch') return Colors.purple.withValues(alpha: 0.08);
                          return null;
                        }),
                        cells: [
                          DataCell(Text(row['source'] as String)),
                          DataCell(Text('${row['invoiceNumber']}')),
                          DataCell(Text(dateStr)),
                          DataCell(Text(NumberFormat('#,##0.00').format(row['invoiceTotal'] ?? 0))),
                          DataCell(Text(row['jeNumber']?.toString() ?? '-')),
                          DataCell(Text(NumberFormat('#,##0.00').format(row['jeDebit'] ?? 0))),
                          DataCell(Text(NumberFormat('#,##0.00').format(row['jeCredit'] ?? 0))),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              row['status'] as String,
                              style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Sync Outbox Panel — embedded in مطابقة الترحيل, visible in client mode only
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSyncOutboxPanel() {
    final syncRepo = ref.watch(syncRepositoryProvider);
    final syncState = ref.watch(syncWorkerProvider);
    return StreamBuilder<List<SyncOutboxItem>>(
      stream: syncRepo.watchPendingItems(),
      builder: (context, snapshot) {
        final allItems = snapshot.data ?? [];
        final pending = allItems.where((i) => i.status == 'pending').toList();
        final failed = allItems.where((i) => i.status == 'dead_letter' || i.status == 'failed').toList();
        final total = pending.length + failed.length;
        if (total == 0 && !syncState.isSyncing) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: failed.isNotEmpty
                ? AppColors.error.withValues(alpha: 0.05)
                : AppColors.warning.withValues(alpha: 0.05),
            border: Border.all(
              color: failed.isNotEmpty
                  ? AppColors.error.withValues(alpha: 0.3)
                  : AppColors.warning.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: failed.isNotEmpty,
              leading: Icon(
                failed.isNotEmpty
                    ? PhosphorIconsBold.cloudSlash
                    : PhosphorIconsBold.cloudArrowUp,
                color: failed.isNotEmpty ? AppColors.error : AppColors.warning,
              ),
              title: Row(
                children: [
                  Text(
                    tr('قائمة انتظار المزامنة'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: failed.isNotEmpty ? AppColors.error : AppColors.warning,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (pending.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(tr('{p0} بانتظار', {'p0': pending.length}),
                          style: const TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 4),
                  if (failed.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(tr('{p0} فشل نهائي', {'p0': failed.length}),
                          style: const TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (syncState.isSyncing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton.icon(
                      onPressed: () =>
                          ref.read(syncWorkerProvider.notifier).processOutbox(),
                      icon: const Icon(PhosphorIconsBold.cloudArrowUp, size: 14),
                      label:  Text(tr('مزامنة الكل'), style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    ),
                  const Icon(Icons.expand_more),
                ],
              ),
              children: [
                const Divider(height: 1),
                ...allItems.where((i) => i.status != 'synced').map((item) {
                  final isDeadLetter = item.status == 'dead_letter';
                  final isFailed = isDeadLetter || item.status == 'failed' || item.attempts > 0;
                  final color = isDeadLetter
                      ? AppColors.error
                      : (isFailed ? AppColors.warning : Colors.grey.shade600);

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(_syncTableIcon(item.targetTable), color: color, size: 14),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_syncTableTitle(item.targetTable)} #${item.recordId}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isDeadLetter)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                            ),
                            child:  Text(tr('فشل نهائي'),
                                style: const TextStyle(fontSize: 9, color: AppColors.error, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('{p0} | المحاولات: {p1}', {'p0': _syncOperationTitle(item.operation), 'p1': item.attempts}),
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                        if (item.lastError != null)
                          Text(
                            item.lastError!.replaceAll('DEAD_LETTER: ', ''),
                            style: TextStyle(
                              fontSize: 10,
                              color: isDeadLetter ? AppColors.error : AppColors.warning,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 16, color: AppColors.info),
                          tooltip: tr('إعادة محاولة'),
                          onPressed: () async {
                            await syncRepo.retryItem(item.id);
                            ref.read(syncWorkerProvider.notifier).processOutbox();
                          },
                        ),
                        IconButton(
                          icon: const Icon(PhosphorIconsBold.trash, size: 16, color: AppColors.error),
                          tooltip: tr('حذف'),
                          onPressed: () => syncRepo.deleteItem(item.id),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  String _syncTableTitle(String table) {
    switch (table) {
      case 'sales':
      case 'sales_invoices': return tr('فاتورة مبيعات');
      case 'sales_returns': return tr('مرتجع مبيعات');
      case 'purchase_invoices':
      case 'purchases': return tr('فاتورة مشتريات');
      case 'shifts': return tr('وردية');
      case 'expenses': return tr('مصروف');
      case 'receipts': return tr('قبض');
      case 'held_orders': return tr('طلب محفوظ');
      case 'parties': return tr('عميل/مورد');
      case 'products': return tr('صنف');
      case 'users': return tr('مستخدم');
      default: return table;
    }
  }

  IconData _syncTableIcon(String table) {
    switch (table) {
      case 'sales':
      case 'sales_invoices':
      case 'sales_returns': return PhosphorIconsBold.receipt;
      case 'purchases':
      case 'purchase_invoices': return PhosphorIconsBold.truck;
      case 'shifts': return PhosphorIconsBold.clock;
      case 'expenses': return PhosphorIconsBold.arrowDown;
      case 'receipts': return PhosphorIconsBold.arrowUp;
      case 'users': return PhosphorIconsBold.user;
      default: return PhosphorIconsBold.shoppingBag;
    }
  }

  String _syncOperationTitle(String op) {
    switch (op) {
      case 'insert': return tr('إضافة');
      case 'update': return tr('تعديل');
      case 'delete': return tr('حذف');
      case 'open': return tr('فتح');
      case 'close': return tr('إغلاق');
      default: return op;
    }
  }

  Widget _reconcileStat(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  Future<void> _showRemediationDialog() async {
    final accounting = ref.read(accountingServiceProvider);

    // Dry-run preview of the branch cost-center repair (read-only) so the
    // operator sees exactly how many entries would move before committing.
    BranchCostCenterRepairReport? preview;
    try {
      preview = await accounting.repairBranchCostCenters(dryRun: true);
    } catch (_) {
      preview = null;
    }
    if (!mounted) return;

    final String branchLine;
    if (preview == null) {
      branchLine = tr('تعذّر حساب معاينة إصلاح مراكز الفروع.');
    } else if (preview.hasWork) {
      branchLine =
          tr('قيود آلية مسجّلة على «عام» وتخص فروعاً لها مركز تكلفة خاص: {p0} قيد / {p1} سطر — ستُنقل إلى مركز تكلفة الفرع.', {'p0': preview.affectedEntries, 'p1': preview.affectedLines});
    } else {
      branchLine = tr('لا توجد قيود بحاجة لإعادة التوزيع على مراكز الفروع.');
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('إصلاح فروقات التقارير والمراكز')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(tr('١) تعبئة مراكز التكلفة للأسطر التاريخية من رؤوس القيود.')),
            const SizedBox(height: 10),
            Text(tr('٢) {branchLine}', {'branchLine': branchLine})),
            const SizedBox(height: 12),
             Text(
              tr('العملية آمنة ولا تغيّر أي مبالغ مدينة/دائنة — تعيد فقط تصنيف مركز التكلفة.'),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child:  Text(tr('إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child:  Text(tr('بدء الإصلاح'))),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        // 1) Backfill line-level cost centers from headers (existing behaviour).
        await accounting.remediateHistoricalData();
        // 2) Re-attribute auto-posted «عام» entries to their branch centre.
        final res = await accounting.repairBranchCostCenters(dryRun: false);
        if (mounted) {
          final moved = res.applied && res.hasWork
              ? tr(' — نُقل {p0} قيد إلى مراكز الفروع', {'p0': res.affectedEntries})
              : '';
          AppToast.show(context, tr('تمت عملية الإصلاح بنجاح{moved}. يرجى تحديث التقارير.', {'moved': moved}),
              type: ToastType.success);
          setState(() => _refreshKey++);
        }
      } catch (e) {
        if (mounted) AppToast.show(context, tr('خطأ أثناء الإصلاح: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }
}