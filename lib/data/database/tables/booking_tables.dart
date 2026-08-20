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
