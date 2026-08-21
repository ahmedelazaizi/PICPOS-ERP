// البطاقةُ الرئيسيّةُ لإجماليات فواتير PicPos (تصميم 2026-08-21).
//
// البطاقةُ تعرض المعادلةَ كاملةً — الإجمالي − المرتجعات = الصافي — ومعها
// **نسبةُ** المحصَّل. والنسبةُ هي الجديدُ الذي لم يكن في الشكل القديم، وهي
// مشتقّةٌ من المبالغ: من لا يحقّ له رؤيةُ المبلغ لا يحقّ له استنتاجُه من
// نسبته. فالحجبُ يُقاس على الأربعة معاً لا على المبالغ وحدَها.
//
// والنوعُ خاصٌّ بمكتبة الشاشة، فيُبلَغ عبر `buildSalesTotalsHero` — نفسُ نمطِ
// `buildMaskedAmountKpiCard` في `task_9_sales_documents_permission_gates_test`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';
import 'package:ural_erp/presentation/sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart'
    as picpos;

void main() {
  // ‏١٠٠٠ إجمالي · ٢٠٠ مرتجع · ٥٠٠ محصَّل ⇒ صافي ٨٠٠ ونسبةُ تحصيلٍ ٥٠٪.
  // أرقامٌ متمايزةٌ عمداً: لو التقط الودجت حقلاً مكانَ آخرَ لظهر الفرق.
  const total = 1000.0;
  const returns = 200.0;
  const collected = 500.0;

  String money(double v) => v.toStringAsFixed(AppConstants.decimalPlaces);

  Future<void> pump(WidgetTester tester, List<String> perms) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 436,
                height: 150,
                child: picpos.buildSalesTotalsHero(
                  total: total,
                  returns: returns,
                  collected: collected,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('بطاقةُ إجماليات المبيعات الرئيسيّة', () {
    testWidgets('بالصلاحية — المعادلةُ الأربعةُ كاملةً بأرقامها',
        (tester) async {
      await pump(tester, const [PermissionCodes.salesAmountsView]);

      expect(find.text(money(total)), findsWidgets,
          reason: 'الإجماليُّ يظهر — كبيراً وفي شريط المعادلة');
      expect(find.text(money(returns)), findsOneWidget,
          reason: 'والمرتجعاتُ حدُّ الطرح');
      expect(find.text(money(total - returns)), findsOneWidget,
          reason: 'والصافي ناتجُها — ٨٠٠ لا ١٠٠٠');
      expect(find.text('50%'), findsOneWidget,
          reason: 'ونسبةُ التحصيل ٥٠٠ من ١٠٠٠');
    });

    testWidgets('بلا صلاحية — لا مبلغَ ولا نسبةَ تُفشيه', (tester) async {
      await pump(tester, const []);

      expect(
        tester
            .widget<PermissionGuard>(find.byType(PermissionGuard).first)
            .permission,
        PermissionCodes.salesAmountsView,
      );

      expect(find.text(money(total)), findsNothing);
      expect(find.text(money(returns)), findsNothing);
      expect(find.text(money(total - returns)), findsNothing,
          reason: 'والصافي مبلغٌ كذلك — لا يُستثنى');
      expect(find.text('50%'), findsNothing,
          reason: 'والنسبةُ تُفشي المقدارَ لمن يعرف أحدَ طرفَيها، فتُحجَب معها');

      // العناوينُ تبقى — المستخدمُ يعرف أن ثمّةَ بياناتٍ لا أن القيمةَ صفر.
      expect(find.text('صافي المبيعات'), findsOneWidget);
      expect(find.text('المحصّل'), findsOneWidget);
    });
  });
}
