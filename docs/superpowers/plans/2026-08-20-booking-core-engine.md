# خطّةُ تنفيذ محرِّك الحجز الأساسيّ

> **للعاملين الوكلاء:** مهارةٌ فرعيّةٌ مطلوبة — استعمل
> `superpowers:subagent-driven-development` (مُرجَّح) أو
> `superpowers:executing-plans` لتنفيذ هذه الخطّة مهمّةً مهمّة. الخطواتُ
> بصيغة صناديق التأشير (`- [ ]`) للتتبّع.

**الهدف:** محرِّكُ حجزِ مواعيدِ خدمةٍ مستقلٌّ عن الطاولات — جداولُه وقواعدُه
وصلاحياتُه وسجلُّه — بلا أيّ شاشة.

**المعماريّة:** ثلاثةُ جداولَ جديدةٍ في drift (`BookingResources` ·
`BookingServices` · `Bookings`)، ومنعُ التعارض مُنفَّذٌ في الـDAO داخل معاملةٍ
لأنّ SQLite لا يملك قيدَ استبعاد، وحسابُ التداخل دالّةٌ خالصةٌ في
`domain/models` تُختبَر بلا قاعدة. لا شاشةَ في هذا المشروع.

**التقنيات:** Dart · Flutter · drift (codegen) · Riverpod · flutter_test.

**المواصفة المرجعيّة:**
[`2026-08-20-booking-core-engine-design.md`](../specs/2026-08-20-booking-core-engine-design.md)

---

## قيودٌ عامّة — تسري على كلّ مهمّةٍ بلا استثناء

- **ممنوع `dart format`.** المستودع غير مضبوطٍ عليه؛ تشغيلُه حوّل تعديلاً من
  ١٥٥ سطراً إلى ٤٢٠ في ملفٍّ مشترَك.
- **ممنوع تحرير `lib/data/database/database.g.dart` يدوياً.** يُولَّد فقط.
- **`build_runner` يُشغَّل من الجلسة الرئيسيّة لا من وكيلٍ فرعيّ**، ويستغرق
  **~٥٩ دقيقة** منها ~٤٠ تحليلٌ صامتٌ بلا نموٍّ في الكاش — **لا تقتله**.
- **ممنوع `git checkout` للتراجع.** استعِد بـ`git show HEAD:<path> > <path>`.
- **ممنوع `perl -i`/`sed -i` على نصٍّ عربيٍّ** بلا `-CSD`؛ يرمّز الملفَّ
  مزدوجاً ويخرج بصفر. وملفّاتُ `lib/` بنهايات **CRLF** و`grep -c $'\r'` يكذب
  فيها — استعمل أدوات التحرير لا التدفّق.
- **`AppDatabase.forTesting()` يُنفِذ المفاتيح الأجنبيّة** — ازرع الأبَ قبل
  الابن وإلّا فشل الإدراج.
- **قبل أيّ قياس:** عمليّةُ flutter واحدة · `build/native_assets/windows/sqlite3.dll`
  موجود · شجرةٌ ساكنة. والتقط المخرَج كاملاً — `| tail` يخفي كودَ الخروج،
  فاستعمل `${PIPESTATUS[0]}`.
- **أكوادُ الصلاحيات تُضاف في آخر القوائم** — `permission_codes.dart` مشترَكٌ
  مع UralCash ويُنقل بـpatch.
- كلُّ مهمّةٍ تنتهي بكوميت.

---

## بنيةُ الملفّات

| الملفّ | مسؤوليّته |
|---|---|
| `lib/data/database/tables/booking_tables.dart` | **يُنشأ** — تعريفُ الجداول الثلاثة |
| `lib/data/database/database.dart` | **يُعدَّل** — `part` + تسجيلُ الجداول + `schemaVersion` |
| `lib/data/database/migrations/epoch_3.dart` | **يُعدَّل** — كتلةُ الترقية |
| `lib/domain/models/booking_overlap.dart` | **يُنشأ** — حسابُ التداخل الخالص |
| `lib/data/database/daos/bookings_dao.dart` | **يُنشأ** — القراءةُ والكتابةُ وإنفاذُ القواعد |
| `lib/services/booking_service.dart` | **يُنشأ** — التسجيلُ في سجلّ العمليات |
| `lib/core/permissions/permission_codes.dart` | **يُعدَّل** — أحدَ عشرَ كوداً |
| `lib/presentation/screens/role_management/data/permission_categories.dart` | **يُعدَّل** — تصنيفُ `bookings` |
| `lib/presentation/screens/activity_log_screen.dart` | **يُعدَّل** — تصنيفُ السجلّ |
| `lib/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart` | **يُعدَّل** — التوأم |
| `lib/core/config/feature_dependency_graph.dart` | **يُعدَّل** — حذفُ التبعيّة |
| `lib/core/config/feature_policy.dart` | **يُعدَّل** — `litePicpos` |

---

## Task 1 — المهمّة ١: حسابُ التداخل الخالص

تسبق الجداولَ عمداً: لا تحتاج `build_runner` فتُنجَز في دقائق، ومخرَجُها
تستهلكه المهمّةُ ٣.

**الملفّات:**
- إنشاء: `lib/domain/models/booking_overlap.dart`
- اختبار: `test/unit/booking_overlap_test.dart`

**الواجهات:**
- يُنتج: `class BookingSlot({required DateTime startsAt, required DateTime endsAt})` ·
  `bool bookingSlotsOverlap(BookingSlot a, BookingSlot b)` ·
  `DateTime computeBookingEndsAt(DateTime startsAt, int durationMinutes, int bufferMinutes)`

- [ ] **الخطوة ١: اكتب الاختبارَ الفاشل**

```dart
// test/unit/booking_overlap_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/booking_overlap.dart';

BookingSlot slot(int startHour, int endHour) => BookingSlot(
      startsAt: DateTime(2026, 8, 20, startHour),
      endsAt: DateTime(2026, 8, 20, endHour),
    );

void main() {
  group('bookingSlotsOverlap', () {
    test('التلاصقُ ليس تداخلاً — المدى نصفُ مفتوح [start, end)', () {
      expect(bookingSlotsOverlap(slot(10, 11), slot(11, 12)), isFalse);
      expect(bookingSlotsOverlap(slot(11, 12), slot(10, 11)), isFalse);
    });

    test('تداخلٌ جزئيّ', () {
      expect(bookingSlotsOverlap(slot(10, 12), slot(11, 13)), isTrue);
      expect(bookingSlotsOverlap(slot(11, 13), slot(10, 12)), isTrue);
    });

    test('احتواءٌ كامل', () {
      expect(bookingSlotsOverlap(slot(10, 14), slot(11, 12)), isTrue);
      expect(bookingSlotsOverlap(slot(11, 12), slot(10, 14)), isTrue);
    });

    test('انفصالٌ تامّ', () {
      expect(bookingSlotsOverlap(slot(10, 11), slot(13, 14)), isFalse);
    });

    test('تطابقٌ تامّ', () {
      expect(bookingSlotsOverlap(slot(10, 11), slot(10, 11)), isTrue);
    });
  });

  group('computeBookingEndsAt', () {
    test('المدّةُ وحدَها بلا فترةِ تنظيف', () {
      expect(
        computeBookingEndsAt(DateTime(2026, 8, 20, 10), 45, 0),
        DateTime(2026, 8, 20, 10, 45),
      );
    });

    test('فترةُ التنظيف تُضاف إلى النهاية فتدخل المقارنة', () {
      expect(
        computeBookingEndsAt(DateTime(2026, 8, 20, 10), 45, 15),
        DateTime(2026, 8, 20, 11),
      );
    });
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
flutter test test/unit/booking_overlap_test.dart
```

