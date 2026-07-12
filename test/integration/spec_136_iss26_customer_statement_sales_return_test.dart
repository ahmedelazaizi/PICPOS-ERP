import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// Spec 136 ISS-26 — customer account statement must show sales returns.
///
/// A sales return created from the returns dialog exists ONLY as a
/// `sales_return_balance` memo in safe_transactions (no sales_invoices row).
/// `getPartyStatement` used to skip that category (Spec 113 skip), so dialog
/// sales returns never appeared in the customer statement — the customer-side
/// mirror of the ISS-14 supplier bug. The fix emits the memo as a CREDIT line.
void main() {
  late AppDatabase db;
  late int customerId;
  late int warehouseId;
  late int userId;
  late int cashSafeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير ISS26', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'iss26', password: 'pw', displayName: 'ISS26', roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    cashSafeId = (await db.getDefaultSafeByType('cash'))!.id;

    customerId = await db.into(db.parties).insert(
          PartiesCompanion.insert(name: 'عميل ISS26', isCustomer: const Value(true)),
        );
  });

  tearDown(() async => db.close());

  test('sales-return-balance memo appears as a CREDIT line in the customer statement',
      () async {
    final now = DateTime.now();

    // A normal credit sale to the customer.
    await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'INV-ISS26-1',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: now.subtract(const Duration(hours: 2)),
            customerId: Value(customerId),
            total: const Value(100.0),
            paid: const Value(0.0),
            paymentMethod: const Value('credit'),
          ),
        );

    // A sales return recorded ONLY as a balance memo (the returns-dialog path).
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: 'SRET-MEMO-1',
            safeId: cashSafeId,
            transactionType: 'memo',
            category: 'sales_return_balance',
            amount: 30.0,
            balanceAfter: 0.0,
            partyId: Value(customerId),
            createdAt: Value(now.subtract(const Duration(hours: 1))),
            description: const Value('تسوية رصيد مرتجع مبيعات فاتورة INV-ISS26-1'),
          ),
        );

    final entries = await db.getPartyStatement(customerId);

    // The memo must now appear as a distinct CREDIT line.
    final returnEntries = entries
        .where((e) => e.referenceType == 'sales_return_balance')
        .toList();
    expect(returnEntries.length, 1,
        reason: 'the sales-return memo must surface as one statement line');
    expect(returnEntries.first.credit, closeTo(30.0, 0.001),
        reason: 'sales return reduces AR → CREDIT column');
    expect(returnEntries.first.debit, 0.0);

    // Sanity: the sale invoice is still there as a DEBIT.
    expect(
      entries.any((e) => e.referenceType == 'sales_invoice' && e.debit == 100.0),
      isTrue,
      reason: 'the original sale invoice still shows as a debit',
    );
  });

  // Spec 136 ISS-26 (#4) — a cash receipt tagged with the customer's (local)
  // partyId must surface as a CREDIT line. The mirror fix writes this row
  // locally so the (local-read) statement sees it; this test pins the display
  // side: a 'receipt' safe_transaction for the party appears as a credit.
  test('cash receipt (local partyId) appears as a CREDIT line in the customer statement',
      () async {
    final now = DateTime.now();
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: 'REC-ISS26-1',
            safeId: cashSafeId,
            transactionType: 'receipt',
            category: 'customer_payment',
            amount: 40.0,
            balanceAfter: 40.0,
            partyId: Value(customerId),
            createdAt: Value(now),
            description: const Value('تحصيل من عميل'),
          ),
        );

    final entries = await db.getPartyStatement(customerId);
    final receipts = entries.where((e) => e.entryType == 'receipt').toList();
    expect(receipts.length, 1,
        reason: 'the cash receipt must surface as one statement line');
    expect(receipts.first.credit, closeTo(40.0, 0.001),
        reason: 'a customer receipt reduces AR → CREDIT column');
  });
}
