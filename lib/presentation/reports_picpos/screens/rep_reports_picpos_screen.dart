// تقاريرُ المناديب — المرحلة و (بند المالك ١٢).
//
// ١ ملخّصُ مبيعات المندوب في فترة · ٢ تفصيلُ حركات المندوب · ٣ تغطيةُ
// المسارات وعملائها · ٤ مخزونُ سيارات المناديب.
//
// ⚠️ الأرقامُ من **الختم** (`rep_employee_id` / `route_id` على المستند لحظةَ
//    إنشائه) لا من مسار العميل الحاليّ — فإعادةُ التوزيع لا تغيّر الماضي.
//    والمبالغُ مبالغُ المستندات نفسِها التي رُحِّلت قيودُها.
// ⚠️ النطاق: المناديبُ المعروضون موظّفو فروع المستخدم وحدَهم
//    (‏`getAllEmployees` تحلّ `branchScopeProvider`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/distribution_model.dart';
import '../../../services/excel_export_helper.dart';
import '../../distribution_picpos/distribution_picpos_providers.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';

enum RepReportKind {
  summary('rep_summary'),
  detail('rep_detail'),
  coverage('rep_coverage'),
  vanStock('rep_van_stock');

  const RepReportKind(this.id);
  final String id;

  String get title => switch (this) {
        summary => tr('ملخص مبيعات المناديب'),
        detail => tr('تفصيل حركات المندوب'),
        coverage => tr('تغطية المسارات والعملاء'),
        vanStock => tr('مخزون سيارات المناديب'),
      };

  String get subtitle => switch (this) {
        summary => tr('الفواتير والمرتجعات والتحصيلات والمسلَّم لكل مندوب'),
        detail => tr('كل فاتورة ومرتجع وتحصيل وتسليم بالعميل والمسار'),
        coverage => tr('عملاء كل مسار وآخر زيارة وآخر فاتورة والأرصدة'),
        vanStock => tr('أرصدة الأصناف في مخزن سيارة كل مندوب'),
      };
}

/// جدولٌ واحدٌ يُعرَض ويُصدَّر **من نفس الصفوف**.
class _RepTable {
  const _RepTable(this.headers, this.rows, {this.totals});
  final List<String> headers;
  final List<List<Object?>> rows;
  final List<String>? totals;
}

class RepReportsPicposScreen extends ConsumerStatefulWidget {
  const RepReportsPicposScreen({super.key, this.kind = RepReportKind.summary});

  final RepReportKind kind;

  @override
  ConsumerState<RepReportsPicposScreen> createState() =>
      _RepReportsPicposScreenState();
}

