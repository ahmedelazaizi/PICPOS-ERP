// J4 (الجزء ٢) — الورديّاتُ والحضورُ والإجازات على قاعدةٍ حقيقيّة.
//
// Proves:
//  * shift assignment keeps history (the open row is closed the day before,
//    a same-day re-assignment replaces it) and bulk-assigns by department;
//  * the computed day status: grace, late, early leave, overtime threshold,
//    a midnight-crossing shift, day off, public holiday, worked day off,
//    absent vs pending;
//  * the fingerprint CSV import: column mapping, the error rows, the
//    midnight shift's dawn punch on the previous work day, earliest/latest
//    merge on re-import;
//  * leave balances: yearly / monthly accrual, carry-over capped, a manual
//    opening that is not recomputed;
//  * the request workflow: draft → submitted → approved by the direct
//    manager (not by another user without `hr_leave_approve`), rejected,
//    cancelled; overlap and balance and attachment refusals; approval marks
//    the work days «إجازة», consumes the balance, mirrors the legacy table
//    and logs history — cancel undoes it;
//  * `attendanceSummary` numbers (the API part 3 reads);
//  * legacy attendance / leaves / balances / holidays are copied without
//    loss (idempotent), and the permission backfill;
//  * the seven v192 tables ride every sync list and cross a `SELECT *` copy.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/domain/models/hr_attendance.dart';
import 'package:picpos_erp/domain/models/hr_attendance_import.dart';
import 'package:picpos_erp/domain/models/hr_employee_file.dart';
import 'package:picpos_erp/domain/models/hr_leave.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/id_namespace_service.dart';

const _newTables = [
  'hr_shifts',
  'hr_shift_assignments',
  'hr_public_holidays',
  'hr_leave_types',
  'hr_leave_requests',
  'hr_leave_entitlements',
  'hr_attendance_days',
];

/// ٢ يونيو ٢٠٢٥ يومُ اثنين.
final _mon = DateTime(2025, 6, 2);
DateTime _d(int day, [int h = 0, int m = 0]) => DateTime(2025, 6, day, h, m);
final _now = DateTime(2026, 1, 1);

const _dayShift = WorkShift(
  name: 'صباحي',
  startMinute: 9 * 60,
  endMinute: 17 * 60,
  breakMinutes: 60,
  graceLateMinutes: 10,
  overtimeAfterMinutes: 30,
  daysOff: {DateTime.friday, DateTime.saturday},
);

