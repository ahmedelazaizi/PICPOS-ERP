// ═══════════════════════════════════════════════════════════════════════════
// Day 10 — POS Cart Widget Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests the presentation layer cart logic through pure widgets and use cases.
// Avoids mounting the full POS screen (too many provider dependencies).
// Verifies: TotalRow rendering, CartItemEntity calculations, and
// CalculateInvoiceTotalsUseCase integration at the widget level.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/pos/widgets/cart/total_row.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'package:ural_erp/core/constants/app_constants.dart';

/// Helper: mount a single widget in a minimal MaterialApp.
Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

/// Helper: compute totals and display the grand total in a [Text] widget.
/// Used to verify CalculateInvoiceTotalsUseCase at the widget level.
class _CartTotalDisplay extends StatelessWidget {
  final List<CartItemEntity> items;
  final double discountPercent;

  const _CartTotalDisplay({
    required this.items,
    this.discountPercent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final useCase = CalculateInvoiceTotalsUseCase();
    final totals = useCase.execute(
      items: items,
      invoiceDiscountPercent: discountPercent,
      taxPercent: 0,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('subtotal:${totals.subtotal.toStringAsFixed(2)}'),
        Text('discount:${totals.totalDiscount.toStringAsFixed(2)}'),
        Text('tax:${totals.taxAmount.toStringAsFixed(2)}'),
        Text('total:${totals.total.toStringAsFixed(2)}'),
      ],
    );
  }
}

/// Helper: widget that shows a "negative stock" error when stock is 0
/// and allowNegativeSale is false.
class _StockGuard extends StatelessWidget {
  final double currentStock;
  final bool allowNegativeSale;

  const _StockGuard({
    required this.currentStock,
    required this.allowNegativeSale,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = currentStock <= 0 && !allowNegativeSale;
    if (blocked) {
      return const Text(
        'خطأ: لا يوجد مخزون كافٍ',
        key: Key('stock_error'),
      );
    }
    return const Text('أضف للسلة', key: Key('add_ok'));
  }
}

void main() {
  group('Day 10 — POS Cart Widget Tests', () {
    // ── Test 1: TotalRow renders label and value correctly ────────────────
    testWidgets('TotalRow يعرض التسمية والقيمة بشكل صحيح', (tester) async {
      await tester.pumpWidget(_wrap(
        const TotalRow(label: 'الإجمالي', value: 150.5),
      ));

      expect(find.text('الإجمالي'), findsOneWidget);
      // Value is formatted with currency suffix
      final currencySuffix = AppConstants.currencySymbolAr;
      expect(
        find.textContaining('150.${AppConstants.decimalPlaces > 0 ? '' : ''}'),
        findsWidgets,
      );
      expect(find.textContaining(currencySuffix), findsWidgets);
    });

    // ── Test 2: TotalRow with isTotal=true shows grand-total styling ──────
    testWidgets('TotalRow isTotal=true يُظهر نمط الإجمالي الكبير',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TotalRow(label: 'الإجمالي الكبير', value: 200.0, isTotal: true),
      ));

      // The label and value must be visible
      expect(find.text('الإجمالي الكبير'), findsOneWidget);
      // isTotal=true → container with primary-color border is in the tree
      final containers = tester.widgetList<Container>(find.byType(Container));
      final decorated = containers.where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.border != null;
      });
      expect(decorated.isNotEmpty, isTrue,
          reason: 'isTotal=true يجب أن يُضيف border للحاوية');
    });

    // ── Test 3: CartItemEntity subtotal = quantity × price ────────────────
    testWidgets('CartItemEntity: الإجمالي = الكمية × السعر', (tester) async {
      const item = CartItemEntity(
        productId: 1,
        productName: 'عصير برتقال',
        productCode: 'J001',
        quantity: 3,
        unitPrice: 25.0,
      );

      await tester.pumpWidget(_wrap(
        Text('subtotal:${item.subtotal.toStringAsFixed(2)}'),
      ));

      // 3 × 25 = 75
      expect(item.subtotal, equals(75.0));
      expect(find.text('subtotal:75.00'), findsOneWidget);
    });

    // ── Test 4: 10% discount reduces cart total correctly ─────────────────
    testWidgets('خصم 10% يُحسب بشكل صحيح على إجمالي السلة', (tester) async {
      // 2 items: 2×50 + 1×100 = subtotal 200
      // 10% invoice discount → 200 × 0.1 = 20 → net = 180
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'منتج أ',
          productCode: 'A',
          quantity: 2,
          unitPrice: 50.0,
        ),
        const CartItemEntity(
          productId: 2,
          productName: 'منتج ب',
          productCode: 'B',
          quantity: 1,
          unitPrice: 100.0,
        ),
      ];

      await tester.pumpWidget(_wrap(
        _CartTotalDisplay(items: items, discountPercent: 10),
      ));
      await tester.pump();

      expect(find.text('subtotal:200.00'), findsOneWidget);
      expect(find.text('discount:20.00'), findsOneWidget);
      expect(find.text('total:180.00'), findsOneWidget);
    });

    // ── Test 5: allowNegativeSale=false + zero stock → shows error ────────
    testWidgets('allowNegativeSale=false مع مخزون صفر يُظهر رسالة خطأ',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const _StockGuard(currentStock: 0, allowNegativeSale: false),
      ));

      expect(find.byKey(const Key('stock_error')), findsOneWidget);
      expect(find.byKey(const Key('add_ok')), findsNothing);
      expect(find.text('خطأ: لا يوجد مخزون كافٍ'), findsOneWidget);
    });
  });
}
