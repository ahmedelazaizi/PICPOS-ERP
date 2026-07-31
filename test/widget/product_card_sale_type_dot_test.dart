import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/presentation/pos/widgets/product_card.dart';

/// The product-tile indicators (طلب ٦).
///
/// Two schemes live in one widget, chosen by constructor flags:
///  • UralCash (defaults): scale BADGE for weighed items, corner dot = stock.
///  • PicPos: no badge; corner dot = SALE TYPE, and out-of-stock dims the card.
///
/// The first group is the no-regression guard — UralCash's grid must render
/// exactly as it did, because that same grid backs the table-service screen
/// where the scale badge tells staff to weigh before sending to the kitchen.
void main() {
  ProductEntity product({
    bool isSoldByWeight = false,
    double currentStock = 10,
  }) =>
      ProductEntity(
        id: 1,
        code: 'P01',
        name: 'صنف',
        salePrice: 10,
        costPrice: 5,
        currentStock: currentStock,
        minStock: 0,
        isSoldByWeight: isSoldByWeight,
      );

  Future<void> pump(
    WidgetTester tester,
    ProductEntity p, {
    bool saleTypeDot = false,
    bool dimWhenOutOfStock = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 160,
                child: ProductCard(
                  product: p,
                  onTap: () {},
                  showImages: false,
                  saleTypeDot: saleTypeDot,
                  dimWhenOutOfStock: dimWhenOutOfStock,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder scalesIcon() => find.byWidgetPredicate(
      (w) => w is Icon && w.icon == PhosphorIconsBold.scales);

  group('UralCash scheme (defaults) — must not change', () {
    testWidgets('a weighed item keeps its scale badge', (tester) async {
      await pump(tester, product(isSoldByWeight: true));
      expect(scalesIcon(), findsOneWidget);
    });

    testWidgets('a counted item has no scale badge', (tester) async {
      await pump(tester, product());
      expect(scalesIcon(), findsNothing);
    });

    testWidgets('out of stock shows the غير متوفر badge', (tester) async {
      await pump(tester, product(currentStock: 0));
      expect(find.text('غير متوفر'), findsOneWidget);
    });
  });

  group('PicPos scheme', () {
    testWidgets('the standalone scale badge is hidden', (tester) async {
      await pump(tester, product(isSoldByWeight: true), saleTypeDot: true);

      // Exactly one scales glyph — the small one INSIDE the dot, not the
      // 22px corner badge. Size is what distinguishes them.
      final icons = tester.widgetList<Icon>(scalesIcon()).toList();
      expect(icons.length, 1);
      expect(icons.single.size, 8,
          reason: 'the badge glyph was 14px; the in-dot glyph is 8px');
      expect(icons.single.color, Colors.white);
    });

    testWidgets('a counted item gets no glyph at all', (tester) async {
      await pump(tester, product(), saleTypeDot: true);
      expect(scalesIcon(), findsNothing,
          reason: '"no glyph" is itself the signal for a counted item');
    });

    testWidgets('the weighed glyph is present regardless of stock',
        (tester) async {
      // Sale type and stock are now independent channels — an out-of-stock
      // weighed item must still read as weighed.
      await pump(tester, product(isSoldByWeight: true, currentStock: 0),
          saleTypeDot: true, dimWhenOutOfStock: true);
      expect(scalesIcon(), findsOneWidget);
    });

    testWidgets('out of stock dims the content but keeps the badge crisp',
        (tester) async {
      await pump(tester, product(currentStock: 0),
          saleTypeDot: true, dimWhenOutOfStock: true);

      // The Opacity wraps the CONTENT; the 'غير متوفر' badge is its sibling, so
      // it stays fully saturated. If the badge ever moves inside the Opacity
      // the out-of-stock signal fades with everything else.
      final dimmed = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(dimmed.any((o) => o.opacity < 1.0), isTrue);
      expect(find.text('غير متوفر'), findsOneWidget);

      final badge = find.text('غير متوفر');
      expect(
        find.ancestor(of: badge, matching: find.byType(Opacity)),
        findsNothing,
        reason: 'the badge must not be inside the dimming Opacity',
      );
    });

    testWidgets('an in-stock card is not dimmed', (tester) async {
      await pump(tester, product(currentStock: 5),
          saleTypeDot: true, dimWhenOutOfStock: true);

      final dimmed = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(dimmed.every((o) => o.opacity == 1.0), isTrue);
      expect(find.text('غير متوفر'), findsNothing);
    });
  });
}
