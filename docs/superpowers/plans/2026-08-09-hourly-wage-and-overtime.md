# الأجر بالساعة والإضافي المحسوب — خطة التنفيذ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** جعلُ `salaryType == 'hourly'` يُحسب من ساعات الحضور الفعلية، وتصحيحُ مقام أجر الساعة في الإضافي، بتقويمِ عطلاتٍ يعرّفه المستخدم لكل فرع.

**Architecture:** دالةٌ واحدة `hourlyRateFor` هي المصدرُ الوحيد لأجر الساعة، تقرأ `hoursPerDay` من الموظف وأيامَ العمل من `HolidayCalendar`. يستعملها مسارُ الراتب ومسارُ الإضافي معاً، فلا يبقى موضعان يشتقّان الرقمَ نفسه.

**Tech Stack:** Flutter · Drift (SQLite + PostgreSQL) · Riverpod · flutter_test

## Global Constraints

- **المواصفة:** `docs/superpowers/specs/2026-08-09-hourly-wage-and-overtime-design.md` — اقرأها قبل المهمة ١.
- **`build_runner` يحتاج ~٤١ دقيقة** في هذه البيئة، منها ٤٠ تحليلٌ صامتٌ بلا نموّ في الكاش. **لا تقتله.** الأمر: `dart run build_runner build --delete-conflicting-outputs`.
- **ممنوع تعديل `lib/data/database/database.g.dart` يدوياً** — ينقص نحو ٤٠٪ بصمت رغم نجاح `analyze` والاختبارات.
- **قبل أيّ `flutter test`:** `rm -rf build/native_assets` — وإلا `PathExistsException` على `sqlite3.dll`.
- **البوابة:** `bash scripts/gate.sh --pg`، تُشغَّل في الخلفية (‏~١٥ دقيقة، وسقفُ أداة الصدفة ١٠). واقرأ `GATE_EXIT` من السجلّ لا من حالة الإشعار.
- **حدودُ البوابة الدنيا تُرفَع في نفس كوميت إضافة الاختبارات** (`scripts/gate.sh`).
- **`schemaVersion` الحالي ١٥٢** — كلُّ تغييرِ سكيما يرفعه ويضيف خطوةَ هجرة.
- **الاختبار قبل الكود دائماً**، ولكلّ إصلاحٍ طفرةٌ تُثبت أن الاختبار يميّز. وتحقّق أن الطفرة **طُبِّقت** (`grep -c`) قبل تفسير نتيجتها — نهاياتُ الأسطر CRLF تُفشل أنماطَ `perl` الحاوية على `\n` أو مرساة `$` صامتةً.
- ⚠️ **`EmployeeSalaryCalculation` لا يعرّف `basePay`** — الأجرُ الأساسيّ متغيّرٌ محلّيٌّ داخل `calculateNetSalary`. المتاحُ من الخارج `grossPay` (‏= الأساسيُّ + الإضافي) و`baseSalary` (‏= **راتبُ العقد** لا المحسوب). فاختباراتُ الأجر الأساسيّ تقارن بـ`grossPay` **وتُبقي `overtimeRecords` فارغاً** كي يتساويا. أضِف صفَّ إضافيٍّ في اختبارٍ يقيس الأساسيَّ ⇒ الرقمُ يزيح بلا سبب ظاهر. (اكتُشف في المهمة ١.)

---

## File Structure

| الملف | المسؤولية |
|---|---|
| `lib/data/database/tables/hr_tables.dart` | جدولُ `WorkHolidays` الجديد · عمودُ `hoursPerDay` · عمودُ `isManualAmount` |
| `lib/data/database/daos/work_holidays_dao.dart` | **جديد** — قراءةُ العطلات وكتابتُها، وحسابُ أيام العمل |
| `lib/data/database/extensions/hr_extensions.dart` | `hourlyRateFor` · موديلُ `hourly` · تصحيحُ `addOvertimeRecord` |
| `lib/domain/repositories/hr_repository_interface.dart` + `lib/data/repositories/hr_repository_impl.dart` | تمريرُ عمليات العطلات |
| `lib/presentation/screens/settings/work_holidays_screen.dart` | **جديد** — شاشةُ تعريف العطلات |
| `test/unit/hourly_rate_test.dart` · `test/unit/work_holidays_test.dart` · `test/unit/hourly_salary_model_test.dart` · `test/unit/overtime_amount_test.dart` | الاختبارات |

---

## Task 1: اختبارُ توصيفٍ مؤقّت — يُستبدَل بالكامل في المهمة ٥

**Files:**
- Test: `test/unit/hourly_salary_model_test.dart` (create)

**Interfaces:**
- Consumes: `AppDatabase.calculateNetSalary({employeeId, year, month})` · `kMonthlySalaryType`
- Produces: لا شيء — اختبارُ توصيفٍ فقط

🔴 **للمراجِع — اقرأ هذا قبل أن تحكم:** اختباراتُ هذه المهمة **تُثبّت سلوكاً
معطوباً عن قصد**: موظفُ `hourly` يأخذ أجرَ يومٍ كامل مقابل ساعتين. هذا
**ليس** إقراراً بالسلوك ولا خطأً في المراجعة — هو **اختبارُ توصيف
(characterization test)**، غرضُه الوحيد تثبيتُ الرقم الحالي كي يظهر تغييرُه
في الـdiff بدل أن يُكتشف في كشف رواتب.

`hourly` بلا اختبارٍ واحد اليوم، فلا شيء يقول ما كان عليه قبل التغيير.

**عمرُ هذا الملفّ ينتهي في المهمة ٥**، التي تعيد كتابته كاملاً باختبارات
تتحقّق من السلوك الصحيح. فلا تُطلب له تغطيةٌ أوسع ولا حالاتٌ حدّية — إضافةُ
أيٍّ منها عملٌ يُرمى بعد مهمتين.

- [ ] **Step 1: اكتب اختبار التوصيف**

```dart
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
```

- [ ] **Step 2: شغّله وتأكّد أنه يمرّ**

```bash
rm -rf build/native_assets && flutter test test/unit/hourly_salary_model_test.dart --concurrency=1
```
المتوقَّع: PASS — هذا توصيفٌ للحاضر لا اختبارُ عطل. لو فشل، فافتراضُ الخطة عن الموديل الحالي غلط: **توقّف وأعِد القياس**.

