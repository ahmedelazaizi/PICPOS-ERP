import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' as intl;

import 'package:ural_erp/core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

/// Feature 009 / T041 — Consumption + product-profitability report.
///
/// Two grids backed by the new DAO methods:
///   • [ConsumptionReportRow] — total qty + total cost per raw material.
///   • [ProfitabilityReportRow] — revenue − raw cost per finished product.
class ConsumptionReportScreen extends ConsumerStatefulWidget {
  const ConsumptionReportScreen({super.key});

  @override
  ConsumerState<ConsumptionReportScreen> createState() =>
      _ConsumptionReportScreenState();
}

class _ConsumptionReportScreenState
    extends ConsumerState<ConsumptionReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  int? _branchId;
  int? _terminalId;
  bool _loading = false;
  List<ConsumptionReportRow>? _consumption;
  List<ProfitabilityReportRow>? _profitability;

  // Spec 151 Track-3: the logged-in user's branch authorization scope — an
  // AUTH CAP distinct from the user-chosen `_branchId` dropdown. null = full
  // access (admin/financial-manager/mirror/userId=1). Resolved in BOTH build()
  // and _load() so no imperative fetch races ahead of the resolved scope.
  Set<int>? _allowedBranchIds;

  final _currency = intl.NumberFormat.currency(
    symbol: '',
    decimalDigits: AppConstants.decimalPlaces,
  );
  final _qty = intl.NumberFormat('#,##0.000');

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    Future.microtask(() async {
      // Feature 058: seed _branchId from the device's active branch BEFORE
      // the first data fetch (FR-001 + FR-002). Field name is _branchId here
      // (not _selectedBranchId) — see contracts/screen-scope-contract.md.
      if (_branchId == null) {
        final activeBranchId = await ref.read(activeBranchIdProvider.future);
        if (!mounted) return;
        if (activeBranchId != null) {
          setState(() => _branchId = activeBranchId);
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
      _load();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Spec 151 Track-3: resolve the auth-level branch scope BEFORE the query
      // runs, on every call (closes the initState-microtask race).
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final db = ref.read(databaseProvider);
      // Inclusive end-of-day so "today" returns sales made today.
      final endOfDay = DateTime(_to.year, _to.month, _to.day)
          .add(const Duration(days: 1));
      final consumption = await db.getConsumptionReport(
        fromDate: DateTime(_from.year, _from.month, _from.day),
        toDate: endOfDay,
        branchId: _branchId,
        terminalId: _terminalId,
        allowedBranchIds: _allowedBranchIds,
      );
      final profitability = await db.getProductProfitabilityReport(
        fromDate: DateTime(_from.year, _from.month, _from.day),
        toDate: endOfDay,
        allowedBranchIds: _allowedBranchIds,
      );
      if (!mounted) return;
      setState(() {
        _consumption = consumption;
        _profitability = profitability;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ فى تحميل التقرير: $e')),
      );
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
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
      _load();
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (scopeAsync.hasError) {
      return Scaffold(
        body: Center(child: Text('تعذر تحديد صلاحيات الفرع: ${scopeAsync.error}')),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.chartLine),
            SizedBox(width: 8),
            Text('تقرير استهلاك الخامات'),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'استهلاك الخامات'),
            Tab(text: 'ربحية المنتجات'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tab,
                    children: [
                      _buildConsumptionGrid(),
                      _buildProfitabilityGrid(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            icon: const Icon(PhosphorIconsBold.calendarBlank, size: 16),
            label: Text(
              '${_fmtDate(_from)} → ${_fmtDate(_to)}',
            ),
            onPressed: _pickRange,
          ),
          // Branch dropdown (driven by allBranchesProvider).
          Consumer(builder: (context, ref, _) {
            final branches = ref.watch(allBranchesProvider);
            return branches.when(
              data: (list) {
                if (list.length <= 1) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _branchId,
                      hint: const Text('كل الفروع'),
                      isDense: true,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('كل الفروع')),
                        for (final b in list)
                          DropdownMenuItem(value: b.id, child: Text(b.name)),
                      ],
                      onChanged: (v) {
                        setState(() => _branchId = v);
                        _load();
                      },
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            );
          }),
          // Terminal dropdown (loaded directly from pos_terminals).
          FutureBuilder<List<({int id, String name})>>(
            future: _loadTerminals(),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _terminalId,
                    hint: const Text('كل الماكينات'),
                    isDense: true,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('كل الماكينات')),
                      for (final t in snap.data!)
                        DropdownMenuItem(value: t.id, child: Text(t.name)),
                    ],
                    onChanged: (v) {
                      setState(() => _terminalId = v);
                      _load();
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowsClockwise),
            tooltip: 'تحديث',
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Future<List<({int id, String name})>> _loadTerminals() async {
    final db = ref.read(databaseProvider);
    final rows = await db.select(db.posTerminals).get();
    return rows.map((r) => (id: r.id, name: r.name)).toList();
  }

  Widget _buildConsumptionGrid() {
    final rows = _consumption ?? const [];
    if (rows.isEmpty) {
      return _emptyState('لا توجد بيانات استهلاك فى المدى المحدد');
    }
    final totalCost = rows.fold<double>(0.0, (s, r) => s + r.totalCost);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('الخامة')),
                  DataColumn(label: Text('الكمية المستهلكة'), numeric: true),
                  DataColumn(label: Text('التكلفة'), numeric: true),
                  DataColumn(label: Text('عدد الفواتير'), numeric: true),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [
                      DataCell(Text(r.name)),
                      DataCell(Text(_qty.format(r.totalQty))),
                      DataCell(Text(_currency.format(r.totalCost))),
                      DataCell(Text('${r.invoiceCount}')),
                    ]),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: AppColors.primary.withValues(alpha: 0.08),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('إجمالى التكلفة (${rows.length} خامة)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(_currency.format(totalCost),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.primary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfitabilityGrid() {
    final rows = _profitability ?? const [];
    if (rows.isEmpty) {
      return _emptyState(
          'لا توجد منتجات auto-deplete مبيعة فى المدى المحدد');
    }
    final totalRevenue = rows.fold<double>(0.0, (s, r) => s + r.revenue);
    final totalCost = rows.fold<double>(0.0, (s, r) => s + r.rawCost);
    final totalMargin = totalRevenue - totalCost;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('المنتج')),
                  DataColumn(label: Text('الكمية المباعة'), numeric: true),
                  DataColumn(label: Text('الإيراد'), numeric: true),
                  DataColumn(label: Text('تكلفة الخامات'), numeric: true),
                  DataColumn(label: Text('الربح'), numeric: true),
                  DataColumn(label: Text('الفواتير'), numeric: true),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [
                      DataCell(Text(r.name)),
                      DataCell(Text(_qty.format(r.qtySold))),
                      DataCell(Text(_currency.format(r.revenue))),
                      DataCell(Text(_currency.format(r.rawCost))),
                      DataCell(Text(
                        _currency.format(r.margin),
                        style: TextStyle(
                          color: r.margin >= 0
                              ? AppColors.success
                              : AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      )),
                      DataCell(Text('${r.invoiceCount}')),
                    ]),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: AppColors.primary.withValues(alpha: 0.08),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'إيراد ${_currency.format(totalRevenue)} − تكلفة ${_currency.format(totalCost)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'الربح: ${_currency.format(totalMargin)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color:
                      totalMargin >= 0 ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsLight.chartLine,
              size: 64, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
