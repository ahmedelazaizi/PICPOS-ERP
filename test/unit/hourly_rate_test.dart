import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<Employee> emp({double salary = 5200, double? hours = 8}) async {
    final id = await db.into(db.employees).insert(EmployeesCompanion.insert(
          name: 'موظف',
          salary: Value(salary),
          salaryType: const Value('hourly'),
          hoursPerDay: Value(hours),
        ));
    return (db.select(db.employees)..where((e) => e.id.equals(id)))
        .getSingle();
  }

  test('بلا عطلاتٍ: ٥٢٠٠ ÷ (٨ × ٣٠) = ٢١٫٦٦٧', () async {
    final e = await emp();
    expect(await db.hourlyRateFor(e, 2026, 4), closeTo(21.6667, 0.0001));
  });

  test('بأربعِ جُمَعٍ: ٥٢٠٠ ÷ (٨ × ٢٦) = ٢٥ بالضبط', () async {
    await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
        name: 'الجمعة', weekday: const Value(5)));
    final e = await emp();
    expect(await db.hourlyRateFor(e, 2026, 4), closeTo(25, 0.0001),
        reason: 'المقامُ ساعاتُ العمل لا أيامُ التقويم');
  });

  test('لا يُقرَّب أجرُ الساعة', () async {
    final e = await emp(salary: 5000);
    final r = await db.hourlyRateFor(e, 2026, 4); // 5000/240
    expect(r, closeTo(20.8333, 0.0001));
    expect(r, isNot(closeTo(20.83, 0.0000001)),
        reason: 'التقريبُ المبكّر يتراكم على عشرات الساعات');
  });

  test('صفرُ أيامِ عملٍ يرمي لا يُرجع لانهاية', () async {
    for (var w = 1; w <= 7; w++) {
      await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'يوم $w', weekday: Value(w)));
    }
    final e = await emp();
    expect(() => db.hourlyRateFor(e, 2026, 4), throwsStateError,
        reason: 'القسمةُ على صفرٍ تعطي Infinity فتمرّ في الحساب وتظهر '
            'راتباً خيالياً');
  });

  test('hoursPerDay معدومٌ يرمي', () async {
    final e = await emp(hours: null);
    expect(() => db.hourlyRateFor(e, 2026, 4), throwsStateError);
  });

  test('hoursPerDay صفرٌ أو سالبٌ يرمي', () async {
    // ⚠️ `await emp(...)` هنا داخل مُغلَّفٍ يُستدعى من `throwsStateError` —
    // فالمُغلَّفُ نفسُه يجب أن يكون `async` وإلا فشل التصريف: «'await' can only
    // be used in 'async' or 'async*' methods». هذا تصحيحٌ للتصريف فقط، لا
    // للمنطق: القيمُ والتوقّعُ كما في الوصف الأصلي بالحرف.
    expect(() async => db.hourlyRateFor(await emp(hours: 0), 2026, 4),
        throwsStateError);
    expect(() async => db.hourlyRateFor(await emp(hours: -1), 2026, 4),
        throwsStateError);
  });
}
