// Task 6a — طبقة الإدارة: التصنيع (`manufacturing_manage`).
//
// «قائمة مواد جديدة» (BOM) كانت شاشته محمية بكود عرض خشن بس
// (`manufacturing_view`).
//
// الزرار اتستخرج كدالة top-level (`buildManufacturingManageBomButton`) في
// `bom_tab.dart` عشان يتبنى لوحده — تركيب `ManufacturingScreen` كاملة
// بقاعدة بيانات حقيقية علّق الاختبارات (~١٠ دقايق لكل اختبار من غير أي
// فايدة، لإن الحارس نفسه declarative بحت).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/manufacturing_screen.dart';
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

  group('manufacturing_manage — زرار قائمة مواد جديدة (BOM)', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildManufacturingManageBomButton(onPressed: () {}),
        [PermissionCodes.manufacturingManage],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.manufacturingManage);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildManufacturingManageBomButton(onPressed: () => tapped = true),
        const [],
      );

      // من غير الصلاحية، الضغطة بتقع على منطقة الحارس (GestureDetector
      // معتم يلف الابن جوه AbsorbPointer) مش على الـText مباشرة — ده الشكل
      // المتوقع بالظبط لـallowManagerOverride. التحذير مش عرض لباج؛
      // warnIfMissed: false بيسكّته عشان مخرجات الاختبار تبقى نضيفة.
      await tester.tap(find.text('قائمة مواد جديدة'), warnIfMissed: false);
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
        buildManufacturingManageBomButton(onPressed: () => tapped = true),
        [PermissionCodes.manufacturingManage],
      );

      await tester.tap(find.text('قائمة مواد جديدة'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