المتوقَّع: فشلُ **ترجمة** — `Target of URI doesn't exist: '.../booking_overlap.dart'`.

- [ ] **الخطوة ٣: اكتب أقلَّ تنفيذٍ يُنجحه**

```dart
// lib/domain/models/booking_overlap.dart
//
// حسابُ تداخلِ المواعيد — خالصٌ بلا قاعدةِ بيانات.
//
// موضعُه `domain/models` لأنّ حارسَ المستودع يفرض أن تعيش الحساباتُ الخالصة
// هناك، ولأنّ اختبارَه حينئذٍ لا يحتاج `AppDatabase` ولا مؤقّتات drift.

/// مدًى زمنيٌّ نصفُ مفتوح: `[startsAt, endsAt)`.
class BookingSlot {
  final DateTime startsAt;
  final DateTime endsAt;

  const BookingSlot({required this.startsAt, required this.endsAt});
}

/// هل يتداخل المدَيان؟
///
/// نصفُ مفتوحٍ عمداً: موعدٌ ينتهي 11:00 وآخرُ يبدأ 11:00 **لا يتعارضان** —
/// وإلّا استحال رصفُ المواعيد بلا فجوات.
bool bookingSlotsOverlap(BookingSlot a, BookingSlot b) =>
    a.startsAt.isBefore(b.endsAt) && b.startsAt.isBefore(a.endsAt);

/// نهايةُ الموعد = البداية + المدّة + فترةِ التنظيف.
///
/// فترةُ التنظيف تدخل **النهايةَ المخزَّنة** لا المقارنةَ وحدَها، فيسري
/// أثرُها على كلّ استعلامٍ بلا أن يتذكّرها أحد.
DateTime computeBookingEndsAt(
  DateTime startsAt,
  int durationMinutes,
  int bufferMinutes,
) =>
    startsAt.add(Duration(minutes: durationMinutes + bufferMinutes));
```

- [ ] **الخطوة ٤: شغّله وتأكّد أنه ينجح**

```bash
flutter test test/unit/booking_overlap_test.dart
```

المتوقَّع: `+7: All tests passed!`

- [ ] **الخطوة ٥: كوميت**

```bash
git add lib/domain/models/booking_overlap.dart test/unit/booking_overlap_test.dart
git commit -m "feat(bookings): حسابُ تداخل المواعيد — دالّةٌ خالصةٌ ومداها نصفُ مفتوح"
```

---

## Task 2 — المهمّة ٢: الجداولُ الثلاثةُ والهجرة

**أغلى مهمّةٍ في الخطّة** — تستدعي `build_runner` مرّةً واحدةً لكلّ الجداول.
لا تُجزّئها وإلّا تكرّرت التكلفة.

**الملفّات:**
- إنشاء: `lib/data/database/tables/booking_tables.dart`
- تعديل: `lib/data/database/database.dart` (‏`part` · قائمة `tables` · `schemaVersion`)
- تعديل: `lib/data/database/migrations/epoch_3.dart` (آخرُ كتلة)

**الواجهات:**
- يُنتج: جداولُ drift `BookingResources` · `BookingServices` · `Bookings`،
  ومعها الأصنافُ المولَّدة `BookingResource` · `BookingService` · `Booking`
  و`BookingsCompanion` وحقولُ `AppDatabase`: `bookingResources` ·
  `bookingServices` · `bookings`.

- [ ] **الخطوة ١: اقرأ رقمَ المخطَّط الحاليَّ بنفسك — لا تثق برقمٍ مكتوب**

```bash
grep -n "schemaVersion =>" lib/data/database/database.dart
```

كان **١٥٨** وقتَ كتابة الخطّة، وفرعُ `claude/pos-flexible-permissions-45bd2b`
يحمل **١٥٩** ولم يُدمج. فالرقمُ الجديدُ = المقروءُ + ١. **اكتب ما قرأتَه لا ما
تتوقّعه.** سمِّه فيما يلي `vNEW`.

- [ ] **الخطوة ٢: أنشئ ملفَّ الجداول**

```dart
// lib/data/database/tables/booking_tables.dart
part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BOOKINGS — مواعيدُ الخدمة
//
// مستقلّةٌ تماماً عن `TableReservations`: تلك تحجز **مكاناً** (طاولةً بعينها)
// وهذه تحجز **وقتَ إنسان**. لا تُدمَجا ولا تتشاركا حالاتٍ.
// ═══════════════════════════════════════════════════════════════════════════

/// «الموظفون / الموارد» — مَن (أو ما) يُحجَز وقتُه.
///
/// **التسمية:** ظاهرُه للمستخدم «الموظفون / الموارد» دائماً، لا «مورد» —
/// فتلك تلتبس بالمورِّد الذي يرسل البضاعة (`Parties.isSupplier`). والاسمُ
/// الإنجليزيُّ يشمل ما ليس إنساناً: كرسيٌّ · غرفةٌ · جهازُ ليزر.
class BookingResources extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get colorHex => text().withDefault(const Constant('#3B82F6'))();
  TextColumn get phone => text().nullable()();

  /// ربطٌ **اختياريّ** بموظَّفِ الموارد البشريّة.
  ///
  /// معدومٌ عمداً: `restaurant` و`cafe` — ملفَّا PicPos الجوهريّان — يفتحان
  /// الحجوزاتِ و`hrEnabled` مطفأةٌ عندهما. وdrift يُنشئ جدولَ `Employees`
  /// مهما كان العلَم (العلَمُ يحجب الواجهةَ لا الجدول) فالمفتاحُ غيرُ ضارّ.
  /// فمَن أطفأ الموارد البشريّة يتركه فارغاً ويعمل، ومَن فعّلها يربط.
  IntColumn get employeeId =>
      integer().nullable().references(Employees, #id)();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get branchId =>
      integer().nullable().references(Branches, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// الخدمةُ المعروضة للحجز.
///
/// جدولٌ خاصٌّ لا أعمدةٌ على `Products`: ذاك مشترَكٌ مع UralCash ويحمل ٤٨
/// عموداً، ومفهوما «المدّة» و«فترة التنظيف» لا يعنيانه في شيء.
class BookingServices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 150)();

  /// مدّةُ الخدمة — **شرطُ منعِ التعارض**، ولا وجودَ لها في `Products`.
  IntColumn get durationMinutes => integer().withDefault(const Constant(30))();

  /// فترةُ تنظيفٍ تُضاف بعد الموعد فلا يُحجَز عليها.
  IntColumn get bufferMinutes => integer().withDefault(const Constant(0))();

  RealColumn get price => real().withDefault(const Constant(0))();
  TextColumn get colorHex => text().withDefault(const Constant('#10B981'))();

  /// ربطٌ **اختياريّ** بصنفٍ من نوع `service`.
  ///
  /// هو ما يجعل تحويلَ الحجز إلى فاتورة (مشروع ٣) حقيقيّاً دون اختراعِ صنفٍ
  /// لحظتَها.
  IntColumn get productId =>
      integer().nullable().references(Products, #id)();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get branchId =>
      integer().nullable().references(Branches, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// الموعد.
class Bookings extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ملفُّ العميل — معدومٌ عمداً.
  IntColumn get partyId => integer().nullable().references(Parties, #id)();

  /// الاسمُ نصّاً **إلى جانب** `partyId`: أكثرُ الحجوزات تُؤخذ بالهاتف
  /// لعابرٍ لا ملفَّ له، وفرضُ إنشاءِ عميلٍ لكلّ مكالمةٍ يُفسد الاستعمال.
  TextColumn get customerName => text().withLength(max: 150)();
  TextColumn get customerPhone => text().nullable()();

  IntColumn get serviceId => integer().references(BookingServices, #id)();

  /// معدومٌ = «قائمة الانتظار»: حجزٌ لم يُسنَد لأحدٍ بعد. وهو **لا يشارك في
  /// فحص التعارض** إذ لا أحدَ يتعارض عليه.
  IntColumn get resourceId =>
      integer().nullable().references(BookingResources, #id)();

  DateTimeColumn get startsAt => dateTime()();

  /// **يُخزَّن ولا يُحسَب.**
  ///
  /// حسابُه من `service.durationMinutes` وقتَ الاستعلام يعني أنّ تعديلَ
  /// مدّةِ الخدمة الشهرَ القادم يغيّر طولَ حجوزٍ ماضيةٍ بأثرٍ رجعيّ ويُنشئ
  /// تعارضاتٍ لم تكن.
  DateTimeColumn get endsAt => dateTime()();

  /// `pending` · `confirmed` · `in_service` · `completed` · `cancelled` ·
  /// `no_show`. مستقلّةٌ عن مفردات `TableReservations`.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  RealColumn get depositAmount => real().withDefault(const Constant(0))();

  /// `held` · `refunded` · `forfeited`.
  ///
  /// ثلاثُ قيمٍ لا أربع: **التأجيلُ لا يحتاج قيمةً رابعة** لأنه نقلٌ للصفّ
  /// نفسِه لا إلغاءٌ وإنشاء، فيبقى العربونُ `held` وقد تبدّل الوقتُ فحسب.
  /// وحركةُ المال وترحيلُها في مشروع ٣ — هذا العمودُ بنيةٌ تحفظ نتيجتَها.
  TextColumn get depositStatus => text().withDefault(const Constant('held'))();

  TextColumn get notes => text().nullable()();
  IntColumn get branchId =>
      integer().nullable().references(Branches, #id)();
  IntColumn get invoiceId =>
      integer().nullable().references(SalesInvoices, #id)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  TextColumn get cancelReason => text().nullable()();
}
```

