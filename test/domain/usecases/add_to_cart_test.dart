import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/usecases/sales/add_to_cart_usecase.dart';

void main() {
  group('AddToCartUseCase', () {
    late AddToCartUseCase useCase;

    setUp(() {
      useCase = AddToCartUseCase();
    });

    test('should add new product to empty cart', () {
      final result = useCase.execute(
        currentCart: [],
        productId: 1,
        productName: 'Apple',
        productCode: 'APL001',
        unitPrice: 5.0,
        quantity: 2,
      );

      expect(result.length, 1);
      expect(result[0].productId, 1);
      expect(result[0].productName, 'Apple');
      expect(result[0].quantity, 2);
      expect(result[0].unitPrice, 5.0);
      expect(result[0].total, 10.0);
    });

    test('should update quantity for existing product', () {
      final existingCart = [
        const CartItemEntity(
          productId: 1,
          productName: 'Apple',
          productCode: 'APL001',
          quantity: 3,
          unitPrice: 5.0,
        ),
      ];

      final result = useCase.execute(
        currentCart: existingCart,
        productId: 1,
        productName: 'Apple',
        productCode: 'APL001',
        unitPrice: 5.0,
        quantity: 2,
      );

      expect(result.length, 1);
      expect(result[0].quantity, 5); // 3 + 2
      expect(result[0].total, 25.0); // 5 * 5
    });

    test('should add new item for weight-based product even if exists', () {
      final existingCart = [
        const CartItemEntity(
          productId: 1,
          productName: 'Meat',
          productCode: 'MEAT01',
          quantity: 1.5,
          unitPrice: 100.0,
          isSoldByWeight: true,
        ),
      ];

      final result = useCase.execute(
        currentCart: existingCart,
        productId: 1,
        productName: 'Meat',
        productCode: 'MEAT01',
        unitPrice: 100.0,
        quantity: 0.75,
        isSoldByWeight: true,
      );

      // Should have two entries for weight-based products
      expect(result.length, 2);
    });

    test('should apply custom price when provided', () {
      final result = useCase.execute(
        currentCart: [],
        productId: 1,
        productName: 'Apple',
        productCode: 'APL001',
        unitPrice: 5.0,
        quantity: 2,
        customPrice: 4.0,
      );

      expect(result[0].customPrice, 4.0);
      expect(result[0].effectivePrice, 4.0);
      expect(result[0].total, 8.0); // 2 * 4
    });
  });
}
