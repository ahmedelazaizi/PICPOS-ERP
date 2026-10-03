// J4 (الجزء ٢) — الورديّاتُ والحضورُ اليوميّ وملخّصُ الفترة.
//
// نماذجُ خالصةٌ بلا Flutter ولا قاعدة: تُبنى من جداول v192 (‏`hr_shifts` ·
// `hr_shift_assignments` · `hr_attendance_days` · `hr_public_holidays`).
//
// ⚠️ الحالةُ **تُحسَب ولا تُخزَّن**: الصفُّ المخزَّن يحمل البصمتين وما علّمه
// المستخدمُ صراحةً (حاضرٌ بلا أوقات · غائب · إجازة)، و[computeDayAttendance]
// يشتقّ منه ومن الورديّة والعطلة والإجازة: حاضر/متأخّر/غائب/إجازة/راحة/عطلة
// ودقائقَ التأخير والانصراف المبكّر والإضافيّ. فتعديلُ ورديّةٍ يُعيد حسابَ
// ماضيها بلا هجرةِ بيانات، والجزءُ ٣ (الرواتب) يقرأ [AttendanceSummary].

/// الحالةُ المحسوبةُ لليوم.
abstract final class AttendanceStatus {
  static const present = 'present';
  static const late = 'late';
  static const absent = 'absent';
  static const leave = 'leave';
  static const unpaidLeave = 'unpaid_leave';
  static const dayOff = 'day_off';
  static const holiday = 'holiday';

  /// يومُ عملٍ لم ينتهِ بعد ولا بصمةَ فيه.
  static const pending = 'pending';

  /// قبل التعيين أو بعد إنهاء الخدمة.
  static const notEmployed = 'not_employed';

  static const values = [
    present,
    late,
    absent,
    leave,
    unpaidLeave,
    dayOff,
    holiday,
    pending,
  ];
}

/// مصدرُ صفّ الحضور المخزَّن.
abstract final class AttendanceSource {
  static const manual = 'manual';
  static const device = 'device';
  static const bulk = 'bulk';
  static const leave = 'leave';
  static const legacy = 'legacy';
}

/// اليومُ بلا ساعاتٍ ودقائق (منتصفُ ليلِه المحلّيّ).
DateTime hrDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// ورديّةُ عمل. الدقائقُ من منتصف الليل؛ نهايةٌ ≤ البداية ⇒ تعبر منتصفَ
/// الليل فتنتهي في اليوم التالي.
class WorkShift {
  const WorkShift({
    this.id,
    required this.name,
    this.nameEn,
    required this.startMinute,
    required this.endMinute,
    this.breakMinutes = 0,
    this.graceLateMinutes = 0,
    this.daysOff = const {},
    this.overtimeAfterMinutes = 0,
    this.isActive = true,
    this.employeeCount = 0,
  });

  final int? id;
  final String name;
  final String? nameEn;
  final int startMinute;
  final int endMinute;
  final int breakMinutes;
  final int graceLateMinutes;

  /// أيّامُ الراحة الأسبوعيّة بقيم `DateTime.weekday` (‏١ الاثنين … ٧ الأحد).
  final Set<int> daysOff;

  /// الإضافيُّ يُحتسَب حين يتجاوز الانصرافُ نهايةَ الورديّة بهذا القدر فأكثر.
  final int overtimeAfterMinutes;
  final bool isActive;

  /// للعرض فقط: الموظفون المسنَدون إليها اليوم.
  final int employeeCount;

  bool get crossesMidnight => endMinute <= startMinute;

  /// مدّةُ العمل المجدولة بالدقائق بعد الاستراحة.
  int get scheduledMinutes {
    final span = crossesMidnight
        ? endMinute + 1440 - startMinute
        : endMinute - startMinute;
    final net = span - breakMinutes;
    return net < 0 ? 0 : net;
  }

  DateTime startOn(DateTime day) =>
      DateTime(day.year, day.month, day.day, 0, startMinute);

