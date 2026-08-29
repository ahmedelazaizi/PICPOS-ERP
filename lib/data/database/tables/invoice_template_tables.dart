part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INVOICE TEMPLATES - مصمم الفواتير
// ═══════════════════════════════════════════════════════════════════════════

/// قوالب الفواتير المخصصة
class InvoiceTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)(); // اسم القالب
  TextColumn get type =>
      text().withDefault(const Constant('thermal'))(); // thermal, a4
  TextColumn get templateCategory => text().withDefault(
    const Constant('receipt'),
  )(); // receipt, invoice, kitchen, quotation, purchase
  BoolColumn get isDefault =>
      boolean().withDefault(const Constant(false))(); // القالب الافتراضي
  TextColumn get paperSize =>
      text().withDefault(const Constant('80mm'))(); // 80mm, 58mm, A4, A5
  RealColumn get paperWidth =>
      real().withDefault(const Constant(80))(); // عرض الورق بالمم
  RealColumn get paperHeight =>
      real().nullable()(); // ارتفاع الورق (null = تلقائي)
  TextColumn get margins => text().withDefault(
    const Constant('{"top":5,"right":5,"bottom":5,"left":5}'),
  )(); // الهوامش JSON
  TextColumn get defaultFont =>
      text().withDefault(const Constant('Cairo'))(); // الخط الافتراضي
  RealColumn get defaultFontSize =>
      real().withDefault(const Constant(12))(); // حجم الخط الافتراضي
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// ١ = تدفّق (‏`sortOrder` + `flexWidth`) · ٢ = نطاقاتٌ بإحداثيّات.
  ///
  /// الراسمُ يقرأ هذا العمودَ ويسلك المسارَ المناسب، **فالقوالبُ غيرُ
  /// المهاجَرة تعمل كما هي بلا أيِّ تغيير**. والهجرةُ كسولةٌ عند أوّل فتحٍ في
  /// المحرّر لا دفعةً واحدة: الترقيةُ الجماعيّةُ تلمس قوالبَ قد لا يفتحها
  /// المستخدمُ أبداً، وأيُّ خطأٍ فيها يظهر على ورقِ عميلٍ لا على شاشة.
  IntColumn get layoutVersion => integer().withDefault(const Constant(1))();

  /// ارتفاعاتُ النطاقات بالمليمتر — JSON ‏`{"header":34,"info":24,…}`.
  ///
  /// ── لماذا عمودٌ أصلاً ────────────────────────────────────────────────
  /// كان ارتفاعُ النطاق **مشتقّاً**: أبعدُ قاعِ عنصرٍ فيه. فزرّا `+`/`−` في
  /// لوحة «ارتفاع النطاق» يعملان في الجلسة ثمّ يعود الرقمُ عند إعادة الفتح —
  /// تعديلٌ لا مستقرَّ له. والاشتقاقُ يمنع أيضاً الحشوةَ السفليّةَ التي
  /// يطلبها التصميم: ‏٣٤/٢٤/٢٦/٩٦/٤٢/٣٦مم بينما الاشتقاقُ يعطي
  /// ٣١/١٩/١٨/٩٦/٣٣/٣٣.
  ///
  /// ── ولماذا JSON لا ستّةُ أعمدة ───────────────────────────────────────
  /// النطاقاتُ قد تزيد (‏`BandId` تعدادٌ قد يكبر)، وستّةُ أعمدةٍ تعني هجرةً
  /// لكلِّ نطاقٍ جديد. والقراءةُ كلُّها دفعةً واحدةً في `buildDocument` فلا
  /// يُستعلَم عن نطاقٍ منفرداً — وهو الشرطُ الذي يجعل JSON مقبولاً هنا.
  ///
  /// ⚠️ **و`null` تعني «اشتقّ»** لا «صفر»: القوالبُ القائمةُ كلُّها فارغةُ
  /// هذا العمود، فلا يجوز أن تنهار نطاقاتُها إلى ارتفاعٍ صفريّ.
  TextColumn get bandHeights => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// عناصر قالب الفاتورة