- [ ] **الخطوة ٣: سجّل الملفَّ والجداولَ وارفع رقمَ المخطَّط**

ثلاثةُ تعديلاتٍ في `lib/data/database/database.dart`:

١. بعد `part 'tables/report_builder_tables.dart';` أضف:

```dart
part 'tables/booking_tables.dart';
```

٢. داخل `@DriftDatabase(tables: [...])` بعد
`TableOrderPayments, // v154: دفعةٌ لكلّ دافعٍ على طلب الطاولة` أضف:

```dart
    BookingResources, // vNEW: «الموظفون / الموارد» — مَن يُحجَز وقتُه
    BookingServices, // vNEW: الخدماتُ المعروضة للحجز
    Bookings, // vNEW: مواعيدُ الخدمة — مستقلّةٌ عن TableReservations
```

٣. ارفع الرقمَ إلى ما قرأتَه في الخطوة ١ زائدَ واحد:

```dart
  int get schemaVersion => vNEW;
```

- [ ] **الخطوة ٤: أضف كتلةَ الترقية**

في آخر `lib/data/database/migrations/epoch_3.dart`، بعد كتلة
`v158 table_order_payments reserve-then-commit` وقبل إغلاق الأقواس:

```dart
      await _safeMigrate('vNEW booking engine tables', () async {
        // جداولُ جديدةٌ خالصةٌ — لا `alterTable`، فلا خطرَ إعادةِ بناءِ
        // جدولٍ قائمٍ ولا إسقاطَ خطوةٍ أقدمَ تُعيد بناءَ نفس الجدول.
        await m.createTable(bookingResources);
        await m.createTable(bookingServices);
        await m.createTable(bookings);
        debugPrint('[Migration] vNEW booking engine tables OK');
      });
```

⚠️ **عُدَّ الكتلَ بأسمائها قبل وبعد التعديل** (‏`grep -c "_safeMigrate"`)
وتأكّد أنّ العددَ زاد واحداً بالضبط ولم تُحذف كتلةٌ.

- [ ] **الخطوة ٥: شغّل `build_runner` — من الجلسة الرئيسيّة**

```bash
dart run build_runner build --delete-conflicting-outputs
```

**~٥٩ دقيقة**، منها ~٤٠ تحليلٌ صامتٌ بلا نموٍّ في الكاش. **لا تقتله.**

- [ ] **الخطوة ٦: تأكّد أنّ التوليد اكتمل ولم ينقص صامتاً**

```bash
grep -c "class Booking\b\|class BookingResource\b\|class BookingService\b" lib/data/database/database.g.dart
flutter analyze lib/data/database/ 2>&1 | tail -5
```

المتوقَّع: العدد **٣** على الأقل، و`No issues found!`.
إن نقص شيءٌ **لا تُحرّر `database.g.dart` يدوياً** — أعِد التشغيل.

- [ ] **الخطوة ٧: كوميت**

```bash
git add lib/data/database/
git commit -m "feat(bookings): ثلاثةُ جداولَ للحجز — والموظَّفُ مفتاحٌ معدومٌ لا تبعيّةٌ قسريّة"
```

---

## Task 3 — المهمّة ٣: الـDAO — القراءةُ والكتابةُ وإنفاذُ القاعدتين

**الملفّات:**
- إنشاء: `lib/data/database/daos/bookings_dao.dart`
- تعديل: `lib/data/database/database.dart` (سطرُ `part` واحد)
- اختبار: `test/unit/bookings_dao_test.dart`

**الواجهات:**
- يستهلك: `bookingSlotsOverlap` و`computeBookingEndsAt` (المهمّة ١)،
  وجداولَ المهمّة ٢.
- يُنتج: `class BookingConflictException implements Exception` ·
  `class BookingInPastException implements Exception` ·
  `Future<int> createBooking({required String customerName, String? customerPhone, int? partyId, required int serviceId, int? resourceId, required DateTime startsAt, double depositAmount, String? notes, int? branchId, int? createdBy, DateTime? now})` ·
  `Future<List<Booking>> getBookingsInRange(DateTime from, DateTime to, {List<int>? allowedBranchIds})` ·
  `Future<List<Booking>> getOverlappingBookings(int resourceId, DateTime startsAt, DateTime endsAt, {int? excludeBookingId})`

- [ ] **الخطوة ١: اكتب الاختبارَ الفاشل**