  DateTime endOn(DateTime day) => DateTime(
      day.year, day.month, day.day + (crossesMidnight ? 1 : 0), 0, endMinute);

  bool isDayOff(DateTime day) => daysOff.contains(day.weekday);

  static Set<int> decodeDays(String? csv) => {
        for (final p in (csv ?? '').split(',')) int.tryParse(p.trim()) ?? 0,
      }..removeWhere((d) => d < 1 || d > 7);

  static String? encodeDays(Set<int> days) {
    final sorted = days.where((d) => d >= 1 && d <= 7).toList()..sort();
    return sorted.isEmpty ? null : sorted.join(',');
  }

  static String formatMinute(int minute) {
    final m = minute % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  /// `HH:mm` ⇒ دقائق من منتصف الليل، أو `null`.
  static int? parseMinute(String text) {
    final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(text);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }
}

/// إسنادُ ورديّةٍ لموظفٍ من تاريخٍ (وإلى تاريخٍ شاملاً، أو مفتوح).
class ShiftAssignment {
  const ShiftAssignment({
    required this.id,
    required this.employeeId,
    required this.shiftId,
    required this.effectiveFrom,
    this.effectiveTo,
    this.notes,
    this.shiftName,
  });
  final int id;
  final int employeeId;
  final int shiftId;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? notes;
  final String? shiftName;

  bool covers(DateTime day) {
    final d = hrDay(day);
    if (d.isBefore(hrDay(effectiveFrom))) return false;
    final to = effectiveTo;
    return to == null || !d.isAfter(hrDay(to));
  }
}

/// الحالةُ التي يعلّمها المستخدمُ صراحةً على الصفّ المخزَّن.
abstract final class AttendanceMark {
  static const present = 'present';
  static const absent = 'absent';
  static const leave = 'leave';
  static const unpaidLeave = 'unpaid_leave';
}

/// صفُّ حضورٍ مخزَّنٌ ليومٍ واحد.
class AttendanceRecord {
  const AttendanceRecord({
    this.id,
    required this.employeeId,
    required this.workDate,
    this.checkIn,
    this.checkOut,
    this.mark,
    this.source = AttendanceSource.manual,
    this.leaveRequestId,
    this.notes,
    this.editReason,
    this.editedBy,
  });
  final int? id;
  final int employeeId;
  final DateTime workDate;
  final DateTime? checkIn;
  final DateTime? checkOut;

  /// [AttendanceMark] أو `null` (البصمتان وحدهما).
  final String? mark;
  final String source;
  final int? leaveRequestId;
  final String? notes;
  final String? editReason;
  final int? editedBy;

  bool get hasPunch =>
      checkIn != null || checkOut != null || mark == AttendanceMark.present;
}

/// إجازةٌ معتمدةٌ تغطّي اليوم.
class LeaveDayMark {
  const LeaveDayMark({required this.paid, this.requestId, this.typeName});
  final bool paid;
  final int? requestId;
  final String? typeName;
}

/// ما يلزم لحساب يومٍ واحد.
class DayContext {
  const DayContext({
    required this.day,
    required this.now,
    this.shift,
    this.record,
    this.holidayName,
    this.leave,
    this.weeklyOff = false,
    this.employed = true,
  });
  final DateTime day;
  final DateTime now;
  final WorkShift? shift;
  final AttendanceRecord? record;

  /// اسمُ العطلة الرسميّة إن كان اليومُ عطلة.
  final String? holidayName;
  final LeaveDayMark? leave;

  /// راحةٌ أسبوعيّةٌ لموظفٍ بلا ورديّة (من تقويم عطلات العمل القديم).
  final bool weeklyOff;
  final bool employed;

