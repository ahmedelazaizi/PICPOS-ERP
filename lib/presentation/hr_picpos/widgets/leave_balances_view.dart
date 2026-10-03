// J4 (الجزء ٢) — أرصدةُ الإجازات لموظفٍ في سنة: الافتتاحيُّ (المرحَّلُ أو
// المُدخَل يدويّاً) والمستحَقُّ والمستهلَكُ والمتبقّي، وتعديلُ الافتتاحيّ
// لصاحب `hr_leave_approve`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_leave.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class LeaveBalancesView extends ConsumerStatefulWidget {
  const LeaveBalancesView({super.key, this.employeeId, this.compact = false});
  final int? employeeId;
  final bool compact;

  @override
  ConsumerState<LeaveBalancesView> createState() => _LeaveBalancesViewState();
}

class _LeaveBalancesViewState extends ConsumerState<LeaveBalancesView> {
  int? _employeeId;
  int _year = DateTime.now().year;

  Future<void> _editOpening(int employeeId, LeaveEntitlement b) async {
    // بلا متحكّم يُتلَف بعد `await` — الحوارُ يرسم الحقلَ أثناء إغلاقه.
    var text = hrDays(b.openingDays);
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.pencilSimple,
      title: tr('الرصيد الافتتاحي'),
      message: tr('{p0} — {p1}: الرصيد المرحّل يدوياً، لا يُعاد حسابه بعد ذلك.',
          {'p0': leaveTypeLabel(b.type), 'p1': _year}),
      details: [
        TextFormField(
          key: const Key('leave_opening_days'),
          initialValue: text,
          onChanged: (v) => text = v,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    );
    final days = double.tryParse(text.trim());
    if (!ok || days == null || !mounted) return;
    try {
      await ref.read(databaseProvider).setLeaveOpeningBalance(
          employeeId: employeeId,
          leaveTypeId: b.leaveTypeId,
          year: _year,
          days: days);
      refreshHrAttendance(ref);
    } on HrException catch (e) {
      if (mounted) AppToast.show(context, e.message, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = [
      for (final p in ref.watch(hrProfilesProvider).value ??
          const <EmployeeProfile>[])
        if (p.status != EmployeeStatus.terminated) p,
    ];
    final id = widget.employeeId ??
        _employeeId ??
        (profiles.isEmpty ? null : profiles.first.id);
    final canApprove = ref
            .watch(hasPermissionProvider(PermissionCodes.hrLeaveApprove))
            .value ??
        false;
    final balances = id == null
        ? const <LeaveEntitlement>[]
        : ref.watch(hrLeaveBalancesProvider((id, _year))).value ??
            const <LeaveEntitlement>[];
    return Column(children: [
      HrToolbar(children: [
        if (widget.employeeId == null)
          SizedBox(
            width: 260,
            child: HrDropdown<int>(
              fieldKey: const Key('leave_bal_employee'),
              label: tr('الموظف'),
              value: id,
              items: {for (final p in profiles) p.id!: p.name},
              onChanged: (v) => setState(() => _employeeId = v),
            ),
          ),
        HrStepper(
          keyPrefix: 'leave_bal_year',
          label: '$_year',
          onPrev: () => setState(() => _year--),
          onNext: () => setState(() => _year++),
        ),
      ]),
      Expanded(
        child: id == null
            ? PicPosEmptyState(
                icon: PhosphorIconsBold.usersThree,
                title: tr('لا موظفين بعد'),
              )
            : Padding(
                padding: widget.compact
                    ? const EdgeInsets.only(top: 12)
                    : const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: HrTable(
                  minWidth: 820,
                  emptyIcon: PhosphorIconsBold.scales,
                  emptyTitle: tr('لا أرصدة — لا أنواع إجازة باستحقاق سنوي'),
                  columns: [
                    HrTableColumn(tr('نوع الإجازة'), flex: 4),
                    HrTableColumn(tr('الاستحقاق')),
                    HrTableColumn(tr('الافتتاحي')),
                    HrTableColumn(tr('المستحق')),
                    HrTableColumn(tr('المستهلك')),
                    HrTableColumn(tr('المتبقي')),
                  ],
                  rows: [
                    for (final b in balances)
                      HrTableRow(
                        key: Key('leave_bal_row_${b.leaveTypeId}'),
                        onTap: canApprove ? () => _editOpening(id, b) : null,
                        cells: [
                          HrCellText(leaveTypeLabel(b.type)),
                          HrCellText(leaveAccrualLabel(
                              b.type?.accrual ?? LeaveAccrual.yearly)),
                          Row(children: [
                            HrCellText(hrDays(b.openingDays), number: true),
                            if (b.openingLocked)
                              Padding(
                                padding:
                                    const EdgeInsetsDirectional.only(start: 4),
                                child: Icon(PhosphorIconsBold.lock,
                                    size: 12, color: context.picposMuted),
                              ),
                          ]),
                          HrCellText(hrDays(b.accruedDays), number: true),
                          HrCellText(hrDays(b.usedDays), number: true),
                          HrCellText(hrDays(b.remaining),
                              number: true,
                              color: b.remaining < 0
                                  ? AppColors.statusError(context)
                                  : AppColors.statusSuccess(context)),
                        ],
                      ),
                  ],
                ),
              ),
      ),
    ]);
  }
}
