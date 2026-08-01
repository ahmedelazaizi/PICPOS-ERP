// Task 6a — طبقة الإدارة: الأصول الثابتة.
//
// `assets_manage` (إنشاء أصل/فئة) و`assets_depreciation` (تنفيذ الإهلاك
// الشهري) كانت شاشتهم محمية بكود عرض خشن بس (`assets_view`) — أي حد يشوف
// الشاشة يقدر يعمل الفعلين من غير أي فحص.
//
// ── ليه مش شاشة كاملة ────────────────────────────────────────────────────
// أول محاولة ركّبت `FixedAssetsScreen` كاملة فوق `AppDatabase.forTesting()`
// حقيقية — كل اختبار كان بياخد ~١٠ دقايق (دورة `runBeforeOpen` الثقيلة)
// من غير أي فايدة إضافية، لإن الحارس نفسه declarative بحت. الزرارين
// اتستخرجوا كدوال top-level (`buildAssetsManageFab`/
// `buildAssetsDepreciationButton`) في `fixed_assets_screen.dart` عشان
// تتبنى هنا لوحدها من غير الشاشة ولا القاعدة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/fixed_assets_screen.dart';
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

  // كلمة مرور المدير بـ`autofocus: true` بتسيب مؤشر وامض شغّال طول ما
  // الديالوج مفتوح — تقفيله وإلغاء التركيز يمنع "Timer is still pending"
  // عند تنظيف الاختبار.
  Future<void> closeAnyOpenDialog(WidgetTester tester) async {
    final cancelButton = find.text('إلغاء');
    if (cancelButton.evaluate().isNotEmpty) {
      await tester.tap(cancelButton.first);
      await tester.pump();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  group('assets_manage — الفتحة العائمة (أصل جديد)', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildAssetsManageFab(onPressed: () => tapped = true, label: 'أصل جديد'),
        [PermissionCodes.assetsManage],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.assetsManage);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);

      expect(tapped, isFalse);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildAssetsManageFab(onPressed: () => tapped = true, label: 'أصل جديد'),
        const [],
      );

      // من غير الصلاحية، الضغطة بتقع على منطقة الحارس (GestureDetector
      // معتم يلف الابن جوه AbsorbPointer) مش على الـText مباشرة — ده الشكل
      // المتوقع بالظبط لـallowManagerOverride (الحارس نفسه بيعترض الضغطة).
      // التحذير هنا مش عرض لباج؛ warnIfMissed: false بيسكّته عشان مخرجات
      // الاختبار تبقى نضيفة.
      await tester.tap(find.text('أصل جديد'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
      expect(tapped, isFalse);

      await closeAnyOpenDialog(tester);
    });

    testWidgets('مع الصلاحية: الضغط بينفّذ الفعل مباشرة من غير طلب تصريح',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildAssetsManageFab(onPressed: () => tapped = true, label: 'أصل جديد'),
        [PermissionCodes.assetsManage],
      );

      await tester.tap(find.text('أصل جديد'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });

  group('assets_depreciation — زرار تنفيذ الإهلاك الشهري', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildAssetsDepreciationButton(onPressed: () {}),
        [PermissionCodes.assetsDepreciation],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.assetsDepreciation);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildAssetsDepreciationButton(onPressed: () => tapped = true),
        const [],
      );

      // نفس ملاحظة تحذير hit-test في مجموعة assets_manage فوق.
      await tester.tap(
        find.text('تنفيذ الإهلاك الشهري'),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
      expect(tapped, isFalse);

      await closeAnyOpenDialog(tester);
    });

    testWidgets('مع الصلاحية: الضغط بينفّذ الفعل مباشرة من غير طلب تصريح',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildAssetsDepreciationButton(onPressed: () => tapped = true),
        [PermissionCodes.assetsDepreciation],
      );

      await tester.tap(find.text('تنفيذ الإهلاك الشهري'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
