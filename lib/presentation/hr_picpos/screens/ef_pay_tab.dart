// J4 — تبويبُ «العقد والأجر»: مدّةُ العقد والتجربة، والراتبُ الأساسيّ
// والبدلات (ثابتٌ أو نسبةٌ من الأساسيّ)، وطريقةُ الصرف والحسابُ البنكيّ.
// تُخزَّن هنا ويقرؤها مسيّرُ الرواتب في الجزء ٣.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../widgets/hr_form_kit.dart';
import 'employee_file_form.dart';

class EfPayTab extends StatelessWidget {
  const EfPayTab({super.key, required this.form});
  final EmployeeFileForm form;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: form,
      builder: (context, _) {
        final contractEnded = form.contractEnd != null &&
            form.contractEnd!.isBefore(DateTime.now());
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            HrSection(
              title: tr('العقد'),
              icon: PhosphorIconsBold.fileText,
              child: HrFieldGrid(children: [
                HrDateField(
                  fieldKey: const Key('ef_contract_start'),
                  label: tr('بداية العقد'),
                  value: form.contractStart,
                  onChanged: (v) => form.set(() => form.contractStart = v),
                ),
                HrDateField(
                  fieldKey: const Key('ef_contract_end'),
                  label: tr('نهاية العقد'),
                  value: form.contractEnd,
                  warning: contractEnded
                      ? Theme.of(context).colorScheme.error
                      : null,
                  onChanged: (v) => form.set(() => form.contractEnd = v),
                ),
                HrDateField(
                  label: tr('نهاية فترة التجربة'),
                  value: form.probationEnd,
                  onChanged: (v) => form.set(() => form.probationEnd = v),
                ),
              ]),
            ),
            HrSection(
              title: tr('الراتب'),
              icon: PhosphorIconsBold.money,
              child: HrFieldGrid(children: [
                HrTextField(
                  fieldKey: const Key('ef_basic_salary'),
                  label: tr('الراتب الأساسي'),
                  controller: form.basicSalary,
                  number: true,
                  onChanged: (_) => form.set(() {}),
                ),
                HrDropdown<String>(
                  label: tr('أساس الراتب'),
                  value: form.salaryType,
                  items: {
                    'monthly': tr('شهري'),
                    'daily': tr('يومي'),
                    'hourly': tr('بالساعة'),
                  },
                  onChanged: (v) =>
                      form.set(() => form.salaryType = v ?? 'monthly'),
                ),
                HrTextField(
                  label: tr('ساعات العمل اليومية'),
                  controller: form.hoursPerDay,
                  number: true,
                  required: form.salaryType == 'hourly',
                ),
              ]),
            ),
            HrSection(
              title: tr('البدلات'),
              icon: PhosphorIconsBold.coins,
              actions: [
                OutlinedButton.icon(
                  key: const Key('ef_allowance_add'),
                  onPressed: form.addAllowance,
                  icon: const Icon(PhosphorIconsBold.plus, size: 16),
                  label: Text(tr('إضافة بدل')),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (form.allowances.isEmpty)
                    Text(tr('لا بدلات — أضف بدل سكن أو انتقال أو غيره.'),
                        style: TextStyle(
                            fontSize: 12.5, color: context.picposMuted)),
                  for (final (i, a) in form.allowances.indexed)
                    _AllowanceRowView(
                        key: ObjectKey(a), index: i, row: a, form: form),
                  if (form.allowances.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: context.picposField,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(tr('إجمالي البدلات الشهري'),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: context.picposMuted)),
                        ),
                        Text(
                          (form.allowancesTotal).toStringAsFixed(2),
                          key: const Key('ef_allowances_total'),
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: context.picposText,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            HrSection(
              title: tr('طريقة صرف الراتب'),
              icon: PhosphorIconsBold.bank,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(spacing: 8, children: [
                    for (final m in const [
                      SalaryPaymentMethod.cash,
                      SalaryPaymentMethod.bank,
                    ])
                      ChoiceChip(
                        key: Key('ef_pay_$m'),
                        label: Text(m == SalaryPaymentMethod.cash
                            ? tr('نقداً')
                            : tr('تحويل بنكي')),
                        selected: form.paymentMethod == m,
                        onSelected: (_) =>
                            form.set(() => form.paymentMethod = m),
                      ),
                  ]),
                  if (form.paymentMethod == SalaryPaymentMethod.bank) ...[
                    const SizedBox(height: 12),
                    HrFieldGrid(children: [
                      HrTextField(
                        label: tr('اسم البنك'),
                        controller: form.bankName,
                      ),
                      HrTextField(
                        fieldKey: const Key('ef_bank_account'),
                        label: tr('رقم الحساب'),
                        controller: form.bankAccount,
                        textDirection: TextDirection.ltr,
                      ),
                      HrTextField(
                        fieldKey: const Key('ef_iban'),
                        label: tr('رقم الآيبان (IBAN)'),
                        controller: form.iban,
                        textDirection: TextDirection.ltr,
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AllowanceRowView extends StatelessWidget {
  const _AllowanceRowView({
    super.key,
    required this.index,
    required this.row,
    required this.form,
  });
  final int index;
  final AllowanceRow row;
  final EmployeeFileForm form;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 3,
            child: HrTextField(
              fieldKey: Key('ef_allowance_name_$index'),
              label: tr('اسم البدل'),
              controller: row.name,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: HrTextField(
              fieldKey: Key('ef_allowance_amount_$index'),
              label: row.type == AllowanceType.percent
                  ? tr('النسبة ٪')
                  : tr('المبلغ'),
              controller: row.amount,
              number: true,
              onChanged: (_) => form.set(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: HrDropdown<String>(
              label: tr('النوع'),
              value: row.type,
              items: {
                AllowanceType.fixed: tr('مبلغ ثابت'),
                AllowanceType.percent: tr('نسبة من الأساسي'),
              },
              onChanged: (v) =>
                  form.set(() => row.type = v ?? AllowanceType.fixed),
            ),
          ),
          IconButton(
            tooltip: tr('حذف'),
            onPressed: () => form.removeAllowance(row),
            icon: Icon(PhosphorIconsBold.trash,
                size: 18, color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
    );
  }
}
