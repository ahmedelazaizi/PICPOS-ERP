// ═══════════════════════════════════════════════════════════════════════════
// Batch B7 (S-FAILLOUD) — unified fail-loud policy pins.
// ═══════════════════════════════════════════════════════════════════════════
//
// Three invariants across the sites touched by this batch:
//   1. No financial side-effect without a balanced JE — a missing required
//      GL account throws INSIDE the surrounding db.transaction() so the
//      whole operation rolls back (stock/cash/balance mutations included).
//   2. No false success — a caught JE-posting exception is never swallowed
//      while the method reports success.
//   3. Atomic record+post — recording a row and posting its JE happen in
//      ONE transaction.
//
// Sites covered:
//   PUR-3  purchase_dao.dart :: createPurchaseInvoice
//   PUR-4  purchase_dao.dart :: voidPurchaseInvoice
//   ACC-1  accounting_autopost_dao.dart :: autoPostDeliveryConfirmed
//   ACC-2  operational_expenses_dao.dart :: applyStockAdjustment
//   EXP-2  operational_expenses_dao.dart :: recordAndPostOperationalExpense
//   P2     purchase_dao.dart :: addPurchasePayment
//
// ACC-1 note: autoPostDeliveryConfirmed is deliberately NOT wrapped in a
// db.transaction() — see the doc comment on that method for why (nesting
// autoPostCashSale/autoPostCreditSale inside another transaction is a
// documented, twice-confirmed production deadlock — SqliteException 517 —
// in this codebase). Its test below pins the alternative design instead:
// sequential fail-fast (no double revenue) + idempotent-dedup self-heal on
// retry (no permanently vanished revenue), rather than a literal rollback.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  // ── shared seed helpers ───────────────────────────────────────────────

  Future<int> seedWarehouse() async {
    final wh = await db.getDefaultWarehouse();
    return wh!.id;
  }

  Future<int> seedSupplier([String name = 'B7 Test Supplier']) => db
      .into(db.parties)
      .insert(PartiesCompanion.insert(name: name, isSupplier: const Value(true)));

  Future<int> seedProduct(String code, {double currentStock = 0.0}) =>
      db.insertProduct(
        ProductsCompanion.insert(
          code: code,
          name: 'صنف اختبار $code',
          salePrice: const Value(50.0),
          costPrice: const Value(20.0),
          currentStock: Value(currentStock),
          trackInventory: const Value(true),
        ),
      );

  Future<int> seedCashSafe() => db.into(db.safes).insert(
        SafesCompanion.insert(
          name: 'B7 Cash Safe',
          safeType: const Value('cash'),
          isDefault: const Value(true),
          isActive: const Value(true),
          balance: const Value(10000.0),
        ),
      );

  /// A date in a DIFFERENT calendar month than "now", but the same year —
  /// so it still falls inside the fiscal year AppDatabase.forTesting()
  /// auto-creates (Jan 1 – Dec 31 of the current year), while its monthly
  /// accounting period can be closed/reopened independently of "now"'s.
  DateTime pastDateDifferentMonth() {
    final now = DateTime.now();
    final month = now.month == 1 ? 2 : 1;
    return DateTime(now.year, month, 10);
  }

  Future<void> setMonthClosed(DateTime date, bool closed) async {
    final updated = await (db.update(db.accountingPeriods)
          ..where((p) => p.month.equals(date.month) & p.year.equals(date.year)))
        .write(AccountingPeriodsCompanion(isClosed: Value(closed)));
    expect(updated, greaterThan(0),
        reason: 'AppDatabase.forTesting() must pre-seed a monthly '
            'accounting_periods row for ${date.month}/${date.year} '
            '(generatePeriodsForYear runs during beforeOpen)');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PUR-3 — createPurchaseInvoice
  // ═══════════════════════════════════════════════════════════════════════
  group('PUR-3 — createPurchaseInvoice fails loud on a missing inventory account', () {
    test(
        'throws and rolls back stock/WAC/party-balance/safe-txn when the '
        'inventory account cannot be resolved', () async {
      final warehouseId = await seedWarehouse();
      final supplierId = await seedSupplier();
      final productId = await seedProduct('B7-PUR3-1');

      // Force resolution of the 'inventory' purpose to fail by deleting the
      // seeded account row itself (code 1136). Deleting the row (rather than
      // just redirecting the account_mappings row) forces getAccountByCode
      // to return null regardless of the mapping-fallback chain — the
      // mapping still points at the now-nonexistent account id, and
      // getMappedAccountCode's fallback to the hardcoded default CODE
      // STRING ('1136') is then also a dead end.
      final deletedCount =
          await (db.delete(db.accounts)..where((a) => a.code.equals('1136'))).go();
      expect(deletedCount, 1,
          reason: 'syncDefaultAccounts() must have seeded 1136 for this '
              'test to be meaningful');

      final stockBefore = (await db.getProductById(productId))!.currentStock;
      final supplierBefore = await (db.select(db.parties)
            ..where((p) => p.id.equals(supplierId)))
          .getSingle();

      await expectLater(
        () => db.createPurchaseInvoice(
          supplierId: supplierId,
          warehouseId: warehouseId,
          paid: 100.0, // non-zero paid → would also touch the safe
          items: [
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: 0,
              productId: productId,
              quantity: 10.0,
              unitCost: 20.0,
              total: 200.0,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      final stockAfter = (await db.getProductById(productId))!.currentStock;
      expect(stockAfter, stockBefore,
          reason: 'stock/WAC must roll back with the failed JE');

      final supplierAfter = await (db.select(db.parties)
            ..where((p) => p.id.equals(supplierId)))
          .getSingle();
      expect(supplierAfter.balance, supplierBefore.balance,
          reason: 'party balance must roll back too');

      final movements = await (db.select(db.stockMovements)
            ..where((m) => m.productId.equals(productId)))
          .get();
      expect(movements, isEmpty, reason: 'no stock movement may survive');

      final safeTxns = await (db.select(db.safeTransactions)
            ..where((t) => t.referenceType.equals('purchase_invoice')))
          .get();
      expect(safeTxns, isEmpty,
          reason: 'the paid=100 safe transaction must roll back too');

      final invoices = await db.select(db.purchaseInvoices).get();
      expect(invoices, isEmpty,
          reason: 'the invoice header itself must roll back — no financial '
              'side-effect may survive with its JE missing');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // PUR-4 — voidPurchaseInvoice
  // ═══════════════════════════════════════════════════════════════════════
  group('PUR-4 — voidPurchaseInvoice fails loud when the reversal JE cannot post', () {
    test(
        'throws and leaves the invoice NOT voided with stock/AP unchanged '
        'when the reversal JE fails', () async {
      final warehouseId = await seedWarehouse();
      final supplierId = await seedSupplier();
      final productId = await seedProduct('B7-PUR4-1', currentStock: 100.0);
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 100.0,
        type: 'in',
        notes: 'B7 seed',
      );

      final invoiceDate = pastDateDifferentMonth();

      final invoiceId = await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'B7-PUR4-INV-1',
              supplierId: supplierId,
              warehouseId: warehouseId,
              invoiceDate: invoiceDate,
              total: const Value(200.0),
              paid: const Value(50.0),
              status: const Value('partial'),
              isLocked: const Value(true),
              globalId: const Value('b7-pur4-inv-1-gid'),
            ),
          );
      await db.into(db.purchaseInvoiceItems).insert(
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: invoiceId,
              productId: productId,
              quantity: 10.0,
              unitCost: 20.0,
              total: 200.0,
            ),
          );

      final inventoryAccount = await db.getAccountByCode('1136');
      final payableAccount = await db.getAccountByCode('2111');
      final origEntryId = await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'B7-JE-ORIG-PUR4-1',
              entryDate: invoiceDate,
              description: const Value('قيود مشتريات تجريبية PUR-4'),
              referenceType: const Value('purchase_invoice'),
              referenceId: Value(invoiceId),
              isAutoPosted: const Value(true),
              globalId: const Value('b7-je-orig-pur4-1'),
            ),
          );
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: origEntryId,
              accountId: inventoryAccount!.id,
              debit: const Value(200.0),
              credit: const Value(0),
            ),
          );
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: origEntryId,
              accountId: payableAccount!.id,
              debit: const Value(0),
              credit: const Value(200.0),
            ),
          );

      // Close the CURRENT month's period — the reversal JE inside
      // voidPurchaseInvoice is dated DateTime.now(), so this forces it to
      // throw, while invoiceDate's (different) month stays open so the
      // top-of-method period gate (validateFinancialPeriod(invoice.invoiceDate))
      // still passes and the void gets far enough to reverse stock/AP.
      await setMonthClosed(DateTime.now(), true);

      final supplierBefore = await (db.select(db.parties)
            ..where((p) => p.id.equals(supplierId)))
          .getSingle();
      final stockBefore = (await db.getProductById(productId))!.currentStock;

      await expectLater(
        () => db.voidPurchaseInvoice(invoiceId),
        throwsA(anything),
      );

      final invoiceAfter = await (db.select(db.purchaseInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingle();
      expect(invoiceAfter.status, 'partial',
          reason: 'must NOT be marked voided when the reversal JE failed');
      expect(invoiceAfter.isDeleted, isFalse);

      final stockAfter = (await db.getProductById(productId))!.currentStock;
      expect(stockAfter, stockBefore,
          reason: 'the stock reversal must roll back too');

      final supplierAfter = await (db.select(db.parties)
            ..where((p) => p.id.equals(supplierId)))
          .getSingle();
      expect(supplierAfter.balance, supplierBefore.balance,
          reason: 'the AP reversal must roll back too');

      final reversalJes = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('purchase_invoice_void') &
                e.referenceId.equals(invoiceId)))
          .get();
      expect(reversalJes, isEmpty,
          reason: 'no half-posted reversal JE may survive the rollback');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ACC-1 — autoPostDeliveryConfirmed
  // ═══════════════════════════════════════════════════════════════════════
  group('ACC-1 — autoPostDeliveryConfirmed never swallows and self-heals on retry', () {
    test(
        'revenue-JE failure propagates (no false success, no double revenue) '
        'and a retry converges to exactly one reversal + one revenue JE',
        () async {
      final warehouseId = await seedWarehouse();
      final roleId = await db.into(db.roles).insert(
            RolesCompanion.insert(name: 'كاشير B7-ACC1', isSystemRole: const Value(false)),
          );
      final userId = await db.createUser(
        username: 'b7_acc1_user',
        password: 'test',
        displayName: 'B7 ACC-1 User',
        roleId: roleId,
      );

      final invoiceDate = pastDateDifferentMonth();

      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'B7-ACC1-INV-1',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 300.0,
        discount: 0.0,
        tax: 0.0,
        total: 300.0,
        paid: 300.0,
        cashAmount: 300.0,
        paymentMethod: 'cash',
        deliveryStatus: 'pending', // → deferred-revenue JE at creation
        invoiceDate: invoiceDate,
        items: const [],
      );

      // Sanity: the deferred JE was posted while invoiceDate's month was
      // still open.
      final deferredBefore = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('deferred_sale') &
                e.referenceId.equals(invoiceId)))
          .get();
      expect(deferredBefore, hasLength(1));

      // Close invoiceDate's month — blocks the revenue JE (dated
      // sale.invoiceDate inside autoPostCashSale) while leaving "now" (the
      // deferred-reversal JE's date) open.
      await setMonthClosed(invoiceDate, true);

      await (db.update(db.salesInvoices)..where((i) => i.id.equals(invoiceId)))
          .write(const SalesInvoicesCompanion(deliveryStatus: Value('delivered')));

      await expectLater(
        () => db.autoPostDeliveryConfirmed(invoiceId),
        throwsA(anything),
      );

      // No false success / no double revenue: the revenue JE must not exist.
      final revenueAfterFirstAttempt = await (db.select(db.journalEntries)
            ..where((e) =>
                (e.referenceType.equals('sale') |
                    e.referenceType.equals('sales_invoice')) &
                e.referenceId.equals(invoiceId)))
          .get();
      expect(revenueAfterFirstAttempt, isEmpty,
          reason: 'the revenue JE must never post on the failed attempt');

      // The reversal DID succeed (dated "now", an open period) — this is
      // the expected transient half-state given the no-nested-transaction
      // design (see class doc). It must NOT be duplicated on retry.
      final reversalAfterFirstAttempt = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('deferred_sale_reversal') &
                e.referenceId.equals(invoiceId)))
          .get();
      expect(reversalAfterFirstAttempt, hasLength(1));

      // Reopen the period and retry — must converge: exactly one reversal
      // (idempotent dedup, no duplicate row) and exactly one revenue JE.
      await setMonthClosed(invoiceDate, false);

      await db.autoPostDeliveryConfirmed(invoiceId);

      final reversalAfterRetry = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('deferred_sale_reversal') &
                e.referenceId.equals(invoiceId)))
          .get();
      expect(reversalAfterRetry, hasLength(1),
          reason: 'idempotent dedup — no duplicate reversal on retry');

      final revenueAfterRetry = await (db.select(db.journalEntries)
            ..where((e) =>
                (e.referenceType.equals('sale') |
                    e.referenceType.equals('sales_invoice')) &
                e.referenceId.equals(invoiceId)))
          .get();
      expect(revenueAfterRetry, hasLength(1),
          reason: 'the revenue JE finally posts once the period is reopened');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ACC-2 — applyStockAdjustment
  // ═══════════════════════════════════════════════════════════════════════
  group('ACC-2 — applyStockAdjustment fails loud when a variance account is missing', () {
    test('throws and rolls back the stock adjustment when the inventory '
        'account cannot be resolved', () async {
      final warehouseId = await seedWarehouse();
      final productId = await seedProduct('B7-ACC2-1', currentStock: 50.0);
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 50.0,
        type: 'in',
        notes: 'B7 seed',
      );

      final deleted =
          await (db.delete(db.accounts)..where((a) => a.code.equals('1136'))).go();
      expect(deleted, 1);

      final stockBefore = (await db.getProductById(productId))!.currentStock;
      // Derive the "actual counted" quantity relative to whatever
      // products.currentStock actually resolved to after the two seed calls
      // above (insertProduct's initial value + adjustStock's own bookkeeping
      // may or may not be additive) — a fixed 10-unit shortfall is enough to
      // trigger the variance branch regardless of the absolute baseline.
      final actualCounted = stockBefore - 10.0;

      await expectLater(
        () => db.applyStockAdjustment(warehouseId, {productId: actualCounted}),
        throwsA(isA<StateError>()),
      );

      final stockAfter = (await db.getProductById(productId))!.currentStock;
      expect(stockAfter, stockBefore,
          reason: 'the stock adjustment must roll back with the failed JE');

      final movements = await (db.select(db.stockMovements)
            ..where((m) =>
                m.productId.equals(productId) &
                m.referenceType.equals('inventory_audit')))
          .get();
      expect(movements, isEmpty, reason: 'no stock movement may survive');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // EXP-2 — recordAndPostOperationalExpense
  // ═══════════════════════════════════════════════════════════════════════
  group('EXP-2 — recordAndPostOperationalExpense is atomic', () {
    test('rolls back the op_expenses insert when the JE post throws', () async {
      final categoryId =
          await db.createExpenseCategory(name: 'فئة B7 EXP-2 (كسر)', accountCode: '5299');
      // Redirect the 'op_expenses' fallback mapping to a nonexistent account
      // — a mapping row wins over the hardcoded default in
      // getAccountByPurpose, so this can't self-heal via syncDefaultAccounts
      // (same technique as the EXP-1 test).
      final updatedMapping = await (db.update(db.accountMappings)
            ..where((m) => m.purpose.equals('op_expenses')))
          .write(const AccountMappingsCompanion(accountId: Value(999999)));
      expect(updatedMapping, 1);

      expect(await db.select(db.opExpenses).get(), isEmpty);

      await expectLater(
        () => db.recordAndPostOperationalExpense(
          categoryId: categoryId,
          amount: 75.0,
          expenseDate: DateTime.now(),
          description: 'مصروف B7 EXP-2',
          expenseAccountCode: '5299',
          userId: 1,
        ),
        throwsA(anything),
      );

      expect(await db.select(db.opExpenses).get(), isEmpty,
          reason: 'the op_expenses row must roll back when the JE cannot post');
    });

    test('a resolvable category posts both the expense row and a balanced '
        'JE in one call', () async {
      final categoryId = await db.createExpenseCategory(name: 'فئة B7 EXP-2 (سليمة)');

      final expenseId = await db.recordAndPostOperationalExpense(
        categoryId: categoryId,
        amount: 120.0,
        expenseDate: DateTime.now(),
        description: 'مصروف B7 صالح',
        expenseAccountCode: '6214',
        userId: 1,
      );

      final expenseRow =
          await (db.select(db.opExpenses)..where((e) => e.id.equals(expenseId))).getSingle();
      expect(expenseRow.amount, 120.0);

      final je = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('op_expense') & e.referenceId.equals(expenseId)))
          .getSingle();
      final lines =
          await (db.select(db.journalEntryLines)..where((l) => l.entryId.equals(je.id))).get();
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit, reason: 'JE must balance');
      expect(totalDebit, 120.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // P2 — addPurchasePayment
  // ═══════════════════════════════════════════════════════════════════════
  group('P2 — addPurchasePayment posts a balanced Dr AP / Cr cash JE atomically', () {
    test('a successful payment posts a balanced JE consistent with the cash move',
        () async {
      final warehouseId = await seedWarehouse();
      final supplierId = await seedSupplier('B7 P2 Supplier OK');
      await seedCashSafe();

      final invoiceId = await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'B7-P2-INV-1',
              supplierId: supplierId,
              warehouseId: warehouseId,
              invoiceDate: DateTime.now(),
              total: const Value(500.0),
              paid: const Value(0.0),
              status: const Value('pending'),
            ),
          );

      await db.addPurchasePayment(invoiceId: invoiceId, amount: 200.0, paymentMethod: 'cash');

      final je = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('payment') & e.referenceId.equals(invoiceId)))
          .getSingle();
      final lines =
          await (db.select(db.journalEntryLines)..where((l) => l.entryId.equals(je.id))).get();
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(totalDebit, totalCredit, reason: 'payment JE must balance');
      expect(totalDebit, 200.0);

      final cashAccount = await db.getAccountByCode('1111');
      final cashLine = lines.firstWhere((l) => l.accountId == cashAccount!.id);
      expect(cashLine.credit, 200.0, reason: 'cash leg must be credited (money leaving)');

      final apAccount = await db.getAccountByCode('2111');
      final apLine = lines.firstWhere((l) => l.accountId == apAccount!.id);
      expect(apLine.debit, 200.0, reason: 'payables leg must be debited (liability reduced)');

      final updatedInvoice =
          await (db.select(db.purchaseInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
      expect(updatedInvoice.paid, 200.0);
      expect(updatedInvoice.status, 'partial');
    });

    test('rolls back the payment + safe movement when the JE cannot post',
        () async {
      final warehouseId = await seedWarehouse();
      final supplierId = await seedSupplier('B7 P2 Supplier FAIL');
      final safeId = await seedCashSafe();

      final deleted =
          await (db.delete(db.accounts)..where((a) => a.code.equals('1111'))).go();
      expect(deleted, 1);

      final invoiceId = await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'B7-P2-INV-2',
              supplierId: supplierId,
              warehouseId: warehouseId,
              invoiceDate: DateTime.now(),
              total: const Value(500.0),
              paid: const Value(0.0),
              status: const Value('pending'),
            ),
          );

      final safeBefore = await db.getSafeById(safeId);

      await expectLater(
        () => db.addPurchasePayment(invoiceId: invoiceId, amount: 200.0),
        throwsA(isA<StateError>()),
      );

      final invoiceAfter =
          await (db.select(db.purchaseInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
      expect(invoiceAfter.paid, 0.0,
          reason: 'the payment write must roll back when the JE cannot post');
      expect(invoiceAfter.status, 'pending');

      final safeAfter = await db.getSafeById(safeId);
      expect(safeAfter!.balance, safeBefore!.balance,
          reason: 'the safe balance must roll back too');

      final safeTxns = await (db.select(db.safeTransactions)
            ..where((t) => t.referenceId.equals(invoiceId)))
          .get();
      expect(safeTxns, isEmpty, reason: 'no half-posted safe transaction may survive');
    });

    test('fails loud and rolls back paid/status when NO safe is configured',
        () async {
      final warehouseId = await seedWarehouse();
      final supplierId = await seedSupplier('B7 P2 Supplier NO-SAFE');
      // Remove ALL safes (forTesting seeds a default one) so
      // _recordPurchasePayment resolves no target safe — cash never moves
      // and no JE can be posted. The payment must fail loud rather than
      // advance invoice.paid silently.
      await db.delete(db.safes).go();

      final invoiceId = await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'B7-P2-INV-3',
              supplierId: supplierId,
              warehouseId: warehouseId,
              invoiceDate: DateTime.now(),
              total: const Value(500.0),
              paid: const Value(0.0),
              status: const Value('pending'),
            ),
          );

      await expectLater(
        () => db.addPurchasePayment(invoiceId: invoiceId, amount: 200.0, paymentMethod: 'cash'),
        throwsA(isA<StateError>()),
      );

      final invoiceAfter =
          await (db.select(db.purchaseInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
      expect(invoiceAfter.paid, 0.0,
          reason: 'paid must roll back — no cash moved, no JE posted');
      expect(invoiceAfter.status, 'pending');
    });
  });
}
