import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/pos/providers/pos_controller.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/data/database/database.dart';

/// POS Controller Unit Tests
///
/// Tests cover: PosState (UI state), CartItemEntity (pricing/discounts),
/// IndustryMode, and edge cases.
/// Note: PosState is UI-only (category, search, grid, table, delivery).
/// Cart/pricing logic lives in CartItemEntity and the POS controller.
void main() {
  group('PosState', () {
    test('initial state has correct defaults', () {
      const state = PosState();
      expect(state.selectedCategoryId, isNull);
      expect(state.searchQuery, '');
      expect(state.isGridCollapsed, false);
      expect(state.industryMode, IndustryMode.retail);
      expect(state.isProcessing, false);
      expect(state.error, isNull);
      expect(state.isBooking, false);
    });

    test('copyWith creates correct copy', () {
      const original = PosState();
      final modified = original.copyWith(searchQuery: 'test');

      expect(original.searchQuery, '');
      expect(modified.searchQuery, 'test');
    });

    test('clearCategoryFilter resets category', () {
      const state = PosState(selectedCategoryId: 5);
      final cleared = state.clearCategoryFilter();

      expect(cleared.selectedCategoryId, isNull);
    });
  });

  group('PosState Industry Mode', () {
    test('defaults to retail mode', () {
      const state = PosState();
      expect(state.industryMode, IndustryMode.retail);
    });

    test('can set restaurant mode', () {
      const state = PosState(industryMode: IndustryMode.restaurant);
      expect(state.industryMode, IndustryMode.restaurant);
    });

    test('can set cafe mode', () {
      const state = PosState(industryMode: IndustryMode.cafe);
      expect(state.industryMode, IndustryMode.cafe);
    });
  });

  group('PosState Delivery', () {
    test('delivery status defaults to null', () {
      const state = PosState();
      expect(state.deliveryStatus, isNull);
    });

    test('can set delivery information', () {
      const state = PosState(
        deliveryStatus: 'pending',
        deliveryCompanyId: 1,
      );

      expect(state.deliveryStatus, 'pending');
      expect(state.deliveryCompanyId, 1);
    });
  });

  group('PosState Booking Mode', () {
    test('booking mode defaults to false', () {
      const state = PosState();
      expect(state.isBooking, false);
    });

    test('can enable booking mode', () {
      const state = PosState(isBooking: true);
      expect(state.isBooking, true);
    });
  });

  group('PosState Grid Collapse', () {
    test('grid collapse defaults to false', () {
      const state = PosState();
      expect(state.isGridCollapsed, false);
    });

    test('can toggle grid collapse', () {
      const state = PosState(isGridCollapsed: true);
      expect(state.isGridCollapsed, true);
    });
  });

  group('PosState Error Handling', () {
    test('error defaults to null', () {
      const state = PosState();
      expect(state.error, isNull);
    });

    test('can set error message', () {
      const state = PosState(error: 'Test error');
      expect(state.error, 'Test error');
    });
  });

  group('PosState Table Context', () {
    test('table context defaults to null', () {
      const state = PosState();
      expect(state.tableId, isNull);
      expect(state.orderId, isNull);
      expect(state.tableName, isNull);
    });

    test('can set table context', () {
      const state = PosState(
        tableId: 1,
        orderId: 42,
        tableName: 'Table 1',
      );

      expect(state.tableId, 1);
      expect(state.orderId, 42);
      expect(state.tableName, 'Table 1');
    });
  });

  group('CartItemEntity', () {
    test('calculates line total correctly', () {
      final item = _createCartItem(productId: 1, unitPrice: 25.0, quantity: 4);

      expect(item.total, 100.0);
    });

    test('uses custom price when set', () {
      final item = _createCartItem(
        productId: 1,
        unitPrice: 25.0,
        quantity: 4,
        customPrice: 30.0,
      );

      expect(item.total, 120.0);
    });

    test('can store item note', () {
      final item = _createCartItem(
        productId: 1,
        unitPrice: 10.0,
        quantity: 1,
        note: 'No onions',
      );

      expect(item.note, 'No onions');
    });

    test('effectivePrice returns custom price when set', () {
      final item = _createCartItem(
        productId: 1,
        unitPrice: 10.0,
        quantity: 1,
        customPrice: 15.0,
      );

      expect(item.effectivePrice, 15.0);
    });

    test('effectivePrice returns unit price when no custom price', () {
      final item = _createCartItem(
        productId: 1,
        unitPrice: 10.0,
        quantity: 1,
      );

      expect(item.effectivePrice, 10.0);
    });

    test('subtotal calculates correctly', () {
      final item = _createCartItem(
        productId: 1,
        unitPrice: 10.0,
        quantity: 3,
      );

      expect(item.subtotal, 30.0);
    });

    test('discountAmount applies correctly', () {
      const item = CartItemEntity(
        productId: 1,
        productName: 'Test',
        productCode: 'TEST',
        unitPrice: 100.0,
        quantity: 1,
        discountPercent: 10,
      );

      expect(item.discountAmount, 10.0);
      expect(item.totalBeforeTax, 90.0);
    });

    test('copyWith creates modified copy', () {
      final original = _createCartItem(productId: 1, unitPrice: 10.0, quantity: 1);
      final modified = original.copyWith(quantity: 5);

      expect(original.quantity, 1);
      expect(modified.quantity, 5);
    });

    test('handles zero quantity', () {
      final item = _createCartItem(productId: 1, unitPrice: 100.0, quantity: 0);
      expect(item.total, 0);
    });

    test('handles fractional quantities (weight-based)', () {
      const item = CartItemEntity(
        productId: 1,
        productName: 'Fruit',
        productCode: 'FRUIT',
        unitPrice: 10.0,
        quantity: 1.5,
        isSoldByWeight: true,
      );

      expect(item.total, 15.0);
    });

    test('handles multiple items with different discounts', () {
      const item1 = CartItemEntity(
        productId: 1,
        productName: 'Item 1',
        productCode: 'I1',
        unitPrice: 100.0,
        quantity: 1,
        discountPercent: 10, // 100 - 10 = 90
      );
      const item2 = CartItemEntity(
        productId: 2,
        productName: 'Item 2',
        productCode: 'I2',
        unitPrice: 50.0,
        quantity: 2,
        discountPercent: 20, // 100 - 20 = 80
      );

      expect(item1.totalBeforeTax, 90.0);
      expect(item2.totalBeforeTax, 80.0);
    });
  });
}

/// Helper to create test CartItemEntity
CartItemEntity _createCartItem({
  required int productId,
  required double unitPrice,
  required double quantity,
  String name = 'Test Product',
  double? customPrice,
  String? note,
}) {
  return CartItemEntity(
    productId: productId,
    productName: name,
    productCode: 'TEST$productId',
    quantity: quantity,
    unitPrice: unitPrice,
    customPrice: customPrice,
    note: note,
  );
}
