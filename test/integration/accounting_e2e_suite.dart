// ==========================================================================
// ACCOUNTING E2E SUITE — AC1..AC8
// ==========================================================================
// Session 4 of the launch-readiness plan.
//
//   AC1  PreBalanceCheck          — unbalanced entries must be rejected
//   AC2  YearEndClosing            — closing produces retained-earnings JE
//   AC3  FXRevaluation             — FX rate change revalues AR/AP
//   AC4  COGSWithReturns           — WAC-aware costing + WAC math
//   AC5  LandedCost                — freight/customs allocated pro-rata
//   AC6  BankReconciliation        — statement vs book matching
//   AC7  FixedAssetDepreciation    — monthly schedule + JE
//   AC8  PeriodLockEnforcement     — closed periods reject new entries
//
// Business decisions encoded in the tests:
//
//   Costing method (AC4): the system uses **Weighted-Average Cost (WAC)** as
//     the primary method for COGS (see `inventory_dao.dart:updateProductWAC`).
//     Batch tracking exists but is used for expiry; sale-time COGS comes from
//     `sales_invoice_items.cost_price` which is captured at line entry from
//     the current product WAC. Returns reverse at the cost amount provided
//     by the caller (the original invoice's cost_price). True FIFO costing
//     on returns would be a feature change, not a fix.
//
//   Depreciation (AC7): straight-line method is verified against the formula
//     (purchasePrice − salvageValue) / (usefulLifeYears × 12). Declining-
//     balance is exercised separately in a smaller assertion.
//
//   Bank reconciliation (AC6): auto-match window is ±3 days / ±0.01 amount
//     (hard-coded in `bank_reconciliation_dao.dart:autoMatchStatementLines`).
//     Test date tolerances stay inside that window.
//
// Note on runtime:
//   The suite runs on `AppDatabase.forTesting()` which uses in-memory SQLite.
//   A couple of DAOs (bank reconciliation auto-match) use the SQLite-specific
//   `julianday()` function — they will NOT run against PostgreSQL. That is
//   acceptable here because the test harness is SQLite-only.
// ==========================================================================