- [ ] **Step 3: ارفع حدَّ البوابة وكوّم**

في `scripts/gate.sh` ارفع الرقم في `run_suite "unit + data + structural + services" <N>` بمقدار ٢.

```bash
git add test/unit/hourly_salary_model_test.dart scripts/gate.sh
git commit -m "test(hr): توصيفُ موديل hourly الحالي قبل تغييره"
```

---

## Task 2: جدول العطلات والسكيما

**Files:**
- Modify: `lib/data/database/tables/hr_tables.dart`
- Modify: `lib/data/database/database.dart` (‏`schemaVersion` و`MigrationStrategy`)
- Test: `test/unit/work_holidays_test.dart` (create)

**Interfaces:**
- Produces: جدولُ `WorkHolidays` بالأعمدة `id` · `branchId` (‏`int?`) · `weekday` (‏`int?`) · `date` (‏`DateTime?`) · `name` (‏`String`) · `createdAt`. وعمودُ `Employees.hoursPerDay` (‏`double?`). وعمودُ `OvertimeRecords.isManualAmount` (‏`bool`، افتراضيّ `false`).

- [ ] **Step 1: أضف الجدول والعمودين**

في `lib/data/database/tables/hr_tables.dart`، بعد `class OvertimeRecords`:

```dart
/// تقويمُ العطلات — يعرّفه المستخدم لكلّ فرع.
///
/// شكلان في جدولٍ واحد: يومٌ أسبوعيٌّ متكرّر، أو تاريخٌ بعينه. والصفُّ يحمل
/// **أحدَهما لا كليهما** — يُفرض بقيدٍ في [WorkHolidays.customConstraints].
///
/// `branchId` معدومٌ = يسري على كلّ الفروع. والدمجُ **تراكميّ**: عطلاتُ فرعٍ
/// هي صفوفُه مضافةً إلى الصفوف العامّة، لا بديلةً عنها.
class WorkHolidays extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get branchId => integer().nullable().references(Branches, #id)();

  /// قيمةُ `DateTime.weekday`: ‏١ = الاثنين … ٧ = الأحد.
  IntColumn get weekday => integer().nullable()();
  DateTimeColumn get date => dateTime().nullable()();
  TextColumn get name => text().withLength(max: 100)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
        'CHECK ((weekday IS NULL) <> (date IS NULL))',
      ];
}
```

وفي `class Employees` أضف:

```dart
  /// ساعاتُ العمل اليومية — مقامُ أجر الساعة.
  ///
  /// مطلوبٌ لموظف `hourly`، واختياريٌّ لغيره: بدونه لا يُشتقّ مبلغُ الإضافي
  /// ويبقى يدوياً. ولا تُخمَّن قيمةٌ افتراضية — تخمينُ المقام يعطي رقماً
  /// يبدو صحيحاً وليس كذلك.
  RealColumn get hoursPerDay => real().nullable()();
```

وفي `class OvertimeRecords` أضف:

```dart
  /// المبلغُ عُدِّل يدوياً ⇒ لا يُعاد اشتقاقُه.
  ///
  /// السجلّاتُ القائمة تُهاجَر إلى `true`: قيمُها حُسبت بمقامٍ آخر، وإعادةُ
  /// حسابها تغيّر رواتبَ ماضية.
  BoolColumn get isManualAmount =>
      boolean().withDefault(const Constant(false))();
```

- [ ] **Step 2: سجّل الجدول وارفع إصدار السكيما**

في `lib/data/database/database.dart` أضف `WorkHolidays` إلى قائمة `tables` في `@DriftDatabase`، وغيّر `int get schemaVersion => 152;` إلى `153`، وأضف في `MigrationStrategy.onUpgrade`:

```dart
        if (from < 153) {
          await m.createTable(workHolidays);
          await m.addColumn(employees, employees.hoursPerDay);
          await m.addColumn(overtimeRecords, overtimeRecords.isManualAmount);
          // السجلّاتُ القائمة حُسبت بمقامٍ آخر — تُعلَّم يدويةً فلا يُعاد
          // حسابُها وتتغيّر رواتبُ ماضية.
          await customStatement(
              'UPDATE overtime_records SET is_manual_amount = 1');
        }
```

- [ ] **Step 3: ولّد الكود**

```bash
dart run build_runner build --delete-conflicting-outputs
```
⚠️ **~٤١ دقيقة، منها ٤٠ صامتة. لا تقتله.** وممنوع تعديل `database.g.dart` يدوياً.

- [ ] **Step 4: اكتب اختبار السكيما والقيد**

```dart
// test/unit/work_holidays_test.dart
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
```

- [ ] **Step 5: شغّل**

```bash
rm -rf build/native_assets && flutter test test/unit/work_holidays_test.dart --concurrency=1
```
المتوقَّع: PASS (‏٤ اختبارات).

- [ ] **Step 6: ارفع حدَّ البوابة وكوّم**

```bash
git add lib/data/database/ test/unit/work_holidays_test.dart scripts/gate.sh
git commit -m "feat(hr): جدولُ تقويم العطلات وعمودا ساعاتِ اليوم والتجاوز اليدويّ"
```

---

## Task 3: حسابُ أيام العمل

**Files:**
- Create: `lib/data/database/daos/work_holidays_dao.dart`
- Modify: `lib/data/database/database.dart` (‏`part` للملف الجديد)
- Test: `test/unit/work_holidays_test.dart` (append)

**Interfaces:**
- Consumes: جدولُ `WorkHolidays` من المهمة ٢
- Produces:
  - `Future<Set<DateTime>> holidaysInMonth(int year, int month, {required int? branchId})` — أيامُ العطلة كتواريخَ بلا وقت
  - `Future<int> workingDaysInMonth(int year, int month, {required int? branchId})`

- [ ] **Step 1: اكتب الاختبار الفاشل**

أضف إلى `test/unit/work_holidays_test.dart`:

```dart
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
```

- [ ] **Step 2: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/work_holidays_test.dart --concurrency=1
```
المتوقَّع: FAIL بـ`The method 'workingDaysInMonth' isn't defined`.

- [ ] **Step 3: نفّذ الأدنى**

