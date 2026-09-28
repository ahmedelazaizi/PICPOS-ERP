// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' as intl;
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../data/providers/providers.dart';
import '../../../services/printing/report_pdf_generator.dart';
import '../../widgets/compact_date_picker.dart';
import '../../widgets/branch_warehouse_filter.dart';
import '../../widgets/report_components.dart' show DateRangeFilter;
import '../../widgets/report_filter_bar.dart';
import 'report_export_guard.dart';

class TaxReportScreen extends ConsumerStatefulWidget {
  const TaxReportScreen({super.key});

  @override
  ConsumerState<TaxReportScreen> createState() => _TaxReportScreenState();
}

class _TaxReportScreenState extends ConsumerState<TaxReportScreen> {
  // Spec 065: defaults are full-day-inclusive (D3-006).
  DateTime _fromDate = DateRangeFilter.normalizeStart(
      DateTime.now().subtract(const Duration(days: 30)));
  DateTime _toDate = DateRangeFilter.normalizeEnd(DateTime.now());
  bool _isLoading = false;
  Map<String, dynamic>? _data;
  List<SalesInvoiceData> _salesInvoices = [];
  List<PurchaseInvoiceWithSupplier> _purchaseInvoices = [];

  /// البند 8 — per-line tax rows, grouped by invoice id for the drill-down.
  Map<int, List<Map<String, dynamic>>> _salesTaxByInvoice = {};

  /// البند 8 — taxable base + tax per distinct rate (VAT-return shape).
  List<Map<String, dynamic>> _salesTaxRateBuckets = [];
  int? _selectedCostCenterId; // null = all cost centers
  int? _selectedRegionId; // Feature 017 — region filter wired to data load
  int? _selectedBranchId;
  int? _selectedWarehouseId;
  Set<int>? _branchWarehouseIds;
  Set<int>? _regionWarehouseIds;

