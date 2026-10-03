// J4 (الجزء ٣) — قسيمةُ موظفٍ في مسيّر: الاستحقاقاتُ والاستقطاعاتُ بكمّيّاتها
// ومعدّلاتها، والصافي وحصّةُ المنشأة، والتسوياتُ اليدويّةُ بأسبابها (تُضاف
// وتُحذف ما دام المسيّرُ مسودةً أو مراجَعاً، لصاحب `hr_payroll_edit`)،
// وطباعتُها PDF.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_payroll.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import 'hr_form_kit.dart';
import 'payroll_run_dialogs.dart';

Future<void> openPayslip(BuildContext context, PayrollRun run, int lineId) =>
    showDialog<void>(
      context: context,
      builder: (_) => PayslipDialog(run: run, lineId: lineId),
    );

class PayslipDialog extends ConsumerWidget {
  const PayslipDialog({super.key, required this.run, required this.lineId});
  final PayrollRun run;
  final int lineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(payrollLinesProvider(run.id)).value;
    final line = lines?.where((l) => l.id == lineId).firstOrNull;
    final current = ref.watch(payrollRunProvider(run.id)).value ?? run;
    final canEdit =
        ref.watch(hasPermissionProvider(PermissionCodes.hrPayrollEdit)).value ??
            false;
    final editable = current.editable && canEdit;

    Future<void> adjust() async {
      if (line == null) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) =>
            PayrollAdjustmentDialog(runId: run.id, employeeId: line.employeeId),
      );
      if (saved == true) refreshPayroll(ref);
    }

    Future<void> remove(PayrollItem i) async {
      try {
        await ref.read(databaseProvider).removePayrollManualItem(i.id!,
            userId: ref.read(authProvider).user?.id);
        refreshPayroll(ref);
      } on HrException catch (e) {
        if (context.mounted) {
          AppToast.show(context, e.message, type: ToastType.error);
        }
      }
    }

    Widget items(String title, Iterable<PayrollItem> list, double total,
        Color color, String keyName) {
      return Container(
        key: Key(keyName),
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border.all(color: context.picposHairline),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13, color: color)),
            const SizedBox(height: 6),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('—', style: TextStyle(color: context.picposMuted)),
              ),
            for (final i in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(payItemLabel(i),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: context.picposText)),
                        if ((i.reason ?? '').isNotEmpty || i.quantity != null)
                          Text(
                            [
                              if (i.quantity != null &&
                                  i.code != PayItemCode.basic)
                                '× ${i.quantity!.toStringAsFixed(i.quantity! % 1 == 0 ? 0 : 2)}',
                              if ((i.reason ?? '').isNotEmpty) trData(i.reason),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: context.picposMuted),
                          ),
                      ],
                    ),
                  ),
                  Text(hrMoney(i.amount),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: context.picposText,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  if (editable && i.isManual)
                    IconButton(
                      key: Key('payslip_remove_${i.id}'),
                      tooltip: tr('حذف'),
                      visualDensity: VisualDensity.compact,
                      iconSize: 15,
                      onPressed: () => remove(i),
                      icon: Icon(PhosphorIconsBold.trash,
                          color: AppColors.statusError(context)),
                    ),
                ]),
              ),
            Divider(color: context.picposHairline),
            Row(children: [
              Expanded(
                child: Text(tr('المجموع'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text(hrMoney(total),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ],
        ),
      );
    }

    return PicPosDialog(
      icon: PhosphorIconsBold.receipt,
      title: line?.employeeName ?? tr('قسيمة راتب'),
      subtitle: tr('قسيمة راتب {p0}', {'p0': run.period}),
      width: 820,
      onCancel: () => Navigator.of(context).pop(),
      cancelLabel: tr('إغلاق'),
      secondaryActions: [
        if (editable)
          PicPosDialogAction(
            label: tr('تسوية'),
            icon: PhosphorIconsBold.pencilSimpleLine,
            onPressed: adjust,
          ),
      ],
      primaryAction: PicPosDialogAction(
        label: tr('طباعة القسيمة'),
        icon: PhosphorIconsBold.printer,
        onPressed: line == null
            ? null
            : () => printPayslips(context, ref, current, [line]),
      ),
      body: line == null
          ? [const Center(child: CircularProgressIndicator())]
          : [
              Wrap(spacing: 10, runSpacing: 8, children: [
                HrPill(
                  label: payrollStatusLabel(current.status),
                  color: payrollStatusColor(context, current.status),
                ),
                HrPill(
                  label: line.isPaid ? tr('مصروف') : tr('غير مصروف'),
                  color: line.isPaid
                      ? AppColors.statusSuccess(context)
                      : context.picposMuted,
                ),
                Text(
                  tr('أيام الاستحقاق: {p0} من {p1}', {
                    'p0': line.paidDays
                        .toStringAsFixed(line.paidDays % 1 == 0 ? 0 : 2),
                    'p1': line.periodDays.toStringAsFixed(0),
                  }),
                  style: TextStyle(fontSize: 12, color: context.picposMuted),
                ),
              ]),
              LayoutBuilder(builder: (context, c) {
                final earnings = items(tr('الاستحقاقات'), line.earnings,
                    line.gross, AppColors.statusSuccess(context), 'payslip_earnings');
                final deductions = items(
                    tr('الاستقطاعات'),
                    line.deductionItems,
                    line.deductions,
                    AppColors.statusError(context),
                    'payslip_deductions');
                if (c.maxWidth < 560) {
                  return Column(children: [
                    earnings,
                    const SizedBox(height: 10),
                    deductions,
                  ]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: earnings),
                    const SizedBox(width: 12),
                    Expanded(child: deductions),
                  ],
                );
              }),
              PicPosDialogSummary(rows: [
                (label: tr('الإجمالي'), value: hrMoney(line.gross), color: null),
                (
                  label: tr('الخصومات'),
                  value: hrMoney(line.deductions),
                  color: AppColors.statusError(context),
                ),
                (
                  label: tr('صافي الراتب'),
                  value: hrMoney(line.net),
                  color: AppColors.statusSuccess(context),
                ),
                if (line.employerCost > 0)
                  (
                    label: tr('حصة المنشأة'),
                    value: hrMoney(line.employerCost),
                    color: null,
                  ),
              ]),
            ],
    );
  }
}
