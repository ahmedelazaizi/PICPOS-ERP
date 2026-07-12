// ═══════════════════════════════════════════════════════════════════════════
// Spec 153 Option B (consistency cleanup) — branch inventory value must be
// computed at the global WAC (products.costPrice), the single inventory-cost
// SoT (owner decision 2026-07-12), NOT per-warehouse inventory_balances.
// average_cost. This aligns getBranchInventoryValue with GL account 1136, the
// inventory report (post-م-1), and the م-2 reconciliation — all costPrice —
// so the branch-performance / branch-management value figures agree with them.
//
// average_cost is kept as an informational per-warehouse figure (transfer cost,
// analytics) but is no longer a valuation basis.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test(
      'getBranchInventoryValue values on-hand stock at products.costPrice, not average_cost',
      () async {
    final branchId = await db
        .into(db.branches)
        .insert(BranchesCompanion.insert(name: 'الفرع 1'));
    final wId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(name: 'W1', branchId: Value(branchId)));
    // Global costPrice 10; the warehouse's per-warehouse average_cost is 15.
    final pId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'صنف', code: 'PA', costPrice: const Value(10)));
    await db.into(db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
        productId: pId,
        warehouseId: wId,
        quantity: const Value(4),
        averageCost: const Value(15)));
    // A NON-tracked product (service) with stock in the same branch → excluded
    // (never posts to GL 1136), so it must not inflate the branch value.
    final svcId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'خدمة',
        code: 'SVC',
        costPrice: const Value(9),
        trackInventory: const Value(false)));
    await db.into(db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
        productId: svcId,
        warehouseId: wId,
        quantity: const Value(100),
        averageCost: const Value(0)));

    final value = await db.getBranchInventoryValue(branchId);

    // costPrice basis: 10 × 4 = 40 (ties out to GL 1136 + inventory report).
    // average_cost basis would be 15 × 4 = 60 — must NOT be used.
    expect(value, closeTo(40.0, 0.001),
        reason:
            'branch inventory value must use products.costPrice (SoT), not per-warehouse average_cost');
  });

  test('getBranchInventoryValue is 0 for a branch with no warehouses', () async {
    final branchId = await db
        .into(db.branches)
        .insert(BranchesCompanion.insert(name: 'فرع فاضي'));
    final value = await db.getBranchInventoryValue(branchId);
    expect(value, closeTo(0.0, 0.001));
  });
}