```dart
// lib/data/database/daos/work_holidays_dao.dart
part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WORK HOLIDAYS — تقويمُ العطلات وأيامُ العمل
// ═══════════════════════════════════════════════════════════════════════════

extension WorkHolidaysDao on AppDatabase {
  /// أيامُ العطلة في شهرٍ لفرعٍ ما — تواريخُ بلا وقت.
  ///
  /// **مجموعةٌ لا قائمة**: عيدٌ يقع على عطلةٍ أسبوعية يجب أن يُعدّ يوماً
  /// واحداً، وإلا نقص من المقام يومٌ غيرُ موجودٍ فارتفع أجرُ الساعة زوراً.
  ///
  /// والدمجُ تراكميّ: صفوفُ الفرع **مضافةً إلى** صفوف `branchId` المعدوم.
  Future<Set<DateTime>> holidaysInMonth(
    int year,
    int month, {
    required int? branchId,
  }) async {
    final rows = await (select(workHolidays)
          ..where((h) => branchId == null
              ? h.branchId.isNull()
              : h.branchId.isNull() | h.branchId.equals(branchId)))
        .get();

    final last = DateTime(year, month + 1, 0).day;
    final out = <DateTime>{};
    for (final r in rows) {
      if (r.weekday != null) {
        for (var d = 1; d <= last; d++) {
          final day = DateTime(year, month, d);
          if (day.weekday == r.weekday) out.add(day);
        }
      } else if (r.date != null) {
        final d = r.date!;
        if (d.year == year && d.month == month) {
          out.add(DateTime(d.year, d.month, d.day));
        }
      }
    }
    return out;
  }

  /// أيامُ العمل = أيامُ الشهر التقويمية − العطلات.
  Future<int> workingDaysInMonth(
    int year,
    int month, {
    required int? branchId,
  }) async {
    final last = DateTime(year, month + 1, 0).day;
    final holidays = await holidaysInMonth(year, month, branchId: branchId);
    return last - holidays.length;
  }
}
```

وفي `lib/data/database/database.dart` أضف بجوار بقية الأجزاء:

```dart
part 'daos/work_holidays_dao.dart';
```

- [ ] **Step 4: شغّل وتأكّد أنه يمرّ**

```bash
rm -rf build/native_assets && flutter test test/unit/work_holidays_test.dart --concurrency=1
```
المتوقَّع: PASS (‏٩ اختبارات).

- [ ] **Step 5: اقتل طفرةً**

بدّل `out.add(day)` إلى قائمةٍ بدل مجموعة (‏`final out = <DateTime>[]`) وشغّل: يجب أن يسقط اختبارُ «عيدٌ يقع على عطلةٍ أسبوعية». تحقّق أوّلاً أن التبديلَ دخل الملف (`grep -c '<DateTime>\['`)، ثم استعِد الملف من نسخةٍ احتياطية — **لا تستعمل `git checkout`**.

- [ ] **Step 6: اكتب اختبارَ التحقّق في مسار الكتابة**

🔴 **لماذا هذا مطلوبٌ رغم وجود قيدِ `CHECK`:** القيدُ في السكيما **لا يوجد على تنصيبات PostgreSQL القائمة**. مقيسٌ في المهمة ٢: `onUpgrade` متجاوَزٌ كلياً على PostgreSQL، والآليةُ الوحيدة لإيصال جدولٍ جديد إلى خادمٍ قائم هي `_ensurePostgresSchemaParity` — وهي لا تكتب `customConstraints` إطلاقاً. فصفٌّ يحمل الشكلين معاً يُقبَل **بصمت** هناك.

فالتحقّقُ في **الكود** يحمي المحرّكَين معاً بلا اعتمادٍ على السكيما. (قرارُ المالك 2026-08-09؛ وإصلاحُ `_buildPgCreateTableSql` بندٌ مستقلٌّ مؤجَّل.)

أضف إلى `test/unit/work_holidays_test.dart`:

```dart
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
```

- [ ] **Step 7: نفّذ التحقّق**

أضف إلى `lib/data/database/daos/work_holidays_dao.dart`:

```dart
  /// يضيف عطلةً بعد **تحقّقٍ في الكود** لا في السكيما وحدها.
  ///
  /// قيدُ `CHECK` موجودٌ على SQLite، لكنه **غائبٌ عن تنصيبات PostgreSQL
  /// القائمة**: `onUpgrade` متجاوَزٌ هناك، و`_ensurePostgresSchemaParity` —
  /// الآليةُ الوحيدة لإيصال جدولٍ جديد لخادمٍ قائم — لا تكتب
  /// `customConstraints`. فصفٌّ يحمل الشكلين يمرّ بصمت. والتحقّقُ هنا يحمي
  /// المحرّكَين معاً.
  Future<int> addWorkHoliday({
    required String name,
    required int? weekday,
    required DateTime? date,
    required int? branchId,
  }) async {
    if ((weekday == null) == (date == null)) {
      throw ArgumentError(
          'العطلةُ إمّا يومٌ أسبوعيٌّ متكرّر وإمّا تاريخٌ بعينه — لا الاثنان '
          'ولا لا شيء');
    }
    if (weekday != null && (weekday < 1 || weekday > 7)) {
      throw ArgumentError(
          'يومُ الأسبوع خارج المدى ١–٧ (اصطلاحُ DateTime.weekday): $weekday');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError('اسمُ العطلة مطلوب');
    }
    return into(workHolidays).insert(WorkHolidaysCompanion.insert(
      name: name.trim(),
      weekday: Value(weekday),
      date: Value(date),
      branchId: Value(branchId),
    ));
  }
```

- [ ] **Step 8: شغّل**

```bash
rm -rf build/native_assets && flutter test test/unit/work_holidays_test.dart --concurrency=1
```
المتوقَّع: PASS (‏١٥ اختباراً: ٤ من المهمة ٢ · ٥ لأيام العمل · ٦ للتحقّق).

- [ ] **Step 9: اقتل طفرةَ التحقّق**

بدّل `if ((weekday == null) == (date == null))` إلى `if (false)` وشغّل: يجب أن يسقط اختبارا «الشكلان معاً» و«بلا أيٍّ منهما». تحقّق بـ`grep -c 'if (false)'` أن التبديل دخل، ثم استعِد بنسخةٍ احتياطية.

- [ ] **Step 10: ارفع حدَّ البوابة وكوّم**

الحدُّ الحاليّ ٢٩٠٠؛ ارفعه بعددِ اختباراتك الجديدة بالضبط (‏١١).

