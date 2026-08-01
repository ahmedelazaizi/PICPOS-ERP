// Task 7 — نقطة البيع: طيّ/توسيع شبكة المنتجات.
//
// `pos_grid_toggle` كان زرارَي الطيّ (في `product_grid.dart`) والتوسيع
// (في `cart_view.dart`) شغّالين لأي مستخدم من غير أي فحص صلاحية — الشرط
// الوحيد كان إعداد عرض (`showProductLayoutToggleInPOSProvider`).
//
// عرض واجهة بحت (مفيش كتابة بيانات)، فالحارس `fallback: SizedBox.shrink()`
// مش `allowManagerOverride` — بدون الصلاحية الزرار يختفي بس.
//
// ── ليه مش الشاشتين كاملتين ───────────────────────────────────────────────
// `CartView`/`ProductGrid` بيعتمدوا على `posControllerProvider` وقاعدة
// بيانات كاملة. الزرارين اتستخرجوا كدوال top-level
// (`buildPosGridToggleButton` في cart_view.dart، `buildPosGridToggleActionButton`
// في product_grid.dart) عشان يتبنوا لوحدهم.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/pos/widgets/cart_view.dart';
import 'package:ural_erp/presentation/pos/widgets/product_grid.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester,
    Widget button,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(home: Scaffold(body: Center(child: button))),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('pos_grid_toggle — زرار «إظهار المنتجات» (cart_view.dart)', () {
    testWidgets('الحارس مربوط بالكود الصح مع fallback مش allowManagerOverride',
        (tester) async {
      await pumpButton(
        tester,
        buildPosGridToggleButton(onToggle: () {}),
        [PermissionCodes.posGridToggle],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.posGridToggle);
      expect(guard.allowManagerOverride, isFalse);
      expect(guard.fallback, isNotNull);
    });

    testWidgets('بدون الصلاحية: الزرار مختفي تماماً (مفيش ديالوج تصريح)',
        (tester) async {
      await pumpButton(tester, buildPosGridToggleButton(onToggle: () {}), const []);

      expect(find.text('إظهار المنتجات'), findsNothing);
      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
    });

    testWidgets('مع الصلاحية: الزرار ظاهر والضغط بينفّذ الفعل', (tester) async {
      var toggled = false;
      await pumpButton(
        tester,
        buildPosGridToggleButton(onToggle: () => toggled = true),
        [PermissionCodes.posGridToggle],
      );

      expect(find.text('إظهار المنتجات'), findsOneWidget);
      await tester.tap(find.text('إظهار المنتجات'));
      expect(toggled, isTrue);
    });
  });

  group('pos_grid_toggle — زرار الطيّ (product_grid.dart)', () {
    testWidgets('الحارس مربوط بالكود الصح مع fallback', (tester) async {
      await pumpButton(
        tester,
        buildPosGridToggleActionButton(onToggle: () {}),
        [PermissionCodes.posGridToggle],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.posGridToggle);
      expect(guard.allowManagerOverride, isFalse);
      expect(guard.fallback, isNotNull);
    });

    testWidgets('بدون الصلاحية: الزرار مختفي تماماً', (tester) async {
      await pumpButton(
        tester,
        buildPosGridToggleActionButton(onToggle: () {}),
        const [],
      );

      expect(find.byTooltip('طي القائمة / ملء الشاشة'), findsNothing);
    });

    testWidgets('مع الصلاحية: الضغط بينفّذ الفعل', (tester) async {
      var toggled = false;
      await pumpButton(
        tester,
        buildPosGridToggleActionButton(onToggle: () => toggled = true),
        [PermissionCodes.posGridToggle],
      );

      await tester.tap(find.byTooltip('طي القائمة / ملء الشاشة'));
      expect(toggled, isTrue);
    });
  });
}
