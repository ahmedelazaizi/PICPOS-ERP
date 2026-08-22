// جدولُ الأصناف — **فوركُ PicPos**.
//
// ═══ لماذا اختبارٌ ثانٍ بدل الاكتفاء بالمشترك ═══
//
// `task_8_products_grid_permission_gates_test` يفحص الخلايا المحروسةَ في
// `presentation/screens/products/widgets/products_table.dart` — وهي الآن
// **ملفٌّ لا تصل إليه شاشةُ PicPos إطلاقاً**. فحارسٌ أخضرُ هناك لا يقول شيئاً
// عن المسار الحيّ هنا، وهي بعينها فئةُ العطب التي وُجد
// `picpos_permission_parity_test` لأجلها: «ضابطٌ رقابيٌّ يبدو مفعَّلاً وهو
// غيرُ موجودٍ على المسار الحيّ».
//
// وذكرُ كودِ الصلاحية في الفورك يُرضي حارسَ التكافؤ (‏يقيس الذكرَ لا الإنفاذ)
// — فالإنفاذُ يُقاس هنا.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/presentation/products_picpos/widgets/products_table_picpos.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';

const _product = ProductEntity(
  id: 1,
  code: 'P-1',
  name: 'صنف تجريبي',
  salePrice: 25,
  costPrice: 18,
  currentStock: 7,
  minStock: 3,
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget guarded,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(
          home: Scaffold(body: Row(children: [guarded])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  PermissionGuard guardOf(WidgetTester tester) =>
      tester.widget<PermissionGuard>(find.byType(PermissionGuard).first);

  group('الفورك يُنفِذ نفسَ صلاحيات العرض', () {
    testWidgets('سعرُ البيع محروسٌ بـproducts_price_view', (tester) async {
      await pump(
        tester,
        buildProductSalePriceCell(salePrice: 25, width: 80),
        [PermissionCodes.productsPriceView],
      );
      expect(guardOf(tester).permission, PermissionCodes.productsPriceView);
      expect(find.textContaining('25.00'), findsOneWidget);
    });

    testWidgets('سعرُ البيع بلا صلاحيةٍ يُموَّه', (tester) async {
      await pump(
        tester,
        buildProductSalePriceCell(salePrice: 25, width: 80),
        const [],
      );
      expect(find.textContaining('25.00'), findsNothing);
      expect(find.text('••••'), findsOneWidget);
    });

    testWidgets('التكلفةُ محروسةٌ بـproducts_cost_view', (tester) async {
      await pump(
        tester,
        buildProductCostPriceCell(costPrice: 18, width: 80),
        [PermissionCodes.productsCostView],
      );
      expect(guardOf(tester).permission, PermissionCodes.productsCostView);
      expect(find.textContaining('18.00'), findsOneWidget);
    });

    testWidgets('التكلفةُ بلا صلاحيةٍ تُموَّه', (tester) async {
      await pump(
        tester,
        buildProductCostPriceCell(costPrice: 18, width: 80),
        const [],
      );
      expect(find.textContaining('18.00'), findsNothing);
      expect(find.text('••••'), findsOneWidget);
    });

    testWidgets('متوسّطُ التكلفة محروسٌ بنفس كود التكلفة', (tester) async {
      await pump(
        tester,
        buildProductAvgCostCell(
          loading: false,
          value: 19.5,
          product: _product,
          width: 90,
        ),
        const [],
      );
      expect(guardOf(tester).permission, PermissionCodes.productsCostView);
      expect(find.text('••••'), findsOneWidget);
    });

    testWidgets('الرصيدُ محروسٌ بـproducts_stock_view', (tester) async {
      await pump(
        tester,
        buildProductStockCell(currentStock: 7, minStock: 3, width: 60),
        const [],
      );
      expect(guardOf(tester).permission, PermissionCodes.productsStockView);
      expect(find.text('••••'), findsOneWidget);
    });

    // ⚠️ عرضٌ بحتٌ لا تجاوزَ مديرٍ فيه: حوارُ كلمةِ مرورٍ لإظهار بياناتٍ
    // محجوبةٍ عمداً يقلب معنى الحجب. (‏درسٌ منقولٌ من الاختبار المشترك.)
    testWidgets('لا تجاوزَ مديرٍ على خلايا العرض', (tester) async {
      await pump(
        tester,
        buildProductSalePriceCell(salePrice: 25, width: 80),
        [PermissionCodes.productsPriceView],
      );
      expect(guardOf(tester).allowManagerOverride, isFalse);
    });
  });
}