```bash
git add lib/data/database/ test/unit/work_holidays_test.dart scripts/gate.sh
git commit -m "feat(hr): حسابُ أيام العمل · وتحقّقُ الكتابة يحرس ما لا تحرسه سكيما PostgreSQL"
```

---

## Task 4: نواةُ أجر الساعة

**Files:**
- Modify: `lib/data/database/extensions/hr_extensions.dart`
- Test: `test/unit/hourly_rate_test.dart` (create)

**Interfaces:**
- Consumes: `workingDaysInMonth(year, month, branchId:)` من المهمة ٣ · `Employee.hoursPerDay` · `Employee.branchId`
- Produces: `Future<double> hourlyRateFor(Employee employee, int year, int month)` — يرمي `StateError` عند صفرِ أيامِ عملٍ أو `hoursPerDay` غيرِ صالح.

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
// test/unit/hourly_rate_test.dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

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
    expect(() => db.hourlyRateFor(await emp(hours: 0), 2026, 4),
        throwsStateError);
    expect(() => db.hourlyRateFor(await emp(hours: -1), 2026, 4),
        throwsStateError);
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/hourly_rate_test.dart --concurrency=1
```
المتوقَّع: FAIL بـ`The method 'hourlyRateFor' isn't defined`.

- [ ] **Step 3: نفّذ الأدنى**

في `lib/data/database/extensions/hr_extensions.dart`، بعد `kStandardWorkHoursPerDay`:

```dart
  /// أجرُ الساعة لموظفٍ في شهرٍ بعينه — **المصدرُ الوحيد**.
  ///
  ///     الراتب الشهري ÷ (ساعاتُ اليوم × أيامِ العمل في ذلك الشهر)
  ///
  /// يستعمله مسارُ الراتب ومسارُ الإضافي معاً. وكان الإضافيُّ يشتقّه محلياً
  /// بمقامٍ خاطئ — `_daysInMonth` (أيامُ التقويم) و٨ ساعاتٍ مثبّتة — فساعةُ
  /// الموظف الإضافية كانت أرخص مما تستحق بنحو ١٥٪ في شهرٍ بأربع عطلات.
  ///
  /// **لا يُقرَّب الناتج**: التقريبُ هنا يتراكم على عشرات الساعات، والتقريبُ
  /// موضعُه الناتجُ النهائيّ وحده.
  Future<double> hourlyRateFor(Employee employee, int year, int month) async {
    final hours = employee.hoursPerDay;
    if (hours == null || hours <= 0) {
      throw StateError(
          'ساعاتُ العمل اليومية غيرُ محدَّدة للموظف ${employee.id} — '
          'لا يمكن اشتقاقُ أجر الساعة');
    }
    final days = await workingDaysInMonth(year, month,
        branchId: employee.branchId);
    if (days <= 0) {
      throw StateError(
          'لا أيامَ عملٍ في $month/$year لفرع الموظف ${employee.id} — '
          'راجع تقويمَ العطلات');
    }
    return employee.salary / (hours * days);
  }
```

- [ ] **Step 4: شغّل وتأكّد أنه يمرّ**

```bash
rm -rf build/native_assets && flutter test test/unit/hourly_rate_test.dart --concurrency=1
```
المتوقَّع: PASS (‏٦ اختبارات).

- [ ] **Step 5: اقتل طفرتين**

١. استبدل `workingDaysInMonth(...)` بـ`_daysInMonth(year, month)` ⇒ يجب أن يسقط اختبارُ «بأربعِ جُمَع».
٢. غلّف الناتج بـ`double.parse(r.toStringAsFixed(2))` ⇒ يجب أن يسقط اختبارُ «لا يُقرَّب».
تحقّق من تطبيق كلٍّ بـ`grep -c` قبل تفسير النتيجة، واستعِد بنسخةٍ احتياطية.

- [ ] **Step 6: ارفع حدَّ البوابة وكوّم**

```bash
git add lib/data/database/extensions/hr_extensions.dart test/unit/hourly_rate_test.dart scripts/gate.sh
git commit -m "feat(hr): نواةُ أجر الساعة — مصدرٌ واحد للراتب والإضافي"
```

---

## Task 5: موديلُ `hourly` في حساب الراتب

**Files:**
- Modify: `lib/data/database/extensions/hr_extensions.dart` (‏`calculateNetSalary` قرب سطر ٨٥٣)
- Test: `test/unit/hourly_salary_model_test.dart` (rewrite)

**Interfaces:**
- Consumes: `hourlyRateFor(employee, year, month)` من المهمة ٤
- Produces: `basePay` لـ`hourly` = ساعاتُ الحضور × أجرُ الساعة. ويُضاف الثابتُ `const String kHourlySalaryType = 'hourly';`

- [ ] **Step 1: أعِد كتابة الاختبار — من توصيفٍ إلى تحقّق**

استبدل محتوى `test/unit/hourly_salary_model_test.dart` كاملاً:

```dart
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
```

- [ ] **Step 2: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/hourly_salary_model_test.dart --concurrency=1
```
المتوقَّع: FAIL — أول اختبارٍ يعطي ٢٠٠ (يومان × ١٠٠) بدل ٣٠٠.

- [ ] **Step 3: نفّذ**

أضف الثابت بجوار `kMonthlySalaryType`:

```dart
const String kHourlySalaryType = 'hourly';
```

أضف قبل حساب `basePay` في `calculateNetSalary`:

```dart
    // ساعاتُ الحضور الفعلية — صفٌّ بلا انصرافٍ لا يُحتسب: مدةٌ مجهولة
    // تُوثَّق ولا تُخمَّن.
    final hoursWorked = attendanceRecords.fold<double>(0, (sum, a) {
      final inAt = a.checkIn, outAt = a.checkOut;
      if (inAt == null || outAt == null) return sum;
      return sum + outAt.difference(inAt).inMinutes / 60.0;
    });
```

⚠️ اسمُ متغيّرِ صفوفِ الحضور في الدالة قد يختلف — اقرأ الدالة وثبّته قبل الكتابة.

واستبدل تفريعَ `basePay`:

```dart
    final basePay = switch (employee.salaryType) {
      kMonthlySalaryType => employee.salary - dailyRate * unpaidDays,
      kHourlySalaryType =>
        hoursWorked * await hourlyRateFor(employee, year, month),
      _ => dailyRate * daysAttended,
    };
