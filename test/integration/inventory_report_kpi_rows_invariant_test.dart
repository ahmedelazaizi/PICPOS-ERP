// ═══════════════════════════════════════════════════════════════════════════
// م-1 (Spec 153 totals-reconciliation) — the inventory-report KPI card MUST
// value the SAME product set with the SAME cost basis as the table rows below.
//
// Each test reconstructs the expected total the EXACT way the report screen
// renders a row — `DriftProductRepository.getAllProducts()` for the set,
// `getWarehouseStockMap()` for scoped stock, and `costPrice × stock` for the
// value (inventory_report_screen.dart:449) — then asserts
// getInventoryReportAnalytics() agrees. Reconstructing from the real row
// sources (not hand-picked constants) means the invariant also breaks if the
// row-side query ever diverges from the KPI query (e.g. the repo's
// getAllProducts being consolidated onto the active-only, LIMIT-500 variant).
//
// The bugs this pins (all made card ≠ Σ rows):
//   (a) > 500 active SKUs  → old KPI capped at 500, rows show all.
//   (b) inactive w/ stock  → rows value it, old KPI (active-only) dropped it.
//   (c) warehouse-scoped   → old KPI used per-warehouse average_cost, rows
//                            used costPrice.
//
// Owner decision (2026-07-12): value at global products.costPrice in BOTH modes
// (matches the rows, matches how COGS credits GL 1136 on sale, matches the WAC
// SoT). average_cost is intentionally NOT the basis.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_product_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<int> seedProduct(
    String name,
    String code, {
    required double cost,
    required double sale,
    double stock = 0,
    double minStock = 0,
    bool active = true,
  }) {
    return db.into(db.products).insert(
          ProductsCompanion.insert(
            name: name,
            code: code,
            costPrice: Value(cost),
            salePrice: Value(sale),
            currentStock: Value(stock),
            minStock: Value(minStock),
            isActive: Value(active),
          ),
        );
  }

  // Rebuild the KPI the SAME way the screen sums its visible rows: iterate the
  // repo's product list (the table's source), take global currentStock or the
  // summed per-warehouse stock map, and value at costPrice / salePrice.
  Future<({double cost, double sale})> expectedFromRows({
    List<int>? warehouseIds,
  }) async {
    final products = await DriftProductRepository(db).getAllProducts();
    final scoped = warehouseIds != null;
    final stockMap = <int, double>{};
    if (scoped) {
      for (final w in warehouseIds) {
        final m = await db.getWarehouseStockMap(w);
        m.forEach((k, v) => stockMap[k] = (stockMap[k] ?? 0.0) + v);
      }
    }
    var cost = 0.0;
    var sale = 0.0;
    for (final p in products) {
      final stock = scoped ? (stockMap[p.id] ?? 0.0) : p.currentStock;
      cost += p.costPrice * stock; // == inventory_report_screen.dart:449
      sale += p.salePrice * stock;
    }
    return (cost: cost, sale: sale);
  }

  test(
      'global KPI == Σ rows over EVERY product at costPrice — no 500 cap, incl inactive-with-stock',
      () async {
    // 600 active products (> the old LIMIT 500) each stock 5 @ cost 2 / sale 3.
    await db.batch((b) {
      for (var i = 0; i < 600; i++) {
        b.insert(
          db.products,
          ProductsCompanion.insert(
            name: 'P$i',
            code: 'C$i',
            costPrice: const Value(2),
            salePrice: const Value(3),
            currentStock: const Value(5),
          ),
        );
      }
    });
    // An INACTIVE product still holding residual stock — a valuation report
    // still owns that stock on hand.
    await seedProduct('Dead', 'DED',
        cost: 7, sale: 9, stock: 10, active: false);

    final exp = await expectedFromRows();
    // The row path itself must be uncapped + include inactive: 600×10 + 70.
    expect(exp.cost, closeTo(6070.0, 0.001),
        reason: 'guard: the row source is not itself capped/dropping inactive');

    final a = await db.getInventoryReportAnalytics(warehouseIds: null);
    expect(a.totalCostValue, closeTo(exp.cost, 0.001),
        reason: 'global KPI cost must equal Σ costPrice×stock over ALL rows');
    expect(a.totalSaleValue, closeTo(exp.sale, 0.001),
        reason: 'global KPI sale must equal Σ salePrice×stock over ALL rows');
  });

  test(
      'warehouse-scoped KPI == Σ rows at costPrice across MULTIPLE warehouses (NOT average_cost)',
      () async {
    // costPrice 10 globally; two warehouses hold stock at average_cost 15 and 12
    // (both ≠ costPrice). Scoping to both must value at costPrice × total qty.
    final pid = await seedProduct('Widget', 'WID', cost: 10, sale: 20, stock: 0);
    final w1 = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'W1'));
    final w2 = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'W2'));
    await db.into(db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
        productId: pid,
        warehouseId: w1,
        quantity: const Value(4),
        averageCost: const Value(15)));
    await db.into(db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
        productId: pid,
        warehouseId: w2,
        quantity: const Value(6),
        averageCost: const Value(12)));

    final exp = await expectedFromRows(warehouseIds: [w1, w2]);
    // costPrice basis across both warehouses: 10 × (4 + 6) = 100.
    // average_cost basis would be (4×15 + 6×12) = 132 — must NOT be this.
    expect(exp.cost, closeTo(100.0, 0.001),
        reason: 'guard: rows value scoped stock at costPrice, summed over both WHs');

    final a = await db.getInventoryReportAnalytics(warehouseIds: [w1, w2]);
    expect(a.totalCostValue, closeTo(exp.cost, 0.001),
        reason: 'scoped KPI cost must equal Σ costPrice×stock over both WHs');
    expect(a.totalSaleValue, closeTo(exp.sale, 0.001),
        reason: 'scoped KPI sale must equal Σ salePrice×stock over both WHs');
  });

  test(
      'low-stock alert count stays active-only (W2 intent) though inactive stock is still valued',
      () async {
    // Active, below minStock → a genuine reorder alert.
    await seedProduct('LowActive', 'LA',
        cost: 3, sale: 5, stock: 1, minStock: 5);
    // Inactive (discontinued), also below minStock → valued, but NO alert.
    await seedProduct('LowDead', 'LD',
        cost: 4, sale: 6, stock: 2, minStock: 5, active: false);

    final a = await db.getInventoryReportAnalytics(warehouseIds: null);

    expect(a.lowStockCount, 1,
        reason: 'only the ACTIVE low-stock product raises a reorder alert (W2)');
    // Both are still VALUED — value coverage ≠ alert semantics.
    final exp = await expectedFromRows();
    expect(exp.cost, closeTo(11.0, 0.001),
        reason: 'guard: inactive stock (LD) is valued too — 3×1 + 4×2 = 11');
    expect(a.totalCostValue, closeTo(exp.cost, 0.001),
        reason: 'card value still covers inactive stock on hand');
  });
}
