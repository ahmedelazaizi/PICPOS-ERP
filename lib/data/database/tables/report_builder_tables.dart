part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REPORT BUILDER — منشئ التقارير المخصصة (Phase C5)
// ═══════════════════════════════════════════════════════════════════════════

/// Custom report definitions
@DataClassName('CustomReportData')
class CustomReports extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // اسم التقرير
  TextColumn get description => text().nullable()();

  /// Source entity: products, sales_invoices, purchase_invoices,
  /// parties, inventory_balances, journal_entries, employees
  TextColumn get sourceEntity => text()();

  /// Selected columns as JSON array: ["name", "price", "quantity"]
  TextColumn get columns => text()();

  /// Filter conditions as JSON: [{"field":"price","op":">","value":100}]
  TextColumn get filters => text().nullable()();

  /// Group-by fields as JSON: ["category_id"]
  TextColumn get groupBy => text().nullable()();

  /// Sort configuration as JSON: [{"field":"name","dir":"asc"}]
  TextColumn get sortBy => text().nullable()();

  /// Aggregate functions as JSON: {"total_amount":"SUM","quantity":"AVG"}
  TextColumn get aggregates => text().nullable()();

  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  BoolColumn get isShared => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Saved report execution logs
@DataClassName('SavedReportRunData')
class SavedReportRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get reportId => integer().references(CustomReports, #id)();
  DateTimeColumn get runAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get rowCount => integer().withDefault(const Constant(0))();
  IntColumn get executionMs => integer().withDefault(const Constant(0))();
}