const _nightShift = WorkShift(
  name: 'ليلي',
  startMinute: 22 * 60,
  endMinute: 6 * 60,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await db.ensureDefaultLeaveTypes();
  });
  tearDown(() async {
    await db.close();
    SyncInterceptor.instance = null;
  });

  Future<int> employee(String name,
          {String? code, int? department, int? managerId}) =>
      db.saveEmployeeProfile(EmployeeProfile(
        name: name,
        code: code,
        departmentId: department,
        managerId: managerId,
        hireDate: DateTime(2020, 1, 1),
      ));

  Future<int> typeId(String code) async =>
      (await db.listLeaveTypes()).firstWhere((t) => t.code == code).id!;

  Future<void> punch(int emp, DateTime day, DateTime? inAt, DateTime? outAt) =>
      db.saveAttendanceEntry(
          employeeId: emp,
          day: day,
          checkIn: inAt,
          checkOut: outAt,
          reason: 'إدخال');

  group('حسابُ اليوم (قاعدةٌ خالصة)', () {
    DayAttendance day(DateTime d,
            {WorkShift? shift = _dayShift,
            DateTime? inAt,
            DateTime? outAt,
            String? holiday,
            DateTime? now}) =>
        computeDayAttendance(DayContext(
          day: d,
          now: now ?? _now,
          shift: shift,
          holidayName: holiday,
          record: inAt == null && outAt == null
              ? null
              : AttendanceRecord(
                  employeeId: 1, workDate: d, checkIn: inAt, checkOut: outAt),
        ));

    test('السماحُ والتأخيرُ والانصرافُ المبكّرُ وحدُّ الإضافيّ', () {
      final a = day(_mon, inAt: _d(2, 9, 10), outAt: _d(2, 17));
      expect([a.status, a.lateMinutes], [AttendanceStatus.present, 0],
          reason: '10 minutes is within the grace');
      final b = day(_mon, inAt: _d(2, 9, 11), outAt: _d(2, 16, 40));
      expect([b.status, b.lateMinutes, b.earlyLeaveMinutes],
          [AttendanceStatus.late, 11, 20]);
      expect(day(_mon, inAt: _d(2, 9), outAt: _d(2, 17, 29)).overtimeMinutes, 0,
          reason: 'below the 30-minute overtime threshold');
      final c = day(_mon, inAt: _d(2, 8, 50), outAt: _d(2, 17, 45));
      expect([c.overtimeMinutes, c.workedMinutes], [45, 8 * 60 + 55 - 60]);
    });

    test('ورديّةٌ تعبر منتصفَ الليل', () {
      final n = day(_mon,
          shift: _nightShift, inAt: _d(2, 22, 15), outAt: _d(3, 7));
      expect(n.status, AttendanceStatus.late);
      expect(n.lateMinutes, 15);
      expect(n.overtimeMinutes, 60);
      expect(n.earlyLeaveMinutes, 0);
      expect(n.workedMinutes, 8 * 60 + 45);
      expect(_nightShift.crossesMidnight, isTrue);
      expect(_nightShift.scheduledMinutes, 480);
      final early = day(_mon,
          shift: _nightShift, inAt: _d(2, 22), outAt: _d(3, 5, 30));
      expect(early.earlyLeaveMinutes, 30);
    });

    test('الراحةُ والعطلةُ والعملُ فيهما، والغيابُ والانتظار', () {
      expect(day(_d(6)).status, AttendanceStatus.dayOff, reason: 'Friday');
      expect(day(_mon, holiday: 'عيد').status, AttendanceStatus.holiday);
      final worked = day(_d(7), inAt: _d(7, 10), outAt: _d(7, 14));
      expect([worked.status, worked.overtimeMinutes],
          [AttendanceStatus.present, 180],
          reason: 'a worked day off is overtime (net of the break)');
      expect(day(_mon).status, AttendanceStatus.absent);
      expect(day(_mon, now: _d(2, 12)).status, AttendanceStatus.pending,
          reason: 'the shift has not ended yet');
      expect(
          computeDayAttendance(DayContext(
                  day: _mon, now: _now, shift: _dayShift, employed: false))
              .status,
          AttendanceStatus.notEmployed);
    });
  });

  group('الورديّاتُ وإسنادُها', () {
    test('السجلُّ يبقى، وإعادةُ الإسناد في اليوم نفسِه تستبدل، والجماعيّ',
        () async {
      final a = await db.saveWorkShift(_dayShift);
      final b = await db.saveWorkShift(_nightShift);
      expect(() => db.saveWorkShift(_dayShift), throwsA(isA<HrException>()),
          reason: 'duplicate name');
      expect(
          () => db.saveWorkShift(const WorkShift(
              name: 'x', startMinute: 600, endMinute: 600)),
          throwsA(isA<HrException>()));
      final e = await employee('سامي');
      await db.assignShift(employeeId: e, shiftId: a, from: DateTime(2025, 1, 1));
      await db.assignShift(employeeId: e, shiftId: b, from: DateTime(2025, 2, 1));
      var history = await db.listShiftAssignments(employeeId: e);
      expect([for (final h in history) (h.shiftId, h.effectiveTo)], [
        (b, null),
        (a, DateTime(2025, 1, 31)),
      ]);
      await db.assignShift(employeeId: e, shiftId: a, from: DateTime(2025, 2, 1));
      history = await db.listShiftAssignments(employeeId: e);
      expect(history.map((h) => h.shiftId), [a, a],
          reason: 'the same-day assignment replaced the night one');
      expect((await db.currentShiftIds(day: DateTime(2025, 1, 15)))[e], a);
      final events = await db.listEmployeeHistory(e);
      expect(events.where((x) => x.eventType == HrEventType.shiftChange),
          hasLength(3));
      expect(() => db.deleteWorkShift(a), throwsA(isA<HrException>()));

      final dept = await db.saveHrDepartment(name: 'المخازن');
      final s1 = await employee('أ', department: dept);
      final s2 = await employee('ب', department: dept);
      await employee('خارج القسم');
      final n = await db.assignShiftBulk(
          shiftId: b, from: DateTime(2025, 3, 1), departmentId: dept);
      expect(n, 2);
      final current = await db.currentShiftIds(day: DateTime(2025, 3, 2));
      expect([current[s1], current[s2]], [b, b]);
      expect((await db.listWorkShifts()).firstWhere((s) => s.id == b).name,
          'ليلي');
    });
  });

  group('الحضورُ وملخّصُ الفترة', () {
    test('اللوحةُ والكشفُ و`attendanceSummary` بأرقامها', () async {
      final manager = await employee('المدير');
      final e = await employee('عامل', managerId: manager);
      final shift = await db.saveWorkShift(_dayShift);
      await db.assignShift(employeeId: e, shiftId: shift, from: DateTime(2025));
      await db.savePublicHoliday(PublicHoliday(date: _d(5), name: 'عيد'));
      expect(
          () => db.savePublicHoliday(PublicHoliday(date: _d(5), name: 'مكرر')),
          throwsA(isA<HrException>()));
      await punch(e, _d(2), _d(2, 9, 5), _d(2, 17));
      await punch(e, _d(3), _d(3, 9, 20), _d(3, 16, 30));
      await punch(e, _d(4), _d(4, 8, 55), _d(4, 18));
      await punch(e, _d(7), _d(7, 10), _d(7, 14));
      expect(
          () => db.saveAttendanceEntry(
              employeeId: e, day: _d(4), checkIn: _d(4, 9), reason: ' '),
          throwsA(isA<HrException>()),
          reason: 'a manual entry needs a reason');
      expect(
          () => punch(e, _d(4), _d(4, 18), _d(4, 9)),
          throwsA(isA<HrException>()));

      final annual = await db.saveLeaveRequest(
          LeaveRequest(
              employeeId: e,
              leaveTypeId: await typeId(LeaveTypeCode.annual),
              startDate: _d(9),
              endDate: _d(10)),
          submit: true);
      await db.approveLeaveRequest(annual, canApproveAll: true);
      final unpaid = await db.saveLeaveRequest(
          LeaveRequest(
              employeeId: e,
              leaveTypeId: await typeId(LeaveTypeCode.unpaid),
              startDate: _d(11),
              endDate: _d(11)),
          submit: true);
      await db.approveLeaveRequest(unpaid, canApproveAll: true);

      final s = await db.attendanceSummary(e, _d(2), _d(12), now: _now);
      expect(s.workedDays, 4, reason: 'Mon, Tue, Wed and the worked Saturday');
      expect(s.lateDays, 1);
      expect(s.lateMinutes, 20);
      expect(s.earlyLeaveMinutes, 30);
      expect(s.overtimeMinutes, 60 + 180);
      expect(s.holidays, 1);
      expect(s.daysOff, 1, reason: 'Friday (Saturday was worked)');
      expect(s.paidLeaveDays, 2);
      expect(s.unpaidLeaveDays, 1);
      expect(s.absentDays, 2, reason: 'Sunday 8 and Thursday 12');
      expect(s.pendingDays, 0);

      final board = await db.attendanceBoard(_d(3), now: _now);
      final row = board.firstWhere((r) => r.employeeId == e);
      expect(row.attendance.status, AttendanceStatus.late);
      expect(row.attendance.shift?.name, 'صباحي');
      expect(board.firstWhere((r) => r.employeeId == manager).attendance.status,
          AttendanceStatus.absent,
          reason: 'no shift, no punch, past day');

      final days =
          await db.employeeAttendanceDays(e, DateTime(2025, 6), _d(30), now: _now);
      expect(days, hasLength(30));
      expect(days[8].status, AttendanceStatus.leave);
    });

    test('«تحضير الكلّ» يحضّر أيّامَ العمل وحدَها، والتصحيحُ يُسجَّل',
        () async {
      final shift = await db.saveWorkShift(_dayShift);
      final a = await employee('أ');
      final b = await employee('ب');
      final c = await employee('ج');
      for (final e in [a, b]) {
        await db.assignShift(employeeId: e, shiftId: shift, from: DateTime(2025));
      }
      await db.saveAttendanceEntry(
          employeeId: b,
          day: _mon,
          mark: AttendanceMark.absent,
          reason: 'غياب بلا إذن');
      final n = await db.markAllPresent(_mon, now: _now);
      expect(n, 2, reason: 'a (shift) and c (no shift); b is marked absent');
      final board = {
        for (final r in await db.attendanceBoard(_mon, now: _now))
          r.employeeId: r.attendance,
      };
      expect(board[a]!.status, AttendanceStatus.present);
      expect(board[a]!.record!.checkIn, _d(2, 9));
      expect(board[a]!.record!.source, AttendanceSource.bulk);
      expect(board[b]!.status, AttendanceStatus.absent);
      expect(board[c]!.status, AttendanceStatus.present);
      expect(await db.markAllPresent(_d(6), now: _now), 1,
          reason: 'Friday is a day off for the shift employees');

      await db.saveAttendanceEntry(
          employeeId: a,
          day: _mon,
          checkIn: _d(2, 9, 30),
          checkOut: _d(2, 17),
          reason: 'تصحيح البصمة',
          actorUserId: 7);
      final edit = (await db.listEmployeeHistory(a))
          .firstWhere((x) => x.eventType == HrEventType.attendanceEdit);
      expect(edit.fromValue, contains('09:00'));
      expect(edit.toValue, contains('09:30'));
      expect(edit.notes, contains('تصحيح البصمة'));
      expect(edit.userId, 7);
      final legacy = await (db.select(db.employeeAttendance)
            ..where((x) => x.employeeId.equals(a)))
          .getSingle();
      expect(legacy.checkIn, _d(2, 9, 30),
          reason: 'mirrored to the legacy payroll table');
      await db.saveAttendanceEntry(
          employeeId: a, day: _mon, reason: 'حذف القيد');
      expect(await db.attendanceRecordFor(a, _mon), isNull);
      expect(
          await (db.select(db.employeeAttendance)
                ..where((x) => x.employeeId.equals(a)))
              .get(),
          isEmpty);
    });
  });

  group('استيرادُ البصمة CSV', () {
    test('ربطُ الأعمدة وأسطرُ الخطأ والورديّةُ الليليّة والدمج', () async {
      final day = await db.saveWorkShift(_dayShift);
      final night = await db.saveWorkShift(_nightShift);
      final a = await employee('نهاري', code: 'EMP-A');
      final n = await employee('ليلي', code: 'EMP-N');
      await db.assignShift(employeeId: a, shiftId: day, from: DateTime(2025));
      await db.assignShift(employeeId: n, shiftId: night, from: DateTime(2025));
      const csv = 'code;when;dir\n'
          'EMP-A;2025-06-02 09:03:00;IN\n'
          'emp-a;2025-06-02 17:10:00;OUT\n'
          'EMP-N;03/06/2025 05:55;out\n'
          'EMP-N;2025-06-02 21:58;in\n'
          'NOPE;2025-06-02 09:00;in\n'
          'EMP-A;2025-13-02 09:00;in\n'
          'EMP-A;2025-06-03 09:00;maybe\n'
          ';2025-06-03 09:00;in\n';
      const mapping = AttendanceCsvMapping(
          codeColumn: 0, dateTimeColumn: 1, directionColumn: 2);
      final preview = await db.previewAttendanceImport(csv, mapping);
      expect(preview.rows, hasLength(8));
      expect({for (final e in preview.errors) e.line: e.error}, {
        6: 'كود الموظف غير موجود',
        7: 'تاريخ ووقت غير مفهوم',
        8: 'اتجاه البصمة غير مفهوم',
        9: 'كود الموظف فارغ',
      });
      final nightRow = preview.rows.firstWhere((r) => r.line == 4);
      expect(nightRow.workDate, _mon,
          reason: 'the dawn punch belongs to the previous night shift');
      expect(preview.days, hasLength(2));
      expect(await db.applyAttendanceImport(preview), 2);

      final board = {
        for (final r in await db.attendanceBoard(_mon, now: _now))
          r.employeeId: r.attendance,
      };
      expect(board[a]!.record!.checkIn, _d(2, 9, 3));
      expect(board[a]!.record!.checkOut, _d(2, 17, 10));
      expect(board[a]!.record!.source, AttendanceSource.device);
      expect(board[n]!.record!.checkIn, _d(2, 21, 58));
      expect(board[n]!.record!.checkOut, _d(3, 5, 55));
      expect(board[n]!.earlyLeaveMinutes, 5);

      // No direction column: first punch in, last punch out — merged with
      // what is already there (earliest in, latest out).
      const plain = 'EMP-A,2025-06-02 08:58\nEMP-A,2025-06-02 12:00\n'
          'EMP-A,2025-06-02 16:00\n';
      final p2 = await db.previewAttendanceImport(
          plain, const AttendanceCsvMapping(hasHeader: false));
      expect(p2.errors, isEmpty);
      expect(p2.days.single.checkIn, _d(2, 8, 58));
      expect(p2.days.single.checkOut, _d(2, 16));
      await db.applyAttendanceImport(p2);
      final merged = (await db.attendanceRecordFor(a, _mon))!;
      expect([merged.checkIn, merged.checkOut], [_d(2, 8, 58), _d(2, 17, 10)]);
    });

    test('التحليلُ: المحدِّداتُ والصيغ وعمودُ الوقت المنفصل', () {
      expect(parsePunchDateTime('2025-06-02T09:03:00'), _d(2, 9, 3));
      expect(parsePunchDateTime('02/06/2025 9:03 PM'), _d(2, 21, 3));
      expect(parsePunchDateTime('31/02/2025 09:00'), isNull);
      expect(parsePunchDateTime('2025-06-02'), isNull);
      expect(parsePunchDateTime('2025-06-02', time: '07:30'), _d(2, 7, 30));
      expect(splitCsvLine('"a,b",c', ','), ['a,b', 'c']);
      final rows = parseAttendanceCsv(
          '\uFEFFid\tdate\ttime\n5\t2025-06-02\t08:00\n',
          const AttendanceCsvMapping(timeColumn: 2));
      expect(rows.single.code, '5');
      expect(rows.single.at, _d(2, 8));
    });
  });

  group('أرصدةُ الإجازات', () {
    test('الاستحقاقُ السنويُّ والشهريّ', () {
      const monthly = LeaveType(
          code: 'custom', name: 'شهري', yearlyDays: 24, accrual: 'monthly');
      expect(accruedLeaveDays(monthly, 2025, DateTime(2025, 3, 15), DateTime(2020)),
          6);
      expect(
          accruedLeaveDays(
              monthly, 2025, DateTime(2025, 3, 15), DateTime(2025, 2, 10)),
          4);
      expect(accruedLeaveDays(monthly, 2025, DateTime(2026, 1, 2), null), 24);
      expect(accruedLeaveDays(monthly, 2025, DateTime(2024, 12, 1), null), 0);
      const yearly = LeaveType(code: 'annual', name: 'سنوي', yearlyDays: 21);
      expect(accruedLeaveDays(yearly, 2025, DateTime(2025, 1, 1), null), 21);
      const unpaid =
          LeaveType(code: 'unpaid', name: 'بدون', isPaid: false, yearlyDays: 5);
      expect(accruedLeaveDays(unpaid, 2025, DateTime(2025, 6), null), 0);
    });

    test('الترحيلُ مقيَّدٌ بحدّه، والافتتاحيُّ اليدويُّ لا يُعاد حسابُه',
        () async {
      final annual = (await db.listLeaveTypes())
          .firstWhere((t) => t.code == LeaveTypeCode.annual);
      await db.saveLeaveType(LeaveType(
          id: annual.id,
          code: annual.code,
          name: annual.name,
          yearlyDays: 21,
          carryOverMax: 5));
      final e = await employee('موظف');
      final shift = await db.saveWorkShift(_dayShift);
      await db.assignShift(employeeId: e, shiftId: shift, from: DateTime(2024));
      await db.refreshLeaveBalances(2024,
          employeeId: e, asOf: DateTime(2024, 12, 31));
      // Sun 3 → Thu 14 March 2024 = 12 days minus Fri 8 and Sat 9.
      final r = await db.saveLeaveRequest(
          LeaveRequest(
              employeeId: e,
              leaveTypeId: annual.id!,
              startDate: DateTime(2024, 3, 3),
              endDate: DateTime(2024, 3, 14)),
          submit: true);
      await db.approveLeaveRequest(r, canApproveAll: true);
      final y2024 = (await db.employeeLeaveBalances(e, 2024,
              asOf: DateTime(2024, 12, 31)))
          .firstWhere((b) => b.leaveTypeId == annual.id);
      expect([y2024.accruedDays, y2024.usedDays, y2024.remaining],
          [21, 10, 11]);
      final y2025 = (await db.employeeLeaveBalances(e, 2025,
              asOf: DateTime(2025, 6, 1)))
          .firstWhere((b) => b.leaveTypeId == annual.id);
      expect(y2025.openingDays, 5, reason: '11 remaining, capped at 5');
      expect(y2025.remaining, 26);

      await db.setLeaveOpeningBalance(
          employeeId: e, leaveTypeId: annual.id!, year: 2025, days: 2);
      final locked = (await db.employeeLeaveBalances(e, 2025))
          .firstWhere((b) => b.leaveTypeId == annual.id);
      expect([locked.openingDays, locked.openingLocked], [2, true]);

      final other = await employee('بلا سابق');
      final fresh = (await db.employeeLeaveBalances(other, 2025))
          .firstWhere((b) => b.leaveTypeId == annual.id);
      expect(fresh.openingDays, 0);
      expect(
          (await db.employeeLeaveBalances(other, 2025)).map((b) => b.type!.code).toSet(),
          {LeaveTypeCode.annual, LeaveTypeCode.sick, LeaveTypeCode.emergency},
          reason: 'unpaid has no entitlement row');
    });
  });

  group('دورةُ طلب الإجازة', () {
    test('المديرُ المباشرُ يعتمد، والاعتمادُ يعلّم الحضورَ ويستهلك الرصيد، '
        'والإلغاءُ يردّهما', () async {
      final uManager = await db.createUser(
          username: 'mgr', password: 'pw-mgr-1', displayName: 'Manager');
      final uOther = await db.createUser(
          username: 'other', password: 'pw-oth-1', displayName: 'Other');
      final manager = await employee('المدير');
      await db.linkEmployeeUser(employeeId: manager, userId: uManager);
      final e = await employee('موظف', managerId: manager);
      final shift = await db.saveWorkShift(_dayShift);
      await db.assignShift(employeeId: e, shiftId: shift, from: DateTime(2025));
      await punch(e, _d(10), _d(10, 9), _d(10, 12));
      final annual = await typeId(LeaveTypeCode.annual);

      final id = await db.saveLeaveRequest(LeaveRequest(
          employeeId: e,
          leaveTypeId: annual,
          startDate: _d(9),
          endDate: _d(13),
          reason: 'سفر'));
      var r = await db.getLeaveRequest(id);
      expect([r.status, r.days], [LeaveRequestStatus.draft, 4],
          reason: 'Mon–Fri minus Friday off');
      await expectLater(
          db.saveLeaveRequest(LeaveRequest(
              employeeId: e,
              leaveTypeId: annual,
              startDate: _d(12),
              endDate: _d(16))),
          throwsA(isA<HrException>()),
          reason: 'overlaps the draft');
      await expectLater(
          db.approveLeaveRequest(id, actorUserId: uManager),
          throwsA(isA<HrException>()),
          reason: 'a draft is not decided');
      await db.submitLeaveRequest(id);
      await expectLater(
          db.approveLeaveRequest(id, actorUserId: uOther),
          throwsA(isA<HrException>()),
          reason: 'not the manager and no hr_leave_approve');
      expect(await db.isDirectManagerUser(uManager, e), isTrue);
      await db.approveLeaveRequest(id, actorUserId: uManager, note: 'موافق');
      r = await db.getLeaveRequest(id);
      expect([r.status, r.decidedBy, r.decisionNote],
          [LeaveRequestStatus.approved, uManager, 'موافق']);

      final days = await db.employeeAttendanceDays(e, _d(9), _d(13), now: _now);
      expect([for (final d in days) d.status], [
        AttendanceStatus.leave,
        AttendanceStatus.leave,
        AttendanceStatus.leave,
        AttendanceStatus.leave,
        AttendanceStatus.dayOff,
      ]);
      final marked = (await db.attendanceRecordFor(e, _d(10)))!;
      expect([marked.mark, marked.leaveRequestId, marked.checkIn],
          [AttendanceMark.leave, id, _d(10, 9)],
          reason: 'the punch stays as evidence');
      final balance = (await db.employeeLeaveBalances(e, 2025))
          .firstWhere((b) => b.leaveTypeId == annual);
      expect([balance.usedDays, balance.remaining], [4, 17]);
      final legacy = await (db.select(db.employeeAttendance)
            ..where((x) => x.employeeId.equals(e))
            ..where((x) => x.status.equals('leave')))
          .get();
      expect(legacy, hasLength(4));
      expect(
          (await db.listEmployeeHistory(e))
              .where((x) => x.eventType == HrEventType.leave)
              .map((x) => x.toValue),
          containsAll([LeaveRequestStatus.submitted, LeaveRequestStatus.approved]));

      await db.cancelLeaveRequest(id, actorUserId: uManager);
      expect((await db.getLeaveRequest(id)).status, LeaveRequestStatus.cancelled);
      expect(await db.attendanceRecordFor(e, _d(9)), isNull);
      final kept = (await db.attendanceRecordFor(e, _d(10)))!;
      expect([kept.mark, kept.leaveRequestId, kept.checkIn],
          [null, null, _d(10, 9)]);
      expect(
          (await db.employeeLeaveBalances(e, 2025))
              .firstWhere((b) => b.leaveTypeId == annual)
              .usedDays,
          0);
      expect(
          await (db.select(db.employeeAttendance)
                ..where((x) => x.status.equals('leave')))
              .get(),
          isEmpty);
    });

    test('الرفضُ بالصلاحية، والمرفقُ المطلوب، والرصيدُ غيرُ الكافي', () async {
      final e = await employee('موظف');
      final sick = await typeId(LeaveTypeCode.sick);
      final emergency = await typeId(LeaveTypeCode.emergency);
      await expectLater(
          db.saveLeaveRequest(
              LeaveRequest(
                  employeeId: e,
                  leaveTypeId: sick,
                  startDate: _d(2),
                  endDate: _d(2)),
              submit: true),
          throwsA(isA<HrException>()),
          reason: 'sick leave requires an attachment');
      final draft = (await db.listLeaveRequests(employeeId: e)).single;
      expect(draft.status, LeaveRequestStatus.draft,
          reason: 'the refused submit keeps the draft');
      await db.cancelLeaveRequest(draft.id!);

      final ok = await db.saveLeaveRequest(
          LeaveRequest(
              employeeId: e,
              leaveTypeId: sick,
              startDate: _d(2),
              endDate: _d(3),
              attachmentPath: r'C:\report.pdf'),
          submit: true);
      await db.rejectLeaveRequest(ok, canApproveAll: true, note: 'لا');
      expect((await db.getLeaveRequest(ok)).status, LeaveRequestStatus.rejected);
      expect(await db.attendanceRecordFor(e, _d(2)), isNull);
      await expectLater(
          db.cancelLeaveRequest(ok), throwsA(isA<HrException>()));

      await expectLater(
          db.saveLeaveRequest(
              LeaveRequest(
                  employeeId: e,
                  leaveTypeId: emergency,
                  startDate: _d(2),
                  endDate: _d(5)),
              submit: true),
          throwsA(isA<HrException>()),
          reason: '4 working days > 3 emergency days');
      await expectLater(
          db.saveLeaveRequest(LeaveRequest(
              employeeId: e,
              leaveTypeId: emergency,
              startDate: _d(5),
              endDate: _d(2))),
          throwsA(isA<HrException>()));
      expect(await db.listLeaveRequests(status: LeaveRequestStatus.rejected),
          hasLength(1));
    });
  });

  group('النقلُ من الشاشة القديمة والصلاحيّات', () {
    test('الحضورُ والإجازاتُ والأرصدةُ والعطلاتُ القديمة تُنسَخ بلا فقد',
        () async {
      final e = await employee('قديم');
      final atts = [
        (DateTime(2025, 6, 2), _d(2, 9), _d(2, 17), 'present'),
        (DateTime(2025, 6, 3), null, null, 'absent'),
        (DateTime(2025, 6, 4), null, null, 'leave'),
      ];
      for (final (day, inAt, outAt, status) in atts) {
        await db.into(db.employeeAttendance).insert(
            EmployeeAttendanceCompanion.insert(
                employeeId: e,
                date: day,
                checkIn: Value(inAt),
                checkOut: Value(outAt),
                status: Value(status)));
      }
      await db.into(db.employeeLeaves).insert(EmployeeLeavesCompanion.insert(
          employeeId: e,
          leaveType: 'sick',
          startDate: _d(4),
          endDate: _d(4),
          days: 1,
          status: const Value('approved')));
      await db.into(db.leaveBalances).insert(LeaveBalancesCompanion.insert(
          employeeId: e, leaveType: 'annual', totalDays: 30, year: 2025));
      await db.into(db.workHolidays).insert(
          WorkHolidaysCompanion.insert(name: 'عيد', date: Value(_d(5))));
      await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'الجمعة', weekday: const Value(DateTime.friday)));

      await db.migrateLegacyHrAttendance();
      await db.migrateLegacyHrAttendance(); // idempotent
      Future<int> count(String t) async => (await db
              .customSelect('SELECT COUNT(*) AS n FROM $t')
              .getSingle())
          .data['n'] as int;
      expect(await count('hr_attendance_days'), 3);
      expect(await count('hr_leave_requests'), 1);
      expect(await count('hr_leave_entitlements'), 1);
      expect(await count('hr_public_holidays'), 1);

      final s = await db.attendanceSummary(e, _d(2), _d(6), now: _now);
      expect(
          [s.workedDays, s.absentDays, s.paidLeaveDays, s.holidays, s.daysOff],
          [1, 1, 1, 1, 1],
          reason: 'Friday comes from the legacy weekday holiday');
      final balance = (await db.employeeLeaveBalances(e, 2025))
          .firstWhere((b) => b.type!.code == LeaveTypeCode.annual);
      expect(balance.accruedDays, 30, reason: 'the legacy total is kept');
    });

    test('الأدوارُ ذاتُ `hr_view` و`hr_manage` تُمنَح الأكوادَ الجديدة مرّة',
        () async {
      await db.syncAllPermissions();
      Future<int> perm(String code) async => (await (db.select(db.permissions)
                ..where((p) => p.code.equals(code)))
              .getSingle())
          .id;
      final viewer =
          await db.into(db.roles).insert(RolesCompanion.insert(name: 'مشاهد'));
      final hr =
          await db.into(db.roles).insert(RolesCompanion.insert(name: 'شؤون'));
      await db.addPermissionToRole(viewer, await perm(PermissionCodes.hrView));
      await db.addPermissionToRole(hr, await perm(PermissionCodes.hrManage));
      // An upgraded install: the one-time flag is not set yet (the test
      // database's own startup already ran it with no HR roles).
      await db.customStatement("DELETE FROM settings WHERE key = "
          "'hr_attendance_perm_backfill_done'");
      await db.backfillHrAttendancePermissionsOnce();
      await db.backfillHrAttendancePermissionsOnce();
      Future<Set<String>> codes(int role) async =>
          {for (final p in await db.getPermissionsForRole(role)) p.code};
      expect(await codes(viewer),
          containsAll([PermissionCodes.hrView, PermissionCodes.hrAttendanceView]));
      expect(await codes(viewer), isNot(contains(PermissionCodes.hrLeaveApprove)));
      expect(
          await codes(hr),
          containsAll([
            PermissionCodes.hrAttendanceView,
            PermissionCodes.hrAttendanceEdit,
            PermissionCodes.hrLeaveRequest,
            PermissionCodes.hrLeaveApprove,
            PermissionCodes.hrShiftsManage,
          ]));
    });
  });

  test('الجداولُ السبعةُ في قوائم المزامنة، وتعبر نسخةَ SELECT *', () async {
    for (final t in _newTables) {
      expect(DeltaPullService.pullTables, contains(t));
      expect(DeltaPullService.deltaOnlyTables, contains(t));
      expect(DeltaPullService.branchScopedPullTables, contains(t));
      expect(IdNamespaceService.namespacedTables, contains(t));
      expect(AppDatabase.syncHardenedTablesForTest, contains(t));
      final cols = {
        for (final c in await db.customSelect('PRAGMA table_info($t)').get())
          c.data['name'] as String,
      };
      expect(
          cols,
          containsAll(<String>[
            'global_id',
            'last_modified_at',
            'deleted_at',
            'origin_client_id',
            'row_version',
          ]),
          reason: t);
    }
    final e = await employee('منقول');
    final shift = await db.saveWorkShift(_dayShift);
    await db.assignShift(employeeId: e, shiftId: shift, from: DateTime(2025));
    await db.savePublicHoliday(PublicHoliday(date: _d(5), name: 'عيد'));
    await punch(e, _d(3), _d(3, 9, 20), _d(3, 18));
    final leave = await db.saveLeaveRequest(
        LeaveRequest(
            employeeId: e,
            leaveTypeId: await typeId(LeaveTypeCode.annual),
            startDate: _d(9),
            endDate: _d(9)),
        submit: true);
    await db.approveLeaveRequest(leave, canApproveAll: true);
    final before = await db.attendanceSummary(e, _d(2), _d(9), now: _now);

    final other = AppDatabase.forTesting();
    addTearDown(other.close);
    await other.customSelect('SELECT 1').get();
    for (final table in ['employees', 'employee_history', ..._newTables]) {
      for (final row in await db.customSelect('SELECT * FROM $table').get()) {
        final cols = row.data.keys.toList();
        await other.customStatement(
          'INSERT OR REPLACE INTO $table (${cols.join(', ')}) '
          'VALUES (${List.filled(cols.length, '?').join(', ')})',
          [for (final col in cols) row.data[col]],
        );
      }
    }
    final after = await other.attendanceSummary(e, _d(2), _d(9), now: _now);
    expect(
        [
          after.workedDays,
          after.lateMinutes,
          after.overtimeMinutes,
          after.holidays,
          after.paidLeaveDays,
          after.absentDays,
        ],
        [
          before.workedDays,
          before.lateMinutes,
          before.overtimeMinutes,
          before.holidays,
          before.paidLeaveDays,
          before.absentDays,
        ]);
    expect(after.paidLeaveDays, 1);
    expect(after.lateMinutes, 20);
  });
}
