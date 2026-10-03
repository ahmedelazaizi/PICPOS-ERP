// J4 (الجزء ٢) — تبويبُ «الكشف الشهري»: اختيارُ الموظف والشهر، ثمّ مجاميعُه
// وتقويمُه. النقرُ على يومٍ يفتح التصحيحَ لصاحب `hr_attendance_edit`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_attendance.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';
import '../hr_picpos_providers.dart';
import 'attendance_entry_dialog.dart';
import 'attendance_month_sheet.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class AttendanceMonthView extends ConsumerStatefulWidget {
  const AttendanceMonthView({super.key});

  @override
  ConsumerState<AttendanceMonthView> createState() =>
      _AttendanceMonthViewState();
}

class _AttendanceMonthViewState extends ConsumerState<AttendanceMonthView> {
  int? _employeeId;
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
    final profiles = [
      for (final p in ref.watch(hrProfilesProvider).value ??
          const <EmployeeProfile>[])
        if (p.status != EmployeeStatus.terminated) p,
    ];
    final canEdit = ref
            .watch(hasPermissionProvider(PermissionCodes.hrAttendanceEdit))
            .value ??
        false;
    final id = _employeeId ?? (profiles.isEmpty ? null : profiles.first.id);
    final name = profiles.where((p) => p.id == id).firstOrNull?.name ?? '';
    return Column(children: [
      HrToolbar(children: [
        SizedBox(
          width: 260,
          child: HrDropdown<int>(
            fieldKey: const Key('att_month_employee'),
            label: tr('الموظف'),
            value: id,
            items: {
              for (final p in profiles)
                p.id!: p.code == null ? p.name : '${p.name} (${p.code})',
            },
            onChanged: (v) => setState(() => _employeeId = v),
          ),
        ),
        HrStepper(
          keyPrefix: 'att_month',
          label: hrMonthLabel(_year, _month),
          onPrev: () => _step(-1),
          onNext: () => _step(1),
        ),
      ]),
      Expanded(
        child: id == null
            ? PicPosEmptyState(
                icon: PhosphorIconsBold.usersThree,
                title: tr('لا موظفين بعد'),
                hint: tr('أضف الموظفين من «سجل الموظفين»'),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: AttendanceMonthSheet(
                  employeeId: id,
                  year: _year,
                  month: _month,
                  onDayTap: !canEdit
                      ? null
                      : (DayAttendance a) async {
                          final saved = await showAttendanceEntryDialog(
                              context,
                              employeeId: id,
                              employeeName: name,
                              day: a.day,
                              current: a);
                          if (saved && mounted) refreshHrAttendance(ref);
                        },
                ),
              ),
      ),
    ]);
  }
}
