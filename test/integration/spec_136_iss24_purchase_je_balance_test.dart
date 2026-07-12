import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// Spec 136 ISS-24 — purchase auto-post JE balance regression.
///
/// The accounting review of the sales fix found `autoPostPurchase` carried the
/// IDENTICAL gross/net-subtotal assumption: it debited Inventory with `subtotal`
/// and credited Purchase-Discount with the raw `discount`, which only balances
/// when `total = subtotal - discount + tax`. A poison invoice whose `subtotal`
/// is already net (subtotal == total) yet still carries a discount would
/// imbalance by exactly the discount — the same failure that hit AQ-POS-1 on
/// the sales side.
///
/// The fix derives the discount leg from the invoice arithmetic:
///   netGoodsCost  = total - tax
///   discountCredit = max(0, subtotal - netGoodsCost)
///   inventoryDebit = netGoodsCost + discountCredit
/// so Dr == Cr by construction.
void main() {
  late AppDatabase db;
  late int supplierId;
  late int warehouseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورد PIR ISS-24',
            isSupplier: const Value(true),
          ),
        );
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
  });

  tearDown(() async => db.close());

  Future<int> insertRawPurchase({
    required String invoiceNumber,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
  }) async {
    return db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: invoiceNumber,
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: DateTime(2026, 6, 4),
            subtotal: Value(subtotal),
            discount: Value(discount),
            tax: Value(tax),
            total: Value(total),
            paid: Value(paid),
            paymentMethod: const Value('cash'),
          ),
        );
  }

  Future<(double, double, int)> postAndBalance(int purchaseId) async {
    final purchase = await (db.select(db.purchaseInvoices)
          ..where((p) => p.id.equals(purchaseId)))
        .getSingle();
    await db.autoPostPurchase(purchase);
    final je = await db.customSelect(
      "SELECT id FROM journal_entries "
      "WHERE reference_type = 'purchase' AND reference_id = ?",
      variables: [Variable<int>(purchaseId)],
      readsFrom: {db.journalEntries},
    ).get();
    expect(je.length, 1, reason: 'a balanced purchase JE must be posted');
    final entryId = je.first.data['id'] as int;
    final bal = await db.customSelect(
      'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c '
      'FROM journal_entry_lines WHERE entry_id = ?',
      variables: [Variable<int>(entryId)],
      readsFrom: {db.journalEntryLines},
    ).getSingle();
    return (
      (bal.data['d'] as num).toDouble(),
      (bal.data['c'] as num).toDouble(),
      entryId,
    );
  }

  test('REGRESSION: net subtotal (==total) + discount posts a balanced JE, no phantom leg',
      () async {
    // The poison shape: subtotal already net, discount still populated.
    final id = await insertRawPurchase(
      invoiceNumber: 'PINV-ISS24-NET',
      subtotal: 1.896,
      discount: 0.192,
      tax: 0.0,
      total: 1.896,
      paid: 1.896,
    );
    final (d, c, entryId) = await postAndBalance(id);
    expect((d - c).abs(), lessThan(0.01),
        reason: 'purchase JE must balance (Dr=$d, Cr=$c)');

    // No phantom purchase-discount leg — subtotal was already net.
    final disc = await db.customSelect(
      "SELECT COUNT(*) as n FROM journal_entry_lines "
      "WHERE entry_id = ? AND description = 'خصم مشتريات'",
      variables: [Variable<int>(entryId)],
      readsFrom: {db.journalEntryLines},
    ).getSingle();
    expect((disc.data['n'] as num).toInt(), 0,
        reason: 'net subtotal must not produce a contra discount leg');
  });

  test('Gross subtotal + discount posts a balanced JE with the discount leg',
      () async {
    final id = await insertRawPurchase(
      invoiceNumber: 'PINV-ISS24-GROSS',
      subtotal: 2.088, // gross (pre-discount)
      discount: 0.192,
      tax: 0.0,
      total: 1.896, // == subtotal - discount
      paid: 1.896,
    );
    final (d, c, entryId) = await postAndBalance(id);
    expect((d - c).abs(), lessThan(0.01),
        reason: 'purchase JE must balance (Dr=$d, Cr=$c)');

    final disc = await db.customSelect(
      "SELECT COALESCE(SUM(credit),0) as dd FROM journal_entry_lines "
      "WHERE entry_id = ? AND description = 'خصم مشتريات'",
      variables: [Variable<int>(entryId)],
      readsFrom: {db.journalEntryLines},
    ).getSingle();
    expect((disc.data['dd'] as num).toDouble(), closeTo(0.192, 0.001),
        reason: 'gross subtotal must record the purchase discount leg');
  });
}
