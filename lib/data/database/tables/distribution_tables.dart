part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DISTRIBUTION & SALES REP TABLES
// ═══════════════════════════════════════════════════════════════════════════

/// مسارات التوزيع — تعريف المسارات الجغرافية للمندوبين
class SalesRoutes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // "مسار شرق القاهرة"
  TextColumn get description => text().nullable()();
  IntColumn get salesRepId =>
      integer().nullable().references(Employees, #id)(); // المندوب المسؤول
  TextColumn get area => text().nullable()(); // المنطقة الجغرافية
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === v167 — أعمدةُ المزامنة (المرحلة ٣: الفئةُ التشغيليّة) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// زيارات المندوبين للعملاء على المسار
class RouteVisits extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get routeId => integer().references(SalesRoutes, #id)();
  IntColumn get customerId => integer().references(Parties, #id)(); // references Parties.id
  IntColumn get salesRepId => integer().references(Employees, #id)(); // references Employees.id
  DateTimeColumn get visitDate => dateTime()();
  TextColumn get status => text().withDefault(
    const Constant('planned'),
  )(); // planned, completed, cancelled, skipped
  TextColumn get notes => text().nullable()();
  IntColumn get saleId =>
      integer().nullable()(); // فاتورة البيع الناتجة (اختياري)
  RealColumn get orderAmount =>
      real().withDefault(const Constant(0))(); // قيمة الطلب
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === v167 — أعمدةُ المزامنة (المرحلة ٣: الفئةُ التشغيليّة) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// أهداف المندوبين الشهرية
class SalesRepTargets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get salesRepId => integer().references(Employees, #id)(); // references Employees.id
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  RealColumn get targetAmount => real()(); // الهدف بالعملة
  RealColumn get achievedAmount =>
      real().withDefault(const Constant(0))(); // المحقق
  IntColumn get targetVisits =>
      integer().withDefault(const Constant(0))(); // زيارات مستهدفة
  IntColumn get achievedVisits =>
      integer().withDefault(const Constant(0))(); // زيارات محققة
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === v167 — أعمدةُ المزامنة (المرحلة ٣: الفئةُ التشغيليّة) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// تحصيلات المندوبين من العملاء
class SalesRepCollections extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get salesRepId => integer().references(Employees, #id)(); // references Employees.id
  IntColumn get customerId => integer().references(Parties, #id)(); // references Parties.id
  RealColumn get amount => real()();
  TextColumn get paymentMethod =>
      text().withDefault(const Constant('cash'))(); // cash, check, transfer
  TextColumn get referenceNumber => text().nullable()(); // رقم الشيك/الإيصال
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // === v167 — أعمدةُ المزامنة (المرحلة ٣: الفئةُ التشغيليّة) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}
