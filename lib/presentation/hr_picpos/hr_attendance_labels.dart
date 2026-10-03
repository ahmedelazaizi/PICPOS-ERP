// J4 (الجزء ٢) — تسمياتُ قيم الحضور والإجازات المخزَّنة وألوانُها، وتنسيقُ
// الأوقات والدقائق. كلُّ نصٍّ عبر `tr`، وأسماءُ الأنواع المبذورة بتسمية رمزها.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/hr_attendance.dart';
import '../../domain/models/hr_leave.dart';
import '../picpos_shell/picpos_surface.dart';

String attendanceStatusLabel(String status) => switch (status) {
      AttendanceStatus.present => tr('حاضر'),
      AttendanceStatus.late => tr('متأخر'),
      AttendanceStatus.absent => tr('غائب'),
      AttendanceStatus.leave => tr('إجازة'),
      AttendanceStatus.unpaidLeave => tr('إجازة بدون أجر'),
      AttendanceStatus.dayOff => tr('راحة'),
      AttendanceStatus.holiday => tr('عطلة رسمية'),
      AttendanceStatus.pending => tr('لم يسجل بعد'),
      _ => tr('خارج الخدمة'),
    };

Color attendanceStatusColor(BuildContext context, String status) =>
    switch (status) {
      AttendanceStatus.present => AppColors.statusSuccess(context),
      AttendanceStatus.late => AppColors.statusWarning(context),
      AttendanceStatus.absent => AppColors.statusError(context),
      AttendanceStatus.leave ||
      AttendanceStatus.unpaidLeave =>
        AppColors.statusInfo(context),
      AttendanceStatus.holiday => context.picposBrandInk,
      _ => context.picposMuted,
    };

IconData attendanceStatusIcon(String status) => switch (status) {
      AttendanceStatus.present => PhosphorIconsBold.checkCircle,
      AttendanceStatus.late => PhosphorIconsBold.clockCountdown,
      AttendanceStatus.absent => PhosphorIconsBold.xCircle,
      AttendanceStatus.leave ||
      AttendanceStatus.unpaidLeave =>
        PhosphorIconsBold.airplaneTilt,
      AttendanceStatus.holiday => PhosphorIconsBold.confetti,
      AttendanceStatus.dayOff => PhosphorIconsBold.coffee,
      _ => PhosphorIconsBold.hourglass,
    };

/// اسمُ نوع الإجازة: المبذورُ بتسمية رمزه، والمخصَّصُ باسمه (الإنجليزيّ إن
/// وُجد في الواجهة الإنجليزيّة).
String leaveTypeLabel(LeaveType? t) {
  if (t == null) return '—';
  final label = switch (t.code) {
    LeaveTypeCode.annual => tr('إجازة سنوية'),
    LeaveTypeCode.sick => tr('إجازة مرضية'),
    LeaveTypeCode.unpaid => tr('إجازة بدون أجر'),
    LeaveTypeCode.emergency => tr('إجازة طارئة'),
    _ => null,
  };
  if (label != null && t.name == _seededLeaveNames[t.code]) return label;
  final en = t.nameEn?.trim();
  if (uiLocaleCode == 'en' && en != null && en.isNotEmpty) return en;
  return trData(t.name);
}

/// اسمُ نوعٍ مخزَّنٌ نصّاً (في السجلّ أو صفّ اللوحة): المبذورُ يُترجَم.
String leaveTypeNameLabel(String name) =>
    _seededLeaveNames.containsValue(name) ? tr(name) : trData(name);

const _seededLeaveNames = {
  LeaveTypeCode.annual: 'إجازة سنوية',
  LeaveTypeCode.sick: 'إجازة مرضية',
  LeaveTypeCode.unpaid: 'إجازة بدون أجر',
  LeaveTypeCode.emergency: 'إجازة طارئة',
};

String leaveAccrualLabel(String accrual) => switch (accrual) {
      LeaveAccrual.monthly => tr('شهري'),
      LeaveAccrual.none => tr('بلا رصيد'),
      _ => tr('سنوي'),
    };

String leaveRequestStatusLabel(String status) => switch (status) {
      LeaveRequestStatus.draft => tr('مسودة'),
      LeaveRequestStatus.submitted => tr('بانتظار الاعتماد'),
      LeaveRequestStatus.approved => tr('معتمد'),
      LeaveRequestStatus.rejected => tr('مرفوض'),
      _ => tr('ملغى'),
    };

Color leaveRequestStatusColor(BuildContext context, String status) =>
    switch (status) {
      LeaveRequestStatus.submitted => AppColors.statusWarning(context),
      LeaveRequestStatus.approved => AppColors.statusSuccess(context),
      LeaveRequestStatus.rejected => AppColors.statusError(context),
      LeaveRequestStatus.draft => AppColors.statusInfo(context),
      _ => context.picposMuted,
    };

/// `HH:mm`، أو `—`.
String hrTime(DateTime? d) => d == null
    ? '—'
    : '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';

/// دقائقُ بصيغة `س:دد` (‏`0` ⇒ `—`).
String hrMinutes(int minutes) {
  if (minutes <= 0) return '—';
  return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// أيّامٌ بلا كسورٍ زائدة.
String hrDays(double days) =>
    days == days.roundToDouble() ? days.toInt().toString() : days.toStringAsFixed(2);

String hrWeekdayLabel(int weekday) => switch (weekday) {
      DateTime.monday => tr('الاثنين'),
      DateTime.tuesday => tr('الثلاثاء'),
      DateTime.wednesday => tr('الأربعاء'),
      DateTime.thursday => tr('الخميس'),
      DateTime.friday => tr('الجمعة'),
      DateTime.saturday => tr('السبت'),
      _ => tr('الأحد'),
    };

/// أيّامُ الأسبوع بترتيب العرض (السبت أوّلاً).
const kHrWeekOrder = [
  DateTime.saturday,
  DateTime.sunday,
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
];

/// `09:00 – 17:00` للورديّة، مع علامة اليوم التالي إن عبرت منتصف الليل.
String shiftTimesLabel(WorkShift s) {
  final base = '${WorkShift.formatMinute(s.startMinute)} – '
      '${WorkShift.formatMinute(s.endMinute)}';
  return s.crossesMidnight ? '$base (+1)' : base;
}

String hrMonthLabel(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';
