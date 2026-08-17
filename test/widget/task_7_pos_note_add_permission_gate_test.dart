// Task 7 — البيع السريع: إضافة ملاحظة لصنف في السلة.
//
// `pos_note_add` كان حقل الملاحظة في لوحة المعدِّلات/الملاحظات
// (`cart_item_modifier_panel.dart`) شغّال لأي مستخدم من غير أي فحص صلاحية.
//
// ── ليه مش CartItemTile كامل ──────────────────────────────────────────────
// الحقل جوه mixin مربوط بـ`State<CartItemTile>` (getters زي `tileRef`/
// `tileIndex`) — تركيب `CartItemTile` كامل يحتاج قاعدة بيانات وسلة حقيقية.
// اتستخرج كدالة top-level (`buildCartItemNoteField`) في
// `cart_item_modifier_panel.dart` عشان يتبنى لوحده بـcallback بسيط
// (`onSave`) بدل الاعتماد على السياق.
//
// الحارس هنا `allowManagerOverride` بلا `onGranted`: الحقل نص حر مالوش فعل
// واحد — الموافقة بتفتح القفل (`_unlocked`) بدل ما تشغّل حفظ فوري، فالاختبار
// بيتحقق من إن الموافقة بتوصل لحالة "الحقل بقى شغّال" مش من استدعاء onSave.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/pos/widgets/cart_item_tile.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';

void main() {
  Future<void> pumpField(
    WidgetTester tester,
    TextEditingController controller,
    VoidCallback onSave,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: buildCartItemNoteField(
                noteController: controller,
                onSave: onSave,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  // كلمة مرور المدير بـ`autofocus: true` بتسيب مؤشر وامض شغّال طول ما
  // الديالوج مفتوح — تقفيله وإلغاء التركيز يمنع "Timer is still pending"
  // عند تنظيف الاختبار (نفس ملاحظة Task 6a).
  Future<void> closeAnyOpenDialog(WidgetTester tester) async {
    final cancelButton = find.text('إلغاء');
    if (cancelButton.evaluate().isNotEmpty) {
      await tester.tap(cancelButton.first);
      await tester.pump();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  group('pos_note_add — حقل ملاحظة الصنف', () {
    testWidgets('الحارس مربوط بالكود الصح وallowManagerOverride بلا onGranted',
        (tester) async {
      final controller = TextEditingController();
      await pumpField(tester, controller, () {}, [PermissionCodes.posNoteAdd]);

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.posNoteAdd);
      expect(guard.allowManagerOverride, isTrue);
      // مفيش onGranted هنا عن قصد — الحقل نص حر بلا فعل واحد، فالموافقة
      // بتفكّ القفل مش تنفّذ onSave مباشرة (شايف تعليق permission_guard.dart
      // عن الفرق بين "فعل واحد" و"قسم بلا فعل").
      expect(guard.onGranted, isNull);
    });

    testWidgets(
        'بدون الصلاحية: الضغط بيطلب تصريح مدير، وonSave ما بيتنفّذش',
        (tester) async {
      final controller = TextEditingController();
      var saved = false;
      await pumpField(tester, controller, () => saved = true, const []);

      // من غير الصلاحية، الحقل ملفوف في AbsorbPointer فالضغطة بتقع على
      // منطقة الحارس نفسه (GestureDetector معتم) — نفس شكل allowManagerOverride
      // المستندة في Task 6a/6b؛ warnIfMissed: false يسكّت تحذير hit-test
      // المتوقّع في هذه الحالة بالذات.
      await tester.tap(
        find.byIcon(PhosphorIconsBold.checkCircle),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
      expect(saved, isFalse);

      await closeAnyOpenDialog(tester);
    });

    testWidgets('مع الصلاحية: الضغط على ✓ ينفّذ onSave مباشرة من غير طلب تصريح',
        (tester) async {
      final controller = TextEditingController(text: 'ملاحظة تجريبية');
      var saved = false;
      await pumpField(
        tester,
        controller,
        () => saved = true,
        [PermissionCodes.posNoteAdd],
      );

      await tester.tap(find.byIcon(PhosphorIconsBold.checkCircle));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(saved, isTrue);
    });
  });
}
