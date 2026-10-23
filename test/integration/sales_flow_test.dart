import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/usecases/sales/add_to_cart_usecase.dart';
import 'package:picpos_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'package:picpos_erp/domain/usecases/sales/cart_operations_usecase.dart';

/// Integration test for complete sales flow
/// Tests the business logic from adding items to calculating totals
void main() {
  group('Sales Flow Integration', () {
    late AddToCartUseCase addToCart;
    late CalculateInvoiceTotalsUseCase calculateTotals;
    late RemoveFromCartUseCase removeFromCart;
    late UpdateCartQuantityUseCase updateQuantity;
    late ClearCartUseCase clearCart;
    late List<CartItemEntity> cart;

    setUp(() {
      addToCart = AddToCartUseCase();
      calculateTotals = CalculateInvoiceTotalsUseCase();
      removeFromCart = RemoveFromCartUseCase();
      updateQuantity = UpdateCartQuantityUseCase();
      clearCart = ClearCartUseCase();
      cart = [];
    });

    test('complete sale flow: add items, update quantities, calculate total', () {
      // Step 1: Add first product
      cart = addToCart.execute(
        currentCart: cart,
        productId: 1,
        productName: 'iPhone 14',
        productCode: 'IPHONE14',
        unitPrice: 35000.0,
        quantity: 1,
      );
      expect(cart.length, 1);
      expect(cart[0].quantity, 1);

      // Step 2: Add same product again (should increase quantity)
      cart = addToCart.execute(
        currentCart: cart,
        productId: 1,
        productName: 'iPhone 14',
        productCode: 'IPHONE14',
        unitPrice: 35000.0,
        quantity: 1,
      );
      expect(cart.length, 1);
      expect(cart[0].quantity, 2);

      // Step 3: Add different product
      cart = addToCart.execute(
        currentCart: cart,
        productId: 2,
        productName: 'AirPods Pro',
        productCode: 'AIRPODS',
        unitPrice: 8000.0,
        quantity: 1,
      );
      expect(cart.length, 2);

      // Step 4: Calculate totals
      var totals = calculateTotals.execute(items: cart);
      expect(totals.itemCount, 2);
      expect(totals.subtotal, 78000.0); // 2*35000 + 1*8000

      // Step 5: Apply invoice discount
      totals = calculateTotals.execute(
        items: cart,
        invoiceDiscountPercent: 5,
      );
      expect(totals.invoiceDiscount, 3900.0); // 5% of 78000
      expect(totals.total, 74100.0);

      // Step 6: Apply tax
      totals = calculateTotals.execute(
        items: cart,
        invoiceDiscountPercent: 5,
        taxPercent: 14,
      );
      expect(totals.taxAmount, closeTo(10374.0, 1)); // 14% of 74100
      expect(totals.total, closeTo(84474.0, 1));
    });

    test('sale with item-level discounts', () {
      // Add item 
      cart = addToCart.execute(
        currentCart: cart,
        productId: 1,
        productName: 'Laptop',
        productCode: 'LAPTOP',
        unitPrice: 20000.0,
        quantity: 1,
      );

      // Apply discount via cart item property
      final discountedCart = [cart[0].copyWith(discountPercent: 10)];

      final totals = calculateTotals.execute(items: discountedCart);
      expect(totals.subtotal, 20000.0);
      expect(totals.itemDiscounts, 2000.0);
      expect(totals.total, 18000.0);
    });

    test('sale with custom price', () {
      cart = addToCart.execute(
        currentCart: cart,
        productId: 1,
        productName: 'Special Item',
        productCode: 'SPECIAL',
        unitPrice: 1000.0,
        quantity: 5,
        customPrice: 800.0, // Manager override price
      );

      expect(cart[0].effectivePrice, 800.0);
      expect(cart[0].total, 4000.0);
    });

    test('cart modification flow', () {
      // Add items
      cart = addToCart.execute(
        currentCart: cart,
        productId: 1,
        productName: 'Item A',
        productCode: 'A',
        unitPrice: 100.0,
        quantity: 5,
      );
      cart = addToCart.execute(
        currentCart: cart,
        productId: 2,
        productName: 'Item B',
        productCode: 'B',
        unitPrice: 200.0,
        quantity: 3,
      );

      // Initial total
      var totals = calculateTotals.execute(items: cart);
      expect(totals.subtotal, 1100.0); // 500 + 600

      // Update quantity of first item
      cart = updateQuantity.execute(currentCart: cart, index: 0, newQuantity: 10);
      totals = calculateTotals.execute(items: cart);
      expect(totals.subtotal, 1600.0); // 1000 + 600

      // Remove second item
      cart = removeFromCart.execute(currentCart: cart, index: 1);
      totals = calculateTotals.execute(items: cart);
      expect(cart.length, 1);
      expect(totals.subtotal, 1000.0);

      // Clear cart
      cart = clearCart.execute();
      expect(cart.isEmpty, true);
    });

    test('payment calculation', () {
      cart = addToCart.execute(
        currentCart: cart,
        productId: 1,
        productName: 'Product',
        productCode: 'PRD',
        unitPrice: 150.0,
        quantity: 4,
      );

      final totals = calculateTotals.execute(items: cart);
      expect(totals.total, 600.0);

      // Customer pays 1000
      expect(totals.changeFor(1000), 400.0);
      expect(totals.remainingFor(1000), 0.0);

      // Customer pays 400 (partial)
      expect(totals.changeFor(400), 0.0);
      expect(totals.remainingFor(400), 200.0);
    });

    test('weight-based product sale', () {
      // First weight entry
      cart = addToCart.execute(
        currentCart: cart,
        productId: 1,
        productName: 'Chicken',
        productCode: 'CHICKEN',
        unitPrice: 120.0, // per kg
        quantity: 1.5, // 1.5 kg
      );

      // Second weight entry for same product - will merge since not marked as weight-based
      cart = addToCart.execute(
        currentCart: cart,
        productId: 1,
        productName: 'Chicken',
        productCode: 'CHICKEN',
        unitPrice: 120.0,
        quantity: 0.75,
      );

      // Items merged
      expect(cart.length, 1);
      expect(cart[0].quantity, 2.25);

      final totals = calculateTotals.execute(items: cart);
      expect(totals.subtotal, 270.0); // 2.25 * 120
    });
  });
}
