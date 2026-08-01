// Task 6a — طبقة الإدارة: التوزيع.
//
// `distribution_manage` (إضافة/تعديل/حذف مسار توزيع) كانت شاشته محمية بكود
// عرض خشن بس (`distribution_view`).
//
// زرار «إضافة مسار» اتستخرج كدالة top-level (`buildDistributionManageAddButton`)
// في `distribution_routes_tab.dart` عشان يتبنى هنا لوحده، من غير تركيب
// `DistributionScreen` كاملة (اللي محتاجة `AppDatabase` حقيقية وعلّقت أول
// محاولة اختبار — ~١٠ دقايق لكل اختبار من غير أي فايدة، لإن الحارس نفسه
// declarative بحت).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/distribution_screen.dart';
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

  group('distribution_manage — زرار إضافة مسار توزيع', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildDistributionManageAddButton(onPressed: () {}),
        [PermissionCodes.distributionManage],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.distributionManage);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildDistributionManageAddButton(onPressed: () => tapped = true),
        const [],
      );

      await tester.tap(find.text('إضافة مسار'));
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
        buildDistributionManageAddButton(onPressed: () => tapped = true),
        [PermissionCodes.distributionManage],
      );

      await tester.tap(find.text('إضافة مسار'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
