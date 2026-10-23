/// Week-9 Integration Tests — Shift Close → Financial Report E2E
///
/// 5 tests that walk the complete cashier-shift lifecycle and verify the
/// downstream accounting / reporting data is correct at every stage:
///
///   1. Full shift cycle  — open → cash sale → exact-match close → closed status
///   2. Shift aggregates  — getShiftClosingAggregates reflects sale totals
///   3. Cash variance     — closing with less cash records negative variance
///   4. Trial balance     — hand-crafted JE shows debit = credit in report
///   5. Income statement  — revenue account credited by JE appears in P&L
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'Cashier', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'shift_tester',
      password: 'shift_pw_1!',
      displayName: 'Shift Tester',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'SHFT-01',
        name: 'Shift Product',
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        trackInventory: const Value(true),
      ),
    );

    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100.0,
      type: 'adjustment',
    );
  });

  tearDown(() async => db.close());

  // ── Helper — create a standard 3-unit cash sale ─────────────────────────
  Future<int> makeCashSale(String invoiceNumber, {double qty = 3.0}) async {
    return db.createSalesInvoice(
      invoiceNumber: invoiceNumber,
      warehouseId: warehouseId,
      userId: userId,
      subtotal: qty * 100.0,
      discount: 0.0,
      tax: 0.0,
      total: qty * 100.0,
      paid: qty * 100.0,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitPrice: 100.0,
          total: qty * 100.0,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Test 1 — Full shift cycle: open → sale → exact-match close
  // ══════════════════════════════════════════════════════════════════════════

  test('full shift cycle: open → cash sale → close → status = closed',
      () async {
    // Open the shift
    final shiftId = await db.openShift(userId, 0.0);
    expect(shiftId, isPositive);

    // Confirm it is open
    final openShift = await db.getCurrentOpenShift(userId);
    expect(openShift, isNotNull);
    expect(openShift!.id, shiftId);

    // Make a 300 cash sale
    await makeCashSale('SHFT-E2E-001');

    // The safe should now hold 300 from the sale receipt
    final cashSafe = await db.getDefaultSafeByType('cash');
    final balanceAfterSale = cashSafe!.balance;

    // Close with the exact expected cash (opening 0 + receipts = balanceAfterSale)
    await db.closeShiftWithAudit(shiftId, balanceAfterSale);

    // Shift must now be marked closed
    final closedShift = await (db.select(db.shifts)
          ..where((s) => s.id.equals(shiftId)))
        .getSingleOrNull();

    expect(closedShift, isNotNull);
    expect(closedShift!.status, 'closed');
    expect(closedShift.endTime, isNotNull);
    // No variance on exact-match close
    expect(closedShift.variance?.abs() ?? 0.0, lessThan(0.01));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Test 2 — Shift closing aggregates reflect sales made during the shift
  // ══════════════════════════════════════════════════════════════════════════

  test('getShiftClosingAggregates returns correct sales total for the shift',
      () async {
    final shiftId = await db.openShift(userId, 0.0);

    // Make two sales: 3 × 100 + 5 × 100 = 800
    await makeCashSale('SHFT-AGG-001', qty: 3.0);
    await makeCashSale('SHFT-AGG-002', qty: 5.0);

    final openShift = await db.getCurrentOpenShift(userId);

    final aggregates = await db.getShiftClosingAggregates(
      userId: userId,
      includeAllUsers: false,
      shiftStart: openShift!.startTime,
      openingBalance: 0.0,
    );

    // Total cash sales should be 800 (3 + 5 units × 100)
    expect(aggregates.salesCash, greaterThanOrEqualTo(800.0));

    await db.closeShiftWithAudit(shiftId, 0.0);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Test 3 — Cash shortage: closing 50 short records negative variance
  // ══════════════════════════════════════════════════════════════════════════

  test('closing shift with less cash than expected records negative variance',
      () async {
    final shiftId = await db.openShift(userId, 0.0);

    // Sale of 300 → expected cash after close = 300
    await makeCashSale('SHFT-VAR-001');

    // Close with 250 — 50 short
    await db.closeShiftWithAudit(shiftId, 250.0);

    final closedShift = await (db.select(db.shifts)
          ..where((s) => s.id.equals(shiftId)))
        .getSingleOrNull();

    expect(closedShift, isNotNull);
    expect(closedShift!.status, 'closed');
    // variance = actualCash − expectedCash = 250 − 300 = −50
    expect(closedShift.variance, lessThan(-0.01),
        reason: 'negative variance expected for a 50-unit shortage');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Test 4 — Trial balance: debits equal credits after manual journal entry
  // ══════════════════════════════════════════════════════════════════════════

  test('trial balance shows debit = credit after a balanced journal entry',
      () async {
    final now = DateTime.now();

    // Create two accounts for this test
    final cashAccountId = await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        code: 'TB-1001',
        name: 'TB Cash',
        accountType: 'asset',
      ),
    );
    final revenueAccountId = await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        code: 'TB-4001',
        name: 'TB Revenue',
        accountType: 'revenue',
      ),
    );

    // Insert a posted JE directly (bypass DAO gating for test isolation)
    final jeId = await db.into(db.journalEntries).insert(
      JournalEntriesCompanion.insert(
        entryNumber: 'TB-TEST-001',
        entryDate: now,
        description: const Value('Test sale JE'),
        isPosted: const Value(true),
        isAutoPosted: const Value(false),
        branchId: const Value(1),
      ),
    );
    await db.into(db.journalEntryLines).insert(
      JournalEntryLinesCompanion.insert(
        entryId: jeId,
        accountId: cashAccountId,
        debit: const Value(500.0),
        credit: const Value(0.0),
      ),
    );
    await db.into(db.journalEntryLines).insert(
      JournalEntryLinesCompanion.insert(
        entryId: jeId,
        accountId: revenueAccountId,
        debit: const Value(0.0),
        credit: const Value(500.0),
      ),
    );

    final trialBalance = await db.accountingDao.getTrialBalance(
      now.subtract(const Duration(minutes: 5)),
      now.add(const Duration(minutes: 5)),
    );

    // Find our two accounts in the trial balance rows
    // Keys: movementDebit / movementCredit (period activity columns)
    final tbRows = trialBalance.where(
      (row) =>
          row['code'] == 'TB-1001' || row['code'] == 'TB-4001',
    ).toList();

    double totalDebit = 0;
    double totalCredit = 0;
    for (final row in tbRows) {
      totalDebit += (row['movementDebit'] as num? ?? 0).toDouble();
      totalCredit += (row['movementCredit'] as num? ?? 0).toDouble();
    }

    expect(totalDebit, greaterThan(0), reason: 'cash account should have debit');
    expect(totalCredit, greaterThan(0),
        reason: 'revenue account should have credit');
    expect(totalDebit, closeTo(totalCredit, 0.01),
        reason: 'trial balance: debits must equal credits');
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Test 5 — Income statement: revenue account shows up in P&L
  // ══════════════════════════════════════════════════════════════════════════

  test('income statement shows revenue from posted journal entry', () async {
    final now = DateTime.now();

    // Create a revenue account and an asset account
    final revenueId = await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        code: 'IS-4001',
        name: 'Sales Revenue',
        accountType: 'revenue',
      ),
    );
    final cashId = await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        code: 'IS-1001',
        name: 'IS Cash',
        accountType: 'asset',
      ),
    );

    // Baseline income statement BEFORE our JE
    final baselineIS = await db.accountingDao.getIncomeStatement(
      now.subtract(const Duration(minutes: 5)),
      now.add(const Duration(minutes: 5)),
    );
    final baselineRevenue =
        (baselineIS['totalRevenue'] as num?)?.toDouble() ?? 0.0;

    // Insert a posted JE directly: IS-Cash dr 1000 / IS-Revenue cr 1000
    final jeId = await db.into(db.journalEntries).insert(
      JournalEntriesCompanion.insert(
        entryNumber: 'IS-TEST-001',
        entryDate: now,
        description: const Value('Sales revenue JE'),
        isPosted: const Value(true),
        isAutoPosted: const Value(false),
        branchId: const Value(1),
      ),
    );
    await db.into(db.journalEntryLines).insert(
      JournalEntryLinesCompanion.insert(
        entryId: jeId,
        accountId: cashId,
        debit: const Value(1000.0),
        credit: const Value(0.0),
      ),
    );
    await db.into(db.journalEntryLines).insert(
      JournalEntryLinesCompanion.insert(
        entryId: jeId,
        accountId: revenueId,
        debit: const Value(0.0),
        credit: const Value(1000.0),
      ),
    );

    // After: revenue should have increased by exactly 1000
    final afterIS = await db.accountingDao.getIncomeStatement(
      now.subtract(const Duration(minutes: 5)),
      now.add(const Duration(minutes: 5)),
    );
    final afterRevenue =
        (afterIS['totalRevenue'] as num?)?.toDouble() ?? 0.0;

    expect(afterRevenue, closeTo(baselineRevenue + 1000.0, 0.01),
        reason: 'income statement totalRevenue must rise by 1000 after JE posted');
  });
}