  bool get isHoliday => holidayName != null;
}

/// يومٌ محسوب.
class DayAttendance {
  const DayAttendance({
    required this.day,
    required this.status,
    this.lateMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.overtimeMinutes = 0,
    this.workedMinutes = 0,
    this.record,
    this.shift,
    this.holidayName,
    this.leave,
  });
  final DateTime day;
  final String status;
  final int lateMinutes;
  final int earlyLeaveMinutes;
  final int overtimeMinutes;
  final int workedMinutes;
  final AttendanceRecord? record;
  final WorkShift? shift;
  final String? holidayName;
  final LeaveDayMark? leave;

  bool get isWorked =>
      status == AttendanceStatus.present || status == AttendanceStatus.late;
}

/// يحسب حالةَ اليوم ودقائقَه — القاعدةُ الوحيدةُ للوحة والكشف والملخّص.
///
/// الترتيب: خارجَ الخدمة ← إجازةٌ معتمدة ← غيابٌ معلَّم ← حضور (وفي يوم
/// راحةٍ أو عطلةٍ يُحسَب كلُّه إضافيّاً) ← عطلة ← راحة ← لم ينتهِ ← غائب.
///
/// • التأخيرُ: دقائقُ الحضور بعد بداية الورديّة، ولا يُحتسَب إلّا إن تجاوز
///   السماح — فإن تجاوزه احتُسب كاملاً من البداية.
/// • الانصرافُ المبكّر: الدقائقُ قبل نهاية الورديّة.
/// • الإضافيّ: الدقائقُ بعد نهاية الورديّة متى بلغت حدَّ الورديّة.
DayAttendance computeDayAttendance(DayContext c) {
  final day = hrDay(c.day);
  final shift = c.shift;
  if (!c.employed) {
    return DayAttendance(day: day, status: AttendanceStatus.notEmployed);
  }
  final r = c.record;
  final leave = c.leave ??
      switch (r?.mark) {
        AttendanceMark.leave => const LeaveDayMark(paid: true),
        AttendanceMark.unpaidLeave => const LeaveDayMark(paid: false),
        _ => null,
      };
  if (leave != null) {
    return DayAttendance(
      day: day,
      status: leave.paid ? AttendanceStatus.leave : AttendanceStatus.unpaidLeave,
      record: r,
      shift: shift,
      leave: leave,
    );
  }
  if (r?.mark == AttendanceMark.absent) {
    return DayAttendance(
        day: day, status: AttendanceStatus.absent, record: r, shift: shift);
  }
  final offDay = c.isHoliday || (shift?.isDayOff(day) ?? c.weeklyOff);
  if (r != null && r.hasPunch) {
    final checkIn = r.checkIn;
    final checkOut = r.checkOut;
    var worked = 0;
    if (checkIn != null && checkOut != null && checkOut.isAfter(checkIn)) {
      worked = checkOut.difference(checkIn).inMinutes -
          (shift?.breakMinutes ?? 0);
      if (worked < 0) worked = 0;
    }
    if (offDay || shift == null) {
      return DayAttendance(
        day: day,
        status: AttendanceStatus.present,
        workedMinutes: worked,
        overtimeMinutes: offDay ? worked : 0,
        record: r,
        shift: shift,
        holidayName: c.holidayName,
      );
    }
    var late = 0;
    if (checkIn != null) {
      final m = checkIn.difference(shift.startOn(day)).inMinutes;
      if (m > shift.graceLateMinutes) late = m;
    }
    var early = 0;
    var overtime = 0;
    if (checkOut != null) {
      final m = shift.endOn(day).difference(checkOut).inMinutes;
      if (m > 0) early = m;
      final after = -m;
      if (after > 0 && after >= shift.overtimeAfterMinutes) overtime = after;
    }
    return DayAttendance(
      day: day,
      status: late > 0 ? AttendanceStatus.late : AttendanceStatus.present,
      lateMinutes: late,
      earlyLeaveMinutes: early,
      overtimeMinutes: overtime,
      workedMinutes: worked,
      record: r,
      shift: shift,
    );
  }
  if (c.isHoliday) {
    return DayAttendance(
        day: day,
        status: AttendanceStatus.holiday,
        record: r,
        shift: shift,
        holidayName: c.holidayName);
  }
  if (offDay) {
    return DayAttendance(
        day: day, status: AttendanceStatus.dayOff, record: r, shift: shift);
  }
  final dayEnd = shift?.endOn(day) ?? DateTime(day.year, day.month, day.day + 1);
  if (c.now.isBefore(dayEnd)) {
    return DayAttendance(
        day: day, status: AttendanceStatus.pending, record: r, shift: shift);
  }
  return DayAttendance(
      day: day, status: AttendanceStatus.absent, record: r, shift: shift);
}

/// ملخّصُ فترةٍ لموظف — ما يقرأه مسيّرُ الرواتب (الجزء ٣).
class AttendanceSummary {
  const AttendanceSummary({
    required this.employeeId,
    required this.from,
    required this.to,
    this.workedDays = 0,
    this.lateDays = 0,
    this.absentDays = 0,
    this.lateMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.overtimeMinutes = 0,
    this.workedMinutes = 0,
    this.paidLeaveDays = 0,
    this.unpaidLeaveDays = 0,
    this.holidays = 0,
    this.daysOff = 0,
    this.pendingDays = 0,
    this.days = const [],
  });

