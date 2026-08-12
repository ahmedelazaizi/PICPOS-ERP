// PicPos — ملاحظة الصنف على سطر السلّة.
//
// سلّةُ PicPos جدولٌ بأعمدةٍ ثابتة، لا صفوفٌ قابلةٌ للتوسّع كسلّة UralCash،
// فلوحُ `cart_item_modifier_panel` لا يصلها (وهو `part` من
// `cart_item_tile.dart` الذي لا تستورده PicPos أصلاً). قرارُ المالك
// 2026-08-12: حوارٌ للسطر المحدَّد بدل التوسّع تحت الصف.
//
// وحقلُ الملاحظة داخل الحوار يُحرَس بنفس حراسة الأصل: `pos_note_add` مع
// `allowManagerOverride` وبلا `onGranted` — الحقلُ نصٌّ حرٌّ بلا زرٍّ واحدٍ
// واضح، فالموافقةُ **تفتح القفل** ثم يكتب الكاشير ويحفظ بنفسه.
//
// ── ليه مش الحوار كامل ────────────────────────────────────────────────────
// الحوار بيحمّل مجموعاتِ المعدِّلات من المستودع ومحتاج قاعدة بيانات. الحقل
// اتستخرج كدالة top-level عشان يتبنى لوحده — نفس نمط Task 6a/6b/7.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/pos/widgets/modifier_selection_dialog.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';

void main() {
  Future<void> pumpField(
    WidgetTester tester,
    TextEditingController controller,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: buildItemNoteField(controller: controller)),
          ),
        ),
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

  group('pos_note_add — حقل ملاحظة الصنف في حوار PicPos', () {
    testWidgets('الحارس مربوط بالكود الصح وبلا onGranted', (tester) async {
      await pumpField(tester, TextEditingController(), [
        PermissionCodes.posNoteAdd,
      ]);

      final guard = tester.widget<PermissionGuard>(
        find.byType(PermissionGuard),
      );
      expect(guard.permission, PermissionCodes.posNoteAdd);
      expect(guard.allowManagerOverride, isTrue);
      expect(
        guard.onGranted,
        isNull,
        reason: 'حقلٌ نصّيٌّ بلا فعلٍ واحد — الموافقة تفتح القفل لا تحفظ',
      );
    });

    testWidgets('مع الصلاحية: الكاشير يكتب مباشرةً', (tester) async {
      final controller = TextEditingController();
      await pumpField(tester, controller, [PermissionCodes.posNoteAdd]);

      await tester.enterText(find.byType(TextField), 'بدون بصل');
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(controller.text, 'بدون بصل');
    });

    testWidgets('بدون الصلاحية: اللمسُ يطلب تصريحَ مدير', (tester) async {
      await pumpField(tester, TextEditingController(), const []);

      await tester.tap(find.byType(PermissionGuard), warnIfMissed: false);
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);

      await closeAnyOpenDialog(tester);
    });
  });
}
