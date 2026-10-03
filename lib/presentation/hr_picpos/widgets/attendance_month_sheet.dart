// J4 (الجزء ٢) — الكشفُ الشهريُّ لموظف: مجاميعُ الشهر (أيّامُ العمل والغياب
// والتأخيرُ والإضافيُّ والإجازات) ثمّ تقويمٌ بسبعة أعمدةٍ (السبت أوّلاً)
// تحمل كلُّ خليّةٍ حالةَ اليوم ووقتيه. يُستعمل في الشاشة وفي ملفّ الموظف.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/hr_attendance.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_attendance_labels.dart';
import '../hr_attendance_providers.dart';

/// مجاميعُ الشهر بلاطاتٍ تلتفّ.
class AttendanceTotals extends StatelessWidget {
  const AttendanceTotals({super.key, required this.summary});
  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final tiles = [
      ('worked', tr('أيام العمل'), '${s.workedDays}', AttendanceStatus.present),
      ('absent', tr('الغياب'), '${s.absentDays}', AttendanceStatus.absent),
      ('late', tr('التأخير (س:د)'), hrMinutes(s.lateMinutes), AttendanceStatus.late),
      ('early', tr('الانصراف المبكر (س:د)'), hrMinutes(s.earlyLeaveMinutes),
          AttendanceStatus.late),
      ('overtime', tr('الإضافي (س:د)'), hrMinutes(s.overtimeMinutes),
          AttendanceStatus.present),
      ('paid_leave', tr('إجازة مدفوعة'), '${s.paidLeaveDays}', AttendanceStatus.leave),
      ('unpaid_leave', tr('إجازة بدون أجر'), '${s.unpaidLeaveDays}',
          AttendanceStatus.unpaidLeave),
      ('holidays', tr('عطلات رسمية'), '${s.holidays}', AttendanceStatus.holiday),
      ('days_off', tr('أيام الراحة'), '${s.daysOff}', AttendanceStatus.dayOff),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (key, label, value, status) in tiles)
          Container(
            key: Key('att_total_$key'),
            width: 132,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.picposCard,
              border: Border.all(color: context.picposHairline),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3, color: attendanceStatusColor(context, status)),
              Expanded(
                child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 8),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.picposMuted)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: context.picposText,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ],
              ),
                ),
              ),
            ]),
            ),
          ),
      ],
    );
  }
}

/// المجاميعُ والتقويمُ لـ(موظف، سنة، شهر).
class AttendanceMonthSheet extends ConsumerWidget {
  const AttendanceMonthSheet({
    super.key,
    required this.employeeId,
    required this.year,
    required this.month,
    this.onDayTap,
  });
  final int employeeId;
  final int year;
  final int month;
  final ValueChanged<DayAttendance>? onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = (employeeId, year, month);
    final days = ref.watch(hrMonthAttendanceProvider(q)).value;
    final summary = ref.watch(hrMonthSummaryProvider(q)).value;
    if (days == null || summary == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AttendanceTotals(summary: summary),
        const SizedBox(height: 12),
        _Calendar(days: days, year: year, month: month, onDayTap: onDayTap),
      ],
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.days,
    required this.year,
    required this.month,
    this.onDayTap,
  });
  final List<DayAttendance> days;
  final int year;
  final int month;
  final ValueChanged<DayAttendance>? onDayTap;

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final d in days) d.day.day: d};
    final first = DateTime(year, month);
    final lead = kHrWeekOrder.indexOf(first.weekday);
    final count = DateTime(year, month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= count; d++) _cell(context, d, byDay[d]),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(17),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: context.picposField,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            for (final w in kHrWeekOrder)
              Expanded(
                child: Text(hrWeekdayLabel(w),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: context.picposMuted)),
              ),
          ]),
        ),
        for (var r = 0; r < cells.length ~/ 7; r++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < 7; c++) Expanded(child: cells[r * 7 + c]),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _cell(BuildContext context, int day, DayAttendance? a) {
    final status = a?.status ?? AttendanceStatus.notEmployed;
    final color = attendanceStatusColor(context, status);
    final r = a?.record;
    final times = r == null || (r.checkIn == null && r.checkOut == null)
        ? null
        : '${hrTime(r.checkIn)}–${hrTime(r.checkOut)}';
    return InkWell(
      key: Key('att_cal_$day'),
      onTap: a == null || onDayTap == null ? null : () => onDayTap!(a),
      child: Container(
        constraints: const BoxConstraints(minHeight: 66),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          border: Border.all(color: context.picposHairline, width: .5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('$day',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const Spacer(),
              if (a != null && status != AttendanceStatus.notEmployed)
                Icon(attendanceStatusIcon(status), size: 13, color: color),
            ]),
            if (a != null && status != AttendanceStatus.notEmployed)
              Text(attendanceStatusLabel(status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
            if (times != null)
              Text(times,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: context.picposMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            if ((a?.lateMinutes ?? 0) > 0 || (a?.overtimeMinutes ?? 0) > 0)
              Row(children: [
                if (a!.lateMinutes > 0) ...[
                  Icon(PhosphorIconsBold.clockCountdown,
                      size: 10, color: AppColors.statusWarning(context)),
                  Text(' ${a.lateMinutes}',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.statusWarning(context))),
                  const SizedBox(width: 4),
                ],
                if (a.overtimeMinutes > 0) ...[
                  Icon(PhosphorIconsBold.plusCircle,
                      size: 10, color: AppColors.statusSuccess(context)),
                  Text(' ${a.overtimeMinutes}',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.statusSuccess(context))),
                ],
              ]),
          ],
        ),
      ),
    );
  }
}
