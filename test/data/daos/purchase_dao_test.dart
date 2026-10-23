import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

/// Id of the seeded `admin` user (role_id 1 = مدير النظام), who holds
/// `purchases_edit` through the system-admin bypass — `purchases_edit` is a
/// normal permission, not one of `PermissionCodes.criticalFinancialOps`.
///
/// `updatePurchaseInvoice` gates every edit on that permission and denies a
/// null identity, so tests exercising the edit path must supply a real user.
Future<int> _permittedEditorId(AppDatabase db) async {
  final row = await db
      .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
      .getSingle();
  return row.read<int>('id');
}

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    
    // Seed essential data
    await database.into(database.warehouses).insert(
      WarehousesCompanion.insert(name: 'Main Warehouse', isDefault: const Value(true))
    );
    await database.into(database.safes).insert(
      SafesCompanion.insert(name: 'Main Safe', safeType: const Value('cash'), isDefault: const Value(true))
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('PurchaseDao - Invoice Operations', () {
    test('createPurchaseInvoice - should create invoice and update stock', () async {
      // 1. Setup Party and Product
      final supplierId = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'Main Supplier', isSupplier: const Value(true))
      );
      
      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          code: 'PROD001', 
          name: 'Purchase Test Product',
          currentStock: const Value(10.0),
          trackInventory: const Value(true),
        )
      );

      final warehouse = await (database.select(database.warehouses)..limit(1)).getSingle();

      // 2. Create Purchase Invoice
      final items = [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 20.0,
          unitCost: 5.0,
          total: 100.0,
          taxRate: const Value(0),
        )
      ];

      final invoiceId = await database.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse.id,
        items: items,
        paid: 60.0, // Partial payment
        paymentMethod: 'cash',
      );

      // 3. Verify
      expect(invoiceId, isPositive);

      // Verify Stock was updated (10 + 20 = 30)
      final product = await database.getProductById(productId);
      expect(product!.currentStock, 30.0);

      // Verify Supplier Balance (Total 100 - Paid 60 = 40 remaining)
      final supplier = await database.getPartyById(supplierId);
      expect(supplier!.balance, 40.0);

      // Verify Treasury Transaction
      final transactions = await database.select(database.safeTransactions).get();
      expect(transactions.length, 1);
      expect(transactions.first.amount, 60.0);
      expect(transactions.first.transactionType, 'payment');
    });

    test('updatePurchaseInvoice - should reverse old stock and apply new', () async {
      // Setup
      final supplierId = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'Supplier A', isSupplier: const Value(true))
      );
      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          code: 'PROD_UPDATE', 
          name: 'Update Test',
          currentStock: const Value(100.0),
          trackInventory: const Value(true),
        )
      );
      final warehouse = await (database.select(database.warehouses)..limit(1)).getSingle();

      // Create Initial Invoice (Qty 50)
      final invoiceId = await database.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse.id,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 50.0,
            unitCost: 10.0,
            total: 500.0,
            taxRate: const Value(0),
          )
        ],
        paid: 500.0,
        paymentMethod: 'cash',
      );

      // Verify Stock after first (100 + 50 = 150)
      var product = await database.getProductById(productId);
      expect(product!.currentStock, 150.0);

      // Update Invoice (New Qty 30, New UnitCost 12 = 360 total)
      await database.updatePurchaseInvoice(
        invoiceId: invoiceId,
        supplierId: supplierId,
        warehouseId: warehouse.id,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 30.0,
            unitCost: 12.0,
            total: 360.0,
            taxRate: const Value(0),
          )
        ],
        paid: 360.0,
        paymentMethod: 'cash',
        // Purchase-edit policy: `purchases_edit` is required and is evaluated
        // against this id. A null userId is denied outright, so DAO-level
        // tests must act as a real, permitted user.
        userId: await _permittedEditorId(database),
      );

      // Verify Stock (150 - 50 + 30 = 130)
      product = await database.getProductById(productId);
      expect(product!.currentStock, 130.0);

      // Verify Items count
      final items = await database.getPurchaseInvoiceItems(invoiceId);
      expect(items.length, 1);
      expect(items.first.quantity, 30.0);
    });

    test('Purchase Invoice - Expiry Tracking Foundation', () async {
      final supplierId = await database.into(database.parties).insert(
        PartiesCompanion.insert(name: 'Pharma Supplier', isSupplier: const Value(true))
      );
      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          code: 'EXP001', 
          name: 'Expiry Product',
          trackInventory: const Value(true),
          trackExpiry: const Value(true),
        )
      );
      final warehouse = await (database.select(database.warehouses)..limit(1)).getSingle();
      final expiryDate = DateTime.now().add(const Duration(days: 365));

      await database.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse.id,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10.0,
            unitCost: 100.0,
            total: 1000.0,
            batchNumber: const Value('BATCH-001'),
            expiryDate: Value(expiryDate),
            taxRate: const Value(0),
          )
        ],
        paid: 0,
        paymentMethod: 'cash',
      );

      // Verify Batch was created
      final batches = await database.select(database.productBatches).get();
      expect(batches.length, 1);
      expect(batches.first.batchNumber, 'BATCH-001');
      expect(batches.first.expiryDate.year, expiryDate.year);
    });
  });
}