```dart
// test/unit/bookings_dao_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int resourceId;

  // «الآن» ثابتٌ يُمرَّر صراحةً: قاعدةُ «لا حجزَ في الماضي» تقارن به،
  // ولو قرأ الكودُ ساعةَ النظام لصار الاختبارُ رهينةَ وقتِ التشغيل.
  final now = DateTime(2026, 8, 20, 9);

  setUp(() async {
    db = AppDatabase.forTesting();
    // المفاتيحُ الأجنبيّة مُنفَذة في `forTesting` — يُزرع الأبُ قبل الابن.
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'قص شعر',
            durationMinutes: const Value(45),
            bufferMinutes: const Value(15),
          ),
        );
    resourceId = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(name: 'محمد علي'),
        );
  });

  tearDown(() async {
    // لا `db.close()`: يعلّق مؤقّتَ drift في المنطقة الوهميّة فيتجمّد
    // الاختبار. الحياةُ تنتهي بانتهاء العمليّة.
  });

  test('الإنشاءُ يحسب النهايةَ من المدّة وفترةِ التنظيف', () async {
    final id = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    final row = await (db.select(db.bookings)..where((b) => b.id.equals(id)))
        .getSingle();
    expect(row.endsAt, DateTime(2026, 8, 20, 11)); // 45 + 15
    expect(row.status, 'pending');
    expect(row.depositStatus, 'held');
  });

  test('حجزٌ متداخلٌ على نفس الموظَّف يُرفَض', () async {
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(
      () => db.createBooking(
        customerName: 'سارة',
        serviceId: serviceId,
        resourceId: resourceId,
        startsAt: DateTime(2026, 8, 20, 10, 30),
        now: now,
      ),
      throwsA(isA<BookingConflictException>()),
    );
  });

  test('التلاصقُ مسموح — النهايةُ تساوي البداية', () async {
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    final id = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 11), // بعد 45+15 تماماً
      now: now,
    );
    expect(id, greaterThan(0));
  });

  test('حجزٌ بلا موظَّفٍ لا يشارك في فحص التعارض', () async {
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    final id = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(id, greaterThan(0));
  });

  test('الملغى ومَن لم يحضر يُفرّغان الوقت', () async {
    final first = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await (db.update(db.bookings)..where((b) => b.id.equals(first)))
        .write(const BookingsCompanion(status: Value('cancelled')));
    final id = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(id, greaterThan(0));
  });

  test('لا حجزَ في الماضي', () async {
    expect(
      () => db.createBooking(
        customerName: 'أحمد',
        serviceId: serviceId,
        resourceId: resourceId,
        startsAt: DateTime(2026, 8, 20, 8), // قبل `now`
        now: now,
      ),
      throwsA(isA<BookingInPastException>()),
    );
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
flutter test test/unit/bookings_dao_test.dart 2>&1 | tail -20; echo "EXIT=${PIPESTATUS[0]}"
```

المتوقَّع: فشلُ ترجمة — `The method 'createBooking' isn't defined`.

- [ ] **الخطوة ٣: اكتب الـDAO**

```dart
// lib/data/database/daos/bookings_dao.dart
// ---------------------------------------------------------------------------
// BOOKINGS DAO — مواعيدُ الخدمة
// ---------------------------------------------------------------------------

part of '../database.dart';

/// الموظَّفُ مشغولٌ في ذلك المدى.
class BookingConflictException implements Exception {
  final String messageAr;
  BookingConflictException(this.messageAr);
  @override
  String toString() => messageAr;
}

/// الحجزُ حاضرٌ أو مستقبل — لا ماضٍ.
class BookingInPastException implements Exception {
  final String messageAr;
  BookingInPastException(this.messageAr);
  @override
  String toString() => messageAr;
}

extension BookingsDao on AppDatabase {
  /// الحجوزاتُ المتداخلةُ مع مدًى على موظَّفٍ بعينه.
  ///
  /// `excludeBookingId` لازمٌ للتعديل: الحجزُ لا يتعارض مع نفسِه.
  /// و`cancelled`/`no_show` مستثنيان لأنّهما يُفرّغان الوقت.
  /// **قرارُ التداخل يقع في `bookingSlotsOverlap` وحدَها — لا في SQL.**
  ///
  /// الاستعلامُ يضيّق المرشَّحين فقط (نفسُ الموظَّف · حالاتٌ حيّة · نافذةُ
  /// اليوم)، ثم تحكم الدالّةُ الخالصة. ولو كُتب شرطُ التداخل مرّتين — مرّةً
  /// في SQL ومرّةً في دارت — لتباعدا عند أوّل تعديل، ولصار الاختبارُ يشهد
  /// لمصدرٍ غيرِ الذي يعمل في الإنتاج. والمرشَّحون عشراتٌ على الأكثر
  /// (موظَّفٌ واحدٌ في يومٍ واحد) فالكلفةُ مهمَلة.
  Future<List<Booking>> getOverlappingBookings(
    int resourceId,
    DateTime startsAt,
    DateTime endsAt, {
    int? excludeBookingId,
  }) async {
    // نافذةُ المرشَّحين تُضيّق فقط ولا تقرّر — فيجب أن تحوي كلَّ صفٍّ قد
    // تحكم عليه الدالّةُ الخالصةُ بالتداخل، وإلّا صارت هي التي تقرّر.
    //
    // إلى الوراء يوماً كاملاً: حجزٌ يبدأ ٢٣:٥٠ وينتهي ٠٠:٥٠ يعبر منتصفَ
    // الليل، وبدايتُه قبل منتصف ليل اليوم المطلوب. (النسخةُ الأولى من هذه
    // الخطّة بدأت النافذةَ من منتصف الليل فأسقطته قبل أن تراه الدالّةُ
    // فمرّ تعارضٌ صامت — أمسكته المراجعة.) ويفترض ألّا يتجاوز موعدٌ
    // أربعاً وعشرين ساعة، وهو صحيحٌ لمواعيد الخدمة.
    //
    // وإلى الأمام حتى `endsAt` وحدَها: ما يبدأ عند نهاية المطلوب أو بعدها
    // لا يمكن أن يتداخل معه — المدى نصفُ مفتوح.
    final windowStart = startsAt.subtract(const Duration(days: 1));
    final windowEnd = endsAt;

    final query = select(bookings)
      ..where((b) => b.resourceId.equals(resourceId))
      ..where((b) => b.status.isNotIn(['cancelled', 'no_show']))
      ..where((b) => b.startsAt.isBiggerOrEqualValue(windowStart))
      ..where((b) => b.startsAt.isSmallerThanValue(windowEnd));
    if (excludeBookingId != null) {
      query.where((b) => b.id.equals(excludeBookingId).not());
    }

    final candidates = await query.get();
    final target = BookingSlot(startsAt: startsAt, endsAt: endsAt);
    return candidates
        .where((b) => bookingSlotsOverlap(
              target,
              BookingSlot(startsAt: b.startsAt, endsAt: b.endsAt),
            ))
        .toList();
  }

  /// حجوزاتُ مدًى زمنيّ — ونطاقُ الفرع يُحقَن **في الاستعلام** لا في العرض.
  Future<List<Booking>> getBookingsInRange(
    DateTime from,
    DateTime to, {
    List<int>? allowedBranchIds,
  }) {
    final query = select(bookings)
      ..where((b) => b.startsAt.isBiggerOrEqualValue(from))
      ..where((b) => b.startsAt.isSmallerThanValue(to))
      ..orderBy([(b) => OrderingTerm.asc(b.startsAt)]);
    if (allowedBranchIds != null) {
      query.where(
        (b) => b.branchId.isIn(allowedBranchIds) | b.branchId.isNull(),
      );
    }
    return query.get();
  }

  /// ينشئ حجزاً بعد إنفاذ القاعدتين داخل معاملةٍ واحدة.
  ///
  /// SQLite لا يملك قيدَ استبعاد (`EXCLUDE`) كما PostgreSQL، فالإنفاذُ هنا
  /// لا في ودجت — وإلّا مرّ من أيّ مسارٍ آخرَ يكتب حجزاً.
  ///
  /// `now` يُمرَّر صراحةً كي يبقى الاختبارُ حتميّاً.
  Future<int> createBooking({
    required String customerName,
    String? customerPhone,
    int? partyId,
    required int serviceId,
    int? resourceId,
    required DateTime startsAt,
    double depositAmount = 0,
    String? notes,
    int? branchId,
    int? createdBy,
    DateTime? now,
  }) {
    return transaction(() async {
      final currentTime = now ?? DateTime.now();
      if (startsAt.isBefore(currentTime)) {
        throw BookingInPastException(
          'لا يمكن الحجز في الماضي — الحجزُ حاضرٌ أو مستقبل',
        );
      }

      final service = await (select(bookingServices)
            ..where((s) => s.id.equals(serviceId)))
          .getSingle();
      final endsAt = computeBookingEndsAt(
        startsAt,
        service.durationMinutes,
        service.bufferMinutes,
      );

      // حجزٌ بلا موظَّفٍ لا يشارك في الفحص — لا أحدَ يتعارض عليه.
      if (resourceId != null) {
        final clashes =
            await getOverlappingBookings(resourceId, startsAt, endsAt);
        if (clashes.isNotEmpty) {
          throw BookingConflictException(
            'الموظَّفُ مشغولٌ في هذا الوقت — ${clashes.length} حجزٌ متعارض',
          );
        }
      }

      return into(bookings).insert(
        BookingsCompanion.insert(
          customerName: customerName,
          customerPhone: Value(customerPhone),
          partyId: Value(partyId),
          serviceId: serviceId,
          resourceId: Value(resourceId),
          startsAt: startsAt,
          endsAt: endsAt,
          depositAmount: Value(depositAmount),
          notes: Value(notes),
          branchId: Value(branchId),
          createdBy: Value(createdBy),
        ),
      );
    });
  }
}
```

