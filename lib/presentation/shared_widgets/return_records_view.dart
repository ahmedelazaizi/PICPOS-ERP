// لبِناتُ سجلَّي المرتجعات (مبيعاتٍ ومشتريات) — J2 (قرارُ المالك).
//
// السجلّان توأمان في الشكل كسجلّ فواتير البيع وسجلّ المشتريات: شريطُ
// مرشِّحاتٍ (مدىً وبحث) ← جدولٌ بشرائح حالةٍ (الكلّ · مسودة · معتمد · ملغى)
// وصفِّ مجاميع ← شريطُ أفعالٍ للصفّ المختار. بناؤهما مرّتين نسختان تنحرفان
// بأوّل تعديل، فيعيشان هنا عرضاً خالصاً: لا قاعدةَ ولا مزوّد.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/i18n/tr.dart';
import '../../domain/models/return_draft.dart';
import '../picpos_shell/picpos_data_table.dart';
import '../picpos_shell/picpos_filter_strip.dart';
import '../picpos_shell/picpos_surface.dart';
import 'return_draft_support.dart';

final _money = NumberFormat('#,##0.${'0' * AppConstants.decimalPlaces}');
final _dateFmt = DateFormat('yyyy/MM/dd');

String returnRecordMoney(double v) => _money.format(v);
String returnRecordDate(DateTime d) => _dateFmt.format(d);

/// شرائحُ الحالة بترتيبها — `null` = «الكلّ».
const returnRecordStatusChips = <ReturnRecordStatus?>[
  null,
  ReturnRecordStatus.draft,
  ReturnRecordStatus.posted,
  ReturnRecordStatus.cancelled,
];

/// شريطُ المرشِّحات — مدىً بتاريخين وبحثٌ بالرقم/الطرف/السبب.
class ReturnRecordsFilterBar extends StatelessWidget {
  const ReturnRecordsFilterBar({
    super.key,
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
    required this.searchController,
    required this.onSearchChanged,
    required this.searchHint,
  });

  final DateTime from;
  final DateTime to;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String searchHint;

