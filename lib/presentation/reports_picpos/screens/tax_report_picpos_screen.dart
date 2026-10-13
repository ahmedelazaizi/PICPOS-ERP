import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/data/providers/providers.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/branch_warehouse_filter.dart';
import '../../widgets/report_components.dart' show DateRangeFilter;

/// Pure accounting rule shared by the report UI and its focused test.
double salesTaxNet(double outputTax, double inputTax) => outputTax - inputTax;

/// PicPos fork of the sales-tax report. Data loading is the legacy query set;
/// only the presentation order and sizing are changed.
class TaxReportPicposScreen extends ConsumerStatefulWidget {
  const TaxReportPicposScreen({super.key});

  @override
  ConsumerState<TaxReportPicposScreen> createState() => _TaxReportPicposScreenState();
}

class _TaxReportPicposScreenState extends ConsumerState<TaxReportPicposScreen> {
  DateTime _from = DateRangeFilter.normalizeStart(DateTime.now().subtract(const Duration(days: 30)));
  DateTime _to = DateRangeFilter.normalizeEnd(DateTime.now());
  int? _regionId;
  int? _branchId;
  int? _warehouseId;
  int? _costCenterId;
  Set<int>? _branchWarehouses;
  Set<int>? _regionWarehouses;
  Set<int>? _allowedBranches;
  bool _loading = false;
  Map<String, dynamic>? _data;
  List<SalesInvoiceData> _sales = [];
  List<PurchaseInvoiceWithSupplier> _purchases = [];
  Map<int, List<Map<String, dynamic>>> _salesTaxByInvoice = {};
  List<Map<String, dynamic>> _rateBuckets = [];
  bool _explanationOpen = false;

  @override
  void initState() { super.initState(); Future.microtask(_load); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final scope = await ref.read(branchScopeProvider.future);
      final allowed = scope.hasFullAccess ? null : scope.allowedBranchIds;
      final repo = ref.read(reportingRepositoryProvider);
      final warehouseIds = _warehouseId != null ? [_warehouseId!] : (_branchWarehouses?.toList() ?? _regionWarehouses?.toList());
      final data = await repo.getTaxReport(_from, _to, costCenterId: _costCenterId, warehouseIds: warehouseIds, branchId: _branchId, allowedBranchIds: allowed);
      final sales = await repo.getSalesByDateRange(_from, _to, warehouseIds: warehouseIds, costCenterId: _costCenterId, allowedBranchIds: allowed, excludeVoided: true);
      final purchases = await repo.getPurchasesWithSupplierByDateRange(_from, _to, warehouseIds: warehouseIds, costCenterId: _costCenterId, allowedBranchIds: allowed);
      final details = await repo.getSalesTaxDetailByItem(_from, _to, costCenterId: _costCenterId, warehouseIds: warehouseIds, branchId: _branchId, allowedBranchIds: allowed);
      final buckets = await repo.getSalesTaxByRate(_from, _to, costCenterId: _costCenterId, warehouseIds: warehouseIds, branchId: _branchId, allowedBranchIds: allowed);
      final grouped = <int, List<Map<String, dynamic>>>{};
      for (final row in details) { (grouped[(row['invoiceId'] as num).toInt()] ??= []).add(row); }
      if (!mounted) return;
      setState(() { _allowedBranches = allowed; _data = data; _sales = sales; _purchases = purchases; _salesTaxByInvoice = grouped; _rateBuckets = buckets; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final output = _num(data?['salesTax']);
    final input = _num(data?['purchaseTax']);
    final net = _num(data?['netTax']);
    return PicPosScreenScaffold(
      title: tr('تقرير ضريبة المبيعات'),
      subtitle: tr('الضرائب المحصلة والمدفوعة وصافي الالتزام'),
      icon: PhosphorIconsBold.percent,
      headerActions: [
        IconButton(tooltip: tr('تحديث'), icon: const Icon(PhosphorIconsBold.arrowClockwise), onPressed: _load),
        IconButton(tooltip: tr('توضيح صافي الضريبة'), icon: const Icon(PhosphorIconsBold.info), onPressed: () => setState(() => _explanationOpen = !_explanationOpen)),
      ],
      subHeader: PicPosFilterStrip(children: [
        PicPosFilterPill(icon: PhosphorIconsBold.calendarBlank, label: '${_date(_from)} → ${_date(_to)}', tabular: true, onTap: _pickRange),
        BranchWarehouseFilterBar(
          selectedRegionId: _regionId, selectedBranchId: _branchId, selectedWarehouseId: _warehouseId,
          onRegionChanged: (v) async { _regionId = v; _branchId = null; _warehouseId = null; _branchWarehouses = null; _regionWarehouses = v == null ? null : (await BranchWarehouseFilterBar.getRegionWarehouseIds(ref, v)).toSet(); if (mounted) { setState(() {}); _load(); } },
          onBranchChanged: (v) async { _branchId = v; _warehouseId = null; _branchWarehouses = v == null ? null : (await BranchWarehouseFilterBar.getBranchWarehouseIds(ref, v)); if (mounted) { setState(() {}); _load(); } },
          onWarehouseChanged: (v) { setState(() => _warehouseId = v); _load(); },
        ),
      ]),
      bodyPadding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
      body: _loading ? const Center(child: CircularProgressIndicator()) : data == null ? Center(child: Text(tr('لا توجد بيانات'))) : ListView(children: [
        PicPosHubKpiRow(items: [
          PicPosHubKpi(icon: PhosphorIconsBold.trendUp, label: tr('ضريبة المخرجات'), value: _money(output), tint: AppColors.success, vs: tr('ضريبة المبيعات')),
          PicPosHubKpi(icon: PhosphorIconsBold.trendDown, label: tr('ضريبة المدخلات'), value: _money(input), tint: AppColors.error, vs: tr('ضريبة المشتريات')),
          PicPosHubKpi(icon: PhosphorIconsBold.calculator, label: tr('صافي الضريبة'), value: _money(net.abs()), tint: net > 0 ? AppColors.warning : AppColors.success, vs: net > 0 ? tr('مستحق الدفع') : tr('رصيد لصالح المنشأة')),
        ]),
        const SizedBox(height: 12),
        if (_explanationOpen) _explanation(output, input, net),
        _summaryDetails(data),
        if (_rateBuckets.isNotEmpty) _rateTable(),
        const SizedBox(height: 12),
        _detailSection(tr('تفاصيل ضريبة المبيعات (مخرجات)'), _sales.isEmpty ? const [] : _sales.where((s) => s.tax > 0).toList(), true),
        _purchaseSection(),
      ]),
    );
  }

  Widget _explanation(double output, double input, double net) => Padding(padding: const EdgeInsets.only(bottom: 12), child: PicPosContentCard(padding: const EdgeInsets.all(12), child: Text(tr('صافي الضريبة = ضريبة المخرجات − ضريبة المدخلات = {p0} − {p1} = {p2}', {'p0': _money(output), 'p1': _money(input), 'p2': _money(net)}), style: TextStyle(color: context.picposText))));

  Widget _summaryDetails(Map<String, dynamic> data) => PicPosContentCard(padding: const EdgeInsets.all(14), child: Column(children: [
    _line(tr('إجمالي المبيعات (بدون الضريبة)'), _money(_num(data['salesTotalExclTax']))),
    _line(tr('إجمالي المشتريات (بدون الضريبة)'), _money(_num(data['purchaseTotalExclTax']))),
    _line(tr('صافي المبيعات قبل الضرائب'), _money(_num(data['salesTotalExclTax']) - _num(data['purchaseTotalExclTax'])), bold: true),
  ]));

  Widget _rateTable() => Padding(padding: const EdgeInsets.only(top: 12), child: PicPosContentCard(padding: const EdgeInsets.all(8), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
    columns: [DataColumn(label: Text(tr('النسبة'))), DataColumn(label: Text(tr('الوعاء الخاضع'))), DataColumn(label: Text(tr('الضريبة')))],
    rows: [for (final b in _rateBuckets) DataRow(cells: [DataCell(Text(_rate(_num(b['taxRate'])))), DataCell(Text(_money(_num(b['taxableBase'])))), DataCell(Text(_money(_num(b['taxAmount']))))])],
  ))));

