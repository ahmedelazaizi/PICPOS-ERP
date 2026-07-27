// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 Track-3 — DB-level branch-scope cap on 6 report DAO methods
// ═══════════════════════════════════════════════════════════════════════════
//
// Track-3 added an `allowedBranchIds` authoritative branch ceiling to six
// report DAO methods that previously filtered by branch on the UI only (or had
// no branch dimension at all), so a branch-restricted user could pull EVERY
// branch's rows straight from the report screen. Each method now enforces the
// same three-way contract (mirrors BranchScope in
// lib/data/providers/branch_scope_provider.dart and the FIL-2 fix tested in
// test/unit/spec_149_b12_branch_scope_leak_test.dart):
//
//   allowedBranchIds == null   → no restriction (full access)
//   allowedBranchIds == {}     → match NOTHING (fail-closed / defensive)
//   allowedBranchIds == {ids}  → branch_id IN (ids) OR branch_id IS NULL
//                                (NULL = global / head-office rows stay visible)
//
// The 6 methods and their branch columns:
//   1. getSalesReturns              → salesInvoices.branchId   (sales_dao)
//   2. getPurchasesForDateRange     → purchaseInvoices.branchId(purchase_dao)
//   3. getDeliveryReport            → salesInvoices.branchId   (delivery_dao)
//   4. getShiftsReportPaginated     → shifts.branchId          (treasury_dao)
//   5. getConsumptionReport         → sale_bom_consumptions.branch_id (mfg_dao)
//   6. getProductProfitabilityReport→ sales_invoices.branch_id (mfg_dao)
//
// NULL-branch rows are inserted DIRECTLY (branchId omitted / Value.absent) so
// they genuinely carry a NULL branch_id — no create-helper that auto-resolves a
// fallback branch is used (see spec_149_b12 note, lines 75-91). FK enforcement
// is OFF in the in-memory test DB (NativeDatabase.memory sets no foreign_keys
// pragma), so bare rows with dummy warehouseId/userId/supplierId/bomId suffice.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branch1;
  late int branch2;
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    branch1 = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع 1 — T3',
            globalId: const Value('gid-br1-t3'),
          ),
        );
    branch2 = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع 2 — T3',
            globalId: const Value('gid-br2-t3'),
          ),
        );
  });

  tearDown(() => db.close());

  // ───────────────────────────────────────────────────────────────────────
  // 1. getSalesReturns — salesInvoices.branchId
  // ───────────────────────────────────────────────────────────────────────
  group('getSalesReturns branch-scope cap', () {
    setUp(() async {
      // saleType == 'return' rows in branch1 / branch2 / NULL-branch.
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'SR-B1',
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 2, 1),
            saleType: const Value('return'),
            branchId: Value(branch1),
            total: const Value(-100),
          ));
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'SR-B2',
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 2, 2),
            saleType: const Value('return'),
            branchId: Value(branch2),
            total: const Value(-200),
          ));
      // NULL-branch (global / head-office) return — branchId omitted.
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'SR-G',
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 2, 3),
            saleType: const Value('return'),
            total: const Value(-50),
          ));
    });

    test('{branch1} → own-branch + NULL only, branch2 excluded', () async {
      final rows =
          await db.getSalesReturns(from, to, allowedBranchIds: {branch1});
      final nums = rows.map((r) => r.invoiceNumber).toSet();
      expect(nums, contains('SR-B1'));
      expect(nums, contains('SR-G'), reason: 'NULL-branch stays visible');
      expect(nums, isNot(contains('SR-B2')),
          reason: 'branch-2 return must NOT leak to a branch-1 user');
    });

    test('null → full access, all three returns', () async {
      final rows = await db.getSalesReturns(from, to);
      final nums = rows.map((r) => r.invoiceNumber).toSet();
      expect(nums, containsAll(<String>['SR-B1', 'SR-B2', 'SR-G']));
    });

    test('{} (empty) → fail-closed, nothing', () async {
      final rows =
          await db.getSalesReturns(from, to, allowedBranchIds: <int>{});
      expect(rows, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 2. getPurchasesForDateRange — purchaseInvoices.branchId
  // ───────────────────────────────────────────────────────────────────────
  group('getPurchasesForDateRange branch-scope cap', () {
    setUp(() async {
      await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'PU-B1',
            supplierId: 1,
            warehouseId: 1,
            invoiceDate: DateTime(2026, 2, 1),
            branchId: Value(branch1),
            total: const Value(100),
          ));
      await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'PU-B2',
            supplierId: 1,
            warehouseId: 1,
            invoiceDate: DateTime(2026, 2, 2),
            branchId: Value(branch2),
            total: const Value(200),
          ));
      // NULL-branch purchase — branchId omitted.
      await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'PU-G',
            supplierId: 1,
            warehouseId: 1,
            invoiceDate: DateTime(2026, 2, 3),
            total: const Value(50),
          ));
    });

    test('{branch1} → own-branch + NULL only, branch2 excluded', () async {
      final rows = await db.getPurchasesForDateRange(from, to,
          allowedBranchIds: {branch1});
      final nums = rows.map((r) => r.invoiceNumber).toSet();
      expect(nums, contains('PU-B1'));
      expect(nums, contains('PU-G'), reason: 'NULL-branch stays visible');
      expect(nums, isNot(contains('PU-B2')),
          reason: 'branch-2 purchase must NOT leak to a branch-1 user');
    });

    test('null → full access, all three purchases', () async {
      final rows = await db.getPurchasesForDateRange(from, to);
      final nums = rows.map((r) => r.invoiceNumber).toSet();
      expect(nums, containsAll(<String>['PU-B1', 'PU-B2', 'PU-G']));
    });

    test('{} (empty) → fail-closed, nothing', () async {
      final rows = await db.getPurchasesForDateRange(from, to,
          allowedBranchIds: <int>{});
      expect(rows, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 3. getDeliveryReport — salesInvoices.branchId (rows w/ deliveryStatus)
  // ───────────────────────────────────────────────────────────────────────
  group('getDeliveryReport branch-scope cap', () {
    setUp(() async {
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'DL-B1',
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 2, 1),
            deliveryStatus: const Value('pending'),
            branchId: Value(branch1),
          ));
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'DL-B2',
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 2, 2),
            deliveryStatus: const Value('shipped'),
            branchId: Value(branch2),
          ));
      // NULL-branch delivery invoice — branchId omitted.
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'DL-G',
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 2, 3),
            deliveryStatus: const Value('delivered'),
          ));
    });

    test('{branch1} → own-branch + NULL only, branch2 excluded', () async {
      final rows = await db.getDeliveryReport(
          from: from, to: to, allowedBranchIds: {branch1});
      final nums =
          rows.map((r) => (r['invoice'] as SalesInvoiceData).invoiceNumber).toSet();
      expect(nums, contains('DL-B1'));
      expect(nums, contains('DL-G'), reason: 'NULL-branch stays visible');
      expect(nums, isNot(contains('DL-B2')),
          reason: 'branch-2 delivery must NOT leak to a branch-1 user');
    });

    test('null → full access, all three delivery invoices', () async {
      final rows = await db.getDeliveryReport(from: from, to: to);
      final nums =
          rows.map((r) => (r['invoice'] as SalesInvoiceData).invoiceNumber).toSet();
      expect(nums, containsAll(<String>['DL-B1', 'DL-B2', 'DL-G']));
    });

    test('{} (empty) → fail-closed, nothing', () async {
      final rows = await db.getDeliveryReport(
          from: from, to: to, allowedBranchIds: <int>{});
      expect(rows, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 4. getShiftsReportPaginated — shifts.branchId (inner-joins users)
  // ───────────────────────────────────────────────────────────────────────
  group('getShiftsReportPaginated branch-scope cap', () {
    late int shiftB1;
    late int shiftB2;
    late int shiftG;

    setUp(() async {
      // The report INNER JOINs users on shifts.userId — seed one user.
      final userId = await db.into(db.users).insert(UsersCompanion.insert(
            username: 'cashier_t3',
            passwordHash: 'x',
            displayName: 'كاشير T3',
          ));
      shiftB1 = await db.into(db.shifts).insert(ShiftsCompanion.insert(
            startTime: DateTime(2026, 2, 1, 8),
            userId: userId,
            status: 'closed',
            branchId: Value(branch1),
          ));
      shiftB2 = await db.into(db.shifts).insert(ShiftsCompanion.insert(
            startTime: DateTime(2026, 2, 2, 8),
            userId: userId,
            status: 'closed',
            branchId: Value(branch2),
          ));
      // NULL-branch (legacy/shared) shift — branchId omitted.
      shiftG = await db.into(db.shifts).insert(ShiftsCompanion.insert(
            startTime: DateTime(2026, 2, 3, 8),
            userId: userId,
            status: 'closed',
          ));
    });

    test('{branch1} → own-branch + NULL only, branch2 excluded', () async {
      final rows = await db.getShiftsReportPaginated(
          startDate: from, endDate: to, allowedBranchIds: {branch1});
      final ids = rows.map((r) => r.id).toSet();
      expect(ids, contains(shiftB1));
      expect(ids, contains(shiftG), reason: 'NULL-branch stays visible');
      expect(ids, isNot(contains(shiftB2)),
          reason: 'branch-2 shift must NOT leak to a branch-1 user');
    });

    test('null → full access, all three shifts', () async {
      final rows =
          await db.getShiftsReportPaginated(startDate: from, endDate: to);
      final ids = rows.map((r) => r.id).toSet();
      expect(ids, containsAll(<int>[shiftB1, shiftB2, shiftG]));
    });

    test('{} (empty) → fail-closed, nothing', () async {
      final rows = await db.getShiftsReportPaginated(
          startDate: from, endDate: to, allowedBranchIds: <int>{});
      expect(rows, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 5. getConsumptionReport — sale_bom_consumptions.branch_id
  //    Aggregated by raw_material_id → use a DISTINCT raw material per branch
  //    so each branch surfaces as its own result row (INNER JOIN products).
  // ───────────────────────────────────────────────────────────────────────
  group('getConsumptionReport branch-scope cap', () {
    late int rm1;
    late int rm2;
    late int rmG;
    late int cInvId;
    late int cItemId;
    late int cBomId;
    final cFrom = DateTime(2026, 1, 1);
    final cTo = DateTime(2026, 12, 31);

    Future<void> seedConsumption({
      required int rawMaterialId,
      required String gid,
      int? branchId,
    }) async {
      await db.into(db.saleBomConsumptions).insert(
          SaleBomConsumptionsCompanion.insert(
            // FK enforced now — reference the shared (report-irrelevant) parents
            // seeded in setUp; getConsumptionReport aggregates by
            // raw_material_id and never joins these.
            saleInvoiceId: cInvId,
            saleInvoiceItemId: cItemId,
            bomId: cBomId,
            rawMaterialId: rawMaterialId,
            consumedQty: 5,
            unitCostAtSale: 2,
            warehouseId: 1,
            globalId: gid,
            branchId: branchId == null ? const Value.absent() : Value(branchId),
            createdAt: Value(DateTime(2026, 2, 5)),
          ));
    }

    setUp(() async {
      // Each raw material needs a products row (INNER JOIN products p).
      rm1 = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'RM1', name: 'خام 1'));
      rm2 = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'RM2', name: 'خام 2'));
      rmG = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'RMG', name: 'خام عام'));

      // Shared (report-irrelevant) FK parents for the consumption rows.
      cInvId = await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'C-INV',
          warehouseId: 1,
          userId: 1,
          invoiceDate: DateTime(2026, 2, 5)));
      cItemId = await db.into(db.salesInvoiceItems).insert(
          SalesInvoiceItemsCompanion.insert(
              invoiceId: cInvId,
              productId: rm1,
              quantity: 1,
              unitPrice: 1,
              total: 1));
      cBomId = await db.into(db.billOfMaterials).insert(
          BillOfMaterialsCompanion.insert(finishedProductId: rm1, bomCode: 'C-BOM'));

      await seedConsumption(rawMaterialId: rm1, gid: 'c-b1', branchId: branch1);
      await seedConsumption(rawMaterialId: rm2, gid: 'c-b2', branchId: branch2);
      // NULL-branch consumption — branchId omitted.
      await seedConsumption(rawMaterialId: rmG, gid: 'c-g');
    });

    test('{branch1} → own-branch + NULL only, branch2 excluded', () async {
      final rows = await db.getConsumptionReport(
          fromDate: cFrom, toDate: cTo, allowedBranchIds: {branch1});
      final ids = rows.map((r) => r.rawMaterialId).toSet();
      expect(ids, contains(rm1));
      expect(ids, contains(rmG), reason: 'NULL-branch stays visible');
      expect(ids, isNot(contains(rm2)),
          reason: 'branch-2 consumption must NOT leak to a branch-1 user');
    });

    test('null → full access, all three raw materials', () async {
      final rows =
          await db.getConsumptionReport(fromDate: cFrom, toDate: cTo);
      final ids = rows.map((r) => r.rawMaterialId).toSet();
      expect(ids, containsAll(<int>[rm1, rm2, rmG]));
    });

    test('{} (empty) → fail-closed, nothing', () async {
      final rows = await db.getConsumptionReport(
          fromDate: cFrom, toDate: cTo, allowedBranchIds: <int>{});
      expect(rows, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 6. getProductProfitabilityReport — sales_invoices.branch_id
  //    Rows require a matching sale_bom_consumption per invoice-item
  //    (HAVING SUM(c.consumed_qty) IS NOT NULL). One DISTINCT finished
  //    product per branch so each surfaces as its own result row.
  // ───────────────────────────────────────────────────────────────────────
  group('getProductProfitabilityReport branch-scope cap', () {
    late int fp1;
    late int fp2;
    late int fpG;
    late int pBomId;
    final pFrom = DateTime(2026, 1, 1);
    final pTo = DateTime(2026, 12, 31);

    // Seeds one sales invoice + item + BOM-consumption chain for [productId],
    // so the finished product appears in the profitability aggregate.
    Future<void> seedProfitChain({
      required int productId,
      required String invNo,
      required String gid,
      int? branchId,
    }) async {
      final invId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: invNo,
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 2, 5),
            branchId:
                branchId == null ? const Value.absent() : Value(branchId),
            total: const Value(100),
          ));
      final itemId = await db.into(db.salesInvoiceItems).insert(
          SalesInvoiceItemsCompanion.insert(
            invoiceId: invId,
            productId: productId,
            quantity: 3,
            unitPrice: 10,
            total: 30,
          ));
      await db.into(db.saleBomConsumptions).insert(
          SaleBomConsumptionsCompanion.insert(
            saleInvoiceId: invId,
            saleInvoiceItemId: itemId, // links c.sale_invoice_item_id = sii.id
            bomId: pBomId, // FK enforced now — shared bom seeded in setUp
            rawMaterialId: fp1, // any real product; not joined against here
            consumedQty: 2,
            unitCostAtSale: 3,
            warehouseId: 1,
            globalId: gid,
          ));
    }

    setUp(() async {
      // INNER JOIN products p ON p.id = sii.product_id → each needs a row.
      fp1 = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'FP1', name: 'منتج 1'));
      fp2 = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'FP2', name: 'منتج 2'));
      fpG = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'FPG', name: 'منتج عام'));

      // Shared (report-irrelevant) bom for the consumption rows.
      pBomId = await db.into(db.billOfMaterials).insert(
          BillOfMaterialsCompanion.insert(finishedProductId: fp1, bomCode: 'PF-BOM'));

      await seedProfitChain(
          productId: fp1, invNo: 'PF-B1', gid: 'pf-b1', branchId: branch1);
      await seedProfitChain(
          productId: fp2, invNo: 'PF-B2', gid: 'pf-b2', branchId: branch2);
      // NULL-branch invoice — branchId omitted.
      await seedProfitChain(productId: fpG, invNo: 'PF-G', gid: 'pf-g');
    });

    test('{branch1} → own-branch + NULL only, branch2 excluded', () async {
      final rows = await db.getProductProfitabilityReport(
          fromDate: pFrom, toDate: pTo, allowedBranchIds: {branch1});
      final ids = rows.map((r) => r.productId).toSet();
      expect(ids, contains(fp1));
      expect(ids, contains(fpG), reason: 'NULL-branch stays visible');
      expect(ids, isNot(contains(fp2)),
          reason: 'branch-2 product profit must NOT leak to a branch-1 user');
    });

    test('null → full access, all three products', () async {
      final rows = await db.getProductProfitabilityReport(
          fromDate: pFrom, toDate: pTo);
      final ids = rows.map((r) => r.productId).toSet();
      expect(ids, containsAll(<int>[fp1, fp2, fpG]));
    });

    test('{} (empty) → fail-closed, nothing', () async {
      final rows = await db.getProductProfitabilityReport(
          fromDate: pFrom, toDate: pTo, allowedBranchIds: <int>{});
      expect(rows, isEmpty);
    });
  });
}
