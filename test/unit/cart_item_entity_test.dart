// =============================================================================
// CartItemEntity UOM & Calculation Tests
// PIR Phase 2 — Test coverage increase
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';

CartItemEntity _makeItem({
  double quantity = 1,
  double unitPrice = 100,
  double? customPrice,
  double discountPercent = 0,
  double taxRate = 0,
  double taxAmount = 0,
  double quantityInBase = 1,
  String? selectedUnitName,
  int? selectedUnitId,
  CartItemType itemType = CartItemType.normal,
}) {
  return CartItemEntity(
    productId: 1,
    productName: 'Test Product',
    productCode: 'P001',
    quantity: quantity,
    unitPrice: unitPrice,
    customPrice: customPrice,
    discountPercent: discountPercent,
    taxRate: taxRate,
    taxAmount: taxAmount,
    quantityInBase: quantityInBase,
    selectedUnitName: selectedUnitName,
    selectedUnitId: selectedUnitId,
    itemType: itemType,
  );
}

void main() {
  group('CartItemEntity — Basic Pricing', () {
    test('effectivePrice returns unitPrice when no customPrice', () {
      final item = _makeItem(unitPrice: 50);
      expect(item.effectivePrice, 50.0);
    });

    test('effectivePrice returns customPrice when set', () {
      final item = _makeItem(unitPrice: 50, customPrice: 40);
      expect(item.effectivePrice, 40.0);
    });

    test('subtotal = quantity × effectivePrice', () {
      final item = _makeItem(quantity: 3, unitPrice: 100);
      expect(item.subtotal, 300.0);
    });

    test('subtotal with customPrice', () {
      final item = _makeItem(quantity: 5, unitPrice: 100, customPrice: 80);
      expect(item.subtotal, 400.0);
    });

    test('subtotal rounds to three decimal places (JOD fils)', () {
      final item = _makeItem(quantity: 3, unitPrice: 33.333);
      // 3 × 33.333 = 99.999 — at 3dp this is exact; rounds to 100.0 only at 2dp
      expect(item.subtotal, closeTo(99.999, 0.0001));
    });
  });

  group('CartItemEntity — Discount Calculations', () {
    test('discountAmount with 10% discount', () {
      final item = _makeItem(quantity: 1, unitPrice: 200, discountPercent: 10);
      expect(item.discountAmount, 20.0);
    });

    test('discountAmount with zero discount', () {
      final item = _makeItem(quantity: 2, unitPrice: 100, discountPercent: 0);
      expect(item.discountAmount, 0.0);
    });

    test('discountAmount with 100% discount', () {
      final item = _makeItem(quantity: 1, unitPrice: 150, discountPercent: 100);
      expect(item.discountAmount, 150.0);
    });

    test('totalBeforeTax = subtotal - discountAmount', () {
      final item = _makeItem(quantity: 2, unitPrice: 100, discountPercent: 25);
      // subtotal = 200, discount = 50, totalBeforeTax = 150
      expect(item.totalBeforeTax, 150.0);
    });
  });

  group('CartItemEntity — Tax Calculations', () {
    test('calculatedTaxAmount with 14% VAT', () {
      final item = _makeItem(quantity: 1, unitPrice: 100, taxRate: 14);
      // totalBeforeTax = 100, tax = 14
      expect(item.calculatedTaxAmount, 14.0);
    });

    test('total = totalBeforeTax + calculatedTaxAmount', () {
      final item = _makeItem(quantity: 1, unitPrice: 100, taxRate: 14);
      expect(item.total, 114.0);
    });

    test('total with discount and tax', () {
      final item = _makeItem(
        quantity: 2,
        unitPrice: 100,
        discountPercent: 10,
        taxRate: 14,
      );
      // subtotal = 200
      // discount = 20
      // totalBeforeTax = 180
      // tax = 25.2
      // total = 205.2
      expect(item.total, 205.2);
    });

    test('total with zero tax', () {
      final item = _makeItem(quantity: 3, unitPrice: 50, taxRate: 0);
      expect(item.total, 150.0);
    });
  });

  group('CartItemEntity — UOM Conversion', () {
    test('stockQuantity equals quantity when base unit (quantityInBase=1)', () {
      final item = _makeItem(quantity: 5, quantityInBase: 1);
      expect(item.stockQuantity, 5.0);
    });

    test('stockQuantity converts carton (24 pieces) correctly', () {
      final item = _makeItem(quantity: 3, quantityInBase: 24);
      // 3 cartons × 24 pieces/carton = 72 pieces
      expect(item.stockQuantity, 72.0);
    });

    test('stockQuantity converts box (6 pieces) correctly', () {
      final item = _makeItem(quantity: 10, quantityInBase: 6);
      // 10 boxes × 6 pieces/box = 60 pieces
      expect(item.stockQuantity, 60.0);
    });

    test('stockQuantity with fractional quantity', () {
      final item = _makeItem(quantity: 0.5, quantityInBase: 12);
      // 0.5 box × 12 = 6 pieces
      expect(item.stockQuantity, 6.0);
    });

    test('stockQuantity with fractional conversion factor', () {
      final item = _makeItem(quantity: 2, quantityInBase: 2.5);
      // 2 × 2.5 = 5
      expect(item.stockQuantity, 5.0);
    });
  });

  group('CartItemEntity — copyWith', () {
    test('copyWith preserves all fields when no changes', () {
      final item = _makeItem(
        quantity: 3,
        unitPrice: 100,
        customPrice: 90,
        discountPercent: 5,
        taxRate: 14,
        quantityInBase: 24,
        selectedUnitName: 'كرتونة',
        selectedUnitId: 7,
      );
      final copy = item.copyWith();
      expect(copy.quantity, 3);
      expect(copy.unitPrice, 100);
      expect(copy.customPrice, 90);
      expect(copy.discountPercent, 5);
      expect(copy.taxRate, 14);
      expect(copy.quantityInBase, 24);
      expect(copy.selectedUnitName, 'كرتونة');
      expect(copy.selectedUnitId, 7);
    });

    test('copyWith changes quantity', () {
      final item = _makeItem(quantity: 1);
      final updated = item.copyWith(quantity: 5);
      expect(updated.quantity, 5);
      expect(updated.productId, item.productId);
    });

    test('copyWith changes unit and price together', () {
      final item = _makeItem(unitPrice: 10, quantityInBase: 1);
      final updated = item.copyWith(
        selectedUnitId: 3,
        selectedUnitName: 'علبة',
        quantityInBase: 6,
        customPrice: 55,
      );
      expect(updated.selectedUnitId, 3);
      expect(updated.selectedUnitName, 'علبة');
      expect(updated.quantityInBase, 6);
      expect(updated.customPrice, 55);
    });

    test('copyWith preserves itemType', () {
      final item = _makeItem(itemType: CartItemType.returned);
      final copy = item.copyWith(quantity: 2);
      expect(copy.itemType, CartItemType.returned);
    });
  });

  group('CartItemEntity — Edge Cases', () {
    test('zero quantity item', () {
      final item = _makeItem(quantity: 0, unitPrice: 100);
      expect(item.subtotal, 0.0);
      expect(item.total, 0.0);
      expect(item.stockQuantity, 0.0);
    });

    test('zero price item', () {
      final item = _makeItem(quantity: 5, unitPrice: 0);
      expect(item.subtotal, 0.0);
      expect(item.total, 0.0);
    });

    test('very large quantity', () {
      final item = _makeItem(quantity: 999999, unitPrice: 0.01);
      expect(item.subtotal, closeTo(9999.99, 0.01));
    });

    test('100% discount results in zero total', () {
      final item = _makeItem(
        quantity: 5,
        unitPrice: 200,
        discountPercent: 100,
        taxRate: 14,
      );
      expect(item.totalBeforeTax, 0.0);
      expect(item.calculatedTaxAmount, 0.0);
      expect(item.total, 0.0);
    });

    test('returned item total is same magnitude', () {
      final normal = _makeItem(quantity: 2, unitPrice: 100);
      final returned = _makeItem(
        quantity: 2,
        unitPrice: 100,
        itemType: CartItemType.returned,
      );
      expect(normal.total, returned.total);
    });
  });

  group('CartItemEntity — Equality', () {
    test('same productId + quantity + price are equal', () {
      final a = _makeItem(quantity: 2, unitPrice: 100);
      final b = _makeItem(quantity: 2, unitPrice: 100);
      expect(a, equals(b));
    });

    test('different quantity are not equal', () {
      final a = _makeItem(quantity: 2, unitPrice: 100);
      final b = _makeItem(quantity: 3, unitPrice: 100);
      expect(a, isNot(equals(b)));
    });

    test('different customPrice makes not equal', () {
      final a = _makeItem(quantity: 1, unitPrice: 100, customPrice: 90);
      final b = _makeItem(quantity: 1, unitPrice: 100, customPrice: 80);
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent for equal objects', () {
      final a = _makeItem(quantity: 5, unitPrice: 50);
      final b = _makeItem(quantity: 5, unitPrice: 50);
      expect(a.hashCode, b.hashCode);
    });
  });
}