```

ولخصمِ الغياب في الشهري، استثنِ أيامَ العطلة عند حساب `unpaidDays`:

```dart
    // التقويمُ يسري على الجميع (قرار المالك 2026-08-09، مواصفة الأجر
    // بالساعة): يومُ العطلة لا يُعدّ غياباً.
    final holidays = await holidaysInMonth(year, month,
        branchId: employee.branchId);
    final unpaidDays = unpaidRecords
        .where((r) => !holidays.contains(
            DateTime(r.date.year, r.date.month, r.date.day)))
        .length;
```

- [ ] **Step 4: شغّل وتأكّد أنه يمرّ**

```bash
rm -rf build/native_assets && flutter test test/unit/hourly_salary_model_test.dart test/unit/monthly_salary_model_test.dart test/unit/payroll_approved_leave_test.dart --concurrency=1
```
المتوقَّع: PASS — بما فيها اختباراتُ الشهريِّ القائمة.

- [ ] **Step 5: اقتل طفرتين**

١. أعِد `_ => dailyRate * daysAttended` لتشمل `hourly` ⇒ يسقط أولُ اختبارين.
٢. أسقِط ترشيحَ العطلات من `unpaidDays` ⇒ يسقط «غيابٌ في يوم عطلةٍ لا يُخصم».

- [ ] **Step 6: ارفع حدَّ البوابة وكوّم**

```bash
git add lib/data/database/extensions/hr_extensions.dart test/unit/hourly_salary_model_test.dart scripts/gate.sh
git commit -m "feat(hr): موديلُ hourly من ساعات الحضور · والعطلةُ لا تُعدّ غياباً"
```

---

## Task 6: الإضافي — مقامٌ صحيحٌ وتجاوزٌ معلَّم

**Files:**
- Modify: `lib/data/database/extensions/hr_extensions.dart` (‏`addOvertimeRecord` قرب سطر ١٢٠٨)
- Test: `test/unit/overtime_amount_test.dart` (create)

**Interfaces:**
- Consumes: `hourlyRateFor` من المهمة ٤ · `OvertimeRecords.isManualAmount` من المهمة ٢
- Produces: `addOvertimeRecord({employeeId, date, hours, rate, notes, double? manualAmount})` — تمريرُ `manualAmount` يضبط `isManualAmount = true`.

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
// test/unit/overtime_amount_test.dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

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
```

- [ ] **Step 2: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/overtime_amount_test.dart --concurrency=1
```
المتوقَّع: FAIL — أولُ اختبارٍ يعطي ٦٥ بدل ٧٥ (المقامُ ٣٠ يوماً).

- [ ] **Step 3: نفّذ**

استبدل جسمَ `addOvertimeRecord`:

```dart
  Future<int> addOvertimeRecord({
    required int employeeId,
    required DateTime date,
    required double hours,
    double rate = 1.5,
    String? notes,
    double? manualAmount,
  }) async {
    final employee = await (select(
      employees,
    )..where((e) => e.id.equals(employeeId))).getSingle();

    // المبلغُ مُشتقٌّ من [hourlyRateFor] — المصدرِ الوحيد. وكان يُشتقّ هنا
    // محلياً بمقام `_daysInMonth` (أيامِ التقويم) و٨ ساعاتٍ مثبّتة، فساعةُ
    // الموظف الإضافية أرخصُ ممّا تستحق بنحو ١٥٪ في شهرٍ بأربع عطلات.
    final double amount;
    if (manualAmount != null) {
      amount = manualAmount;
    } else {
      amount = hours * rate * await hourlyRateFor(employee, date.year, date.month);
    }

    return into(overtimeRecords).insert(
      OvertimeRecordsCompanion.insert(
        employeeId: employeeId,
        date: date,
        hours: hours,
        rate: Value(rate),
        amount: amount,
        isManualAmount: Value(manualAmount != null),
        notes: Value(notes),
      ),
    );
  }
