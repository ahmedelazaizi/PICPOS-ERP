// test/unit/hourly_salary_model_test.dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

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
}
