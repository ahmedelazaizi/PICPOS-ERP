// ═══════════════════════════════════════════════════════════════════════════
// Batch quantities must move whenever warehouse stock moves.
// ═══════════════════════════════════════════════════════════════════════════
//
// `adjustStock` decides whether to touch batches from a hard-coded list of
// movement types:
//
//   isSaleDeduction  = qty < 0 && type in {sale, legacy_sale, edit_adjustment}
//   isReturnAddition = qty > 0 && type in {return, edit_reversal}
//
// Two real movement types are in neither list, so they move warehouse stock
// while the batch ledger sits still:
//
//   • `purchase_return` (negative) — goods physically go back to the supplier
//     (purchases_repository_impl ~809, api_purchase_handler ~430 / ~911).
//     Warehouse stock drops, batches keep their quantity
//     ⇒ Σ(batches) > stock: the batch ledger claims goods that left the door.
//   • `void_reversal` — voiding a SALE puts goods back (sales_actions_dao ~76,
//     positive) and voiding a PURCHASE takes them away (purchase_dao ~1869,
//     negative). Neither direction reaches the batches.
//
// Conservation is broken in BOTH directions, so the drift does not even
// average out over time. Everything downstream that reads batches — expiry
// alerts, FEFO ordering, recall traceability — works off quantities that no
// longer describe what is on the shelf.
//
// Both classification lists already gate on the SIGN of the movement, so a
// type listed in both is dispatched by direction, not by name.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int productId;
  late int batchId;

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = (await db.getDefaultWarehouse())!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'CONS-01',
        name: 'منتج',
        trackInventory: const Value(true),
        trackExpiry: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100,
      type: 'purchase',
      unitCost: 10,
      notes: 'seed',
    );
    batchId = await db.into(db.productBatches).insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            warehouseId: warehouseId,
            batchNumber: 'LOT-CONS',
            quantity: const Value(100),
            unitCost: const Value(10),
            expiryDate: DateTime.now().add(const Duration(days: 90)),
            status: const Value('active'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<double> batchQty() async {
    final row = await (db.select(db.productBatches)
          ..where((b) => b.id.equals(batchId)))
        .getSingle();
    return row.quantity;
  }

  Future<double> stockQty() async =>
      (await db.getProductById(productId))!.currentStock;

  test('returning goods to a supplier deducts the batch too', () async {
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -20,
      type: 'purchase_return',
      notes: 'مرتجع مشتريات',
    );

    expect(await stockQty(), 80.0);
    expect(await batchQty(), 80.0,
        reason: 'the 20 units physically went back to the supplier. A batch '
            'still holding them means the expiry report is watching stock '
            'that is no longer in the building');
  });

  test('voiding a sale restores the batch, not just the warehouse total',
      () async {
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -30,
      type: 'sale',
      notes: 'بيعة',
    );
    expect(await batchQty(), 70.0, reason: 'sanity: a sale already works');

    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 30,
      type: 'void_reversal',
      notes: 'إلغاء الفاتورة',
    );

    expect(await stockQty(), 100.0);
    expect(await batchQty(), 100.0,
        reason: 'the void put the goods back on the shelf — the lot they '
            'came from has to get them back, or the batch ledger '
            'permanently under-reports what is on hand');
  });

  test('voiding a purchase removes the goods from the batch as well',
      () async {
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: -100,
      type: 'void_reversal',
      notes: 'إلغاء فاتورة شراء',
    );

    expect(await stockQty(), 0.0);
    expect(await batchQty(), 0.0,
        reason: 'voiding the purchase that brought these goods in must empty '
            'the lot too — the same movement type runs in both directions '
            'and the sign is what decides which');
  });

  test('conservation holds across a full mixed cycle', () async {
    // The property the individual cases are examples of: after any sequence,
    // the batch ledger and the warehouse agree.
    await db.adjustStock(
      productId: productId, warehouseId: warehouseId,
      quantity: -30, type: 'sale', notes: 'بيعة',
    );
    await db.adjustStock(
      productId: productId, warehouseId: warehouseId,
      quantity: 10, type: 'return', notes: 'مرتجع مبيعات',
    );
    await db.adjustStock(
      productId: productId, warehouseId: warehouseId,
      quantity: -15, type: 'purchase_return', notes: 'مرتجع مشتريات',
    );
    await db.adjustStock(
      productId: productId, warehouseId: warehouseId,
      quantity: 5, type: 'void_reversal', notes: 'إلغاء',
    );

    final batches = await (db.select(db.productBatches)
          ..where((b) => b.productId.equals(productId)))
        .get();
    final batchTotal = batches.fold<double>(0, (s, b) => s + b.quantity);

    expect(batchTotal, closeTo(await stockQty(), 0.001),
        reason: 'Σ(batch quantities) must equal warehouse stock after any '
            'sequence of movements — 100 -30 +10 -15 +5 = 70');
  });
}
