// J4 (الجزء ٣) — المكافآتُ والجزاءاتُ لمرّةٍ واحدة: لموظفٍ في شهرٍ بسببٍ
// إلزاميّ (‏`hr_payroll_edit`)، وتُعتمد أو تُرفض (‏`hr_payroll_approve`)،
// والمعتمدةُ تدخل مسيّرَ شهرها وتُستهلك عند ترحيله.
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
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class PayrollAdjustmentsView extends ConsumerWidget {
  const PayrollAdjustmentsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(payrollAdjustmentsProvider(null)).value ??
        const <PayrollAdjustment>[];
    bool can(String code) =>
        ref.watch(hasPermissionProvider(code)).value ?? false;
    final canEdit = can(PermissionCodes.hrPayrollEdit);
    final canApprove = can(PermissionCodes.hrPayrollApprove);

    Future<void> run(Future<void> Function(int? user) action) async {
      try {
        await action(ref.read(authProvider).user?.id);
        refreshPayroll(ref);
      } on HrException catch (e) {
        if (context.mounted) {
          AppToast.show(context, e.message, type: ToastType.error);
        }
      }
    }

    final db = ref.read(databaseProvider);
    return Column(children: [
      HrToolbar(children: [
        FilledButton.icon(
          key: const Key('adjustment_new'),
          onPressed: canEdit
              ? () async {
                  final ok = await showDialog<bool>(
                      context: context, builder: (_) => const _AdjustmentDialog());
                  if (ok == true) refreshPayroll(ref);
                }
              : null,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: Text(tr('مكافأة أو جزاء')),
        ),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 980,
            emptyIcon: PhosphorIconsBold.scales,
            emptyTitle: tr('لا مكافآت ولا جزاءات بعد'),
            columns: [
              HrTableColumn(tr('الموظف'), flex: 3),
              HrTableColumn(tr('النوع')),
              HrTableColumn(tr('المبلغ')),
              HrTableColumn(tr('الشهر')),
              HrTableColumn(tr('السبب'), flex: 4),
              HrTableColumn(tr('الحالة'), flex: 3),
              const HrTableColumn('', flex: 2),
            ],
            rows: [
              for (final a in rows)
                HrTableRow(
                  key: Key('adjustment_row_${a.id}'),
                  cells: [
                    HrCellText(a.employeeName ?? ''),
                    HrCellText(adjustmentKindLabel(a.kind),
                        color: a.kind == AdjustmentKind.bonus
                            ? AppColors.statusSuccess(context)
                            : AppColors.statusError(context)),
                    HrCellText(hrMoney(a.amount), number: true),
                    HrCellText(hrPeriod(a.year, a.month), number: true),
                    HrCellText(trData(a.reason)),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: HrPill(
                        label: a.payrollRunId != null
                            ? tr('مستهلكة في مسير')
                            : adjustmentStatusLabel(a.status),
                        color: adjustmentStatusColor(context, a.status),
                      ),
                    ),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (canApprove &&
                          a.payrollRunId == null &&
                          a.status != AdjustmentStatus.approved)
                        IconButton(
                          key: Key('adjustment_approve_${a.id}'),
                          tooltip: tr('اعتماد'),
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          onPressed: () => run((u) => db
                              .decidePayrollAdjustment(a.id!,
                                  approve: true, userId: u)),
                          icon: Icon(PhosphorIconsBold.check,
                              color: AppColors.statusSuccess(context)),
                        ),
                      if (canApprove &&
                          a.payrollRunId == null &&
                          a.status != AdjustmentStatus.rejected)
                        IconButton(
                          key: Key('adjustment_reject_${a.id}'),
                          tooltip: tr('رفض'),
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          onPressed: () => run((u) => db
                              .decidePayrollAdjustment(a.id!,
                                  approve: false, userId: u)),
                          icon: Icon(PhosphorIconsBold.x,
                              color: AppColors.statusError(context)),
                        ),
                    ]),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _AdjustmentDialog extends ConsumerStatefulWidget {
  const _AdjustmentDialog();

  @override
  ConsumerState<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends ConsumerState<_AdjustmentDialog> {
  int? _employee;
  String _kind = AdjustmentKind.bonus;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  late DateTime _month = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_employee == null) {
      setState(() => _error = tr('اختر الموظف.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).createPayrollAdjustment(
            PayrollAdjustment(
              employeeId: _employee!,
              kind: _kind,
              amount: double.tryParse(_amount.text.trim()) ?? 0,
              year: _month.year,
              month: _month.month,
              reason: _reason.text,
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
    final people = ref.watch(hrProfilesProvider).value ?? const <EmployeeProfile>[];
    return PicPosDialog(
      icon: PhosphorIconsBold.scales,
      title: tr('مكافأة أو جزاء'),
      width: 620,
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
          HrDropdown<int>(
            fieldKey: const Key('adjustment_employee'),
            label: tr('الموظف'),
            value: _employee,
            required: true,
            items: {
              for (final p in people)
                if (p.status != EmployeeStatus.terminated) p.id!: p.name,
            },
            onChanged: (v) => setState(() => _employee = v),
          ),
          HrDropdown<String>(
            fieldKey: const Key('adjustment_kind'),
            label: tr('النوع'),
            value: _kind,
            items: {
              for (final k in AdjustmentKind.values) k: adjustmentKindLabel(k),
            },
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
        ]),
        PicPosDialogRow(children: [
          HrTextField(
            fieldKey: const Key('adjustment_amount'),
            label: tr('المبلغ'),
            controller: _amount,
            number: true,
            required: true,
          ),
          HrLabeled(
            label: tr('الشهر'),
            child: HrStepper(
              keyPrefix: 'adjustment_month',
              label: hrPeriod(_month.year, _month.month),
              onPrev: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
              onNext: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ),
        ]),
        HrTextField(
          fieldKey: const Key('adjustment_reason'),
          label: tr('السبب'),
          controller: _reason,
          required: true,
          maxLines: 2,
        ),
      ],
    );
  }
}
