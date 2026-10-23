// Task 6b — طبقة الإدارة: المطبخ (`kitchen_manage`).
//
// أزرار «تحضير»/«جاهز»/«استرجاع» في شاشة عرض المطبخ كانت بتغيّر حالة أمر
// المطبخ من غير أي فحص صلاحية — الشاشة محمية بكود عرض خشن بس (`kitchen_view`).
//
// ── ليه مش شاشة كاملة ────────────────────────────────────────────────────
// نفس سبب Task 6a: تركيب `KitchenDisplayScreen` كاملة يحتاج `AppDatabase`
// حقيقية (دورة `runBeforeOpen` الثقيلة) من غير أي فايدة إضافية، لإن الحارس
// نفسه declarative بحت. الثلاث أزرار بتستخدم نفس الدالة المستخرجة
// (`buildKitchenManageActionButton`) في `kitchen_display_screen.dart`، فاختبار
// واحد يغطّي الثلاثة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/kitchen/screens/kitchen_display_screen.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';

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

  group('kitchen_manage — زرار «تحضير»', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildKitchenManageActionButton(
          onPressed: () {},
          icon: PhosphorIconsBold.cookingPot,
          label: 'تحضير',
          color: Colors.orange,
        ),
        [PermissionCodes.kitchenManage],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.kitchenManage);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildKitchenManageActionButton(
          onPressed: () => tapped = true,
          icon: PhosphorIconsBold.cookingPot,
          label: 'تحضير',
          color: Colors.orange,
        ),
        const [],
      );

      // من غير الصلاحية، الضغطة بتقع على منطقة الحارس مش على الـText مباشرة
      // — الشكل المتوقع لـallowManagerOverride. warnIfMissed: false بيسكّت
      // تحذير الـhit-test غير الضار ده.
      await tester.tap(find.text('تحضير'), warnIfMissed: false);
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
        buildKitchenManageActionButton(
          onPressed: () => tapped = true,
          icon: PhosphorIconsBold.cookingPot,
          label: 'تحضير',
          color: Colors.orange,
        ),
        [PermissionCodes.kitchenManage],
      );

      await tester.tap(find.text('تحضير'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });

  group('kitchen_manage — زرار مخطّط (استرجاع، outlined)', () {
    testWidgets('نفس الحارس بيتلف حوالين الزرار المخطّط برضه', (tester) async {
      await pumpButton(
        tester,
        buildKitchenManageActionButton(
          onPressed: () {},
          icon: PhosphorIconsBold.arrowCounterClockwise,
          label: 'استرجاع',
          color: Colors.orange,
          outlined: true,
        ),
        [PermissionCodes.kitchenManage],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.kitchenManage);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });
  });

  // ── فيكس المراجعة (Critical 2) ──────────────────────────────────────────
  // «تعليم صنف كجاهز» (ضغطة على صف الصنف جوه الطلب، `kitchenRepo.
  // markItemReady`) كان مستبعد أول مرة بحجة "فعل أدق من غير كود مخصص" —
  // نفس المنطق اللي اتطبّق مختلف مع `offers_toggle` (اتحطّت تحت offers_edit
  // بدل ما تتسحب). المراجعة صححت التناقض: نفس فئة الفعل اللي kitchen_manage
  // موجود عشانها، فبيتحمي بنفس الكود.
  group('kitchen_manage — صف الصنف («تعليم جاهز»)', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildKitchenManageItemReadyTile(
          onTap: () {},
          child: const Text('صنف تجريبي'),
        ),
        [PermissionCodes.kitchenManage],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.kitchenManage);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildKitchenManageItemReadyTile(
          onTap: () => tapped = true,
          child: const Text('صنف تجريبي'),
        ),
        const [],
      );

      await tester.tap(find.text('صنف تجريبي'), warnIfMissed: false);
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
        buildKitchenManageItemReadyTile(
          onTap: () => tapped = true,
          child: const Text('صنف تجريبي'),
        ),
        [PermissionCodes.kitchenManage],
      );

      await tester.tap(find.text('صنف تجريبي'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
