import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('صفٌّ أسبوعيّ وصفٌّ بتاريخٍ كلاهما مقبول', () async {
    await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
        name: 'الجمعة', weekday: const Value(5)));
    await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
        name: 'العيد', date: Value(DateTime(2026, 4, 10))));
    expect(await db.select(db.workHolidays).get(), hasLength(2));
  });

  test('صفٌّ بالاثنين معاً مرفوض', () async {
    expect(
      () => db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'خطأ',
          weekday: const Value(5),
          date: Value(DateTime(2026, 4, 10)))),
      throwsA(anything),
      reason: 'صفٌّ يحمل الشكلين لا معنى له، وقبولُه يجعل الحسابَ يعتمد '
          'على أيِّهما يُقرأ أولاً',
    );
  });

  test('صفٌّ بلا أيٍّ منهما مرفوض', () async {
    expect(
      () => db.into(db.workHolidays)
          .insert(WorkHolidaysCompanion.insert(name: 'فارغ')),
      throwsA(anything),
    );
  });

  test('العمودان الجديدان معدومان افتراضياً / false', () async {
    final id = await db.into(db.employees)
        .insert(EmployeesCompanion.insert(name: 'ع'));
    final emp = await (db.select(db.employees)..where((e) => e.id.equals(id)))
        .getSingle();
    expect(emp.hoursPerDay, isNull,
        reason: 'لا قيمةَ افتراضية — الغيابُ يعني «لم يُحدَّد» لا «ثمانٍ»');
  });
}