ثم **تعديلان** في `lib/data/database/database.dart` — ملفُّ الـDAO هو
`part of` فلا يملك استيراداتِه، وهي تعيش في المكتبة الأمّ:

١. بعد `import '../../domain/models/tables_report_row.dart';` أضف:

```dart
import '../../domain/models/booking_overlap.dart';
```

(سابقةٌ مستقرّة: `safe_running_balance` و`table_order_totals` و
`tables_report_row` كلُّها تُستورَد هكذا.)

٢. بعد `part 'daos/tables_dao.dart';` أضف:

```dart
part 'daos/bookings_dao.dart';
```

- [ ] **الخطوة ٤: شغّل الاختبارات**

```bash
flutter test test/unit/bookings_dao_test.dart 2>&1 | tail -20; echo "EXIT=${PIPESTATUS[0]}"
```

المتوقَّع: `+6: All tests passed!` وخروجٌ 0.

- [ ] **الخطوة ٥: كوميت**

```bash
git add lib/data/database/ test/unit/bookings_dao_test.dart
git commit -m "feat(bookings): DAO الحجز — منعُ التعارض ومنعُ الماضي في معاملةٍ واحدة"
```

---

## Task 4 — المهمّة ٤: الإسنادُ وإعادةُ الجدولة — والقاعدةُ بالثلاثيّة

**الملفّات:**
- تعديل: `lib/data/database/daos/bookings_dao.dart`
- اختبار: `test/unit/bookings_reschedule_test.dart`

**الواجهات:**
- يستهلك: `getOverlappingBookings` · `BookingConflictException` ·
  `BookingInPastException` (المهمّة ٣).
- يُنتج: `Future<void> updateBookingSlot(int bookingId, {int? resourceId, bool clearResource = false, DateTime? startsAt, DateTime? now})`

- [ ] **الخطوة ١: اكتب الاختبارَ الفاشل**

```dart
// test/unit/bookings_reschedule_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int resourceA;
  late int resourceB;
  final now = DateTime(2026, 8, 20, 9);

  setUp(() async {
    db = AppDatabase.forTesting();
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'مساج',
            durationMinutes: const Value(60),
          ),
        );
    resourceA = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(name: 'محمد'),
        );
    resourceB = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(name: 'ريم'),
        );
  });

  test('إسنادُ حجزٍ من قائمة الانتظار يفحص التعارض', () async {
    // حجزٌ قائمٌ على «محمد» 10:00-11:00
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    // حجزٌ بلا موظَّفٍ في نفس الوقت — وُلد بلا تعارضٍ لأنه بلا موظَّف
    final waiting = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    // إسنادُه إلى «محمد» يجب أن يُرفض — وهذا هو الموضعُ الذي يتسرّب منه
    // التعارضُ لو اكتُفي بالفحص عند الإنشاء.
    expect(
      () => db.updateBookingSlot(waiting, resourceId: resourceA, now: now),
      throwsA(isA<BookingConflictException>()),
    );
  });

  test('إسنادُه إلى موظَّفٍ فارغٍ ينجح', () async {
    final waiting = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.updateBookingSlot(waiting, resourceId: resourceB, now: now);
    final row = await (db.select(db.bookings)..where((b) => b.id.equals(waiting)))
        .getSingle();
    expect(row.resourceId, resourceB);
  });

  test('التأجيلُ يفحص التعارضَ أيضاً — لا الإسنادُ وحدَه', () async {
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 12),
      now: now,
    );
    final mine = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    // تأجيلٌ ساعتين يوقعه فوق حجز أحمد
    expect(
      () => db.updateBookingSlot(
        mine,
        startsAt: DateTime(2026, 8, 20, 12),
        now: now,
      ),
      throwsA(isA<BookingConflictException>()),
    );
  });

  test('الحجزُ لا يتعارض مع نفسِه عند التأجيل', () async {
    final mine = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.updateBookingSlot(
      mine,
      startsAt: DateTime(2026, 8, 20, 10, 30),
      now: now,
    );
    final row = await (db.select(db.bookings)..where((b) => b.id.equals(mine)))
        .getSingle();
    expect(row.startsAt, DateTime(2026, 8, 20, 10, 30));
    expect(row.endsAt, DateTime(2026, 8, 20, 11, 30));
  });

  test('التأجيلُ إلى الماضي يُرفض', () async {
    final mine = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(
      () => db.updateBookingSlot(
        mine,
        startsAt: DateTime(2026, 8, 20, 8),
        now: now,
      ),
      throwsA(isA<BookingInPastException>()),
    );
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
flutter test test/unit/bookings_reschedule_test.dart 2>&1 | tail -20; echo "EXIT=${PIPESTATUS[0]}"
```

المتوقَّع: `The method 'updateBookingSlot' isn't defined`.

- [ ] **الخطوة ٣: أضف الدالّة إلى الـDAO**

في آخر `extension BookingsDao` في `lib/data/database/daos/bookings_dao.dart`:

