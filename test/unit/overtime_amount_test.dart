import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  late int employeeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
        name: 'الجمعة', weekday: const Value(5)));
    employeeId = await db.into(db.employees).insert(
        EmployeesCompanion.insert(
          name: 'موظف',
          salary: const Value(5200),
          hoursPerDay: const Value(8),
        ));
  });

  tearDown(() => db.close());

  Future<OvertimeRecord> single() =>
      db.select(db.overtimeRecords).getSingle();

  test('المبلغُ يُشتقّ بمقام أيام العمل لا أيام التقويم', () async {
    // أجرُ الساعة = 5200 / (8×26) = 25 ⇒ ساعتان × ١٫٥ × ٢٥ = ٧٥
    await db.addOvertimeRecord(
        employeeId: employeeId, date: DateTime(2026, 4, 7), hours: 2);
    expect((await single()).amount, closeTo(75, 0.01),
        reason: 'بمقام ٣٠ يوماً كان ٦٥ — أرخصَ بنحو ١٥٪');
  });

  test('المضاعِفُ يدخل الحساب', () async {
    await db.addOvertimeRecord(
        employeeId: employeeId,
        date: DateTime(2026, 4, 7),
        hours: 2,
        rate: 2);
    expect((await single()).amount, closeTo(100, 0.01));
  });

  test('التجاوزُ اليدويّ يُحفظ ويُعلَّم', () async {
    await db.addOvertimeRecord(
        employeeId: employeeId,
        date: DateTime(2026, 4, 7),
        hours: 2,
        manualAmount: 500);
    final r = await single();
    expect(r.amount, closeTo(500, 0.01));
    expect(r.isManualAmount, isTrue,
        reason: 'الاستثناءُ يُرى ولا يُخفى');
  });

  test('غيرُ المتجاوَز يُعلَّم false', () async {
    await db.addOvertimeRecord(
        employeeId: employeeId, date: DateTime(2026, 4, 7), hours: 2);
    expect((await single()).isManualAmount, isFalse);
  });

  test('موظفٌ بلا hoursPerDay: يبقى المبلغُ يدوياً ولا يرمي', () async {
    final id = await db.into(db.employees).insert(
        EmployeesCompanion.insert(name: 'بلا ساعات', salary: const Value(5200)));
    await db.addOvertimeRecord(
        employeeId: id,
        date: DateTime(2026, 4, 7),
        hours: 2,
        manualAmount: 120);
    final r = await single();
    expect(r.amount, closeTo(120, 0.01));
    expect(r.isManualAmount, isTrue);
  });

  test('موظفٌ بلا hoursPerDay وبلا مبلغٍ يدويّ يرمي', () async {
    final id = await db.into(db.employees).insert(
        EmployeesCompanion.insert(name: 'بلا ساعات', salary: const Value(5200)));
    expect(
        () => db.addOvertimeRecord(
            employeeId: id, date: DateTime(2026, 4, 7), hours: 2),
        throwsStateError,
        reason: 'لا يُخمَّن مقام — الرقمُ المخمَّن يبدو صحيحاً وليس كذلك');
  });
}
