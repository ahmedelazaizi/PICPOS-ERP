part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OFFERS & RESTAURANT TABLES
// ═══════════════════════════════════════════════════════════════════════════

class Offers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // اسم العرض
  TextColumn get barcode =>
      text().nullable().unique()(); // Barcode for the offer (NEW)
  RealColumn get offerPrice => real()(); // سعر العرض
  DateTimeColumn get startDate => dateTime().nullable()(); // تاريخ البداية
  DateTimeColumn get endDate => dateTime().nullable()(); // تاريخ النهاية
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // --- Advanced Offers ---
  TextColumn get offerType => text().withDefault(
    const Constant('bundle'),
  )(); // bundle | buy_x_get_y | percentage | fixed_discount
  RealColumn get discountValue => real().nullable()(); // نسبة/مبلغ الخصم
  IntColumn get buyQuantity => integer().nullable()(); // اشترِ X
  IntColumn get getQuantity => integer().nullable()(); // واحصل على Y مجاناً
  IntColumn get minQuantity => integer().nullable()(); // الحد الأدنى للكمية
  IntColumn get maxUses => integer().nullable()(); // الحد الأقصى للاستخدام
  IntColumn get currentUses =>
      integer().withDefault(const Constant(0))(); // الاستخدام الحالي
  TextColumn get timeStart => text().nullable()(); // وقت البداية اليومي HH:mm
  TextColumn get timeEnd => text().nullable()(); // وقت النهاية اليومي HH:mm
  IntColumn get categoryId =>
      integer().nullable()(); // التصنيف (للعروض على مستوى التصنيف)
  // M6: branch targeting — null/empty = global (applies to all branches)
  TextColumn get branchIds => text().nullable()(); // CSV of branch IDs
  BoolColumn get isGlobal => boolean().withDefault(const Constant(true))();
}

class OfferItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get offerId => integer().references(Offers, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()(); // الكمية في العرض
}