```dart
  /// يبدّل الموظَّفَ أو الوقتَ أو كليهما — **ويُعيد فحصَ التعارض كاملاً**.
  ///
  /// القاعدةُ صيغت بالثلاثيّة `(resourceId, startsAt, endsAt)` لا
  /// بـ«الإسناد» عمداً: **التأجيلُ خطرٌ كالإسناد تماماً** — حجزٌ سليمٌ
  /// يُؤجَّل ساعةً قد يقع فوق حجزٍ آخرَ لنفس الموظَّف. ولو حُصر الفحصُ في
  /// دالّةِ إسنادٍ لمرّ التأجيلُ من جانبها بلا فحص.
  ///
  /// وحجزٌ وُلد بلا موظَّفٍ **لم يُفحَص قطّ**: أوّلُ فحصٍ حقيقيٍّ له يقع
  /// لحظةَ إسناده، فإن غاب هنا لم يقع أبداً.
  ///
  /// `clearResource` يفصل «لا تغيّر الموظَّف» (‏`resourceId: null`) عن
  /// «أعِدْه إلى قائمة الانتظار» — وإلّا استحال التمييز بينهما.
  Future<void> updateBookingSlot(
    int bookingId, {
    int? resourceId,
    bool clearResource = false,
    DateTime? startsAt,
    DateTime? now,
  }) {
    return transaction(() async {
      final currentTime = now ?? DateTime.now();
      final current = await (select(bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingle();

      final newResourceId =
          clearResource ? null : (resourceId ?? current.resourceId);
      final newStartsAt = startsAt ?? current.startsAt;

      if (startsAt != null && newStartsAt.isBefore(currentTime)) {
        throw BookingInPastException(
          'لا يمكن تأجيل الحجز إلى الماضي — الحجزُ حاضرٌ أو مستقبل',
        );
      }

      // النهايةُ تُعاد من مدّةِ الخدمة كي يبقى الطولُ صحيحاً بعد التأجيل.
      final service = await (select(bookingServices)
            ..where((s) => s.id.equals(current.serviceId)))
          .getSingle();
      final newEndsAt = computeBookingEndsAt(
        newStartsAt,
        service.durationMinutes,
        service.bufferMinutes,
      );

      if (newResourceId != null) {
        final clashes = await getOverlappingBookings(
          newResourceId,
          newStartsAt,
          newEndsAt,
          excludeBookingId: bookingId, // لا يتعارض مع نفسِه
        );
        if (clashes.isNotEmpty) {
          throw BookingConflictException(
            'الموظَّفُ مشغولٌ في هذا الوقت — ${clashes.length} حجزٌ متعارض',
          );
        }
      }

      await (update(bookings)..where((b) => b.id.equals(bookingId))).write(
        BookingsCompanion(
          resourceId: Value(newResourceId),
          startsAt: Value(newStartsAt),
          endsAt: Value(newEndsAt),
          updatedAt: Value(currentTime),
        ),
      );
    });
  }
```

- [ ] **الخطوة ٤: شغّل الاختبارات**

```bash
flutter test test/unit/bookings_reschedule_test.dart 2>&1 | tail -20; echo "EXIT=${PIPESTATUS[0]}"
```

المتوقَّع: `+5: All tests passed!`

- [ ] **الخطوة ٥: كوميت**

```bash
git add lib/data/database/daos/bookings_dao.dart test/unit/bookings_reschedule_test.dart
git commit -m "feat(bookings): أيُّ تبدُّلٍ في (الموظَّف، البداية، النهاية) يُعيد فحصَ التعارض"
```

---

## Task 5 — المهمّة ٥: الصلاحياتُ الإحدى عشرة — في الملفّين معاً

**الملفّات:**
- تعديل: `lib/core/permissions/permission_codes.dart`
- تعديل: `lib/presentation/screens/role_management/data/permission_categories.dart`
- اختبار: `test/static/bookings_permission_registration_test.dart`

**الواجهات:**
- يُنتج: ثوابتُ `PermissionCodes.bookingsView` … `bookingsSettings`.

- [ ] **الخطوة ١: اكتب الحارسَ النصّيَّ الفاشل**

```dart
// test/static/bookings_permission_registration_test.dart
//
// كودُ صلاحيةٍ في `permission_codes.dart` وحدَه **لا يمكن منحُه لأحد**:
// شاشةُ «الأدوار والصلاحيات» تُبنى من خريطة `permissionCategories` لا من
// القاعدة. فكودٌ غائبٌ عنها يحرس زرّاً حيّاً ويجعله ميّتاً لغير مدير النظام —
// وهو حالُ `tables_pos_access` اليوم.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _expected = <String>[
  'bookings_view',
  'bookings_add',
  'bookings_edit',
  'bookings_cancel',
  'bookings_status',
  'bookings_assign',
  'bookings_deposit',
  'bookings_services_manage',
  'bookings_resources_manage',
  'bookings_reports',
  'bookings_settings',
];

void main() {
  test('كلُّ كودِ حجزٍ مسجَّلٌ في الملفَّين معاً', () {
    final codes =
        File('lib/core/permissions/permission_codes.dart').readAsStringSync();
    final categories = File(
      'lib/presentation/screens/role_management/data/permission_categories.dart',
    ).readAsStringSync();

    final missingFromCodes =
        _expected.where((c) => !codes.contains("'$c'")).toList();
    final missingFromCategories =
        _expected.where((c) => !categories.contains("'$c'")).toList();

    expect(missingFromCodes, isEmpty,
        reason: 'غائبٌ عن permission_codes.dart: $missingFromCodes');
    expect(missingFromCategories, isEmpty,
        reason: 'غائبٌ عن permission_categories.dart — '
            'فلا يمكن منحُه لأحد: $missingFromCategories');
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
flutter test test/static/bookings_permission_registration_test.dart 2>&1 | tail -12
```

المتوقَّع: فشلٌ بقائمتين تحملان الأكوادَ الأحدَ عشرَ كلَّها.

- [ ] **الخطوة ٣: أضف الأكوادَ إلى `permission_codes.dart`**

**في آخر قائمة الثوابت**، بعد `static const String tablesReserve = 'tables_reserve';`:

```dart

  // ── الحجوزات — مواعيدُ الخدمة (مستقلّةٌ عن حجز الطاولات) ──────────────
  static const String bookingsView = 'bookings_view';
  static const String bookingsAdd = 'bookings_add';
  static const String bookingsEdit = 'bookings_edit';
  static const String bookingsCancel = 'bookings_cancel';
  static const String bookingsStatus = 'bookings_status';

  /// منفصلٌ عن `bookingsEdit` عمداً: الإسنادُ والنقلُ عند الغياب عملُ مضيفٍ
  /// يُمارَس عشراتِ المرّات يوميّاً، بينما تعديلُ الوقتِ والعربونِ أضيق.
  /// دمجُهما يفرض إعطاءَ الأوسعِ لمن يحتاج الأضيق.
  static const String bookingsAssign = 'bookings_assign';

  static const String bookingsDeposit = 'bookings_deposit';
  static const String bookingsServicesManage = 'bookings_services_manage';
  static const String bookingsResourcesManage = 'bookings_resources_manage';
  static const String bookingsReports = 'bookings_reports';
  static const String bookingsSettings = 'bookings_settings';
```

وفي خريطة `categoryLabels` في آخر الملفّ، بعد
`'critical_financial': 'عمليات مالية حرجة',`:

```dart
    'bookings': 'الحجوزات',
```

- [ ] **الخطوة ٤: أضف التصنيفَ إلى `permission_categories.dart`**

في خريطة `permissionCategories`، بعد مدخل `'tables'`:

```dart
  'bookings': const PermissionCategory(
    name: 'الحجوزات',
    icon: PhosphorIconsBold.calendarCheck,
    color: AppColors.info,
    permissions: {
      'bookings_view': 'عرض الحجوزات',
      'bookings_add': 'إضافة حجز',
      'bookings_edit': 'تعديل بيانات الحجز',
      'bookings_cancel': 'إلغاء حجز',
      'bookings_status': 'تغيير حالة الحجز',
      'bookings_assign': 'إسناد/نقل الحجز بين الموظفين',
      'bookings_deposit': 'تحصيل ورد العربون',
      'bookings_services_manage': 'إدارة الخدمات',
      'bookings_resources_manage': 'إدارة الموظفين / الموارد',
      'bookings_reports': 'تقارير الحجوزات',
      'bookings_settings': 'إعدادات الحجوزات',
    },
  ),
```

