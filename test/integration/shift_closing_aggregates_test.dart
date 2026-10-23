/// Day-16 Integration Tests — getShiftClosingAggregates() SQL Optimization
///
/// Verifies that the GROUP BY SQL rewrite produces the same results as the
/// original row-by-row Dart loop for every payment-method branch.
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int safeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'cashier', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'cashier1',
      password: 'pw',
      displayName: 'Cashier 1',
      roleId: roleId,
    );
    warehouseId = await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'Main',
        isActive: const Value(true),
        isDefault: const Value(true),
      ),
    );

    // Fiscal year required by createSalesInvoice
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        name: '2026',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
      ),
    );

    // Default cash safe (required for treasury routing)
    safeId = await db.into(db.safes).insert(
      SafesCompanion.insert(
        name: 'Cash',
        safeType: const Value('cash'),
        isDefault: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: quick invoice insert
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> insertInvoice({
    required double paid,
    required double total,
    required String paymentMethod,
    String saleType = 'counter',
    int? customerId,
    double cashPaid = 0,
    double bankPaid = 0,
    double clickPaid = 0,
  }) async {
    await db.into(db.salesInvoices).insert(
      SalesInvoicesCompanion.insert(
        invoiceNumber: 'INV-${DateTime.now().microsecondsSinceEpoch}',
        invoiceDate: DateTime.now(),
        warehouseId: warehouseId,
        userId: userId,
        total: Value(total),
        subtotal: const Value(0),
        discount: const Value(0),
        tax: const Value(0),
        paid: Value(paid),
        paymentMethod: Value(paymentMethod),
        saleType: Value(saleType),
        customerId: Value(customerId),
        cashPaid: Value(cashPaid),
        bankPaid: Value(bankPaid),
        clickPaid: Value(clickPaid),
        isDeleted: const Value(false),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Test 1 — Cash and bank invoices aggregate correctly
  // ─────────────────────────────────────────────────────────────────────────

  test('cash and bank invoices aggregate into correct buckets', () async {
    // 3 cash invoices: 100 + 200 + 150 = 450
    await insertInvoice(paid: 100, total: 100, paymentMethod: 'cash');
    await insertInvoice(paid: 200, total: 200, paymentMethod: 'cash');
    await insertInvoice(paid: 150, total: 150, paymentMethod: 'cash');
    // 2 bank invoices: 300 + 250 = 550
    await insertInvoice(paid: 300, total: 300, paymentMethod: 'bank');
    await insertInvoice(paid: 250, total: 250, paymentMethod: 'bank');

    final agg = await db.getShiftClosingAggregates(
      userId: userId,
      includeAllUsers: true,
      shiftStart: DateTime.now().subtract(const Duration(hours: 1)),
    );

    expect(agg.salesCash, closeTo(450, 0.01));
    expect(agg.salesBank, closeTo(550, 0.01));
    expect(agg.salesClick, 0);
    expect(agg.salesCount, 5);
    expect(agg.counterSalesCount, 5);
    expect(agg.counterSalesTotal, closeTo(1000, 0.01));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 2 — Mixed payment splits across channels
  // ─────────────────────────────────────────────────────────────────────────

  test('mixed invoice splits into cash/bank/click correctly', () async {
    // One mixed invoice: 60 cash + 40 bank + 20 click = 120 total paid
    await insertInvoice(
      paid: 120,
      total: 120,
      paymentMethod: 'mixed',
      cashPaid: 60,
      bankPaid: 40,
      clickPaid: 20,
    );

    final agg = await db.getShiftClosingAggregates(
      userId: userId,
      includeAllUsers: true,
      shiftStart: DateTime.now().subtract(const Duration(hours: 1)),
    );

    expect(agg.salesCash, closeTo(60, 0.01));
    expect(agg.salesBank, closeTo(40, 0.01));
    expect(agg.salesClick, closeTo(20, 0.01));
    expect(agg.salesCredit, 0,
        reason: 'fully paid mixed invoice has no credit portion');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 3 — Credit invoices route to salesCredit (with customer)
  // ─────────────────────────────────────────────────────────────────────────

  test('credit invoice with customer adds to salesCredit', () async {
    // Seed a customer party
    final customerId = await db.into(db.parties).insert(
      PartiesCompanion.insert(
        name: 'Test Customer',
        isCustomer: const Value(true),
        isSupplier: const Value(false),
      ),
    );

    // Invoice total=500, paid=0 → fully unpaid credit
    await insertInvoice(
      paid: 0,
      total: 500,
      paymentMethod: 'credit',
      customerId: customerId,
    );

    final agg = await db.getShiftClosingAggregates(
      userId: userId,
      includeAllUsers: true,
      shiftStart: DateTime.now().subtract(const Duration(hours: 1)),
    );

    expect(agg.salesCredit, closeTo(500, 0.01));
    expect(agg.salesCreditCount, 1);
    expect(agg.salesCash, 0,
        reason: 'no cash payment was made');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 4 — POS return invoices go to returns buckets, not sales
  // ─────────────────────────────────────────────────────────────────────────

  test('POS return invoice (saleType=return) routes to returns buckets', () async {
    // Normal sale
    await insertInvoice(paid: 200, total: 200, paymentMethod: 'cash');
    // POS return: paid is negative in production but ABS is applied
    await insertInvoice(
      paid: -80,
      total: -80,
      paymentMethod: 'cash',
      saleType: 'return',
    );

    final agg = await db.getShiftClosingAggregates(
      userId: userId,
      includeAllUsers: true,
      shiftStart: DateTime.now().subtract(const Duration(hours: 1)),
    );

    expect(agg.salesCash, closeTo(200, 0.01),
        reason: 'normal cash sale counted once');
    expect(agg.returnsCash, closeTo(80, 0.01),
        reason: 'return is ABS-d and routed to returns');
    expect(agg.returnsCount, 1);
    expect(agg.salesCount, 1,
        reason: 'return row must not inflate salesCount');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 5 — Auto-ref transactions (sales_invoice) are excluded
  // ─────────────────────────────────────────────────────────────────────────

  test('safe_transactions with referenceType=sales_invoice are excluded', () async {
    // Insert a shadow transaction that must NOT affect the receipt count
    await db.into(db.safeTransactions).insert(
      SafeTransactionsCompanion.insert(
        voucherNumber: 'TEST-ST-001',
        safeId: safeId,
        amount: 500,
        balanceAfter: 500,
        transactionType: 'receipt',
        category: 'sales',
        referenceType: const Value('sales_invoice'),
        userId: Value(userId),
      ),
    );

    final agg = await db.getShiftClosingAggregates(
      userId: userId,
      includeAllUsers: true,
      shiftStart: DateTime.now().subtract(const Duration(hours: 1)),
    );

    // The auto-ref shadow row must be suppressed
    expect(agg.receiptCount, 0,
        reason: 'auto-ref rows must not count as explicit receipts');
    expect(agg.receiptCash, 0);
  });
}
