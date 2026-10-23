// Task 6a — طبقة الإدارة: الفوترة الإلكترونية (`einvoice_submit`).
//
// «إعادة إرسال المعلقة» كانت شاشته محمية بكود عرض خشن بس (`einvoice_view`).
//
// `einvoice_cancel` (الكود التاني في نفس الشاشة) اتغطّى بوحدة اختبار منفصلة
// (`test/unit/task_6a_einvoice_cancel_permission_test.dart`) على الدالة
// المستخرجة `canCancelEInvoice`.
//
// الزرار هنا اتستخرج كدالة top-level (`buildEinvoiceSubmitButton`) في
// `e_invoice_dashboard_screen.dart` عشان يتبنى لوحده — تركيب الشاشة كلها
// بقاعدة بيانات حقيقية علّق الاختبارات (~١٠ دقايق لكل اختبار).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/e_invoice_dashboard_screen.dart';
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

  group('einvoice_submit — زرار إعادة إرسال الفواتير المعلقة', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildEinvoiceSubmitButton(onPressed: () {}),
        [PermissionCodes.einvoiceSubmit],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.einvoiceSubmit);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildEinvoiceSubmitButton(onPressed: () => tapped = true),
        const [],
      );

      // من غير الصلاحية، الضغطة بتقع على منطقة الحارس (GestureDetector
      // معتم يلف الابن جوه AbsorbPointer) مش على الـText مباشرة — ده الشكل
      // المتوقع بالظبط لـallowManagerOverride. التحذير مش عرض لباج؛
      // warnIfMissed: false بيسكّته عشان مخرجات الاختبار تبقى نضيفة.
      await tester.tap(
        find.text('إعادة إرسال المعلقة'),
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
        buildEinvoiceSubmitButton(onPressed: () => tapped = true),
        [PermissionCodes.einvoiceSubmit],
      );

      await tester.tap(find.text('إعادة إرسال المعلقة'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