  // FIL-2 (spec 149 B12): the logged-in user's branch authorization scope.
  // null = full access (admin/financial-manager/mirror) → no restriction.
  // Mirrors financial_statements_screen.dart's B12-1 wiring. Set both here
  // (build()) AND at the top of _loadData() — unlike financial_statements_
  // screen's declarative per-tab FutureBuilder, this screen fetches
  // imperatively from initState()'s microtask, which can run before build()
  // ever resolves branchScopeProvider; _loadData() re-resolves the scope
  // itself so the very first fetch can never race ahead unrestricted.
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
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير الضريبة');
      } catch (_) {}
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // FIL-2 (spec 149 B12): resolve the auth-level branch scope BEFORE the
      // report query runs, on every call. _loadData is invoked both from
      // initState's microtask and from the filter-bar onChanged callbacks,
      // so re-resolving here (rather than relying solely on build()'s
      // ref.watch) closes the race where the FIRST load could otherwise run
      // before build() ever observes branchScopeProvider.
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final repo = ref.read(reportingRepositoryProvider);
      // Feature 017 — resolve filter scope: warehouse > branch > region.
      final warehouseIds = _selectedWarehouseId != null
          ? [_selectedWarehouseId!]
          : _branchWarehouseIds?.toList() ?? _regionWarehouseIds?.toList();

      final data = await repo.getTaxReport(
        _fromDate,
        _toDate,
        costCenterId: _selectedCostCenterId,
        warehouseIds: warehouseIds,
        branchId: _selectedBranchId,
        allowedBranchIds: _allowedBranchIds,
      );
      
      // H8 · البطاقةُ فوق تقرأ من **الأستاذ** فتستبعد الملغى وتحمل عكسَ
      // ضريبة المرتجع سالباً. فالقائمةُ التفصيلية لازم تطابقها: تستبعد
      // الملغى، وتُبقي المرتجعَ لكن **مطروحاً** (اقرا `taxSigned` تحت).
      // بلا هذا كانت تجمع الملغى وتجمع المرتجعَ موجباً: ٢٥٥ بدل ١٥٠.
      final salesList = await repo.getSalesByDateRange(
        _fromDate,
        _toDate,
        warehouseIds: warehouseIds,
        costCenterId: _selectedCostCenterId,
        allowedBranchIds: _allowedBranchIds,
        excludeVoided: true,
      );

      final purchasesList = await repo.getPurchasesWithSupplierByDateRange(
        _fromDate,
        _toDate,
        warehouseIds: warehouseIds,
        costCenterId: _selectedCostCenterId,
        allowedBranchIds: _allowedBranchIds,
      );

      // البند 8 — per-item tax detail + rate buckets. Same filter set as the
      // summary above so the drill-down reconciles with the cards.
      final taxDetail = await repo.getSalesTaxDetailByItem(
        _fromDate,
        _toDate,
        costCenterId: _selectedCostCenterId,
        warehouseIds: warehouseIds,
        branchId: _selectedBranchId,
        allowedBranchIds: _allowedBranchIds,
      );
      final rateBuckets = await repo.getSalesTaxByRate(
        _fromDate,
        _toDate,
        costCenterId: _selectedCostCenterId,
        warehouseIds: warehouseIds,
        branchId: _selectedBranchId,
        allowedBranchIds: _allowedBranchIds,
      );
      final grouped = <int, List<Map<String, dynamic>>>{};
      for (final row in taxDetail) {
        final id = (row['invoiceId'] as num).toInt();
        (grouped[id] ??= []).add(row);
      }

      if (mounted) {
        setState(() {
          _data = data;
          _salesInvoices = salesList;
          _purchaseInvoices = purchasesList;
          _salesTaxByInvoice = grouped;
          _salesTaxRateBuckets = rateBuckets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
          body: Center(child: Text('تعذر تحديد صلاحيات الفرع: ${scopeAsync.error}')),
        ),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          // Spec 057: explicit back leading — AppBar's automaticallyImplyLeading
          // does not always show the right glyph under custom RTL Directionality.
          leading: Navigator.canPop(context)
              ? IconButton(
                  tooltip: 'رجوع',
                  icon: const Icon(PhosphorIconsBold.caretRight, size: 20),
                  onPressed: () => Navigator.pop(context),
                )
              : null,
          title: const Text('تقرير ضريبة المبيعات'),
          actions: [
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
                      hint: const Text('مركز التكلفة', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      dropdownColor: AppColors.primary,
                      iconEnabledColor: Colors.white70,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
                        ...centers.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => setState(() { _selectedCostCenterId = v; _loadData(); }),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.printer),
              onPressed: _printTaxReport,
              tooltip: 'طباعة/PDF',
            ),
            buildReportExportAction(onExport: _exportToExcel),
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

                          'Region $v selected but no warehouses linked. '

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
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: ShimmerLoading.list(itemCount: 6),
                    )
                  : _data == null
                      ? const Center(child: Text('لا توجد بيانات'))
                      : _buildReport(_data!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport(Map<String, dynamic> data) {
    final currencyFormat = intl.NumberFormat.currency(
      symbol: ' ',
      decimalDigits: AppConstants.decimalPlaces,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodCard(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'ضريبة المبيعات (مخرجات)',
                  data['salesTax'],
                  AppColors.success,
                  PhosphorIconsBold.trendUp,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  'ضريبة المشتريات (مدخلات)',
                  data['purchaseTax'],
                  AppColors.error,
                  PhosphorIconsBold.trendDown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildNetTaxCard(data['netTax'], currencyFormat),
          const SizedBox(height: 32),
          const Text(
            'التفاصيل الضريبية',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            'إجمالي المبيعات (بدون الضريبة)',
            data['salesTotalExclTax'],
            currencyFormat,
          ),
          _buildDetailRow(
            'إجمالي المشتريات (بدون الضريبة)',
            data['purchaseTotalExclTax'],
            currencyFormat,
          ),
          const Divider(height: 32),
          _buildDetailRow(
            'صافي المبيعات قبل الضرائب',
            data['salesTotalExclTax'] - data['purchaseTotalExclTax'],
            currencyFormat,
            isBold: true,
          ),
          const SizedBox(height: 32),
          // البند 8 — rate buckets (VAT-return shape) above the drill-down.
          if (_salesTaxRateBuckets.isNotEmpty) ...[
            const Text('ملخص الضريبة حسب النسبة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border)),
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('النسبة', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('الوعاء الخاضع', style: TextStyle(fontSize: 12)), numeric: true),
                    DataColumn(label: Text('الضريبة', style: TextStyle(fontSize: 12)), numeric: true),
                  ],
                  rows: _salesTaxRateBuckets.map((b) {
                    final rate = (b['taxRate'] as num).toDouble();
                    return DataRow(cells: [
                      DataCell(Text(
                          rate == 0 ? 'معفي / صفري' : '${_fmtRate(rate)}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                      DataCell(Text(currencyFormat.format((b['taxableBase'] as num).toDouble()),
                          style: const TextStyle(fontSize: 12))),
                      DataCell(Text(currencyFormat.format((b['taxAmount'] as num).toDouble()),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          // Invoice-Level Sales Tax Detail — البند 8: expandable per invoice so
          // each LINE shows its own rate, taxable base and tax. Previously this
          // was a flat header table with one lump tax figure and no rate.
          if (_salesInvoices.isNotEmpty) ...[
            const Text('تفاصيل ضريبة المبيعات (مخرجات)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: _salesInvoices.where((s) => s.tax > 0).map((s) {
                    // H8 · مستندُ المرتجع يحمل ضريبتَه **موجبةً** في صفّه،
                    // وهو في الحقيقة عكسٌ لضريبة مخرجاتٍ سبق تحصيلُها.
                    // فيُعرض مطروحاً كي يجمع العمودُ على ما تقوله البطاقة
                    // (وهي تقرأ من الأستاذ حيث العكسُ مقيَّدٌ مديناً).
                    final isReturn = s.saleType == 'return';
                    final taxSigned = isReturn ? -s.tax : s.tax;
                    final totalSigned = isReturn ? -s.total : s.total;
                    final lines = _salesTaxByInvoice[s.id] ?? const [];
                    final lineTaxSum = lines.fold<double>(
                        0, (sum, l) => sum + ((l['taxAmount'] as num?)?.toDouble() ?? 0));
                    // Spec 151 guarantees SUM(line.tax) == header.tax for rows
                    // written after it; legacy rows predate the guarantee, so
                    // surface a mismatch instead of silently showing a total
                    // the lines below don't add up to.
                    final mismatch = lines.isNotEmpty && (lineTaxSum - s.tax).abs() > 0.01;
                    return ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Row(
                        children: [
                          Expanded(flex: 3, child: Text(s.invoiceNumber, style: const TextStyle(fontSize: 12))),
                          Expanded(flex: 2, child: Text(intl.DateFormat('yyyy-MM-dd').format(s.invoiceDate), style: const TextStyle(fontSize: 12))),
                          Expanded(flex: 2, child: Text(currencyFormat.format(totalSigned), style: const TextStyle(fontSize: 12), textAlign: TextAlign.end)),
                          Expanded(
                            flex: 2,
                            child: Text(currencyFormat.format(taxSigned),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isReturn
                                        ? AppColors.error
                                        : AppColors.success),
                                textAlign: TextAlign.end),
                          ),
                          if (mismatch)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(start: 4),
                              child: Tooltip(
                                message: 'مجموع ضرائب الأصناف لا يساوي ضريبة الفاتورة',
                                child: Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                              ),
                            ),
                        ],
                      ),
                      children: [
                        if (lines.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('لا توجد أصناف مسجّلة لهذه الفاتورة',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: DataTable(
                              columnSpacing: 16,
                              headingRowHeight: 34,
                              dataRowMinHeight: 30,
                              dataRowMaxHeight: 38,
                              columns: const [
                                DataColumn(label: Text('الصنف', style: TextStyle(fontSize: 11))),
                                DataColumn(label: Text('الكمية', style: TextStyle(fontSize: 11)), numeric: true),
                                DataColumn(label: Text('الوعاء الضريبي', style: TextStyle(fontSize: 11)), numeric: true),
                                DataColumn(label: Text('النسبة', style: TextStyle(fontSize: 11)), numeric: true),
                                DataColumn(label: Text('قيمة الضريبة', style: TextStyle(fontSize: 11)), numeric: true),
                              ],
                              rows: lines.map((l) {
                                final rate = (l['taxRate'] as num?)?.toDouble() ?? 0;
                                return DataRow(cells: [
                                  DataCell(Text('${l['productName'] ?? '—'}', style: const TextStyle(fontSize: 11))),
                                  DataCell(Text('${(l['quantity'] as num?)?.toDouble() ?? 0}', style: const TextStyle(fontSize: 11))),
                                  DataCell(Text(currencyFormat.format((l['taxableBase'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontSize: 11))),
                                  DataCell(Text(rate == 0 ? 'معفي' : '${_fmtRate(rate)}%',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  DataCell(Text(currencyFormat.format((l['taxAmount'] as num?)?.toDouble() ?? 0),
                                      style: const TextStyle(fontSize: 11, color: AppColors.success))),
                                ]);
                              }).toList(),
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Invoice-Level Purchase Tax Detail
          if (_purchaseInvoices.isNotEmpty) ...[
            const Text('تفاصيل ضريبة المشتريات (مدخلات)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('رقم الفاتورة', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('المورد', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('التاريخ', style: TextStyle(fontSize: 12))),
                    DataColumn(label: Text('الإجمالي', style: TextStyle(fontSize: 12)), numeric: true),
                    DataColumn(label: Text('الضريبة', style: TextStyle(fontSize: 12)), numeric: true),
                  ],
                  rows: _purchaseInvoices.where((p) => p.invoice.tax > 0).map((p) {
                    return DataRow(cells: [
                      DataCell(Text(p.invoice.invoiceNumber, style: const TextStyle(fontSize: 12))),
                      DataCell(Text(p.supplierName ?? '-', style: const TextStyle(fontSize: 12))),
                      DataCell(Text(intl.DateFormat('yyyy-MM-dd').format(p.invoice.invoiceDate), style: const TextStyle(fontSize: 12))),
                      DataCell(Text(currencyFormat.format(p.invoice.total), style: const TextStyle(fontSize: 12))),
                      DataCell(Text(currencyFormat.format(p.invoice.tax), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.error))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.info, color: AppColors.info),
          const SizedBox(width: 12),
          Text(
            'الفترة من: ${intl.DateFormat('yyyy-MM-dd').format(_fromDate)} إلى: ${intl.DateFormat('yyyy-MM-dd').format(_toDate)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    double amount,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            intl.NumberFormat.currency(
              symbol: '',
              decimalDigits: AppConstants.decimalPlaces,
            ).format(amount),
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetTaxCard(double netTax, intl.NumberFormat format) {
    final isPayable = netTax > 0;
    final color = isPayable ? AppColors.warning : AppColors.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.8), color],
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'صافي الضريبة المستحقة للدفع',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Text(
            format.format(netTax.abs()),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPayable ? '(مستحق الدفع)' : '(رصيد لصالح المنشأة)',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  /// البند 8 — نسبة الضريبة كما يكتبها المحاسب: 16 لا 16.0، و2.5 تبقى 2.5.
  String _fmtRate(double rate) =>
      rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();

  Widget _buildDetailRow(
    String label,
    double value,
    intl.NumberFormat format, {
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            format.format(value),
            style: TextStyle(
              fontSize: 16,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  /// Print tax report as PDF
  Future<void> _printTaxReport() async {
    if (_data == null) {
      AppToast.show(context, 'لا توجد بيانات للطباعة', type: ToastType.error);
      return;
    }
    try {
      await ReportPdfGenerator.printGeneralLedger(
        accountName: 'تقرير ضريبة المبيعات',
        fromDate: _fromDate,
        toDate: _toDate,
        data: [
          {
            'entry_date': DateTime.now(),
            'entry_number': '',
            'description': '═══ ملخص الضريبة ═══',
            'debit': 0.0,
            'credit': 0.0,
            'balance': 0.0,
            'is_opening': true,
          },
          {
            'entry_date': DateTime.now(),
            'entry_number': '',
            'description': 'إجمالي المبيعات (بدون ضريبة)',
            'debit': (_data!['salesTotalExclTax'] as double?) ?? 0.0,
            'credit': 0.0,
            'balance': 0.0,
          },
          {
            'entry_date': DateTime.now(),
            'entry_number': '',
            'description': 'ضريبة المبيعات (مخرجات)',
            'debit': (_data!['salesTax'] as double?) ?? 0.0,
            'credit': 0.0,
            'balance': 0.0,
          },
          {
            'entry_date': DateTime.now(),
            'entry_number': '',
            'description': 'إجمالي المشتريات (بدون ضريبة)',
            'debit': 0.0,
            'credit': (_data!['purchaseTotalExclTax'] as double?) ?? 0.0,
            'balance': 0.0,
          },
          {
            'entry_date': DateTime.now(),
            'entry_number': '',
            'description': 'ضريبة المشتريات (مدخلات)',
            'debit': 0.0,
            'credit': (_data!['purchaseTax'] as double?) ?? 0.0,
            'balance': 0.0,
          },
          {
            'entry_date': DateTime.now(),
            'entry_number': '',
            'description': '═══ صافي الضريبة المستحقة ═══',
            'debit': 0.0,
            'credit': 0.0,
            'balance': (_data!['netTax'] as double?) ?? 0.0,
            'is_opening': true,
          },
        ],
      );
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await CompactDatePicker.showCompactRange(
      context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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

  Future<void> _exportToExcel() async {
    if (_data == null) {
      AppToast.show(context, 'لا توجد بيانات للتصدير', type: ToastType.error);
      return;
    }
    final service = ref.read(excelServiceProvider);
    final path = await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
      title: 'تقرير ضريبة المبيعات',
      headers: [
        'البند',
        'القيمة',
      ],
      rows: [
        // البند 8 — stamp the filter context. A file exported for one branch
        // used to be indistinguishable from a company-wide one: only the date
        // range appeared, and only on screen.
        ['الفترة', '${intl.DateFormat('yyyy-MM-dd').format(_fromDate)} → '
            '${intl.DateFormat('yyyy-MM-dd').format(_toDate)}'],
        ['الفرع', _selectedBranchId?.toString() ?? 'الكل'],
        ['المخزن', _selectedWarehouseId?.toString() ?? 'الكل'],
        ['مركز التكلفة', _selectedCostCenterId?.toString() ?? 'الكل'],
        const ['', ''],
        ['إجمالي المبيعات (بدون ضريبة)', _data!['salesTotalExclTax']],
        ['ضريبة المبيعات (مخرجات)', _data!['salesTax']],
        ['إجمالي المشتريات (بدون ضريبة)', _data!['purchaseTotalExclTax']],
        ['ضريبة المشتريات (مدخلات)', _data!['purchaseTax']],
        ['صافي الضريبة المستحقة', _data!['netTax']],
        const ['', ''],
        const ['═══ ملخص الضريبة حسب النسبة ═══', ''],
        for (final b in _salesTaxRateBuckets)
          [
            (b['taxRate'] as num).toDouble() == 0
                ? 'معفي / صفري — وعاء'
                : '${_fmtRate((b['taxRate'] as num).toDouble())}% — وعاء',
            b['taxableBase'],
          ],
        const ['', ''],
        const ['═══ تفصيل الضريبة لكل صنف ═══', ''],
        for (final entry in _salesTaxByInvoice.entries)
          for (final l in entry.value)
            [
              '${l['invoiceNumber']} · ${l['productName'] ?? '—'} · '
                  '${(l['taxRate'] as num?)?.toDouble() == 0 ? 'معفي' : '${_fmtRate((l['taxRate'] as num?)?.toDouble() ?? 0)}%'}',
              l['taxAmount'],
            ],
      ],
    );
    if (path != null && mounted) {
      // Was `'... \$path'` — the escaped `$` printed the literal text `$path`
      // instead of the file location, so the operator never learned where the
      // export landed.
      AppToast.show(context, 'تم تصدير التقرير بنجاح: $path', type: ToastType.success);
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportExport(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير الضريبة', 'Excel');
      } catch (_) {}
    }
  }
}