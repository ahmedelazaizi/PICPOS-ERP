import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/usecases/sales/cart_operations_usecase.dart';

void main() {
  group('CartOperationsUseCases', () {
    group('RemoveFromCartUseCase', () {
      late RemoveFromCartUseCase useCase;

      setUp(() {
        useCase = RemoveFromCartUseCase();
      });

      test('should remove item at specified index', () {
        final cart = [
          const CartItemEntity(productId: 1, productName: 'A', productCode: 'A', quantity: 1, unitPrice: 10),
          const CartItemEntity(productId: 2, productName: 'B', productCode: 'B', quantity: 1, unitPrice: 20),
          const CartItemEntity(productId: 3, productName: 'C', productCode: 'C', quantity: 1, unitPrice: 30),
        ];

        final result = useCase.execute(currentCart: cart, index: 1);

        expect(result.length, 2);
        expect(result[0].productId, 1);
        expect(result[1].productId, 3);
      });

      test('should return same cart for invalid index', () {
        final cart = [
          const CartItemEntity(productId: 1, productName: 'A', productCode: 'A', quantity: 1, unitPrice: 10),
        ];

        final result = useCase.execute(currentCart: cart, index: 5);

        expect(result.length, 1);
        expect(result, cart);
      });

      test('should handle negative index', () {
        final cart = [
          const CartItemEntity(productId: 1, productName: 'A', productCode: 'A', quantity: 1, unitPrice: 10),
        ];

        final result = useCase.execute(currentCart: cart, index: -1);

        expect(result, cart);
      });
    });

    group('UpdateCartQuantityUseCase', () {
      late UpdateCartQuantityUseCase useCase;

      setUp(() {
        useCase = UpdateCartQuantityUseCase();
      });

      test('should update quantity at specified index', () {
        final cart = [
          const CartItemEntity(productId: 1, productName: 'A', productCode: 'A', quantity: 1, unitPrice: 10),
        ];

        final result = useCase.execute(currentCart: cart, index: 0, newQuantity: 5);

        expect(result[0].quantity, 5);
        expect(result[0].total, 50);
      });

      test('should remove item when quantity is zero', () {
        final cart = [
          const CartItemEntity(productId: 1, productName: 'A', productCode: 'A', quantity: 5, unitPrice: 10),
        ];

        final result = useCase.execute(currentCart: cart, index: 0, newQuantity: 0);

        expect(result.length, 0);
      });

      test('should remove item when quantity is negative', () {
        final cart = [
          const CartItemEntity(productId: 1, productName: 'A', productCode: 'A', quantity: 5, unitPrice: 10),
        ];

        final result = useCase.execute(currentCart: cart, index: 0, newQuantity: -1);

        expect(result.length, 0);
      });
    });

    group('UpdateCartPriceUseCase', () {
      late UpdateCartPriceUseCase useCase;

      setUp(() {
        useCase = UpdateCartPriceUseCase();
      });

      test('should update custom price at specified index', () {
        final cart = [
          const CartItemEntity(productId: 1, productName: 'A', productCode: 'A', quantity: 2, unitPrice: 10),
        ];

        final result = useCase.execute(currentCart: cart, index: 0, newPrice: 8.0);

        expect(result[0].customPrice, 8.0);
        expect(result[0].effectivePrice, 8.0);
        expect(result[0].total, 16.0); // 2 * 8
      });
    });

    group('ClearCartUseCase', () {
      late ClearCartUseCase useCase;

      setUp(() {
        useCase = ClearCartUseCase();
      });

      test('should return empty list', () {
        final result = useCase.execute();

        expect(result, isEmpty);
        expect(result, isA<List<CartItemEntity>>());
      });
    });
  });
}
