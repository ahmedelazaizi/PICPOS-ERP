// ═══════════════════════════════════════════════════════════════════════════
// الموديل الشهري — الراتبُ كاملاً ناقص غيابٍ مسجَّل (قرار المالك 2026-08-09).
// ═══════════════════════════════════════════════════════════════════════════
//
// كان المحرّكُ يطبّق موديلاً واحداً — **أجرٌ يومي** — على الأنواع الثلاثة:
// `daysAttended × dailyRate`. و`salaryType` **لم يُقرأ قطّ** (صفر إشارة في
// الدالة). والأيامُ المدفوعة تُعَدّ من **وجود** صفِّ حضور، وصفوفُ الحضور تأتي
// من ثلاثة مصادر فقط: بصمة · تحضير يدوي · إجازة معتمدة.
//
// ويومُ الراحة لا أحد يبصم فيه ⇒ لا صفَّ له ⇒ **لا يُدفَع**. فموظفٌ شهريٌّ
// بـ٢٨٠٠ وأسبوعُ عملٍ من خمسة أيام كان يأخذ ٢٢٠٠ — خصمُ ٢١٪ على شهرٍ لم يغب
// فيه يوماً واحداً. ولو لم يكن في الفرع جهازُ بصمةٍ أصلاً كان يأخذ **صفراً**.
//
// ── الموديل الآن ───────────────────────────────────────────────────────────
//   شهري : الراتبُ كاملاً − (الأجرُ اليومي × أيامٍ غيرِ مدفوعةٍ **مسجَّلة**)
//   يومي : الأجرُ اليومي × الأيامِ المدفوعة        ← كما كان، وهو صحيحٌ له
//
// وغيرُ المدفوعِ المسجَّل حالتان: `absent` (غيابٌ يعلّمه المدير) و`unpaid_leave`
// (إجازةٌ غيرُ مدفوعةٍ معتمدة يكتبها B4). لو خُصمت الأولى وحدها لصارت الإجازةُ
// غيرُ المدفوعةِ مدفوعةً بحكم الأمر الواقع.
//
// ⚠️ الاتجاهُ الآمن مقصود: غيابٌ لم يُسجَّل = لا خصم. فمن لا يعلّم الغيابَ يدفع
// كاملاً، ولا يُخصَم من موظفٍ بالخطأ لأن أحداً نسي أن يبصم له.
//
// الراتبُ ٢٨٠٠ وفبراير ٢٠٢٦ ‏٢٨ يوماً ⇒ الأجرُ اليومي = ١٠٠ بالتدقيق.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  late int monthlyId;
  late int dailyId;

  const salary = 2800.0;
  const dailyRate = 100.0;

  Future<void> present(int empId, int fromDay, int toDay) async {
    for (var d = fromDay; d <= toDay; d++) {
      await db.into(db.employeeAttendance).insert(
            EmployeeAttendanceCompanion.insert(
              employeeId: empId,
              date: DateTime(2026, 2, d),
              status: const Value('present'),
            ),
          );
    }
  }

  Future<void> absent(int empId, int fromDay, int toDay) async {
    for (var d = fromDay; d <= toDay; d++) {
      await db.markEmployeeAbsent(empId, DateTime(2026, 2, d));
    }
  }

  Future<EmployeeSalaryCalculation> calc(int empId) => db.calculateNetSalary(
        employeeId: empId,
        year: 2026,
        month: 2,
      );

  Future<void> approveLeave(
    int empId,
    String leaveType,
    int fromDay,
    int toDay,
  ) async {
    final id = await db.requestLeave(
      employeeId: empId,
      leaveType: leaveType,
      startDate: DateTime(2026, 2, fromDay),
      endDate: DateTime(2026, 2, toDay),
      days: toDay - fromDay + 1,
    );
    await db.updateLeaveStatus(id, 'approved', 1);
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    monthlyId = await db.addEmployee(
      name: 'شهري',
      salary: salary,
      salaryType: 'monthly',
    );
    dailyId = await db.addEmployee(
      name: 'يومي',
      salary: salary,
      salaryType: 'daily',
    );
    await db.initializeLeaveBalances(monthlyId, 2026);
  });

  tearDown(() => db.close());

  group('الشهري — الراتبُ هو الأصل لا الاستثناء', () {
    test('بلا أيّ صفِّ حضور: الراتبُ كاملاً', () async {
      final c = await calc(monthlyId);

      expect(c.payableAmount, closeTo(salary, 0.01),
          reason: 'فرعٌ بلا جهاز بصمةٍ كان يُعطي صفراً لكل موظفيه الشهريين');
      expect(c.unpaidDays, 0);
      expect(c.netSalary, closeTo(salary, 0.01));
    });

    test('٢٢ يوم بصمة وأيامُ الراحة بلا صفوف: الراتبُ كاملاً', () async {
      await present(monthlyId, 1, 22);

      final c = await calc(monthlyId);

      expect(c.payableAmount, closeTo(salary, 0.01),
          reason: 'الموديلُ القديم كان يُعطي ٢٢٠٠ — خصمُ ٢١٪ بلا غيابٍ واحد');
      expect(c.unpaidDays, 0);
    });

    test('يومان غيابٌ مسجَّلان يُخصمان', () async {
      await present(monthlyId, 1, 26);
      await absent(monthlyId, 27, 28);

      final c = await calc(monthlyId);

      expect(c.unpaidDays, 2);
      expect(c.payableAmount, closeTo(salary - 2 * dailyRate, 0.01));
      expect(c.payableAmount, closeTo(2600, 0.01));
    });

    test('الإجازةُ المدفوعة المعتمدة لا تُخصم', () async {
      await present(monthlyId, 1, 20);
      await approveLeave(monthlyId, 'annual', 21, 25);

      final c = await calc(monthlyId);

      expect(c.unpaidDays, 0);
      expect(c.payableAmount, closeTo(salary, 0.01));
    });

    test('الإجازةُ غيرُ المدفوعة المعتمدة تُخصم', () async {
      await present(monthlyId, 1, 20);
      await approveLeave(monthlyId, 'unpaid', 21, 23);

      final c = await calc(monthlyId);

      expect(c.unpaidDays, 3,
          reason: 'لو لم تُخصم لصارت غيرُ المدفوعةِ مدفوعةً بحكم الأمر الواقع');
      expect(c.payableAmount, closeTo(salary - 3 * dailyRate, 0.01));
    });

    test('الغيابُ والإجازةُ غيرُ المدفوعة يُجمعان', () async {
      await absent(monthlyId, 1, 2);
      await approveLeave(monthlyId, 'unpaid', 5, 6);

      final c = await calc(monthlyId);

      expect(c.unpaidDays, 4);
      expect(c.payableAmount, closeTo(salary - 4 * dailyRate, 0.01));
    });

    test('الوقتُ الإضافي يُضاف فوق الراتب الكامل', () async {
      await db.addOvertimeRecord(
        employeeId: monthlyId,
        date: DateTime(2026, 2, 12),
        hours: 2,
        rate: 1.5,
      );

      final c = await calc(monthlyId);

      expect(c.overtimeAmount, closeTo(37.5, 0.01));
      expect(c.payableAmount, closeTo(salary + 37.5, 0.01));
    });

    test('شهرٌ كامل الغياب: صفرٌ لا سالب', () async {
      await absent(monthlyId, 1, 28);

      final c = await calc(monthlyId);

      expect(c.unpaidDays, 28);
      expect(c.payableAmount, closeTo(0, 0.01),
          reason: 'قيدُ v152 يمنع أكثر من صفٍّ لليوم، فالغيابُ محدودٌ بأيام '
              'الشهر ⇒ المستحقُّ لا يهبط تحت الصفر بالبناء');
      expect(c.netSalary, closeTo(0, 0.01));
    });
  });

  group('اليومي — لم يتغيّر شيء', () {
    test('٢٢ يوم بصمة = ٢٢ × الأجر اليومي', () async {
      await present(dailyId, 1, 22);

      final c = await calc(dailyId);

      expect(c.daysAttended, 22);
      expect(c.payableAmount, closeTo(2200, 0.01),
          reason: 'اليومي يُدفع بما عمل — وهذا صحيحٌ له');
    });

    test('بلا صفوف: صفر', () async {
      expect((await calc(dailyId)).payableAmount, closeTo(0, 0.01));
    });

    test('صفوفُ الغياب لا تَخصم منه مرةً ثانية', () async {
      await present(dailyId, 1, 22);
      await absent(dailyId, 23, 24);

      final c = await calc(dailyId);

      expect(c.payableAmount, closeTo(2200, 0.01),
          reason: 'اليومُ غيرُ المعمول غيرُ مدفوعٍ أصلاً — لا يُخصَم ثانيةً');
    });
  });

  group('التفاعل مع السلف والجزاءات — ثابتُ B3 يبقى', () {
    test('شهريٌّ بغيابٍ وجزاءٍ وسلفة: المستحقّ = الصافي + المسوّى', () async {
      await absent(monthlyId, 27, 28);
      await db.recordEmployeeAdvance(
        employeeId: monthlyId,
        amount: 1000,
        affectsTreasury: false,
        transactionDate: DateTime(2026, 2, 10),
      );
      await db.recordEmployeeDeduction(
        employeeId: monthlyId,
        amount: 300,
        transactionDate: DateTime(2026, 2, 11),
      );

      final c = await calc(monthlyId);

      expect(c.grossPay, closeTo(2600, 0.01), reason: '2800 − يومان غياب');
      expect(c.payableAmount, closeTo(2300, 0.01), reason: '2600 − جزاء 300');
      expect(c.advancesSettled, closeTo(1000, 0.01));
      expect(c.netSalary, closeTo(1300, 0.01));
      expect(c.payableAmount, closeTo(c.netSalary + c.advancesSettled, 0.01),
          reason: 'شرطُ توازنِ قيدِ اليومية');
    });
  });

  group('markEmployeeAbsent', () {
    test('يكتب صفاً بحالة absent', () async {
      await db.markEmployeeAbsent(monthlyId, DateTime(2026, 2, 14));

      final rows = await (db.select(db.employeeAttendance)
            ..where((a) => a.employeeId.equals(monthlyId)))
          .get();
      expect(rows.length, 1);
      expect(rows.first.status, kAttendanceStatusAbsent);
      expect(rows.first.date, DateTime(2026, 2, 14));
    });

    test('upsert لا insert — يومٌ فيه صفٌّ سابق لا يرتطم بقيد v152', () async {
      await present(monthlyId, 14, 14);

      await db.markEmployeeAbsent(monthlyId, DateTime(2026, 2, 14));

      final rows = await (db.select(db.employeeAttendance)
            ..where((a) => a.employeeId.equals(monthlyId)))
          .get();
      expect(rows.length, 1, reason: 'insert كان سيرتطم بالفهرس الفريد');
      expect(rows.first.status, kAttendanceStatusAbsent,
          reason: 'تعليمُ المدير هو الأحدث فهو الحاكم');
    });

    test('تعليمُ الغياب مرتين لا يُخصم مرتين', () async {
      await db.markEmployeeAbsent(monthlyId, DateTime(2026, 2, 14));
      await db.markEmployeeAbsent(monthlyId, DateTime(2026, 2, 14));

      final c = await calc(monthlyId);
      expect(c.unpaidDays, 1);
      expect(c.payableAmount, closeTo(salary - dailyRate, 0.01));
    });
  });
}
