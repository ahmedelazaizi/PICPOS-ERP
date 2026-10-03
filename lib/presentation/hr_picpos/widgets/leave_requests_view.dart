// J4 (الجزء ٢) — طلباتُ الإجازة: مرشّحُ الحالة والموظف، وإجراءاتُ الدورة
// (تقديم · اعتماد · رفض · إلغاء). الاعتمادُ والرفضُ للمدير المباشر أو لصاحب
// `hr_leave_approve`، والطلبُ الجديدُ لصاحب `hr_leave_request`.
import 'package:flutter/material.dart';
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
import '../../picpos_shell/picpos_surface.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';
import 'leave_request_dialog.dart';

class LeaveRequestsView extends ConsumerStatefulWidget {
  const LeaveRequestsView({super.key, this.employeeId, this.compact = false});

  /// طلباتُ موظفٍ واحد (ملفُّ الموظف) — بلا مرشّح الموظف.
  final int? employeeId;
  final bool compact;

  @override
  ConsumerState<LeaveRequestsView> createState() => _LeaveRequestsViewState();
}

class _LeaveRequestsViewState extends ConsumerState<LeaveRequestsView> {
  String? _status;
  int? _employeeFilter;

  int? get _employee => widget.employeeId ?? _employeeFilter;

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      refreshHrAttendance(ref);
      refreshHr(ref, _employee);
      if (mounted) AppToast.show(context, done);
    } on HrException catch (e) {
      if (mounted) AppToast.show(context, e.message, type: ToastType.error);
    }
  }

  Future<String?> _note(String title, {bool danger = false}) async {
    // بلا متحكّم: الحوارُ يُغلَق بحركةٍ ما زالت ترسم الحقل، ومتحكّمٌ يُتلَف
    // بعد `await` مباشرةً يُستعمَل بعد إتلافه.
    var text = '';
    final ok = await showPicPosConfirm(
      context,
      icon: danger ? PhosphorIconsBold.xCircle : PhosphorIconsBold.checkCircle,
      title: title,
      message: tr('ملاحظة القرار (اختيارية):'),
      danger: danger,
      details: [
        TextField(
          key: const Key('leave_decision_note'),
          onChanged: (v) => text = v,
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    );
    return ok ? text : null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(hrLeaveRequestsProvider((_employee, _status))).value ??
        const <LeaveRequest>[];
    final profiles = {
      for (final p in ref.watch(hrProfilesProvider).value ??
          const <EmployeeProfile>[])
        p.id!: p,
    };
    final canRequest = ref
            .watch(hasPermissionProvider(PermissionCodes.hrLeaveRequest))
            .value ??
        false;
    final canApproveAll = ref
            .watch(hasPermissionProvider(PermissionCodes.hrLeaveApprove))
            .value ??
        false;
    final me = ref.watch(authProvider).user?.id;
    bool canDecide(LeaveRequest r) {
      if (canApproveAll) return true;
      final managerId = profiles[r.employeeId]?.managerId;
      return me != null && profiles[managerId]?.userId == me;
    }

    final db = ref.read(databaseProvider);
    final pending =
        rows.where((r) => r.status == LeaveRequestStatus.submitted).length;
    return Column(children: [
      HrToolbar(children: [
        SizedBox(
          width: 190,
          child: HrDropdown<String>(
            fieldKey: const Key('leave_filter_status'),
            label: tr('الحالة'),
            value: _status,
            emptyLabel: tr('الكل'),
            items: {
              for (final s in LeaveRequestStatus.values)
                s: leaveRequestStatusLabel(s),
            },
            onChanged: (v) => setState(() => _status = v),
          ),
        ),
        if (widget.employeeId == null)
          SizedBox(
            width: 220,
            child: HrDropdown<int>(
              fieldKey: const Key('leave_filter_employee'),
              label: tr('الموظف'),
              value: _employeeFilter,
              emptyLabel: tr('الكل'),
              items: {for (final p in profiles.values) p.id!: p.name},
              onChanged: (v) => setState(() => _employeeFilter = v),
            ),
          ),
        HrPill(
          key: const Key('leave_pending_count'),
          label: tr('{p0} بانتظار الاعتماد', {'p0': pending}),
          color: AppColors.statusWarning(context),
        ),
        FilledButton.icon(
          key: const Key('leave_new'),
          onPressed: canRequest
              ? () async {
                  if (await showLeaveRequestDialog(context,
                          employeeId: widget.employeeId) &&
                      mounted) {
                    refreshHrAttendance(ref);
                    refreshHr(ref, widget.employeeId);
                  }
                }
              : null,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: Text(tr('طلب إجازة')),
        ),
      ]),
      Expanded(
        child: Padding(
          padding: widget.compact
              ? const EdgeInsets.only(top: 12)
              : const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 1040,
            emptyIcon: PhosphorIconsBold.airplaneTilt,
            emptyTitle: tr('لا طلبات إجازة'),
            emptyHint: tr('الطلبات الجديدة تظهر هنا بحالتها'),
            columns: [
              if (widget.employeeId == null) HrTableColumn(tr('الموظف'), flex: 3),
              HrTableColumn(tr('النوع'), flex: 3),
              HrTableColumn(tr('من')),
              HrTableColumn(tr('إلى')),
              HrTableColumn(tr('الأيام'), flex: 1),
              HrTableColumn(tr('الحالة'), flex: 3),
              HrTableColumn(tr('ملاحظة'), flex: 3),
              HrTableColumn(tr('إجراءات'), flex: 4),
            ],
            rows: [
              for (final r in rows)
                HrTableRow(
                  key: Key('leave_row_${r.id}'),
                  cells: [
                    if (widget.employeeId == null)
                      HrCellText(r.employeeName ?? '—'),
                    HrCellText(leaveTypeLabel(r.type),
                        sub: r.type == null
                            ? null
                            : (r.type!.isPaid ? tr('مدفوعة') : tr('غير مدفوعة'))),
                    HrCellText(hrDate(r.startDate), number: true),
                    HrCellText(hrDate(r.endDate), number: true),
                    HrCellText(hrDays(r.days), number: true),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: HrPill(
                        label: leaveRequestStatusLabel(r.status),
                        color: leaveRequestStatusColor(context, r.status),
                      ),
                    ),
                    HrCellText(r.decisionNote ?? r.reason ?? '—'),
                    Wrap(spacing: 2, children: [
                      if (r.status == LeaveRequestStatus.draft && canRequest)
                        _action('leave_submit_${r.id}', PhosphorIconsBold.paperPlaneTilt,
                            tr('تقديم'), context.picposBrandInk,
                            () => _run(() => db.submitLeaveRequest(r.id!,
                                actorUserId: me), tr('تم تقديم الطلب'))),
                      if (r.status == LeaveRequestStatus.submitted &&
                          canDecide(r)) ...[
                        _action(
                            'leave_approve_${r.id}',
                            PhosphorIconsBold.checkCircle,
                            tr('اعتماد'),
                            AppColors.statusSuccess(context), () async {
                          final note = await _note(tr('اعتماد الإجازة'));
                          if (note == null) return;
                          await _run(
                              () => db.approveLeaveRequest(r.id!,
                                  actorUserId: me,
                                  canApproveAll: canApproveAll,
                                  note: note),
                              tr('تم اعتماد الإجازة'));
                        }),
                        _action(
                            'leave_reject_${r.id}',
                            PhosphorIconsBold.xCircle,
                            tr('رفض'),
                            AppColors.statusError(context), () async {
                          final note =
                              await _note(tr('رفض الإجازة'), danger: true);
                          if (note == null) return;
                          await _run(
                              () => db.rejectLeaveRequest(r.id!,
                                  actorUserId: me,
                                  canApproveAll: canApproveAll,
                                  note: note),
                              tr('تم رفض الطلب'));
                        }),
                      ],
                      if (LeaveRequestStatus.blocking.contains(r.status) &&
                          (r.status != LeaveRequestStatus.approved ||
                              canDecide(r)) &&
                          canRequest)
                        _action('leave_cancel_${r.id}', PhosphorIconsBold.prohibit,
                            tr('إلغاء'), AppColors.statusWarning(context),
                            () async {
                          final ok = await showPicPosConfirm(context,
                              icon: PhosphorIconsBold.prohibit,
                              title: tr('إلغاء الطلب'),
                              message: r.status == LeaveRequestStatus.approved
                                  ? tr('الطلب معتمد: إلغاؤه يعيد الرصيد ويرفع علامات الإجازة من الحضور.')
                                  : tr('إلغاء هذا الطلب؟'),
                              danger: true,
                              confirmLabel: tr('إلغاء الطلب'));
                          if (!ok) return;
                          await _run(
                              () => db.cancelLeaveRequest(r.id!, actorUserId: me),
                              tr('تم إلغاء الطلب'));
                        }),
                    ]),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _action(String key, IconData icon, String tip, Color color,
          VoidCallback onPressed) =>
      IconButton(
        key: Key(key),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(),
        padding: const EdgeInsets.all(5),
        iconSize: 18,
        onPressed: onPressed,
        icon: Icon(icon, color: color),
      );
}