```

- [ ] **Step 4: شغّل وتأكّد أنه يمرّ**

```bash
rm -rf build/native_assets && flutter test test/unit/overtime_amount_test.dart --concurrency=1
```
المتوقَّع: PASS (‏٦ اختبارات).

- [ ] **Step 5: اقتل طفرةً**

استبدل `hourlyRateFor(...)` بالصيغة القديمة `employee.salary / _daysInMonth(date.year, date.month) / kStandardWorkHoursPerDay` ⇒ يجب أن يسقط أولُ اختبار.

- [ ] **Step 6: ارفع حدَّ البوابة وكوّم**

```bash
git add lib/data/database/extensions/hr_extensions.dart test/unit/overtime_amount_test.dart scripts/gate.sh
git commit -m "fix(hr): مقامُ أجر الساعة في الإضافي كان أيامَ التقويم لا أيامَ العمل"
```

---

## Task 6أ: توصيلُ المسار — الإضافي معطَّلٌ صامتاً بعد المهمة ٦

**Files:**
- Modify: `lib/domain/repositories/hr_repository_interface.dart:101-107`
- Modify: `lib/data/repositories/hr_repository_impl.dart:183-195`
- Modify: `lib/presentation/screens/hr/hr_notifier.dart:209-223`
- Modify: `lib/presentation/screens/hr/widgets/overtime_tab.dart` (نحو ٢٠٦-٢٢٤)
- Modify: `lib/presentation/screens/hr/hr_dialogs.dart` (‏`showEmployeeForm`)
- Modify: `lib/data/database/extensions/hr_extensions.dart` (‏`addEmployee` · `updateEmployee`)
- Test: `test/unit/employee_hours_validation_test.dart` (create)

**Interfaces:**
- Consumes: `addOvertimeRecord({… , double? manualAmount})` من المهمة ٦ · `kHourlySalaryType` من المهمة ٥
- Produces: `addEmployee({… , double? hoursPerDay})` و`updateEmployee({… , double? hoursPerDay})` يرميان `ArgumentError` لموظف `hourly` بلا ساعاتٍ صالحة · `IHRRepository.addOvertimeRecord({… , double? manualAmount})` · `HRNotifier.addOvertime({… , double? manualAmount})`

🔴 **لماذا هذه المهمة أُدرجت بعد كتابة الخطة:** المهمةُ ٦ جعلت `addOvertimeRecord` يرمي `StateError` لأيّ موظفٍ بلا `hoursPerDay` حين لا يُمرَّر `manualAmount`. وفحصُ المراجعة أظهر ثلاثةَ أمورٍ لم تكن الخطةُ تعلمها:

1. **لا واجهةَ في التطبيق تعرض `hoursPerDay` لأحد** — ولا حتى لموظف `hourly`.
2. **`manualAmount` غيرُ موصَّلٍ للواجهة** — لا في `IHRRepository` ولا `HRRepositoryImpl` ولا `HRNotifier`. فمنفذُ الهروب المصمَّم غيرُ قابلٍ للوصول.
3. **الفشلُ صامتٌ تماماً**: `HRNotifier` ليس `AsyncNotifier` وبلا `try/catch`، فالاستثناءُ يهبط في `PlatformDispatcher.onError` الذي يسجّله ويُعيد `true` — لا التطبيقُ يسقط ولا المستخدمُ يرى شيئاً. يضغط «تسجيل»، النافذةُ تبقى مفتوحة، ولا رسالةَ ولا سجلّ.

⇒ **تسجيلُ الإضافي معطَّلٌ لكلّ الموظفين** في التطبيق الحيّ، لا للشهريّين وحدَهم.

⚠️ **والمهمةُ ٨ القديمة مدموجةٌ هنا** — كانت تضيف الحقلَ «مطلوباً لـ`hourly` وحدَه»، وهذا لا يغلق الثغرة: `hoursPerDay` مطلوبٌ عملياً **لكلّ من يُسجَّل له إضافي**. فالحقلُ يظهر للجميع، ويُلزَم لـ`hourly` وحدَه، ومَن لا يملكه يسجّل إضافيَّه بمبلغٍ يدويّ.

- [ ] **Step 1: اكتب اختبارَ التحقّق الفاشل**

```dart
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
      () => db.updateEmployee(id, salaryType: 'hourly'),
      throwsArgumentError,
      reason: 'بابُ التعديل ثغرةٌ إن حُرس بابُ الإضافة وحدَه',
    );
  });

  test('التعديلُ إلى hourly مع ساعاتٍ يُقبَل', () async {
    final id = await db.addEmployee(name: 'ش', salary: 5200);
    await db.updateEmployee(id, salaryType: 'hourly', hoursPerDay: 8);
    final e = await (db.select(db.employees)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(e.hoursPerDay, 8);
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/employee_hours_validation_test.dart --concurrency=1
```
المتوقَّع: FAIL — لا معاملَ `hoursPerDay` في `addEmployee`.

- [ ] **Step 3: نفّذ التحقّق في طبقة البيانات**

في `hr_extensions.dart` أضف `double? hoursPerDay` إلى معاملات `addEmployee` و`updateEmployee`، ومرّرْه في الـCompanion (‏`hoursPerDay: Value(hoursPerDay)`). وأضف في أوّل كلٍّ منهما:

```dart
    // ساعاتُ اليوم مقامُ أجر الساعة. وموظفُ `hourly` بدونها تجهيزةٌ ناقصة
    // تُفشل حسابَ راتبه، والمنعُ عند الإدخال أرخصُ وأوضحُ من اكتشافه في كشف.
    if (salaryType == kHourlySalaryType &&
        (hoursPerDay == null || hoursPerDay <= 0)) {
      throw ArgumentError('ساعاتُ العمل اليومية مطلوبةٌ لموظفٍ بأجر الساعة');
    }
```

⚠️ في `updateEmployee` احذر: `salaryType` معاملٌ اختياريّ (‏`String?`). لو كان `null` فالنوعُ لم يتغيّر — اقرأ الصفَّ القائمَ لتعرف النوعَ الفعليّ قبل الحكم، ولا تفترض أن `null` يعني «ليس hourly».

- [ ] **Step 4: شغّل وتأكّد أنه يمرّ**

```bash
rm -rf build/native_assets && flutter test test/unit/employee_hours_validation_test.dart test/unit/manage_employee_usecase_test.dart --concurrency=1
```
المتوقَّع: PASS — بما فيها اختباراتُ الموظف القائمة.

- [ ] **Step 5: مرّر `manualAmount` عبر الطبقات الثلاث**

أضِف `double? manualAmount` إلى:
* `IHRRepository.addOvertimeRecord` (‏`hr_repository_interface.dart:101`)
* `HRRepositoryImpl.addOvertimeRecord` (‏`hr_repository_impl.dart:183`) — ومرّرْه إلى `_db.addOvertimeRecord`
* `HRNotifier.addOvertime` (‏`hr_notifier.dart:209`) — ومرّرْه إلى المستودع

- [ ] **Step 6: أوقِف الفشلَ الصامت**

في `HRNotifier.addOvertime` غلّف النداءَ:

```dart
  /// يُعيد `null` عند النجاح، أو رسالةَ خطأٍ للعرض.
  ///
  /// كان النداءُ عارياً، و`HRNotifier` ليس `AsyncNotifier` فلا تغليفَ تلقائي:
  /// أيُّ استثناءٍ يهبط في `PlatformDispatcher.onError` الذي يسجّله ويُعيد
  /// `true` — فلا التطبيقُ يسقط ولا المستخدمُ يرى شيئاً. الزرُّ يبدو أنه لم
  /// يفعل شيئاً، والسجلُّ لا يُحفظ، ولا رسالة. **الفشلُ الصامت أسوأ من
  /// الانهيار**: الانهيارُ يُبلَّغ عنه.
  Future<String?> addOvertime({
    required int employeeId,
    required DateTime date,
    required double hours,
    double rate = 1.5,
    String? notes,
    double? manualAmount,
  }) async {
    try {
      await _hrRepo.addOvertimeRecord(
        employeeId: employeeId,
        date: date,
        hours: hours,
        rate: rate,
        notes: notes,
        manualAmount: manualAmount,
      );
      return null;
    } on StateError catch (e) {
      return 'تعذّر احتسابُ المبلغ تلقائياً: ${e.message}. '
          'أدخِل ساعاتِ العمل اليومية للموظف، أو أدخِل المبلغَ يدوياً.';
    } catch (e) {
      return 'تعذّر تسجيلُ الوقت الإضافي: $e';
    }
  }
```

وفي `overtime_tab.dart` عند الزرّ: استقبل القيمةَ المُعادة، واعرضها بـ`AppToast` إن لم تكن `null`، ولا تُغلق النافذةَ إلا عند النجاح.

- [ ] **Step 7: أضِف الحقلَين للواجهة**

في `hr_dialogs.dart` (‏`showEmployeeForm`):
* حقلٌ رقميّ **«ساعات العمل اليومية»** يظهر **لكلّ الأنواع** — مع تلميحٍ «مطلوب لأجر الساعة، ويُستعمل لاحتساب الوقت الإضافي تلقائياً». امنع الحفظَ إن كان النوعُ `hourly` والحقلُ فارغاً أو ≤ صفر.
* وفي نافذة «تسجيل عمل إضافي»: حقلٌ اختياريّ **«المبلغ (اتركه فارغاً للاحتساب التلقائي)»** يُمرَّر `manualAmount`.

- [ ] **Step 8: شغّل السويّات المتأثّرة**

```bash
rm -rf build/native_assets && flutter test test/unit/employee_hours_validation_test.dart test/unit/overtime_amount_test.dart test/unit/manage_employee_usecase_test.dart test/unit/hourly_salary_model_test.dart --concurrency=1
```
المتوقَّع: PASS. و`flutter analyze lib test` ⇒ ٦ info صفر error/warning.

- [ ] **Step 9: اقتل طفرتين**

١. أسقِط شرطَ `ArgumentError` في `addEmployee` ⇒ يجب أن يسقط اختبارا `hourly` بلا ساعات.
٢. أعِد `addOvertime` إلى نداءٍ عارٍ بلا `try/catch` وأرجِع `void` ⇒ يجب أن يفشل التصريفُ عند مستدعي `overtime_tab` — **وهذه طفرةٌ تكسر التصريف فلا تُثبت المنطق**؛ سجّل ذلك واقترح بديلاً يُبقيه مترجَماً (مثلاً `catch` يبتلع ويُعيد `null` دائماً) وشغّله.

تحقّق بـ`grep -c` أن كلَّ طفرةٍ دخلت **قبل** تفسير نتيجتها، واستعِد بـ`cp` لا بـ`git checkout`.

- [ ] **Step 10: ارفع حدَّ البوابة وكوّم**

اضبط الحدَّ بالعدّ الفعليّ (`grep -c '  test('`). الحدُّ الحاليّ ٢٩٣٢.

```bash
git add lib/ test/unit/employee_hours_validation_test.dart scripts/gate.sh
git commit -m "fix(hr): تسجيلُ الإضافي كان معطَّلاً صامتاً · وحقلُ ساعات العمل موصَّلٌ للواجهة"
```

---

## Task 7: شاشةُ تعريف العطلات

**Files:**
- Create: `lib/presentation/screens/settings/work_holidays_screen.dart`
- Modify: `lib/domain/repositories/hr_repository_interface.dart` · `lib/data/repositories/hr_repository_impl.dart`
- Test: `test/widget/work_holidays_screen_test.dart` (create)

**Interfaces:**
- Consumes: `holidaysInMonth` · جدولُ `WorkHolidays`
- Produces: `IHRRepository.getWorkHolidays({required Set<int>? allowedBranchIds})` · `addWorkHoliday(WorkHolidaysCompanion)` · `deleteWorkHoliday(int id)`

- [ ] **Step 1: اكتب اختبار الودجت الفاشل**

```dart
// test/widget/work_holidays_screen_test.dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/settings/work_holidays_screen.dart';

import '_support/screen_smoke.dart';

void main() {
  testWidgets('الشاشةُ تُرسَم بلا استثناءٍ ولا فيضان',
      timeout: const Timeout(Duration(seconds: 45)), (tester) async {
    final error =
        await pumpScreen(tester, () => const WorkHolidaysScreen());
    expect(error, isNull);
  });
}
```

⚠️ `pumpScreen` في `test/widget/_support/screen_smoke.dart` — اقرأ رأسَ الملف: يفكّك الشجرةَ ويدفع إطاراً **ولا يُغلق القاعدة**، وإلا علّق الاختبارُ ٤٥ ثانية.

- [ ] **Step 2: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/widget/work_holidays_screen_test.dart --concurrency=1
```
المتوقَّع: FAIL بـ`Undefined name 'WorkHolidaysScreen'`.

- [ ] **Step 3: نفّذ الشاشة والمستودع**

في `lib/domain/repositories/hr_repository_interface.dart`:

```dart
  /// عطلاتُ العمل — محصورةٌ بفروع المستخدم.
  Future<List<WorkHoliday>> getWorkHolidays({
    required Set<int>? allowedBranchIds,
  });
  Future<int> addWorkHoliday(WorkHolidaysCompanion holiday);
  Future<void> deleteWorkHoliday(int id);
```

وفي `lib/data/repositories/hr_repository_impl.dart` نفّذها بالتفويض إلى `_db`. والشاشةُ قائمةٌ بسيطة: صفٌّ لكلّ عطلةٍ باسمها وشكلها (يومٌ أسبوعيّ أو تاريخ) وفرعِها، وزرُّ إضافةٍ يفتح حواراً فيه اختيارُ الشكل، وزرُّ حذف. تتبع نمطَ شاشات الإعدادات القائمة.

⚠️ الحصرُ إلزاميّ: `allowedBranchIds` **مطلوب** في التوقيع — فالنسيانُ خطأُ ترجمة.

- [ ] **Step 4: شغّل وتأكّد أنه يمرّ**

```bash
rm -rf build/native_assets && flutter test test/widget/work_holidays_screen_test.dart --concurrency=1
```
المتوقَّع: PASS.

- [ ] **Step 5: ارفع حدَّ سويّة الواجهات وكوّم**

```bash
git add lib/presentation/screens/settings/work_holidays_screen.dart lib/domain/ lib/data/repositories/ test/widget/work_holidays_screen_test.dart scripts/gate.sh
git commit -m "feat(hr): شاشةُ تعريف عطلات العمل لكل فرع"
```

---

## Task 8: (مدموجةٌ في المهمة ٦أ — لا تُنفَّذ)

🔴 كانت تضيف حقلَ `hoursPerDay` «مطلوباً لـ`hourly` وحدَه»، وهذا **لا يغلق الثغرة** التي كشفتها مراجعةُ المهمة ٦: الحقلُ مطلوبٌ عملياً لكلّ من يُسجَّل له إضافي. دُمجت في المهمة ٦أ التي تسبق المهمة ٧.

<details><summary>النصُّ الأصليّ (للسجل)</summary>

**Files:**
- Modify: شاشةُ إضافة/تعديل الموظف (‏ابحث عن مستدعي `addEmployee` تحت `lib/presentation/screens/hr/`)
- Modify: `lib/data/database/extensions/hr_extensions.dart` (‏`addEmployee` / `updateEmployee`)
- Test: `test/unit/employee_hours_validation_test.dart` (create)

**Interfaces:**
- Consumes: عمودُ `hoursPerDay` من المهمة ٢
- Produces: رفضُ حفظِ موظف `hourly` بلا `hoursPerDay` صالح

- [ ] **Step 1: اكتب الاختبار الفاشل**

```dart
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
      reason: 'التجهيزةُ الناقصة تُمنع عند الإدخال لا تُكتشف في الراتب',
    );
  });

  test('hourly بساعاتٍ صالحةٍ يُقبَل', () async {
    final id = await db.addEmployee(
        name: 'ع', salary: 5200, salaryType: 'hourly', hoursPerDay: 8);
    expect(id, greaterThan(0));
  });

  test('الشهريُّ بلا ساعاتٍ يُقبَل', () async {
    final id = await db.addEmployee(name: 'ش', salary: 5200);
    expect(id, greaterThan(0));
  });

  test('ساعاتٌ صفرٌ أو سالبةٌ تُرفَض', () async {
    expect(
      () => db.addEmployee(
          name: 'ع', salary: 1, salaryType: 'hourly', hoursPerDay: 0),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنه يفشل**

```bash
rm -rf build/native_assets && flutter test test/unit/employee_hours_validation_test.dart --concurrency=1
```
المتوقَّع: FAIL — لا معاملَ `hoursPerDay` في `addEmployee`.

- [ ] **Step 3: نفّذ**

أضف `double? hoursPerDay` إلى `addEmployee` و`updateEmployee`، ومرّرْه في الـCompanion، وفي أوّلهما:

```dart
    // ساعاتُ اليوم مقامُ أجر الساعة — وموظفٌ `hourly` بدونها تجهيزةٌ ناقصة
    // تنفجر عند حساب الراتب. المنعُ عند الإدخال أرخص وأوضح.
    if (salaryType == kHourlySalaryType &&
        (hoursPerDay == null || hoursPerDay <= 0)) {
      throw ArgumentError('ساعاتُ العمل اليومية مطلوبةٌ لموظفٍ بأجر الساعة');
    }
```

وفي شاشة الموظف أضف حقلَ إدخالٍ رقميّاً يظهر دائماً ويُلزَم عند اختيار `hourly`.

- [ ] **Step 4: شغّل وتأكّد أنه يمرّ**

```bash
rm -rf build/native_assets && flutter test test/unit/employee_hours_validation_test.dart test/unit/manage_employee_usecase_test.dart --concurrency=1
```
المتوقَّع: PASS — بما فيها اختباراتُ الموظف القائمة.

- [ ] **Step 5: ارفع حدَّ البوابة وكوّم**

```bash
git add lib/ test/unit/employee_hours_validation_test.dart scripts/gate.sh
git commit -m "feat(hr): حقلُ ساعات العمل اليومية وإلزامُه لموظف الساعة"
```

---

## Task 9: البوابة الكاملة وملاحظاتُ الإصدار

**Files:**
- Modify: `scripts/gate.sh` (‏ضبطُ الحدود النهائية)
- Modify: `docs/` — ملاحظاتُ الإصدار

- [ ] **Step 1: شغّل البوابة كاملةً**

```bash
rm -rf build/native_assets && bash scripts/gate.sh --pg > /tmp/gate.log 2>&1; RC=$?; echo "GATE_EXIT=$RC"
```
⚠️ شغّلها في الخلفية — تأخذ ~١٥ دقيقة وسقفُ أداة الصدفة ١٠. والحكمُ من `GATE_EXIT` ونصّ `✓ البوابة كلها خضراء` معاً، لا من حالة الإشعار.

- [ ] **Step 2: صحّح الحدود الدنيا بالمقيس**

اقرأ الأعداد الفعلية من السجلّ واضبط أرقامَ `run_suite` عليها.

- [ ] **Step 3: اكتب ملاحظات الإصدار**

يجب أن تذكر صراحةً:
1. **موديلُ الشهري تغيّر**: يومُ العطلة المعرَّفة لا يُعدّ غياباً.
2. **أجرُ الساعة الإضافية ارتفع** بنحو ١٥٪ في الشهور ذاتِ أربع عطلات — المقامُ صار أيامَ العمل لا أيامَ التقويم.
3. **السجلّاتُ القائمة للإضافي لم تتغيّر** — عُلّمت يدويةً بالهجرة.
4. **موظفو `hourly`** يحتاجون إدخالَ ساعاتِ العمل اليومية قبل أوّل حساب راتب.

- [ ] **Step 4: كوّم**

```bash
git add scripts/gate.sh docs/
git commit -m "chore(hr): خطُّ الأساس بعد الأجر بالساعة · وملاحظاتُ الإصدار"
```

---

## Self-Review

**تغطيةُ المواصفة:** §٣ النواة ← المهمة ٤ · §٣ الحالاتُ الحدّية ← المهمة ٤ خطوة ١ · §٤ التقويم ← المهام ٢·٣·٧ · §٤ أثرُ الشهري ← المهمة ٥ · §٥ الإضافي ← المهمة ٦ · §٥ الهجرة ← المهمة ٢ · §٥ موظفٌ بلا `hoursPerDay` ← المهمة ٦ · §٧ الاختبار ← كلُّ مهمة · §٧ الطفرات ← المهام ٣·٤·٥·٦.

**فجوةٌ سُدّت:** المواصفةُ تلزم بإدخال `hoursPerDay` لـ`hourly` ولم تكن هناك مهمةٌ تفرضه — أُضيفت المهمة ٨.

**اتّساقُ الأسماء:** `hourlyRateFor` · `workingDaysInMonth` · `holidaysInMonth` · `isManualAmount` · `hoursPerDay` · `kHourlySalaryType` — مستعملةٌ بنفس التهجئة في كلّ المهام.
