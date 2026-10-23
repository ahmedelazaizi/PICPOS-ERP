// ═══════════════════════════════════════════════════════════════════════════
// Selling a BOM item must book the raw materials it actually consumed.
// ═══════════════════════════════════════════════════════════════════════════
//
// A finished item assembled from a BOM (a meal, a kit) normally carries
// costPrice = 0 — its cost lives in the raw materials, and there is no
// production order to stamp a WAC onto it. `applyAutoDepleteForSale` takes the
// raw materials out of stock and hands the caller a `cogsBreakdown` describing
// exactly what left.
//
// The defect: `journal_entry_factory` derives `cogsTotal` from the INVOICE
// LINES only, then gates the ENTIRE COGS block — debit AND the breakdown
// credit legs — behind `cogsTotal > 0`. With costPrice = 0 that gate is
// closed, so the JE is just `Dr Cash / Cr Sales`. Balanced, therefore silent:
// no validator fires. Meanwhile the stock really did leave.
//
// The asymmetry is what makes it corrupting rather than merely incomplete:
// the RETURN path (accounting_autopost_dao `effectiveCogs`) does honour the
// raw-material cost. So sell-then-return leaves the inventory account
// permanently inflated and COGS sitting on a credit balance, even though the
// physical stock came back to exactly where it started.
//
// Second defect, same block: `legacyAmount = cogsTotal - breakdownTotal` goes
// NEGATIVE on any mixed invoice (one ordinary line + one BOM line) and is
// written straight into the ledger as `JournalLine(credit: negative)`.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
// CogsLine lives in manufacturing_dao.dart, which is a `part` of database.dart
// — importing the part directly does not compile.
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;
  late AccountingService svc;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
    svc = AccountingService(
      repo,
      _ThrowingPartiesRepo(),
      _ThrowingTreasuryRepo(),
      _ThrowingProductRepo(),
      _ThrowingInventoryRepo(),
      _ThrowingSettingsRepo(),
      _ThrowingAuditRepo(),
    );
  });

  tearDown(() async => db.close());

  Future<List<JournalEntryLine>> linesOfLastEntry() async {
    final entries = await repo.getJournalEntries();
    expect(entries, isNotEmpty, reason: 'the sale must post a journal entry');
    return (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entries.last.id)))
        .get();
  }

  // «سيخ كباب»: sells for 50, carries no book cost, made of 11.02 of raw
  // material per unit. Twelve of them = 600 revenue, 132.24 of stock gone.
  const mealUnitPrice = 50.0;
  const mealQty = 12.0;
  const mealRevenue = mealUnitPrice * mealQty; // 600
  const rawMaterialCost = 132.24;

  test('BOM meal with costPrice=0 still books the raw-material COGS', () async {
    final invAcc = await repo.getLeafAccountByPurpose('inventory');
    final cogsAcc = await repo.getLeafAccountByPurpose('cogs');
    expect(invAcc, isNotNull);
    expect(cogsAcc, isNotNull);

    await svc.generateSalesAccountingEntry(
      invoiceId: 900,
      invNumber: 'BOM-COGS-1',
      tax: 0,
      paid: mealRevenue,
      remaining: 0,
      paymentMethod: 'cash',
      deliveryFee: 0,
      items: [
        const SalesInvoiceItem(
          id: 1, invoiceId: 900, productId: 7,
          quantity: mealQty, unitPrice: mealUnitPrice, discount: 0,
          total: mealRevenue,
          costPrice: 0, // ← the finished meal has no book cost
          sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 1,
          rowVersion: 0,
        ),
      ],
      cogsBreakdown: [
        CogsLine(
          rawMaterialId: 8,
          inventoryAccountId: invAcc!.id,
          totalCost: rawMaterialCost,
        ),
      ],
    );

    final lines = await linesOfLastEntry();

    final inventoryCredit = lines
        .where((l) => l.accountId == invAcc.id)
        .fold<double>(0, (s, l) => s + l.credit);
    expect(inventoryCredit, closeTo(rawMaterialCost, 0.001),
        reason: 'the raw materials physically left stock — the inventory '
            'account must be credited for them');

    final cogsDebit = lines
        .where((l) => l.accountId == cogsAcc!.id)
        .fold<double>(0, (s, l) => s + l.debit);
    expect(cogsDebit, closeTo(rawMaterialCost, 0.001),
        reason: 'gross profit is 600 - 132.24, not 600. Without this the '
            'meal looks 100% margin and income tax is computed on it');
  });

  test('mixed invoice never writes a negative credit into the ledger',
      () async {
    final invAcc = await repo.getLeafAccountByPurpose('inventory');

    // One ordinary line costing 10, plus the BOM meal. cogsTotal (10) is
    // smaller than breakdownTotal (132.24) → legacyAmount = -122.24.
    await svc.generateSalesAccountingEntry(
      invoiceId: 901,
      invNumber: 'BOM-COGS-2',
      tax: 0,
      paid: mealRevenue + 40,
      remaining: 0,
      paymentMethod: 'cash',
      deliveryFee: 0,
      items: [
        const SalesInvoiceItem(
          id: 1, invoiceId: 901, productId: 3,
          quantity: 1, unitPrice: 40, discount: 0, total: 40,
          costPrice: 10, sortOrder: 0, taxRate: 0, taxAmount: 0,
          quantityInBase: 1, rowVersion: 0,
        ),
        const SalesInvoiceItem(
          id: 2, invoiceId: 901, productId: 7,
          quantity: mealQty, unitPrice: mealUnitPrice, discount: 0,
          total: mealRevenue,
          costPrice: 0, sortOrder: 1, taxRate: 0, taxAmount: 0,
          quantityInBase: 1, rowVersion: 0,
        ),
      ],
      cogsBreakdown: [
        CogsLine(
          rawMaterialId: 8,
          inventoryAccountId: invAcc!.id,
          totalCost: rawMaterialCost,
        ),
      ],
    );

    final lines = await linesOfLastEntry();

    expect(lines.where((l) => l.debit < 0 || l.credit < 0), isEmpty,
        reason: 'a negative amount on a journal line corrupts every report '
            'that reads the debit/credit columns directly — the sign, not '
            'the arithmetic, is the bug');

    // And the books must still balance, with BOTH costs recognised.
    final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
    final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
    expect(totalDebit, closeTo(totalCredit, 0.001));

    final inventoryCredit = lines
        .where((l) => l.accountId == invAcc.id)
        .fold<double>(0, (s, l) => s + l.credit);
    expect(inventoryCredit, closeTo(10 + rawMaterialCost, 0.001),
        reason: 'both the ordinary line cost and the raw materials left '
            'stock — the inventory credit is the sum, not the difference');
  });

  test('a tracked BOM item with a book cost is NOT charged twice', () async {
    // The failure mode introduced by a naive fix: if `cogsTotal` keeps
    // counting a line whose raw materials the breakdown already covers, the
    // finished good and its inputs are both expensed. `autoDepletedItemIds`
    // is what stops that.
    final invAcc = await repo.getLeafAccountByPurpose('inventory');
    final cogsAcc = await repo.getLeafAccountByPurpose('cogs');

    await svc.generateSalesAccountingEntry(
      invoiceId: 903,
      invNumber: 'BOM-COGS-4',
      tax: 0,
      paid: mealRevenue,
      remaining: 0,
      paymentMethod: 'cash',
      deliveryFee: 0,
      items: [
        const SalesInvoiceItem(
          id: 5, invoiceId: 903, productId: 7,
          quantity: mealQty, unitPrice: mealUnitPrice, discount: 0,
          total: mealRevenue,
          // 20 × 12 = 240, deliberately ≠ 132.24 so the assertion can tell
          // "raw materials only" apart from "raw materials + finished good".
          costPrice: 20,
          sortOrder: 0, taxRate: 0, taxAmount: 0, quantityInBase: 1,
          rowVersion: 0,
        ),
      ],
      cogsBreakdown: [
        CogsLine(
          rawMaterialId: 8,
          inventoryAccountId: invAcc!.id,
          totalCost: rawMaterialCost,
        ),
      ],
      autoDepletedItemIds: const {5},
    );

    final lines = await linesOfLastEntry();
    final cogsDebit = lines
        .where((l) => l.accountId == cogsAcc!.id)
        .fold<double>(0, (s, l) => s + l.debit);
    expect(cogsDebit, closeTo(rawMaterialCost, 0.001),
        reason: 'only the raw materials are expensed — adding the finished '
            'item\'s own 132.24 on top would double the cost of goods sold');
  });

  test('legacy single-account path is untouched when there is no breakdown',
      () async {
    // Constitution I — a sale with no auto-deplete BOM must produce exactly
    // the JE it produced before this fix. This is the regression guard.
    final invAcc = await repo.getLeafAccountByPurpose('inventory');

    await svc.generateSalesAccountingEntry(
      invoiceId: 902,
      invNumber: 'BOM-COGS-3',
      tax: 0,
      paid: 500,
      remaining: 0,
      paymentMethod: 'cash',
      deliveryFee: 0,
      items: [
        const SalesInvoiceItem(
          id: 1, invoiceId: 902, productId: 1,
          quantity: 5, unitPrice: 100, discount: 0, total: 500,
          costPrice: 60, sortOrder: 0, taxRate: 0, taxAmount: 0,
          quantityInBase: 1, rowVersion: 0,
        ),
      ],
      // no cogsBreakdown
    );

    final lines = await linesOfLastEntry();
    final inventoryCredit = lines
        .where((l) => l.accountId == invAcc!.id)
        .fold<double>(0, (s, l) => s + l.credit);
    expect(inventoryCredit, closeTo(300, 0.001),
        reason: '5 × 60 on the legacy path, unchanged');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // SERVER PATH — same defect, different code
  // ═════════════════════════════════════════════════════════════════════════
  //
  // The client/standalone flow builds its JE with JournalEntryFactory (fixed
  // above). The SERVER flow (api_sales_handler → autoPostCashSale) computes
  // COGS from `sales_invoice_items.cost_price` alone, behind the same `> 0`
  // gate — so on a client/server topology the fix above covers only half the
  // deployments. autoPostCashSale now reads `sale_bom_consumptions`, which
  // applyAutoDepleteForSale writes in the same transaction.

  group('server path (autoPostCashSale)', () {
    late int warehouseId;
    late int mealProductId;
    late int rawProductId;
    late int bomId;

    Future<int> seedSale({required double finishedCostPrice}) async {
      warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'WH-SRV',
              isDefault: const Value(true),
              globalId: Value('gid-wh-srv-${DateTime.now().microsecond}'),
            ),
          );
      await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'Safe-SRV',
              safeType: const Value('cash'),
              isDefault: const Value(true),
              globalId: Value('gid-safe-srv-${DateTime.now().microsecond}'),
            ),
          );
      mealProductId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'MEAL-SRV-${DateTime.now().microsecondsSinceEpoch}',
              name: 'سيخ كباب',
              trackInventory: const Value(false),
            ),
          );
      rawProductId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'RAW-SRV-${DateTime.now().microsecondsSinceEpoch}',
              name: 'لحمة',
              trackInventory: const Value(true),
            ),
          );
      bomId = await db.into(db.billOfMaterials).insert(
            BillOfMaterialsCompanion.insert(
              finishedProductId: mealProductId,
              bomCode: 'BOM-SRV-${DateTime.now().microsecondsSinceEpoch}',
              autoDepleteOnSale: const Value(true),
            ),
          );

      final invoiceId = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'SRV-${DateTime.now().microsecondsSinceEpoch}',
              warehouseId: warehouseId,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(mealRevenue),
              total: const Value(mealRevenue),
              paid: const Value(mealRevenue),
              paymentMethod: const Value('cash'),
            ),
          );
      final itemId = await db.into(db.salesInvoiceItems).insert(
            SalesInvoiceItemsCompanion.insert(
              invoiceId: invoiceId,
              productId: mealProductId,
              quantity: mealQty,
              unitPrice: mealUnitPrice,
              total: mealRevenue,
              costPrice: Value(finishedCostPrice),
            ),
          );
      // What applyAutoDepleteForSale persists after taking the raws out.
      await db.into(db.saleBomConsumptions).insert(
            SaleBomConsumptionsCompanion.insert(
              saleInvoiceId: invoiceId,
              saleInvoiceItemId: itemId,
              bomId: bomId,
              rawMaterialId: rawProductId,
              consumedQty: mealQty,
              unitCostAtSale: rawMaterialCost / mealQty,
              warehouseId: warehouseId,
              globalId: 'gid-cons-${DateTime.now().microsecondsSinceEpoch}',
            ),
          );
      return invoiceId;
    }

    test('books the consumed raw materials even when the meal costs 0',
        () async {
      final invoiceId = await seedSale(finishedCostPrice: 0);
      final sale = await db.getSalesInvoiceById(invoiceId);
      await db.autoPostCashSale(sale!);

      final cogsAcc = await repo.getLeafAccountByPurpose('cogs');
      final lines = await linesOfLastEntry();
      final cogsDebit = lines
          .where((l) => l.accountId == cogsAcc!.id)
          .fold<double>(0, (s, l) => s + l.debit);
      expect(cogsDebit, closeTo(rawMaterialCost, 0.01),
          reason: 'the server must recognise the same cost the client does — '
              'otherwise a client/server deployment books different books '
              'for the same sale');
    });

    test('does not double-count a tracked finished item', () async {
      // Same sale, but the meal DOES carry a book cost. Only the raw
      // materials may be expensed — the consumption row supersedes the line.
      //
      // 20/unit is chosen so 12 × 20 = 240 is clearly distinguishable from
      // the 132.24 of raw material. An earlier draft used 11.02/unit, whose
      // total happens to EQUAL 132.24 — the test passed with the fix removed,
      // i.e. it proved nothing. Fixture numbers have to be able to disagree.
      final invoiceId = await seedSale(finishedCostPrice: 20);
      final sale = await db.getSalesInvoiceById(invoiceId);
      await db.autoPostCashSale(sale!);

      final cogsAcc = await repo.getLeafAccountByPurpose('cogs');
      final lines = await linesOfLastEntry();
      final cogsDebit = lines
          .where((l) => l.accountId == cogsAcc!.id)
          .fold<double>(0, (s, l) => s + l.debit);
      expect(cogsDebit, closeTo(rawMaterialCost, 0.01),
          reason: 'adding the line cost on top would expense the goods twice');
    });
  });
}

// ── Collaborator stubs (same pattern as accounting_double_entry_test) ───────

class _ThrowingPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _ThrowingTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _ThrowingProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _ThrowingInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _ThrowingSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _ThrowingAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}
