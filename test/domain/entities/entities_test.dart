import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/entities/party_entity.dart';
import 'package:picpos_erp/domain/entities/invoice_entity.dart';

void main() {
  group('CartItemEntity', () {
    test('should calculate subtotal correctly', () {
      const item = CartItemEntity(
        productId: 1,
        productName: 'Test',
        productCode: 'TST',
        quantity: 3,
        unitPrice: 10.0,
      );

      expect(item.subtotal, 30.0);
    });

    test('should use custom price in effectivePrice', () {
      const item = CartItemEntity(
        productId: 1,
        productName: 'Test',
        productCode: 'TST',
        quantity: 2,
        unitPrice: 10.0,
        customPrice: 8.0,
      );

      expect(item.effectivePrice, 8.0);
      expect(item.total, 16.0);
    });

    test('should calculate discount correctly', () {
      const item = CartItemEntity(
        productId: 1,
        productName: 'Test',
        productCode: 'TST',
        quantity: 10,
        unitPrice: 10.0,
        discountPercent: 20,
      );

      expect(item.subtotal, 100.0);
      expect(item.discountAmount, 20.0);
      expect(item.total, 80.0);
    });

    test('copyWith should work correctly', () {
      const item = CartItemEntity(
        productId: 1,
        productName: 'Test',
        productCode: 'TST',
        quantity: 1,
        unitPrice: 10.0,
      );

      final updated = item.copyWith(quantity: 5, customPrice: 8.0);

      expect(updated.quantity, 5);
      expect(updated.customPrice, 8.0);
      expect(updated.productId, 1); // Unchanged
    });
  });

  group('ProductEntity', () {
    test('should identify low stock correctly', () {
      const product = ProductEntity(
        id: 1,
        code: 'TST',
        name: 'Test',
        salePrice: 10.0,
        costPrice: 5.0,
        currentStock: 5,
        minStock: 10,
        trackInventory: true,
      );

      expect(product.isLowStock, true);
      expect(product.isOutOfStock, false);
    });

    test('should identify out of stock correctly', () {
      const product = ProductEntity(
        id: 1,
        code: 'TST',
        name: 'Test',
        salePrice: 10.0,
        costPrice: 5.0,
        currentStock: 0,
        minStock: 10,
        trackInventory: true,
      );

      expect(product.isOutOfStock, true);
    });

    test('should calculate profit margin correctly', () {
      const product = ProductEntity(
        id: 1,
        code: 'TST',
        name: 'Test',
        salePrice: 150.0,
        costPrice: 100.0,
        currentStock: 10,
        minStock: 5,
      );

      expect(product.profitMargin, 50.0); // (150-100)/100 * 100
    });

    test('should calculate stock value correctly', () {
      const product = ProductEntity(
        id: 1,
        code: 'TST',
        name: 'Test',
        salePrice: 15.0,
        costPrice: 10.0,
        currentStock: 50,
        minStock: 5,
      );

      expect(product.stockValue, 500.0); // 50 * 10
    });
  });

  group('PartyEntity', () {
    test('should identify dual role party', () {
      const party = PartyEntity(
        id: 1,
        name: 'Test Company',
        isCustomer: true,
        isSupplier: true,
      );

      expect(party.isDualRole, true);
    });

    test('should identify credit exceeded', () {
      const party = PartyEntity(
        id: 1,
        name: 'Test',
        balance: 5000,
        creditLimit: 3000,
      );

      expect(party.creditExceeded, true);
      expect(party.availableCredit, -2000);
    });

    test('should calculate available credit correctly', () {
      const party = PartyEntity(
        id: 1,
        name: 'Test',
        balance: 1000,
        creditLimit: 5000,
      );

      expect(party.availableCredit, 4000);
    });

    test('should identify owes/owed correctly', () {
      const owes = PartyEntity(id: 1, name: 'Test', balance: 100);
      const owed = PartyEntity(id: 2, name: 'Test', balance: -100);

      expect(owes.owes, true);
      expect(owes.owed, false);
      expect(owed.owes, false);
      expect(owed.owed, true);
    });
  });

  group('InvoiceEntity', () {
    test('should calculate remaining correctly', () {
      final invoice = InvoiceEntity(
        invoiceNumber: 'INV001',
        type: InvoiceType.sale,
        invoiceDate: DateTime.now(),
        lines: [],
        subtotal: 100,
        total: 100,
        paid: 60,
        status: InvoiceStatus.partial,
      );

      expect(invoice.remaining, 40);
      expect(invoice.isFullyPaid, false);
      expect(invoice.hasPayment, true);
    });

    test('should identify fully paid invoice', () {
      final invoice = InvoiceEntity(
        invoiceNumber: 'INV001',
        type: InvoiceType.sale,
        invoiceDate: DateTime.now(),
        lines: [],
        subtotal: 100,
        total: 100,
        paid: 100,
        status: InvoiceStatus.paid,
      );

      expect(invoice.isFullyPaid, true);
      expect(invoice.remaining, 0);
    });
  });
}
