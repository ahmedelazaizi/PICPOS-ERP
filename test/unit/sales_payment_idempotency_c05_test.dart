// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Wave B · C-05 (MAJOR) — customer collection idempotency.
// ═══════════════════════════════════════════════════════════════════════════
//
// The exact TWIN of purchase_payment_idempotency_c03_test.dart. A customer
// collection is ADDITIVE (paid += delta), unlike a void (idempotent terminal
// state). So an offline-outbox replay or a mirror re-submit carrying the SAME
// globalId must NOT double-apply — otherwise a single 200 collection becomes
// 400 on retry, over-crediting the safe, double-reducing the customer's AR and
// over-advancing invoice.paid.
//
// The dedup lives in addSalesPayment (keyed on the receipt safe_transaction's
// globalId, threaded through createReceiptVoucher) so BOTH the local path and
// the server handler are idempotent. This test pins: same globalId twice →
// applied ONCE; a different globalId → a distinct second collection applies. It
// also pins CRUX 2 (no AR double-count): the collection credits the customer
// party once (via the receipt's party-AR leg) and advances invoice.paid once,
// and the receipt JE balances Dr Safe / Cr Customer.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    // SalesInvoices.userId is NOT NULL — seed a real user to attribute the row.
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'cashier', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'c05cashier',
      password: 'pw',
      displayName: 'C05 Cashier',
      roleId: roleId,
    );
    // safe_transactions.user_id FKs to users — the stamp test threads a distinct
    // userId 7 (proving the payment's userId, not the invoice's, is recorded).
    await db.into(db.users).insert(UsersCompanion.insert(
        id: const Value(7), username: 'usr7', passwordHash: 'x', displayName: 'U7'));
  });
  tearDown(() => db.close());

  // Seed a customer with an opening AR of 500 (as if a credit sale already
  // Dr'd the customer at sale time). The collection must Cr it back down.
  Future<int> seedCustomer() => db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'C05 Customer',
          isCustomer: const Value(true),
          balance: const Value(500.0),
        ),
      );

  // forTesting already seeds a default cash safe (balance 0); clear it so the
  // resolved default is unambiguously ours (balance assertions stay meaningful).
  Future<int> seedCashSafe() async {
    await db.delete(db.safes).go();
    return db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'C05 Cash Safe',
            safeType: const Value('cash'),
            isDefault: const Value(true),
            isActive: const Value(true),
            balance: const Value(10000.0),
          ),
        );
  }

  Future<int> seedInvoice(int customerId, int warehouseId) =>
      db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'C05-INV-1',
              customerId: Value(customerId),
              warehouseId: warehouseId,
              userId: userId,
              invoiceDate: DateTime.now(),
              total: const Value(500.0),
              paid: const Value(0.0),
              paymentMethod: const Value('credit'),
              status: const Value('pending'),
            ),
          );

  // The receipt safe_transaction carries transactionType 'receipt' + the
  // customer partyId (createReceiptVoucher does not stamp referenceType/Id).
  Future<int> receiptTxnCount(int customerId) async {
    final rows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.transactionType.equals('receipt') &
              t.partyId.equals(customerId)))
        .get();
    return rows.length;
  }

  Future<double> partyBalance(int partyId) async {
    final p = await (db.select(db.parties)..where((x) => x.id.equals(partyId)))
        .getSingle();
    return p.balance;
  }

  test('same globalId replayed does not double-apply the collection', () async {
    final wh = await db.getDefaultWarehouse();
    final customerId = await seedCustomer();
    await seedCashSafe();
    final invoiceId = await seedInvoice(customerId, wh!.id);

    const gid = 'gid-c05-collect-1';
    await db.addSalesPayment(invoiceId: invoiceId, amount: 200.0, globalId: gid);

    var inv = await (db.select(db.salesInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
    expect(inv.paid, 200.0);
    expect(inv.status, 'partial');
    expect(await receiptTxnCount(customerId), 1);
    // CRUX 2 — customer AR credited exactly once (500 → 300), not twice.
    expect(await partyBalance(customerId), 300.0);

    final safeAfterFirst = await db.getDefaultSafeByType('cash');
    expect(safeAfterFirst!.balance, 10200.0, reason: 'safe credited once (+200)');

    // The receipt JE must balance Dr Safe / Cr Customer-AR.
    final je = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('receipt_voucher')))
        .getSingle();
    final lines =
        await (db.select(db.journalEntryLines)..where((l) => l.entryId.equals(je.id))).get();
    final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
    final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
    expect(totalDebit, totalCredit, reason: 'collection JE must balance');
    expect(totalDebit, 200.0);
    final cashAccount = await db.getAccountByCode('1111');
    final cashLine = lines.firstWhere((l) => l.accountId == cashAccount!.id);
    expect(cashLine.debit, 200.0, reason: 'cash leg debited (money arriving)');

    // Replay with the SAME globalId — must be a no-op.
    await db.addSalesPayment(invoiceId: invoiceId, amount: 200.0, globalId: gid);

    inv = await (db.select(db.salesInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
    expect(inv.paid, 200.0, reason: 'replay must NOT advance paid to 400');
    expect(await receiptTxnCount(customerId), 1, reason: 'no second receipt txn');
    expect(await partyBalance(customerId), 300.0, reason: 'AR unchanged on replay');

    final safeAfterReplay = await db.getDefaultSafeByType('cash');
    expect(safeAfterReplay!.balance, 10200.0, reason: 'safe credited once, not twice');
  });

  test('a different globalId applies a distinct second collection', () async {
    final wh = await db.getDefaultWarehouse();
    final customerId = await seedCustomer();
    await seedCashSafe();
    final invoiceId = await seedInvoice(customerId, wh!.id);

    await db.addSalesPayment(invoiceId: invoiceId, amount: 200.0, globalId: 'gid-a');
    await db.addSalesPayment(invoiceId: invoiceId, amount: 100.0, globalId: 'gid-b');

    final inv = await (db.select(db.salesInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
    expect(inv.paid, 300.0, reason: 'two distinct collections apply');
    expect(inv.status, 'partial');
    expect(await receiptTxnCount(customerId), 2);
    // 500 − 200 − 100 = 200 remaining AR.
    expect(await partyBalance(customerId), 200.0);
  });

  test('the receipt safe_transaction carries the caller globalId + userId', () async {
    final wh = await db.getDefaultWarehouse();
    final customerId = await seedCustomer();
    await seedCashSafe();
    final invoiceId = await seedInvoice(customerId, wh!.id);

    await db.addSalesPayment(
        invoiceId: invoiceId, amount: 50.0, globalId: 'gid-stamp', userId: 7);
    final txn = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.transactionType.equals('receipt') &
              t.partyId.equals(customerId)))
        .getSingle();
    expect(txn.globalId, 'gid-stamp');
    expect(txn.userId, 7, reason: 'userId threaded onto the receipt voucher');
  });

  test('collection on a customerless invoice fails loud (no revenue double-book)',
      () async {
    final wh = await db.getDefaultWarehouse();
    await seedCashSafe();
    // Invoice with NO customer (customerId null) + a remaining balance. Crediting
    // via createReceiptVoucher would fall back to the 'sales' revenue account and
    // double-book revenue — addSalesPayment must reject it instead.
    final invoiceId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'C05-INV-NULLCUST',
            warehouseId: wh!.id,
            userId: userId,
            invoiceDate: DateTime.now(),
            total: const Value(500.0),
            paid: const Value(0.0),
            status: const Value('pending'),
          ),
        );
    await expectLater(
      () => db.addSalesPayment(invoiceId: invoiceId, amount: 100.0, globalId: 'gid-nc'),
      throwsA(isA<StateError>()),
    );
    // Nothing applied — paid rolled back, no receipt txn.
    final inv = await (db.select(db.salesInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
    expect(inv.paid, 0.0, reason: 'the paid advance must roll back with the throw');
    final receipts = await (db.select(db.safeTransactions)
          ..where((t) => t.transactionType.equals('receipt')))
        .get();
    expect(receipts, isEmpty, reason: 'no receipt posted for a customerless collection');
  });
}