  final int employeeId;
  final DateTime from;
  final DateTime to;

  /// أيّامٌ حضرها (حاضرٌ أو متأخّر، وتشمل العملَ في يوم راحةٍ أو عطلة).
  final int workedDays;
  final int lateDays;
  final int absentDays;
  final int lateMinutes;
  final int earlyLeaveMinutes;
  final int overtimeMinutes;
  final int workedMinutes;
  final int paidLeaveDays;
  final int unpaidLeaveDays;
  final int holidays;
  final int daysOff;

  /// أيّامُ عملٍ لم تنتهِ بعد (اليومُ الجاري أو المستقبل).
  final int pendingDays;
  final List<DayAttendance> days;

  double get overtimeHours => overtimeMinutes / 60;

  static AttendanceSummary of(
    int employeeId,
    DateTime from,
    DateTime to,
    List<DayAttendance> days,
  ) {
    int count(String s) => days.where((d) => d.status == s).length;
    int sum(int Function(DayAttendance) f) =>
        days.fold(0, (a, d) => a + f(d));
    return AttendanceSummary(
      employeeId: employeeId,
      from: hrDay(from),
      to: hrDay(to),
      workedDays: days.where((d) => d.isWorked).length,
      lateDays: count(AttendanceStatus.late),
      absentDays: count(AttendanceStatus.absent),
      lateMinutes: sum((d) => d.lateMinutes),
      earlyLeaveMinutes: sum((d) => d.earlyLeaveMinutes),
      overtimeMinutes: sum((d) => d.overtimeMinutes),
      workedMinutes: sum((d) => d.workedMinutes),
      paidLeaveDays: count(AttendanceStatus.leave),
      unpaidLeaveDays: count(AttendanceStatus.unpaidLeave),
      holidays: count(AttendanceStatus.holiday),
      daysOff: count(AttendanceStatus.dayOff),
      pendingDays: count(AttendanceStatus.pending),
      days: days,
    );
  }
}

/// عطلةٌ رسميّةٌ بتاريخها (على مستوى الشركة).
class PublicHoliday {
  const PublicHoliday({
    this.id,
    required this.date,
    required this.name,
    this.nameEn,
  });
  final int? id;
  final DateTime date;
  final String name;
  final String? nameEn;
}

/// صفٌّ في لوحة الحضور اليوميّة.
class AttendanceBoardRow {
  const AttendanceBoardRow({
    required this.employeeId,
    required this.name,
    required this.attendance,
    this.code,
    this.departmentName,
    this.branchName,
  });
  final int employeeId;
  final String name;
  final String? code;
  final String? departmentName;
  final String? branchName;
  final DayAttendance attendance;
}