- [ ] **الخطوة ٥: شغّل الحارسَ والتحليل**

```bash
flutter test test/static/bookings_permission_registration_test.dart 2>&1 | tail -8
flutter analyze lib/core/permissions/ lib/presentation/screens/role_management/ 2>&1 | tail -4
```

المتوقَّع: `All tests passed!` و`No issues found!`.

- [ ] **الخطوة ٦: كوميت**

```bash
git add lib/core/permissions/permission_codes.dart \
        lib/presentation/screens/role_management/data/permission_categories.dart \
        test/static/bookings_permission_registration_test.dart
git commit -m "feat(bookings): أحدَ عشرَ كودَ صلاحيةٍ — وحارسٌ يمنع تسجيلاً في ملفٍّ واحد"
```

---

## Task 6 — المهمّة ٦: سجلُّ العمليات — والتصنيفُ في الشاشتين التوأمين

**الملفّات:**
- إنشاء: `lib/services/booking_service.dart`
- تعديل: `lib/presentation/screens/activity_log_screen.dart`
- تعديل: `lib/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart`
- اختبار: `test/static/bookings_activity_category_parity_test.dart`

**الواجهات:**
- يستهلك: `AppDatabase.logActivity(...)` و`createBooking`/`updateBookingSlot`.
- يُنتج: `class BookingService({required AppDatabase db})` بدوالّ
  `Future<int> create(...)` و`Future<void> reassign(...)` تكتبان السجلَّ.

- [ ] **الخطوة ١: اكتب حارسَ التكافؤ الفاشل**

```dart
// test/static/bookings_activity_category_parity_test.dart
//
// سطرٌ يُكتب في دلوٍ لا يراه أحد. وقع فعلاً: `TableSessionService` صارت
// تكتب `table_reserve` بينما بقيت خريطةُ `_categoryActions` على الاسم
// القديم `add_reservation` — فمن يصفّي بتصنيف «الطاولات» لا يرى شيئاً.
// والخريطةُ خاصّةٌ فلا اختبارَ سلوكٍ يصل إليها؛ الحارسُ نصّيٌّ بالضرورة.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _screens = <String>[
  'lib/presentation/screens/activity_log_screen.dart',
  'lib/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart',
];

const _actions = <String>[
  'booking_create',
  'booking_reassign',
  'booking_reschedule',
  'booking_cancel',
  'booking_status',
];

void main() {
  test('تصنيفُ الحجوزات موجودٌ في الشاشتين وبنفس الأفعال', () {
    for (final path in _screens) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path غير موجود');
      final src = file.readAsStringSync();
      expect(src.contains("'bookings': ["), isTrue,
          reason: 'تصنيفُ bookings غائبٌ عن $path');
      for (final action in _actions) {
        expect(src.contains("'$action'"), isTrue,
            reason: "الفعلُ '$action' غائبٌ عن $path");
      }
    }
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
flutter test test/static/bookings_activity_category_parity_test.dart 2>&1 | tail -10
```

المتوقَّع: `تصنيفُ bookings غائبٌ عن …` للشاشتين.

- [ ] **الخطوة ٣: أضف التصنيفَ إلى الشاشتين — نصٌّ واحدٌ في الاثنتين**

في `_categoryActions` بعد مدخل `'tables': [ … ]` في **كلٍّ** من
`activity_log_screen.dart` و`activity_log_picpos_screen.dart`:

```dart
    // الحجوزات — مواعيدُ الخدمة. أفعالُها منفصلةٌ عن أفعال الطاولات لأنّ
    // الجدولين منفصلان: ذاك يحجز مكاناً وهذا يحجز وقتَ إنسان.
    'bookings': [
      'booking_create', 'booking_reassign', 'booking_reschedule',
      'booking_cancel', 'booking_status',
    ],
```

- [ ] **الخطوة ٤: اكتب الخدمةَ التي تسجّل**

```dart
// lib/services/booking_service.dart
//
// السجلُّ يُكتب من **الخدمة** لا من الودجت: لو كُتب في الودجت لمرّ كلُّ
// مسارٍ آخرَ يكتب حجزاً بلا أثر.

import '../data/database/database.dart';

class BookingService {
  final AppDatabase _db;

  BookingService({required AppDatabase db}) : _db = db;

  Future<int> create({
    required String customerName,
    String? customerPhone,
    int? partyId,
    required int serviceId,
    int? resourceId,
    required DateTime startsAt,
    double depositAmount = 0,
    String? notes,
    int? branchId,
    required int? userId,
    required String userName,
  }) async {
    final id = await _db.createBooking(
      customerName: customerName,
      customerPhone: customerPhone,
      partyId: partyId,
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: startsAt,
      depositAmount: depositAmount,
      notes: notes,
      branchId: branchId,
      createdBy: userId,
    );
    await _db.logActivity(
      userId: userId,
      userName: userName,
      action: 'booking_create',
      // `entityType` هو ما تُرشِّح عليه شاشةُ سجلّ الحجز الواحد.
      entityType: 'booking',
      entityId: id,
      description: 'حجزٌ جديد لـ$customerName في ${startsAt.toIso8601String()}',
      amount: depositAmount,
      branchId: branchId,
    );
    return id;
  }

  /// نقلٌ أو تأجيلٌ — **ويُسجَّل بقيمتَيه السابقةِ واللاحقة.**
  ///
  /// «مَن نقل حجزَ الزبون من فلانٍ إلى فلان» و«مَن أجّل الموعد» سؤالان
  /// يُسألان عند الخلاف، ولا يجيبهما إلا سطرٌ مكتوب.
  Future<void> reassign(
    int bookingId, {
    int? resourceId,
    bool clearResource = false,
    DateTime? startsAt,
    required int? userId,
    required String userName,
  }) async {
    final before = await (_db.select(_db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .getSingle();

    await _db.updateBookingSlot(
      bookingId,
      resourceId: resourceId,
      clearResource: clearResource,
      startsAt: startsAt,
    );

    final after = await (_db.select(_db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .getSingle();

    final movedResource = before.resourceId != after.resourceId;
    await _db.logActivity(
      userId: userId,
      userName: userName,
      action: movedResource ? 'booking_reassign' : 'booking_reschedule',
      entityType: 'booking',
      entityId: bookingId,
      description: movedResource
          ? 'نقلُ حجز ${after.customerName} بين الموظفين'
          : 'تأجيلُ حجز ${after.customerName}',
      oldValue: 'resource=${before.resourceId} start=${before.startsAt}',
      newValue: 'resource=${after.resourceId} start=${after.startsAt}',
      branchId: after.branchId,
    );
  }
}
```

- [ ] **الخطوة ٥: شغّل الحارسَ والتحليل**

```bash
flutter test test/static/bookings_activity_category_parity_test.dart 2>&1 | tail -8
flutter analyze lib/services/booking_service.dart lib/presentation/screens/activity_log_screen.dart lib/presentation/activity_log_picpos/ 2>&1 | tail -4
```

المتوقَّع: `All tests passed!` و`No issues found!`.

- [ ] **الخطوة ٦: كوميت**

```bash
git add lib/services/booking_service.dart \
        lib/presentation/screens/activity_log_screen.dart \
        lib/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart \
        test/static/bookings_activity_category_parity_test.dart
git commit -m "feat(bookings): السجلُّ من الخدمة، والتصنيفُ في الشاشتين معاً"
```

---

