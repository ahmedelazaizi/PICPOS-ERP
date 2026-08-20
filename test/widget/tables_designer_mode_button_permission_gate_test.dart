// المهمّة ٦-ب — زرُّ وضع التصميم في ترويسة `TablesPicposScreen` محروسٌ
// بـ`tables_manage` (ترتيبُ المخطَّط إدارةٌ لا تشغيل — البند ٢ في
// `task-6b-brief.md`).
//
// مستخرجٌ كدالّةٍ top-level (`buildTablesDesignerModeButton`) في
// `tables_picpos_screen.dart` لنفس سبب `buildTablesManageAddTableButton` في
// `tables_top_bar.dart` (انظر `task_6b_tables_manage_permission_gate_test
// .dart`): يُبنى وحدَه بلا `TablesPicposScreen` كاملةً (محتاجةٌ
// `AppDatabase` حقيقيّة فتتعلّق عند `db.close()`).
//
// ودرسُ المراجعة السابقة: `PopupMenuItem` ملفوفٌ بحارسٍ يبقى قابلاً للاختيار
// مهما لُفَّ نصُّه — فالحراسةُ هنا على زرٍّ حقيقيٍّ يُعطَّل فعلاً، والدليلُ
// نقرةٌ فعليّةٌ لا فحصُ تهيئةٍ فقط.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/tables_picpos/screens/tables_picpos_screen.dart';
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

  group('tables_manage — زرّ وضع التصميم', () {
    testWidgets('الحارس مربوط بالكود الصح ومعه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildTablesDesignerModeButton(
          isDesignerMode: false,
          onToggle: () {},
        ),
        [PermissionCodes.tablesManage],
      );

      final guard =
          tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.tablesManage);
      expect(guard.allowManagerOverride, isTrue);
      expect(guard.onGranted, isNotNull);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح مدير، والفعل ما بيتنفّذش',
        (tester) async {
      var toggled = false;
      await pumpButton(
        tester,
        buildTablesDesignerModeButton(
          isDesignerMode: false,
          onToggle: () => toggled = true,
        ),
        const [],
      );

      await tester.tap(find.text('تصميم'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
      expect(toggled, isFalse);

      await closeAnyOpenDialog(tester);
    });

    testWidgets('مع الصلاحية: الضغط بينفّذ التبديل مباشرة من غير طلب تصريح',
        (tester) async {
      var toggled = false;
      await pumpButton(
        tester,
        buildTablesDesignerModeButton(
          isDesignerMode: false,
          onToggle: () => toggled = true,
        ),
        [PermissionCodes.tablesManage],
      );

      await tester.tap(find.text('تصميم'));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(toggled, isTrue);
    });

    testWidgets('في وضع التصميم المفعّل: النصُّ يتحوّل إلى «حفظ»',
        (tester) async {
      await pumpButton(
        tester,
        buildTablesDesignerModeButton(
          isDesignerMode: true,
          onToggle: () {},
        ),
        [PermissionCodes.tablesManage],
      );

      expect(find.text('حفظ'), findsOneWidget);
      expect(find.text('تصميم'), findsNothing);
    });
  });
}
