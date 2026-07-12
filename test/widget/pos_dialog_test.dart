import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';

/// POS Dialog Widget Tests
/// 
/// Tests cover: dialog rendering and basic widget components
/// Note: Full dialog integration tests require complex mocking of providers and database
void main() {
  group('Dialog Smoke Tests', () {
    testWidgets('AlertDialog renders with RTL text direction', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => const Directionality(
                    textDirection: TextDirection.rtl,
                    child: AlertDialog(
                      title: Text('تحرير المنتج'),
                      content: Text('اختبار المحتوى'),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('تحرير المنتج'), findsOneWidget);
      expect(find.text('اختبار المحتوى'), findsOneWidget);
    });

    testWidgets('Dialog with action buttons renders correctly', (tester) async {
      bool confirmClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: AlertDialog(
                      title: const Text('تأكيد'),
                      content: const Text('هل أنت متأكد؟'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                          },
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            confirmClicked = true;
                            Navigator.pop(ctx);
                          },
                          child: const Text('تأكيد'),
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify dialog content
      expect(find.text('إلغاء'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'تأكيد'), findsOneWidget);

      // Test confirm button
      await tester.tap(find.widgetWithText(ElevatedButton, 'تأكيد'));
      await tester.pumpAndSettle();
      expect(confirmClicked, true);
    });

    testWidgets('Dialog with TextField for input', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: AlertDialog(
                      title: const Text('إدخال'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'الكمية',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إغلاق'),
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify TextField exists
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('الكمية'), findsOneWidget);

      // Enter text
      await tester.enterText(find.byType(TextField), '10');
      expect(controller.text, '10');
    });

    testWidgets('Dialog dismisses on cancel button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: const Text('Content'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Content'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Content'), findsNothing);
    });
  });

  group('Cart State Widget Tests', () {
    testWidgets('Cart item displays correctly', (tester) async {
      const item = CartItemEntity(
        productId: 1,
        productName: 'Test Product',
        productCode: 'TEST001',
        quantity: 3,
        unitPrice: 10.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: ListTile(
                title: Text(item.productName),
                subtitle: Text('${item.quantity} × ${item.effectivePrice.toStringAsFixed(2)}'),
                trailing: Text('${item.total.toStringAsFixed(2)} JOD'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Test Product'), findsOneWidget);
      expect(find.text('3.0 × 10.00'), findsOneWidget);
      expect(find.text('30.00 JOD'), findsOneWidget);
    });

    testWidgets('Cart summary shows correct totals', (tester) async {
      const item1 = CartItemEntity(
        productId: 1,
        productName: 'Item 1',
        productCode: 'I1',
        quantity: 2,
        unitPrice: 25.0,
      );
      const item2 = CartItemEntity(
        productId: 2,
        productName: 'Item 2',
        productCode: 'I2',
        quantity: 1,
        unitPrice: 50.0,
      );

      final items = [item1, item2];
      final subtotal = items.fold(0.0, (sum, i) => sum + i.total);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('Items: ${items.length}'),
                Text('Subtotal: ${subtotal.toStringAsFixed(2)} JOD'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Items: 2'), findsOneWidget);
      expect(find.text('Subtotal: 100.00 JOD'), findsOneWidget);
    });
  });

  group('CartItemEntity Widget Integration Tests', () {
    testWidgets('Discount display updates correctly', (tester) async {
      const item = CartItemEntity(
        productId: 1,
        productName: 'Test',
        productCode: 'T1',
        quantity: 1,
        unitPrice: 100.0,
        discountPercent: 15,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('Subtotal: ${item.subtotal.toStringAsFixed(2)}'),
                Text('Discount: ${item.discountPercent.toStringAsFixed(0)}%'),
                Text('Discount Amount: -${item.discountAmount.toStringAsFixed(2)}'),
                Text('Total: ${item.totalBeforeTax.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Subtotal: 100.00'), findsOneWidget);
      expect(find.text('Discount: 15%'), findsOneWidget);
      expect(find.text('Discount Amount: -15.00'), findsOneWidget);
      expect(find.text('Total: 85.00'), findsOneWidget);
    });

    testWidgets('Tax display via item-level tax rate', (tester) async {
      const item = CartItemEntity(
        productId: 1,
        productName: 'Test',
        productCode: 'T1',
        quantity: 1,
        unitPrice: 100.0,
        taxRate: 16, // 16% as percentage
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('Tax Rate: ${item.taxRate.toStringAsFixed(0)}%'),
                Text('Tax Amount: ${item.calculatedTaxAmount.toStringAsFixed(2)}'),
                Text('Total: ${item.total.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Tax Rate: 16%'), findsOneWidget);
      expect(find.text('Tax Amount: 16.00'), findsOneWidget);
      expect(find.text('Total: 116.00'), findsOneWidget);
    });
  });
}
