// ═══════════════════════════════════════════════════════════════════════════
// SAL-1 — quantityInBase threaded into the SQL-level COGS autopost
// ═══════════════════════════════════════════════════════════════════════════
//
// accounting_autopost_dao.dart's autoPostCashSale/autoPostCreditSale compute
// COGS with a raw SQL SUM over sales_invoice_items. cost_price is per BASE
// unit (WAC); quantity is in SALE units. Before the fix the SQL ignored
// quantity_in_base, so selling a carton (quantityInBase=24) posted COGS as if
// only the carton count (not the physical piece count) had left the
// warehouse — silently understating COGS/inventory-credit on every
// non-base-unit sale. This exercises the real end-to-end path
// (db.createSalesInvoice → autoPostCashSale) rather than mocking the SQL.
//
// DB setup copied from test/unit/process_sales_return_happy_path_test.dart.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

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
      username: 'uom_cogs_user',
      password: 'test',
      displayName: 'UOM COGS User',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    // costPrice is per BASE unit (piece).
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'UOM-COGS-1',
        name: 'منتج بوحدة كرتون',
        salePrice: const Value(300.0),
        costPrice: const Value(10.0),
        currentStock: const Value(1000.0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1000.0,
      type: 'in',
      notes: 'seed',
    );
  });

  tearDown(() async => db.close());

  Future<double> postedCogsFor(int invoiceId) async {
    final entry = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('sale') & e.referenceId.equals(invoiceId)))
        .getSingle();
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entry.id)))
        .get();
    final cogsAcc = await db.getAccountByCode('5211');
    final cogsLine = lines.firstWhere((l) => l.accountId == cogsAcc!.id);
    return cogsLine.debit;
  }

  test('cash-sale COGS = quantity × quantityInBase × costPrice (carton sale)',
      () async {
    const quantity = 3.0; // cartons (SALE units)
    const quantityInBase = 24.0; // pieces per carton
    const costPrice = 10.0; // per piece (BASE unit)
    const expectedCogs = quantity * quantityInBase * costPrice; // 720

    final stockBefore = (await db.getProductById(productId))!.currentStock;

    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'INV-UOM-COGS-001',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 900.0,
      discount: 0.0,
      tax: 0.0,
      total: 900.0,
      paid: 900.0,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: quantity,
          unitPrice: 300.0,
          total: 900.0,
          costPrice: const Value(costPrice),
          quantityInBase: const Value(quantityInBase),
        ),
      ],
    );

    expect(await postedCogsFor(invoiceId), expectedCogs,
        reason: 'COGS must be qty × quantityInBase × costPrice = '
            '$expectedCogs, not qty × costPrice (30)');

    // The physical stock removed must match the SAME factor (already correct
    // pre-fix — asserted here so COGS and stock never diverge again).
    final stockAfter = (await db.getProductById(productId))!.currentStock;
    expect(stockAfter, stockBefore - (quantity * quantityInBase));
  });

  test('base-unit sale (quantityInBase=1) is unaffected — COGS = qty × cost',
      () async {
    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'INV-UOM-COGS-002',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 100.0,
      discount: 0.0,
      tax: 0.0,
      total: 100.0,
      paid: 100.0,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10.0,
          unitPrice: 10.0,
          total: 100.0,
          costPrice: const Value(10.0),
          // quantityInBase omitted → DB default 1.0 (base-unit sale).
        ),
      ],
    );

    expect(await postedCogsFor(invoiceId), 100.0,
        reason: '10 × 1.0 × 10 = 100 (no UOM conversion)');
  });
}
