// زرُّ «مصمم القاعة» في ترويسة `TablesPicposScreen` محروسٌ بـ`tables_manage`
// (ترتيبُ المخطَّط إدارةٌ لا تشغيل — البند ٢ في `task-6b-brief.md`).
//
// ⚠️ **وقسمُ ٧ بدّل ما يفعله الزرُّ لا حراستَه.** كان `buildTablesDesignerMode
// Button` يقلب هذه الشاشةَ نفسَها إلى محرّر، فصار `buildTablesOpenDesigner
// Button` يفتح شاشةً مستقلّة. والحراسةُ هي هي، **وهذا الملفُّ هو ما يُثبتها**:
// نقلُ فعلٍ إلى مكانٍ آخرَ أشهرُ طريقةٍ لإسقاط حارسِه في الطريق.
//
// مستخرجٌ كدالّةٍ top-level في `tables_picpos_screen.dart` لنفس سبب
// `buildTablesManageAddTableButton` في `tables_top_bar.dart`: يُبنى وحدَه بلا
// `TablesPicposScreen` كاملةً (محتاجةٌ `AppDatabase` حقيقيّة فتتعلّق).
//
// ودرسُ المراجعة السابقة: `PopupMenuItem` ملفوفٌ بحارسٍ يبقى قابلاً للاختيار
// مهما لُفَّ نصُّه — فالحراسةُ هنا على زرٍّ حقيقيٍّ يُعطَّل فعلاً، والدليلُ
// نقرةٌ فعليّةٌ لا فحصُ تهيئةٍ فقط.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/tables_picpos/screens/tables_picpos_screen.dart';
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

  group('tables_manage — زرّ مصمم القاعة', () {
    testWidgets('الحارس مربوط بالكود الصح ومعه onGranted صريح', (tester) async {
      await pumpButton(
        tester,
        buildTablesOpenDesignerButton(onOpen: () {}),
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
      var opened = false;
      await pumpButton(
        tester,
        buildTablesOpenDesignerButton(onOpen: () => opened = true),
        const [],
      );

      await tester.tap(find.byKey(const Key('tables_open_designer')),
          warnIfMissed: false);
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
      expect(opened, isFalse);

      await closeAnyOpenDialog(tester);
    });

    testWidgets('مع الصلاحية: الضغط بيفتح المصمّم مباشرة من غير طلب تصريح',
        (tester) async {
      var opened = false;
      await pumpButton(
        tester,
        buildTablesOpenDesignerButton(onOpen: () => opened = true),
        [PermissionCodes.tablesManage],
      );

      await tester.tap(find.byKey(const Key('tables_open_designer')));
      await tester.pump();

      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(opened, isTrue);
    });

    testWidgets('النصُّ ثابتٌ لا يتبدّل بحالةٍ — الزرُّ يفتح شاشةً لا يقلب وضعاً',
        (tester) async {
      // ⚠️ توكيدٌ على **غياب** «حفظ» من الزرّ: النصُّ المتبدّل كان يعني أنّ
      //    الشاشةَ نفسَها في وضعِ تحرير، وذاك بالضبط ما أزاله قسمُ ٧.
      await pumpButton(
        tester,
        buildTablesOpenDesignerButton(onOpen: () {}),
        [PermissionCodes.tablesManage],
      );

      expect(find.text('مصمم القاعة'), findsOneWidget);
      expect(find.text('حفظ'), findsNothing);
      expect(find.text('تصميم'), findsNothing);
    });
  });
}
