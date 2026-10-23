// ═══════════════════════════════════════════════════════════════════════════
// J4 (v192) — الورديّاتُ والحضورُ والإجازات على PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════
//
// الجداولُ السبعةُ **SQL خامٌّ بلا صنفِ drift**، فيُنشئها
// `ensureHrAttendanceSchema` على PG بصيغتها (`SERIAL` · `BIGINT` ·
// `DOUBLE PRECISION`). وهنا يُقاس أنّها موجودةٌ بأعمدة الدلتا، وأنّ الكتابةَ
// بقيمٍ فارغةٍ في أعمدةٍ رقميّة (‏PG يرفض NULL غيرَ مُنمَّط) تعمل: البصمةُ
// بلا انصراف، والإسنادُ المفتوح، ودورةُ الإجازة، والملخّص، والنقلُ من
// الجداول القديمة.
//
// ⚠️ يعمل عبر `dart run scripts/run_pg_tests.dart` وحدَه.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/hr_attendance.dart';
import 'package:picpos_erp/domain/models/hr_attendance_import.dart';
import 'package:picpos_erp/domain/models/hr_employee_file.dart';
import 'package:picpos_erp/domain/models/hr_leave.dart';

import '_support/pg_fixture.dart';

DateTime _d(int day, [int h = 0, int m = 0]) => DateTime(2025, 6, day, h, m);

void main() {
  late AppDatabase db;

  setUp(() async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    db = fx.db;
    await db.select(db.accounts).get(); // يُجبر الهجرةَ ومسارَ الإقلاع
    await db.ensureDefaultLeaveTypes();
  });

  Future<Set<String>> columnsOf(String table) async {
    final rows = await db
        .customSelect(
          "SELECT column_name FROM information_schema.columns "
          "WHERE table_name = '$table'",
        )
        .get();
    return rows.map((r) => r.data['column_name'] as String).toSet();
  }

  test('الجداولُ السبعةُ موجودةٌ على PG بأعمدة الدلتا', () async {
    for (final t in [
      'hr_shifts',
      'hr_shift_assignments',
      'hr_public_holidays',
      'hr_leave_types',
      'hr_leave_requests',
      'hr_leave_entitlements',
      'hr_attendance_days',
    ]) {
      expect(
          await columnsOf(t),
          containsAll(const [
            'global_id',
            'last_modified_at',
            'deleted_at',
            'origin_client_id',
            'row_version',
          ]),
          reason: t);
    }
  });

  test('الورديّةُ والحضورُ والإجازةُ والملخّصُ والاستيرادُ والنقل', () async {
    final manager = await db.saveEmployeeProfile(
        EmployeeProfile(name: 'مدير', hireDate: DateTime(2020)));
    final e = await db.saveEmployeeProfile(EmployeeProfile(
        name: 'عامل',
        code: 'PG-1',
        managerId: manager,
        hireDate: DateTime(2020)));
    final shift = await db.saveWorkShift(const WorkShift(
      name: 'صباحي',
      startMinute: 540,
      endMinute: 1020,
      breakMinutes: 60,
      graceLateMinutes: 10,
      overtimeAfterMinutes: 30,
      daysOff: {DateTime.friday, DateTime.saturday},
    ));
    await db.assignShift(employeeId: e, shiftId: shift, from: DateTime(2025));
    expect((await db.listShiftAssignments(employeeId: e)).single.effectiveTo,
        isNull);
    await db.savePublicHoliday(PublicHoliday(date: _d(5), name: 'عيد'));
    await db.saveAttendanceEntry(
        employeeId: e,
        day: _d(2),
        checkIn: _d(2, 9, 20),
        reason: 'بلا انصراف');
    await db.saveAttendanceEntry(
        employeeId: e,
        day: _d(3),
        checkIn: _d(3, 9),
        checkOut: _d(3, 18),
        reason: 'كامل');

    final preview = await db.previewAttendanceImport(
        'code,when\nPG-1,2025-06-04 08:59\nPG-1,2025-06-04 17:00\n',
        const AttendanceCsvMapping());
    expect(preview.errors, isEmpty);
    expect(await db.applyAttendanceImport(preview), 1);

    final annual = (await db.listLeaveTypes())
        .firstWhere((t) => t.code == LeaveTypeCode.annual);
    final r = await db.saveLeaveRequest(
        LeaveRequest(
            employeeId: e,
            leaveTypeId: annual.id!,
            startDate: _d(8),
            endDate: _d(10)),
        submit: true);
    await db.approveLeaveRequest(r, canApproveAll: true, note: 'ok');
    final s = await db.attendanceSummary(e, _d(2), _d(10),
        now: DateTime(2026));
    expect(s.workedDays, 3);
    expect(s.lateMinutes, 20);
    expect(s.overtimeMinutes, 60);
    expect(s.holidays, 1);
    expect(s.daysOff, 2);
    expect(s.paidLeaveDays, 3);
    final balance = (await db.employeeLeaveBalances(e, 2025))
        .firstWhere((b) => b.leaveTypeId == annual.id);
    expect(balance.usedDays, 3);
    await db.cancelLeaveRequest(r);
    expect(
        (await db.employeeLeaveBalances(e, 2025))
            .firstWhere((b) => b.leaveTypeId == annual.id)
            .usedDays,
        0);
    await db.saveAttendanceEntry(employeeId: e, day: _d(2), reason: 'حذف');
    expect(await db.attendanceRecordFor(e, _d(2)), isNull);

    await db.into(db.employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
            employeeId: manager,
            date: _d(2),
            status: const Value('absent')));
    await db.migrateLegacyHrAttendance();
    await db.migrateLegacyHrAttendance();
    expect((await db.attendanceRecordFor(manager, _d(2)))?.mark,
        AttendanceMark.absent);
  });
}
