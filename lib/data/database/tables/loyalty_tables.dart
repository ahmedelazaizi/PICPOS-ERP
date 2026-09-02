part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LOYALTY SYSTEM TABLES
// ═══════════════════════════════════════════════════════════════════════════

/// برامج الولاء — تعريف قواعد النقاط
class LoyaltyPrograms extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // "برنامج النقاط الأساسي"
  RealColumn get pointsPerUnit =>
      real()(); // نقاط لكل 1 عملة (مثلاً 1 نقطة لكل 10 دينار)
  RealColumn get redemptionRate =>
      real()(); // قيمة النقطة // كل دينار يساوي نقطة
  RealColumn get pointsPerCurrency => real().withDefault(const Constant(1.0))();
  IntColumn get minRedeemPoints => integer().withDefault(
    const Constant(100),
  )(); // أقل عدد نقاط قابل للاستبدال
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// رصيد نقاط العميل لكل برنامج
class CustomerLoyaltyPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Parties, #id)(); // references Parties.id
  IntColumn get programId => integer().references(LoyaltyPrograms, #id)();
  IntColumn get totalEarned => integer().withDefault(const Constant(0))();
  IntColumn get totalRedeemed => integer().withDefault(const Constant(0))();
  IntColumn get currentBalance => integer().withDefault(const Constant(0))();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// سجل حركات النقاط (كسب / استبدال / تعديل)
class LoyaltyTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Parties, #id)(); // references Parties.id
  IntColumn get programId => integer().references(LoyaltyPrograms, #id)();
  TextColumn get type => text()(); // 'earn', 'redeem', 'expire', 'adjust'
  IntColumn get points => integer()(); // موجب للكسب، سالب للاستبدال
  IntColumn get saleId => integer().nullable()(); // ربط بفاتورة البيع (اختياري)
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}
