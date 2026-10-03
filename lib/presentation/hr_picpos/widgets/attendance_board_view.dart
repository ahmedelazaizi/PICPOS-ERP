// J4 (الجزء ٢) — اللوحةُ اليوميّة: كلُّ موظفٍ في الخدمة بورديّته وبصمتَيه
// وحالته المحسوبة ودقائقه، مع «تحضير الكلّ» واستيراد البصمة والتصحيح.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_attendance.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import 'attendance_entry_dialog.dart';
import 'attendance_import_dialog.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class AttendanceBoardView extends ConsumerStatefulWidget {
  const AttendanceBoardView({super.key});

  @override
  ConsumerState<AttendanceBoardView> createState() =>
      _AttendanceBoardViewState();
}

class _AttendanceBoardViewState extends ConsumerState<AttendanceBoardView> {
  DateTime _day = hrDay(DateTime.now());
  int? _branchId;
  int? _departmentId;
  String? _status;

  void _shift(int days) => setState(
      () => _day = DateTime(_day.year, _day.month, _day.day + days));

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null) setState(() => _day = hrDay(picked));
  }

  Future<void> _markAll(List<AttendanceBoardRow> rows) async {
    final targets = [
      for (final r in rows)
        if (r.attendance.status == AttendanceStatus.absent ||
            r.attendance.status == AttendanceStatus.pending)
          r.employeeId,
    ];
    if (targets.isEmpty) {
      AppToast.show(context, tr('لا موظفين بلا تسجيل في هذا اليوم'));
      return;
    }
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.checks,
      title: tr('تحضير الكل'),
      message: tr(
          'سيُسجَّل {p0} موظف حاضرين بأوقات ورديّاتهم في {p1}. الغائب المعلَّم والإجازات والعطلات لا تتأثر.',
          {'p0': targets.length, 'p1': hrDate(_day)}),
      confirmLabel: tr('تحضير'),
    );
    if (!ok || !mounted) return;
    try {
      final n = await ref.read(databaseProvider).markAllPresent(_day,
          employeeIds: targets.toSet(),
          actorUserId: ref.read(authProvider).user?.id);
      refreshHrAttendance(ref);
      if (mounted) {
        AppToast.show(context, tr('تم تحضير {p0} موظف', {'p0': n}));
      }
    } catch (e, st) {
      if (mounted) AppErrorHandler.handle(context, e, st);
    }
  }

  Future<void> _edit(AttendanceBoardRow r) async {
    final saved = await showAttendanceEntryDialog(context,
        employeeId: r.employeeId,
        employeeName: r.name,
        day: _day,
        current: r.attendance);
    if (saved && mounted) refreshHrAttendance(ref);
  }

  Future<void> _import() async {
    final done = await showAttendanceImportDialog(context);
    if (done && mounted) refreshHrAttendance(ref);
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref
            .watch(hrAttendanceBoardProvider((_day, _branchId, _departmentId)))
            .value ??
        const <AttendanceBoardRow>[];
    final branches = ref.watch(hrBranchesProvider).value ?? const [];
    final departments = ref.watch(hrDepartmentsProvider).value ?? const [];
    final canEdit = ref
            .watch(hasPermissionProvider(PermissionCodes.hrAttendanceEdit))
            .value ??
        false;
    int count(Set<String> s) =>
        rows.where((r) => s.contains(r.attendance.status)).length;
    final shown = [
      for (final r in rows)
        if (_status == null || r.attendance.status == _status) r,
    ];

    Widget pill(String key, String label, int n, Color color, String? status) =>
        InkWell(
          key: Key('att_kpi_$key'),
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _status = _status == status ? null : status),
          child: Opacity(
            opacity: _status == null || _status == status ? 1 : .45,
            child: HrPill(label: '$label · $n', color: color),
          ),
        );

    return Column(children: [
      HrToolbar(children: [
        HrStepper(
          keyPrefix: 'att_day',
          label: '${hrWeekdayLabel(_day.weekday)} ${hrDate(_day)}',
          onPrev: () => _shift(-1),
          onNext: () => _shift(1),
          onTapLabel: _pickDay,
        ),
        SizedBox(
          width: 180,
          child: HrDropdown<int>(
            fieldKey: const Key('att_filter_branch'),
            label: tr('الفرع'),
            value: _branchId,
            emptyLabel: tr('الكل'),
            items: {for (final b in branches) b.id: trData(b.name)},
            onChanged: (v) => setState(() => _branchId = v),
          ),
        ),
        SizedBox(
          width: 180,
          child: HrDropdown<int>(
            fieldKey: const Key('att_filter_department'),
            label: tr('القسم'),
            value: _departmentId,
            emptyLabel: tr('الكل'),
            items: {for (final d in departments) d.id: trData(d.name)},
            onChanged: (v) => setState(() => _departmentId = v),
          ),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          pill('present', tr('حاضر'),
              count({AttendanceStatus.present}),
              attendanceStatusColor(context, AttendanceStatus.present),
              AttendanceStatus.present),
          pill('late', tr('متأخر'), count({AttendanceStatus.late}),
              attendanceStatusColor(context, AttendanceStatus.late),
              AttendanceStatus.late),
          pill('absent', tr('غائب'), count({AttendanceStatus.absent}),
              attendanceStatusColor(context, AttendanceStatus.absent),
              AttendanceStatus.absent),
          pill(
              'leave',
              tr('إجازة'),
              count({AttendanceStatus.leave, AttendanceStatus.unpaidLeave}),
              attendanceStatusColor(context, AttendanceStatus.leave),
              AttendanceStatus.leave),
          pill(
              'off',
              tr('راحة / عطلة'),
              count({AttendanceStatus.dayOff, AttendanceStatus.holiday}),
              attendanceStatusColor(context, AttendanceStatus.dayOff),
              AttendanceStatus.dayOff),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            key: const Key('att_import'),
            onPressed: canEdit ? _import : null,
            icon: const Icon(PhosphorIconsBold.fileCsv, size: 16),
            label: Text(tr('استيراد البصمة')),
          ),
          FilledButton.icon(
            key: const Key('att_mark_all'),
            onPressed: canEdit ? () => _markAll(rows) : null,
            icon: const Icon(PhosphorIconsBold.checks, size: 16),
            label: Text(tr('تحضير الكل')),
          ),
        ]),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: 1000,
            emptyIcon: PhosphorIconsBold.usersThree,
            emptyTitle: tr('لا موظفين في الخدمة لهذا اليوم'),
            emptyHint: tr('غيّر اليوم أو المرشحات'),
            columns: [
              HrTableColumn(tr('الموظف'), flex: 4),
              HrTableColumn(tr('الوردية'), flex: 3),
              HrTableColumn(tr('الحضور')),
              HrTableColumn(tr('الانصراف')),
              HrTableColumn(tr('الحالة'), flex: 3),
              HrTableColumn(tr('التأخير')),
              HrTableColumn(tr('انصراف مبكر')),
              HrTableColumn(tr('إضافي')),
              const HrTableColumn('', flex: 2),
            ],
            rows: [for (final r in shown) _row(context, r, canEdit)],
          ),
        ),
      ),
    ]);
  }

  HrTableRow _row(BuildContext context, AttendanceBoardRow r, bool canEdit) {
    final a = r.attendance;
    final shift = a.shift;
    final color = attendanceStatusColor(context, a.status);
    String? statusSub;
    if (a.status == AttendanceStatus.holiday) {
      statusSub = a.holidayName == null ? null : trData(a.holidayName!);
    } else if (a.leave?.typeName != null) {
      statusSub = leaveTypeNameLabel(a.leave!.typeName!);
    }
    final edited = a.record?.editReason;
    return HrTableRow(
      key: Key('att_row_${r.employeeId}'),
      onTap: canEdit ? () => _edit(r) : null,
      cells: [
        HrCellText(r.name, sub: r.code),
        HrCellText(shift == null ? tr('بلا وردية') : trData(shift.name),
            sub: shift == null ? null : shiftTimesLabel(shift),
            color: shift == null ? context.picposMuted : null),
        HrCellText(hrTime(a.record?.checkIn), number: true),
        HrCellText(hrTime(a.record?.checkOut), number: true),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            HrPill(
              label: attendanceStatusLabel(a.status),
              color: color,
              icon: attendanceStatusIcon(a.status),
            ),
            if (statusSub != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(statusSub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.picposMuted)),
              ),
          ],
        ),
        HrCellText(hrMinutes(a.lateMinutes),
            number: true,
            color: a.lateMinutes > 0
                ? attendanceStatusColor(context, AttendanceStatus.late)
                : null),
        HrCellText(hrMinutes(a.earlyLeaveMinutes), number: true),
        HrCellText(hrMinutes(a.overtimeMinutes),
            number: true,
            color: a.overtimeMinutes > 0
                ? attendanceStatusColor(context, AttendanceStatus.present)
                : null),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (edited != null)
            Tooltip(
              message: tr('عُدّل يدوياً: {p0}', {'p0': edited}),
              child: Icon(PhosphorIconsBold.info,
                  size: 15, color: context.picposMuted),
            ),
          if (canEdit)
            IconButton(
              key: Key('att_edit_${r.employeeId}'),
              tooltip: tr('تعديل الحضور'),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              iconSize: 16,
              onPressed: () => _edit(r),
              icon: Icon(PhosphorIconsBold.pencilSimple,
                  color: context.picposBrandInk),
            ),
        ]),
      ],
    );
  }
}
