// دفعة ١١ — لوحة التحكم: كارت صافي الإيراد، بانر تنبيه المخزون، الرسوم.
//
// ── ليه الحرّاس متبنيّة هنا بدل تركيب اللوحة ──────────────────────────────
// `DashboardScreen` و`DashboardPicposScreen` بيقرأوا `dashboardKpiProvider`
// و`dashboardCashBalanceProvider` و`lowStockProductsProvider` — كلهم بيوصلوا
// لقاعدة بيانات حقيقية. الحرّاس نفسها هي اللي تحت الاختبار: نفس الأكواد ونفس
// الشكل (بديل مموّه/إخفاء، وتجاوز مدير من عدمه) اللي مركّب في الشاشتين.
//
// الاختبار ده بيقفل على **الشكل** — إن كود العرض المالي بيموّه فعلاً وإن
// كود التنبيه بيخفي. التوصيلة نفسها (إن الشاشة بتنادي الحارس) مغطّاة
// بـ`permission_enforcement_coverage_test` اللي بيمسح `lib/` كله.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';

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

  group('dashboard_sales_today — كارت صافي الإيراد', () {
    // نفس شكل الحارس المركّب في الشاشتين: بديل مموّه + تجاوز مدير.
    Widget revenueCardGuard() => const PermissionGuard(
          permission: PermissionCodes.dashboardSalesToday,
          allowManagerOverride: true,
          actionName: 'عرض صافي الإيراد',
          fallback: Text('---'),
          child: Text('84,300.00'),
        );

    testWidgets('بدون الصلاحية: الرقم مموّه', (tester) async {
      await pump(tester, revenueCardGuard(), const []);

      expect(find.text('---'), findsOneWidget);
      expect(
        find.text('84,300.00'),
        findsNothing,
        reason: 'من غير إصلاح المحرك (d01fdfdc) الرقم كان بيتعرض تحت '
            'AbsorbPointer رغم وجود fallback',
      );
    });

    testWidgets('بالصلاحية: الرقم ظاهر', (tester) async {
      await pump(
        tester,
        revenueCardGuard(),
        [PermissionCodes.dashboardSalesToday],
      );

      expect(find.text('84,300.00'), findsOneWidget);
      expect(find.text('---'), findsNothing);
    });

    testWidgets('بدون الصلاحية: الضغط بيطلب تصريح المسؤول', (tester) async {
      await pump(tester, revenueCardGuard(), const []);

      await tester.tap(find.text('---'));
      await tester.pumpAndSettle();

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
    });
  });

  group('dashboard_alerts — بانر تنبيه نقص المخزون', () {
    // إخفاء بلا تجاوز: ديالوج كلمة سر مدير عشان يظهر بانر تنبيه غلط
    // (نفس قرار `pos_low_stock_alert` في دفعة ٧ — حرفياً نفس التنبيه).
    Widget alertsGuard() => const PermissionGuard(
          permission: PermissionCodes.dashboardAlerts,
          fallback: SizedBox.shrink(),
          child: Text('تنبيه: 3 صنف وصل للحد الأدنى من المخزون'),
        );

    testWidgets('بالصلاحية: البانر ظاهر', (tester) async {
      await pump(tester, alertsGuard(), [PermissionCodes.dashboardAlerts]);
      expect(
        find.text('تنبيه: 3 صنف وصل للحد الأدنى من المخزون'),
        findsOneWidget,
      );
    });

    testWidgets('بدون الصلاحية: البانر مختفي ومفيش ديالوج مدير',
        (tester) async {
      await pump(tester, alertsGuard(), const []);

      expect(
        find.text('تنبيه: 3 صنف وصل للحد الأدنى من المخزون'),
        findsNothing,
      );
      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
    });
  });

  group('dashboard_chart — الرسوم (فورك PicPos)', () {
    Widget chartGuard() => const PermissionGuard(
          permission: PermissionCodes.dashboardChart,
          fallback: SizedBox.shrink(),
          child: Text('هامش الربح'),
        );

    testWidgets('بالصلاحية: الرسم ظاهر', (tester) async {
      await pump(tester, chartGuard(), [PermissionCodes.dashboardChart]);
      expect(find.text('هامش الربح'), findsOneWidget);
    });

    testWidgets('بدون الصلاحية: الرسم مختفي — مش مجرد ممتص للضغط',
        (tester) async {
      await pump(tester, chartGuard(), const []);
      expect(find.text('هامش الربح'), findsNothing);
    });
  });

  group('dashboard_sales_total — كود بلا سطح', () {
    test('متسجّل في nonToggleable بسبب صريح', () {
      expect(
        PermissionCodes.nonToggleable.containsKey('dashboard_sales_total'),
        isTrue,
        reason: 'مفيش كارت «إجمالي مبيعات» منفصل — نفس كارت '
            'dashboard_sales_today بفلتر فترة أوسع',
      );
      expect(
        PermissionCodes.nonToggleable['dashboard_sales_total'],
        isNotEmpty,
      );
    });
  });
}
