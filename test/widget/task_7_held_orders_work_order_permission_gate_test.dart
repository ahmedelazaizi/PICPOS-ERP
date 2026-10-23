// Task 7 — البيع السريع: طباعة أمر شغل لفاتورة معلقة (held order).
//
// `pos_work_order` هنا كان زرار الطباعة في `_HeldOrderTile`
// (`held_orders_dialog.dart`) شغّال من غير أي فحص، بينما الزرارين جنبه
// («استرجاع»/«حذف») محميين بـ`PermissionGuard` من زمان — نفس شكل الفجوة
// اللي اكتشفناها في `modifiers_manage` (Task 6b): سيبنج بالمقارنة.
//
// اتلفّ في دالة top-level (`buildHeldOrderPrintButton`) عشان يتعمله اختبار
// widget من غير الديالوج كله (`_HeldOrderTile` private، ومش ممكن تستورده
// مباشرة برضه).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/pos/widgets/held_orders_dialog.dart';
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

  group('pos_work_order — زرار طباعة فاتورة معلقة', () {
    testWidgets('الحارس مربوط بالكود الصح، بلا allowManagerOverride',
        (tester) async {
      await pumpButton(
        tester,
        buildHeldOrderPrintButton(onPrint: () {}),
        [PermissionCodes.posWorkOrder],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.posWorkOrder);
      expect(guard.allowManagerOverride, isFalse);
    });

    testWidgets('بدون الصلاحية: الزرار مختفي تماماً', (tester) async {
      var printed = false;
      await pumpButton(
        tester,
        buildHeldOrderPrintButton(onPrint: () => printed = true),
        const [],
      );

      expect(find.byTooltip('طباعة'), findsNothing);
      expect(printed, isFalse);
    });

    testWidgets('مع الصلاحية: الزرار ظاهر والضغط بينفّذ الطباعة',
        (tester) async {
      var printed = false;
      await pumpButton(
        tester,
        buildHeldOrderPrintButton(onPrint: () => printed = true),
        [PermissionCodes.posWorkOrder],
      );

      expect(find.byTooltip('طباعة'), findsOneWidget);
      await tester.tap(find.byTooltip('طباعة'));
      expect(printed, isTrue);
    });
  });
}
