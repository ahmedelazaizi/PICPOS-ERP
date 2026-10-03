// J4 (الجزء ٢) — تبويبُ «الحضور» في ملفّ الموظف: ورديّتُه الحاليّة وسجلُّ
// إسناداتها، ثمّ ملخّصُ الشهر وتقويمُه (من نفس قاعدة اللوحة والكشف).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_attendance.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import '../hr_labels.dart';
import '../widgets/attendance_month_sheet.dart';
import '../widgets/hr_form_kit.dart';
import '../widgets/hr_table.dart';
import '../widgets/shift_dialogs.dart';

class EfAttendanceTab extends ConsumerStatefulWidget {
  const EfAttendanceTab({super.key, required this.employeeId, this.name = ''});
  final int? employeeId;
  final String name;

  @override
  ConsumerState<EfAttendanceTab> createState() => _EfAttendanceTabState();
}

class _EfAttendanceTabState extends ConsumerState<EfAttendanceTab> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;

  void _step(int delta) {
    final d = DateTime(_year, _month + delta);
    setState(() {
      _year = d.year;
      _month = d.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.employeeId;
    if (id == null) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.fingerprint,
        title: tr('احفظ الموظف أولاً'),
        hint: tr('يظهر الحضور بعد حفظ ملف الموظف'),
      );
    }
    final history =
        ref.watch(hrShiftAssignmentsProvider(id)).value ?? const [];
    final today = hrDay(DateTime.now());
    final current = history.where((a) => a.covers(today)).firstOrNull;
    final canAssign = ref
            .watch(hasPermissionProvider(PermissionCodes.hrShiftsManage))
            .value ??
        false;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        HrSection(
          title: tr('الوردية'),
          icon: PhosphorIconsBold.clockClockwise,
          actions: [
            TextButton.icon(
              key: const Key('ef_assign_shift'),
              onPressed: canAssign
                  ? () async {
                      if (await showShiftAssignDialog(context,
                              employeeId: id, employeeName: widget.name) &&
                          mounted) {
                        refreshHrAttendance(ref);
                      }
                    }
                  : null,
              icon: const Icon(PhosphorIconsBold.userSwitch, size: 15),
              label: Text(tr('إسناد وردية')),
            ),
          ],
          child: Column(children: [
            HrInfoLine(
              icon: PhosphorIconsBold.clockClockwise,
              label: tr('الوردية الحالية'),
              value: current?.shiftName == null
                  ? tr('بلا وردية')
                  : trData(current!.shiftName!),
            ),
            for (final a in history.take(5))
              HrInfoLine(
                icon: PhosphorIconsBold.clockCounterClockwise,
                label: trData(a.shiftName ?? '—'),
                value: a.effectiveTo == null
                    ? tr('من {p0} — حتى الآن', {'p0': hrDate(a.effectiveFrom)})
                    : '${hrDate(a.effectiveFrom)} → ${hrDate(a.effectiveTo)}',
              ),
          ]),
        ),
        HrSection(
          title: tr('حضور الشهر'),
          icon: PhosphorIconsBold.calendarDots,
          actions: [
            HrStepper(
              keyPrefix: 'ef_att_month',
              label: hrMonthLabel(_year, _month),
              onPrev: () => _step(-1),
              onNext: () => _step(1),
            ),
          ],
          child: AttendanceMonthSheet(
              employeeId: id, year: _year, month: _month),
        ),
      ],
    );
  }
}
