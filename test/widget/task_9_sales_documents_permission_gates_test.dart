// دفعة ٩ — مستندات البيع: طباعة الفاتورة، عرض المبالغ، وطباعة/إلغاء المرتجع.
//
// كل الحرّاس دي جوه ملفات `part` (شاشات كاملة بتقرا من قاعدة بيانات حقيقية)،
// فالمحروس اتلمّ في دوال top-level داخل نفس المكتبة والإنتاج بينادي نفس
// الدوال — الاختبار بيبنيها لوحدها من غير ما يركّب شاشة (درس دفعة ٦أ).
//
// الفوركين متغطّيين: `sales_invoices_screen.dart` (UralCash) و
// `sales_invoices_picpos_screen.dart` (PicPos) بيعرّفوا كل واحد نسخته من
// `buildSalesPrintButtonGuarded` — الاختبار بيمرّ على الاتنين عشان أي فورك
// يفضل مكشوف يتمسك.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';
import 'package:ural_erp/presentation/screens/sales_invoices_screen.dart'
    as uralcash;
import 'package:ural_erp/presentation/sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart'
    as picpos;
import 'package:ural_erp/presentation/screens/sales_returns_screen.dart'
    as uralcash_returns;
import 'package:ural_erp/presentation/sales_returns_picpos/screens/sales_returns_picpos_screen.dart'
    as picpos_returns;

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget guarded,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(
          home: Scaffold(body: Center(child: guarded)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  PermissionGuard guardOf(WidgetTester tester) =>
      tester.widget<PermissionGuard>(find.byType(PermissionGuard).first);

  group('sales_print — زرار طباعة فاتورة البيع (الفوركين)', () {
    final forks = <String, Widget Function({required VoidCallback onPrint})>{
      'UralCash': uralcash.buildSalesPrintButtonGuarded,
      'PicPos': picpos.buildSalesPrintButtonGuarded,
    };

    forks.forEach((name, build) {
      testWidgets('$name — بالصلاحية: الضغطة بتطبع على طول', (tester) async {
        var printed = 0;
        await pump(
          tester,
          build(onPrint: () => printed++),
          [PermissionCodes.salesPrint],
        );

        final guard = guardOf(tester);
        expect(guard.permission, PermissionCodes.salesPrint);
        expect(guard.allowManagerOverride, isTrue);
        // درس f8d3fa9 — من غير onGranted الحارس بيفكّ القفل وبس.
        expect(guard.onGranted, isNotNull);

        await tester.tap(find.byType(IconButton));
        await tester.pump();
        expect(printed, 1);
      });

      testWidgets('$name — بدون الصلاحية: مفيش طباعة من غير موافقة مدير',
          (tester) async {
        var printed = 0;
        await pump(tester, build(onPrint: () => printed++), const []);

        // بدون الصلاحية `_ManagerOverrideWrapper` بيزوّد أيقونة قفل جنب
        // الزرار، فالتحديد بالـtooltip مش بالنوع.
        await tester.tap(find.byTooltip('طباعة'), warnIfMissed: false);
        await tester.pump();
        expect(printed, 0);
      });
    });
  });

  group('sales_amounts_view — تمويه المبالغ', () {
    testWidgets('بالصلاحية: المبلغ ظاهر', (tester) async {
      await pump(
        tester,
        const PermissionMaskedText(
          permission: PermissionCodes.salesAmountsView,
          text: '1250.00',
        ),
        [PermissionCodes.salesAmountsView],
      );

      expect(find.text('1250.00'), findsOneWidget);
      expect(find.text(kMaskedValuePlaceholder), findsNothing);
    });

    testWidgets('بدون الصلاحية: المبلغ مموّه', (tester) async {
      await pump(
        tester,
        const PermissionMaskedText(
          permission: PermissionCodes.salesAmountsView,
          text: '1250.00',
        ),
        const [],
      );

      expect(find.text('1250.00'), findsNothing);
      expect(find.text(kMaskedValuePlaceholder), findsOneWidget);
    });

    testWidgets('مدير النظام بيشوف المبلغ حتى من غير الكود نفسه',
        (tester) async {
      // ده سبب استعمال PermissionGuard بدل PermissionBuilder: التاني
      // بيعمل contains() نضيف من غير تجاوز مدير النظام.
      await pump(
        tester,
        const PermissionMaskedText(
          permission: PermissionCodes.salesAmountsView,
          text: '1250.00',
        ),
        const ['system_admin'],
      );

      expect(find.text('1250.00'), findsOneWidget);
    });

    testWidgets('كارت الإجماليات محجوب بنفس الكود (الفوركين)', (tester) async {
      for (final build in [
        uralcash.buildMaskedAmountKpiCard,
        picpos.buildMaskedAmountKpiCard,
      ]) {
        await pump(
          tester,
          build(
            icon: Icons.money,
            label: 'إجمالي المبيعات',
            value: '9000.00',
            color: Colors.blue,
          ),
          const [],
        );

        expect(guardOf(tester).permission, PermissionCodes.salesAmountsView);
        expect(find.text('9000.00'), findsNothing);
        // العنوان فاضل ظاهر — المستخدم يعرف إن فيه بيانات مش إنها صفر.
        expect(find.text('إجمالي المبيعات'), findsOneWidget);
      }
    });
  });

  group('sales_return_delete / sales_return_print — سجل المرتجعات (الفوركين)',
      () {
    testWidgets('إلغاء المرتجع: بتجاوز مدير و onGranted صريح', (tester) async {
      for (final build in [
        uralcash_returns.buildSalesReturnDeleteButtonGuarded,
        picpos_returns.buildSalesReturnDeleteButtonGuarded,
      ]) {
        var cancelled = 0;
        await pump(
          tester,
          build(onCancel: () => cancelled++),
          [PermissionCodes.salesReturnDelete],
        );

        final guard = guardOf(tester);
        expect(guard.permission, PermissionCodes.salesReturnDelete);
        expect(guard.allowManagerOverride, isTrue);
        expect(guard.onGranted, isNotNull);

        await tester.tap(find.byType(IconButton));
        await tester.pump();
        expect(cancelled, 1);
      }
    });

    testWidgets('إلغاء المرتجع بدون صلاحية: ما بيتنفّذش', (tester) async {
      for (final build in [
        uralcash_returns.buildSalesReturnDeleteButtonGuarded,
        picpos_returns.buildSalesReturnDeleteButtonGuarded,
      ]) {
        var cancelled = 0;
        await pump(tester, build(onCancel: () => cancelled++), const []);

        // بدون الصلاحية `_ManagerOverrideWrapper` بيزوّد أيقونة قفل جنب
        // الزرار، فالتحديد بالـtooltip مش بالنوع.
        await tester.tap(
          find.byTooltip('إلغاء المرتجع'),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(cancelled, 0);
      }
    });

    testWidgets('طباعة المرتجع: نفس الشكل بكودها', (tester) async {
      for (final build in [
        uralcash_returns.buildSalesReturnPrintButtonGuarded,
        picpos_returns.buildSalesReturnPrintButtonGuarded,
      ]) {
        var printed = 0;
        await pump(
          tester,
          build(onPrint: () => printed++),
          [PermissionCodes.salesReturnPrint],
        );

        expect(guardOf(tester).permission, PermissionCodes.salesReturnPrint);
        await tester.tap(find.byType(IconButton));
        await tester.pump();
        expect(printed, 1);
      }
    });
  });
}
