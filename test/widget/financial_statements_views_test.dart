// test/widget/financial_statements_views_test.dart
//
// انقسامُ «ميزان المراجعة» عن «القوائم المالية» — قرارُ مالك 2026-08-27.
//
// ═══ ما يقيسه ═══
//
// شريحةُ `tb` في حاوية الحسابات كانت تفتح شاشةَ القوائم المالية بستِّ
// تبويباتٍ داخليّة — **تبويباتٌ داخل تبويبات**، وأوّلُها ميزانُ المراجعة
// نفسُه. فالمستخدمُ ينقر «ميزان المراجعة» فيجد شريطاً ثانياً أوّلُه
// «ميزان المراجعة».
//
// فالعرضان الآن منفصلان، وهذا الملفُّ يثبّت الثلاثةَ معاً:
//   * عرضُ الميزان يعرض الميزانَ **ولا شريطَ تبويباتٍ فيه أصلاً**؛
//   * عرضُ القوائم يعرض الخمسَ **ولا يعرض الميزان**؛
//   * وعرضُ `all` باقٍ بستّته — فمستدعٍ خارجيٌّ لم يتغيّر تحته شيء.
//
// ⚠️ ولا يُكتفى بـ«لم تنهر»: شاشةٌ تُرسم فارغةً تمرّ على ذلك الشرط.
//    ويُقاس بعرضَين — فيضُ التبويبات يتغيّر بالعرض.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/accounting_picpos/financial_statements_picpos_screen.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    double width,
    FinancialStatementsView view, {
    int initialTabIndex = 0,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchScopeProvider
              .overrideWith((ref) async => const BranchScope.fullAccess()),
        ],
        child: MaterialApp(
          home: FinancialStatementsPicPosScreen(
            view: view,
            initialTabIndex: initialTabIndex,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('الميزانُ وحدَه — بعنوان التصميم وبلا شريطِ تبويبات',
          (tester) async {
        await pump(tester, width, FinancialStatementsView.trialBalance);

        expect(find.text('ميزان المراجعة'), findsWidgets);
        // عنوانُ `HEADS.tb` الفرعيُّ من التصميم حرفاً.
        expect(find.text('أرصدة افتتاحية وحركة وأرصدة ختامية'), findsOneWidget);
        // ⚠️ لبُّ القرار: لا `TabBar` هنا. تبويبٌ داخلَ تبويبٍ هو **عينُ**
        //    ما شكا منه المالك.
        expect(find.byType(TabBar), findsNothing);
        // ولا أثرَ للقوائم الخمسِ الأخرى في هذا العرض.
        expect(find.text('قائمة الدخل (P&L)'), findsNothing);
        expect(find.text('مطابقة الترحيل'), findsNothing);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('والقوائمُ الخمسُ — بشريطٍ فيه خمسةٌ لا ستّة',
          (tester) async {
        await pump(
          tester,
          width,
          FinancialStatementsView.statements,
          initialTabIndex: 1,
        );

        expect(find.byType(TabBar), findsOneWidget);
        expect(find.text('قائمة الدخل (P&L)'), findsOneWidget);
        expect(find.text('الميزانية العمومية'), findsOneWidget);
        expect(find.text('التدفقات النقدية'), findsOneWidget);
        expect(find.text('تقادم الذمم'), findsOneWidget);
        expect(find.text('مطابقة الترحيل'), findsOneWidget);
        // ⚠️ والميزانُ **ليس** فيها — وإلّا صار في موضعَين.
        expect(find.text('ميزان المراجعة'), findsNothing);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('و`all` باقٍ بستّته — مستدعٍ خارجيٌّ لم يتغيّر تحته شيء',
          (tester) async {
        await pump(tester, width, FinancialStatementsView.all);

        expect(find.byType(TabBar), findsOneWidget);
        expect(find.text('ميزان المراجعة'), findsWidgets);
        expect(find.text('قائمة الدخل (P&L)'), findsOneWidget);
        expect(find.text('مطابقة الترحيل'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });
    });
  }

  testWidgets('ورقمُ التبويب الخارجيُّ ثابتٌ: ٥ = مطابقةُ الترحيل في العرضَين',
      (tester) async {
    // ⚠️ شارةُ المزامنة تمرّر `5`. ولو اشتُقّ الرقمُ من الموضع في القائمة
    //    المعروضةِ لصار «٥» يعني تبويباً مختلفاً بكلّ عرض — وهو عطبٌ
    //    صامتٌ: الشاشةُ تُفتَح، على التبويب الخطأ.
    await pump(tester, 1920, FinancialStatementsView.all, initialTabIndex: 5);
    var bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.controller!.index, 5);
    await teardown(tester);

    await pump(
      tester,
      1920,
      FinancialStatementsView.statements,
      initialTabIndex: 5,
    );
    bar = tester.widget<TabBar>(find.byType(TabBar));
    // في العرض الخماسيّ موضعُها ٤ — والرقمُ المطلوبُ ما زال ٥.
    expect(bar.controller!.index, 4);
    await teardown(tester);
  });
}
