part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LANDED COST — التكاليف المحملة (Phase C2)
// ═══════════════════════════════════════════════════════════════════════════

/// Landed cost sheet linked to a purchase invoice
@DataClassName('LandedCostSheetData')
@TableIndex(name: 'idx_landed_cost_purchase', columns: {#purchaseInvoiceId})
class LandedCostSheets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseInvoiceId =>
      integer().references(PurchaseInvoices, #id)();
  TextColumn get sheetNumber => text().withLength(max: 50)();
  RealColumn get totalAdditionalCost =>
      real().withDefault(const Constant(0))();

  /// Allocation method: by_value, by_quantity, equal
  /// (by_weight is intentionally not offered — deferred; needs a product weight.)
  TextColumn get allocationMethod =>
      text().withDefault(const Constant('by_value'))();

  /// Status: draft, applied, cancelled, voided (set when the parent purchase
  /// invoice is voided — S-COST-2 / Spec 145; its landed JE is reversed).
  TextColumn get status =>
      text().withDefault(const Constant('draft'))();

  TextColumn get notes => text().nullable()();
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Individual cost items within a landed cost sheet
@DataClassName('LandedCostItemData')
@TableIndex(name: 'idx_landed_cost_item_sheet', columns: {#sheetId})
class LandedCostItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sheetId => integer().references(LandedCostSheets, #id)();

  /// Cost type: shipping, customs, insurance, freight, handling, other
  TextColumn get costType =>
      text().withDefault(const Constant('shipping'))();

  TextColumn get description => text()();
  RealColumn get amount => real()();
  IntColumn get supplierPartyId =>
      integer().nullable().references(Parties, #id)();
}

/// Allocation of costs to individual products
@DataClassName('LandedCostAllocationData')
@TableIndex(name: 'idx_landed_alloc_sheet', columns: {#sheetId})
@TableIndex(name: 'idx_landed_alloc_product', columns: {#productId})
class LandedCostAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sheetId => integer().references(LandedCostSheets, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get purchaseItemId =>
      integer().references(PurchaseInvoiceItems, #id)();
  RealColumn get originalCost => real()();
  RealColumn get allocatedAmount => real()();
  RealColumn get newUnitCost => real()();
  RealColumn get quantity => real()();
}
