part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COMMERCIAL PAPERS (الأوراق التجارية — شيكات/كمبيالات)
// ═══════════════════════════════════════════════════════════════════════════

@DataClassName('CommercialPaperData')
@TableIndex(name: 'idx_papers_due_date', columns: {#dueDate})
@TableIndex(name: 'idx_papers_status', columns: {#status})
@TableIndex(name: 'idx_papers_party', columns: {#partyId})
class CommercialPapers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get paperNumber => text().withLength(max: 50)();
  TextColumn get type => text()(); // cheque, promissory_note, bill_of_exchange
  TextColumn get direction => text()(); // received (وارد), issued (صادر)
  IntColumn get partyId => integer().references(Parties, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get issueDate => dateTime()();
  DateTimeColumn get dueDate => dateTime()();
  TextColumn get bankName => text().nullable().withLength(max: 100)();
  TextColumn get bankBranch => text().nullable().withLength(max: 100)();
  TextColumn get accountNumber => text().nullable().withLength(max: 50)();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  // Status: pending, deposited, cashed, bounced, endorsed, cancelled, partially_cashed
  IntColumn get endorsedToPartyId =>
      integer().nullable().references(Parties, #id)();
  TextColumn get notes => text().nullable()();
  IntColumn get safeId =>
      integer().nullable().references(Safes, #id)(); // الخزنة المودع فيها
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// History of status changes for audit trail
@DataClassName('PaperStatusHistoryData')
class PaperStatusHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paperId => integer().references(CommercialPapers, #id)();
  TextColumn get fromStatus => text()();
  TextColumn get toStatus => text()();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get changedBy => integer().references(Users, #id)();
  TextColumn get notes => text().nullable()();
}

// ═══════════════════════════════════════════════════════════════════════════
// CURRENCIES & EXCHANGE RATES (العملات وأسعار الصرف)
// ═══════════════════════════════════════════════════════════════════════════

class Currencies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(max: 5)(); // USD, EUR, JOD, EGP, SAR
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get symbol => text().withLength(max: 5)(); // $, €, د.أ, ج.م, ر.س
  RealColumn get exchangeRate => real().withDefault(
    const Constant(1.0),
  )(); // سعر الصرف مقابل العملة الأساسية
  IntColumn get decimalPlaces => integer().withDefault(const Constant(2))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@DataClassName('ExchangeRateHistoryData')
class ExchangeRateHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get currencyId => integer().references(Currencies, #id)();
  RealColumn get rate => real()();
  DateTimeColumn get effectiveDate => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ═══════════════════════════════════════════════════════════════════════════
// PRICE LISTS (قوائم الأسعار)
// ═══════════════════════════════════════════════════════════════════════════

@DataClassName('PriceListData')
class PriceLists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name =>
      text().withLength(max: 100)(); // جملة, نصف جملة, تجزئة, خاص
  TextColumn get code => text().withLength(max: 20)();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get currencyId => integer().nullable()(); // عملة القائمة
  DateTimeColumn get startDate => dateTime().nullable()(); // تاريخ البداية
  DateTimeColumn get endDate => dateTime().nullable()(); // تاريخ الانتهاء
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@DataClassName('PriceListItemData')
@TableIndex(name: 'idx_price_list_items_product', columns: {#productId})
@TableIndex(name: 'idx_price_list_items_list', columns: {#priceListId})
class PriceListItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get priceListId => integer().references(PriceLists, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get price => real()();
  RealColumn get minQuantity =>
      real().withDefault(const Constant(1))(); // حد أدنى للكمية
  RealColumn get maxDiscount =>
      real().withDefault(const Constant(0))(); // أقصى خصم مسموح %
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}
