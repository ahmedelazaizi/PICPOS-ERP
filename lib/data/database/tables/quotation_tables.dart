part of '../database.dart';

@DataClassName('QuotationData')
@TableIndex(name: 'idx_quotations_date', columns: {#quotationDate})
@TableIndex(name: 'idx_quotations_customer', columns: {#customerId})
class Quotations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get quotationNumber => text().withLength(max: 50)();
  IntColumn get customerId => integer().nullable().references(Parties, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  IntColumn get userId => integer().references(Users, #id)();
  DateTimeColumn get quotationDate => dateTime()();
  DateTimeColumn get validityDate =>
      dateTime().nullable()(); // Expiry date for quotation
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('draft'))(); // draft, converted
  IntColumn get convertedToInvoiceId =>
      integer().nullable().references(SalesInvoices, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'idx_quotation_items_quotation', columns: {#quotationId})
@TableIndex(name: 'idx_quotation_items_product', columns: {#productId})
class QuotationItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get quotationId => integer().references(Quotations, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  RealColumn get taxRate => real().withDefault(const Constant(0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}
