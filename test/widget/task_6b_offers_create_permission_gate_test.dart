// Task 6b — طبقة الإدارة: العروض (`offers_create`).
//
// زرار «إضافة عرض» في شاشة العروض كان محمي بكود عرض خشن بس (`offers_view`)
// — مفيش فحص على الإنشاء نفسه.
//
// مستخرج كدالة top-level (`buildOffersCreateButton`) في `offers_screen.dart`
// عشان يتبنى هنا لوحده من غير تركيب `OffersScreen` كاملة.
//
// `offers_edit`/`offers_delete` مش هنا — هما فحص صريح جوه `PopupMenuButton.
// onSelected` (زي `einvoice_cancel` في Task 6a)، مش ودجت واحد يتلف
// بـ`PermissionGuard`؛ اختبارهم في
// `test/unit/task_6b_offer_cards_edit_delete_permission_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/offers_screen.dart';
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

  group('offers_create — زرار إضافة عرض', () {
    testWidgets('الحارس مربوط بالكود الصح ومعاه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildOffersCreateButton(onPressed: () {}),
        [PermissionCodes.offersCreate],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.offersCreate);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var tapped = false;
      await pumpButton(
        tester,
        buildOffersCreateButton(onPressed: () => tapped = true),
        const [],
      );

      await tester.tap(find.text('إضافة عرض'), warnIfMissed: false);
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
        buildOffersCreateButton(onPressed: () => tapped = true),
        [PermissionCodes.offersCreate],
      );

      await tester.tap(find.text('إضافة عرض'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(tapped, isTrue);
    });
  });
}
