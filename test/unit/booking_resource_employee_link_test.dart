// test/unit/booking_resource_employee_link_test.dart
//
// ربطُ موردِ الحجز بموظَّفِ الموارد البشريّة.
//
// ⚠️ `BookingResources.employeeId` عمودٌ قائمٌ منذ شحن المحرّك وعليه تعليقٌ
// يشرح أنه ربطٌ اختياريٌّ — و**لا موضعَ واحدٌ كان يكتبه**:
// `upsertBookingResource` لم تكن تقبله أصلاً. فالمالكُ يُنشئ الشخصَ مرّتين
// (موظَّفاً في الرواتب ومورداً في الحجوزات) ولا شيءَ يصل بينهما.
//
// والقرارُ (المالك 2026-08-23): ربطٌ **اختياريٌّ باختيارٍ من القائمين** — لا
// مزامنةٌ تلقائيّةٌ في الاتّجاهين. فالمحاسبُ وأمينُ المخزن موظَّفان ولا
// يُحجَز وقتُهما، والملفّاتُ التي تُطفئ الموارد البشريّة تظلّ تعمل.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int employeeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    employeeId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            name: 'محمد الفنان',
            salary: const Value(3000),
          ),
        );
  });

  Future<BookingResource> single() async =>
      (await db.select(db.bookingResources).get()).single;

  test('موردٌ يُربَط بموظَّفٍ قائمٍ ويُحفَظ الربط', () async {
    await db.upsertBookingResource(
      name: 'محمد الفنان',
      kind: 'staff',
      colorHex: '#3B82F6',
      employeeId: employeeId,
    );

    expect((await single()).employeeId, employeeId);
  });

  test('والربطُ اختياريٌّ — موردٌ بلا موظَّفٍ يُحفَظ', () async {
    // ملفَّا `restaurant` و`cafe` يفتحان الحجوزاتِ و`hrEnabled` مطفأةٌ
    // عندهما، فالمورد لا بدّ أن يعمل قائماً بذاته.
    await db.upsertBookingResource(
      name: 'كرسي ١',
      kind: 'device',
      colorHex: '#3B82F6',
    );

    expect((await single()).employeeId, isNull);
  });

  test('والربطُ يُفَكُّ صراحةً بلا أن يمسح باقي الحقول', () async {
    final id = await db.upsertBookingResource(
      name: 'محمد الفنان',
      kind: 'staff',
      colorHex: '#3B82F6',
      role: 'حلّاق',
      employeeId: employeeId,
    );

    await db.upsertBookingResource(
      id: id,
      name: 'محمد الفنان',
      kind: 'staff',
      colorHex: '#3B82F6',
      role: 'حلّاق',
      employeeId: null,
    );

    final row = await single();
    expect(row.employeeId, isNull, reason: 'الفكُّ يقع فعلاً لا يُتجاهَل');
    expect(row.role, 'حلّاق', reason: 'الفكُّ لا يمسح ما لم يُطلَب');
  });

  test('وموظَّفٌ لا وجودَ له يُرفَض — لا صفٌّ يشير إلى العدم', () async {
    await expectLater(
      db.upsertBookingResource(
        name: 'شبح',
        kind: 'staff',
        colorHex: '#3B82F6',
        employeeId: 999999,
      ),
      throwsA(anything),
    );
  });
}
