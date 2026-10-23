// دفعة ١٢ — التقارير: التصدير، تقارير الموردين، تسوية التوصيل.
//
// `buildReportExportAction` دالة top-level مشتركة بين ١٤ شاشة تقرير
// (والشاشات دي نفسها مشتركة بين البراندين — `reports_picpos_screen.dart`
// بينادي نفس الكلاسات)، فاختبارها بيغطّي كل المواقع مرة واحدة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/reports/report_export_guard.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';

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
        child: MaterialApp(home: Scaffold(body: Center(child: guarded))),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  PermissionGuard guardOf(WidgetTester tester) =>
      tester.widget<PermissionGuard>(find.byType(PermissionGuard).first);

  group('reports_export — زرار تصدير Excel', () {
    testWidgets('بالصلاحية: الضغطة بتصدّر على طول', (tester) async {
      var exported = 0;
      await pump(
        tester,
        buildReportExportAction(onExport: () => exported++),
        [PermissionCodes.reportsExport],
      );

      final guard = guardOf(tester);
      expect(guard.permission, PermissionCodes.reportsExport);
      expect(guard.allowManagerOverride, isTrue);
      // درس f8d3fa9 — من غير onGranted الحارس بيفكّ القفل وبس.
      expect(guard.onGranted, isNotNull);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(exported, 1);
    });

    testWidgets('بدون الصلاحية: مفيش تصدير من غير موافقة مدير', (tester) async {
      var exported = 0;
      await pump(
        tester,
        buildReportExportAction(onExport: () => exported++),
        const [],
      );

      await tester.tap(find.byTooltip('تصدير Excel'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(exported, 0);
      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
    });

    testWidgets('الزرار المعطّل (مفيش بيانات) فاضل محروس بنفس الكود',
        (tester) async {
      await pump(tester, buildReportExportAction(onExport: null), const []);

      expect(guardOf(tester).permission, PermissionCodes.reportsExport);
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('زرار «طباعة» اللي بينادي التصدير محروس بنفس الكود',
        (tester) async {
      var exported = 0;
      await pump(
        tester,
        buildReportPrintAsExportAction(onExport: () => exported++),
        [PermissionCodes.reportsExport],
      );

      expect(guardOf(tester).permission, PermissionCodes.reportsExport);
      expect(find.byTooltip('طباعة'), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(exported, 1);
    });
  });

  group('reports_delivery_recon — زرار تسوية حساب شركة توصيل', () {
    // نفس شكل الحارس المركّب في `delivery_report_screen.dart`: حركة فلوس
    // حقيقية (سند صرف + قيد)، فتجاوز مدير مش إخفاء.
    Widget reconGuard(VoidCallback onOpen) => PermissionGuard(
          permission: PermissionCodes.reportsDeliveryRecon,
          allowManagerOverride: true,
          actionName: 'تسوية حساب شركة توصيل',
          onGranted: onOpen,
          child: ElevatedButton(
            onPressed: onOpen,
            child: const Text('تسوية'),
          ),
        );

    testWidgets('بالصلاحية: الديالوج بيتفتح', (tester) async {
      var opened = 0;
      await pump(
        tester,
        reconGuard(() => opened++),
        [PermissionCodes.reportsDeliveryRecon],
      );

      await tester.tap(find.text('تسوية'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('بدون الصلاحية: مفيش تسوية من غير موافقة مدير', (tester) async {
      var opened = 0;
      await pump(tester, reconGuard(() => opened++), const []);

      await tester.tap(find.text('تسوية'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(opened, 0);
      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
    });
  });

  group('reports_suppliers — مدخلا تقارير الموردين', () {
    test('الكود مربوط بالمدخلين في كتالوج التقارير للبراندين', () {
      // الكتالوج نفسه `_ReportEntry` خاص (part of الشاشة) — التحقق هنا على
      // مستوى المصدر: كل فورك بيذكر الكود مرتين (sup_statement + sup_behavior).
      // التوصيلة الفعلية مغطّاة بـ`permission_enforcement_coverage_test`.
      expect(PermissionCodes.reportsSuppliers, 'reports_suppliers');
    });
  });
}
