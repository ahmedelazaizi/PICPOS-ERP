// ═══════════════════════════════════════════════════════════════════════════
// B4 — الإجازة المعتمدة كانت تُخصم كغياب.
// ═══════════════════════════════════════════════════════════════════════════
//
// `updateLeaveStatus` كان يغيّر حالة الطلب و**لا يكتب صف حضور**، وحساب الراتب
// كان يعدّ `status = 'present'` وحده. فإجازةٌ سنوية **معتمدة** سبعة أيام كانت
// تُخصم سبعة أيام من الراتب: الموظف يطلب، والمدير يوافق، والنظام يعاقبه.
//
// القرار المحاسبي المثبَّت هنا: المدفوعة (سنوية · مرضية · طارئة) تُحتسب
// حضوراً، وغير المدفوعة (`unpaid`) لا. راجع [kPaidLeaveTypes].
//
// وقيد v152 `idx_employee_attendance_day_dedup` فريدٌ على (موظف، يوم)، فمسار
// الاعتماد لا بد أن يكون upsert لا insert — وله اختبارٌ صريح أدناه.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  late int employeeId;

  const salary = 3000.0;
  const managerId = 7;

  Future<void> markPresent(int year, int month, int fromDay, int toDay) async {
    for (var d = fromDay; d <= toDay; d++) {
      await db.into(db.employeeAttendance).insert(
            EmployeeAttendanceCompanion.insert(
              employeeId: employeeId,
              date: DateTime(year, month, d),
              status: const Value('present'),
            ),
          );
    }
  }

  Future<int> requestLeave({
    required String leaveType,
    required DateTime start,
    required DateTime end,
    required int days,
  }) =>
      db.requestLeave(
        employeeId: employeeId,
        leaveType: leaveType,
        startDate: start,
        endDate: end,
        days: days,
      );

  Future<List<EmployeeAttendanceData>> attendanceIn(
    DateTime start,
    DateTime end,
  ) =>
      (db.select(db.employeeAttendance)
            ..where((a) => a.employeeId.equals(employeeId))
            ..where((a) => a.date.isBiggerOrEqual(Variable(start)))
            ..where((a) => a.date.isSmallerOrEqual(Variable(end)))
            ..orderBy([(a) => OrderingTerm.asc(a.date)]))
          .get();

  setUp(() async {
    db = AppDatabase.forTesting();
    employeeId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            name: 'أحمد',
            salary: const Value(salary),
          ),
        );
    await db.initializeLeaveBalances(employeeId, 2026);
  });

  tearDown(() => db.close());

  group('B4 — الاعتماد يكتب صفوف حضور للفترة', () {
    test('إجازة سنوية ٧ أيام تكتب ٧ صفوف بحالة إجازة مدفوعة', () async {
      final leaveId = await requestLeave(
        leaveType: 'annual',
        start: DateTime(2026, 2, 22),
        end: DateTime(2026, 2, 28),
        days: 7,
      );

      await db.updateLeaveStatus(leaveId, 'approved', managerId);

      final rows =
          await attendanceIn(DateTime(2026, 2, 22), DateTime(2026, 2, 28));
      expect(rows.length, 7, reason: 'الاعتماد لم يكتب صفوف حضور أصلاً');
      expect(rows.map((r) => r.date.day), [22, 23, 24, 25, 26, 27, 28]);
      expect(
        rows.every((r) => r.status == kAttendanceStatusPaidLeave),
        isTrue,
      );
    });

    test('الرفض لا يكتب صفّاً واحداً', () async {
      final leaveId = await requestLeave(
        leaveType: 'annual',
        start: DateTime(2026, 2, 22),
        end: DateTime(2026, 2, 28),
        days: 7,
      );

      await db.updateLeaveStatus(leaveId, 'rejected', managerId);

      expect(
        await attendanceIn(DateTime(2026, 2, 22), DateTime(2026, 2, 28)),
        isEmpty,
      );
    });

    test('إجازة عابرة للشهرين تكتب في الشهرين', () async {
      final leaveId = await requestLeave(
        leaveType: 'annual',
        start: DateTime(2026, 2, 26),
        end: DateTime(2026, 3, 3),
        days: 6,
      );

      await db.updateLeaveStatus(leaveId, 'approved', managerId);

      final rows =
          await attendanceIn(DateTime(2026, 2, 26), DateTime(2026, 3, 3));
      expect(rows.length, 6);
      expect(rows.where((r) => r.date.month == 2).length, 3);
      expect(rows.where((r) => r.date.month == 3).length, 3);
    });
  });

  group('B4 — أثر الاعتماد على الراتب', () {
    test('٢١ يوم حضور + ٧ أيام إجازة سنوية معتمدة = الراتب كامل', () async {
      await markPresent(2026, 2, 1, 21);
      final leaveId = await requestLeave(
        leaveType: 'annual',
        start: DateTime(2026, 2, 22),
        end: DateTime(2026, 2, 28),
        days: 7,
      );
      await db.updateLeaveStatus(leaveId, 'approved', managerId);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 2,
      );

      expect(calc.daysAttended, 28,
          reason: 'الإجازة المعتمدة يوم مدفوع، فلا بد أن تُعدّ');
      expect(calc.grossPay, closeTo(salary, 0.01),
          reason: 'قبل الإصلاح: ٢١ يوماً فقط = 2250 — خصم إجازةٍ وافق عليها المدير');
    });

    test('الإجازة المرضية المعتمدة مدفوعة كذلك', () async {
      await markPresent(2026, 2, 1, 25);
      final leaveId = await requestLeave(
        leaveType: 'sick',
        start: DateTime(2026, 2, 26),
        end: DateTime(2026, 2, 28),
        days: 3,
      );
      await db.updateLeaveStatus(leaveId, 'approved', managerId);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 2,
      );

      expect(calc.daysAttended, 28);
      expect(calc.grossPay, closeTo(salary, 0.01));
    });

    test('الإجازة غير المدفوعة لا تُحتسب — لكنها تُوثَّق', () async {
      await markPresent(2026, 2, 1, 21);
      final leaveId = await requestLeave(
        leaveType: 'unpaid',
        start: DateTime(2026, 2, 22),
        end: DateTime(2026, 2, 28),
        days: 7,
      );
      await db.updateLeaveStatus(leaveId, 'approved', managerId);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 2,
      );

      expect(calc.daysAttended, 21,
          reason: 'غير المدفوعة يومٌ بلا أجر بحكم اسمها');
      expect(calc.grossPay, closeTo(salary / 28 * 21, 0.01));

      // ومع ذلك الصفوف مكتوبة: الغياب مصرَّح به، لا مجهول.
      final rows =
          await attendanceIn(DateTime(2026, 2, 22), DateTime(2026, 2, 28));
      expect(rows.length, 7);
      expect(
        rows.every((r) => r.status == kAttendanceStatusUnpaidLeave),
        isTrue,
      );
    });
  });

  group('B4 — قيد v152: upsert لا insert', () {
    test('يوم فيه صف حضور سابق لا يُرفض الاعتماد بسببه', () async {
      // الموظف بصم يوم ٢٢ ثم اعتُمدت إجازته من ٢٢ إلى ٢٨.
      await markPresent(2026, 2, 22, 22);
      final leaveId = await requestLeave(
        leaveType: 'annual',
        start: DateTime(2026, 2, 22),
        end: DateTime(2026, 2, 28),
        days: 7,
      );

      await db.updateLeaveStatus(leaveId, 'approved', managerId);

      final rows =
          await attendanceIn(DateTime(2026, 2, 22), DateTime(2026, 2, 28));
      expect(rows.length, 7,
          reason: 'insert كان سيرتطم بـidx_employee_attendance_day_dedup');
      expect(rows.first.date.day, 22);
      expect(rows.first.status, kAttendanceStatusPaidLeave);
    });

    test('التحضير والانصراف المسجّلان على صفٍّ موجود لا يُمسحان', () async {
      final attId = await db.into(db.employeeAttendance).insert(
            EmployeeAttendanceCompanion.insert(
              employeeId: employeeId,
              date: DateTime(2026, 2, 22),
              checkIn: Value(DateTime(2026, 2, 22, 8, 30)),
              checkOut: Value(DateTime(2026, 2, 22, 16, 45)),
            ),
          );
      final leaveId = await requestLeave(
        leaveType: 'annual',
        start: DateTime(2026, 2, 22),
        end: DateTime(2026, 2, 22),
        days: 1,
      );

      await db.updateLeaveStatus(leaveId, 'approved', managerId);

      final row = await (db.select(db.employeeAttendance)
            ..where((a) => a.id.equals(attId)))
          .getSingle();
      expect(row.status, kAttendanceStatusPaidLeave);
      expect(row.checkIn, DateTime(2026, 2, 22, 8, 30),
          reason: 'إثبات أنه حضر فعلاً لا يجوز أن يضيع');
      expect(row.checkOut, DateTime(2026, 2, 22, 16, 45));
    });
  });

  group('B4 — رصيد الإجازات لم يتأثّر بالإصلاح', () {
    test('الاعتماد ما زال يخصم من الرصيد السنوي', () async {
      final leaveId = await requestLeave(
        leaveType: 'annual',
        start: DateTime(2026, 2, 22),
        end: DateTime(2026, 2, 28),
        days: 7,
      );

      await db.updateLeaveStatus(leaveId, 'approved', managerId);

      final balances = await db.getLeaveBalances(employeeId, 2026);
      final annual = balances.firstWhere((b) => b.leaveType == 'annual');
      expect(annual.usedDays, 7);
    });
  });
}