  Widget _detailSection(String title, List<SalesInvoiceData> rows, bool sales) => Padding(padding: const EdgeInsets.only(top: 12), child: PicPosContentCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Padding(padding: const EdgeInsets.all(14), child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))), if (rows.isEmpty) Padding(padding: const EdgeInsets.all(14), child: Text(tr('لا توجد بيانات'), style: TextStyle(color: context.picposMuted))) else SizedBox(height: rows.length * 70.0 + 4, child: ListView.builder(itemCount: rows.length, itemBuilder: (context, i) { final row = rows[i]; final returned = row.saleType == 'return'; final tax = returned ? -row.tax : row.tax; return ListTile(dense: true, leading: Icon(PhosphorIconsBold.receipt, color: returned ? AppColors.error : context.picposBrandInk), title: Text(row.invoiceNumber), subtitle: Text(intl.DateFormat('yyyy-MM-dd').format(row.invoiceDate)), trailing: Text(_money(tax), style: TextStyle(color: returned ? AppColors.error : AppColors.success, fontWeight: FontWeight.bold))); }))])));

  Widget _purchaseSection() => Padding(padding: const EdgeInsets.only(top: 12), child: PicPosContentCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Padding(padding: const EdgeInsets.all(14), child: Text(tr('تفاصيل ضريبة المشتريات (مدخلات)'), style: const TextStyle(fontWeight: FontWeight.bold))), if (_purchases.isEmpty) Padding(padding: const EdgeInsets.all(14), child: Text(tr('لا توجد بيانات'), style: TextStyle(color: context.picposMuted))) else SizedBox(height: _purchases.length * 62.0 + 4, child: ListView.builder(itemCount: _purchases.length, itemBuilder: (context, i) { final p = _purchases[i]; return ListTile(dense: true, leading: Icon(PhosphorIconsBold.shoppingCart, color: AppColors.error), title: Text(p.invoice.invoiceNumber), subtitle: Text(p.supplierName ?? tr('غير محدد')), trailing: Text(_money(p.invoice.tax), style: const TextStyle(fontWeight: FontWeight.bold))); }))])));

  Widget _line(String label, String value, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: context.picposText)), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: context.picposText))]));
  Future<void> _pickRange() async { final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)), initialDateRange: DateTimeRange(start: _from, end: _to)); if (picked != null) { setState(() { _from = DateRangeFilter.normalizeStart(picked.start); _to = DateRangeFilter.normalizeEnd(picked.end); }); _load(); } }
  double _num(Object? value) => value is num ? value.toDouble() : 0;
  String _money(double value) => '${value.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}';
  String _rate(double value) => value == value.roundToDouble() ? '${value.toInt()}%' : '$value%';
  String _date(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
