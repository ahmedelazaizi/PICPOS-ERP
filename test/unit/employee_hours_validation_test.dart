// test/unit/employee_hours_validation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('hourly بلا ساعاتٍ يوميةٍ يُرفَض عند الحفظ', () async {
    expect(
      () => db.addEmployee(name: 'ع', salary: 5200, salaryType: 'hourly'),
      throwsArgumentError,
      reason: 'التجهيزةُ الناقصة تُمنع عند الإدخال لا تُكتشف في كشفِ راتب',
    );
  });

  test('hourly بساعاتٍ صالحةٍ يُقبَل', () async {
    final id = await db.addEmployee(
        name: 'ع', salary: 5200, salaryType: 'hourly', hoursPerDay: 8);
    expect(id, greaterThan(0));
  });

  test('الشهريُّ بلا ساعاتٍ يُقبَل — الحقلُ اختياريٌّ له', () async {
    final id = await db.addEmployee(name: 'ش', salary: 5200);
    expect(id, greaterThan(0));
  });

  test('ساعاتٌ صفرٌ أو سالبةٌ تُرفَض لـhourly', () async {
    expect(
      () => db.addEmployee(
          name: 'ع', salary: 1, salaryType: 'hourly', hoursPerDay: 0),
      throwsArgumentError,
    );
    expect(
      () => db.addEmployee(
          name: 'ع', salary: 1, salaryType: 'hourly', hoursPerDay: -1),
      throwsArgumentError,
    );
  });

  test('التعديلُ إلى hourly بلا ساعاتٍ يُرفَض كذلك', () async {
    final id = await db.addEmployee(name: 'ش', salary: 5200);
    expect(
      () => db.updateEmployee(id: id, salaryType: 'hourly'),
      throwsArgumentError,
      reason: 'بابُ التعديل ثغرةٌ إن حُرس بابُ الإضافة وحدَه',
    );
  });

  test('التعديلُ إلى hourly مع ساعاتٍ يُقبَل', () async {
    final id = await db.addEmployee(name: 'ش', salary: 5200);
    await db.updateEmployee(id: id, salaryType: 'hourly', hoursPerDay: 8);
    final e = await (db.select(db.employees)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(e.hoursPerDay, 8);
  });
}