  @override
  Widget build(BuildContext context) {
    return PicPosFilterStrip(
      children: [
        PicPosFilterPill(
          key: const Key('return_records_from'),
          icon: PhosphorIconsBold.calendarBlank,
          label: tr('من {p0}', {'p0': _dateFmt.format(from)}),
          tabular: true,
          onTap: onPickFrom,
        ),
        PicPosFilterPill(
          key: const Key('return_records_to'),
          icon: PhosphorIconsBold.calendarCheck,
          label: tr('إلى {p0}', {'p0': _dateFmt.format(to)}),
          tabular: true,
          onTap: onPickTo,
        ),
        SizedBox(
          width: 260,
          child: TextField(
            key: const Key('return_records_search'),
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: searchHint,
              prefixIcon:
                  const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

/// جدولُ السجلّ — شرائحُ الحالة تُعَدّ من [rows] كلِّها (بعد المدى والبحث)،
/// والجدولُ يعرض ما يطابق [statusChip] وحدَه.
class ReturnRecordsTable extends StatelessWidget {
  const ReturnRecordsTable({
    super.key,
    required this.title,
    required this.rows,
    required this.statusChip,
    required this.onStatusChip,
    required this.selectedKey,
    required this.onSelect,
    required this.partyLabel,
    this.loading = false,
    this.emptyLabel,
  });

  /// نصُّ الجدول الفارغ — الافتراضيُّ «لا مرتجعاتٍ في هذا المدى».
  final String? emptyLabel;
  final String title;
  final List<ReturnRecordRow> rows;
  final int statusChip;
  final ValueChanged<int> onStatusChip;
  final String? selectedKey;
  final ValueChanged<String?> onSelect;
  final String partyLabel;
  final bool loading;

  /// الصفوفُ المعروضة بعد شريحة الحالة.
  static List<ReturnRecordRow> shownRows(
    List<ReturnRecordRow> rows,
    int statusChip,
  ) {
    final status = returnRecordStatusChips[statusChip];
    return status == null
        ? rows
        : [for (final r in rows) if (r.status == status) r];
  }

  @override
  Widget build(BuildContext context) {
    final shown = shownRows(rows, statusChip);
    final tax = shown.fold<double>(0, (s, r) => s + r.tax);
    final total = shown.fold<double>(0, (s, r) => s + r.total);
    const none = '—';
    return PicPosDataTable(
      title: title,
      subtitle: loading
          ? tr('جارٍ القراءة…')
          : tr('المعروضُ {p0} مرتجعاً', {'p0': shown.length}),
      chips: [
        for (var i = 0; i < returnRecordStatusChips.length; i++)
          PicPosTableChip(
            label: returnRecordStatusChips[i] == null
                ? tr('الكلّ')
                : returnStatusLabel(returnRecordStatusChips[i]!),
            count: '${shownRows(rows, i).length}',
            onTap: () => onStatusChip(i),
          ),
      ],
      selectedChip: statusChip,
      columns: [
        const PicPosTableColumn('', flex: 0.35),
        PicPosTableColumn(tr('الرقم'), flex: 1.1),
        PicPosTableColumn(tr('التاريخ'), flex: 0.95),
        PicPosTableColumn(tr('الفاتورة الأصل'), flex: 1.1),
        PicPosTableColumn(partyLabel, flex: 1.4),
        PicPosTableColumn(tr('التسوية'), flex: 1.0),
        PicPosTableColumn(tr('الضريبة'), flex: 0.9, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('الإجمالي'), flex: 1.0, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('الحالة'), flex: 0.85),
      ],
      totals: [
        '',
        tr('{p0} مرتجع', {'p0': shown.length}),
        '',
        '',
        '',
        '',
        _money.format(tax),
        _money.format(total),
        '',
      ],
      emptyLabel: emptyLabel ?? tr('لا مرتجعاتٍ في هذا المدى'),
      rows: [
        for (final r in shown)
          PicPosTableRow(
            selected: r.key == selectedKey,
            onTap: () => onSelect(r.key == selectedKey ? null : r.key),
            cells: [
              PicPosRadioCell(
                selected: r.key == selectedKey,
                onSelect: () => onSelect(r.key == selectedKey ? null : r.key),
              ),
              PicPosTextCell(r.number, bold: true),
              PicPosTextCell(_dateFmt.format(r.date)),
              PicPosTextCell(
                r.originalInvoiceNumber ?? none,
                sub: r.isFullReturn ? tr('ارتجاعٌ كامل') : tr('ارتجاعٌ جزئيّ'),
              ),
              PicPosTextCell(r.partyName ?? none, sub: r.reason),
              r.settlement == null
                  ? const PicPosTextCell(none)
                  : PicPosPillCell(
                      returnSettlementLabel(r.settlement),
                      returnSettlementTint(r.settlement),
                    ),
              PicPosTextCell(_money.format(r.tax)),
              PicPosTextCell(_money.format(r.total)),
              PicPosPillCell(
                returnStatusLabel(r.status),
                returnStatusTint(r.status),
              ),
            ],
          ),
      ],
    );
  }
}

/// شريطُ أفعال الصفّ المختار — عنوانُه ثمّ أزرارُه.
class ReturnRecordActionBar extends StatelessWidget {
  const ReturnRecordActionBar({
    super.key,
    required this.row,
    required this.actions,
  });

  final ReturnRecordRow row;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('return_record_actions'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${row.number} · ${returnStatusLabel(row.status)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// زرُّ فعلٍ في شريط الصفّ.
Widget returnRowActionButton({
  required Key key,
  required IconData icon,
  required String label,
  required VoidCallback? onPressed,
  Color? tint,
}) =>
    OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon, size: 15, color: onPressed == null ? null : tint),
      label: Text(label),
    );

/// حقلُ «تسمية: قيمة» في حوار عرض المرتجع.
class ReturnRecordField extends StatelessWidget {
  const ReturnRecordField(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 170,
              child: Text(label,
                  style: TextStyle(color: context.picposMuted, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// حقولُ صفّ السجلّ المشتركة في حوار العرض.
List<Widget> returnRecordFields(ReturnRecordRow r, {required String partyLabel}) => [
      ReturnRecordField(tr('الرقم'), r.number),
      ReturnRecordField(tr('الحالة'), returnStatusLabel(r.status)),
      ReturnRecordField(tr('التاريخ'), _dateFmt.format(r.date)),
      ReturnRecordField(tr('الفاتورةُ الأصل'), r.originalInvoiceNumber ?? '—'),
      ReturnRecordField(partyLabel, r.partyName ?? '—'),
      ReturnRecordField(tr('التسوية'), returnSettlementLabel(r.settlement)),
      ReturnRecordField(tr('الضريبة'), _money.format(r.tax)),
      ReturnRecordField(tr('الإجمالي'), _money.format(r.total)),
      if ((r.reason ?? '').isNotEmpty) ReturnRecordField(tr('السبب'), r.reason!),
    ];
