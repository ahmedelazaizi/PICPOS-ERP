import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';

/// PicPos fork of the raw-material consumption report.
/// Queries, scope resolution, and calculations intentionally match the legacy screen.
class ConsumptionReportPicposScreen extends ConsumerStatefulWidget {
  const ConsumptionReportPicposScreen({super.key});

  @override
  ConsumerState<ConsumptionReportPicposScreen> createState() =>
      _ConsumptionReportPicposScreenState();
}

class _ConsumptionReportPicposScreenState
    extends ConsumerState<ConsumptionReportPicposScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  int? _branchId;
  int? _terminalId;
  bool _loading = false;
  List<ConsumptionReportRow>? _consumption;
  List<ProfitabilityReportRow>? _profitability;
  Set<int>? _allowedBranchIds;
  final _currency = intl.NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);
  final _qty = intl.NumberFormat('#,##0.000');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final scope = await ref.read(branchScopeProvider.future);
      final allowed = scope.hasFullAccess ? null : scope.allowedBranchIds;
      final end = DateTime(_to.year, _to.month, _to.day).add(const Duration(days: 1));
      final db = ref.read(databaseProvider);
      final consumption = await db.getConsumptionReport(
        fromDate: DateTime(_from.year, _from.month, _from.day),
        toDate: end,
        branchId: _branchId,
        terminalId: _terminalId,
        allowedBranchIds: allowed,
      );
      final profitability = await db.getProductProfitabilityReport(
        fromDate: DateTime(_from.year, _from.month, _from.day),
        toDate: end,
        allowedBranchIds: allowed,
      );
      if (!mounted) return;
      setState(() {
        _allowedBranchIds = allowed;
        _consumption = consumption;
        _profitability = profitability;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() { _from = picked.start; _to = picked.end; });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr('تقرير استهلاك الخامات'),
      subtitle: tr('استهلاك الخامات وربحية المنتجات'),
      icon: PhosphorIconsBold.chartLine,
      headerActions: [
        IconButton(
          tooltip: tr('تحديث'),
          icon: const Icon(PhosphorIconsBold.arrowClockwise),
          onPressed: _load,
        ),
      ],
      subHeader: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PicPosFilterStrip(children: [
            PicPosFilterPill(
              icon: PhosphorIconsBold.calendarBlank,
              label: '${_fmt(_from)} → ${_fmt(_to)}',
              tabular: true,
              onTap: _pickRange,
            ),
            _branchFilter(),
            _terminalFilter(),
          ]),
          TabBar(
            controller: _tabs,
            labelColor: context.picposBrandInk,
            tabs: [
              Tab(text: tr('استهلاك الخامات')),
              Tab(text: tr('ربحية المنتجات')),
            ],
          ),
        ],
      ),
      bodyPadding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_consumptionView(), _profitabilityView()],
            ),
    );
  }

  Widget _branchFilter() {
    return Consumer(builder: (context, ref, _) {
      final async = ref.watch(allBranchesProvider);
      return async.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (branches) {
          if (branches.length <= 1) return const SizedBox.shrink();
          return _dropdown<int?>(
            icon: PhosphorIconsBold.buildings,
            label: _branchId == null ? tr('كل الفروع') : tr('الفرع {p0}', {'p0': _branchId}),
            items: [null, ...branches.map((b) => b.id)],
            value: _branchId,
            text: (id) => id == null ? tr('كل الفروع') : id.toString(),
            onChanged: (v) { setState(() => _branchId = v); _load(); },
          );
        },
      );
    });
  }

  Widget _terminalFilter() => _dropdown<int?>(
        icon: PhosphorIconsBold.desktop,
        label: _terminalId == null ? tr('كل الماكينات') : _terminalId.toString(),
        items: const [null],
        value: _terminalId,
        text: (id) => id == null ? tr('كل الماكينات') : id.toString(),
        onChanged: (v) { setState(() => _terminalId = v); _load(); },
      );

  Widget _dropdown<T>({required IconData icon, required String label, required List<T> items, required T value, required String Function(T) text, required ValueChanged<T?> onChanged}) {
    return Container(
      height: 40,
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(color: context.picposField, borderRadius: BorderRadius.circular(11), border: Border.all(color: context.picposHairline)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.contains(value) ? value : null,
          hint: Row(children: [Icon(icon, size: 15, color: context.picposBrandInk), const SizedBox(width: 8), Text(label)]),
          icon: const Icon(Icons.expand_more),
          items: items.map((v) => DropdownMenuItem<T>(value: v, child: Text(text(v)))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _consumptionView() {
    final rows = _consumption ?? const <ConsumptionReportRow>[];
    final total = rows.fold<double>(0, (sum, row) => sum + row.totalCost);
    return _reportTable(
      rows.isEmpty,
      tr('لا توجد بيانات استهلاك في المدى المحدد'),
      PicPosHubKpiRow(items: [
        PicPosHubKpi(icon: PhosphorIconsBold.package, label: tr('الخامات'), value: rows.length.toString(), tint: AppColors.primary, vs: tr('في المدى المختار')),
        PicPosHubKpi(icon: PhosphorIconsBold.money, label: tr('إجمالي التكلفة'), value: _currency.format(total), tint: AppColors.warning, vs: AppConstants.currencySymbolEn),
      ]),
      PicPosContentCard(padding: const EdgeInsets.all(8), child: _table([
        tr('الخامة'), tr('الكمية المستهلكة'), tr('التكلفة'), tr('عدد الفواتير')
      ], [for (final row in rows) [row.name, _qty.format(row.totalQty), _currency.format(row.totalCost), row.invoiceCount.toString()]])),
    );
  }

  Widget _profitabilityView() {
    final rows = _profitability ?? const <ProfitabilityReportRow>[];
    final revenue = rows.fold<double>(0, (sum, row) => sum + row.revenue);
    final cost = rows.fold<double>(0, (sum, row) => sum + row.rawCost);
    return _reportTable(
      rows.isEmpty,
      tr('لا توجد منتجات auto-deplete مبيعة في المدى المحدد'),
      PicPosHubKpiRow(items: [
        PicPosHubKpi(icon: PhosphorIconsBold.receipt, label: tr('الإيراد'), value: _currency.format(revenue), tint: AppColors.primary, vs: AppConstants.currencySymbolEn),
        PicPosHubKpi(icon: PhosphorIconsBold.trendUp, label: tr('الربح'), value: _currency.format(revenue - cost), tint: revenue >= cost ? AppColors.success : AppColors.error, vs: tr('الإيراد ناقص التكلفة')),
      ]),
      PicPosContentCard(padding: const EdgeInsets.all(8), child: _table([
        tr('المنتج'), tr('الكمية المباعة'), tr('الإيراد'), tr('تكلفة الخامات'), tr('الربح'), tr('الفواتير')
      ], [for (final row in rows) [row.name, _qty.format(row.qtySold), _currency.format(row.revenue), _currency.format(row.rawCost), _currency.format(row.margin), row.invoiceCount.toString()]])), 
    );
  }

  Widget _reportTable(bool empty, String emptyText, Widget kpis, Widget table) {
    if (empty) return Center(child: Text(emptyText, style: TextStyle(color: context.picposMuted)));
    return ListView(children: [kpis, const SizedBox(height: 12), table]);
  }

  Widget _table(List<String> headers, List<List<String>> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [for (final h in headers) DataColumn(label: Text(h))],
        rows: [for (final row in rows) DataRow(cells: [for (final cell in row) DataCell(Text(cell, style: TextStyle(color: context.picposText)))])],
      ),
    );
  }

  String _fmt(DateTime date) => '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
}
