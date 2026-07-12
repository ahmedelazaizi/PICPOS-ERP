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
}
