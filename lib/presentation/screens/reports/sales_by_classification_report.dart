// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/payment_methods.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import 'report_export_guard.dart';
import 'report_scaffold.dart';
import '../../picpos_shell/picpos_report_tabs.dart';

import '../../../core/logging/diagnostic_logger.dart';
import '../../../data/providers/providers.dart';
import '../../../services/invoice_generator.dart';
import '../../../../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../widgets/permission_guard.dart';
import '../../widgets/branch_warehouse_filter.dart';
import '../../widgets/report_components.dart' show DateRangeFilter;
import '../../widgets/report_filter_bar.dart';

class SalesByClassificationReport extends ConsumerStatefulWidget {
  const SalesByClassificationReport({super.key});

  @override
  ConsumerState<SalesByClassificationReport> createState() =>
      _SalesByClassificationReportState();
}

class _SalesByClassificationReportState
    extends ConsumerState<SalesByClassificationReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Spec 065: default range is full-day-inclusive [00:00, 23:59:59.999] (D3-006).
  DateTimeRange _dateRange = DateRangeFilter.normalizeRange(
    DateTime.now().subtract(const Duration(days: 30)),
    DateTime.now(),
  );

  // Data for export (P2-03: typed)
  List<SalesByCategoryRow> _categoryData = [];
  List<SalesBySaleTypeRow> _saleTypeData = [];
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
    _tabController = TabController(length: 2, vsync: this);
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
    // Spec 149 B12-5b (FIL-2): resolve the auth-level branch scope BEFORE
    // the report query runs, on every call. _loadData is invoked both from
    // initState's microtask and from the filter-bar onChanged callbacks, so
    // re-resolving here (rather than relying solely on build()'s
    // ref.watch) closes the race where the FIRST load could otherwise run
    // before build() ever observes branchScopeProvider.
    final scope = await ref.read(branchScopeProvider.future);
    if (!mounted) return;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    // Build warehouseIds — Feature 017 added the region branch.
    List<int>? warehouseIds;
    if (_selectedWarehouseId != null) {
      warehouseIds = [_selectedWarehouseId!];
    } else if (_branchWarehouseIds != null && _branchWarehouseIds!.isNotEmpty) {
      warehouseIds = _branchWarehouseIds!.toList();
    } else if (_regionWarehouseIds != null && _regionWarehouseIds!.isNotEmpty) {
      warehouseIds = _regionWarehouseIds!.toList();
    }

    final repo = ref.read(reportingRepositoryProvider);
    _categoryData = await repo.getSalesByCategory(
      from: _dateRange.start,
      to: _dateRange.end,
      warehouseIds: warehouseIds,
      allowedBranchIds: _allowedBranchIds,
    );
    _saleTypeData = await repo.getSalesBySaleType(
      from: _dateRange.start,
      to: _dateRange.end,
      warehouseIds: warehouseIds,
      allowedBranchIds: _allowedBranchIds,
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
              child: child!,
            ),
          ),
        );
      },
    );

    if (picked != null) {
      // H10 · `showDateRangePicker` يرجّع النهايةَ عند **منتصف ليل آخر يوم**،
      // والاستعلاماتُ تقارن `BETWEEN from AND to`. فأخذُ الناتج خاماً كان
      // يبتر اليومَ الأخيرَ كلَّه: مقيس ٢٬٠٠٠ ⇒ ١٬٤٠٠. نفسُ التطبيع الذي
      // تبدأ به الشاشةُ في السطر ٣٧ بالضبط.
      setState(() => _dateRange =
          DateRangeFilter.normalizeRange(picked.start, picked.end));
      _loadData();
    }
  }

  Future<void> _exportToExcel() async {
    final service = ref.read(excelServiceProvider);
    final isCategory = _tabController.index == 0;

    final data = isCategory ? _categoryData : _saleTypeData;
    if (data.isEmpty) {
      if (mounted) {
        AppToast.show(context, 'لا توجد بيانات للتصدير', type: ToastType.error);
      }
      return;
    }

    final path = await service.exportReport(
      periodFrom: _dateRange.start,
      periodTo: _dateRange.end,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
      title: isCategory
          ? 'تقرير المبيعات حسب التصنيف'
          : 'تقرير المبيعات حسب نوع البيع',
      headers: isCategory
          ? ['التصنيف', 'الكمية', 'القيمة']
          : ['نوع البيع', 'عدد الفواتير', 'القيمة'],
      rows: isCategory
          ? (_categoryData)
                .map<List<dynamic>>(
                  (item) => [item.category, item.quantity, item.total],
                )
                .toList()
          : (_saleTypeData)
                .map<List<dynamic>>(
                  (item) => [item.type, item.count, item.total],
                )
                .toList(),
    );

    if (path != null && mounted) {
      AppToast.show(
        context,
        'تم تصدير التقرير بنجاح: $path',
        type: ToastType.success,
      );
    }
  }

  Future<void> _printReport() async {
    final isCategory = _tabController.index == 0;

    // Convert typed rows back to Map for legacy print generator
    final List<Map<String, dynamic>> printData = isCategory
        ? _categoryData.map((r) => r.toMap()).toList()
        : _saleTypeData.map((r) => r.toMap()).toList();

    if (printData.isEmpty) {
      if (mounted) {
        AppToast.show(context, 'لا توجد بيانات للطباعة', type: ToastType.error);
      }
      return;
    }

    final totalSales = isCategory
        ? _categoryData.fold<double>(0, (sum, item) => sum + item.total)
        : _saleTypeData.fold<double>(0, (sum, item) => sum + item.total);

    // GAP-15: اسم الشركة من إعدادات العميل مش قيمة مكتوبة بالإيد. كان
    // مثبَّت على `MONEXIA Market` — اسم علامة تالتة على رأس تقرير العميل.
    final receiptSettings =
        await ref.read(settingsRepositoryProvider).getReceiptSettings();

    await InvoiceGenerator.printCategoryReport(
      categories: printData,
      totalSales: totalSales,
      isCategory: isCategory,
      fromDate: _dateRange.start,
      toDate: _dateRange.end,
      companyName: receiptSettings['companyName'] as String? ?? 'الشركة',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Spec 149 B12-5b (FIL-2): resolve the auth-level branch scope BEFORE any
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

    final dateFormat = DateFormat('yyyy/MM/dd');

    return reportScaffold(
      context: context,
      title: 'تقرير المبيعات حسب التصنيف',
      subtitle: 'المبيعاتُ حسبَ تصنيف الأصناف ونوعِ البيع',
      icon: PhosphorIconsBold.chartPieSlice,
      // ⚠️ **لا لونَ علامةٍ هنا**: هذه الشاشةُ لم تكن تكتب لوناً لـ`AppBar`
      //    فتتبع الثيم، وفرضُ لون العلامة عليها تبديلٌ في مسار UralCash.
      //    و`centerTitle: false` هو الافتراضُ على هذه المنصّة فسقط بلا أثر.
      brandedAppBar: false,
      // تبويباتُ التصميم لفرع PicPos، وشريطُ UralCash كما هو حرفاً بحرف.
      subHeader: PicPosReportTabs(
        controller: _tabController,
        tabs: const [
          (
            label: 'حسب تصنيف الأصناف (Categories)',
            icon: PhosphorIconsBold.tag,
            badge: null
          ),
          (
            label: 'حسب نوع البيع (Classification)',
            icon: PhosphorIconsBold.storefront,
            badge: null
          ),
        ],
      ),
      appBarBottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'حسب تصنيف الأصناف (Categories)'),
          Tab(text: 'حسب نوع البيع (Classification)'),
        ],
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textPrimary,
      ),
      actions: [
            buildReportExportAction(onExport: _exportToExcel),
            IconButton(
              onPressed: _printReport,
              icon: const Icon(PhosphorIconsBold.printer),
              tooltip: 'طباعة/PDF',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(PhosphorIconsBold.calendar, size: 18),
                label: Text(
                  '${dateFormat.format(_dateRange.start)} - ${dateFormat.format(_dateRange.end)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.primary,
                ),
              ),
            ),
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
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCategoryReport(),
                  PermissionGuard(
                    permission: PermissionCodes.reportsOrderType,
                    fallback: const Center(
                      child: Text('لا تملك صلاحية عرض تقرير المبيعات حسب نوع الطلب'),
                    ),
                    child: _buildSaleTypeReport(),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildCategoryReport() {
    final repo = ref.watch(reportingRepositoryProvider);
    return FutureBuilder<List<SalesByCategoryRow>>(
      future: repo.getSalesByCategory(
        from: _dateRange.start,
        to: _dateRange.end,
        allowedBranchIds: _allowedBranchIds,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('حدث خطأ: ${snapshot.error}'));
        }

        final data = snapshot.data ?? [];
        if (data.isEmpty) {
          return const Center(child: Text('لا توجد بيانات لهذه الفترة'));
        }

        double totalSales = data.fold(0, (sum, item) => sum + item.total);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummaryCard(
              'إجمالي المبيعات',
              totalSales,
              data.length,
              'تصنيف',
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('القسم / التصنيف')),
                  DataColumn(label: Text('الكمية المباعة')),
                  DataColumn(label: Text('القيمة الإجمالية')),
                  DataColumn(label: Text('النسبة')),
                ],
                rows: data.map((item) {
                  final amount = item.total;
                  final percentage = totalSales > 0
                      ? (amount / totalSales)
                      : 0.0;

                  return DataRow(
                    cells: [
                      DataCell(
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              color: AppColors.primary.withValues(
                                alpha: 0.5 + (percentage * 0.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              item.category,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(Text(item.quantity.toStringAsFixed(1))),
                      DataCell(
                        Text(
                          '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        ),
                      ),
                      DataCell(
                        Text('${(percentage * 100).toStringAsFixed(1)}%'),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSaleTypeReport() {
    final repo = ref.watch(reportingRepositoryProvider);
    return FutureBuilder<List<SalesBySaleTypeRow>>(
      future: repo.getSalesBySaleType(
        from: _dateRange.start,
        to: _dateRange.end,
        allowedBranchIds: _allowedBranchIds,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('حدث خطأ: ${snapshot.error}'));
        }

        final data = snapshot.data ?? [];
        if (data.isEmpty) {
          return const Center(child: Text('لا توجد بيانات لهذه الفترة'));
        }

        double totalSales = data.fold(0, (sum, item) => sum + item.total);

        // Map keys to readable names
        final Map<String, String> typeNames = {
          'default': 'داخلي (معرض)',
          'delivery': 'توصيل',
          'talabat': 'طلبات',
          'careem': 'كريم',
          'ashyae': 'أشيائي',
          'table': 'طاولات',
          'return': 'مرتجعات',
        };

        final Map<String, Color> typeColors = {
          'default': Colors.blueGrey,
          'delivery': Colors.teal,
          'talabat': Colors.orange,
          'careem': Colors.green,
          'ashyae': Colors.purple,
          'table': Colors.indigo,
          'return': AppColors.error,
        };

        final Map<String, IconData> typeIcons = {
          'default': PhosphorIconsBold.storefront,
          'delivery': PhosphorIconsBold.truck,
          'talabat': PhosphorIconsBold.motorcycle,
          'careem': PhosphorIconsBold.car,
          'ashyae': PhosphorIconsBold.package,
          'table': PhosphorIconsBold.armchair,
          'return': PhosphorIconsBold.arrowUUpLeft,
        };

        final dateFormat = DateFormat('MM/dd HH:mm');

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummaryCard(
              'إجمالي المبيعات',
              totalSales,
              data.fold<int>(0, (sum, item) => sum + item.count),
              'فاتورة',
            ),
            const SizedBox(height: 16),
            ...data.map((item) {
              final typeKey = item.type;
              final name = typeNames[typeKey] ?? typeKey;
              final amount = item.total;
              final count = item.count;
              final percentage = totalSales > 0 ? (amount / totalSales) : 0.0;
              final color = typeColors[typeKey] ?? AppColors.primary;
              final icon = typeIcons[typeKey] ?? PhosphorIconsBold.tag;

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Icon(icon, color: color),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        '$count فاتورة • ${(percentage * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage,
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                  trailing: Text(
                    '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  children: [
                    // Per-invoice detail table (loaded on expand)
                    FutureBuilder<List<SalesInvoiceSummaryRow>>(
                      future: repo.getSalesInvoicesBySaleType(
                        saleType: typeKey,
                        from: _dateRange.start,
                        to: _dateRange.end,
                        allowedBranchIds: _allowedBranchIds,
                      ),
                      builder: (context, detailSnap) {
                        if (detailSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final invoices = detailSnap.data ?? [];
                        if (invoices.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('لا توجد فواتير'),
                          );
                        }

                        // Summary row
                        final totalPaid = invoices.fold<double>(
                          0,
                          (s, i) => s + i.paid,
                        );
                        final totalRemaining = amount - totalPaid;

                        return Column(
                          children: [
                            // Summary bar
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              color: color.withValues(alpha: 0.05),
                              child: Row(
                                children: [
                                  _buildMiniStat(
                                    'الإجمالي',
                                    amount,
                                    color,
                                  ),
                                  _buildMiniStat(
                                    'المحصل',
                                    totalPaid,
                                    AppColors.success,
                                  ),
                                  _buildMiniStat(
                                    'المتبقي',
                                    totalRemaining,
                                    totalRemaining > 0
                                        ? AppColors.error
                                        : AppColors.success,
                                  ),
                                ],
                              ),
                            ),
                            // Invoice rows
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columnSpacing: 16,
                                dataRowMinHeight: 36,
                                dataRowMaxHeight: 40,
                                columns: const [
                                  DataColumn(label: Text('رقم الفاتورة')),
                                  DataColumn(label: Text('التاريخ')),
                                  DataColumn(label: Text('العميل')),
                                  DataColumn(label: Text('الإجمالي')),
                                  DataColumn(label: Text('المدفوع')),
                                  DataColumn(label: Text('المتبقي')),
                                  DataColumn(label: Text('الدفع')),
                                ],
                                rows: invoices.map((inv) {
                                  final invTotal = inv.total;
                                  final invPaid = inv.paid;
                                  final invRemaining =
                                      invTotal - invPaid;

                                  // Parse date (invoiceDate may be int unix or DateTime)
                                  String dateStr = '';
                                  final rawDate = inv.invoiceDate;
                                  if (rawDate is int) {
                                    dateStr = dateFormat.format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        rawDate * 1000,
                                      ),
                                    );
                                  } else if (rawDate is DateTime) {
                                    dateStr =
                                        dateFormat.format(rawDate);
                                  }

                                  // Payment method label — المصدرُ الواحد.
                                  // كانت خريطةً محلّيةً من سبعِ خرائطَ لا تتفق.
                                  final pm = inv.paymentMethod;

                                  return DataRow(
                                    cells: [
                                      DataCell(Text(
                                        inv.invoiceNumber,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      )),
                                      DataCell(Text(
                                        dateStr,
                                        style: const TextStyle(
                                            fontSize: 12),
                                      )),
                                      DataCell(Text(
                                        inv.customerName ?? '—',
                                        style: const TextStyle(
                                            fontSize: 12),
                                      )),
                                      DataCell(Text(
                                        invTotal
                                            .toStringAsFixed(AppConstants.decimalPlaces),
                                        style: const TextStyle(
                                            fontSize: 12),
                                      )),
                                      DataCell(Text(
                                        invPaid
                                            .toStringAsFixed(AppConstants.decimalPlaces),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color:
                                              AppColors.success,
                                        ),
                                      )),
                                      DataCell(Text(
                                        invRemaining
                                            .toStringAsFixed(AppConstants.decimalPlaces),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: invRemaining > 0
                                              ? AppColors.error
                                              : AppColors
                                                  .textMuted,
                                        ),
                                      )),
                                      DataCell(
                                        Container(
                                          padding:
                                              const EdgeInsets
                                                  .symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration:
                                              BoxDecoration(
                                            color: AppColors
                                                .info
                                                .withValues(
                                                    alpha:
                                                        0.1),
                                            borderRadius:
                                                BorderRadius
                                                    .circular(
                                                        4),
                                          ),
                                          child: Text(
                                            PaymentMethods.label(pm),
                                            style:
                                                const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildMiniStat(String label, double value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            '${value.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    double amount,
    int count,
    String countLabel,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  countLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}