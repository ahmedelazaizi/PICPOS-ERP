import 'package:picpos_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:google_fonts/google_fonts.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import 'report_export_guard.dart';
import 'report_scaffold.dart';

import '../../../data/providers/providers.dart';
import '../../widgets/report_components.dart';
import '../../widgets/report_filter_bar.dart';
import '../../../services/invoice_generator.dart';
import '../../../../../../core/constants/app_constants.dart';
import '../../../data/providers/manufacturing_providers.dart';
import '../../widgets/branch_warehouse_filter.dart';

class PurchasesReportScreen extends ConsumerStatefulWidget {
  const PurchasesReportScreen({super.key});

  @override
  ConsumerState<PurchasesReportScreen> createState() =>
      _PurchasesReportScreenState();
}

class _PurchasesReportScreenState extends ConsumerState<PurchasesReportScreen> {
  // Spec 065: default range is full-day-inclusive [00:00, 23:59:59.999] (D3-006).
  DateTimeRange _dateRange = DateRangeFilter.normalizeRange(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
    DateTime.now(),
  );

  bool _isLoading = false;
  PurchasesAnalytics? _analytics;
  List<PurchaseInvoiceWithSupplier> _invoices = [];
  List<PurchaseInvoiceWithSupplier> _filteredInvoices = [];
  List<Map<String, dynamic>> _supplierAnalysis = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);
  int? _selectedRegionId;
  int? _selectedWarehouseId;
  int? _selectedBranchId;
  Set<int>? _branchWarehouseIds;
  // Spec 080: region's resolved warehouse-id list. Null when no region
  // is selected. The screen owns regionId-to-warehouseIds resolution
  // because the repo methods that build the invoice list and supplier
  // breakdown don't accept regionId — only the analytics method does.
  // See specs/080-purchases-region-filter/spec.md.
  List<int>? _regionWarehouseIds;
  int? _selectedCostCenterId;
  List<CostCenter> _costCenters = [];
  Map<int, String> _warehouseNames = {};

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  // Spec 149 B12-4 (FIL-2): the logged-in user's branch authorization scope.
  // null = full access (admin/financial-manager/mirror) → no restriction.
  // Mirrors tax_report_screen.dart's B12-2 wiring. Set both here (build())
  // AND at the top of _loadData() — this screen fetches imperatively from
  // initState()'s microtask and filter callbacks, so _loadData() re-resolves
  // the scope itself so no fetch can ever race ahead of the resolved scope.
  Set<int>? _allowedBranchIds;

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
          // H13 · بذرُ الاسم وحدَه كان يخلّي القائمةَ تقول فرعاً والأرقامَ
          // تقول شركة: نطاقُ الاستعلام (`_branchWarehouseIds`) كان يُحلّ في
          // `onBranchChanged` فقط، فيفضل `null` على أوّل تحميل.
          _branchWarehouseIds =
              await BranchWarehouseFilterBar.getBranchWarehouseIds(
                  ref, activeBranchId);
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
      _loadFilters();
      _loadData();
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(user?.id ?? 0, user?.displayName ?? tr('مجهول'), tr('تقرير المشتريات'));
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    final accountingRepo = ref.read(accountingRepositoryProvider);
    final cc = await accountingRepo.getActiveCostCenters();
    setState(() => _costCenters = cc);
  }

  void _applyFilters() {
    var filtered = List<PurchaseInvoiceWithSupplier>.from(_invoices);

    // Only text search remains client-side; spatial filters are now server-side
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        final inv = item.invoice;
        final supplierName = item.supplierName?.toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        return inv.invoiceNumber.toLowerCase().contains(query) ||
            supplierName.contains(query);
      }).toList();
    }

    setState(() => _filteredInvoices = filtered);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Spec 149 B12-4 (FIL-2): resolve the auth-level branch scope BEFORE
      // the report query runs, on every call. _loadData is invoked both
      // from initState's microtask and from the filter-bar onChanged
      // callbacks, so re-resolving here closes the race where the FIRST
      // load could otherwise run before build() ever observes
      // branchScopeProvider.
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final repo = ref.read(reportingRepositoryProvider);

      // Spec 080: build effective warehouseIds with 3-level precedence
      // (most specific wins): single warehouse → branch's warehouses →
      // region's warehouses. The region tier replaces the old approach
      // of passing `regionId` to the analytics call — now ALL three
      // repo calls get the same pre-resolved list, so they agree on
      // what data to return. Closes the field-reported asymmetry where
      // KPIs filtered by region but the invoice list and supplier
      // breakdown did not.
      List<int>? warehouseIds;
      if (_selectedWarehouseId != null) {
        warehouseIds = [_selectedWarehouseId!];
      } else if (_branchWarehouseIds != null) {
        warehouseIds = _branchWarehouseIds!.toList();
      } else if (_regionWarehouseIds != null) {
        warehouseIds = _regionWarehouseIds!;
      }

      final analytics = await repo.getPurchasesReportAnalytics(
        _dateRange.start,
        _dateRange.end,
        warehouseIds: warehouseIds,
        costCenterId: _selectedCostCenterId,
        // regionId intentionally dropped — already encoded in warehouseIds.
        allowedBranchIds: _allowedBranchIds,
      );
      final invoices = await repo.getPurchasesWithSupplierByDateRange(
        _dateRange.start,
        _dateRange.end,
        warehouseIds: warehouseIds,
        costCenterId: _selectedCostCenterId,
        allowedBranchIds: _allowedBranchIds,
      );
      final supplierData = await repo.getPurchasesBySupplier(
        from: _dateRange.start,
        to: _dateRange.end,
        warehouseIds: warehouseIds,
        costCenterId: _selectedCostCenterId,
        allowedBranchIds: _allowedBranchIds,
      );

      // Load warehouse names
      final warehouses = await ref.read(warehouseListProvider.future);
      final whMap = <int, String>{};
      for (final w in warehouses) {
        whMap[w.id] = w.name;
      }

      setState(() {
        _analytics = analytics;
        _invoices = invoices;
        _supplierAnalysis = supplierData;
        _warehouseNames = whMap;
        _applyFilters();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Spec 149 B12-4 (FIL-2): resolve the auth-level branch scope BEFORE any
    // report query runs. Reports MUST NOT render (even a flash) while the
    // scope is unknown — a restricted user briefly seeing an unscoped
    // report is itself the leak this fix closes. Mirrors tax_report_screen.
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

    return reportScaffold(
      context: context,
      title: tr('تقرير المشتريات التفصيلي'),
      subtitle: tr('فواتيرُ الشراء والموردون في المدى المحدَّد'),
      icon: PhosphorIconsBold.shoppingCart,
      actions: [
            buildReportExportAction(onExport: _exportToExcel),
            IconButton(
              onPressed: _printReport,
              icon: const Icon(PhosphorIconsBold.printer),
              tooltip: tr('طباعة/PDF'),
            ),
            const SizedBox(width: 8),
          ],
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
                  onRegionChanged: (v) async {
                    // Spec 079b (B2) + b142 hotfix: passes `regionId` to
                    // repo. We resolve the branch list here to fire the
                    // FILTER-WARN diagnostic via the DAO directly — the
                    // `regionBranchesProvider` is autoDispose+family and
                    // disposes before its Stream emits when read via
                    // `.future`, swallowing both the diagnostic AND any
                    // downstream resolution.
                    //
                    // Spec 080: also resolve the warehouse-id list here
                    // and store it in `_regionWarehouseIds`. The invoice-
                    // list + supplier-breakdown repo methods don't accept
                    // `regionId`, so the screen has to pre-resolve and
                    // pass `warehouseIds` for ALL three repo calls. Without
                    // this, KPIs filter correctly but the table doesn't —
                    // the asymmetry was the field-reported 080 bug.
                    List<int>? regionWhIds;
                    if (v != null) {
                      final db = ref.read(databaseProvider);
                      final regionBranches = await db.getBranchesByRegion(v);
                      if (regionBranches.isEmpty) {
                        unawaited(DiagnosticLogger.log(
                          'FILTER-WARN',
                          'Region $v selected on purchases report but no '
                          'branches linked. Check that branches in this '
                          'region have a regionId set.',
                        ));
                      }
                      final regionRepo = ref.read(regionRepositoryProvider);
                      regionWhIds =
                          await regionRepo.getWarehouseIdsForRegion(v);
                    }
                    if (!mounted) return;
                    setState(() {
                      _selectedRegionId = v;
                      _selectedBranchId = null;
                      _selectedWarehouseId = null;
                      _branchWarehouseIds = null;
                      _regionWarehouseIds = regionWhIds;
                    });
                    _loadData();
                  },
                  selectedBranchId: _selectedBranchId,
                  selectedWarehouseId: _selectedWarehouseId,
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
                if (_costCenters.isNotEmpty)
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<int?>(
                      initialValue: _selectedCostCenterId,
                      isExpanded: true,
                      decoration:  InputDecoration(
                        labelText: tr('مركز التكلفة'),
                        isDense: true,
                        prefixIcon: const Icon(PhosphorIconsBold.buildings, size: 16),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                         DropdownMenuItem<int?>(value: null, child: Text(tr('الكل'))),
                        ..._costCenters.map((cc) => DropdownMenuItem<int?>(
                              value: cc.id,
                              child: Text(trData(cc.name), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedCostCenterId = v);
                        _loadData();
                      },
                    ),
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
                          if (_analytics != null)
                            Row(
                              children: [
                                Expanded(
                                  child: ReportKpiCard(
                                    title: tr('إجمالي المشتريات'),
                                    value:
                                        '${_currencyFormat.format(_analytics!.totalPurchases)} ${AppConstants.currencySymbolEn}',
                                    icon: PhosphorIconsBold.shoppingBagOpen,
                                    color: AppColors.warning,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ReportKpiCard(
                                    title: tr('مستحقات للموردين'),
                                    value:
                                        '${_currencyFormat.format(_analytics!.totalOutstanding)} ${AppConstants.currencySymbolEn}',
                                    icon: PhosphorIconsBold.money,
                                    color: AppColors.error,
                                    subtitle: tr('فواتير غير مسددة بالكامل'),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ReportKpiCard(
                                    title: tr('عدد فواتير الشراء'),
                                    value: _analytics!.invoiceCount.toString(),
                                    icon: PhosphorIconsBold.files,
                                    color: AppColors.info,
                                    subtitle:
                                        tr('متوسط القيمة: {p0}', {'p0': _currencyFormat.format(_analytics!.averagePurchaseValue)}),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 24),

                          // ── Supplier Analysis ──
                          if (_supplierAnalysis.isNotEmpty) ..._buildSupplierAnalysis(),

                          // ── Monthly Trends ──
                          if (_invoices.isNotEmpty) ..._buildMonthlyTrends(),

                          const SizedBox(height: 24),

                          // Search Bar
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: TextField(
                              controller: _searchController,
                              decoration:  InputDecoration(
                                hintText: tr('بحث برقم الفاتورة أو اسم المورد...'),
                                prefixIcon: const Icon(
                                  PhosphorIconsBold.magnifyingGlass,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (value) {
                                setState(() => _searchQuery = value);
                                _applyFilters();
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          Text(
                            tr('سجل مشتريات الفترة'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.titleLarge?.color,
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
                                columns:  [
                                  DataColumn(label: Text(tr('رقم الفاتورة'))),
                                  DataColumn(label: Text(tr('التاريخ'))),
                                  DataColumn(label: Text(tr('المورد'))),
                                  DataColumn(label: Text(tr('المخزن'))),
                                  DataColumn(label: Text(tr('الإجمالي'))),
                                  DataColumn(label: Text(tr('المدفوع'))),
                                  DataColumn(label: Text(tr('المتبقي'))),
                                  DataColumn(label: Text(tr('الحالة'))),
                                ],
                                rows: _filteredInvoices.map((item) {
                                  final p = item.invoice;
                                  final remaining = p.total - p.paid;
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(p.invoiceNumber)),
                                      DataCell(
                                        Text(_dateFormat.format(p.invoiceDate)),
                                      ),
                                      DataCell(
                                        Text(
                                          item.supplierName ?? tr('مورد غير معروف'),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          _warehouseNames[p.warehouseId] ?? tr('غير محدد'),
                                        ),
                                      ),
                                      DataCell(
                                        Text(_currencyFormat.format(p.total)),
                                      ),
                                      DataCell(
                                        Text(_currencyFormat.format(p.paid)),
                                      ),
                                      DataCell(
                                        Text(_currencyFormat.format(remaining)),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: remaining <= 0
                                                ? AppColors.success.withValues(
                                                    alpha: 0.1,
                                                  )
                                                : AppColors.error.withValues(
                                                    alpha: 0.1,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            remaining <= 0 ? tr('مسددة') : tr('آجلة'),
                                            style: TextStyle(
                                              color: remaining <= 0
                                                  ? AppColors.success
                                                  : AppColors.error,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
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
    );
  }

  // ── Supplier Analysis ──────────────────────────────────────
  List<Widget> _buildSupplierAnalysis() {
    final totalAll = _supplierAnalysis.fold<double>(
        0, (s, e) => s + ((e['totalPurchases'] as num?)?.toDouble() ?? 0));

    return [
      Text(tr('تحليل الموردين'),
          style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            columns:  [
              DataColumn(label: Text(tr('المورد'))),
              DataColumn(label: Text(tr('فواتير')), numeric: true),
              DataColumn(label: Text(tr('إجمالي')), numeric: true),
              DataColumn(label: Text(tr('النسبة')), numeric: true),
            ],
            rows: _supplierAnalysis.take(10).map((s) {
              final total =
                  (s['totalPurchases'] as num?)?.toDouble() ?? 0;
              final pct =
                  totalAll > 0 ? (total / totalAll * 100) : 0.0;
              return DataRow(cells: [
                DataCell(Text(s['name']?.toString() ?? tr('غير معروف'))),
                DataCell(Text('${s['invoiceCount'] ?? 0}')),
                DataCell(Text(
                    '${_currencyFormat.format(total)} ${AppConstants.currencySymbolEn}')),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${pct.toStringAsFixed(1)}%',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: AppColors.primary)),
                  ),
                ),
              ]);
            }).toList(),
          ),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  // ── Monthly Purchase Trends ───────────────────────────────
  List<Widget> _buildMonthlyTrends() {
    // Group invoices by month
    final Map<String, double> monthlyTotals = {};
    final Map<String, int> monthlyCounts = {};
    for (final item in _invoices) {
      final key =
          '${item.invoice.invoiceDate.year}-${item.invoice.invoiceDate.month.toString().padLeft(2, '0')}';
      monthlyTotals[key] = (monthlyTotals[key] ?? 0) + item.invoice.total;
      monthlyCounts[key] = (monthlyCounts[key] ?? 0) + 1;
    }

    if (monthlyTotals.length <= 1) return [];

    final sortedKeys = monthlyTotals.keys.toList()..sort();
    final maxVal =
        monthlyTotals.values.fold<double>(0, (a, b) => a > b ? a : b);

    return [
      Text(tr('اتجاهات المشتريات الشهرية'),
          style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: sortedKeys.map((key) {
              final total = monthlyTotals[key]!;
              final count = monthlyCounts[key]!;
              final pct = maxVal > 0 ? total / maxVal : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                        width: 70,
                        child: Text(key,
                            style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.w600))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 18,
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.05),
                          valueColor: const AlwaysStoppedAnimation(
                              AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: Text(
                          tr('{p0} ({count}ف)', {'p0': _currencyFormat.format(total), 'count': count}),
                          textAlign: TextAlign.end,
                          style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  Future<void> _exportToExcel() async {
    final service = ref.read(excelServiceProvider);

    final path = await service.exportReport(
      periodFrom: _dateRange.start,
      periodTo: _dateRange.end,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
      title: tr('تقرير المشتريات'),
      headers: [
        tr('رقم الفاتورة'),
        tr('التاريخ'),
        tr('المورد'),
        tr('المخزن'),
        tr('الإجمالي'),
        tr('المدفوع'),
        tr('المتبقي'),
        tr('الحالة'),
      ],
      // ‏`_filteredInvoices` لا `_invoices`: الجدولُ والطباعةُ والتحليلاتُ كلُّها
      // تقرأ المفلترة، والفلترُ الباقي عميلاً هو **البحثُ النصّي**. فمن يبحث عن
      // مورّدٍ فيرى ثلاثَ فواتير ثم يصدّر كان يحصل على المئتين كلِّها.
      rows: _filteredInvoices.map<List<dynamic>>((item) {
        final p = item.invoice;
        return [
          p.invoiceNumber,
          _dateFormat.format(p.invoiceDate),
          item.supplierName ?? tr('غير معروف'),
          _warehouseNames[p.warehouseId] ?? tr('غير محدد'),
          p.total,
          p.paid,
          p.total - p.paid,
          (p.total - p.paid) <= 0 ? tr('مسددة') : tr('آجلة'),
        ];
      }).toList(),
    );

    if (path != null && mounted) {
      AppToast.show(
        context,
        tr('تم تصدير التقرير بنجاح: {path}', {'path': path}),
        type: ToastType.success,
      );
    }
  }

  Future<void> _printReport() async {
    if (_analytics == null || _filteredInvoices.isEmpty) {
      AppToast.show(context, tr('لا توجد بيانات للطباعة'), type: ToastType.error);
      return;
    }

    try {
      await InvoiceGenerator.printPurchasesReport(
        invoices: _filteredInvoices,
        totalPurchases: _analytics!.totalPurchases,
        invoiceCount: _filteredInvoices.length,
        fromDate: _dateRange.start,
        toDate: _dateRange.end,
        printedBy: ref.read(authProvider).user?.displayName,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ في الطباعة: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }
}