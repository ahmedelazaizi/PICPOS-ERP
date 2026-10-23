// Task 6b — طبقة الإدارة: المعدّلات (`modifiers_manage`).
//
// زرار «مجموعة جديدة» في شاشة إدارة الإضافات والمعدلات، وحتى مدخل الشاشة
// نفسها (الـ`ListTile` في شاشتَي الإعدادات) كانا من غير أي فحص صلاحية —
// السيبلينج `kdsSettings` جنبه بالظبط بيستخدم `PermissionGuard` صح، فده كان
// فجوة نسخ-ولصق واضحة (مذكورة في التريّاج).
//
// مستخرج كدالة top-level (`buildModifiersManageAddGroupButton`) في
// `modifier_management_widget.dart` عشان يتبنى هنا لوحده من غير شاشة/قاعدة
// بيانات حقيقية.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/widgets/settings/modifier_management_widget.dart';
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

  group('modifiers_manage — زرار مجموعة إضافات جديدة', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildModifiersManageAddGroupButton(onPressed: () {}),
        [PermissionCodes.modifiersManage],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.modifiersManage);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildModifiersManageAddGroupButton(onPressed: () => tapped = true),
        const [],
      );

      await tester.tap(find.text('مجموعة جديدة'), warnIfMissed: false);
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
        buildModifiersManageAddGroupButton(onPressed: () => tapped = true),
        [PermissionCodes.modifiersManage],
      );

      await tester.tap(find.text('مجموعة جديدة'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
