// J4 (الجزء ٢) — مزوّداتُ الحضور والإجازات والورديّات. كلُّ قراءةٍ عبر
// `databaseProvider`، والصفوفُ محصورةٌ بفروع المستخدم (H6) كسجلّ الموظفين.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/providers.dart';
import '../../domain/models/hr_attendance.dart';
import '../../domain/models/hr_leave.dart';
import 'hr_picpos_providers.dart';

final hrShiftsProvider = FutureProvider.autoDispose<List<WorkShift>>(
    (ref) => ref.watch(databaseProvider).listWorkShifts());

/// الإسناداتُ كلُّها (‏`null`) أو لموظف.
final hrShiftAssignmentsProvider = FutureProvider.autoDispose
    .family<List<ShiftAssignment>, int?>((ref, employeeId) =>
        ref.watch(databaseProvider).listShiftAssignments(employeeId: employeeId));

final hrHolidaysProvider = FutureProvider.autoDispose
    .family<List<PublicHoliday>, int>(
        (ref, year) => ref.watch(databaseProvider).listPublicHolidays(year: year));

/// لوحةُ يومٍ (يوم، فرع، قسم) محصورةٌ بنطاق المستخدم.
final hrAttendanceBoardProvider = FutureProvider.autoDispose
    .family<List<AttendanceBoardRow>, (DateTime, int?, int?)>((ref, q) async {
  final db = ref.watch(databaseProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  final profiles = {
    for (final p in await ref.watch(hrProfilesProvider.future)) p.id: p,
  };
  final rows = await db.attendanceBoard(q.$1, branchId: q.$2, departmentId: q.$3);
  return [
    for (final r in rows)
      if (profiles.containsKey(r.employeeId) &&
          scope.isAllowed(profiles[r.employeeId]!.branchId))
        r,
  ];
});

/// أيّامُ شهرٍ لموظف (موظف، سنة، شهر).
final hrMonthAttendanceProvider = FutureProvider.autoDispose
    .family<List<DayAttendance>, (int, int, int)>((ref, q) {
  final from = DateTime(q.$2, q.$3);
  final to = DateTime(q.$2, q.$3 + 1, 0);
  return ref.watch(databaseProvider).employeeAttendanceDays(q.$1, from, to);
});

final hrMonthSummaryProvider = FutureProvider.autoDispose
    .family<AttendanceSummary, (int, int, int)>((ref, q) {
  final from = DateTime(q.$2, q.$3);
  final to = DateTime(q.$2, q.$3 + 1, 0);
  return ref.watch(databaseProvider).attendanceSummary(q.$1, from, to);
});

final hrLeaveTypesProvider = FutureProvider.autoDispose<List<LeaveType>>(
    (ref) => ref.watch(databaseProvider).listLeaveTypes());

/// الطلبات (موظف أو الكلّ، حالة أو الكلّ) محصورةٌ بنطاق المستخدم.
final hrLeaveRequestsProvider = FutureProvider.autoDispose
    .family<List<LeaveRequest>, (int?, String?)>((ref, q) async {
  final scope = await ref.watch(branchScopeProvider.future);
  final profiles = {
    for (final p in await ref.watch(hrProfilesProvider.future)) p.id: p,
  };
  final rows = await ref
      .watch(databaseProvider)
      .listLeaveRequests(employeeId: q.$1, status: q.$2);
  return [
    for (final r in rows)
      if (profiles.containsKey(r.employeeId) &&
          scope.isAllowed(profiles[r.employeeId]!.branchId))
        r,
  ];
});

/// أرصدةُ موظفٍ في سنة (موظف، سنة).
final hrLeaveBalancesProvider = FutureProvider.autoDispose
    .family<List<LeaveEntitlement>, (int, int)>((ref, q) =>
        ref.watch(databaseProvider).employeeLeaveBalances(q.$1, q.$2));

/// يُعيد قراءةَ كلِّ ما يتغيّر بعد كتابةٍ في الحضور أو الإجازات أو الورديّات.
void refreshHrAttendance(WidgetRef ref) {
  ref.invalidate(hrShiftsProvider);
  ref.invalidate(hrShiftAssignmentsProvider);
  ref.invalidate(hrHolidaysProvider);
  ref.invalidate(hrAttendanceBoardProvider);
  ref.invalidate(hrMonthAttendanceProvider);
  ref.invalidate(hrMonthSummaryProvider);
  ref.invalidate(hrLeaveTypesProvider);
  ref.invalidate(hrLeaveRequestsProvider);
  ref.invalidate(hrLeaveBalancesProvider);
  ref.invalidate(hrHistoryProvider);
}
