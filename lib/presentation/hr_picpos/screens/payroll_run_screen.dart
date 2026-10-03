// J4 (الجزء ٣) — صفحةُ المسيّر: المجاميعُ وسطورُ الموظفين، وأفعالُ الدورة
// بحسب الحالة والصلاحيّة — إعادةُ الاحتساب والمراجعة (‏`hr_payroll_edit`)،
// الاعتماد (‏`hr_payroll_approve`)، الترحيلُ بقيدٍ واحدٍ والصرفُ والعكس
// (‏`hr_payroll_post`) — وطباعةُ القسائم وتصديرُ السجلّ إلى Excel.
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
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import '../widgets/hr_form_kit.dart';
import '../widgets/hr_table.dart';
import '../widgets/payroll_run_dialogs.dart';
import '../widgets/payslip_view.dart';

Future<void> openPayrollRun(BuildContext context, int runId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PayrollRunScreen(runId: runId),
    ));

class PayrollRunScreen extends ConsumerStatefulWidget {
  const PayrollRunScreen({super.key, required this.runId});
  final int runId;

  @override
  ConsumerState<PayrollRunScreen> createState() => _PayrollRunScreenState();
}

class _PayrollRunScreenState extends ConsumerState<PayrollRunScreen> {
  bool _busy = false;

  bool _can(String code) =>
      ref.watch(hasPermissionProvider(code)).value ?? false;

