import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/screens/inventory/inventory_summary_card.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';

/// Widget tests for InventorySummaryCard and CartItemEntity presentation.
void main() {
  group('InventorySummaryCard', () {
    testWidgets('renders title and value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                InventorySummaryCard(
                  title: 'إجمالي المنتجات',
                  value: '250',
                  icon: PhosphorIconsBold.package,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('إجمالي المنتجات'), findsOneWidget);
      expect(find.text('250'), findsOneWidget);
    });

    testWidgets('applies correct color to value text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                InventorySummaryCard(
                  title: 'نفاد المخزون',
                  value: '12',
                  icon: PhosphorIconsBold.warning,
                  color: AppColors.error,
                ),
              ],
            ),
          ),
        ),
      );

      final valueText = tester.widget<Text>(find.text('12'));
      expect(valueText.style?.color, AppColors.error);
    });

    testWidgets('renders icon in colored container', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                InventorySummaryCard(
                  title: 'الأصناف',
                  value: '100',
                  icon: PhosphorIconsBold.barcode,
                  color: AppColors.success,
                ),
              ],
            ),
          ),
        ),
      );

      // Verify icon exists
      final iconFinder = find.byType(Icon);
      expect(iconFinder, findsOneWidget);
    });
  });

  group('CartItemEntity Widget Integration', () {
    testWidgets('displays item with UOM conversion info', (tester) async {
      const item = CartItemEntity(
        productId: 1,
        productName: 'حليب طازج',
        productCode: 'MLK001',
        quantity: 3,
        unitPrice: 24.0,
        selectedUnitName: 'كرتونة',
        quantityInBase: 12, // 12 pieces per carton
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text(item.productName),
                Text('${item.quantity} ${item.selectedUnitName ?? 'وحدة'}'),
                Text('الكمية بالأساس: ${item.stockQuantity.toStringAsFixed(0)}'),
                Text('الإجمالي: ${item.total.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('حليب طازج'), findsOneWidget);
      expect(find.text('3.0 كرتونة'), findsOneWidget);
      expect(find.text('الكمية بالأساس: 36'), findsOneWidget);
      expect(find.text('الإجمالي: 72.00'), findsOneWidget);
    });

    testWidgets('displays exchange/return item type badge', (tester) async {
      const normalItem = CartItemEntity(
        productId: 1,
        productName: 'منتج عادي',
        productCode: 'N01',
        quantity: 1,
        unitPrice: 50.0,
        itemType: CartItemType.normal,
      );

      const returnedItem = CartItemEntity(
        productId: 2,
        productName: 'مرتجع',
        productCode: 'R01',
        quantity: 1,
        unitPrice: 30.0,
        itemType: CartItemType.returned,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                _buildItemTypeBadge(normalItem),
                _buildItemTypeBadge(returnedItem),
              ],
            ),
          ),
        ),
      );

      expect(find.text('بيع'), findsOneWidget);
      expect(find.text('مرتجع'), findsOneWidget);
    });

    testWidgets('displays combined discount and tax calculation', (tester) async {
      const item = CartItemEntity(
        productId: 1,
        productName: 'جهاز',
        productCode: 'DEV01',
        quantity: 2,
        unitPrice: 100.0,
        discountPercent: 10,
        taxRate: 14,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('المبلغ: ${item.subtotal.toStringAsFixed(2)}'),
                Text('الخصم: ${item.discountAmount.toStringAsFixed(2)}'),
                Text('بعد الخصم: ${item.totalBeforeTax.toStringAsFixed(2)}'),
                Text('الضريبة: ${item.calculatedTaxAmount.toStringAsFixed(2)}'),
                Text('الإجمالي: ${item.total.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('المبلغ: 200.00'), findsOneWidget);
      expect(find.text('الخصم: 20.00'), findsOneWidget);
      expect(find.text('بعد الخصم: 180.00'), findsOneWidget);
      expect(find.text('الضريبة: 25.20'), findsOneWidget);
      expect(find.text('الإجمالي: 205.20'), findsOneWidget);
    });
  });
}

/// Helper to render item type badge for testing.
Widget _buildItemTypeBadge(CartItemEntity item) {
  final label = item.itemType == CartItemType.returned
      ? 'مرتجع'
      : item.itemType == CartItemType.exchanged
          ? 'استبدال'
          : 'بيع';
  final color = item.itemType == CartItemType.returned
      ? AppColors.error
      : item.itemType == CartItemType.exchanged
          ? AppColors.warning
          : AppColors.success;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label),
  );
}