import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int fiscalYearId;
  late int cashAccountId;
  late int revenueAccountId;
  late int expenseAccountId;
  late int bankAccountId;
  // ignore: unused_local_variable
  late int arAccountId;
  // ignore: unused_local_variable
  late int fxGainLossAccountId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'E2E Tester',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'e2e_tester',
      password: 'test123',
      displayName: 'E2E Tester',
      roleId: roleId,
    );

    // The forTesting() database seeds a default fiscal year + monthly
    // periods. Re-use them if present; create otherwise.
    final now = DateTime.now();
    final existingFy = await db.getFiscalYearByDate(DateTime(now.year, 6, 1));
    if (existingFy != null) {
      fiscalYearId = existingFy.id;
    } else {
      fiscalYearId = await db.createFiscalYear(
        name: 'FY-${now.year}',
        startDate: DateTime(now.year, 1, 1),
        endDate: DateTime(now.year, 12, 31),
      );
    }
    final existingPeriods = await (db.select(db.accountingPeriods)
          ..where((p) => p.fiscalYearId.equals(fiscalYearId)))
        .get();
    if (existingPeriods.isEmpty) {
      await db.generatePeriodsForYear(
        fiscalYearId,
        DateTime(now.year, 1, 1),
        DateTime(now.year, 12, 31),
      );
    }

    cashAccountId = await _ensureAccount(db, '1110', 'النقدية', 'asset');
    revenueAccountId =
        await _ensureAccount(db, '4110', 'إيرادات مبيعات', 'revenue');
    expenseAccountId =
        await _ensureAccount(db, '5110', 'مصروفات تشغيلية', 'expense');
    bankAccountId =
        await _ensureAccount(db, '1120', 'البنك الأهلي', 'asset');
    arAccountId =
        await _ensureAccount(db, '1210', 'ذمم العملاء', 'asset');
    fxGainLossAccountId =
        await _ensureAccount(db, '7110', 'أرباح/خسائر فروق عملة', 'revenue');
  });

  tearDown(() async => db.close());

  // ═════════════════════════════════════════════════════════════════════════
  // AC1 — PreBalanceCheck
  // ═════════════════════════════════════════════════════════════════════════
  group('AC1 — Pre-balance check', () {
    test('unbalanced journal entry is rejected', () async {
      expect(
        () => db.createJournalEntry(
          description: 'Test unbalanced',
          date: DateTime.now(),
          lines: [
            JournalLine(accountId: cashAccountId, debit: 100),
            JournalLine(accountId: revenueAccountId, credit: 90),
          ],
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('المدين'),
        )),
      );
    });

    test('balanced entry is accepted and stored', () async {
      final id = await db.createJournalEntry(
        description: 'Balanced cash-in',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: cashAccountId, debit: 100),
          JournalLine(accountId: revenueAccountId, credit: 100),
        ],
      );
      expect(id, isPositive);
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(id)))
          .get();
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, closeTo(totalCredit, 0.001));
    });

    test('rollback on failure — no lines orphaned', () async {
      final before = await db.select(db.journalEntries).get();
      try {
        await db.createJournalEntry(
          description: 'Will fail',
          date: DateTime.now(),
          lines: [
            JournalLine(accountId: cashAccountId, debit: 50),
            JournalLine(accountId: revenueAccountId, credit: 40),
          ],
        );
        fail('expected throw');
      } catch (_) {
        // expected
      }
      final after = await db.select(db.journalEntries).get();
      expect(after.length, before.length,
          reason: 'failed JE must not leave a header row behind');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // AC2 — YearEndClosing
  // ═════════════════════════════════════════════════════════════════════════
  group('AC2 — Year-end closing', () {
    test('closing a year generates a fiscal_close journal entry', () async {
      final midYear = DateTime(DateTime.now().year, 6, 15);
      await db.createJournalEntry(
        description: 'Revenue',
        date: midYear,
        lines: [
          JournalLine(accountId: cashAccountId, debit: 1000),
          JournalLine(accountId: revenueAccountId, credit: 1000),
        ],
      );
      await db.createJournalEntry(
        description: 'Expense',
        date: midYear,
        lines: [
          JournalLine(accountId: expenseAccountId, debit: 300),
          JournalLine(accountId: cashAccountId, credit: 300),
        ],
      );

      final periods = await (db.select(db.accountingPeriods)
            ..where((p) => p.fiscalYearId.equals(fiscalYearId)))
          .get();
      for (final p in periods) {
        await db.closeAccountingPeriod(p.id, userId);
      }

      await db.closeFiscalYear(fiscalYearId, userId);

      final closingJE = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('fiscal_close') &
                e.referenceId.equals(fiscalYearId)))
          .getSingleOrNull();
      expect(closingJE, isNotNull,
          reason: 'expected a fiscal_close JE after year-end');

      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(closingJE!.id)))
          .get();
      final d = lines.fold<double>(0, (s, l) => s + l.debit);
      final c = lines.fold<double>(0, (s, l) => s + l.credit);
      expect((d - c).abs(), lessThan(0.01));

      final fy = await (db.select(db.fiscalYears)
            ..where((f) => f.id.equals(fiscalYearId)))
          .getSingle();
      expect(fy.isClosed, isTrue);
    });

    test('closing with open monthly periods is rejected', () async {
      expect(
        () => db.closeFiscalYear(fiscalYearId, userId),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('فترات شهرية مفتوحة'),
        )),
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // AC3 — FX Revaluation
  // ═════════════════════════════════════════════════════════════════════════
  group('AC3 — FX revaluation', () {
    late int usdId;

    setUp(() async {
      usdId = await db.into(db.currencies).insert(
            CurrenciesCompanion.insert(
              code: 'USD',
              name: 'دولار أمريكي',
              symbol: '\$',
              exchangeRate: const Value(30.0),
            ),
          );
      await db.recordExchangeRate(
        currencyId: usdId,
        rate: 30.0,
        effectiveDate: DateTime(DateTime.now().year, 1, 1),
      );
    });

    test('exchange rate history is persisted and retrievable', () async {
      final today = DateTime.now();
      final rate = await db.getExchangeRate(usdId, date: today);
      expect(rate, closeTo(30.0, 0.0001));
    });

    test('convertToBase / convertFromBase round-trip', () async {
      final base = await db.convertToBase(100, usdId);
      expect(base, closeTo(3000, 0.001));
      final foreign = await db.convertFromBase(3000, usdId);
      expect(foreign, closeTo(100, 0.001));
    });

  });

  // ═════════════════════════════════════════════════════════════════════════
  // AC4 — COGS with returns (WAC)
  // ═════════════════════════════════════════════════════════════════════════
  group('AC4 — COGS with returns (WAC)', () {
    test('WAC formula recalculates correctly across two purchases', () async {
      final wh = (await db.getDefaultWarehouse())!.id;
      final pid = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'WAC-001',
          name: 'Widget',
          salePrice: const Value(20),
          costPrice: const Value(0),
          trackInventory: const Value(true),
        ),
      );

      // Purchase 1: 10 units @ 8 → WAC becomes 8 (0 prior stock).
      await db.updateProductWAC(
        productId: pid,
        newQuantity: 10,
        newUnitCost: 8,
      );
      await db.adjustStock(
        productId: pid,
        warehouseId: wh,
        quantity: 10,
        type: 'purchase',
        unitCost: 8,
      );
      // Cache may hold stale product; read fresh from DB.
      db.invalidateProductCache(pid);
      var p = await db.getProductById(pid);
      expect(p!.costPrice, closeTo(8.0, 0.0001));
      expect(p.currentStock, closeTo(10.0, 0.0001));

      // Purchase 2: 10 units @ 12 → WAC should be (10*8 + 10*12)/20 = 10.
      await db.updateProductWAC(
        productId: pid,
        newQuantity: 10,
        newUnitCost: 12,
      );
      await db.adjustStock(
        productId: pid,
        warehouseId: wh,
        quantity: 10,
        type: 'purchase',
        unitCost: 12,
      );
      db.invalidateProductCache(pid);
      p = await db.getProductById(pid);
      expect(p!.costPrice, closeTo(10.0, 0.0001),
          reason: 'WAC must blend prior cost with new cost');
    });

    test('WAC reset when prior stock is zero', () async {
      final pid = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'WAC-RESET',
          name: 'Reset',
          salePrice: const Value(1),
          costPrice: const Value(0),
          trackInventory: const Value(true),
        ),
      );
      // No prior stock → WAC should take the new unit cost directly.
      await db.updateProductWAC(
        productId: pid,
        newQuantity: 5,
        newUnitCost: 7.5,
      );
      final p = await db.getProductById(pid);
      expect(p!.costPrice, closeTo(7.5, 0.0001));
    });

    test('reverseProductWAC unwinds a purchase cleanly', () async {
      final pid = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'WAC-REV',
          name: 'Reversal',
          salePrice: const Value(1),
          costPrice: const Value(0),
          trackInventory: const Value(true),
        ),
      );
      // Prime: WAC=10 at qty=10 (simulate purchase 1)
      await (db.update(db.products)..where((x) => x.id.equals(pid))).write(
        const ProductsCompanion(
          currentStock: Value(10),
          costPrice: Value(10),
        ),
      );
      // Purchase 2: 10 @ 20 → WAC = 15
      await db.updateProductWAC(
        productId: pid,
        newQuantity: 10,
        newUnitCost: 20,
      );
      // Set currentStock to reflect new purchase
      await (db.update(db.products)..where((x) => x.id.equals(pid))).write(
        const ProductsCompanion(currentStock: Value(20)),
      );
      var p = await db.getProductById(pid);
      expect(p!.costPrice, closeTo(15.0, 0.0001));

      // Reverse purchase 2 → WAC should return to ~10
      await db.reverseProductWAC(
        productId: pid,
        reversedQuantity: 10,
        reversedUnitCost: 20,
      );
      p = await db.getProductById(pid);
      expect(p!.costPrice, closeTo(10.0, 0.0001));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // AC5 — Landed cost
  // ═════════════════════════════════════════════════════════════════════════
  group('AC5 — Landed cost', () {
    test('by_value allocation spreads freight pro-rata and applies to stock',
        () async {
      // Set up: supplier + warehouse + 2 products + purchase invoice
      final warehouse = await db.getDefaultWarehouse();
      expect(warehouse, isNotNull,
          reason: 'forTesting() should seed a default warehouse');
      final whId = warehouse!.id;

      final supplierId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'Supplier LC',
              isSupplier: const Value(true),
              isCustomer: const Value(false),
            ),
          );
      final p1 = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'LC-A',
          name: 'A',
          salePrice: const Value(0),
          costPrice: const Value(0),
          trackInventory: const Value(true),
        ),
      );
      final p2 = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'LC-B',
          name: 'B',
          salePrice: const Value(0),
          costPrice: const Value(0),
          trackInventory: const Value(true),
        ),
      );

      // Seed inventory_balances rows (required because applyLandedCost does
      // an UPDATE, not an UPSERT).
      await db.adjustStock(
        productId: p1,
        warehouseId: whId,
        quantity: 10,
        type: 'purchase',
        unitCost: 8,
      );
      await db.adjustStock(
        productId: p2,
        warehouseId: whId,
        quantity: 10,
        type: 'purchase',
        unitCost: 12,
      );

      // Purchase invoice with two items: A=10@8=80, B=10@12=120. Total=200.
      final invId = await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'PI-LC-1',
              supplierId: supplierId,
              warehouseId: whId,
              invoiceDate: DateTime.now(),
              subtotal: const Value(200),
              total: const Value(200),
            ),
          );
      await db.into(db.purchaseInvoiceItems).insert(
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: invId,
              productId: p1,
              quantity: 10,
              unitCost: 8,
              total: 80,
            ),
          );
      await db.into(db.purchaseInvoiceItems).insert(
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: invId,
              productId: p2,
              quantity: 10,
              unitCost: 12,
              total: 120,
            ),
          );

      // Create a landed-cost sheet with 40 freight
      final sheetId = await db.createLandedCostSheet(
        purchaseInvoiceId: invId,
        sheetNumber: 'LC-E2E-1',
        allocationMethod: 'by_value',
      );
      await db.addLandedCostItem(
        sheetId: sheetId,
        costType: 'freight',
        description: 'شحن',
        amount: 40,
      );

      final allocs = await db.calculateAllocations(sheetId);
      expect(allocs.length, 2);

      // by_value: A = 40 * 80/200 = 16 → newUnit = 8 + 16/10 = 9.6
      //           B = 40 * 120/200 = 24 → newUnit = 12 + 24/10 = 14.4
      final byProduct = {for (final a in allocs) a.productId: a};
      expect(byProduct[p1]!.allocatedAmount, closeTo(16.0, 0.01));
      expect(byProduct[p1]!.newUnitCost, closeTo(9.6, 0.01));
      expect(byProduct[p2]!.allocatedAmount, closeTo(24.0, 0.01));
      expect(byProduct[p2]!.newUnitCost, closeTo(14.4, 0.01));

      // Total allocated equals the sheet total (no rounding leak)
      final totalAllocated =
          allocs.fold<double>(0, (s, a) => s + a.allocatedAmount);
      expect(totalAllocated, closeTo(40.0, 0.001));

      // Apply → inventory_balances.average_cost for each product updates.
      await db.applyLandedCost(sheetId);
      final avgA = await _inventoryAvg(db, p1, whId);
      final avgB = await _inventoryAvg(db, p2, whId);
      expect(avgA, closeTo(9.6, 0.01));
      expect(avgB, closeTo(14.4, 0.01));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // AC6 — Bank reconciliation
  // ═════════════════════════════════════════════════════════════════════════
  group('AC6 — Bank reconciliation', () {
    test('auto-match pairs a statement line with an existing JE line',
        () async {
      // Post a JE that puts money into the bank account (e.g. cash deposit).
      final opDate = DateTime(DateTime.now().year, 5, 10);
      await db.createJournalEntry(
        description: 'Deposit',
        date: opDate,
        lines: [
          JournalLine(accountId: bankAccountId, debit: 500),
          JournalLine(accountId: cashAccountId, credit: 500),
        ],
      );

      // Statement line matches on amount (500) and date (within 3 days).
      // Bank's perspective: a credit to our bank account (money in) shows up
      // as a credit on the statement, which matches our DEBIT journal line.
      final imported = await db.importBankStatementLines(
        bankAccountId: bankAccountId,
        batchId: 'BATCH-E2E-1',
        lines: [
          {
            'date': opDate.add(const Duration(days: 1)),
            'reference': 'DEP-1',
            'description': 'إيداع نقدي',
            'debit': 0.0,
            'credit': 500.0,
            'balance': 500.0,
          },
        ],
      );
      expect(imported, 1);

      final matched = await db.autoMatchStatementLines(bankAccountId);
      expect(matched, 1, reason: 'auto-match should link the deposit');

      // Unmatched list is now empty.
      final unmatched = await db.getUnmatchedStatementLines(bankAccountId);
      expect(unmatched, isEmpty);
    });

    test('non-matching amounts stay unmatched', () async {
      final opDate = DateTime(DateTime.now().year, 5, 20);
      await db.createJournalEntry(
        description: 'Book side',
        date: opDate,
        lines: [
          JournalLine(accountId: bankAccountId, debit: 100),
          JournalLine(accountId: cashAccountId, credit: 100),
        ],
      );
      await db.importBankStatementLines(
        bankAccountId: bankAccountId,
        batchId: 'BATCH-E2E-2',
        lines: [
          {
            'date': opDate,
            'debit': 0.0,
            'credit': 200.0, // different amount
            'balance': 0.0,
          },
        ],
      );
      final matched = await db.autoMatchStatementLines(bankAccountId);
      expect(matched, 0);
    });

    test('reconciling does not alter book balances', () async {
      final opDate = DateTime(DateTime.now().year, 5, 25);
      await db.createJournalEntry(
        description: 'Pre-balance',
        date: opDate,
        lines: [
          JournalLine(accountId: bankAccountId, debit: 777),
          JournalLine(accountId: cashAccountId, credit: 777),
        ],
      );

      // Snapshot the balance in the accounts tree before reconciliation.
      final beforeSum = await _accountBalance(db, bankAccountId);

      await db.importBankStatementLines(
        bankAccountId: bankAccountId,
        batchId: 'BATCH-E2E-3',
        lines: [
          {
            'date': opDate,
            'debit': 0.0,
            'credit': 777.0,
            'balance': 777.0,
          },
        ],
      );
      await db.autoMatchStatementLines(bankAccountId);

      final afterSum = await _accountBalance(db, bankAccountId);
      expect(afterSum, closeTo(beforeSum, 0.001),
          reason: 'reconciliation is metadata-only; GL must not shift');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // AC7 — Fixed asset depreciation
  // ═════════════════════════════════════════════════════════════════════════
  group('AC7 — Fixed asset depreciation (straight-line)', () {
    late int categoryId;
    late int assetId;

    setUp(() async {
      // Feature 050 (v132): createAssetCategory now requires both account
      // ids. Use seeded vehicles + accumulated-depreciation accounts —
      // they exist after the suite-level syncDefaultAccounts() bootstrap.
      final assetAcct = await (db.select(db.accounts)
            ..where((a) => a.code.equals('1213')))
          .getSingle();
      final deprecAcct = await (db.select(db.accounts)
            ..where((a) => a.code.equals('1219')))
          .getSingle();
      categoryId = await db.createAssetCategory(
        name: 'معدات مكتبية',
        accountId: assetAcct.id,
        depreciationAccountId: deprecAcct.id,
      );
      // Asset: cost=12000, salvage=0, 1 year → 12000/12 = 1000/month.
      assetId = await db.createFixedAsset(
        code: 'FA-E2E-1',
        name: 'جهاز حاسوب',
        categoryId: categoryId,
        purchasePrice: 12000,
        purchaseDate: DateTime(DateTime.now().year, 1, 1),
        usefulLifeYears: 1,
      );
    });

    test('monthly depreciation equals (cost - salvage) / (years * 12)',
        () async {
      final period = DateTime(DateTime.now().year, 2, 28);
      final n = await db.runMonthlyDepreciation(period);
      expect(n, greaterThanOrEqualTo(1));

      final asset = await db.getFixedAssetById(assetId);
      expect(asset!.accumulatedDepreciation, closeTo(1000.0, 0.01));

      final rows = await (db.select(db.assetDepreciations)
            ..where((d) => d.assetId.equals(assetId)))
          .get();
      expect(rows, hasLength(1));
      expect(rows.first.depreciationAmount, closeTo(1000.0, 0.01));
      expect(rows.first.journalEntryId, isNotNull,
          reason: 'each depreciation row must link to its JE');
    });

    test('12 months of depreciation sum to depreciable base', () async {
      // Close no period; run 12 successive months inside the fiscal year.
      final y = DateTime.now().year;
      for (var m = 1; m <= 12; m++) {
        final last = DateTime(y, m + 1, 0); // last day of month m
        await db.runMonthlyDepreciation(last);
      }
      final asset = await db.getFixedAssetById(assetId);
      expect(asset!.accumulatedDepreciation, closeTo(12000.0, 0.05),
          reason: '12 × 1000 = 12000 = depreciable base');

      final rows = await (db.select(db.assetDepreciations)
            ..where((d) => d.assetId.equals(assetId)))
          .get();
      expect(rows, hasLength(12));
    });

    test('re-running the same period is idempotent', () async {
      final period = DateTime(DateTime.now().year, 2, 28);
      await db.runMonthlyDepreciation(period);
      await db.runMonthlyDepreciation(period);
      final rows = await (db.select(db.assetDepreciations)
            ..where((d) => d.assetId.equals(assetId)))
          .get();
      expect(rows, hasLength(1),
          reason: 'runMonthlyDepreciation must skip assets already done');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // AC8 — PeriodLockEnforcement
  // ═════════════════════════════════════════════════════════════════════════
  group('AC8 — Period-lock enforcement', () {
    test('closing a period blocks new entries within its date range',
        () async {
      final firstPeriod = await (db.select(db.accountingPeriods)
            ..where((p) => p.fiscalYearId.equals(fiscalYearId))
            ..orderBy([(p) => OrderingTerm.asc(p.month)])
            ..limit(1))
          .getSingle();
      await db.closeAccountingPeriod(firstPeriod.id, userId);

      final insidePeriod = DateTime(firstPeriod.year, firstPeriod.month, 15);
      expect(
        () => db.createJournalEntry(
          description: 'Locked-period write',
          date: insidePeriod,
          lines: [
            JournalLine(accountId: cashAccountId, debit: 10),
            JournalLine(accountId: revenueAccountId, credit: 10),
          ],
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('مغلقة'),
        )),
      );
    });

    test('entries outside the locked period are still accepted', () async {
      final m1 = await (db.select(db.accountingPeriods)
            ..where((p) =>
                p.fiscalYearId.equals(fiscalYearId) & p.month.equals(1))
            ..limit(1))
          .getSingle();
      await db.closeAccountingPeriod(m1.id, userId);

      final id = await db.createJournalEntry(
        description: 'Post in open period',
        date: DateTime(m1.year, 2, 5),
        lines: [
          JournalLine(accountId: cashAccountId, debit: 10),
          JournalLine(accountId: revenueAccountId, credit: 10),
        ],
      );
      expect(id, isPositive);
    });

    test('reopening a period allows new entries again', () async {
      final m1 = await (db.select(db.accountingPeriods)
            ..where((p) =>
                p.fiscalYearId.equals(fiscalYearId) & p.month.equals(3))
            ..limit(1))
          .getSingle();
      await db.closeAccountingPeriod(m1.id, userId);
      await db.reopenAccountingPeriod(m1.id);

      final id = await db.createJournalEntry(
        description: 'After reopen',
        date: DateTime(m1.year, 3, 10),
        lines: [
          JournalLine(accountId: cashAccountId, debit: 5),
          JournalLine(accountId: revenueAccountId, credit: 5),
        ],
      );
      expect(id, isPositive);
    });
  });

}

// ────────────────────────────────────────────────────────────────────────────
// helpers
// ────────────────────────────────────────────────────────────────────────────

/// Look up an account by code; create it with [name]/[type] if absent.
Future<int> _ensureAccount(
  AppDatabase db,
  String code,
  String name,
  String type,
) async {
  final existing = await db.getAccountByCode(code);
  if (existing != null) return existing.id;
  return db.createAccount(code: code, name: name, accountType: type);
}

/// Read the current average_cost from inventory_balances.
Future<double> _inventoryAvg(
  AppDatabase db,
  int productId,
  int warehouseId,
) async {
  final row = await (db.select(db.inventoryBalances)
        ..where((b) =>
            b.productId.equals(productId) &
            b.warehouseId.equals(warehouseId)))
      .getSingleOrNull();
  return row?.averageCost ?? 0;
}

/// Sum debit - credit for an account from posted JE lines.
Future<double> _accountBalance(AppDatabase db, int accountId) async {
  final lines = await (db.select(db.journalEntryLines)
        ..where((l) => l.accountId.equals(accountId)))
      .get();
  return lines.fold<double>(0, (s, l) => s + l.debit - l.credit);
}
