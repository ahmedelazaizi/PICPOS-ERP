part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BRANCHES & WAREHOUSES & INVENTORY
// ═══════════════════════════════════════════════════════════════════════════

class Regions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get globalId => text().nullable().unique()();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

class Branches extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  // L4 (2026-04-28): short branch code used as a prefix for invoice numbers
  // (e.g. "CAI", "ALX") so server-side invoice listings show the originating
  // branch directly instead of the opaque CLT{ip} suffix. Nullable to keep
  // backward-compat with rows from before this column existed.
  TextColumn get code => text().nullable().withLength(max: 10)();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  IntColumn get regionId => integer().nullable().references(Regions, #id)();
  // Spec 129 F6 — seeded-default flag. The boot self-heal recreates a row
  // only if NO row has is_system_default=true (FR-601..606). Operator
  // renames survive because the flag isn't tied to the row's name.
  BoolColumn get isSystemDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

class Warehouses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)();
  IntColumn get branchId => integer().nullable().references(Branches, #id)();
  TextColumn get type => text().withDefault(const Constant('general'))();
  // Types: general (عام), raw_materials (خامات), finished_goods (منتج تام), retail (بيع)
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)();
  IntColumn get regionId => integer().nullable().references(Regions, #id)();
  // Spec 129 F6 — seeded-default flag (see Branches.isSystemDefault).
  BoolColumn get isSystemDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'idx_stock_movements_product', columns: {#productId})
@TableIndex(name: 'idx_stock_movements_date', columns: {#createdAt})
@TableIndex(
  name: 'idx_stock_movements_report',
  columns: {#createdAt, #movementType, #warehouseId},
)
@TableIndex(
  name: 'idx_stock_movements_product_date',
  columns: {#productId, #createdAt},
)
@TableIndex(
  name: 'idx_stock_movements_composite',
  columns: {#productId, #warehouseId, #createdAt},
)
@TableIndex(
  name: 'idx_stock_movements_reference',
  columns: {#referenceType, #referenceId},
)
@TableIndex(name: 'idx_stock_movements_branch', columns: {#branchId, #createdAt})
class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  TextColumn get movementType =>
      text()(); // purchase, sale, return, adjustment, transfer
  RealColumn get quantity => real()(); // +in / -out
  RealColumn get unitCost => real().withDefault(const Constant(0))();
  RealColumn get balanceAfter => real()();
  TextColumn get referenceType =>
      text().nullable()(); // purchase_invoice, sales_invoice
  IntColumn get referenceId => integer().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)(); // R-28: audit trail
  IntColumn get branchId => integer().nullable().references(Branches, #id)(); // Branch isolation
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // Phase 4: Distributed Sync Reliability

  TextColumn get idempotencyKey => text().nullable()(); // Deduplication key for offline replay resilience
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'idx_inventory_balances_product', columns: {#productId})
@TableIndex(name: 'idx_inventory_balances_warehouse', columns: {#warehouseId})
@TableIndex(
  name: 'idx_inventory_balances_composite',
  columns: {#productId, #warehouseId},
  unique: true,
)
class InventoryBalances extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  RealColumn get quantity => real().withDefault(const Constant(0))();
  RealColumn get reservedQuantity => real().withDefault(const Constant(0))(); // الكمية المحجوزة لطلبات البيع
  // Spec 153: informational per-warehouse cost (transfer-source cost,
  // analytics). NOT the inventory-valuation SoT — products.costPrice is, and it
  // alone posts to GL 1136. Do not use averageCost as a valuation basis.
  RealColumn get averageCost => real().withDefault(const Constant(0))();
  DateTimeColumn get lastUpdated =>
      dateTime().withDefault(currentDateAndTime)();

}

class StockAudits extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get auditDate => dateTime().withDefault(currentDateAndTime)();
  TextColumn get status =>
      text().withDefault(const Constant('open'))(); // open, completed
  TextColumn get notes => text().nullable()();
  IntColumn get warehouseId => integer().nullable().references(Warehouses, #id)(); // المستودع
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

}

class StockAuditItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get auditId => integer().references(StockAudits, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get expectedQuantity => real()();
  RealColumn get actualQuantity => real()();
  RealColumn get difference => real()();
  DateTimeColumn get scannedAt => dateTime().withDefault(currentDateAndTime)();

}

// ═══════════════════════════════════════════════════════════════════════════
// INVENTORY BONDS (Phase 2)
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_inventory_bonds_date', columns: {#bondDate})
@TableIndex(name: 'idx_inventory_bonds_warehouse', columns: {#warehouseId})
@TableIndex(name: 'idx_inventory_bonds_type', columns: {#type})
class InventoryBonds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bondNumber => text().withLength(max: 50)(); // رقم السند
  TextColumn get type => text().withDefault(
    const Constant('in'),
  )(); // in (إضافة), out (صرف), opening (رصيد افتتاحي)
  DateTimeColumn get bondDate => dateTime().withDefault(currentDateAndTime)();
  IntColumn get warehouseId => integer().references(Warehouses, #id)();
  IntColumn get toWarehouseId => integer().nullable().references(
    Warehouses,
    #id,
  )(); // Destination for transfers
  TextColumn get notes => text().nullable()();
  IntColumn get costCenterId => integer().nullable().references(CostCenters, #id)(); // مركز التكلفة
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Spec 129 F4 — caller-minted UUIDv7 so mirror local insert + server-side
  // insert agree on identity. Server-side handler dedups against this column.
  TextColumn get globalId => text().nullable().unique()();

}

@TableIndex(name: 'idx_inventory_bond_items_bond', columns: {#bondId})
@TableIndex(name: 'idx_inventory_bond_items_product', columns: {#productId})
class InventoryBondItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bondId => integer().references(InventoryBonds, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitCost =>
      real().withDefault(const Constant(0))(); // التكلفة وقت الإضافة
  IntColumn get unitId => integer().nullable().references(Units, #id)();
  TextColumn get notes => text().nullable()();

}

// ═══════════════════════════════════════════════════════════════════════════
// STOCK REQUISITIONS (Phase 2)
// ═══════════════════════════════════════════════════════════════════════════

@TableIndex(name: 'idx_stock_requisitions_date', columns: {#requisitionDate})
@TableIndex(name: 'idx_stock_requisitions_status', columns: {#status})
class StockRequisitions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get requisitionNumber => text().withLength(max: 50)(); // رقم الطلب
  DateTimeColumn get requisitionDate => dateTime().withDefault(currentDateAndTime)();
  IntColumn get fromBranchId => integer().references(Branches, #id)(); // الفرع الطالب
  IntColumn get toBranchId => integer().references(Branches, #id)(); // الفرع المورد
  TextColumn get status => text().withDefault(
        const Constant('pending'),
      )(); // pending, approved, rejected, fulfilled
  TextColumn get notes => text().nullable()();
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Spec 148 (S-ISSUE) — caller-minted UUIDv7 so a future cross-node sync can
  // dedup this between-branches document. Mirrors inventory_bonds.globalId.
  // (The inventory + GL effect already syncs via the transfer this document
  // triggers; the doc itself is not yet registered in the sync pipeline.)
  TextColumn get globalId => text().nullable().unique()();
  // Spec 148 — the transfer bond id that fulfilled this requisition (null
  // until fulfilled). Audit link requisition → warehouse transfer. Plain
  // nullable int (no drift-level relationship needed; the migration adds a
  // bare INTEGER column, matching how the id is used).
  IntColumn get fulfilledByTransferId => integer().nullable()();

}

@TableIndex(name: 'idx_stock_requisition_items_req', columns: {#requisitionId})
@TableIndex(name: 'idx_stock_requisition_items_prod', columns: {#productId})
class StockRequisitionItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get requisitionId => integer().references(StockRequisitions, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  IntColumn get unitId => integer().nullable().references(Units, #id)();
  TextColumn get notes => text().nullable()();

}
