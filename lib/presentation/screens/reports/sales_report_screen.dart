// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';

import '../../../data/providers/providers.dart';
import '../../widgets/report_components.dart';
import '../../widgets/report_filter_bar.dart';
import '../../../services/invoice_generator.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/manufacturing_providers.dart';
import '../../widgets/branch_warehouse_filter.dart';

class SalesReportScreen extends ConsumerStatefulWidget {
  const SalesReportScreen({super.key});

  @override
  ConsumerState<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends ConsumerState<SalesReportScreen> {
  // Spec 065: default range is full-day-inclusive [00:00, 23:59:59.999] so the
  // initial load matches what the chip "اليوم"/"الشهر" emits (D3-006).
  DateTimeRange _dateRange = DateRangeFilter.normalizeRange(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
    DateTime.now(),
  );

  bool _isLoading = false;
  SalesAnalytics? _analytics;
  SalesAnalytics? _previousAnalytics;
  List<SalesInvoiceData> _invoices = [];
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);
  int? _selectedUserId;
  String? _selectedPaymentMethod;
  String? _selectedSaleType;
  int? _selectedRegionId;
  int? _selectedWarehouseId;
  int? _selectedBranchId;
  Set<int>? _branchWarehouseIds;
  // 072 (D3-003): cache region's warehouse IDs so the invoice list narrows
  // when only Region is picked (no Branch). Mirrors delivery_report,
  // top_products_report, sales_returns_report.
  Set<int>? _regionWarehouseIds;
  int? _selectedCostCenterId;
  List<CostCenter> _costCenters = [];
  Map<int, String> _userNames = {};
  Map<int, String> _warehouseNames = {};
  List<UserWithRole> _allUsers = [];

  // Spec 149 B12-4 (FIL-2): the logged-in user's branch authorization scope.
  // null = full access (admin/financial-manager/mirror) → no restriction.
  // Mirrors tax_report_screen.dart's B12-2 wiring. Set both here (build())
  // AND at the top of _loadData() — this screen fetches imperatively from
  // initState()'s microtask AND from a salesDataVersionProvider subscription
  // + filter callbacks, so _loadData() re-resolves the scope itself so no
  // fetch can ever race ahead of the resolved scope.
  Set<int>? _allowedBranchIds;

