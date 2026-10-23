// Task 6b — طبقة الإدارة: الولاء (`loyalty_manage`).
//
// زرار «إضافة برنامج» في تبويب برامج الولاء كان محمي بكود عرض خشن بس
// (`loyalty_view`) — مفيش فحص على الإنشاء نفسه.
//
// مستخرج كدالة top-level (`buildLoyaltyManageAddButton`) في
// `loyalty_programs_tab.dart` عشان يتبنى هنا لوحده، من غير تركيب
// `LoyaltyScreen` كاملة (محتاجة `AppDatabase` حقيقية — نفس سبب التعليق في
// Task 6a).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/loyalty_screen.dart';
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

  group('loyalty_manage — زرار إضافة برنامج ولاء', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildLoyaltyManageAddButton(onPressed: () {}),
        [PermissionCodes.loyaltyManage],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.loyaltyManage);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildLoyaltyManageAddButton(onPressed: () => tapped = true),
        const [],
      );

      await tester.tap(find.text('إضافة برنامج'), warnIfMissed: false);
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
        buildLoyaltyManageAddButton(onPressed: () => tapped = true),
        [PermissionCodes.loyaltyManage],
      );

      await tester.tap(find.text('إضافة برنامج'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
