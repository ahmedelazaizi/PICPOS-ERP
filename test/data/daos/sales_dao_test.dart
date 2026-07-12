import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    
    // Seed required data: warehouse and user with role reference
    await database.into(database.warehouses).insert(
      WarehousesCompanion.insert(name: 'Test Warehouse'),
    );
    
    final roleId = await database.into(database.roles).insert(
      RolesCompanion.insert(name: 'مدير النظام', isSystemRole: const Value(true))
    );

    await database.createUser(
      username: 'testuser',
      password: 'test123',
      displayName: 'Test User',
      roleId: roleId,
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('SalesDao - Accounting & Tax Features', () {
    test('createSalesInvoice - should record taxRate and taxAmount per item', () async {
      final productId = await database.insertProduct(
        ProductsCompanion.insert(
          code: 'TAX01',
          name: 'Taxable Product',
          salePrice: const Value(100.0),
          trackInventory: const Value(false),
        ),
      );

      final invoiceId = await database.createSalesInvoice(
        invoiceNumber: 'INV-TAX-001',
        warehouseId: 1,
        userId: 1,
        subtotal: 100.0,
        discount: 0.0,
        tax: 15.0,
        total: 115.0,
        paid: 115.0,
        paymentMethod: 'نقدي',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0, // Will be overridden by DAO
            productId: productId,
            quantity: 1.0,
            unitPrice: 100.0,
            total: 100.0,
            taxRate: const Value(15.0),
            taxAmount: const Value(15.0),
            sortOrder: const Value(1),
          ),
        ],
      );

      final items = await database.getSalesInvoiceItems(invoiceId);
      expect(items.first.taxRate, 15.0);
      expect(items.first.taxAmount, 15.0);
      expect(items.first.sortOrder, 1);
    });

    test('updateSalesInvoice - should handle tax and sortOrder updates', () async {
       final productId = await database.insertProduct(
        ProductsCompanion.insert(
          code: 'UPDT-TAX',
          name: 'Update Tax Test',
          trackInventory: const Value(false),
        ),
      );

      final invoiceId = await database.createSalesInvoice(
        invoiceNumber: 'INV-UT-001',
        warehouseId: 1,
        userId: 1,
        subtotal: 100.0,
        discount: 0.0,
        tax: 0.0,
        total: 100.0,
        paid: 100.0,
        paymentMethod: 'نقدي',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 100.0,
            total: 100.0,
          ),
        ],
      );

      // ISS-004 locks invoices after autopost; unlock so this test can validate update logic
      await (database.update(database.salesInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .write(const SalesInvoicesCompanion(isLocked: Value(false)));

      // Update with tax
      await database.updateSalesInvoice(
        invoiceId: invoiceId,
        subtotal: 100.0,
        discount: 0.0,
        tax: 5.0,
        total: 105.0,
        paid: 105.0,
        paymentMethod: 'نقدي',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: invoiceId,
            productId: productId,
            quantity: 1.0,
            unitPrice: 100.0,
            total: 100.0,
            taxRate: const Value(5.0),
            taxAmount: const Value(5.0),
            sortOrder: const Value(2),
          ),
        ],
      );

      final items = await database.getSalesInvoiceItems(invoiceId);
      expect(items.first.taxRate, 5.0);
      expect(items.first.sortOrder, 2);
    });
  });

  group('SalesDao - Party Fixed Discount', () {
    test('Parties table should store fixedDiscount', () async {
      final partyId = await database.into(database.parties).insert(
        PartiesCompanion.insert(
          name: 'Premium Customer',
          isCustomer: const Value(true),
          fixedDiscount: const Value(10.0),
        ),
      );

      final party = await (database.select(database.parties)..where((p) => p.id.equals(partyId))).getSingle();
      expect(party.fixedDiscount, 10.0);
    });
  });
}