  // Spec 056: live-refresh subscription. Created in initState (synchronously,
  // not in a microtask) via ref.listenManual so it works outside of build,
  // and closed in dispose to avoid leaks.
  ProviderSubscription<int>? _salesVersionSub;

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  @override
  void initState() {
    super.initState();
    // Auto-refresh when server API receives a sale from a client.
    // listenManual is the documented Riverpod 3.x API for subscribing
    // outside of build; the previous ref.listen-in-microtask pattern asserts
    // because debugDoingBuild is false by the time the microtask runs.
    _salesVersionSub = ref.listenManual<int>(salesDataVersionProvider,
        (prev, next) {
      if (prev != null && next > prev) {
        _loadData();
      }
    });

    Future.microtask(() async {
      // Feature 058: seed _selectedBranchId from the device's active branch
      // BEFORE the first data fetch (FR-001 + FR-002). Skip if a preset has
      // already populated the field (forward-compat with Feature 059).
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
      _loadFilters();
      _loadData();
      // #Forensic Log: Report View
      try {
        final user = ref.read(authProvider).user;
        final logger = ref.read(activityLoggerProvider);
        logger.logReportView(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير المبيعات');
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _salesVersionSub?.close();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    final accountingRepo = ref.read(accountingRepositoryProvider);
    final cc = await accountingRepo.getActiveCostCenters();
    setState(() => _costCenters = cc);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Spec 149 B12-4 (FIL-2): resolve the auth-level branch scope BEFORE
      // the report query runs, on every call. _loadData is invoked from
      // initState's microtask, the salesDataVersionProvider subscription,
      // AND the filter-bar onChanged callbacks, so re-resolving here closes
      // the race where an early load could otherwise run unrestricted.
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final repo = ref.read(reportingRepositoryProvider);
      // Build warehouseIds from filter state.
      // 072 (D3-003): fall back to region's warehouses when neither
      // Warehouse nor Branch is picked but Region is.
      List<int>? warehouseIds;
      if (_selectedWarehouseId != null) {
        warehouseIds = [_selectedWarehouseId!];
      } else if (_branchWarehouseIds != null) {
        warehouseIds = _branchWarehouseIds!.toList();
      } else if (_regionWarehouseIds != null) {
        warehouseIds = _regionWarehouseIds!.toList();
      }

      // 072 (D3-002): thread costCenterId into all 3 repo calls; the
      // dropdown's onChanged was setState+_loadData, but the value never
      // reached the repo — silent no-op. Repo signatures already accept
      // costCenterId.
      // Spec 136 (field 2026-06-09): thread paymentMethod + saleType into the
      // analytics call so the KPI cards respect the SAME filters as the
      // invoice list below them. Before this, the cards summed every payment
      // method/sale type while the list was filtered — a confusing mismatch
      // (card said 100,000; rows summed to 35,000 cash-only).
      final analytics = await repo.getSalesAnalytics(
        _dateRange.start,
        _dateRange.end,
        userId: _selectedUserId,
        warehouseIds: warehouseIds,
        costCenterId: _selectedCostCenterId,
        paymentMethod: _selectedPaymentMethod,
        saleType: _selectedSaleType,
        allowedBranchIds: _allowedBranchIds,
      );
      final invoices = await repo.getSalesByDateRange(
        _dateRange.start,
        _dateRange.end,
        userId: _selectedUserId,
        warehouseIds: warehouseIds,
        costCenterId: _selectedCostCenterId,
        allowedBranchIds: _allowedBranchIds,
      );

      // Compute previous period (same duration, immediately before)
      final duration = _dateRange.end.difference(_dateRange.start);
      final prevEnd = _dateRange.start.subtract(const Duration(seconds: 1));
      final prevStart = prevEnd.subtract(duration);
      final prevAnalytics = await repo.getSalesAnalytics(
        prevStart,
        prevEnd,
        userId: _selectedUserId,
        warehouseIds: warehouseIds,
        costCenterId: _selectedCostCenterId,
        paymentMethod: _selectedPaymentMethod,
        saleType: _selectedSaleType,
        allowedBranchIds: _allowedBranchIds,
      );

      // Load user names for display
      final users = await repo.watchAllUsers().first;
      final userMap = <int, String>{};
      for (final u in users) {
        userMap[u.user.id] = u.user.displayName;
      }

      // Load warehouse names
      final warehouses = await ref.read(warehouseListProvider.future);
      final whMap = <int, String>{};
      for (final w in warehouses) {
        whMap[w.id] = w.name;
      }

      setState(() {
        _analytics = analytics;
        _previousAnalytics = prevAnalytics;
        var filtered = invoices;
        if (_selectedPaymentMethod != null) {
          // Spec 079 / B3: filter values match the DISPLAY labels.
          // The display at line ~620 collapses card+transfer+bank into
          // a single "بطاقة/تحويل" label; the filter follows suit so
          // picking "بطاقة/تحويل" matches every row the user would
          // see labeled that way. Similar grouping for multiple/mixed.
          filtered = filtered.where((i) {
            switch (_selectedPaymentMethod) {
              case 'bank_group':
                return i.paymentMethod == 'card' ||
                    i.paymentMethod == 'transfer' ||
                    i.paymentMethod == 'bank';
              case 'multiple':
                return i.paymentMethod == 'multiple' ||
                    i.paymentMethod == 'mixed';
              default:
                return i.paymentMethod == _selectedPaymentMethod;
            }
          }).toList();
        }
        if (_selectedSaleType != null) {
          filtered = filtered.where((i) => i.saleType == _selectedSaleType).toList();
        }
        if (_selectedWarehouseId != null) {
          filtered = filtered.where((i) => i.warehouseId == _selectedWarehouseId).toList();
        } else if (_branchWarehouseIds != null) {
          filtered = filtered.where((i) => _branchWarehouseIds!.contains(i.warehouseId)).toList();
        } else if (_regionWarehouseIds != null) {
          // Spec 079 / B1: region scope MUST also filter locally — the
          // repo call already passes warehouseIds, but if the dataset
          // includes rows whose warehouse is outside the region (e.g.
          // because warehouseIds was empty due to incomplete
          // region→branch→warehouse data), the local filter is the
          // belt-and-suspenders guard.
          filtered = filtered.where((i) => _regionWarehouseIds!.contains(i.warehouseId)).toList();
        }
        _invoices = filtered;
        _userNames = userMap;
        _warehouseNames = whMap;
        _allUsers = users;
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
          title: const Text('تقرير المبيعات التفصيلي'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              onPressed: _exportToExcel,
              icon: const Icon(PhosphorIconsBold.fileXls),
              tooltip: 'تصدير Excel',
            ),
            IconButton(
              onPressed: _printReport,
              icon: const Icon(PhosphorIconsBold.printer),
              tooltip: 'طباعة/PDF',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // Spec 076: unified two-row filter bar (date presets on top,
            // variable filters reflow below via Wrap+Scrollbar). No more
            // single-Row overflow on the 7-filter sales report.
            ReportFilterBar(
              selectedRange: _dateRange,
              onRangeChanged: (start, end) {
                setState(
                  () => _dateRange = DateTimeRange(start: start, end: end),
                );
                _loadData();
              },
              trailing: [
                // User Filter
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedUserId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المستخدم',
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
                // Payment method filter
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedPaymentMethod,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'طريقة الدفع',
                      isDense: true,
                      prefixIcon: Icon(PhosphorIconsBold.creditCard, size: 16),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                      DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                      // Spec 079 / B3: grouped value matches the display
                      // label collapse (card / transfer / bank).
                      DropdownMenuItem(value: 'bank_group', child: Text('بطاقة/تحويل')),
                      DropdownMenuItem(value: 'click', child: Text('كليك')),
                      DropdownMenuItem(value: 'credit', child: Text('آجل')),
                      DropdownMenuItem(value: 'multiple', child: Text('متعدد')),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedPaymentMethod = v);
                      _loadData();
                    },
                  ),
                ),
                // Sale type filter
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedSaleType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'نوع البيع',
                      isDense: true,
                      prefixIcon: Icon(PhosphorIconsBold.storefront, size: 16),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                      DropdownMenuItem(value: 'default', child: Text('نقطة البيع')),
                      DropdownMenuItem(value: 'talabat', child: Text('طلبات')),
                      DropdownMenuItem(value: 'careem', child: Text('كريم')),
                      DropdownMenuItem(value: 'ashyae', child: Text('أشيائي')),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedSaleType = v);
                      _loadData();
                    },
                  ),
                ),
                // Region + Branch + Warehouse filter
                BranchWarehouseFilterBar(
                  selectedRegionId: _selectedRegionId,
                  onRegionChanged: (v) async {
                    _selectedRegionId = v;
                    _selectedBranchId = null;
                    _selectedWarehouseId = null;
                    _branchWarehouseIds = null;
                    // 072 (D3-003): compute region's warehouse set so the
                    // invoice list scopes to it when no Branch is picked.
                    if (v != null) {
                      final ids = await BranchWarehouseFilterBar
                          .getRegionWarehouseIds(ref, v);
                      _regionWarehouseIds = ids.toSet();
                      // Spec 079 / B1+FR-003: surface data-integrity hint
                      // when a region selection yields zero warehouses.
                      // Without this, the report renders "empty" and the
                      // operator has no signal whether it's truly empty
                      // or whether the region→branch→warehouse mapping
                      // is incomplete.
                      if (_regionWarehouseIds!.isEmpty) {
                        unawaited(DiagnosticLogger.log(
                          'FILTER-WARN',
                          'Region $v selected on sales report but no '
                          'warehouses linked. Check that branches in this '
                          'region have a regionId, and their warehouses '
                          'have branchId set.',
                        ));
                      }
                    } else {
                      _regionWarehouseIds = null;
                    }
                    setState(() {});
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
                // Cost Center filter (conditional)
                if (_costCenters.isNotEmpty)
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<int?>(
                      initialValue: _selectedCostCenterId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'مركز التكلفة',
                        isDense: true,
                        prefixIcon: Icon(PhosphorIconsBold.buildings, size: 16),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
                        ..._costCenters.map((cc) => DropdownMenuItem<int?>(
                              value: cc.id,
                              child: Text(cc.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
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
                          // Spec 076 polish: 5 KPIs merged into one Row so
                          // they read as a single eye-line at standard
                          // desktop widths (was 3 + 2 wrap).
                          if (_analytics != null)
                            Row(
                              children: [
                                Expanded(
                                  child: ReportKpiCard(
                                    title: 'إجمالي المبيعات',
                                    value:
                                        '${_currencyFormat.format(_analytics!.totalSales)} ${AppConstants.currencySymbolEn}',
                                    icon: PhosphorIconsBold.chartLineUp,
                                    color: AppColors.primary,
                                    changePercent: _calcChange(
                                      _analytics!.totalSales,
                                      _previousAnalytics?.totalSales,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ReportKpiCard(
                                    // B11 REP-1 (spec 149): this is
                                    // getSalesAnalytics.totalProfit — a
                                    // sales-level figure (revenue − discount
                                    // − COGS − tax) that never touches the
                                    // GL and structurally omits operating
                                    // expenses/salaries/depreciation. It is
                                    // NOT the company's true net profit, so
                                    // it must not be labeled "صافي الربح".
                                    // The GL-sourced true net profit lives on
                                    // the main dashboard (dashboardKpiProvider)
                                    // and the financial statements screen.
                                    // This screen's filters (user/payment
                                    // method/sale type/warehouse) have no GL
                                    // equivalent, so routing this card to the
                                    // GL would silently diverge from the
                                    // filtered invoice list below it — kept
                                    // as the sales-level figure, relabeled.
                                    title: 'ربح المبيعات (قبل المصروفات)',
                                    value:
                                        '${_currencyFormat.format(_analytics!.totalProfit)} ${AppConstants.currencySymbolEn}',
                                    icon: PhosphorIconsBold.trendUp,
                                    color: AppColors.success,
                                    subtitle: 'بناءً على تكلفة المنتج — قبل المصروفات التشغيلية',
                                    changePercent: _calcChange(
                                      _analytics!.totalProfit,
                                      _previousAnalytics?.totalProfit,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ReportKpiCard(
                                    title: 'عدد الفواتير',
                                    value: _analytics!.invoiceCount.toString(),
                                    icon: PhosphorIconsBold.receipt,
                                    color: AppColors.info,
                                    subtitle:
                                        'متوسط: ${_currencyFormat.format(_analytics!.averageInvoiceValue)}',
                                    changePercent: _calcChange(
                                      _analytics!.invoiceCount.toDouble(),
                                      _previousAnalytics?.invoiceCount
                                          .toDouble(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ReportKpiCard(
                                    title: 'هامش ربح المبيعات',
                                    value: _analytics!.totalSales > 0
                                        ? '${(_analytics!.totalProfit / _analytics!.totalSales * 100).toStringAsFixed(1)}%'
                                        : '0%',
                                    icon: PhosphorIconsBold.percent,
                                    color: const Color(0xFF7C3AED),
                                    subtitle: 'ربح المبيعات / إجمالي المبيعات',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ReportKpiCard(
                                    title: 'متوسط ربح الفاتورة',
                                    value: _analytics!.invoiceCount > 0
                                        ? '${_currencyFormat.format(_analytics!.totalProfit / _analytics!.invoiceCount)} ${AppConstants.currencySymbolEn}'
                                        : '0',
                                    icon: PhosphorIconsBold.piggyBank,
                                    color: const Color(0xFF059669),
                                    subtitle: 'ربح لكل فاتورة',
                                  ),
                                ),
                              ],
                            ),

                          const SizedBox(height: 24),

                          // Invoices Table
                          Text(
                            'سجل الفواتير',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.titleLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Issue 15 — DataTable forces its intrinsic width
                          // and overflows the right side on smaller laptop
                          // displays (1366×768). Wrap in a horizontal
                          // SingleChildScrollView and let the table size
                          // itself to its content; the user can scroll
                          // sideways for the trailing columns.
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: AppColors.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  Theme.of(context).cardColor,
                                ),
                                columnSpacing: 24,
                                columns: const [
                                  DataColumn(label: Text('رقم الفاتورة')),
                                  DataColumn(label: Text('التاريخ')),
                                  DataColumn(label: Text('المستخدم')),
                                  DataColumn(label: Text('العميل')),
                                  DataColumn(label: Text('المخزن')),
                                  DataColumn(label: Text('الإجمالي'), numeric: true),
                                  DataColumn(label: Text('المدفوع'), numeric: true),
                                  DataColumn(label: Text('المتبقي'), numeric: true),
                                  DataColumn(label: Text('طريقة الدفع')),
                                ],
                                rows: _invoices.map((s) {
                                  final remaining = s.total - s.paid;
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        InkWell(
                                          onTap: () => _viewInvoice(s),
                                          child: Text(
                                            s.invoiceNumber,
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(_dateFormat.format(s.invoiceDate)),
                                      ),
                                      DataCell(
                                        Text(
                                          _userNames[s.userId] ?? 'غير معروف',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          s.customerId?.toString() ?? 'نقدي',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          _warehouseNames[s.warehouseId] ?? 'غير محدد',
                                        ),
                                      ),
                                      DataCell(
                                        Text(_currencyFormat.format(s.total)),
                                      ),
                                      DataCell(
                                        Text(_currencyFormat.format(s.paid)),
                                      ),
                                      DataCell(
                                        Text(
                                          _currencyFormat.format(remaining),
                                          style: TextStyle(
                                            color: remaining > 0
                                                ? AppColors.error
                                                : AppColors.success,
                                            fontWeight: remaining > 0
                                                ? FontWeight.bold
                                                : null,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          switch (s.paymentMethod) {
                                            'cash' => 'نقدي',
                                            'card' || 'transfer' || 'bank' => 'بطاقة/تحويل',
                                            'click' => 'كليك',
                                            'multiple' || 'mixed' => 'متعدد',
                                            'credit' => 'آجل',
                                            _ => s.paymentMethod ?? '-',
                                          },
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

  void _viewInvoice(SalesInvoiceData invoice) async {
    // We can reuse the dialog logic from PartyStatementScreen if we refactor it,
    // or implement a quick version here.
    final salesRepo = ref.read(salesRepositoryProvider);
    final items = await salesRepo.getSalesInvoiceItems(invoice.id);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text('تفاصيل فاتورة ${invoice.invoiceNumber}'),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('التاريخ: ${_dateFormat.format(invoice.invoiceDate)}'),
                    Text('العميل: ${invoice.customerId ?? "نقدي"}'),
                  ],
                ),
                const Divider(height: 32),
                DataTable(
                  columns: const [
                    DataColumn(label: Text('المنتج')),
                    DataColumn(label: Text('الكمية')),
                    DataColumn(label: Text('السعر')),
                    DataColumn(label: Text('الإجمالي')),
                  ],
                  rows: items
                      .map(
                        (item) => DataRow(
                          cells: [
                            DataCell(
                              Text('منتج #${item.productId}'),
                            ), // Ideally fetch name
                            DataCell(Text(item.quantity.toString())),
                            DataCell(Text(item.unitPrice.toString())),
                            DataCell(Text(item.total.toString())),
                          ],
                        ),
                      )
                      .toList(),
                ),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'الإجمالي النهائي: ${invoice.total} ${AppConstants.currencySymbolEn}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
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
    final service = ref.read(excelServiceProvider);

    final path = await service.exportReport(
      title: 'تقرير المبيعات',
      headers: [
        'رقم الفاتورة',
        'التاريخ',
        'العميل',
        'المخزن',
        'الإجمالي',
        'المدفوع',
        'المتبقي',
        'طريقة الدفع',
      ],
      rows: _invoices
          .map<List<dynamic>>(
            (SalesInvoiceData s) => [
              s.invoiceNumber,
              _dateFormat.format(s.invoiceDate),
              s.customerId ?? 'نقدي',
              _warehouseNames[s.warehouseId] ?? 'غير محدد',
              s.total,
              s.paid,
              s.total - s.paid,
              s.paymentMethod == 'cash' ? 'نقدي' : 'آجل',
            ],
          )
          .whereType<List<dynamic>>()
          .toList(),
    );

    if (path != null && mounted) {
      AppToast.show(
        context,
        'تم تصدير التقرير بنجاح: $path',
        type: ToastType.success,
      );
      // #Forensic Log: Report Export
      try {
        final user = ref.read(authProvider).user;
        final logger = ref.read(activityLoggerProvider);
        logger.logReportExport(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير المبيعات', 'Excel');
      } catch (_) {}
    }
  }

  Future<void> _printReport() async {
    if (_analytics == null || _invoices.isEmpty) {
      AppToast.show(context, 'لا توجد بيانات للطباعة', type: ToastType.error);
      return;
    }

    try {
      await InvoiceGenerator.printSalesReport(
        invoices: _invoices,
        totalSales: _analytics!.totalSales,
        totalProfit: _analytics!.totalProfit,
        invoiceCount: _analytics!.invoiceCount,
        fromDate: _dateRange.start,
        toDate: _dateRange.end,
        companyName: 'MONEXIA Market',
        printedBy: ref.read(authProvider).user?.displayName,
      );
      // #Forensic Log: Report Print
      try {
        final user = ref.read(authProvider).user;
        final logger = ref.read(activityLoggerProvider);
        logger.logPrint(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير المبيعات');
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }

  /// Compute the percentage change between current and previous values.
  /// Returns null if there is no previous data (avoids ÷0).
  double? _calcChange(double current, double? previous) {
    if (previous == null || previous == 0) return null;
    return ((current - previous) / previous) * 100;
  }
}