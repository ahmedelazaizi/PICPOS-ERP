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
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
}

class TableOrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tableOrderId => integer().references(TableOrders, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get total => real()();
  RealColumn get taxRate => real().withDefault(const Constant(0))(); // NEW
  RealColumn get taxAmount => real().withDefault(const Constant(0))(); // NEW
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
