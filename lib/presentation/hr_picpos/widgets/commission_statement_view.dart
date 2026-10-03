// J4 (الجزء ٣) — كشفُ عمولة مندوبٍ لشهر: المبيعاتُ والمرتجعاتُ والصافي
// والتحصيلات، والهدفُ ونسبةُ تحقيقه والنسبةُ المطبَّقة، ثمّ المستنداتُ
// المختومةُ به واحداً واحداً بعمولة كلٍّ منها — وهو نفسُ ما يدخل المسيّر.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_payroll.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_labels.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class CommissionStatementView extends ConsumerStatefulWidget {
  const CommissionStatementView({super.key, this.employeeId});

  /// مندوبٌ ثابت (ملفّ الموظف)، وإلّا يُختار.
  final int? employeeId;

  @override
  ConsumerState<CommissionStatementView> createState() =>
      _CommissionStatementViewState();
}

class _CommissionStatementViewState
    extends ConsumerState<CommissionStatementView> {
  late int? _rep = widget.employeeId;
  late DateTime _month = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }();

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(hrProfilesProvider).value ?? const <EmployeeProfile>[];
    final plans =
        ref.watch(commissionPlansProvider).value ?? const <CommissionPlan>[];
    final withPlan = {for (final p in plans) p.employeeId};
    final reps = {
      for (final p in people)
        if (p.roleTags.contains(HrRoleTag.rep) || withPlan.contains(p.id))
          p.id!: p.name,
    };
    final rep = _rep;
    final st = rep == null
        ? null
        : ref
            .watch(commissionStatementProvider((rep, _month.year, _month.month)))
            .value;

    Widget stat(String label, String value, {Color? color, String? key}) =>
        Container(
          key: key == null ? null : Key(key),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: context.picposField,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: context.picposMuted)),
              Text(value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color ?? context.picposText,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        );
    String pct(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}%';

    return Column(children: [
      HrToolbar(children: [
        if (widget.employeeId == null)
          SizedBox(
            width: 280,
            child: HrDropdown<int>(
              fieldKey: const Key('commission_statement_rep'),
              label: tr('المندوب'),
              value: reps.containsKey(_rep) ? _rep : null,
              items: reps,
              onChanged: (v) => setState(() => _rep = v),
            ),
          ),
        HrStepper(
          keyPrefix: 'commission_month',
          label: hrPeriod(_month.year, _month.month),
          onPrev: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1)),
          onNext: () => setState(
              () => _month = DateTime(_month.year, _month.month + 1)),
        ),
      ]),
      if (st != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(spacing: 10, runSpacing: 8, children: [
              stat(tr('المبيعات'), hrMoney(st.sales)),
              stat(tr('المرتجعات'), hrMoney(st.returns),
                  color: AppColors.statusError(context)),
              stat(tr('صافي المبيعات'), hrMoney(st.netSales)),
              stat(tr('التحصيلات'), hrMoney(st.collections)),
              stat(tr('الهدف'), st.target == null ? '—' : hrMoney(st.target!)),
              stat(tr('نسبة التحقيق'),
                  st.achievementPct == null ? '—' : pct(st.achievementPct!)),
              stat(tr('النسبة المطبقة'), pct(st.appliedSalesRatePct)),
              stat(tr('العمولة'), hrMoney(st.total),
                  color: AppColors.statusSuccess(context),
                  key: 'commission_total'),
            ]),
          ),
        ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 820,
            emptyIcon: PhosphorIconsBold.fileText,
            emptyTitle: rep == null
                ? tr('اختر مندوباً')
                : (st?.plan == null
                    ? tr('لا خطة عمولة تسري على هذا المندوب')
                    : tr('لا مستندات مختومة بهذا المندوب في الشهر')),
            columns: [
              HrTableColumn(tr('التاريخ')),
              HrTableColumn(tr('المستند')),
              HrTableColumn(tr('الرقم')),
              HrTableColumn(tr('العميل'), flex: 3),
              HrTableColumn(tr('المبلغ')),
              HrTableColumn(tr('العمولة')),
            ],
            rows: [
              for (final (i, d) in (st?.docs ?? const <CommissionDoc>[]).indexed)
                HrTableRow(
                  key: Key('commission_doc_$i'),
                  cells: [
                    HrCellText(hrDate(d.date), number: true),
                    HrCellText(commissionDocKindLabel(d.kind)),
                    HrCellText(d.number, number: true),
                    HrCellText(trData(d.customerName ?? '—')),
                    HrCellText(hrMoney(d.amount),
                        number: true,
                        color: d.amount < 0
                            ? AppColors.statusError(context)
                            : null),
                    HrCellText(hrMoney(d.commission), number: true),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}
