// test/unit/hourly_salary_model_test.dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<int> employee(String type,
          {double salary = 5200, double? hours = 8}) =>
      db.into(db.employees).insert(EmployeesCompanion.insert(
            name: 'موظف $type',
            salary: Value(salary),
            salaryType: Value(type),
            hoursPerDay: Value(hours),
          ));

  Future<void> attend(int id, int day, int fromHour, int toHour) =>
      db.into(db.employeeAttendance).insert(EmployeeAttendanceCompanion.insert(
            employeeId: id,
            date: DateTime(2026, 4, day),
            checkIn: Value(DateTime(2026, 4, day, fromHour)),
            checkOut: Value(DateTime(2026, 4, day, toHour)),
          ));

  Future<void> fridayOff() => db.into(db.workHolidays).insert(
      WorkHolidaysCompanion.insert(name: 'الجمعة', weekday: const Value(5)));

  test('hourly يُدفع بالساعات لا بالأيام', () async {
    await fridayOff(); // ⇒ أجرُ الساعة = 5200 / (8×26) = 25
    final id = await employee('hourly');
    await attend(id, 1, 9, 17); // ٨ ساعات
    await attend(id, 2, 9, 13); // ٤ ساعات

    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(12 * 25, 0.01),
        reason: '١٢ ساعةً × ٢٥ — لا يومان × الأجر اليومي');
  });

  test('يومٌ قصيرٌ يُدفع بقدره', () async {
    await fridayOff();
    final id = await employee('hourly');
    await attend(id, 1, 9, 11); // ساعتان
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(2 * 25, 0.01),
        reason: 'كان يأخذ يوماً كاملاً مقابل ساعتين');
  });

  test('صفُّ حضورٍ بلا انصرافٍ لا يُحتسب ساعات', () async {
    await fridayOff();
    final id = await employee('hourly');
    await db.into(db.employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: id,
          date: DateTime(2026, 4, 1),
          checkIn: Value(DateTime(2026, 4, 1, 9)),
        ));
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(0, 0.01),
        reason: 'مدةٌ مجهولة لا تُخمَّن — والاتجاهُ الآمن أن تُوثَّق');
  });

  test('الشهريُّ لا يتأثّر بالساعات', () async {
    await fridayOff();
    final id = await employee(kMonthlySalaryType);
    await attend(id, 1, 9, 11);
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(5200, 0.01),
        reason: 'الشهريُّ = الراتبُ كاملاً ناقص غيابٍ مسجَّل');
  });

  test('الشهريّ: غيابٌ في يوم عطلةٍ لا يُخصم', () async {
    await fridayOff();
    final id = await employee(kMonthlySalaryType);
    // ٣ أبريل ٢٠٢٦ جمعة.
    await db.into(db.employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: id,
          date: DateTime(2026, 4, 3),
          status: const Value('absent'),
        ));
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(5200, 0.01),
        reason: 'التقويمُ يسري على الجميع — تغييرٌ مقصودٌ في موديل الشهري');
  });

  test('الشهريّ: غيابٌ في يوم عملٍ يُخصم كما كان', () async {
    await fridayOff();
    final id = await employee(kMonthlySalaryType);
    await db.into(db.employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: id,
          date: DateTime(2026, 4, 7), // ثلاثاء
          status: const Value('absent'),
        ));
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, lessThan(5200));
  });

  // ── دورة إصلاح ١ — الملاحظة ٢: الإجازةُ المدفوعة تُدفع لموظف الساعة ──────
  // (قرار المالك 2026-08-09، سدُّ فجوة B4 المذكورة في hr_extensions.dart)

  test('إجازةٌ مدفوعةٌ معتمدة تُدفع لموظف الساعة', () async {
    await fridayOff(); // ⇒ أجرُ الساعة = 25
    final id = await employee('hourly');
    await db.into(db.employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: id,
          date: DateTime(2026, 4, 1),
          status: const Value(kAttendanceStatusPaidLeave),
        ));
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(8 * 25, 0.01),
        reason: 'يومُ الإجازة المدفوعة يُحتسب hoursPerDay ساعةً لا صفراً');
  });

  test('الإجازةُ غيرُ المدفوعة لا تُدفع لموظف الساعة', () async {
    await fridayOff();
    final id = await employee('hourly');
    await db.into(db.employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: id,
          date: DateTime(2026, 4, 1),
          status: const Value(kAttendanceStatusUnpaidLeave),
        ));
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(0, 0.01),
        reason: 'غيرُ مدفوعةٍ بحكم اسمها — لا تصير مدفوعةً لموظف الساعة');
  });

  test('الغيابُ لا يُدفع لموظف الساعة', () async {
    await fridayOff();
    final id = await employee('hourly');
    await db.into(db.employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: id,
          date: DateTime(2026, 4, 1),
          status: const Value(kAttendanceStatusAbsent),
        ));
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(0, 0.01),
        reason: 'غيابٌ بلا حضورٍ ولا إجازةٍ معتمدة');
  });

  test('صفُّ إجازةٍ مدفوعةٍ يحمل بصمةً كذلك لا يُحتسب مرتين', () async {
    await fridayOff();
    final id = await employee('hourly');
    await db.into(db.employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: id,
          date: DateTime(2026, 4, 1),
          status: const Value(kAttendanceStatusPaidLeave),
          checkIn: Value(DateTime(2026, 4, 1, 9)),
          checkOut: Value(DateTime(2026, 4, 1, 17)), // ٨ ساعات بصمة كذلك
        ));
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(8 * 25, 0.01),
        reason: 'hoursPerDay وحدها — لا هي مجموعةً مع بصمة اليوم نفسه '
            '(لو احتُسبتا معاً لكانت النتيجة ١٦ ساعة = ٤٠٠)');
  });

  test('ثابتةٌ تربط الموديلين: شهرٌ كاملُ العمل يعطي الراتبَ بالضبط', () async {
    await fridayOff();
    final id = await employee('hourly');
    for (var d = 1; d <= 30; d++) {
      if (DateTime(2026, 4, d).weekday == DateTime.friday) continue;
      await attend(id, d, 9, 17); // ٨ ساعات كلَّ يوم عمل
    }
    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(5200, 0.01),
        reason: 'المقامُ والبسطُ متّسقان — موظفُ الساعة الملتزمُ يأخذ راتبَه '
            'كاملاً لا أقلّ');
  });
}
