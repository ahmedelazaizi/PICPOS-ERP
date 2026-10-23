// Pre-deploy hardening (P2, accounting audit 2026-07-13) — autoPostCashSale
// gated the receivable leg on `customerId != null`, but always credited full
// net revenue. A partial-cash sale to NO customer (walk-in, total > paid) then
// posted credits (revenue + VAT) > debits (only the cash paid) → the writer
// threw "المدين لا يساوى الدائن" → the invoice saved but its JE dead-lettered,
// and repairAllMissingInvoiceJEs re-failed identically → a permanent GL gap.
// Fix: debit the unpaid remainder to the receivables CONTROL account even when
// customerId is null (mirrors the factory).
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'pc_nocust_user',
      password: 'test',
      displayName: 'Partial Cash User',
      roleId: roleId,
    );
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'PC-NOCUST-1',
        name: 'صنف نقدي جزئي',
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        currentStock: const Value(100.0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100.0,
      type: 'in',
      notes: 'seed',
    );
  });

  tearDown(() async => db.close());

  test('partial-cash sale with NO customer posts a balanced JE', () async {
    // total 114 = net 100 + 14 VAT; paid only 60; customerId null.
    // Remainder 54 must hit the receivables control account so debits == 114.
    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'INV-PC-NOCUST-001',
      warehouseId: warehouseId,
      userId: userId,
      customerId: null,
      subtotal: 100.0,
      discount: 0.0,
      tax: 14.0,
      total: 114.0,
      paid: 60.0,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 1,
          unitPrice: 100.0,
          total: 100.0,
          costPrice: const Value(60.0),
          quantityInBase: const Value(1),
        ),
      ],
    );

    final entry = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('sale') & e.referenceId.equals(invoiceId)))
        .getSingleOrNull();
    expect(entry, isNotNull,
        reason: 'the sale JE must exist — it must NOT dead-letter on imbalance');

    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entry!.id)))
        .get();
    final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
    final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
    expect(totalDebit, closeTo(totalCredit, 0.001),
        reason: 'double-entry must balance (the whole point — no dead-letter)');
    // Revenue side: Dr cash 60 + Dr receivable 54 + Dr COGS 60 = 174
    //             = Cr sales 100 + Cr VAT 14 + Cr inventory 60.
    expect(totalDebit, closeTo(174.0, 0.001),
        reason: 'cash 60 + receivable remainder 54 + COGS 60');
    // The fix specifically: the 54 unpaid remainder is booked (receivable leg).
    expect(lines.any((l) => (l.debit - 54.0).abs() < 0.001), isTrue,
        reason: 'the unpaid 54 must hit the receivables control account');
  });
}