## Task 7 — المهمّة ٧: علَمُ الميزة — فكُّ التبعيّة وفتحُ litePicpos

**الملفّات:**
- تعديل: `lib/core/config/feature_dependency_graph.dart:34`
- تعديل: `lib/core/config/feature_policy.dart` (ثابت `litePicpos`)
- اختبار: `test/unit/bookings_feature_flag_test.dart`

**الواجهات:**
- يُنتج: لا واجهةَ برمجيّة — تغييرُ سلوكِ إعدادٍ فقط.

- [ ] **الخطوة ١: اكتب الاختبارَ الفاشل**

```dart
// test/unit/bookings_feature_flag_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/feature_dependency_graph.dart';
import 'package:ural_erp/core/config/feature_key.dart';
import 'package:ural_erp/core/config/feature_policy.dart';

void main() {
  test('الحجوزاتُ لا تُجبر على وحدة الطاولات', () {
    // صالونٌ أو عيادةٌ لا طاولاتِ فيها. وبقاءُ التبعيّة يعني أنّ فتحَ
    // الحجوزات على PicPos-lite يُشغّل وحدةَ الطاولات قسراً على كلّ تنصيب.
    expect(
      FeatureDependencyGraph.requires[FeatureKey.posReservations],
      anyOf(isNull, isEmpty),
    );
  });

  test('litePicpos تفتح الحجوزات و lite لا تُمَسّ', () {
    expect(FeaturePolicy.litePicpos.reservationsEnabled, isTrue);
    // UralCash-lite مطروحةٌ وقد تكون منصَّبةً عند عميل.
    expect(FeaturePolicy.lite.reservationsEnabled, isFalse);
    // ولا تُفتح الطاولاتُ تبعاً لذلك.
    expect(FeaturePolicy.litePicpos.tablesEnabled, isFalse);
  });
}
```

- [ ] **الخطوة ٢: شغّله وتأكّد أنه يفشل**

```bash
flutter test test/unit/bookings_feature_flag_test.dart 2>&1 | tail -12
```

المتوقَّع: فشلُ الاختبارين — التبعيّةُ موجودةٌ و`litePicpos.reservationsEnabled` تساوي `false`.

- [ ] **الخطوة ٣: احذف التبعيّة**

في `lib/core/config/feature_dependency_graph.dart` احذف السطر:

```dart
    FeatureKey.posReservations: [FeatureKey.posTables],
```

وضع مكانه:

```dart
    // لا `posReservations: [posTables]`: الحجزُ موعدُ خدمةٍ يحجز وقتَ إنسان،
    // والطاولةُ تحجز مكاناً — وصالونٌ أو عيادةٌ لا طاولاتِ فيها. وإبقاؤها
    // كان يُشغّل وحدةَ الطاولات قسراً على كلّ تنصيبٍ يفتح الحجوزات.
```

- [ ] **الخطوة ٤: افتح `litePicpos` وحدَها**

في `lib/core/config/feature_policy.dart` داخل ثابت `litePicpos` غيّر:

```dart
    reservationsEnabled: false,
```

إلى:

```dart
    // قرارُ المالك 2026-08-20. و`lite` (UralCash) لا تُمَسّ — مطروحةٌ وقد
    // تكون منصَّبةً عند عميل. وحذفُ تبعيّة `posReservations → posTables`
    // شرطُ هذا الفتح: بدونه يُشغّل وحدةَ الطاولات على كلّ تنصيبات lite.
    reservationsEnabled: true,
```

- [ ] **الخطوة ٥: شغّل الاختبار وسويّةَ الوحدات كاملةً**

```bash
flutter test test/unit/bookings_feature_flag_test.dart 2>&1 | tail -8
flutter test test/unit 2>&1 | tail -8; echo "EXIT=${PIPESTATUS[0]}"
```

المتوقَّع: الاختبارُ الجديد أخضر، **وسويّةُ الوحدات كلُّها خضراء**.
تغييرُ علَمِ ملفٍّ قد يُسقط اختباراتٍ تفترض القديم — إن سقط شيءٌ فاقرأ سببَه
ولا تُطفئ العلَمَ للهروب.

- [ ] **الخطوة ٦: كوميت**

```bash
git add lib/core/config/ test/unit/bookings_feature_flag_test.dart
git commit -m "feat(bookings): فكُّ تبعيّة الطاولات وفتحُ الحجوزات في PicPos-lite"
```

---

## البوّابةُ النهائيّة

- [ ] **شغّل البوّابةَ كاملةً — في الخلفية**

```bash
bash scripts/gate.sh
```

**~٣٤ دقيقة** وسقفُ الأداة ١٠، فالخلفيّةُ إلزاميّة. **ولا تعدّل ملفاً وهي
تعمل.**

- [ ] **افصل الفشلَ الحقيقيَّ عن فشل الإقلاع**

```bash
grep -c "\[E\]\|Test failed" <سجلّ-البوّابة>
```

**صفرٌ ⇒ لا اختبارَ فشل** ⇒ ابحث عن سببِ إقلاع (شبكةٌ · `sqlite3.dll` ·
تصادمُ `build/`) لا عن عطبٍ في الكود. و«٠ ناجح» في سويّةٍ **ليست فشلاً بل
سويّةً لم تعمل أصلاً** — والقرينةُ الحاسمةُ أن سويّةً سابقةً مرّت بعددٍ كبير.

- [ ] **قارِن بخطّ الأساس**

خطُّ الأساس المقيسُ على `main` قبل هذا العمل: analyze ٦ info ·
unit **٣٥٣٨** · widget **٧٠٨** · integration **٧١٠**. الأعدادُ الجديدةُ يجب
أن تكون **أكبرَ** بعدد الاختبارات المضافة، ولا يقلّ شيءٌ منها.
**أعد قياسَ خطّ الأساس بنفسك إن شككت** — أرقامُ المستندات تبطُل.

---

## ما هو خارجُ هذه الخطّة صراحةً

لئلّا يظنّ منفِّذٌ أنه نسي شيئاً:

- **أيُّ شاشة** — مشروع ٢
- **تحصيلُ العربون وردُّه ومصادرتُه وترحيلُه المحاسبيّ** — مشروع ٣
  (`depositStatus` مضافٌ هنا بنيةً، والحوارُ والحركةُ الماليّة هناك)
- **الوجهاتُ السبعُ في الشريط السفليّ** — مشروع ٤
- **التقاريرُ والتذكيرات** — مشروع ٥

وثلاثةُ بنودٍ من المواصفة **لا يمكن إنجازُها هنا** فتُنقَل صراحةً إلى مشروع ٢
لئلّا تُحسَب منسيّة:

- **وصلُ `AppConfig.showReservations` بمستهلكٍ حقيقيّ.** العلَمُ يبقى ميّتاً
  بعد هذه الخطّة لأنه يحجب **شاشةً**، ولا شاشةَ هنا. المهمّةُ ٧ تُصلح
  التبعيّةَ والملفّ فقط.
- **إغلاقُ ثغرة `PermissionGuard`** محلّيّاً في مُشغِّل أفعال الحجوزات — ذاك
  مُشغِّلُ واجهةٍ لا يوجد بعد.
- **إنفاذُ انتقالات الحالة** (`pending → confirmed → in_service → completed`).
  هذه الخطّةُ تُثبّت الحالاتِ قيمةً في العمود وتستثني `cancelled`/`no_show`
  من فحص التعارض، ولا تفرض آلةَ حالاتٍ — المواصفةُ لا تطلبها، والانتقالاتُ
  تقع من الشاشة.
