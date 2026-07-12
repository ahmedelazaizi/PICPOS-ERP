part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// KITCHEN DISPLAY SYSTEM (KDS) TABLES
// ═══════════════════════════════════════════════════════════════════════════

/// Work Orders - Main kitchen orders
///
/// Each work order represents a set of items to be prepared in the kitchen.
/// Can be linked to a table order or a POS sale.
class WorkOrders extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Order number for display (e.g., WO-001)
  TextColumn get orderNumber => text()();

  /// Status: pending, preparing, ready, served, cancelled
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Priority: normal, high, urgent
  TextColumn get priority => text().withDefault(const Constant('normal'))();

  /// Kitchen station: kitchen, bar, dessert, etc.
  TextColumn get station => text().withDefault(const Constant('kitchen'))();

  /// Link to table order (optional - for restaurant mode)
  IntColumn get tableOrderId =>
      integer().nullable().references(TableOrders, #id)();

  /// Link to sales invoice (optional - for POS mode)
  IntColumn get invoiceId =>
      integer().nullable().references(SalesInvoices, #id)();

  /// Customer name for display (if not table order)
  TextColumn get customerName => text().nullable()();

  /// Special notes for kitchen
  TextColumn get notes => text().nullable()();

  /// Who created this order
  IntColumn get createdBy => integer().nullable().references(Users, #id)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get preparedAt => dateTime().nullable()();
  DateTimeColumn get servedAt => dateTime().nullable()();
}

/// Work Order Items - Individual items in a work order
class WorkOrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get workOrderId => integer().references(WorkOrders, #id)();
  IntColumn get productId => integer().references(Products, #id)();

  /// Product name cached for display
  TextColumn get productName => text()();

  RealColumn get quantity => real()();

  /// Status: pending, preparing, ready
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Special preparation notes
  TextColumn get notes => text().nullable()();

  /// Assigned chef (optional)
  IntColumn get assignedTo => integer().nullable().references(Users, #id)();

  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

/// Kitchen Stations - Define kitchen areas/stations
class KitchenStations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // Kitchen, Bar, Dessert, etc.
  TextColumn get code => text()(); // KITCHEN, BAR, DESSERT
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Category → Station mapping for intelligent order routing
/// Maps product categories to kitchen stations so orders are
/// automatically split and routed to the correct station.
class CategoryStationMappings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get stationId => integer().references(KitchenStations, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [{categoryId, stationId}];
}

