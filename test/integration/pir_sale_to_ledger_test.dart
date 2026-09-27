import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// PIR Integration Test 1 — Sale-to-Ledger Flow
///
/// Verifies the full chain:
///   POS Sale → Stock Decrease → Auto-post JE → Debit == Credit
///
/// This test ensures:
///   - Stock is correctly deducted on sale
///   - A journal entry is auto-posted with balanced debits/credits
///   - Cash safe balance increases by the paid amount
///   - Global trial balance remains zero after the sale
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;
  late int cashSafeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Seed role + user
    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(
        name: 'كاشير PIR',
        isSystemRole: const Value(false),
      ),
    );
    userId = await db.createUser(
      username: 'pir_sale_test',
      password: 'test123',
      displayName: 'PIR Sale Tester',
      roleId: roleId,
    );

    // Default warehouse
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    // Product with known cost price
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'PIR-SALE-01',
        name: 'منتج اختبار PIR',
        salePrice: const Value(150.0),
        costPrice: const Value(80.0),
        trackInventory: const Value(true),
      ),
    );

    // Seed stock
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100.0,
      type: 'adjustment',
    );

    // Reset cash safe to zero
    final cashSafe = await db.getDefaultSafeByType('cash');
    cashSafeId = cashSafe!.id;
    await db.updateSafeBalance(cashSafeId, 0.0);

    // Note: syncDefaultAccounts is called by beforeOpen seeder automatically
  });

  tearDown(() async => db.close());

  group('PIR: Sale → Stock → Ledger Flow', () {
    test('Cash sale deducts stock correctly', () async {
      // Record initial stock
      final before = await db.getProductById(productId);
      expect(before!.currentStock, 100.0);

      // Create sale: 5 units @ 150
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 750.0,
        discount: 0.0,
        tax: 0.0,
        total: 750.0,
        paid: 750.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5.0,
            unitPrice: 150.0,
            total: 750.0,
          ),
        ],
      );

      expect(invoiceId, isPositive);

      // Verify stock decreased: 100 - 5 = 95
      final after = await db.getProductById(productId);
      expect(after!.currentStock, 95.0,
          reason: 'Stock should decrease by quantity sold');
    });

    test('Cash sale increases safe balance', () async {
      // Verify initial safe balance is zero
      final safeBefore = await db.getSafeById(cashSafeId);
      final initialBalance = safeBefore!.balance;

      // Create sale: 3 units @ 150 = 450
      await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-002',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 450.0,
        discount: 0.0,
        tax: 0.0,
        total: 450.0,
        paid: 450.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3.0,
            unitPrice: 150.0,
            total: 450.0,
          ),
        ],
      );

      // Verify safe balance increased
      final safeAfter = await db.getSafeById(cashSafeId);
      expect(safeAfter!.balance - initialBalance, closeTo(450.0, 0.01),
          reason: 'Cash safe balance should increase by paid amount');
    });

    test('Auto-posted JE maintains debit == credit invariant', () async {
      // Create sale: 2 units @ 150 = 300
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-003',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 300.0,
        discount: 0.0,
        tax: 0.0,
        total: 300.0,
        paid: 300.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 2.0,
            unitPrice: 150.0,
            total: 300.0,
          ),
        ],
      );

      // Trigger auto-posting (createSalesInvoice does NOT auto-post)
      final invoice = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingle();
      await db.autoPostCashSale(invoice);

      // Verify global trial balance: sum(debit) == sum(credit)
      final result = await db.customSelect(
        'SELECT '
        'COALESCE(SUM(debit), 0) as total_debit, '
        'COALESCE(SUM(credit), 0) as total_credit '
        'FROM journal_entry_lines',
        readsFrom: {db.journalEntryLines},
      ).getSingle();

      final totalDebit = (result.data['total_debit'] as num).toDouble();
      final totalCredit = (result.data['total_credit'] as num).toDouble();

      expect(
        (totalDebit - totalCredit).abs(),
        lessThan(0.01),
        reason: 'INVARIANT: Global trial balance must be zero (Dr=$totalDebit, Cr=$totalCredit)',
      );
      expect(totalDebit, greaterThan(0),
          reason: 'JE should have non-zero amounts');
    });

    // Spec 136 (field 2026-06-04, invoice AQ-POS-1) regression.
    // The upstream creator stored an invoice whose `subtotal` was already
    // NET of the discount (subtotal == total) yet still carried a non-zero
    // `discount`. The old auto-post credited Sales with the net `subtotal`
    // AND debited a full Sales-Discount leg → JE off by exactly the discount
    // (debit ≠ credit) → rejected → client retried ~40× and flooded the
    // server. The fix derives the discount leg from the invoice arithmetic.
    // createSalesInvoice auto-posts internally and SWALLOWS an imbalance
    // throw into `failed_autoposts` (no sale JE created). So the regression
    // proof is: a balanced sale JE exists for this invoice AND failed_autoposts
    // is empty. Under the old code the imbalance threw → JE absent + a
    // failed_autoposts row.
    test('REGRESSION AQ-POS-1: net subtotal + discount posts a balanced JE, no phantom leg',
        () async {
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-AQ1',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 1.896, // already NET (== total) — the poison shape
        discount: 0.192, // still populated despite being baked into prices
        tax: 0.0,
        total: 1.896,
        paid: 1.896,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 1.896,
            total: 1.896,
          ),
        ],
      );

      // A balanced sale JE must have been posted (no imbalance throw).
      final je = await db.customSelect(
        "SELECT id FROM journal_entries "
        "WHERE reference_type = 'sale' AND reference_id = ?",
        variables: [Variable<int>(invoiceId)],
        readsFrom: {db.journalEntries},
      ).get();
      expect(je.length, 1,
          reason: 'A balanced sale JE must be posted for AQ-POS-1');

      final failed = await db.customSelect(
        'SELECT COUNT(*) as n FROM failed_autoposts WHERE invoice_id = ?',
        variables: [Variable<int>(invoiceId)],
        readsFrom: {db.failedAutoposts},
      ).getSingle();
      expect((failed.data['n'] as num).toInt(), 0,
          reason: 'Imbalance must NOT have dropped the sale into failed_autoposts');

      final entryId = je.first.data['id'] as int;
      final bal = await db.customSelect(
        'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c '
        'FROM journal_entry_lines WHERE entry_id = ?',
        variables: [Variable<int>(entryId)],
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      final d = (bal.data['d'] as num).toDouble();
      final c = (bal.data['c'] as num).toDouble();
      expect((d - c).abs(), lessThan(0.01),
          reason: 'Sale JE must balance (Dr=$d, Cr=$c)');

      // No phantom Sales-Discount leg — subtotal was already net.
      final discountLines = await db.customSelect(
        "SELECT COUNT(*) as n FROM journal_entry_lines "
        "WHERE entry_id = ? AND description = 'خصم مبيعات'",
        variables: [Variable<int>(entryId)],
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      expect((discountLines.data['n'] as num).toInt(), 0,
          reason: 'A net subtotal must not produce a contra-revenue discount leg');
    });

    // Spec 136 — the legitimate gross-subtotal case still posts the discount
    // leg correctly (behaviour preserved for the normal POS path).
    test('Gross subtotal + discount posts a balanced discount leg', () async {
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-GROSS',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 2.088, // GROSS (pre-discount)
        discount: 0.192,
        tax: 0.0,
        total: 1.896, // == subtotal - discount
        paid: 1.896,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 2.088,
            total: 1.896,
          ),
        ],
      );
      final je = await db.customSelect(
        "SELECT id FROM journal_entries "
        "WHERE reference_type = 'sale' AND reference_id = ?",
        variables: [Variable<int>(invoiceId)],
        readsFrom: {db.journalEntries},
      ).get();
      expect(je.length, 1, reason: 'Gross-subtotal sale must post a JE');
      final entryId = je.first.data['id'] as int;

      final bal = await db.customSelect(
        'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c '
        'FROM journal_entry_lines WHERE entry_id = ?',
        variables: [Variable<int>(entryId)],
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      final d = (bal.data['d'] as num).toDouble();
      final c = (bal.data['c'] as num).toDouble();
      expect((d - c).abs(), lessThan(0.01),
          reason: 'Sale JE must balance (Dr=$d, Cr=$c)');

      // The discount leg IS posted and equals the gross→net gap (0.192) —
      // provided a sales_discount account is mapped in the seeded COA.
      final discountLeg = await db.customSelect(
        "SELECT COALESCE(SUM(debit), 0) as dd FROM journal_entry_lines "
        "WHERE entry_id = ? AND description = 'خصم مبيعات'",
        variables: [Variable<int>(entryId)],
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      expect((discountLeg.data['dd'] as num).toDouble(), closeTo(0.192, 0.001),
          reason: 'Gross subtotal must record the discount as a contra-revenue leg');
    });

    // Spec 136 ISS-24 — the credit (آجل) sale path got the IDENTICAL discount
    // derivation; cover the poison shape there too (previously uncovered).
    test('REGRESSION credit sale: net subtotal + discount stays balanced', () async {
      final customerId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'عميل آجل PIR', isCustomer: const Value(true)),
      );
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-CR1',
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 1.896, // net (== total) with a populated discount
        discount: 0.192,
        tax: 0.0,
        total: 1.896,
        paid: 0.0,
        paymentMethod: 'credit',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 1.896,
            total: 1.896,
          ),
        ],
      );
      final je = await db.customSelect(
        "SELECT id FROM journal_entries "
        "WHERE reference_type = 'sale' AND reference_id = ?",
        variables: [Variable<int>(invoiceId)],
        readsFrom: {db.journalEntries},
      ).get();
      expect(je.length, 1,
          reason: 'credit-sale poison shape must post a balanced JE');
      final entryId = je.first.data['id'] as int;
      final bal = await db.customSelect(
        'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c '
        'FROM journal_entry_lines WHERE entry_id = ?',
        variables: [Variable<int>(entryId)],
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      final d = (bal.data['d'] as num).toDouble();
      final c = (bal.data['c'] as num).toDouble();
      expect((d - c).abs(), lessThan(0.01),
          reason: 'credit JE must balance (Dr=$d, Cr=$c)');
    });

    // Spec 136 ISS-24 — VAT + delivery + discount together exercises the
    // netRevenue = total - tax - deliveryFee subtraction (not covered by the
    // no-tax cases above).
    test('Sale with VAT + delivery + discount posts a balanced JE', () async {
      // gross subtotal 1000, discount 100, VAT 135, delivery 50 → total 1085
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-VAT',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 1000.0,
        discount: 100.0,
        tax: 135.0,
        total: 1085.0,
        paid: 1085.0,
        paymentMethod: 'cash',
        deliveryFee: 50.0,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 1000.0,
            total: 1000.0,
          ),
        ],
      );
      final je = await db.customSelect(
        "SELECT id FROM journal_entries "
        "WHERE reference_type = 'sale' AND reference_id = ?",
        variables: [Variable<int>(invoiceId)],
        readsFrom: {db.journalEntries},
      ).get();
      expect(je.length, 1, reason: 'VAT+delivery+discount sale must post a JE');
      final entryId = je.first.data['id'] as int;
      final bal = await db.customSelect(
        'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c '
        'FROM journal_entry_lines WHERE entry_id = ?',
        variables: [Variable<int>(entryId)],
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      final d = (bal.data['d'] as num).toDouble();
      final c = (bal.data['c'] as num).toDouble();
      expect((d - c).abs(), lessThan(0.01),
          reason: 'VAT+delivery+discount JE must balance (Dr=$d, Cr=$c)');
      // The discount leg equals the gross→net gap (100).
      final disc = await db.customSelect(
        "SELECT COALESCE(SUM(debit),0) as dd FROM journal_entry_lines "
        "WHERE entry_id = ? AND description = 'خصم مبيعات'",
        variables: [Variable<int>(entryId)],
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      expect((disc.data['dd'] as num).toDouble(), closeTo(100.0, 0.01),
          reason: 'discount leg must equal subtotal - netRevenue');
    });

    // Spec 136 ISS-24 — discount/return symmetry INVARIANT (locks correct
    // behaviour; guards against a naive "reverse the discount leg" change).
    //
    // A sale with a separate discount leg, then a FULL return, must net
    // revenue to ZERO. The return books Sales-Returns at the NET refunded
    // amount (already net of the original discount), so net revenue
    // (Sales − Discount − Returns) cancels exactly WITHOUT reversing the
    // discount leg. Adding a discount reversal while keeping Returns at net
    // would over-credit revenue by the discount — this test would catch that.
    test('INVARIANT: full return of a discounted sale nets revenue to zero', () async {
      // Sale: gross subtotal 1000, discount 100, no tax → total 900, cash.
      final saleId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-RETSYM',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 1000.0,
        discount: 100.0,
        tax: 0.0,
        total: 900.0,
        paid: 900.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 1000.0,
            total: 900.0,
          ),
        ],
      );
      final invoice = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(saleId)))
          .getSingle();

      // Full return: refund the net total (900), reverse the product cost (80).
      await db.autoPostSalesReturn(
        originalInvoice: invoice,
        returnAmount: 900.0,
        cogsAmount: 80.0,
        cashRefund: 900.0,
        bankRefund: 0.0,
        arRefund: 0.0,
        vatAmount: 0.0,
      );

      // 1. Global trial balance stays zero.
      final tb = await db.customSelect(
        'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c '
        'FROM journal_entry_lines',
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      expect(((tb.data['d'] as num) - (tb.data['c'] as num)).abs(), lessThan(0.01),
          reason: 'trial balance must stay zero after sale + full return');

      // 2. NET revenue = Sales(credit) − Discount(debit) − Returns(debit) == 0.
      final rev = await db.customSelect(
        "SELECT "
        "COALESCE(SUM(CASE WHEN description = 'مبيعات' THEN credit END),0) as sales, "
        "COALESCE(SUM(CASE WHEN description = 'خصم مبيعات' THEN debit END),0) as disc, "
        "COALESCE(SUM(CASE WHEN description LIKE 'مردودات مبيعات%' THEN debit END),0) as ret "
        "FROM journal_entry_lines",
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      final sales = (rev.data['sales'] as num).toDouble();
      final disc = (rev.data['disc'] as num).toDouble();
      final ret = (rev.data['ret'] as num).toDouble();
      expect(sales, closeTo(1000.0, 0.01), reason: 'gross sales credited');
      expect(disc, closeTo(100.0, 0.01), reason: 'discount leg posted on the sale');
      expect(ret, closeTo(900.0, 0.01), reason: 'returns booked at NET refunded amount');
      expect(sales - disc - ret, closeTo(0.0, 0.01),
          reason: 'net revenue must cancel on a full return (no discount-reversal needed)');
    });

    // Spec 136 (field 2026-06-08) — a TAXABLE sale must still post a BALANCED
    // JE even when the output_vat account is unmapped on the server. Pre-fix
    // the tax was subtracted from Sales but never credited to VAT → the JE was
    // short by the tax → every taxable sale dead-lettered and the tax never
    // reached the ledger.
    test('REGRESSION taxable sale balances even when the VAT account is UNMAPPED',
        () async {
      // Remove the VAT account so getAccountByCode('output_vat') resolves null.
      // FK is enforced in tests now — force the deletion with FK momentarily
      // off; the code under test still runs with FK ON.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await (db.delete(db.accounts)..where((a) => a.code.equals('2121'))).go();
      await db.customStatement('PRAGMA foreign_keys = ON');

      final saleId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-VATMISS',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 100.0,
        discount: 0.0,
        tax: 8.0,
        total: 108.0,
        paid: 108.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 100.0,
            total: 108.0,
          ),
        ],
      );

      final je = await db.customSelect(
        "SELECT id FROM journal_entries "
        "WHERE reference_type = 'sale' AND reference_id = ?",
        variables: [Variable<int>(saleId)],
        readsFrom: {db.journalEntries},
      ).get();
      expect(je.length, 1,
          reason: 'taxable sale must post even with no VAT account '
              '(tax folded into Sales, no dead-letter)');

      final entryId = je.first.data['id'] as int;
      final bal = await db.customSelect(
        'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c '
        'FROM journal_entry_lines WHERE entry_id = ?',
        variables: [Variable<int>(entryId)],
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      final d = (bal.data['d'] as num).toDouble();
      final c = (bal.data['c'] as num).toDouble();
      expect((d - c).abs(), lessThan(0.01),
          reason: 'JE must balance when VAT account is missing (Dr=$d, Cr=$c)');
    });

    test('Stock movements audit trail is complete', () async {
      // Create sale
      await db.createSalesInvoice(
        invoiceNumber: 'PIR-STL-004',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 150.0,
        discount: 0.0,
        tax: 0.0,
        total: 150.0,
        paid: 150.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 150.0,
            total: 150.0,
          ),
        ],
      );

      // Verify stock movement exists (adjustment + sale = at least 2 movements)
      final movements = await db.getMovementsForProduct(productId);
      expect(movements.length, greaterThanOrEqualTo(2),
          reason: 'Should have initial adjustment + sale movement');

      // Find the sale movement (negative quantity = stock deduction)
      final saleMovements = movements.where((m) => m.quantity < 0).toList();
      expect(saleMovements, isNotEmpty,
          reason: 'Sale should create a negative stock movement');
      expect(saleMovements.first.quantity.abs(), 1.0,
          reason: 'Sale movement should record the sold quantity');
    });
  });
}
