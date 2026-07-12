import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/purchases_state.dart';

/// Integration test for complete purchase flow
/// Tests the business logic for purchase operations
void main() {
  group('Purchase Flow Integration', () {
    late PurchasesState state;

    setUp(() {
      state = PurchasesState.initial();
    });

    test('purchase state initialization', () {
      expect(state.cart, isEmpty);
      expect(state.selectedSupplierId, isNull);
      expect(state.paid, 0);
      expect(state.total, 0);
      expect(state.remaining, 0);
      expect(state.isEditing, false);
    });

    test('purchase cart calculations', () {
      // Simulate adding items to cart
      final items = [
        const PurchaseCartItemEntity(
          productId: 1,
          productName: 'Rice 5kg',
          productCode: 'RICE5',
          quantity: 10,
          unitCost: 150.0,
        ),
        const PurchaseCartItemEntity(
          productId: 2,
          productName: 'Sugar 1kg',
          productCode: 'SUGAR1',
          quantity: 20,
          unitCost: 45.0,
        ),
      ];

      state = state.copyWith(cart: items);
      
      expect(state.cart.length, 2);
      expect(state.subtotal, 2400.0); // 10*150 + 20*45
      expect(state.total, 2400.0);
    });

    test('purchase with partial payment', () {
      final items = [
        const PurchaseCartItemEntity(
          productId: 1,
          productName: 'Product',
          productCode: 'PRD',
          quantity: 10,
          unitCost: 100.0,
        ),
      ];

      state = state.copyWith(
        cart: items,
        paid: 500.0,
      );

      expect(state.total, 1000.0);
      expect(state.paid, 500.0);
      expect(state.remaining, 500.0);
    });

    test('purchase cart item with batch info', () {
      final item = PurchaseCartItemEntity(
        productId: 1,
        productName: 'Medicine',
        productCode: 'MED001',
        quantity: 50,
        unitCost: 25.0,
        batchNumber: 'B20260117',
        expiryDate: DateTime(2027, 6, 30),
      );

      expect(item.batchNumber, 'B20260117');
      expect(item.expiryDate, isNotNull);
      expect(item.total, 1250.0);
    });

    test('cart item copyWith', () {
      const original = PurchaseCartItemEntity(
        productId: 1,
        productName: 'Test',
        productCode: 'TST',
        quantity: 10,
        unitCost: 50.0,
      );

      final updated = original.copyWith(
        quantity: 20,
        unitCost: 45.0,
      );

      expect(updated.quantity, 20);
      expect(updated.unitCost, 45.0);
      expect(updated.productId, 1); // Unchanged
      expect(updated.total, 900.0); // 20 * 45
    });

    test('state copyWith preserves values', () {
      state = state.copyWith(
        selectedSupplierId: 5,
        selectedSupplierName: 'Test Supplier',
        paid: 1000,
      );

      final newState = state.copyWith(
        notes: 'Test notes',
      );

      expect(newState.selectedSupplierId, 5);
      expect(newState.selectedSupplierName, 'Test Supplier');
      expect(newState.paid, 1000);
      expect(newState.notes, 'Test notes');
    });

    test('clear supplier', () {
      state = state.copyWith(
        selectedSupplierId: 5,
        selectedSupplierName: 'Supplier Name',
      );

      state = state.clearSupplier();

      expect(state.selectedSupplierId, isNull);
      expect(state.selectedSupplierName, isNull);
    });

    test('editing mode detection', () {
      expect(state.isEditing, false);

      state = state.copyWith(editingInvoiceId: 15);
      expect(state.isEditing, true);
    });
  });
}
