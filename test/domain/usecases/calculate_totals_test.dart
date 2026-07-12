import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';

void main() {
  group('CalculateInvoiceTotalsUseCase', () {
    late CalculateInvoiceTotalsUseCase useCase;

    setUp(() {
      useCase = CalculateInvoiceTotalsUseCase();
    });

    test('should return empty totals for empty cart', () {
      final result = useCase.execute(items: []);

      expect(result.itemCount, 0);
      expect(result.subtotal, 0);
      expect(result.total, 0);
    });

    test('should calculate correct subtotal', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'Apple',
          productCode: 'APL',
          quantity: 5,
          unitPrice: 10.0,
        ),
        const CartItemEntity(
          productId: 2,
          productName: 'Banana',
          productCode: 'BAN',
          quantity: 3,
          unitPrice: 5.0,
        ),
      ];

      final result = useCase.execute(items: items);

      expect(result.itemCount, 2);
      expect(result.subtotal, 65.0); // 5*10 + 3*5
      expect(result.total, 65.0);
    });

    test('should apply invoice discount percentage', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'Apple',
          productCode: 'APL',
          quantity: 10,
          unitPrice: 10.0,
        ),
      ];

      final result = useCase.execute(
        items: items,
        invoiceDiscountPercent: 10, // 10% discount
      );

      expect(result.subtotal, 100.0);
      expect(result.invoiceDiscount, 10.0);
      expect(result.total, 90.0); // 100 - 10
    });

    test('should apply tax correctly', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'Apple',
          productCode: 'APL',
          quantity: 10,
          unitPrice: 10.0,
        ),
      ];

      final result = useCase.execute(
        items: items,
        taxPercent: 14, // 14% tax
      );

      expect(result.subtotal, 100.0);
      expect(result.taxAmount, closeTo(14.0, 0.01));
      expect(result.total, closeTo(114.0, 0.01)); // 100 + 14
    });

    test('should apply both discount and tax', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'Apple',
          productCode: 'APL',
          quantity: 10,
          unitPrice: 100.0,
        ),
      ];

      final result = useCase.execute(
        items: items,
        invoiceDiscountPercent: 10, // 10% discount
        taxPercent: 14, // 14% tax
      );

      expect(result.subtotal, 1000.0);
      expect(result.invoiceDiscount, closeTo(100.0, 0.01)); // 10% of 1000
      // After discount: 900
      expect(result.taxAmount, closeTo(126.0, 0.01)); // 14% of 900
      expect(result.total, closeTo(1026.0, 0.01)); // 900 + 126
    });

    test('should calculate item-level discounts', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'Apple',
          productCode: 'APL',
          quantity: 10,
          unitPrice: 10.0,
          discountPercent: 20, // 20% line discount
        ),
      ];

      final result = useCase.execute(items: items);

      expect(result.subtotal, 100.0);
      expect(result.itemDiscounts, 20.0); // 20% of 100
      expect(result.total, 80.0);
    });

    test('should calculate change correctly', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'Apple',
          productCode: 'APL',
          quantity: 10,
          unitPrice: 10.0,
        ),
      ];

      final result = useCase.execute(items: items);

      expect(result.changeFor(150), 50.0); // 150 paid, 100 total
      expect(result.changeFor(100), 0.0); // Exact payment
      expect(result.changeFor(80), 0.0); // Under payment - no change
    });

    test('should calculate remaining balance', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'Apple',
          productCode: 'APL',
          quantity: 10,
          unitPrice: 10.0,
        ),
      ];

      final result = useCase.execute(items: items);

      expect(result.remainingFor(60), 40.0); // 100 - 60
      expect(result.remainingFor(100), 0.0); // Full payment
    });
  });
}