class TableSections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name =>
      text().withLength(max: 100)(); // اسم القسم (صالة، تراس، خارجي)
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class RestaurantTables extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sectionId =>
      integer().nullable().references(TableSections, #id)(); // القسم التتبع له
  TextColumn get name => text()(); // اسم الطاولة
  IntColumn get capacity => integer().withDefault(const Constant(4))(); // السعة
  TextColumn get status => text().withDefault(
    const Constant('available'),
  )(); // available, reserved, occupied, seated, ordered, eating, billing, cleaning
  RealColumn get x =>
      real().withDefault(const Constant(0))(); // X coordinate in Floor Plan
  RealColumn get y =>
      real().withDefault(const Constant(0))(); // Y coordinate in Floor Plan
  TextColumn get shape =>
      text().withDefault(const Constant('rect'))(); // rect, circle
  DateTimeColumn get lastStatusAt => dateTime().withDefault(
    currentDateAndTime,
  )(); // For Service Attention timers
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class TableOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tableId => integer().references(RestaurantTables, #id)();
  TextColumn get status => text().withDefault(
    const Constant('open'),
  )(); // open, bill_requested, closed, cancelled
  RealColumn get total => real().withDefault(const Constant(0))();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  IntColumn get mergedToId => integer().nullable().references(
    TableOrders,
    #id,
  )(); // ID of the order this was merged into

  /// عددُ الأشخاص — يُسأل عند فتح الطاولة، وهو مقامُ التقسيم بالتساوي.
  IntColumn get guestCount => integer().withDefault(const Constant(1))();

  /// ملاحظةُ الطلب — تنتقل مع الطلب عند النقل.
  TextColumn get notes => text().nullable()();

  /// نوعُ خصم الطلب: `percent` أو `amount`.
  TextColumn get discountType => text().nullable()();

  /// قيمةُ الخصم بحسب نوعه. يُثبَّت قبل الدفع فينتقل ويُطبع.
  RealColumn get discountValue => real().withDefault(const Constant(0))();

  /// هل تُحتسَب ضريبةُ المبيعات على هذا الطلب؟
  ///
  /// مرآةُ `CartState.taxEnabled` بحرفها — بما في ذلك الافتراضُ `false`:
  /// الزرُّ في الشاشة هو ما يفعّلها، لا الإعداد. وتثبيتُها **على الطلب** —
  /// لا في السلّة لحظةَ الدفع — هو ما يجعل المشحونَ على الفاتورة يطابق
  /// المسجَّلَ على الطلب، فيسكت حارسُ [checkTableCharge] لأن الرقمين صارا
  /// واحداً حقّاً، لا لأنه أُضعِف.
  BoolColumn get taxEnabled => boolean().withDefault(const Constant(false))();

  /// نسبةُ ضريبة الطلب احتياطاً لبنودٍ لا نسبةَ لها (`TableOrderItems.taxRate`
  /// صفرٌ) — كسريّةً لا مئويّةً (0.16 لا 16)، مرآةً لـ`CartState.taxRate`
  /// ولإعداد `pos_default_tax_rate` الذي تُنسَخ منه. والمئويّةُ تُشتقّ عند
  /// العرض والحساب بالضرب في ١٠٠، تماماً كما يفعل `CartState.totals`.
  ///
  /// **وهنا الموضعُ الوحيدُ الذي نخالف فيه سلّةَ الكاشير عمداً:** السلّةُ
  /// تقرأ النسبةَ حيّةً فتتغيّر تحت يدها إن غُيّر الإعداد، أمّا الطاولةُ فهذه
  /// **لقطةٌ تُؤخذ لحظةَ فتحها**. الوجبةُ تمتدّ ساعةً، والحسابُ يُعرَض على
  /// الضيف قبل أن يُدفَع؛ فتغييرُ الإعداد في منتصف الوجبة يجب ألّا يُعيد
  /// تسعيرَ حسابٍ رآه الضيفُ بالفعل.
  RealColumn get taxRate => real().withDefault(const Constant(0))();

  /// مجموعُ ما حُصِّل. تُشتقّ منه حالةُ الطاولة: `occupied` حتى يبلغ
  /// `total`، ثم `paid`. لا حالةَ سادسةً للدفع الجزئي.
  RealColumn get paidAmount => real().withDefault(const Constant(0))();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();

  /// ضريبةٌ «مفعَّلةٌ» بنسبةِ صفرٍ حالةٌ **تكذب**، فلا تُمثَّل.
  ///
  /// `TableSessionService.setOrderTax` يرفضها عند المفتاح، لكنّ الرفضَ عند
  /// بابٍ واحدٍ يُبقيها ممكنةَ الوجود: تصفيرُ `taxRate` من تحت الزرِّ يصنعها
  /// بلا أن يمرَّ على الحارس، وكذلك أيُّ مسارِ كتابةٍ يُضاف غداً. وهنا
  /// يستوي البابان: القيدُ يسري على `INSERT` و`UPDATE` وعلى كلِّ مَن يكتب.
  ///
  /// وهو يُصاغ بشقٍّ للإطفاء لا بـ`taxRate > 0` وحدَها عن قصد: الطلبُ يُفتَح
  /// مطفأً ونسبتُه ملقوطةٌ، والمطفأُ حرٌّ في نسبته — فاللقطةُ تبقى محفوظةً
  /// بعد الإطفاء ولا تُطارَد.
  ///
  /// و`NOT tax_enabled` لا `tax_enabled = 0` عن قصدٍ كذلك — والفرقُ يقع على
  /// Postgres لا على SQLite. المقارنةُ `boolean = integer` لا وجودَ لها في
  /// Postgres إلّا بمعامِلٍ يصنعه `_createPostgresCompatLayer` بنفسه، وكلُّ
  /// جملةٍ فيه ملفوفةٌ بـ`try/catch` لا تطبع إلّا سطراً. فلو أخفق صنعُ
  /// المعامِل، أخفقت `m.create(tableOrders)` في المرحلة الأولى وسقط الجدولُ
  /// إلى بديل الـDDL الخام — وذلك البديلُ يكتب الأعمدةَ وأنواعَها فقط، **بلا
  /// أيّ `REFERENCES`**. فيُنشَأ `table_orders` على خادمٍ جديدٍ بلا مفاتيحه
  /// الثلاثة، صامتاً. و`NOT` مفهومةٌ في اللهجتين بلا معامِلٍ مُصطنَع، فلا
  /// تُعلَّق سلامةُ المفاتيح على `catch` يطبع سطراً.
  @override
  List<String> get customConstraints => [
        'CHECK (NOT tax_enabled OR tax_rate > 0)',
      ];
}

class TableOrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// أصنافُ هذا الطلب. تُسمّى صراحةً لأن البند يشير إلى `TableOrders` مرّتين
  /// (هنا وفي `sourceTableOrderId`)، وبلا تسميةٍ صريحةٍ يتصادم الاسمان
  /// فيُسقط المولِّد العلاقتين معاً بلا خطأ.
  @ReferenceName('orderItems')
  IntColumn get tableOrderId => integer().references(TableOrders, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get total => real()();
  RealColumn get taxRate => real().withDefault(const Constant(0))(); // NEW
  RealColumn get taxAmount => real().withDefault(const Constant(0))(); // NEW

  /// ملاحظةُ البند («بلا بصل») — تصل المطبخ وتُطبع.
  TextColumn get notes => text().nullable()();

  /// الطلبُ الذي جاء منه هذا البند بعد الدمج. فارغٌ للأصناف الأصلية.
  /// وجودُه هو ما يجعل الطباعةَ مجمَّعةً وفكَّ الدمج ممكناً.
  @ReferenceName('mergedAwayItems')
  IntColumn get sourceTableOrderId =>
      integer().nullable().references(TableOrders, #id)();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Table reservations for restaurant tables
class TableReservations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tableId => integer().references(RestaurantTables, #id)();
  TextColumn get customerName => text().withLength(max: 100)();
  TextColumn get customerPhone => text().nullable()();
  DateTimeColumn get reservationTime => dateTime()(); // الوقت المتوقع للوصول
  IntColumn get partySize =>
      integer().withDefault(const Constant(2))(); // عدد الأشخاص
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending, confirmed, seated, cancelled, no_show
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// دفعةٌ واحدةٌ على طلبِ طاولة — صفٌّ لكلّ دافع.
///
/// هو ما يجعل «عدّةَ فواتيرَ لطلبٍ واحد» ممكناً (التقسيم بالأصناف)، ويحتمل
/// في الوقت نفسه «فاتورةً واحدةً بعدّة دفعات» (التقسيم بالتساوي/بمبلغ) إذ
/// يتكرّر `invoiceId`. ولذلك لم يُضَف عمودٌ إلى `SalesInvoices`: هي جدولٌ
/// مشترَكٌ مع UralCash يُنقل بـpatch، ولا يعرف الطاولات.
class TableOrderPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tableOrderId => integer().references(TableOrders, #id)();
  IntColumn get invoiceId => integer().references(SalesInvoices, #id)();
  RealColumn get amount => real()();
  TextColumn get splitLabel => text().nullable()(); // «ضيف ١»
  DateTimeColumn get paidAt => dateTime().withDefault(currentDateAndTime)();
}
