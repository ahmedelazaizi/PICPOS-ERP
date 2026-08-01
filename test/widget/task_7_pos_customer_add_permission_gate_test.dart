// Task 7 — نقطة البيع: إضافة عميل سريع.
//
// `pos_customer_add` كان زرار «إضافة عميل سريع» في منتقي العملاء شغّال لأي
// مستخدم من غير أي فحص صلاحية — الشرط الوحيد كان إعداد عرض
// (`showAddCustomerInPOSProvider`) بيخفي/يظهر الزرار بس، مش بوابة أمان.
//
// ── ليه مش الشاشة كاملة ───────────────────────────────────────────────────
// `CustomerSelectorV2` بتعتمد على `allCustomersProvider` و`cartControllerProvider`
// و`OverlayEntry` — تركيبها كاملة يحتاج قاعدة بيانات وسياق POS كامل. الزرار
// اتستخرج كدالة top-level (`buildPosCustomerAddIconButton`) في
// `customer_selector_v2.dart` عشان يتبنى لوحده.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/pos/widgets/customer_selector_v2.dart';
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

  Future<void> closeAnyOpenDialog(WidgetTester tester) async {
    final cancelButton = find.text('إلغاء');
    if (cancelButton.evaluate().isNotEmpty) {
      await tester.tap(cancelButton.first);
      await tester.pump();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  group('pos_customer_add — زرار إضافة عميل سريع', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildPosCustomerAddIconButton(onPressed: () => tapped = true),
        [PermissionCodes.posCustomerAdd],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.posCustomerAdd);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
      expect(tapped, isFalse);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildPosCustomerAddIconButton(onPressed: () => tapped = true),
        const [],
      );

      await tester.tap(find.byTooltip('إضافة عميل سريع'), warnIfMissed: false);
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
        buildPosCustomerAddIconButton(onPressed: () => tapped = true),
        [PermissionCodes.posCustomerAdd],
      );

      await tester.tap(find.byTooltip('إضافة عميل سريع'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
