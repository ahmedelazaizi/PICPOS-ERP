import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// E2E Test: Landed Cost + WAC Integration
/// Purchase → WAC Calculation → Second Purchase → WAC Update → Sale → Stock Verification
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int productId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    // Create supplier
    supplierId = await db.into(db.parties).insert(
      PartiesCompanion.insert(
        name: 'مورد اختبار',
        isCustomer: const Value(false),
        isSupplier: const Value(true),
      ),
    );

    // Create product with initial cost
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'LC-01',
        name: 'منتج بتكاليف إضافية',
        salePrice: const Value(200.0),
        costPrice: const Value(100.0),
        trackInventory: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  group('Landed Cost + WAC Integration', () {
    test('Purchase → WAC → Second Purchase → WAC Update', () async {
      // 1. Create initial purchase (10 units @ 100 each)
      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 1000.0,
        paymentMethod: 'cash',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10.0,
            unitCost: 100.0,
            total: 1000.0,
          ),
        ],
      );

      // 2. Verify initial WAC = 100.0
      final afterPurchase = await db.getProductById(productId);
      expect(afterPurchase!.costPrice, 100.0);

      // 3. Second purchase at different price (5 units @ 120)
      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 600.0,
        paymentMethod: 'cash',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5.0,
            unitCost: 120.0,
            total: 600.0,
          ),
        ],
      );

      // 4. Verify WAC updated: (10*100 + 5*120) / 15 = 1600/15 ≈ 106.67
      final afterSecondPurchase = await db.getProductById(productId);
      const expectedWac = (10 * 100.0 + 5 * 120.0) / 15;
      expect(
        afterSecondPurchase!.costPrice,
        closeTo(expectedWac, 0.01),
      );
    });

    test('WAC does not change after sale', () async {
      // Seed stock via purchase
      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 2000.0,
        paymentMethod: 'cash',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 20.0,
            unitCost: 100.0,
            total: 2000.0,
          ),
        ],
      );

      final beforeSale = await db.getProductById(productId);
      final wacBeforeSale = beforeSale!.costPrice;

      // Sell 5 units
      await db.createSalesInvoice(
        invoiceNumber: 'INV-LC-WAC',
        warehouseId: warehouseId,
        userId: 1,
        subtotal: 1000.0,
        discount: 0.0,
        tax: 0.0,
        total: 1000.0,
        paid: 1000.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5.0,
            unitPrice: 200.0,
            total: 1000.0,
          ),
        ],
      );

      // WAC should remain unchanged after sale
      final afterSale = await db.getProductById(productId);
      expect(afterSale!.costPrice, wacBeforeSale);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // S-COST (Spec 144): landed cost reaches COGS + balanced atomic JE + durable
  // ─────────────────────────────────────────────────────────────────────────
  group('Landed Cost Apply (S-COST 144)', () {
    /// Helper: purchase [qty]@[cost], then a sheet with the given cost items.
    Future<(int invoiceId, int sheetId)> seedSheet({
      required double qty,
      required double cost,
      required List<({double amount, int? supplier})> items,
    }) async {
      final invId = await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: qty * cost,
        paymentMethod: 'cash',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: qty,
            unitCost: cost,
            total: qty * cost,
          ),
        ],
      );
      final sheetId = await db.createLandedCostSheet(
        purchaseInvoiceId: invId,
        sheetNumber: 'LCS-$invId',
      );
      for (final it in items) {
        await db.addLandedCostItem(
          sheetId: sheetId,
          costType: 'shipping',
          description: 'شحن',
          amount: it.amount,
          supplierPartyId: it.supplier,
        );
      }
      await db.calculateAllocations(sheetId);
      return (invId, sheetId);
    }

    test('A. apply blends costPrice + average_cost (reaches COGS), value-add', () async {
      // 10 @ 100 (WAC=100), then 200 landed → (10*100 + 200)/10 = 120.
      final (_, sheetId) = await seedSheet(
        qty: 10, cost: 100, items: [(amount: 200.0, supplier: null)]);

      await db.applyLandedCost(sheetId);

      final p = await db.getProductById(productId);
      expect(p!.costPrice, closeTo(120.0, 0.001), reason: 'costPrice must reach COGS via value-add blend');

      final bal = await (db.select(db.inventoryBalances)
            ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId)))
          .getSingle();
      expect(bal.averageCost, closeTo(120.0, 0.001), reason: 'warehouse avg blended, not overwritten');
      expect(bal.quantity, 10.0, reason: 'landed cost adds value, not quantity');
    });

    test('B. posts one balanced JE, credit split by supplier vs cash', () async {
      // Two cost items: one cash (supplier null), one on the supplier (آجل).
      final (_, sheetId) = await seedSheet(
        qty: 10, cost: 100,
        items: [(amount: 100.0, supplier: null), (amount: 100.0, supplier: supplierId)]);

      await db.applyLandedCost(sheetId);

      final entries = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('landed_cost') & e.referenceId.equals(sheetId)))
          .get();
      expect(entries.length, 1, reason: 'exactly one JE per applied sheet');

      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(entries.first.id)))
          .get();
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, closeTo(200.0, 0.001));
      expect(totalCredit, closeTo(200.0, 0.001));
      expect(totalDebit, closeTo(totalCredit, 0.001), reason: 'balanced (R3/double-entry)');

      final creditLines = lines.where((l) => l.credit > 0).toList();
      expect(creditLines.length, 2, reason: 'split into cash + supplier-AP, not lumped');
      expect(entries.first.globalId, isNotNull, reason: 'FR-009 globalId threaded');
    });

    test('C. re-apply is idempotent (no second JE, no double blend)', () async {
      final (_, sheetId) = await seedSheet(
        qty: 10, cost: 100, items: [(amount: 200.0, supplier: null)]);

      await db.applyLandedCost(sheetId);
      final firstWac = (await db.getProductById(productId))!.costPrice;

      await db.applyLandedCost(sheetId); // second call — must be a no-op

      final secondWac = (await db.getProductById(productId))!.costPrice;
      expect(secondWac, firstWac, reason: 'no double blend on re-apply');

      final entries = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('landed_cost') & e.referenceId.equals(sheetId)))
          .get();
      expect(entries.length, 1, reason: 'no second JE');
    });

    test('D. recalculateProductWAC includes applied landed cost (FR-006)', () async {
      final (_, sheetId) = await seedSheet(
        qty: 10, cost: 100, items: [(amount: 200.0, supplier: null)]);
      await db.applyLandedCost(sheetId);

      // A return/adjustment path calls recalc — it must fold in the applied
      // landed cost, not reset to the raw purchase cost (100).
      // NOTE: full durability through purchase VOID/EDIT is S-COST-2 (those
      // paths delete/keep items differently and need JE reversal) — not here.
      await db.recalculateProductWAC(productId);

      final p = await db.getProductById(productId);
      expect(p!.costPrice, closeTo(120.0, 0.001),
          reason: 'recalc includes applied landed cost, not raw purchase cost 100');
    });

    test('E. edge: apply with zero on-hand stock does not divide by zero', () async {
      // Fresh product, no purchases → currentStock 0.
      final pid = await db.insertProduct(ProductsCompanion.insert(
        code: 'LC-ZERO', name: 'صنف بلا رصيد',
        costPrice: const Value(50.0), trackInventory: const Value(true)));

      await db.applyLandedCostToProductWAC(productId: pid, addedValue: 100.0);

      final p = await db.getProductById(pid);
      expect(p!.costPrice, 50.0, reason: 'no spread over 0 stock; WAC unchanged');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // S-COST-2 (Spec 145): landed-cost lifecycle on purchase void / edit
  // ─────────────────────────────────────────────────────────────────────────
  group('Landed Cost Lifecycle (S-COST-2 / 145)', () {
    test('void reverses the applied landed JE and un-applies the sheet', () async {
      // Credit purchase (paid 0) so void does not hit the paid-in-full gate.
      final invId = await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 0.0,
        paymentMethod: 'credit',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0, productId: productId,
            quantity: 10.0, unitCost: 100.0, total: 1000.0),
        ],
      );
      final sheetId = await db.createLandedCostSheet(
        purchaseInvoiceId: invId, sheetNumber: 'LCS-V$invId');
      await db.addLandedCostItem(
        sheetId: sheetId, costType: 'shipping', description: 'شحن', amount: 200.0);
      await db.calculateAllocations(sheetId);
      await db.applyLandedCost(sheetId);

      final original = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('landed_cost') & e.referenceId.equals(sheetId)))
          .getSingle();

      await db.voidPurchaseInvoice(invId, reason: 'اختبار', deletedBy: 1);

      // Reversal JE exists, balanced, and mirrors the original amount.
      final reversal = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('landed_cost_void') & e.referenceId.equals(sheetId)))
          .getSingle();
      final rLines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(reversal.id))).get();
      final oLines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(original.id))).get();
      final rDebit = rLines.fold<double>(0, (s, l) => s + l.debit);
      final rCredit = rLines.fold<double>(0, (s, l) => s + l.credit);
      final oDebit = oLines.fold<double>(0, (s, l) => s + l.debit);
      expect(rDebit, closeTo(rCredit, 0.001), reason: 'reversal balanced');
      expect(rCredit, closeTo(oDebit, 0.001),
          reason: 'reversal credits inventory by the original debit (net GL 0)');

      final sheet = await (db.select(db.landedCostSheets)
            ..where((s) => s.id.equals(sheetId))).getSingle();
      expect(sheet.status, 'voided', reason: 'sheet un-applied on void');
    });

    test('editing a purchase with an applied landed sheet is blocked', () async {
      final invId = await db.createPurchaseInvoice(
        supplierId: supplierId, warehouseId: warehouseId,
        paid: 1000.0, paymentMethod: 'cash',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0, productId: productId,
            quantity: 10.0, unitCost: 100.0, total: 1000.0),
        ],
      );
      final sheetId = await db.createLandedCostSheet(
        purchaseInvoiceId: invId, sheetNumber: 'LCS-E$invId');
      await db.addLandedCostItem(
        sheetId: sheetId, costType: 'shipping', description: 'شحن', amount: 200.0);
      await db.calculateAllocations(sheetId);
      await db.applyLandedCost(sheetId);

      // Must throw with the landed-specific message BEFORE deleting items
      // (would otherwise FK-crash in prod). userId:1 (admin) clears the
      // isLocked gate so we reach — and assert — the landed block specifically.
      await expectLater(
        db.updatePurchaseInvoice(
          invoiceId: invId,
          supplierId: supplierId,
          warehouseId: warehouseId,
          paid: 1000.0,
          paymentMethod: 'cash',
          userId: 1,
          items: [
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: invId, productId: productId,
              quantity: 12.0, unitCost: 100.0, total: 1200.0),
          ],
        ),
        throwsA(predicate(
            (e) => e.toString().contains('تكاليف محمّلة'))),
      );
    });

    test('editing is blocked even for a DRAFT sheet with persisted allocations', () async {
      // compute-then-cancel: calculateAllocations persists allocation rows (FK
      // pins the invoice's items) while the sheet stays 'draft' — must still block.
      final invId = await db.createPurchaseInvoice(
        supplierId: supplierId, warehouseId: warehouseId,
        paid: 1000.0, paymentMethod: 'cash',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0, productId: productId,
            quantity: 10.0, unitCost: 100.0, total: 1000.0),
        ],
      );
      final sheetId = await db.createLandedCostSheet(
        purchaseInvoiceId: invId, sheetNumber: 'LCS-D$invId');
      await db.addLandedCostItem(
        sheetId: sheetId, costType: 'shipping', description: 'شحن', amount: 200.0);
      await db.calculateAllocations(sheetId); // persists allocations; NO apply

      final sheet = await (db.select(db.landedCostSheets)
            ..where((s) => s.id.equals(sheetId))).getSingle();
      expect(sheet.status, 'draft', reason: 'sheet not applied');

      await expectLater(
        db.updatePurchaseInvoice(
          invoiceId: invId, supplierId: supplierId, warehouseId: warehouseId,
          paid: 1000.0, paymentMethod: 'cash', userId: 1,
          items: [
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: invId, productId: productId,
              quantity: 12.0, unitCost: 100.0, total: 1200.0),
          ],
        ),
        throwsA(predicate((e) => e.toString().contains('تكاليف محمّلة'))),
      );
    });
  });
}