class InvoiceTemplateElements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateId => integer().references(InvoiceTemplates, #id)();
  TextColumn get elementType =>
      text()(); // logo, company_name, invoice_number, date, customer, items_table, totals, footer, qr_code, barcode, text, variable, image, line, rectangle
  IntColumn get rowIndex => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  RealColumn get flexWidth => real().withDefault(const Constant(100))();
  RealColumn get xPosition => real().withDefault(const Constant(0))();
  RealColumn get yPosition => real().withDefault(const Constant(0))();
  RealColumn get width => real().withDefault(const Constant(100))();
  RealColumn get height => real().withDefault(const Constant(20))();
  TextColumn get textAlign => text().withDefault(const Constant('center'))();
  TextColumn get fontFamily => text().nullable()();
  RealColumn get fontSize => real().withDefault(const Constant(12))();
  BoolColumn get isBold => boolean().withDefault(const Constant(false))();
  BoolColumn get isItalic => boolean().withDefault(const Constant(false))();
  TextColumn get fontColor => text().withDefault(const Constant('#000000'))();
  TextColumn get backgroundColor => text().nullable()();
  TextColumn get borderColor => text().nullable()();
  RealColumn get borderWidth => real().withDefault(const Constant(0))();
  TextColumn get content => text().nullable()(); // المحتوى المخصص
  TextColumn get labelAr => text().nullable()();
  TextColumn get labelEn => text().nullable()();
  BoolColumn get isVisible => boolean().withDefault(const Constant(true))();
  TextColumn get extraStyles => text().nullable()();
  TextColumn get section => text().withDefault(const Constant('body'))(); // header, body, details, footer
  TextColumn get formula => text().nullable()(); // مثل: "[subtotal] - [discount]"

  // ── نموذجُ النطاقات ──────────────────────────────────────────────────────
  // تُكتب **بجانب** القديمة لا بدلاً منها، فالقالبُ غيرُ المهاجَر يبقى يعمل.
  //
  // وكلُّها `nullable` بلا افتراضٍ عمداً: الصفرُ موضعٌ حقيقيٌّ عند الحافّة،
  // و`null` وحدَها تقول «هذا العنصرُ لم يُهاجَر بعد». خلطُ الاثنين يجعل كلَّ
  // عنصرٍ قديمٍ يبدو ملتصقاً بالزاوية العليا.
  //
  // ⚠️ مُعلَنةٌ هنا لا في الهجرة وحدَها: `onCreate` يبني من كيانات drift،
  //    فعمودٌ يعيش في `ALTER TABLE` فقط يغيب عن كلِّ تنصيبٍ **جديد**.

  /// header · info · party · details · totals · footer
  TextColumn get bandId => text().nullable()();

  /// إحداثيّاتٌ بالمليمتر من حافّة النطاق — لا بالبكسل: البكسلُ يتغيّر
  /// بالتكبير، والمليمترُ وحدةُ الورق.
  RealColumn get xMm => real().nullable()();
  RealColumn get yMm => real().nullable()();
  RealColumn get wMm => real().nullable()();
  RealColumn get hMm => real().nullable()();

  /// `field op value` — فارغٌ يعني «يظهر دائماً».
  TextColumn get condition => text().nullable()();
}

