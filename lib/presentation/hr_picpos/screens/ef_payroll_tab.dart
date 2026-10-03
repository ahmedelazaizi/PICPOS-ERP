// J4 (الجزء ٣) — تبويبُ «الرواتب» في ملفّ الموظف: قسائمُه عبر المسيّرات
// (تُفتح وتُطبع)، وسلفُه ورصيدُها، وعمولةُ الشهر الجاري إن كان مندوباً.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_payroll.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import '../hr_picpos_providers.dart';
import '../widgets/advances_view.dart';
import '../widgets/hr_form_kit.dart';
import '../widgets/hr_table.dart';
import '../widgets/payslip_view.dart';

class EfPayrollTab extends ConsumerWidget {
  const EfPayrollTab({super.key, required this.employeeId});
  final int? employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = employeeId;
    if (id == null) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.money,
        title: tr('احفظ الموظف أولاً'),
        hint: tr('تظهر القسائم والسلف بعد حفظ ملف الموظف'),
      );
    }
    final slips =
        ref.watch(employeePayslipsProvider(id)).value ?? const <PayslipEntry>[];
    final profile = ref.watch(hrProfileProvider(id)).value;
    final now = DateTime.now();
    final isRep = profile?.roleTags.contains(HrRoleTag.rep) ?? false;
    final commission = isRep
        ? ref.watch(commissionStatementProvider((id, now.year, now.month))).value
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [
        if (commission != null && commission.plan != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: HrPill(
                key: const Key('ef_payroll_commission'),
                icon: PhosphorIconsBold.percent,
                label: tr('عمولة {p0}: {p1}', {
                  'p0': hrPeriod(now.year, now.month),
                  'p1': hrMoney(commission.total),
                }),
                color: AppColors.statusSuccess(context),
              ),
            ),
          ),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: HrTable(
              minWidth: 820,
              emptyIcon: PhosphorIconsBold.receipt,
              emptyTitle: tr('لا قسائم رواتب بعد'),
              columns: [
                HrTableColumn(tr('الشهر')),
                HrTableColumn(tr('الإجمالي')),
                HrTableColumn(tr('الخصومات')),
                HrTableColumn(tr('الصافي')),
                HrTableColumn(tr('المسير')),
                HrTableColumn(tr('الصرف')),
              ],
              rows: [
                for (final s in slips)
                  HrTableRow(
                    key: Key('ef_payslip_${s.line.id}'),
                    onTap: () => openPayslip(context, s.run, s.line.id),
                    cells: [
                      HrCellText(s.run.period, number: true),
                      HrCellText(hrMoney(s.line.gross), number: true),
                      HrCellText(hrMoney(s.line.deductions), number: true),
                      HrCellText(hrMoney(s.line.net), number: true),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: HrPill(
                          label: payrollStatusLabel(s.run.status),
                          color: payrollStatusColor(context, s.run.status),
                        ),
                      ),
                      HrCellText(
                          s.line.isPaid ? tr('مصروف') : tr('غير مصروف')),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(flex: 3, child: AdvancesView(employeeId: id, compact: true)),
      ]),
    );
  }
}
