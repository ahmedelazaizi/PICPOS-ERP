// دفعة ٨ — شبكة الأصناف: أعمدة السعر/التكلفة/متوسط التكلفة/الرصيد + زرار
// استثناء الصنف من قفل التصنيف.
//
// الأربع أعمدة كانت بتترسم لأي حد يفتح شاشة الأصناف (`products_price_view`
// و`products_cost_view` و`products_stock_view` أكواد بلا إنفاذ)، وزرار
// القفل (`products_lock`) كان بيكتب في قاعدة البيانات بلا أي فحص.
//
// ── ليه مش `ProductsTable` كاملة ──────────────────────────────────────────
// تركيبها بيجرّ `productsControllerProvider` و`weightedAverageCostProvider`
// و`AppDatabase` حقيقية — ده بالظبط فخ الـ١٠ دقايق اللي وقفناه في دفعة ٦أ.
// الخلايا اتلمّت في دوال top-level (`buildProductSalePriceCell` وإخواتها)
// والإنتاج بينادي نفس الدوال دي، فالاختبار بيثبت التوصيلة مش نسخة موازية.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/screens/products/widgets/products_table.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';

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

  group('products_price_view — عمود سعر البيع', () {
    testWidgets('بالصلاحية: القيمة ظاهرة', (tester) async {
      await pump(
        tester,
        buildProductSalePriceCell(salePrice: 25, width: 80),
        [PermissionCodes.productsPriceView],
      );

      final guard = guardOf(tester);
      expect(guard.permission, PermissionCodes.productsPriceView);
      // عرض بحت — لا تجاوز مدير (درس هـ: ديالوج كلمة سر عشان يخفي بيانات غلط)
      expect(guard.allowManagerOverride, isFalse);
      expect(find.textContaining('25.00'), findsOneWidget);
      expect(find.text('••••'), findsNothing);
    });

    testWidgets('بدون الصلاحية: القيمة مموّهة والعرض ثابت', (tester) async {
      await pump(
        tester,
        buildProductSalePriceCell(salePrice: 25, width: 80),
        const [],
      );

      expect(find.textContaining('25.00'), findsNothing);
      expect(find.text('••••'), findsOneWidget);
      // نفس عرض العمود — إخفاء الخلية كان هيزحلق الصف بعيد عن الهيدر.
      final box = tester.widget<SizedBox>(
        find
            .ancestor(of: find.text('••••'), matching: find.byType(SizedBox))
            .last,
      );
      expect(box.width, 80);
    });
  });

  group('products_cost_view — عمود سعر التكلفة', () {
    testWidgets('بالصلاحية: القيمة ظاهرة', (tester) async {
      await pump(
        tester,
        buildProductCostPriceCell(costPrice: 18, width: 80),
        [PermissionCodes.productsCostView],
      );

      expect(guardOf(tester).permission, PermissionCodes.productsCostView);
      expect(find.textContaining('18.00'), findsOneWidget);
    });

    testWidgets('بدون الصلاحية: القيمة مموّهة', (tester) async {
      await pump(
        tester,
        buildProductCostPriceCell(costPrice: 18, width: 80),
        const [],
      );

      expect(find.textContaining('18.00'), findsNothing);
      expect(find.text('••••'), findsOneWidget);
    });
  });

  group('products_cost_view — عمود متوسط التكلفة', () {
    testWidgets('نفس كود التكلفة — مش عمود مكشوف', (tester) async {
      await pump(
        tester,
        buildProductAvgCostCell(
          loading: false,
          value: 19.5,
          product: _product,
          width: 90,
        ),
        [PermissionCodes.productsCostView],
      );

      expect(guardOf(tester).permission, PermissionCodes.productsCostView);
      expect(find.textContaining('19.50'), findsOneWidget);
    });

    testWidgets('بدون الصلاحية: مموّه — والـtooltip اللي بيسرّب نسبة الفرق '
        'عن سعر التكلفة مش موجود', (tester) async {
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

      expect(find.textContaining('19.50'), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
      expect(find.text('••••'), findsOneWidget);
    });
  });

  group('products_stock_view — عمود الرصيد', () {
    testWidgets('بالصلاحية: الرصيد ظاهر', (tester) async {
      await pump(
        tester,
        buildProductStockCell(currentStock: 7, minStock: 3, width: 60),
        [PermissionCodes.productsStockView],
      );

      expect(guardOf(tester).permission, PermissionCodes.productsStockView);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('بدون الصلاحية: الرصيد مموّه', (tester) async {
      await pump(
        tester,
        buildProductStockCell(currentStock: 7, minStock: 3, width: 60),
        const [],
      );

      expect(find.text('7'), findsNothing);
      expect(find.text('••••'), findsOneWidget);
    });
  });

  group('products_lock — استثناء الصنف من قفل التصنيف', () {
    testWidgets('بالصلاحية: الضغطة بتنفّذ على طول', (tester) async {
      var toggled = 0;
      await pump(
        tester,
        buildProductLockButton(isLocked: false, onToggle: () => toggled++),
        [PermissionCodes.productsLock],
      );

      final guard = guardOf(tester);
      // كتابة حقيقية (`updateProduct`) → تجاوز مدير مش إخفاء.
      expect(guard.allowManagerOverride, isTrue);
      // درس f8d3fa9: من غير `onGranted` الحارس بيفكّ القفل وبس.
      expect(guard.onGranted, isNotNull);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(toggled, 1);
    });

    testWidgets('بدون الصلاحية: الضغطة ما بتنفّذش من غير موافقة مدير',
        (tester) async {
      var toggled = 0;
      await pump(
        tester,
        buildProductLockButton(isLocked: false, onToggle: () => toggled++),
        const [],
      );

      await tester.tap(find.byType(IconButton), warnIfMissed: false);
      await tester.pump();
      expect(toggled, 0);
    });
  });
}
