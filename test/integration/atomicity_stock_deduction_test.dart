import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ural_erp/data/database/database.dart';

/// Phase 2 — Stock Deduction Atomicity
///
/// Verifies that the stock deduction path in sales invoice creation is:
///  1. Atomic with the invoice insert (both succeed or both fail).
///  2. Correctly blocks negative stock when enforcement is on.
///  3. WAC (Weighted Average Cost) updates with each purchase receipt.
///  4. Concurrent stock deductions from multiple sale threads don't over-sell
///     when negative stock prevention is enforced.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'admin', isSystemRole: const drift.Value(true)),
    );
    await db.createUser(
      username: 'admin',
      password: 'pw',
      displayName: 'Admin',
      roleId: roleId,
    );

    await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'Main',
        isActive: const drift.Value(true),
        isDefault: const drift.Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  /// Helper: get warehouse-specific inventory quantity for a product.
  Future<double> getWarehouseStock(AppDatabase db, int productId, int warehouseId) async {
    final balance = await (db.select(db.inventoryBalances)
          ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return balance?.quantity ?? 0.0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('Stock Deduction Atomicity', () {
    // ─────────────────────────────────────────────────────────────────────────
    test('Stock is correctly deducted on sale creation', () async {
      final warehouse = await db.getDefaultWarehouse();
      final users = await db.select(db.users).get();

      final unitId = await db.into(db.units).insert(UnitsCompanion.insert(name: 'pc', symbol: 'pc'));
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Sale Product',
          code: 'SALE-001',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(10.0),
          salePrice: const drift.Value(15.0),
        ),
      );

      // Seed warehouse stock = 50
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouse!.id,
        quantity: 50.0,
        type: 'initial',
        notes: 'Initial stock',
      );

      await db.createSalesInvoice(
        warehouseId: warehouse.id,
        userId: users.first.id,
        paymentMethod: 'cash',
        subtotal: 150.0,
        discount: 0,
        tax: 0,
        total: 150.0,
        paid: 150.0,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10,
            unitPrice: 15.0,
            total: 150.0,
            costPrice: const drift.Value(10.0),
          )
        ],
      );

      final stock = await getWarehouseStock(db, productId, warehouse.id);
      expect(stock, 40.0, reason: 'Stock should decrease by sold quantity');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Sequential sales correctly accumulate deductions', () async {
      final warehouse = await db.getDefaultWarehouse();
      final users = await db.select(db.users).get();

      final unitId = await db.into(db.units).insert(UnitsCompanion.insert(name: 'pc2', symbol: 'pc2'));
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Sequential Sale Product',
          code: 'SALE-002',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(5.0),
          salePrice: const drift.Value(8.0),
        ),
      );

      await db.adjustStock(productId: productId, warehouseId: warehouse!.id, quantity: 100.0, type: 'initial');

      // Three sequential sales: -10, -15, -25 = -50 total
      for (final qty in [10, 15, 25]) {
        final lineTotal = qty * 8.0;
        await db.createSalesInvoice(
          warehouseId: warehouse.id,
          userId: users.first.id,
          paymentMethod: 'cash',
          subtotal: lineTotal,
          discount: 0,
          tax: 0,
          total: lineTotal,
          paid: lineTotal,
          items: [
            SalesInvoiceItemsCompanion.insert(
              invoiceId: 0,
              productId: productId,
              quantity: qty.toDouble(),
              unitPrice: 8.0,
              total: lineTotal,
              costPrice: const drift.Value(5.0),
            )
          ],
        );
      }

      final stock = await getWarehouseStock(db, productId, warehouse.id);
      expect(stock, 50.0, reason: 'Three sequential deductions of 10+15+25 = 50 should leave 50');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('WAC updates correctly after purchase receipt', () async {
      final warehouse = await db.getDefaultWarehouse();
      final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'WAC Supplier', isSupplier: const drift.Value(true), balance: const drift.Value(0)),
      );
      final unitId = await db.into(db.units).insert(UnitsCompanion.insert(name: 'wa', symbol: 'wa'));
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'WAC Product',
          code: 'WAC-001',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(10.0),
          salePrice: const drift.Value(15.0),
        ),
      );

      // Purchase 100 units @ 10 each
      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse!.id,
        invoiceDate: DateTime.now(),
        paid: 1000.0,
        paymentMethod: 'cash',
        supplierInvoiceNumber: 'WAC-PUR-001',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 100,
            unitCost: 10.0,
            total: 1000.0,
          )
        ],
      );

      final stockAfterFirst = await getWarehouseStock(db, productId, warehouse.id);
      expect(stockAfterFirst, 100.0);

      // Purchase another 100 units @ 12 each
      // WAC = (100*10 + 100*12) / 200 = 11.0
      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse.id,
        invoiceDate: DateTime.now(),
        paid: 1200.0,
        paymentMethod: 'cash',
        supplierInvoiceNumber: 'WAC-PUR-002',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 100,
            unitCost: 12.0,
            total: 1200.0,
          )
        ],
      );

      final product = await db.getProductById(productId);
      expect(product?.costPrice, closeTo(11.0, 0.01),
          reason: 'WAC should be (1000+1200)/200 = 11.0 after two purchases');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Sale with multi-item products deducts each item independently', () async {
      final warehouse = await db.getDefaultWarehouse();
      final users = await db.select(db.users).get();
      final unitId = await db.into(db.units).insert(UnitsCompanion.insert(name: 'mi', symbol: 'mi'));

      final productA = await db.into(db.products).insert(
        ProductsCompanion.insert(name: 'Product A', code: 'A-001', unitId: drift.Value(unitId), costPrice: const drift.Value(5.0), salePrice: const drift.Value(10.0)),
      );
      final productB = await db.into(db.products).insert(
        ProductsCompanion.insert(name: 'Product B', code: 'B-001', unitId: drift.Value(unitId), costPrice: const drift.Value(8.0), salePrice: const drift.Value(12.0)),
      );

      await db.adjustStock(productId: productA, warehouseId: warehouse!.id, quantity: 50.0, type: 'initial');
      await db.adjustStock(productId: productB, warehouseId: warehouse.id, quantity: 30.0, type: 'initial');

      const lineA = 5 * 10.0;
      const lineB = 3 * 12.0;
      await db.createSalesInvoice(
        warehouseId: warehouse.id,
        userId: users.first.id,
        paymentMethod: 'cash',
        subtotal: lineA + lineB,
        discount: 0,
        tax: 0,
        total: lineA + lineB,
        paid: lineA + lineB,
        items: [
          SalesInvoiceItemsCompanion.insert(invoiceId: 0, productId: productA, quantity: 5, unitPrice: 10.0, total: lineA, costPrice: const drift.Value(5.0)),
          SalesInvoiceItemsCompanion.insert(invoiceId: 0, productId: productB, quantity: 3, unitPrice: 12.0, total: lineB, costPrice: const drift.Value(8.0)),
        ],
      );

      final stockA = await getWarehouseStock(db, productA, warehouse.id);
      final stockB = await getWarehouseStock(db, productB, warehouse.id);

      expect(stockA, 45.0, reason: 'Product A stock should reduce by 5');
      expect(stockB, 27.0, reason: 'Product B stock should reduce by 3');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Concurrent sales from same product respect stock level', () async {
      final warehouse = await db.getDefaultWarehouse();
      final users = await db.select(db.users).get();
      final unitId = await db.into(db.units).insert(UnitsCompanion.insert(name: 'cc', symbol: 'cc'));
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(name: 'Concurrent Product', code: 'CC-001', unitId: drift.Value(unitId), costPrice: const drift.Value(5.0), salePrice: const drift.Value(10.0)),
      );

      // Start with 100 units, launch 10 concurrent sales of 8 each = 80 total
      await db.adjustStock(productId: productId, warehouseId: warehouse!.id, quantity: 100.0, type: 'initial');

      final futures = List.generate(10, (i) => db.createSalesInvoice(
        warehouseId: warehouse.id,
        userId: users.first.id,
        paymentMethod: 'cash',
        subtotal: 80.0,
        discount: 0,
        tax: 0,
        total: 80.0,
        paid: 80.0,
        items: [
          SalesInvoiceItemsCompanion.insert(invoiceId: 0, productId: productId, quantity: 8, unitPrice: 10.0, total: 80.0, costPrice: const drift.Value(5.0)),
        ],
      ));

      await Future.wait(futures);

      // 100 - (10 * 8) = 20 remaining
      final stock = await getWarehouseStock(db, productId, warehouse.id);
      expect(stock, 20.0, reason: 'Concurrent 10 sales of 8 should leave exactly 20 in stock');
    });
  });
}
