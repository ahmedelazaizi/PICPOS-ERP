// ═══════════════════════════════════════════════════════════════════════════
// م-2 (Spec 153 totals-reconciliation) — Option A: a READ-ONLY reconciliation
// that surfaces the gap between the perpetual inventory value and GL account
// 1136, plus the two documented drift sources. Posts nothing; changes no WAC
// semantics (products.costPrice stays the SoT).
//
//   glBalance                 = Σ(debit − credit) over POSTED, non-deleted JE
//                               lines on account 1136.
//   reportValue               = Σ currentStock × costPrice over inventory-TRACKED
//                               products — the GL-comparable perpetual value
//                               (services never post to 1136; deactivated stock
//                               stays, since deactivation posts no reversal).
//   perpetualBalancesAtCostPrice = Σ inventory_balances.qty × products.costPrice
//   perpetualBalancesAtAvgCost   = Σ inventory_balances.qty × average_cost
//   delta                     = reportValue − glBalance  (the reconciliation gap)
//   costBasisDivergence       = perpetualBalancesAtAvgCost − perpetualBalancesAtCostPrice
//                               (drift source 1: warehouse average_cost vs the
//                                global costPrice that GL was posted at)
//   stockVsLedgerDivergence   = reportValue − perpetualBalancesAtCostPrice
//                               (drift source 3: products.currentStock vs the
//                                Σ inventory_balances.quantity ledger, at costPrice)
//   zeroCostItemCount/Qty     = products with on-hand stock but costPrice = 0
//                               (drift source 2: zero_cost_policy=warn moves that
//                                skipped the COGS/inventory JE)
//
// Assertions are DELTA-based (measure, mutate, re-measure) so any bootstrap
// baseline the test DB seeds is irrelevant, plus two internal identities.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int accId; // account 1136
  late int wId;

  setUp(() async {
    db = AppDatabase.forTesting();
    // Reuse a seeded inventory account if the bootstrap created one; otherwise
    // create it. Either way exactly one '1136' exists after setUp, so the DAO's
    // getAccountByCode('1136') resolves to the same account these JE lines hit.
    final existing =
        await (db.select(db.accounts)..where((a) => a.code.equals('1136'))).get();
    accId = existing.isNotEmpty
        ? existing.first.id
        : await db.into(db.accounts).insert(AccountsCompanion.insert(
              code: '1136',
              name: 'مخزون البضاعة',
              accountType: 'asset',
            ));
    wId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'W1'));
  });

  tearDown(() => db.close());

  test(
      'reconciliation reflects a GL posting, perpetual value, cost-basis divergence and zero-cost stock',
      () async {
    final base = await db.getInventoryGlReconciliation();
    expect(base, isNotNull, reason: 'account 1136 resolves → non-null result');

    // 1. Post a JE debiting 1136 by 1000 (posted, non-deleted) → glBalance +1000.
    final jeId = await db.into(db.journalEntries).insert(
          JournalEntriesCompanion.insert(
            entryNumber: 'JE-T1',
            entryDate: DateTime(2026, 6, 1),
          ),
        );
    await db.into(db.journalEntryLines).insert(
          JournalEntryLinesCompanion.insert(
            entryId: jeId,
            accountId: accId,
            debit: const Value(1000),
          ),
        );
    // A POSTED, non-deleted CREDIT line on 1136 as well (COGS credits inventory
    // on every sale) — exercises the − SUM(credit) arm. Net GL move = 1000 − 200.
    await db.into(db.journalEntryLines).insert(
          JournalEntryLinesCompanion.insert(
            entryId: jeId,
            accountId: accId,
            credit: const Value(200),
          ),
        );

    // 2. A product with global stock 10 @ costPrice 5 → reportValue +50.
    await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'A', code: 'PA', costPrice: const Value(5), currentStock: const Value(10)));

    // 3. A product whose warehouse average_cost (15) ≠ global costPrice (10),
    //    stock only in the warehouse ledger → costBasisDivergence +(15−10)×4 = 20.
    final pB = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'B', code: 'PB', costPrice: const Value(10)));
    await db.into(db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
        productId: pB,
        warehouseId: wId,
        quantity: const Value(4),
        averageCost: const Value(15)));

    // 4. A zero-cost product still holding stock → zeroCostItemCount +1, qty +7.
    await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'C', code: 'PC', costPrice: const Value(0), currentStock: const Value(7)));
    // 5. A zero-cost product with NO stock → must be EXCLUDED (current_stock > 0),
    //    so the zero-cost count/qty deltas stay +1 / +7.
    await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'D', code: 'PD', costPrice: const Value(0), currentStock: const Value(0)));
    // 6. A NON-tracked product (service) with stock 100 @ cost 9 → EXCLUDED from
    //    every figure: it never posts to GL 1136, so 900 must not become drift.
    await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'E',
        code: 'PE',
        costPrice: const Value(9),
        currentStock: const Value(100),
        trackInventory: const Value(false)));

    final after = await db.getInventoryGlReconciliation();
    expect(after, isNotNull);

    expect(after!.glBalance - base!.glBalance, closeTo(800, 0.001),
        reason: 'net posted 1136 move = debit 1000 − credit 200 (both arms)');
    // reportValue counts only inventory-TRACKED products: A adds 50; the
    // non-tracked service E (100×9 = 900) must NOT leak in.
    expect(after.reportValue - base.reportValue, closeTo(50, 0.001),
        reason: 'reportValue = Σ currentStock×costPrice over tracked products only');
    expect(
        after.perpetualBalancesAtCostPrice - base.perpetualBalancesAtCostPrice,
        closeTo(40, 0.001),
        reason: 'ledger at costPrice: product B qty 4 × costPrice 10');
    expect(after.costBasisDivergence - base.costBasisDivergence, closeTo(20, 0.001),
        reason: 'per-warehouse avg_cost 15 vs costPrice 10 over qty 4 = 20');
    // stockVsLedgerDivergence = reportValue − perpetualCostPrice: A's currentStock
    // 10 has no ledger row (+50), B's ledger qty 4 has no currentStock (−40) → +10.
    expect(
        after.stockVsLedgerDivergence - base.stockVsLedgerDivergence,
        closeTo(10, 0.001),
        reason: 'currentStock vs ledger quantity, valued at costPrice');
    expect(after.delta - base.delta, closeTo(50 - 800, 0.001),
        reason: 'delta = reportValue − glBalance moved by (+50) − (+800)');
    expect(after.zeroCostItemCount - base.zeroCostItemCount, 1,
        reason: 'only the tracked zero-cost product WITH stock is flagged (C, not D/E)');
    expect(after.zeroCostStockQty - base.zeroCostStockQty, closeTo(7, 0.001),
        reason: 'its on-hand quantity is surfaced');
  });

  test('a DELETED or UNPOSTED journal entry is excluded from the GL balance',
      () async {
    final base = await db.getInventoryGlReconciliation();

    // Unposted entry — must not count.
    final jeUnposted = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(
            entryNumber: 'JE-UP',
            entryDate: DateTime(2026, 6, 1),
            isPosted: const Value(false)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: jeUnposted, accountId: accId, debit: const Value(500)));

    // Deleted entry — must not count.
    final jeDeleted = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(
            entryNumber: 'JE-DEL',
            entryDate: DateTime(2026, 6, 1),
            isDeleted: const Value(true)));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: jeDeleted, accountId: accId, credit: const Value(300)));

    final after = await db.getInventoryGlReconciliation();
    expect(after!.glBalance - base!.glBalance, closeTo(0, 0.001),
        reason: 'neither an unposted nor a deleted JE line moves the GL balance');
  });

  test(
      'a DEACTIVATED but inventory-tracked product with stock stays valued (its value is still in GL 1136)',
      () async {
    final base = await db.getInventoryGlReconciliation();
    // Deactivation posts NO GL reversal, so a discontinued item still holding
    // stock keeps its value in account 1136 — the reconciliation must keep it too
    // (do NOT filter isActive, only track_inventory).
    await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Dead',
        code: 'PX',
        costPrice: const Value(6),
        currentStock: const Value(5),
        isActive: const Value(false)));
    final after = await db.getInventoryGlReconciliation();
    expect(after!.reportValue - base!.reportValue, closeTo(30, 0.001),
        reason: 'inactive tracked stock (5×6) stays counted — isActive is NOT filtered');
  });
}
