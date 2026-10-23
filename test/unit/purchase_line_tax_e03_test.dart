// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Wave C · E-03 (MINOR) — a MIXED purchase invoice must store the
// per-line tax the caller passed, so an EXEMPT line keeps 0 input VAT and the
// per-line tax reconciles with the header tax to the minor unit.
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: the per-line INSERT always RECOMPUTED tax = qty*cost*(rate/100),
// ignoring the passed per-line taxAmount. A mixed invoice sends taxAmount=0 for
// an exempt line while still carrying the product's rate (>0) — so the line
// stored PHANTOM input VAT that a later purchase RETURN reversed, and made
// SUM(line.taxAmount) diverge from the header tax. Fix honours the passed
// amount (fallback-recompute only when none supplied) and rounds with the same
// FinancialUtils.round expression the header loop uses.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  Future<int> seedSupplier() => db.into(db.parties).insert(
      PartiesCompanion.insert(name: 'مورد E03', isSupplier: const Value(true)));

  Future<int> seedProduct(String code) => db.insertProduct(
        ProductsCompanion.insert(
          code: code,
          name: 'صنف $code',
          salePrice: const Value(150.0),
          costPrice: const Value(100.0),
          trackInventory: const Value(true),
        ),
      );

  test(
      'exempt line stores 0 tax (no phantom VAT) and SUM(line.tax) == header.tax',
      () async {
    final warehouseId = (await db.getDefaultWarehouse())!.id;
    final supplierId = await seedSupplier();
    final taxableProductId = await seedProduct('E03-TAXABLE');
    final exemptProductId = await seedProduct('E03-EXEMPT');

    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      items: [
        // Taxable line: rate 14, caller passes the correct 14.0 amount.
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: taxableProductId,
          quantity: 1.0,
          unitCost: 100.0,
          total: 114.0,
          taxRate: const Value(14.0),
          taxAmount: const Value(14.0),
        ),
        // EXEMPT line: rate is still 14 (from the product) but the form
        // passes taxAmount=0 → the stored line must NOT recompute to 14.
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: exemptProductId,
          quantity: 1.0,
          unitCost: 100.0,
          total: 100.0,
          taxRate: const Value(14.0),
          taxAmount: const Value(0.0),
        ),
      ],
    );

    final lines = await (db.select(db.purchaseInvoiceItems)
          ..where((l) => l.invoiceId.equals(invoiceId)))
        .get();
    expect(lines, hasLength(2));

    final exemptLine = lines.firstWhere((l) => l.productId == exemptProductId);
    expect(exemptLine.taxAmount, 0.0,
        reason: 'exempt line must keep 0 input VAT — no phantom '
            'qty*cost*rate recompute');

    final taxableLine = lines.firstWhere((l) => l.productId == taxableProductId);
    expect(taxableLine.taxAmount, closeTo(14.0, 0.001));

    final header = await (db.select(db.purchaseInvoices)
          ..where((i) => i.id.equals(invoiceId)))
        .getSingle();
    final lineTaxSum = lines.fold<double>(0, (s, l) => s + l.taxAmount);
    expect(lineTaxSum, closeTo(header.tax, 0.001),
        reason: 'SUM(line.taxAmount) must reconcile with the header tax');
    expect(header.tax, closeTo(14.0, 0.001),
        reason: 'header tax = 14 (taxable) + 0 (exempt)');
  });
}
