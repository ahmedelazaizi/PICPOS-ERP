// Task 6b — طبقة الإدارة: الطاولات (`tables_manage`).
//
// زرار «طاولة» (إضافة طاولة) في الشريط العلوي لشاشة الطاولات كان من غير أي
// فحص صلاحية على الإنشاء نفسه — `tables_manage` مالوش أي موضع تنفيذ حقيقي
// في `lib/` قبل التاسك ده (صفر مراجع برّه الكتالوج/السيدر/السجل).
//
// مستخرج كدالة top-level (`buildTablesManageAddTableButton`) في
// `tables_top_bar.dart` عشان يتبنى هنا لوحده من غير تركيب `TablesScreen`
// كاملة (محتاجة `AppDatabase` حقيقية — نفس سبب Task 6a).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/tables/widgets/tables_top_bar.dart';
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

  group('tables_manage — زرار إضافة طاولة', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildTablesManageAddTableButton(onPressed: () {}),
        [PermissionCodes.tablesManage],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.tablesManage);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildTablesManageAddTableButton(onPressed: () => tapped = true),
        const [],
      );

      await tester.tap(find.text('طاولة'), warnIfMissed: false);
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
        buildTablesManageAddTableButton(onPressed: () => tapped = true),
        [PermissionCodes.tablesManage],
      );

      await tester.tap(find.text('طاولة'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