  Future<void> _act(Future<void> Function(int? userId) action,
      {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(authProvider).user?.id);
      refreshPayroll(ref);
      if (done != null && mounted) AppToast.show(context, done);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e is HrException ? e.message : '$e',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(payrollRunProvider(widget.runId)).value;
    final lines =
        ref.watch(payrollLinesProvider(widget.runId)).value ?? const <PayrollLine>[];
    final db = ref.read(databaseProvider);
    final canEdit = _can(PermissionCodes.hrPayrollEdit);
    final canApprove = _can(PermissionCodes.hrPayrollApprove);
    final canPost = _can(PermissionCodes.hrPayrollPost);
    if (run == null) {
      return PicPosScreenScaffold(
        title: tr('مسير الرواتب'),
        icon: PhosphorIconsBold.money,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final s = run.status;
    final legacy = run.legacy;
    final actions = <Widget>[
      if (!legacy && PayrollRunStatus.isEditable(s)) ...[
        OutlinedButton.icon(
          key: const Key('payroll_recompute'),
          onPressed: canEdit && !_busy
              ? () => _act((u) => db.recomputePayrollRun(run.id, userId: u),
                  done: tr('أعيد احتساب المسير'))
              : null,
          icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 16),
          label: Text(tr('إعادة الاحتساب')),
        ),
      ],
      if (!legacy && s == PayrollRunStatus.draft) ...[
        FilledButton.icon(
          key: const Key('payroll_review'),
          onPressed: canEdit && !_busy
              ? () => _act((u) => db.reviewPayrollRun(run.id, userId: u))
              : null,
          icon: const Icon(PhosphorIconsBold.checkSquare, size: 16),
          label: Text(tr('تمت المراجعة')),
        ),
        TextButton.icon(
          key: const Key('payroll_delete'),
          onPressed: canEdit && !_busy
              ? () async {
                  await _act((u) => db.deletePayrollRun(run.id, userId: u));
                  if (context.mounted) Navigator.of(context).maybePop();
                }
              : null,
          icon: Icon(PhosphorIconsBold.trash,
              size: 16, color: AppColors.statusError(context)),
          label: Text(tr('حذف المسودة')),
        ),
      ],
      if (!legacy && s == PayrollRunStatus.reviewed) ...[
        FilledButton.icon(
          key: const Key('payroll_approve'),
          onPressed: canApprove && !_busy
              ? () => _act((u) => db.approvePayrollRun(run.id, userId: u))
              : null,
          icon: const Icon(PhosphorIconsBold.sealCheck, size: 16),
          label: Text(tr('اعتماد')),
        ),
      ],
      if (!legacy &&
          (s == PayrollRunStatus.reviewed || s == PayrollRunStatus.approved))
        OutlinedButton.icon(
          key: const Key('payroll_reopen'),
          onPressed: canEdit && !_busy
              ? () => _act((u) => db.reopenPayrollRun(run.id, userId: u))
              : null,
          icon: const Icon(PhosphorIconsBold.arrowUUpLeft, size: 16),
          label: Text(tr('إعادة للمسودة')),
        ),
      if (!legacy && s == PayrollRunStatus.approved)
        FilledButton.icon(
          key: const Key('payroll_post'),
          onPressed: canPost && !_busy
              ? () => _act((u) => db.postPayrollRun(run.id, userId: u),
                  done: tr('رُحّل المسير بقيد واحد'))
              : null,
          icon: const Icon(PhosphorIconsBold.bookOpenText, size: 16),
          label: Text(tr('ترحيل القيد')),
        ),
      if (!legacy && s == PayrollRunStatus.posted) ...[
        FilledButton.icon(
          key: const Key('payroll_pay'),
          onPressed: canPost && !_busy
              ? () async {
                  final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => PayrollPayDialog(run: run));
                  if (ok == true) refreshPayroll(ref);
                }
              : null,
          icon: const Icon(PhosphorIconsBold.handCoins, size: 16),
          label: Text(tr('صرف الرواتب')),
        ),
        if (run.paid <= 0)
          OutlinedButton.icon(
            key: const Key('payroll_reverse'),
            onPressed: canPost && !_busy
                ? () async {
                    final reason = await askPayrollReason(context,
                        title: tr('عكس المسير'), action: tr('عكس'));
                    if (reason == null) return;
                    await _act(
                        (u) => db.reversePayrollRun(run.id,
                            reason: reason, userId: u),
                        done: tr('عُكس المسير بقيد عاكس'));
                  }
                : null,
            icon: Icon(PhosphorIconsBold.arrowCounterClockwise,
                size: 16, color: AppColors.statusError(context)),
            label: Text(tr('عكس المسير')),
          ),
      ],
      OutlinedButton.icon(
        key: const Key('payroll_print_all'),
        onPressed:
            lines.isEmpty ? null : () => printPayslips(context, ref, run, lines),
        icon: const Icon(PhosphorIconsBold.printer, size: 16),
        label: Text(tr('طباعة القسائم')),
      ),
      OutlinedButton.icon(
        key: const Key('payroll_export'),
        onPressed: lines.isEmpty
            ? null
            : () => exportPayrollRegister(context, ref, run),
        icon: const Icon(PhosphorIconsBold.microsoftExcelLogo, size: 16),
        label: Text(tr('تصدير السجل')),
      ),
    ];

    Widget stat(String label, String value, {Color? color}) => Container(
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

    return PicPosScreenScaffold(
      title: tr('مسير رواتب {p0}', {'p0': run.period}),
      icon: PhosphorIconsBold.money,
      headerActions: [
        HrPill(
          label: payrollStatusLabel(s),
          color: payrollStatusColor(context, s),
        ),
        if (legacy) ...[
          const SizedBox(width: 8),
          HrPill(label: tr('للقراءة فقط'), color: context.picposMuted),
        ],
      ],
      bodyPadding: EdgeInsets.zero,
      subHeader: HrToolbar(children: actions),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 8, children: [
            stat(tr('الموظفون'), '${run.employeeCount}'),
            stat(tr('الإجمالي'), hrMoney(run.gross)),
            stat(tr('الخصومات'), hrMoney(run.deductions),
                color: AppColors.statusError(context)),
            stat(tr('الصافي'), hrMoney(run.net),
                color: AppColors.statusSuccess(context)),
            stat(tr('حصة المنشأة'), hrMoney(run.employerCost)),
            stat(tr('المصروف'), hrMoney(run.paid)),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: HrTable(
              minWidth: 1000,
              emptyIcon: PhosphorIconsBold.users,
              emptyTitle: tr('لا موظفين في هذا المسير'),
              columns: [
                HrTableColumn(tr('الموظف'), flex: 4),
                HrTableColumn(tr('القسم'), flex: 3),
                HrTableColumn(tr('الأساسي')),
                HrTableColumn(tr('الإجمالي')),
                HrTableColumn(tr('الخصومات')),
                HrTableColumn(tr('الصافي')),
                HrTableColumn(tr('الصرف')),
              ],
              rows: [
                for (final l in lines)
                  HrTableRow(
                    key: Key('payroll_line_${l.id}'),
                    onTap: () => openPayslip(context, run, l.id),
                    cells: [
                      HrCellText(l.employeeName, sub: l.employeeCode),
                      HrCellText(trData(l.departmentName ?? '—')),
                      HrCellText(hrMoney(l.basicSalary), number: true),
                      HrCellText(hrMoney(l.gross), number: true),
                      HrCellText(hrMoney(l.deductions),
                          number: true, color: AppColors.statusError(context)),
                      HrCellText(hrMoney(l.net), number: true),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: HrPill(
                          label: l.isPaid ? tr('مصروف') : tr('غير مصروف'),
                          color: l.isPaid
                              ? AppColors.statusSuccess(context)
                              : context.picposMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
