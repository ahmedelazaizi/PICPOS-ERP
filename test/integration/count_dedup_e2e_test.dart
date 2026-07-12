// ═══════════════════════════════════════════════════════════════════════════
// S-COUNT (Spec 147) — Inventory-Count De-duplication E2E
//
// US1: the full audit (finalizeAudit) posts ONE balanced settlement entry per
//      session — the per-item internal JE is suppressed (no double-post).
// US2: finalizeCycleCountTask is atomic (rollback on failure), updates the
//      global stock cache, and mints a globalId on its movement.
// US3: both subsystems value a variance on the approved WAC (products.costPrice),
//      not the per-warehouse average_cost — identical settlement value.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;

  // Standard COA codes seeded by forTesting().
  const invCode = '1136'; // مخزون
  const shrinkCode = '6216'; // عجز مخزون
  const surplusCode = '4317'; // فائض مخزون

  setUp(() async {
    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'جارد', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'counter', password: 'pw', displayName: 'Counter', roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
  });

  tearDown(() => db.close());

  // ── helpers ────────────────────────────────────────────────────────────
  Future<int> seedProduct(String code, double cost, double stock) async {
    final pid = await db.insertProduct(ProductsCompanion.insert(
      code: code, name: 'صنف $code',
      salePrice: const Value(0.0), costPrice: Value(cost),
      trackInventory: const Value(true),
    ));
    // type:'initial' is NOT an accounted movement type → seeds stock without
    // any JE, so per-account JE totals below reflect only the count settlement.
    await db.adjustStock(
      productId: pid, warehouseId: warehouseId, quantity: stock,
      type: 'initial', unitCost: cost,
    );
    return pid;
  }

  Future<double> balance(int pid) async {
    final b = await (db.select(db.inventoryBalances)
          ..where((x) => x.productId.equals(pid) & x.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return b?.quantity ?? 0.0;
  }

  Future<double> currentStock(int pid) async =>
      (await db.getProductById(pid))!.currentStock;

  Future<int> acctId(String code) async =>
      (await db.accountingDao.getAccountByCode(code))!.id;

  /// (debit − credit) posted to [code] across entries of [refType]/[refId].
  Future<double> netFor(String refType, int refId, String code) async {
    final aid = await acctId(code);
    final r = await db.customSelect(
      '''SELECT COALESCE(SUM(l.debit),0) AS d, COALESCE(SUM(l.credit),0) AS c
         FROM journal_entry_lines l
         JOIN journal_entries e ON e.id = l.entry_id
         WHERE e.reference_type = ? AND e.reference_id = ? AND l.account_id = ?''',
      variables: [Variable(refType), Variable(refId), Variable(aid)],
    ).getSingle();
    return (r.data['d'] as num).toDouble() - (r.data['c'] as num).toDouble();
  }

  Future<int> jeCount(String refType, int refId) async {
    final rows = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals(refType) & e.referenceId.equals(refId)))
        .get();
    return rows.length;
  }

  /// Assert every entry of [refType]/[refId] balances (Σdebit == Σcredit).
  Future<void> expectBalanced(String refType, int refId) async {
    final r = await db.customSelect(
      '''SELECT COALESCE(SUM(l.debit),0) AS d, COALESCE(SUM(l.credit),0) AS c
         FROM journal_entry_lines l
         JOIN journal_entries e ON e.id = l.entry_id
         WHERE e.reference_type = ? AND e.reference_id = ?''',
      variables: [Variable(refType), Variable(refId)],
    ).getSingle();
    final d = (r.data['d'] as num).toDouble();
    final c = (r.data['c'] as num).toDouble();
    expect((d - c).abs() < 0.005, isTrue, reason: 'entry must balance: dr=$d cr=$c');
  }

  Future<int> makeCycleTask(int warehouse) async {
    final planId = await db.createCycleCountPlan(
      name: 'خطة', warehouseId: warehouse, frequency: 'monthly',
      productsPerTask: 50, createdBy: userId,
    );
    final taskId = await db.generateCycleCountTask(
      planId: planId, warehouseId: warehouse, productsPerTask: 50, assignedTo: userId,
    );
    await db.startCycleCountTask(taskId);
    return taskId;
  }

  // ═══ US1 — Audit posts one settlement, not two ═════════════════════════
  group('US1 — full audit single settlement post', () {
    test('mixed shortage + surplus → posted exactly once, balanced', () async {
      final a = await seedProduct('AUD-A', 40.0, 100.0); // shortage 10 → 400
      final b = await seedProduct('AUD-B', 25.0, 50.0); //  surplus 5  → 125

      final auditId = await db.createStockAudit(userId: userId);
      await db.saveAuditItem(auditId: auditId, productId: a, actualQuantity: 90.0, expectedQuantity: 100.0);
      await db.saveAuditItem(auditId: auditId, productId: b, actualQuantity: 55.0, expectedQuantity: 50.0);
      await db.finalizeAudit(auditId);

      // Stock corrected.
      expect(await balance(a), 90.0);
      expect(await balance(b), 55.0);

      // Exactly one aggregate settlement entry; NO per-item internal JE.
      expect(await jeCount('inventory_audit', auditId), 1, reason: 'one aggregate entry');
      expect(await jeCount('stock_adjustment', auditId), 0, reason: 'per-item internal JE suppressed');

      // Values posted ONCE (a double-post would read 800 / 250).
      expect(await netFor('inventory_audit', auditId, shrinkCode), 400.0);
      expect(await netFor('inventory_audit', auditId, surplusCode), -125.0); // credit
      // inventory: Cr 400 (shortage) + Dr 125 (surplus) → net −275.
      expect(await netFor('inventory_audit', auditId, invCode), -275.0);

      await expectBalanced('inventory_audit', auditId);
    });

    test('zero variance → no entry, no movement', () async {
      final p = await seedProduct('AUD-Z', 40.0, 100.0);
      final auditId = await db.createStockAudit(userId: userId);
      await db.saveAuditItem(auditId: auditId, productId: p, actualQuantity: 100.0, expectedQuantity: 100.0);
      await db.finalizeAudit(auditId);

      expect(await jeCount('inventory_audit', auditId), 0);
      expect(await balance(p), 100.0);
      final moves = await (db.select(db.stockMovements)
            ..where((m) => m.referenceType.equals('inventory_audit') & m.referenceId.equals(auditId)))
          .get();
      expect(moves, isEmpty);
    });
  });

  // ═══ US2 — Cycle finalize atomic, cache-consistent, synced ═════════════
  group('US2 — cycle finalize atomicity + cache + gid', () {
    test('finalize updates stock cache and posts one settlement JE with gid', () async {
      final p = await seedProduct('CYC-A', 40.0, 100.0); // shortage 10 → 400
      final taskId = await makeCycleTask(warehouseId);
      final item = (await db.getCycleCountItems(taskId)).firstWhere((i) => i.productId == p);
      await db.submitCount(itemId: item.id, countedQty: 90.0);

      await db.finalizeCycleCountTask(taskId);

      // Cache parity: product.currentStock == per-warehouse balance (the bug the
      // old raw UPDATE left — it never touched currentStock).
      expect(await balance(p), 90.0);
      expect(await currentStock(p), 90.0);

      // One balanced settlement entry, valued at costPrice.
      expect(await jeCount('cycle_count', taskId), 1);
      expect(await netFor('cycle_count', taskId, shrinkCode), 400.0);
      expect(await netFor('cycle_count', taskId, invCode), -400.0);
      await expectBalanced('cycle_count', taskId);

      // Movement carries a globalId (reaches sync).
      final mv = await (db.select(db.stockMovements)
            ..where((m) => m.referenceType.equals('cycle_count') & m.referenceId.equals(taskId)))
          .get();
      expect(mv, isNotEmpty);
      expect(mv.first.globalId != null && mv.first.globalId!.isNotEmpty, isTrue);
    });

    test('failure at JE step rolls back stock + status (atomic)', () async {
      final p = await seedProduct('CYC-R', 40.0, 100.0);
      final taskId = await makeCycleTask(warehouseId);
      final item = (await db.getCycleCountItems(taskId)).firstWhere((i) => i.productId == p);
      await db.submitCount(itemId: item.id, countedQty: 90.0);

      // Force the JE step to fail: remove the inventory account (no fallback).
      await (db.delete(db.accountMappings)..where((m) => m.purpose.equals('inventory'))).go();
      await (db.delete(db.accounts)..where((a) => a.code.equals(invCode))).go();

      await expectLater(db.finalizeCycleCountTask(taskId), throwsA(isA<Exception>()));

      // Full rollback: stock unchanged, cache unchanged, task not completed, no JE.
      expect(await balance(p), 100.0);
      expect(await currentStock(p), 100.0);
      final task = await (db.select(db.cycleCountTasks)..where((t) => t.id.equals(taskId))).getSingle();
      expect(task.status, 'in_progress');
      expect(await jeCount('cycle_count', taskId), 0);
    });

    test('double finalize is idempotent (no second post)', () async {
      final p = await seedProduct('CYC-D', 40.0, 100.0);
      final taskId = await makeCycleTask(warehouseId);
      final item = (await db.getCycleCountItems(taskId)).firstWhere((i) => i.productId == p);
      await db.submitCount(itemId: item.id, countedQty: 90.0);

      await db.finalizeCycleCountTask(taskId);
      await db.finalizeCycleCountTask(taskId); // second call — task already completed

      expect(await balance(p), 90.0); // not applied twice
      expect(await jeCount('cycle_count', taskId), 1); // not posted twice
    });
  });

  // ═══ US3 — Both systems value on costPrice (not average_cost) ══════════
  group('US3 — cost basis parity', () {
    test('cycle and audit settle the same variance to the same costPrice value', () async {
      // costPrice 40, but per-warehouse average_cost forced to 30 → the two
      // must NOT diverge; both must use 40.
      final pc = await seedProduct('PAR-C', 40.0, 100.0);
      final pa = await seedProduct('PAR-A', 40.0, 100.0);
      await (db.update(db.inventoryBalances)
            ..where((x) => x.productId.equals(pc) & x.warehouseId.equals(warehouseId)))
          .write(const InventoryBalancesCompanion(averageCost: Value(30.0)));
      await (db.update(db.inventoryBalances)
            ..where((x) => x.productId.equals(pa) & x.warehouseId.equals(warehouseId)))
          .write(const InventoryBalancesCompanion(averageCost: Value(30.0)));

      // Cycle path: shortage 10.
      final taskId = await makeCycleTask(warehouseId);
      final item = (await db.getCycleCountItems(taskId)).firstWhere((i) => i.productId == pc);
      await db.submitCount(itemId: item.id, countedQty: 90.0);
      await db.finalizeCycleCountTask(taskId);

      // Audit path: shortage 10.
      final auditId = await db.createStockAudit(userId: userId);
      await db.saveAuditItem(auditId: auditId, productId: pa, actualQuantity: 90.0, expectedQuantity: 100.0);
      await db.finalizeAudit(auditId);

      final cycleShort = await netFor('cycle_count', taskId, shrinkCode);
      final auditShort = await netFor('inventory_audit', auditId, shrinkCode);
      expect(cycleShort, 400.0, reason: '10 × costPrice(40), not average_cost(30)=300');
      expect(auditShort, 400.0);
      expect(cycleShort, auditShort);
    });
  });
}
