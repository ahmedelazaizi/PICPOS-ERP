import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

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

  group('أيامُ العمل', () {
    test('أربعُ جُمَعٍ في أبريل ٢٠٢٦ ⇒ ٣٠ − ٤ = ٢٦', () async {
      // ⚠️ ١ = الاثنين … ٥ = الجمعة (اصطلاحُ DateTime.weekday).
      await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'الجمعة', weekday: const Value(5)));
      expect(await db.workingDaysInMonth(2026, 4, branchId: null), 26);
    });

    test('عيدٌ في يوم عملٍ يُنقص يوماً إضافياً', () async {
      await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'الجمعة', weekday: const Value(5)));
      await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'العيد', date: Value(DateTime(2026, 4, 7)))); // ثلاثاء
      expect(await db.workingDaysInMonth(2026, 4, branchId: null), 25);
    });

    test('عيدٌ يقع على عطلةٍ أسبوعية لا يُخصم مرتين', () async {
      await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'الجمعة', weekday: const Value(5)));
      await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'عيدٌ على جمعة', date: Value(DateTime(2026, 4, 3))));
      expect(await db.workingDaysInMonth(2026, 4, branchId: null), 26,
          reason: 'مجموعةٌ لا قائمة — التكرارُ يُنقص يوماً غيرَ موجود');
    });

    test('الدمجُ تراكميّ: عطلاتُ الفرع + العامّة', () async {
      final branch = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع', globalId: const Value('g-1')));
      await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'عيدٌ عامّ', date: Value(DateTime(2026, 4, 7))));
      await db.into(db.workHolidays).insert(WorkHolidaysCompanion.insert(
          name: 'جمعةُ الفرع',
          weekday: const Value(5),
          branchId: Value(branch)));

      expect(await db.workingDaysInMonth(2026, 4, branchId: branch), 25,
          reason: 'صفُّ الفرع يضيف ولا يُلغي العامّ');
      expect(await db.workingDaysInMonth(2026, 4, branchId: null), 29,
          reason: 'العامُّ وحده لا يرى عطلةَ الفرع');
    });

    test('شهرٌ بلا عطلاتٍ ⇒ كلُّ أيامه عمل', () async {
      expect(await db.workingDaysInMonth(2026, 4, branchId: null), 30);
    });
  });

  group('التحقّقُ في مسار الكتابة — لا يعتمد على السكيما', () {
    test('يومٌ أسبوعيّ وحدَه يُقبَل', () async {
      final id = await db.addWorkHoliday(
          name: 'الجمعة', weekday: 5, date: null, branchId: null);
      expect(id, greaterThan(0));
    });

    test('تاريخٌ وحدَه يُقبَل', () async {
      final id = await db.addWorkHoliday(
          name: 'العيد',
          weekday: null,
          date: DateTime(2026, 4, 10),
          branchId: null);
      expect(id, greaterThan(0));
    });

    test('الشكلان معاً يُرفَضان بـArgumentError', () async {
      expect(
        () => db.addWorkHoliday(
            name: 'خطأ',
            weekday: 5,
            date: DateTime(2026, 4, 10),
            branchId: null),
        throwsArgumentError,
        reason: 'قيدُ السكيما غائبٌ على PostgreSQL القائم — فالكودُ يحرس',
      );
    });

    test('بلا أيٍّ منهما يُرفَض بـArgumentError', () async {
      expect(
        () => db.addWorkHoliday(
            name: 'فارغ', weekday: null, date: null, branchId: null),
        throwsArgumentError,
      );
    });

    test('يومُ أسبوعٍ خارج ١–٧ يُرفَض', () async {
      expect(
        () => db.addWorkHoliday(
            name: 'ثامن', weekday: 8, date: null, branchId: null),
        throwsArgumentError,
        reason: 'قيمةٌ لا يُنتجها `DateTime.weekday` أبداً ⇒ عطلةٌ لا تقع '
            'في أيّ يوم، وصفٌّ ميّتٌ لا يُرى',
      );
    });

    test('اسمٌ فارغٌ يُرفَض', () async {
      expect(
        () => db.addWorkHoliday(
            name: '  ', weekday: 5, date: null, branchId: null),
        throwsArgumentError,
        reason: 'الاسمُ هو ما يميّز الصفَّ في الشاشة والتدقيق',
      );
    });
  });
}
