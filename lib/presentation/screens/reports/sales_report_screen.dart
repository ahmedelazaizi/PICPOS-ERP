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
import 'report_export_guard.dart';

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
  Map<int, String> _customerNames = {};
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

      // Load customer names. The table, the details dialog and the export all
      // used to print the raw `customerId`, which is meaningless to a user
      // reading a sales report — "العميل: 34" tells them nothing.
      // `watchAllCustomersForLookup` on purpose: it ignores `isActive`, so a
      // customer deactivated after the sale still resolves on a historical
      // report instead of silently falling back to a bare id.
      final customers = await ref
          .read(partiesRepositoryProvider)
          .watchAllCustomersForLookup()
          .first;
      final customerMap = <int, String>{};
      for (final c in customers) {
        customerMap[c.id] = c.name;
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
        _customerNames = customerMap;
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
            buildReportExportAction(onExport: _exportToExcel),
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
                                      DataCell(Text(_customerLabel(s))),
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
                                        Text(_paymentLabel(s.paymentMethod)),
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

  /// Human-readable customer for an invoice row.
  ///
  /// Order matters: an ad-hoc (walk-in-with-a-name) sale stores the name on
  /// the invoice itself and has no party row, so it must win over the id
  /// lookup. A sale with neither is a plain cash sale.
  String _customerLabel(SalesInvoiceData s) {
    final adhoc = s.adhocCustomerName?.trim();
    if (adhoc != null && adhoc.isNotEmpty) return adhoc;
    final id = s.customerId;
    if (id == null) return 'نقدي';
    return _customerNames[id] ?? 'عميل #$id';
  }

  /// Arabic label for a payment method. Shared by the invoice table and the
  /// details dialog so the same sale never reads two different ways.
  static String _paymentLabel(String? method) => switch (method) {
        'cash' => 'نقدي',
        'card' || 'transfer' || 'bank' => 'بطاقة/تحويل',
        'click' => 'كليك',
        'multiple' || 'mixed' => 'متعدد',
        'credit' => 'آجل',
        _ => method ?? '-',
      };

  /// Quantity with just enough precision: weighed lines carry 3 decimals,
  /// counted lines are whole numbers. Printing `2.0` for two loaves of bread
  /// (what `toString()` did) reads like a measurement error.
  static String _qty(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _viewInvoice(SalesInvoiceData invoice) async {
    final salesRepo = ref.read(salesRepositoryProvider);
    // `getInvoiceItemsWithProduct`, not `getSalesInvoiceItems`: the latter is
    // a bare SELECT with no join, which is why this dialog used to print
    // "منتج #20" for every line — there was no name to print.
    final items = await salesRepo.getInvoiceItemsWithProduct(invoice.id);

    if (!mounted) return;

    final remaining = invoice.total - invoice.paid;
    final currency = AppConstants.currencySymbolEn;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.receipt,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('فاتورة ${invoice.invoiceNumber}')),
              _StatusPill(status: invoice.status, isLocked: invoice.isLocked),
            ],
          ),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header facts ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Wrap(
                      spacing: 28,
                      runSpacing: 10,
                      children: [
                        _MetaField(
                          label: 'التاريخ',
                          value: _dateFormat.format(invoice.invoiceDate),
                        ),
                        _MetaField(
                          label: 'العميل',
                          value: _customerLabel(invoice),
                        ),
                        _MetaField(
                          label: 'الكاشير',
                          value: _userNames[invoice.userId] ?? 'غير معروف',
                        ),
                        _MetaField(
                          label: 'المخزن',
                          value: _warehouseNames[invoice.warehouseId] ??
                              'غير محدد',
                        ),
                        _MetaField(
                          label: 'طريقة الدفع',
                          value: _paymentLabel(invoice.paymentMethod),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Lines ──────────────────────────────────────────────
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'لا توجد أصناف على هذه الفاتورة',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 38,
                        dataRowMinHeight: 34,
                        dataRowMaxHeight: 44,
                        columns: const [
                          DataColumn(label: Text('الصنف')),
                          DataColumn(label: Text('الكمية'), numeric: true),
                          DataColumn(label: Text('السعر'), numeric: true),
                          DataColumn(label: Text('الخصم'), numeric: true),
                          DataColumn(label: Text('الضريبة'), numeric: true),
                          DataColumn(label: Text('الإجمالي'), numeric: true),
                        ],
                        rows: items.map((row) {
                          final line = row.item;
                          // A line whose product row is gone is rendered in
                          // muted italics rather than dropped — an invoice
                          // whose lines don't add up to its total is worse
                          // than one that admits a deleted item.
                          final missing = row.product == null;
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  row.displayName,
                                  style: TextStyle(
                                    fontStyle: missing
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                    color:
                                        missing ? AppColors.textMuted : null,
                                  ),
                                ),
                              ),
                              DataCell(Text(
                                '${_qty(line.quantity)}'
                                '${line.unitName != null ? ' ${line.unitName}' : ''}',
                              )),
                              DataCell(
                                  Text(_currencyFormat.format(line.unitPrice))),
                              DataCell(
                                  Text(_currencyFormat.format(line.discount))),
                              DataCell(
                                  Text(_currencyFormat.format(line.taxAmount))),
                              DataCell(Text(
                                _currencyFormat.format(line.total),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // ── Totals ─────────────────────────────────────────────
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        children: [
                          _TotalRow(
                            label: 'الإجمالي الفرعي',
                            value:
                                '${_currencyFormat.format(invoice.subtotal)} $currency',
                          ),
                          if (invoice.discount != 0)
                            _TotalRow(
                              label: 'الخصم',
                              value:
                                  '${_currencyFormat.format(invoice.discount)} $currency',
                              color: AppColors.warning,
                            ),
                          if (invoice.tax != 0)
                            _TotalRow(
                              label: 'الضريبة',
                              value:
                                  '${_currencyFormat.format(invoice.tax)} $currency',
                            ),
                          if (invoice.deliveryFee != 0)
                            _TotalRow(
                              label: 'رسوم التوصيل',
                              value:
                                  '${_currencyFormat.format(invoice.deliveryFee)} $currency',
                            ),
                          const Divider(height: 18),
                          _TotalRow(
                            label: 'الإجمالي',
                            value:
                                '${_currencyFormat.format(invoice.total)} $currency',
                            emphasize: true,
                          ),
                          _TotalRow(
                            label: 'المدفوع',
                            value:
                                '${_currencyFormat.format(invoice.paid)} $currency',
                            color: AppColors.success,
                          ),
                          _TotalRow(
                            label: 'المتبقي',
                            value:
                                '${_currencyFormat.format(remaining)} $currency',
                            color: remaining > 0
                                ? AppColors.error
                                : AppColors.success,
                            emphasize: remaining > 0,
                          ),
                        ],
                      ),
                    ),
                  ),

                  if ((invoice.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'ملاحظات: ${invoice.notes!.trim()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _printInvoice(invoice, items),
              icon: const Icon(PhosphorIconsBold.printer, size: 16),
              label: const Text('طباعة'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printInvoice(
    SalesInvoiceData invoice,
    List<SalesInvoiceItemWithProduct> items,
  ) async {
    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      await InvoiceGenerator.printSalesInvoice(
        invoiceNumber: invoice.invoiceNumber,
        date: invoice.invoiceDate,
        customerName: _customerLabel(invoice),
        items: items
            .map((row) => InvoiceItem(
                  name: row.displayName,
                  quantity: row.item.quantity,
                  price: row.item.unitPrice,
                  total: row.item.total,
                  note: row.item.note,
                ))
            .toList(),
        subtotal: invoice.subtotal,
        discount: invoice.discount,
        tax: invoice.tax,
        total: invoice.total,
        paid: invoice.paid,
        notes: invoice.notes,
        companyName: await settingsRepo.getSetting('company_name'),
        companyAddress: await settingsRepo.getSetting('company_address'),
        companyPhone: await settingsRepo.getSetting('company_phone'),
        companyTaxId: await settingsRepo.getSetting('company_tax_id'),
        db: ref.read(databaseProvider),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'تعذّرت الطباعة: $e', type: ToastType.error);
    }
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
              _customerLabel(s),
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
      // GAP-15: اسم الشركة من إعدادات العميل مش قيمة مكتوبة بالإيد. كان
      // مثبَّت على `MONEXIA Market` — اسم علامة تالتة كان بيتطبع على
      // رأس تقرير العميل مهما كان اسم شركته في الإعدادات.
      final receiptSettings =
          await ref.read(settingsRepositoryProvider).getReceiptSettings();
      final companyName =
          receiptSettings['companyName'] as String? ?? 'الشركة';

      await InvoiceGenerator.printSalesReport(
        invoices: _invoices,
        totalSales: _analytics!.totalSales,
        totalProfit: _analytics!.totalProfit,
        invoiceCount: _analytics!.invoiceCount,
        fromDate: _dateRange.start,
        toDate: _dateRange.end,
        companyName: companyName,
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
/// Small label-over-value block used in the invoice details header.
class _MetaField extends StatelessWidget {
  final String label;
  final String value;

  const _MetaField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// One line of the totals stack in the invoice details dialog.
class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool emphasize;

  const _TotalRow({
    required this.label,
    required this.value,
    this.color,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasize ? 15 : 13,
      fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Status chip in the invoice details title. A posted (locked) invoice is
/// called out explicitly because it cannot be edited — the cashier asking
/// "why can't I change this?" should be able to see the answer.
class _StatusPill extends StatelessWidget {
  final String status;
  final bool isLocked;

  const _StatusPill({required this.status, required this.isLocked});

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      'cancelled' || 'canceled' => ('ملغاة', AppColors.error),
      'returned' => ('مرتجعة', AppColors.warning),
      'draft' => ('مسودة', AppColors.textMuted),
      _ => isLocked
          ? ('مُرحّلة', AppColors.success)
          : ('مكتملة', AppColors.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
