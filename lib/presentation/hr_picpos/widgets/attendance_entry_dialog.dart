// J4 (الجزء ٢) — إدخالُ حضور يومٍ أو تصحيحُه يدويّاً: وقتا الحضور والانصراف
// (والانصرافُ في اليوم التالي لورديّةٍ ليليّة) أو علامةُ حاضر/غائب، **بسببٍ
// إلزاميّ** يُسجَّل في سجلّ الموظف. محروسٌ بـ`hr_attendance_edit` عند المنادي.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_attendance.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../hr_attendance_labels.dart';
import '../hr_labels.dart';
import 'hr_form_kit.dart';

Future<bool> showAttendanceEntryDialog(
  BuildContext context, {
  required int employeeId,
  required String employeeName,
  required DateTime day,
  DayAttendance? current,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AttendanceEntryDialog(
        employeeId: employeeId,
        employeeName: employeeName,
        day: hrDay(day),
        current: current,
      ),
    ) ??
    false;

class AttendanceEntryDialog extends ConsumerStatefulWidget {
  const AttendanceEntryDialog({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.day,
    this.current,
  });
  final int employeeId;
  final String employeeName;
  final DateTime day;
  final DayAttendance? current;

  @override
  ConsumerState<AttendanceEntryDialog> createState() =>
      _AttendanceEntryDialogState();
}

class _AttendanceEntryDialogState extends ConsumerState<AttendanceEntryDialog> {
  late final AttendanceRecord? _record = widget.current?.record;
  late final _in = TextEditingController(
      text: _record?.checkIn == null ? '' : hrTime(_record!.checkIn));
  late final _out = TextEditingController(
      text: _record?.checkOut == null ? '' : hrTime(_record!.checkOut));
  final _reason = TextEditingController();
  late bool _nextDay = (widget.current?.shift?.crossesMidnight ?? false) ||
      (_record?.checkOut != null &&
          hrDay(_record!.checkOut!).isAfter(widget.day));
  late String? _mark = switch (_record?.mark) {
    AttendanceMark.present => AttendanceMark.present,
    AttendanceMark.absent => AttendanceMark.absent,
    _ => null,
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _in.dispose();
    _out.dispose();
    _reason.dispose();
    super.dispose();
  }

  DateTime? _time(String text, {bool nextDay = false}) {
    if (text.trim().isEmpty) return null;
    final m = WorkShift.parseMinute(text);
    if (m == null) throw HrException('صيغة الوقت ساعة:دقيقة مثل 09:30');
    final d = widget.day;
    return DateTime(d.year, d.month, d.day + (nextDay ? 1 : 0), 0, m);
  }

  Future<void> _save({bool clear = false}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final checkIn = clear ? null : _time(_in.text);
      final checkOut = clear ? null : _time(_out.text, nextDay: _nextDay);
      await ref.read(databaseProvider).saveAttendanceEntry(
            employeeId: widget.employeeId,
            day: widget.day,
            checkIn: checkIn,
            checkOut: checkOut,
            mark: clear ? null : _mark,
            reason: _reason.text,
            actorUserId: ref.read(authProvider).user?.id,
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
    final shift = widget.current?.shift;
    return PicPosDialog(
      icon: PhosphorIconsBold.fingerprint,
      title: tr('تسجيل الحضور يدوياً'),
      subtitle: '${widget.employeeName} · ${hrDate(widget.day)}',
      width: 560,
      onCancel: () => Navigator.of(context).pop(false),
      secondaryActions: [
        if (_record != null)
          PicPosDialogAction(
            label: tr('مسح السجل'),
            icon: PhosphorIconsBold.eraser,
            onPressed: _saving ? null : () => _save(clear: true),
          ),
      ],
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
        HrInfoLine(
          icon: PhosphorIconsBold.clockClockwise,
          label: tr('الوردية'),
          value: shift == null
              ? tr('بلا وردية')
              : '${trData(shift.name)} · ${shiftTimesLabel(shift)}',
        ),
        PicPosDialogRow(children: [
          HrTextField(
            fieldKey: const Key('att_entry_in'),
            label: tr('وقت الحضور'),
            controller: _in,
            hint: '09:00',
            textDirection: TextDirection.ltr,
          ),
          HrTextField(
            fieldKey: const Key('att_entry_out'),
            label: tr('وقت الانصراف'),
            controller: _out,
            hint: '17:00',
            textDirection: TextDirection.ltr,
          ),
        ]),
        CheckboxListTile(
          key: const Key('att_entry_next_day'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _nextDay,
          onChanged: (v) => setState(() => _nextDay = v ?? false),
          title: Text(tr('الانصراف في اليوم التالي')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        HrDropdown<String>(
          fieldKey: const Key('att_entry_mark'),
          label: tr('العلامة'),
          value: _mark,
          emptyLabel: tr('حسب البصمة'),
          items: {
            AttendanceMark.present: tr('حاضر بلا أوقات'),
            AttendanceMark.absent: tr('غائب'),
          },
          onChanged: (v) => setState(() => _mark = v),
        ),
        HrTextField(
          fieldKey: const Key('att_entry_reason'),
          label: tr('سبب التعديل'),
          controller: _reason,
          required: true,
          hint: tr('يُسجَّل في سجل الموظف'),
        ),
      ],
    );
  }
}
