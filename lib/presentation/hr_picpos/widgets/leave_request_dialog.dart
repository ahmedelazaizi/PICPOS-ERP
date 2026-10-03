// J4 (الجزء ٢) — طلبُ إجازة: الموظفُ والنوعُ والفترةُ والسببُ والمرفق، ورصيدُ
// النوع المتبقّي أمام العين. يُحفَظ مسودةً أو يُقدَّم للاعتماد مباشرة. الأيّامُ
// تُحسَب عند الحفظ (أيّامُ العمل بلا الراحة والعطلات).
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_attendance.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_leave.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';

Future<bool> showLeaveRequestDialog(BuildContext context,
        {int? employeeId, LeaveRequest? request}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) =>
          LeaveRequestDialog(employeeId: employeeId, request: request),
    ) ??
    false;

class LeaveRequestDialog extends ConsumerStatefulWidget {
  const LeaveRequestDialog({super.key, this.employeeId, this.request});

  /// موظفٌ ثابت (من ملفّه) — لا منتقي.
  final int? employeeId;

  /// مسودةٌ تُعدَّل.
  final LeaveRequest? request;

  @override
  ConsumerState<LeaveRequestDialog> createState() => _LeaveRequestDialogState();
}

class _LeaveRequestDialogState extends ConsumerState<LeaveRequestDialog> {
  late int? _employeeId = widget.request?.employeeId ?? widget.employeeId;
  late int? _typeId = widget.request?.leaveTypeId;
  late DateTime? _from = widget.request?.startDate ?? hrDay(DateTime.now());
  late DateTime? _to = widget.request?.endDate ?? hrDay(DateTime.now());
  late final _reason = TextEditingController(text: widget.request?.reason);
  late String? _attachment = widget.request?.attachmentPath;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    final r = await FilePicker.pickFiles(dialogTitle: tr('اختر المرفق'));
    final path = r?.files.firstOrNull?.path;
    if (path != null && mounted) setState(() => _attachment = path);
  }

  Future<void> _save({required bool submit}) async {
    final employee = _employeeId;
    final type = _typeId;
    final from = _from;
    final to = _to;
    if (employee == null || type == null || from == null || to == null) {
      setState(() => _error = tr('أكمل الموظف والنوع والفترة.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).saveLeaveRequest(
            LeaveRequest(
              id: widget.request?.id,
              employeeId: employee,
              leaveTypeId: type,
              startDate: from,
              endDate: to,
              reason: _reason.text,
              attachmentPath: _attachment,
            ),
            actorUserId: ref.read(authProvider).user?.id,
            submit: submit,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on HrException catch (e) {
      // A refused submit keeps the saved draft — the list must still refresh.
      if (mounted) {
        refreshHrAttendance(ref);
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = [
      for (final p in ref.watch(hrProfilesProvider).value ??
          const <EmployeeProfile>[])
        if (p.isActive || p.id == _employeeId) p,
    ];
    final types = [
      for (final t in ref.watch(hrLeaveTypesProvider).value ??
          const <LeaveType>[])
        if (t.isActive || t.id == _typeId) t,
    ];
    final type = types.where((t) => t.id == _typeId).firstOrNull;
    final year = (_from ?? DateTime.now()).year;
    final balance = _employeeId == null || type == null || !type.hasEntitlement
        ? null
        : (ref.watch(hrLeaveBalancesProvider((_employeeId!, year))).value ??
                const <LeaveEntitlement>[])
            .where((b) => b.leaveTypeId == type.id)
            .firstOrNull;
    final fixed = widget.employeeId != null || widget.request != null;
    return PicPosDialog(
      icon: PhosphorIconsBold.airplaneTilt,
      title: widget.request == null ? tr('طلب إجازة') : tr('تعديل طلب الإجازة'),
      subtitle: fixed
          ? profiles.where((p) => p.id == _employeeId).firstOrNull?.name
          : null,
      width: 620,
      onCancel: () => Navigator.of(context).pop(false),
      secondaryActions: [
        PicPosDialogAction(
          label: tr('حفظ كمسودة'),
          icon: PhosphorIconsBold.floppyDisk,
          onPressed: _saving ? null : () => _save(submit: false),
        ),
      ],
      primaryAction: PicPosDialogAction(
        label: tr('تقديم للاعتماد'),
        icon: PhosphorIconsBold.paperPlaneTilt,
        busy: _saving,
        onPressed: _saving ? null : () => _save(submit: true),
      ),
      body: [
        if (_error != null)
          PicPosDialogBanner(
            key: const Key('leave_req_error'),
            icon: PhosphorIconsBold.warningCircle,
            text: _error!,
            color: AppColors.statusError(context),
          ),
        if (!fixed)
          HrDropdown<int>(
            fieldKey: const Key('leave_req_employee'),
            label: tr('الموظف'),
            required: true,
            value: _employeeId,
            items: {for (final p in profiles) p.id!: p.name},
            onChanged: (v) => setState(() => _employeeId = v),
          ),
        HrDropdown<int>(
          fieldKey: const Key('leave_req_type'),
          label: tr('نوع الإجازة'),
          required: true,
          value: _typeId,
          items: {for (final t in types) t.id!: leaveTypeLabel(t)},
          onChanged: (v) => setState(() => _typeId = v),
        ),
        PicPosDialogRow(children: [
          HrDateField(
            fieldKey: const Key('leave_req_from'),
            label: tr('من'),
            required: true,
            value: _from,
            onChanged: (v) => setState(() => _from = v),
          ),
          HrDateField(
            fieldKey: const Key('leave_req_to'),
            label: tr('إلى'),
            required: true,
            value: _to,
            onChanged: (v) => setState(() => _to = v),
          ),
        ]),
        if (type != null)
          HrInfoLine(
            icon: PhosphorIconsBold.scales,
            label: tr('الرصيد المتبقي'),
            value: !type.hasEntitlement
                ? (type.isPaid ? tr('بلا حد') : tr('بدون أجر — بلا رصيد'))
                : balance == null
                    ? '—'
                    : tr('{p0} يوم', {'p0': hrDays(balance.remaining)}),
          ),
        HrTextField(
          fieldKey: const Key('leave_req_reason'),
          label: tr('السبب'),
          controller: _reason,
        ),
        Row(children: [
          Expanded(
            child: HrInfoLine(
              icon: PhosphorIconsBold.paperclip,
              label: type?.requiresAttachment == true
                  ? tr('المرفق (مطلوب)')
                  : tr('المرفق'),
              value: _attachment ?? '—',
            ),
          ),
          TextButton.icon(
            key: const Key('leave_req_attach'),
            onPressed: _pickAttachment,
            icon: const Icon(PhosphorIconsBold.paperclip, size: 15),
            label: Text(tr('إرفاق')),
          ),
        ]),
      ],
    );
  }
}
