// ⚠️ اختبارُ توصيفٍ مؤقّت — يُثبّت سلوكاً **معطوباً** عن قصد كي يظهر تغييرُه
// في الـdiff. يُستبدَل بالكامل في المهمة ٥. لا تُوسَّع تغطيتُه.
// test/unit/hourly_salary_model_test.dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<int> employee(String type, double salary) =>
      db.into(db.employees).insert(EmployeesCompanion.insert(
            name: 'موظف $type',
            salary: Value(salary),
            salaryType: Value(type),
          ));

  Future<void> attend(int id, int day) =>
      db.into(db.employeeAttendance).insert(EmployeeAttendanceCompanion.insert(
            employeeId: id,
            date: DateTime(2026, 4, day),
            checkIn: Value(DateTime(2026, 4, day, 9)),
            checkOut: Value(DateTime(2026, 4, day, 17)),
          ));

  test('التوصيف: hourly يمشي اليوم على موديل اليوم لا على الساعات', () async {
    // أبريل ٢٠٢٦ = ٣٠ يوماً. راتب ٣٠٠٠ ⇒ الأجرُ اليوميّ ١٠٠.
    final id = await employee('hourly', 3000);
    for (var d = 1; d <= 10; d++) {
      await attend(id, d);
    }

    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);

    // EmployeeSalaryCalculation لا يُخرِج basePay كحقلٍ علنيّ (هو متغيّرٌ
    // محليّ داخل calculateNetSalary فقط) — لكن grossPay = basePay +
    // overtimeAmount، وبلا صفوفٍ في overtimeRecords فـovertimeAmount = صفر،
    // فـgrossPay يساوي basePay رقمياً في هذا السيناريو.
    expect(calc.grossPay, closeTo(1000, 0.01),
        reason: '١٠ أيامٍ × ١٠٠ — أي أن ساعاتِ الحضور لا تُقرأ إطلاقاً، '
            'وثمانُ ساعاتٍ أو ثنتان تعطيان الرقمَ نفسه');
  });

  test('التوصيف: طولُ اليوم لا يغيّر شيئاً اليوم', () async {
    final id = await employee('hourly', 3000);
    await db.into(db.employeeAttendance).insert(
        EmployeeAttendanceCompanion.insert(
          employeeId: id,
          date: DateTime(2026, 4, 1),
          checkIn: Value(DateTime(2026, 4, 1, 9)),
          checkOut: Value(DateTime(2026, 4, 1, 11)), // ساعتان فقط
        ));

    final calc = await db.calculateNetSalary(
        employeeId: id, year: 2026, month: 4);
    expect(calc.grossPay, closeTo(100, 0.01),
        reason: 'يومٌ كامل الأجر مقابل ساعتين — وهو ما تُصلحه هذه المواصفة');
  });
}
