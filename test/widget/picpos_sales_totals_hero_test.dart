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
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';
import 'package:picpos_erp/presentation/sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart'
    as picpos;

/// عرضُ قطعةِ الشريط ذاتِ [color] — صفرٌ إن لم تُرسم أصلاً.
///
/// المطابقةُ باللون لا بالموضع: `find.byType(ColoredBox)` وحدَه يلتقط صناديقَ
/// `Scaffold` الداخليّةَ فيقيس ما ليس شريطاً — وهو ما أوقعني في قراءةٍ كاذبة.
double _segmentWidth(WidgetTester tester, Color color) {
  final f = find.byWidgetPredicate(
    (w) => w is ColoredBox && w.color == color,
  );
  if (f.evaluate().isEmpty) return 0;
  return tester.getSize(f.first).width;
}

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

  group('نسبةُ التغيّر عن الفترة السابقة', () {
    test('لا فترةَ سابقة ⇒ لا نسبة (لا صفر)', () {
      expect(picpos.salesDeltaPct(1000, null), isNull,
          reason: 'شارةُ «‏0%» تدّعي ثباتاً لم يُقَس أصلاً');
    });

    test('الفترةُ السابقة صفرٌ ⇒ لا نسبة', () {
      // القسمةُ على صفرٍ في Dart تعطي `Infinity` لا استثناءً، فتُطبَع
      // «‏+Infinity%» على شاشةٍ ماليّةٍ لو مرّت. وهي ليست نموّاً بل غيابُ
      // أساسٍ للمقارنة.
      expect(picpos.salesDeltaPct(1000, 0), isNull);
      expect(picpos.salesDeltaPct(0, 0), isNull);
    });

    test('الاتّجاهان يُحسبان على الأساس السابق لا الحاليّ', () {
      // ‏١٥٠ عن ١٠٠ = +٥٠٪ (لا +٣٣٪ الذي ينتج من القسمة على الحاليّ).
      expect(picpos.salesDeltaPct(150, 100), closeTo(50, 0.001));
      expect(picpos.salesDeltaPct(50, 100), closeTo(-50, 0.001));
      expect(picpos.salesDeltaPct(100, 100), closeTo(0, 0.001));
    });
  });

  group('بطاقةُ إجماليات المبيعات الرئيسيّة', () {
    testWidgets('بالصلاحية — المعادلةُ الأربعةُ كاملةً بأرقامها',
        (tester) async {
      await pump(tester, const [
        PermissionCodes.salesView,
        PermissionCodes.salesAmountsView,
      ]);

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

      // القرار (AUTHZ-004، 2026-10): الأرقام تتطلّب sales_view **و**
      // sales_amounts_view معاً — الأخير بوّابةٌ أشدُّ كانت مستقلّةً قبل d2272da0.
      expect(
        tester
            .widget<PermissionGuard>(find.byType(PermissionGuard).first)
            .allOf,
        containsAll([PermissionCodes.salesView, PermissionCodes.salesAmountsView]),
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

    for (final perms in [
      const [PermissionCodes.salesView],
      const [PermissionCodes.salesAmountsView],
    ]) {
      testWidgets('AUTHZ-004: كودٌ واحدٌ وحدَه ($perms) لا يكشف الأرقام',
          (tester) async {
        await pump(tester, perms);
        expect(find.text(money(total)), findsNothing);
        expect(find.text(money(total - returns)), findsNothing);
      });
    }

    // شريطُ النِّسَب السفليُّ يرسم **عرضَه** من نفس الأرقام. فحجبُ النصِّ
    // وحدَه لا يكفي: مسطرةٌ على الشاشة تقرأ ٥٠٪ من طول القطعة الزرقاء كما
    // تقرؤها من الرقم. والقياسُ هنا على العرض المرسوم لا على وجود الودجت —
    // قطعةٌ بوزنٍ صفر تبقى في الشجرة ولا تشغل بكسلاً.
    testWidgets('بلا صلاحية — شريطُ النِّسَب لا يرسم مقداراً', (tester) async {
      await pump(tester, const []);

      expect(_segmentWidth(tester, AppColors.primaryLight), 0,
          reason: 'قطعةُ المحصَّل مرسومةٌ بعرضٍ يقرؤه المسطرةُ نسبةً — '
              'بعد أن حُجبت النسبةُ بالنصّ');
      expect(_segmentWidth(tester, AppColors.warning), 0,
          reason: 'وقطعةُ المرتجع كذلك');
    });

    testWidgets('بالصلاحية — الشريطُ يرسم القطعَ فعلاً (ضابطٌ للاختبار السابق)',
        (tester) async {
      await pump(tester, const [
        PermissionCodes.salesView,
        PermissionCodes.salesAmountsView,
      ]);

      // ضابط: لولاه لمرّ اختبارُ الحجب على شريطٍ لا يُرسم أصلاً.
      // ‏٥٠٪ محصَّل و٢٠٪ مرتجع من عرضٍ ٤٣٦ ⇒ ٢١٨ و٨٧٫٢ تقريباً.
      expect(_segmentWidth(tester, AppColors.primaryLight), closeTo(218, 1),
          reason: 'بالصلاحية تُرسم قطعةُ المحصَّل بنصف العرض — وإلّا كان '
              'اختبارُ الحجب يقيس عدماً');
      expect(_segmentWidth(tester, AppColors.warning), closeTo(87.2, 1),
          reason: 'وقطعةُ المرتجع بخُمسه');
    });
  });
}
