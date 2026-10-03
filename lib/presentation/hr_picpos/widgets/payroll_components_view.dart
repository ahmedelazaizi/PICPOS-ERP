// J4 (الجزء ٣) — بنودُ الراتب العامّة (لكلّ الموظفين أو لقسم): استحقاقٌ أو
// استقطاع، مبلغٌ ثابتٌ أو نسبةٌ من الأساسيّ أو لكلّ يوم/ساعة عملٍ أو صيغةٌ
// مبسّطة. بدلاتُ الموظف الخاصّة تبقى في ملفّه. الإدارةُ لـ`hr_payroll_edit`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_payroll.dart';
import '../../../domain/models/hr_payroll_engine.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class PayrollComponentsView extends ConsumerWidget {
  const PayrollComponentsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(salaryComponentsProvider).value ?? const <SalaryComponent>[];
    final canEdit =
        ref.watch(hasPermissionProvider(PermissionCodes.hrPayrollEdit)).value ??
            false;
    final departments = {
      for (final d in ref.watch(hrDepartmentsProvider).value ??
          const <HrDepartment>[])
        d.id: d.name,
    };
    Future<void> edit([SalaryComponent? c]) async {
      final saved = await showDialog<bool>(
          context: context, builder: (_) => _ComponentDialog(component: c));
      if (saved == true) refreshPayroll(ref);
    }

    String value(SalaryComponent c) => switch (c.calc) {
          ComponentCalc.percentBasic => '${hrMoney(c.amount)} %',
          ComponentCalc.formula => c.formula ?? '',
          _ => hrMoney(c.amount),
        };

    return Column(children: [
      HrToolbar(children: [
        FilledButton.icon(
          key: const Key('payroll_component_new'),
          onPressed: canEdit ? () => edit() : null,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: Text(tr('بند جديد')),
        ),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 900,
            emptyIcon: PhosphorIconsBold.stack,
            emptyTitle: tr('لا بنود راتب عامة بعد'),
            emptyHint: tr('بدلات كل موظف تُضبط في ملفه؛ هنا البنود العامة'),
            columns: [
              HrTableColumn(tr('البند'), flex: 4),
              HrTableColumn(tr('النوع')),
              HrTableColumn(tr('الاحتساب'), flex: 3),
              HrTableColumn(tr('القيمة'), flex: 3),
              HrTableColumn(tr('القسم')),
              HrTableColumn(tr('الحالة')),
              const HrTableColumn('', flex: 1),
            ],
            rows: [
              for (final c in items)
                HrTableRow(
                  key: Key('payroll_component_row_${c.id}'),
                  onTap: canEdit ? () => edit(c) : null,
                  cells: [
                    HrCellText(trData(c.name)),
                    HrCellText(payItemKindLabel(c.kind),
                        color: c.kind == PayItemKind.deduction
                            ? AppColors.statusError(context)
                            : AppColors.statusSuccess(context)),
                    HrCellText(componentCalcLabel(c.calc)),
                    HrCellText(value(c), number: true),
                    HrCellText(c.departmentId == null
                        ? tr('الكل')
                        : trData(departments[c.departmentId] ?? '')),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: HrPill(
                        label: c.isActive ? tr('فعال') : tr('موقوف'),
                        color: c.isActive
                            ? AppColors.statusSuccess(context)
                            : context.picposMuted,
                      ),
                    ),
                    if (canEdit)
                      IconButton(
                        tooltip: tr('حذف'),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        iconSize: 16,
                        onPressed: () async {
                          await ref.read(databaseProvider).deleteSalaryComponent(
                              c.id!,
                              userId: ref.read(authProvider).user?.id);
                          refreshPayroll(ref);
                        },
                        icon: Icon(PhosphorIconsBold.trash,
                            color: AppColors.statusError(context)),
                      )
                    else
                      const SizedBox(),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _ComponentDialog extends ConsumerStatefulWidget {
  const _ComponentDialog({this.component});
  final SalaryComponent? component;

  @override
  ConsumerState<_ComponentDialog> createState() => _ComponentDialogState();
}

class _ComponentDialogState extends ConsumerState<_ComponentDialog> {
  late final SalaryComponent? _c = widget.component;
  late final _name = TextEditingController(text: _c?.name);
  late final _nameEn = TextEditingController(text: _c?.nameEn);
  late final _amount =
      TextEditingController(text: _c == null ? '' : '${_c.amount}');
  late final _formula = TextEditingController(text: _c?.formula);
  late String _kind = _c?.kind ?? PayItemKind.earning;
  late String _calc = _c?.calc ?? ComponentCalc.fixed;
  late int? _department = _c?.departmentId;
  late bool _active = _c?.isActive ?? true;
  late bool _taxable = _c?.taxable ?? true;
  late bool _insurable = _c?.insurable ?? false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _nameEn, _amount, _formula]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).saveSalaryComponent(
            SalaryComponent(
              id: _c?.id,
              name: _name.text,
              nameEn: _nameEn.text,
              kind: _kind,
              calc: _calc,
              amount: double.tryParse(_amount.text.trim()) ?? 0,
              formula: _formula.text,
              departmentId: _department,
              isActive: _active,
              taxable: _taxable,
              insurable: _insurable,
            ),
            userId: ref.read(authProvider).user?.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on HrException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments =
        ref.watch(hrDepartmentsProvider).value ?? const <HrDepartment>[];
    final formula = _calc == ComponentCalc.formula;
    return PicPosDialog(
      icon: PhosphorIconsBold.stack,
      title: _c == null ? tr('بند راتب جديد') : tr('تعديل بند الراتب'),
      width: 660,
      onCancel: () => Navigator.of(context).pop(false),
      primaryAction: PicPosDialogAction(
        label: tr('حفظ'),
        icon: PhosphorIconsBold.floppyDisk,
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
      body: [
        if (_error != null)
          PicPosDialogBanner(
            icon: PhosphorIconsBold.warningCircle,
            text: _error!,
            color: AppColors.statusError(context),
          ),
        PicPosDialogRow(children: [
          HrTextField(
              fieldKey: const Key('payroll_component_name'),
              label: tr('الاسم'),
              controller: _name,
              required: true),
          HrTextField(
              fieldKey: const Key('payroll_component_name_en'),
              label: tr('الاسم بالإنجليزية'),
              controller: _nameEn,
              textDirection: TextDirection.ltr),
        ]),
        PicPosDialogRow(children: [
          HrDropdown<String>(
            fieldKey: const Key('payroll_component_kind'),
            label: tr('النوع'),
            value: _kind,
            items: {
              PayItemKind.earning: payItemKindLabel(PayItemKind.earning),
              PayItemKind.deduction: payItemKindLabel(PayItemKind.deduction),
            },
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          HrDropdown<String>(
            fieldKey: const Key('payroll_component_calc'),
            label: tr('الاحتساب'),
            value: _calc,
            items: {
              for (final c in ComponentCalc.values) c: componentCalcLabel(c),
            },
            onChanged: (v) => setState(() => _calc = v ?? _calc),
          ),
          HrDropdown<int>(
            fieldKey: const Key('payroll_component_department'),
            label: tr('القسم'),
            value: _department,
            emptyLabel: tr('كل الأقسام'),
            items: {for (final d in departments) d.id: trData(d.name)},
            onChanged: (v) => setState(() => _department = v),
          ),
        ]),
        if (formula) ...[
          HrTextField(
            fieldKey: const Key('payroll_component_formula'),
            label: tr('الصيغة'),
            controller: _formula,
            textDirection: TextDirection.ltr,
            hint: 'basic * 0.1 + worked_days * 5',
          ),
          Text(
            tr('المتغيرات: {p0}', {'p0': kPayFormulaVariables.join(' · ')}),
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 11.5, color: context.picposMuted),
          ),
        ] else
          HrTextField(
            fieldKey: const Key('payroll_component_amount'),
            label: _calc == ComponentCalc.percentBasic
                ? tr('النسبة %')
                : tr('المبلغ'),
            controller: _amount,
            number: true,
          ),
        Wrap(spacing: 16, children: [
          for (final (key, label, value, set) in [
            ('active', tr('فعال'), _active, (bool v) => _active = v),
            ('taxable', tr('خاضع للضريبة'), _taxable, (bool v) => _taxable = v),
            ('insurable', tr('خاضع للتأمينات'), _insurable,
                (bool v) => _insurable = v),
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                key: Key('payroll_component_$key'),
                value: value,
                onChanged: (v) => setState(() => set(v ?? false)),
              ),
              Text(label),
            ]),
        ]),
      ],
    );
  }
}
