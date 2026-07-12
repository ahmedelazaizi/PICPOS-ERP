// Feature 016 — sales_invoice_items.cost_price backfill regression guard.
//
// Reproduces the legacy mirror state (sales rows posted before the
// orchestrator's mirror branch started stamping local product WAC) and
// asserts that the one-shot startup pass:
//   * fills cost_price from products.cost_price (current WAC)
//   * is idempotent (second run does nothing)
//   * skips orphans (product missing or product WAC=0)

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/sales_cogs_backfill_extension.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int customerId;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
    customerId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'عميل تجريبي',
            isCustomer: const Value(true),
          ),
        );
    // Reuse the seeded admin user (id=1) the seeder always creates.
    userId = 1;
  });

  tearDown(() => db.close());

  /// Seeds a product + a sales invoice with one item whose cost_price is
  /// deliberately left at 0 (the legacy-mirror state).
  Future<({int productId, int invoiceId, int itemId})> seedZeroCostSale({
    required String code,
    required double productWac,
  }) async {
    final productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: code,
        name: 'منتج $code',
        salePrice: const Value(150),
        costPrice: Value(productWac),
      ),
    );
    final invoiceId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'INV-$code-${DateTime.now().microsecondsSinceEpoch}',
            customerId: Value(customerId),
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime(2026, 5, 1),
            subtotal: const Value(150),
            total: const Value(150),
            paid: const Value(150),
            paymentMethod: const Value('cash'),
          ),
        );
    final itemId = await db.into(db.salesInvoiceItems).insert(
          SalesInvoiceItemsCompanion.insert(
            invoiceId: invoiceId,
            productId: productId,
            quantity: 1,
            unitPrice: 150,
            total: 150,
            // cost_price intentionally OMITTED → 0 (the legacy bug).
          ),
        );
    return (productId: productId, invoiceId: invoiceId, itemId: itemId);
  }

  test('dry-run returns 0 on a clean DB (no zero-cost rows present)', () async {
    expect(await db.dryRunSalesCogsBackfill(), 0);
  });

  test('backfill is a no-op on a clean DB', () async {
    expect(await db.backfillSalesItemCostPrice(), 0);
  });

  test('backfill copies products.cost_price onto every zero-cost item',
      () async {
    final a = await seedZeroCostSale(code: 'COGS-A', productWac: 70);
    final b = await seedZeroCostSale(code: 'COGS-B', productWac: 42.5);
    final c = await seedZeroCostSale(code: 'COGS-C', productWac: 12);

    expect(await db.dryRunSalesCogsBackfill(), 3,
        reason: 'three legacy rows visible to the dry-run');

    final updated = await db.backfillSalesItemCostPrice();
    expect(updated, 3, reason: 'backfill must touch all three rows');

    final itemA = await (db.select(db.salesInvoiceItems)
          ..where((i) => i.id.equals(a.itemId)))
        .getSingle();
    final itemB = await (db.select(db.salesInvoiceItems)
          ..where((i) => i.id.equals(b.itemId)))
        .getSingle();
    final itemC = await (db.select(db.salesInvoiceItems)
          ..where((i) => i.id.equals(c.itemId)))
        .getSingle();
    expect(itemA.costPrice, 70);
    expect(itemB.costPrice, 42.5);
    expect(itemC.costPrice, 12);
  });

  test('backfill is idempotent — second run touches nothing', () async {
    await seedZeroCostSale(code: 'COGS-IDEM', productWac: 80);
    expect(await db.backfillSalesItemCostPrice(), 1);
    // Second run must report 0 (clean state).
    expect(await db.backfillSalesItemCostPrice(), 0);
    expect(await db.dryRunSalesCogsBackfill(), 0);
  });

  test('orphan rows (product WAC=0) are skipped, not patched', () async {
    final orphan = await seedZeroCostSale(code: 'COGS-ORPH', productWac: 0);
    final good = await seedZeroCostSale(code: 'COGS-OK', productWac: 50);

    final updated = await db.backfillSalesItemCostPrice();
    expect(updated, 1,
        reason: 'only the row whose product has a real WAC should change');

    final orphanItem = await (db.select(db.salesInvoiceItems)
          ..where((i) => i.id.equals(orphan.itemId)))
        .getSingle();
    expect(orphanItem.costPrice, 0,
        reason: 'product WAC=0 → row stays at 0 rather than getting fake data');

    final goodItem = await (db.select(db.salesInvoiceItems)
          ..where((i) => i.id.equals(good.itemId)))
        .getSingle();
    expect(goodItem.costPrice, 50);
  });
}
