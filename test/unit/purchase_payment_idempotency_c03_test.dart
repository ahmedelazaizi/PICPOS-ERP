// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Wave B · C-03 (MAJOR) — purchase payment idempotency.
// ═══════════════════════════════════════════════════════════════════════════
//
// A purchase payment is ADDITIVE (paid += amount), unlike a void (idempotent
// terminal state). So an offline-outbox replay or a mirror re-submit carrying
// the SAME globalId must NOT double-apply — otherwise a single 200 payment
// becomes 400 on retry, over-crediting the safe and double-reducing payables.
//
// The dedup lives in addPurchasePayment (keyed on the payment safe_transaction's
// globalId) so BOTH the local path and the server handler are idempotent. This
// test pins: same globalId twice → applied ONCE; a different globalId → a
// distinct second payment applies.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    // safe_transactions.user_id FKs to users — the stamp test threads userId 9
    // (only the admin user 1 is seeded). FK is enforced in tests now.
    await db.into(db.users).insert(UsersCompanion.insert(
        id: const Value(9), username: 'usr9', passwordHash: 'x', displayName: 'U9'));
  });
  tearDown(() => db.close());

  // Opening payable 500 (as if a credit invoice already credited the supplier).
  Future<int> seedSupplier() => db.into(db.parties).insert(PartiesCompanion.insert(
      name: 'C03 Supplier',
      isSupplier: const Value(true),
      balance: const Value(500.0)));

  Future<double> supplierBalance(int id) async =>
      (await (db.select(db.parties)..where((p) => p.id.equals(id))).getSingle()).balance;

  // forTesting already seeds a default cash safe (balance 0); clear it so the
  // resolved default is unambiguously ours (balance assertions stay meaningful).
  Future<int> seedCashSafe() async {
    await db.delete(db.safes).go();
    return db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'C03 Cash Safe',
            safeType: const Value('cash'),
            isDefault: const Value(true),
            isActive: const Value(true),
            balance: const Value(10000.0),
          ),
        );
  }

  Future<int> seedInvoice(int supplierId, int warehouseId) =>
      db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'C03-INV-1',
              supplierId: supplierId,
              warehouseId: warehouseId,
              invoiceDate: DateTime.now(),
              total: const Value(500.0),
              paid: const Value(0.0),
              status: const Value('pending'),
            ),
          );

  Future<int> paymentTxnCount(int invoiceId) async {
    final rows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('purchase_invoice') &
              t.referenceId.equals(invoiceId) &
              t.transactionType.equals('payment')))
        .get();
    return rows.length;
  }

  test('same globalId replayed does not double-apply the payment', () async {
    final wh = await db.getDefaultWarehouse();
    final supplierId = await seedSupplier();
    await seedCashSafe();
    final invoiceId = await seedInvoice(supplierId, wh!.id);

    const gid = 'gid-c03-pay-1';
    await db.addPurchasePayment(invoiceId: invoiceId, amount: 200.0, globalId: gid);

    var inv = await (db.select(db.purchaseInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
    expect(inv.paid, 200.0);
    expect(inv.status, 'partial');
    expect(await paymentTxnCount(invoiceId), 1);

    // Replay with the SAME globalId — must be a no-op.
    await db.addPurchasePayment(invoiceId: invoiceId, amount: 200.0, globalId: gid);

    inv = await (db.select(db.purchaseInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
    expect(inv.paid, 200.0, reason: 'replay must NOT advance paid to 400');
    expect(await paymentTxnCount(invoiceId), 1, reason: 'no second safe_transaction');

    final safe = await db.getDefaultSafeByType('cash');
    expect(safe!.balance, 9800.0, reason: 'safe debited once, not twice');

    // FIN-B-ACC-1: supplier payable decremented once (500 → 300), not twice.
    expect(await supplierBalance(supplierId), 300.0,
        reason: 'payment reduces the supplier payable by 200, and the replay is a no-op');
  });

  test('a different globalId applies a distinct second payment', () async {
    final wh = await db.getDefaultWarehouse();
    final supplierId = await seedSupplier();
    await seedCashSafe();
    final invoiceId = await seedInvoice(supplierId, wh!.id);

    await db.addPurchasePayment(invoiceId: invoiceId, amount: 200.0, globalId: 'gid-a');
    await db.addPurchasePayment(invoiceId: invoiceId, amount: 100.0, globalId: 'gid-b');

    final inv = await (db.select(db.purchaseInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
    expect(inv.paid, 300.0, reason: 'two distinct payments apply');
    expect(await paymentTxnCount(invoiceId), 2);
  });

  test('the payment safe_transaction carries the caller globalId', () async {
    final wh = await db.getDefaultWarehouse();
    final supplierId = await seedSupplier();
    await seedCashSafe();
    final invoiceId = await seedInvoice(supplierId, wh!.id);

    await db.addPurchasePayment(invoiceId: invoiceId, amount: 50.0, globalId: 'gid-stamp', userId: 9);
    final txn = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('purchase_invoice') &
              t.referenceId.equals(invoiceId) &
              t.transactionType.equals('payment')))
        .getSingle();
    expect(txn.globalId, 'gid-stamp');
    expect(txn.userId, 9, reason: 'userId threaded onto the payment voucher');
  });
}