/// إعدادات جدول الأصناف في القالب
class InvoiceTableSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateId => integer().references(InvoiceTemplates, #id)();
  RealColumn get xPosition => real().withDefault(const Constant(0))();
  RealColumn get yPosition => real().withDefault(const Constant(200))();
  RealColumn get width => real().withDefault(const Constant(500))();
  RealColumn get fontSize => real().withDefault(const Constant(12))();
  BoolColumn get showIndex =>
      boolean().withDefault(const Constant(true))(); // عرض رقم الصنف
  BoolColumn get showProductCode =>
      boolean().withDefault(const Constant(false))(); // عرض كود المنتج
  BoolColumn get showProductName =>
      boolean().withDefault(const Constant(true))(); // عرض اسم المنتج
  BoolColumn get showQuantity =>
      boolean().withDefault(const Constant(true))(); // عرض الكمية
  BoolColumn get showUnitPrice =>
      boolean().withDefault(const Constant(true))(); // عرض سعر الوحدة
  BoolColumn get showDiscount =>
      boolean().withDefault(const Constant(true))(); // عرض الخصم
  BoolColumn get showTax =>
      boolean().withDefault(const Constant(false))(); // عرض الضريبة
  BoolColumn get showTotal =>
      boolean().withDefault(const Constant(true))(); // عرض الإجمالي
  BoolColumn get showUnit =>
      boolean().withDefault(const Constant(false))(); // عرض الوحدة
  BoolColumn get showBarcode =>
      boolean().withDefault(const Constant(false))(); // عرض الباركود
  BoolColumn get showNotes =>
      boolean().withDefault(const Constant(false))(); // عرض ملاحظات الصنف
  TextColumn get headerBgColor =>
      text().withDefault(const Constant('#333333'))();
  TextColumn get headerTextColor =>
      text().withDefault(const Constant('#FFFFFF'))();
  RealColumn get headerFontSize => real().withDefault(const Constant(12))();
  TextColumn get headerFontFamily => text().nullable()();
  TextColumn get rowBgColor => text().withDefault(const Constant('#FFFFFF'))();
  TextColumn get altRowBgColor => text().nullable()();
  RealColumn get rowHeight => real().withDefault(const Constant(20))();
  TextColumn get columnWidths => text().nullable()();

  /// items | ledger | report — يقرّر أيَّ حمولةٍ يقرأ الرابط.
  TextColumn get tableKind => text().withDefault(const Constant('items'))();

  /// الأعمدةُ بعناوينها وعروضها ومنازلها، مسلسلةً.
  ///
  /// `null` تعني «استعمل أعلام `show*` القديمة» — وهو ما يُبقي كلَّ قالبٍ
  /// قائمٍ يطبع كما كان بالضبط. وبها تحلّ عناوينُ الأعمدة محلَّ الحرفيّات
  /// الثمانية المكتوبة في الكود، فتعمل ثنائيّةُ اللغة في رؤوس الجدول.
  TextColumn get columnsJson => text().nullable()();
}

// ═══════════════════════════════════════════════════════════════════════════
// TEMPLATE BINDINGS - رابطاتُ القوالب
// ═══════════════════════════════════════════════════════════════════════════

/// أيُّ قالبٍ يخدم أيَّ مستند — بمفتاحٍ رباعيّ.
///
/// ── لماذا جدولٌ بدل عَلَم `isDefault` ────────────────────────────────────
/// `isDefault` عَلَمٌ **عالميٌّ لا يعرف فرعاً ولا طابعةً ولا لغة**. فالفرعُ
/// الذي يريد ترويسةً مختلفةً لا يستطيع، والطابعةُ الحراريّةُ تتلقّى قالبَ A4
/// فيُقصّ المطبوعُ صامتاً.
///
/// و`null` في أيِّ حقلِ نطاقٍ تعني «أيّاً كان» — **لا صفراً**: الصفرُ معرِّفُ
/// فرعٍ محتمل، فلا يصلح علامةً للعموم.
///
/// السلسلةُ في `services/printing/template_resolver.dart`.
class TemplateBindings extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// sales_invoice · sales_return · purchase_invoice · purchase_return · …
  ///
  /// والمرتجعان فئتان قائمتان بذاتهما: بدونهما يتقاسم المرتجعُ فئةَ الفاتورة
  /// ويستحيل أن يكون له قالبٌ افتراضيٌّ خاصّ.
  TextColumn get documentType => text().withLength(max: 40)();

  /// null = أيُّ فرع.
  IntColumn get branchId => integer().nullable()();

  /// null = أيُّ طابعة.
  IntColumn get printerId => integer().nullable()();

  /// null = أيُّ لغة.
  TextColumn get locale => text().nullable().withLength(max: 10)();

  IntColumn get templateId => integer().references(InvoiceTemplates, #id)();

  IntColumn get copies => integer().withDefault(const Constant(1))();
  BoolColumn get directPrint => boolean().withDefault(const Constant(false))();

  /// يفصل عند تساوي الخصوصيّة — الأعلى يفوز.
  IntColumn get priority => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