class _RepReportsPicposScreenState
    extends ConsumerState<RepReportsPicposScreen> {
  late RepReportKind _kind = widget.kind;
  late DateTimeRange _range = () {
    final now = DateTime.now();
    return DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month, now.day));
  }();
  int? _repId;
  Future<_RepTable>? _future;
  final _fmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = _load());

  String _n(double v) => v.toStringAsFixed(2);
  String _d(DateTime? d) => d == null ? '—' : _fmt.format(d);

  String _kindLabel(String k) => switch (k) {
        'invoice' => tr('فاتورة'),
        'return' => tr('مرتجع'),
        'receipt' => tr('سند قبض'),
        'collection' => tr('تحصيل ميداني'),
        _ => tr('تسليم عهدة'),
      };

  Future<_RepTable> _load() async {
    final db = ref.read(databaseProvider);
    final scoped = {
      for (final e in await ref.read(dmEmployeesProvider.future)) e.id: e.name,
    };
    final from = _range.start;
    final to = _range.end.add(const Duration(days: 1));
    switch (_kind) {
      case RepReportKind.summary:
        final rows = (await db.repSalesSummary(from: from, to: to))
            .where((r) => scoped.containsKey(r.repEmployeeId))
            .toList();
        double sum(double Function(RepSalesSummaryRow) f) =>
            rows.fold(0.0, (s, r) => s + f(r));
        return _RepTable([
          tr('المندوب'),
          tr('عدد الفواتير'),
          tr('صافي المبيعات'),
          tr('المرتجعات'),
          tr('التحصيلات'),
          tr('تحصيل ميداني'),
          tr('المسلَّم للخزينة'),
        ], [
          for (final r in rows)
            [
              r.repName,
              r.invoiceCount,
              r.netSales,
              r.returns,
              r.collections,
              r.fieldCollections,
              r.handedOver,
            ],
        ], totals: [
          tr('الإجمالي'),
          '${rows.fold<int>(0, (s, r) => s + r.invoiceCount)}',
          _n(sum((r) => r.netSales)),
          _n(sum((r) => r.returns)),
          _n(sum((r) => r.collections)),
          _n(sum((r) => r.fieldCollections)),
          _n(sum((r) => r.handedOver)),
        ]);
      case RepReportKind.detail:
        final rows = (await db.repTransactionDetail(
                from: from, to: to, repEmployeeId: _repId))
            .where((r) => scoped.containsKey(r.repEmployeeId))
            .toList();
        return _RepTable([
          tr('التاريخ'),
          tr('النوع'),
          tr('الرقم'),
          tr('المندوب'),
          tr('العميل'),
          tr('المسار'),
          tr('المبلغ'),
          tr('المدفوع'),
          tr('المتبقي'),
        ], [
          for (final r in rows)
            [
              _d(r.date),
              _kindLabel(r.kind),
              r.number,
              scoped[r.repEmployeeId] ?? '—',
              r.customerName ?? '—',
              r.routeName ?? '—',
              r.amount,
              r.paid,
              r.remaining,
            ],
        ]);
      case RepReportKind.coverage:
        final rows = await db.routeCoverage();
        return _RepTable([
          tr('المسار'),
          tr('المنطقة'),
          tr('المندوب'),
          tr('الترتيب'),
          tr('العميل'),
          tr('آخر زيارة'),
          tr('آخر فاتورة'),
          tr('الرصيد'),
        ], [
          for (final r in rows)
            [
              r.routeName,
              r.areaName ?? '—',
              r.repName ?? '—',
              r.sequence,
              r.customerName,
              _d(r.lastVisitDate),
              _d(r.lastInvoiceDate),
              r.balance,
            ],
        ]);
      case RepReportKind.vanStock:
        final rows = (await db.vanStock(repEmployeeId: _repId))
            .where((r) => scoped.containsKey(r.repEmployeeId))
            .toList();
        return _RepTable([
          tr('المندوب'),
          tr('مخزن السيارة'),
          tr('الصنف'),
          tr('الكمية'),
          tr('متوسط التكلفة'),
          tr('القيمة'),
        ], [
          for (final r in rows)
            [
              r.repName,
              r.warehouseName,
              r.productName,
              r.quantity,
              r.averageCost,
              r.value,
            ],
        ], totals: [
          tr('الإجمالي'),
          '',
          '',
          '',
          '',
          _n(rows.fold(0.0, (s, r) => s + r.value)),
        ]);
    }
  }

  String _cell(Object? v) => switch (v) {
        double() => _n(v),
        null => '—',
        _ => '$v',
      };

  @override
  Widget build(BuildContext context) {
    final reps = ref.watch(dmEmployeesProvider).value ?? const <Employee>[];
    final needsPeriod =
        _kind == RepReportKind.summary || _kind == RepReportKind.detail;
    final needsRep =
        _kind == RepReportKind.detail || _kind == RepReportKind.vanStock;
    return PicPosScreenScaffold(
      title: _kind.title,
      subtitle: _kind.subtitle,
      icon: PhosphorIconsBold.truck,
      toolbar: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<RepReportKind>(
              key: const Key('rep_report_kind'),
              showSelectedIcon: false,
              segments: [
                for (final k in RepReportKind.values)
                  ButtonSegment(value: k, label: Text(k.title)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) {
                _kind = s.first;
                _reload();
              },
            ),
            if (needsPeriod)
              OutlinedButton.icon(
                key: const Key('rep_report_period'),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: _range,
                  );
                  if (picked != null) {
                    _range = picked;
                    _reload();
                  }
                },
                icon: const Icon(PhosphorIconsBold.calendar, size: 16),
                label: Text('${_d(_range.start)} — ${_d(_range.end)}'),
              ),
            if (needsRep)
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  initialValue: _repId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: tr('المندوب'), isDense: true),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('الكل'))),
                    for (final e in reps)
                      DropdownMenuItem(value: e.id, child: Text(e.name)),
                  ],
                  onChanged: (v) {
                    _repId = v;
                    _reload();
                  },
                ),
              ),
          ],
        ),
      ),
      body: FutureBuilder<_RepTable>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final table = snap.data;
          if (table == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              PicPosDataTable(
                title: _kind.title,
                subtitle: needsPeriod
                    ? '${_d(_range.start)} — ${_d(_range.end)}'
                    : null,
                emptyLabel: tr('لا بيانات لهذه الفترة'),
                minWidth: 900,
                headerAction: TextButton.icon(
                  key: const Key('rep_report_export'),
                  onPressed: () => ExcelExportHelper.export(
                    context: context,
                    title: _kind.title,
                    headers: table.headers,
                    rows: table.rows,
                    fromDate: needsPeriod ? _range.start : null,
                    toDate: needsPeriod ? _range.end : null,
                  ),
                  icon: const Icon(PhosphorIconsBold.fileXls,
                      size: 16, color: AppColors.success),
                  label: Text(tr('تصدير Excel'),
                      style: const TextStyle(color: AppColors.success)),
                ),
                columns: [
                  for (var i = 0; i < table.headers.length; i++)
                    PicPosTableColumn(
                      table.headers[i],
                      align: table.rows.isNotEmpty &&
                              table.rows.first[i] is num
                          ? PicPosCellAlign.end
                          : PicPosCellAlign.start,
                    ),
                ],
                totals: table.totals,
                rows: [
                  for (final r in table.rows)
                    PicPosTableRow(cells: [
                      for (final v in r) PicPosTextCell(_cell(v)),
                    ]),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
