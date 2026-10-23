// Audit B RPT-001 — the party statement must not show voided / soft-deleted
// invoices or soft-deleted safe transactions, neither in the period window
// nor in the opening balance.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/parties_repository_impl.dart';

void main() {
  late AppDatabase db;
  late int wh;
  late int user;
  late int customer;
  late int supplier;
  late int safe;

  setUp(() async {
    db = AppDatabase.forTesting();
    wh = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'W'));
    user = await db.into(db.users).insert(UsersCompanion.insert(
        username: 'user1', passwordHash: 'x', displayName: 'U'));
    customer =
        await db.into(db.parties).insert(PartiesCompanion.insert(name: 'C'));
    supplier = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'S', isSupplier: const Value(true), isCustomer: const Value(false)));
    safe = await db.into(db.safes).insert(SafesCompanion.insert(name: 'SF'));
  });
  tearDown(() => db.close());

  Future<void> sale(String no, DateTime d, double total,
      {bool deleted = false}) async {
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: no,
          warehouseId: wh,
          userId: user,
          customerId: Value(customer),
          invoiceDate: d,
          total: Value(total),
          status: deleted ? const Value('voided') : const Value.absent(),
          isDeleted: Value(deleted),
        ));
  }

  Future<void> purchase(String no, DateTime d, double total,
      {bool deleted = false}) async {
    await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
          invoiceNumber: no,
          supplierId: supplier,
          warehouseId: wh,
          invoiceDate: d,
          total: Value(total),
          isDeleted: Value(deleted),
        ));
  }

  Future<void> receipt(String no, int party, DateTime d, double amt,
      {bool deleted = false}) async {
    await db
        .into(db.safeTransactions)
        .insert(SafeTransactionsCompanion.insert(
          voucherNumber: no,
          safeId: safe,
          transactionType: 'receipt',
          category: 'customer_payment',
          amount: amt,
          balanceAfter: amt,
          partyId: Value(party),
          createdAt: Value(d),
          deletedAt: Value(deleted ? DateTime(2026, 6, 1) : null),
        ));
  }

  test('customer: voided invoice and deleted receipt are absent (window)',
      () async {
    await sale('S-OK', DateTime(2026, 5, 2), 100);
    await sale('S-VOID', DateTime(2026, 5, 3), 100, deleted: true);
    await receipt('R-OK', customer, DateTime(2026, 5, 4), 30);
    await receipt('R-DEL', customer, DateTime(2026, 5, 5), 30, deleted: true);

    final rows = await db.getPartyStatement(customer,
        fromDate: DateTime(2026, 5, 1), toDate: DateTime(2026, 5, 31));
    expect(rows.map((e) => e.invoiceNumber), ['S-OK', 'R-OK']);
    expect(rows.last.balance, 70);
  });

  test('customer: voided invoice / deleted receipt excluded from opening',
      () async {
    await sale('S-OK', DateTime(2026, 4, 2), 100);
    await sale('S-VOID', DateTime(2026, 4, 3), 500, deleted: true);
    await receipt('R-OK', customer, DateTime(2026, 4, 4), 10);
    await receipt('R-DEL', customer, DateTime(2026, 4, 5), 40, deleted: true);

    final rows = await db.getPartyStatement(customer,
        fromDate: DateTime(2026, 5, 1), toDate: DateTime(2026, 5, 31));
    expect(rows.single.entryType, 'opening');
    expect(rows.single.balance, 90);
  });

  test('supplier: voided purchase excluded in window and opening', () async {
    await purchase('P-OK', DateTime(2026, 5, 2), 200);
    await purchase('P-VOID', DateTime(2026, 5, 3), 200, deleted: true);
    await purchase('P-OLD-VOID', DateTime(2026, 4, 3), 900, deleted: true);

    final rows = await db.getPartyStatement(supplier,
        fromDate: DateTime(2026, 5, 1), toDate: DateTime(2026, 5, 31));
    expect(rows.map((e) => e.invoiceNumber), ['P-OK']);
    expect(rows.single.balance, 200);
  });

  test('getCalculatedPartyBalance ignores voided invoices', () async {
    await sale('S-OK', DateTime(2026, 5, 2), 100);
    await sale('S-VOID', DateTime(2026, 5, 3), 100, deleted: true);
    expect(await PartiesRepositoryImpl(db).getCalculatedPartyBalance(customer), 100);
  });
}

