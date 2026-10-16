// اختبار بطاقة المؤشّر: غير متاح لا صفر، الأخضر/الأحمر، RTL والإنجليزيّة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/domain/analytics/ratio_engine.dart';
import 'package:ural_erp/domain/analytics/kpi_comparison.dart';
import 'package:ural_erp/presentation/analytics_picpos/fin_kpi_card.dart';

import 'fin_test_support.dart';

KpiComparison _kpi({
  double actual = 120,
  double? prior = 100,
  double? budget,
  double? priorBudget,
  GoodDirection dir = GoodDirection.higherBetter,
}) =>
    KpiComparison(
      key: 'revenue',
      actual: actual,
      direction: dir,
      prior: prior,
      budget: budget,
      priorBudget: priorBudget,
    );

Widget _card(KpiComparison c, {bool budgetAvailable = true}) =>
    FinancialKpiCard(
      label: 'الإيرادات',
      icon: Icons.point_of_sale,
      comparison: c,
      budgetAvailable: budgetAvailable,
    );

void main() {
  testWidgets('الموازنة غير متاحة (العرض مقيَّد) ⇒ «غير متاح» لا صفر',
      (tester) async {
    // الهدفُ موجودٌ في المدخل لكنّ العرض مقيَّدٌ بفرع ⇒ لا يُعرض.
    await pumpFin(tester, _card(_kpi(budget: 90), budgetAvailable: false));
    final budget = find.byKey(const ValueKey('kpi-revenue-budget'));
    expect(tester.widget<Text>(budget).data, 'غير متاح');
    expect(find.textContaining('%'), findsOneWidget,
        reason: 'نسبةُ الفترة السابقة وحدَها؛ لا نسبةَ للموازنة');
    expect(find.text('0.0%'), findsNothing);
  });

  testWidgets('هدفُ الموازنة null ⇒ «غير متاح» حتى لو العرضُ متاح',
      (tester) async {
    await pumpFin(tester, _card(_kpi(budget: null)));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('kpi-revenue-budget'))).data,
      'غير متاح',
    );
  });

  testWidgets('الإنجليزيّة: «غير متاح» من كتالوج en.json (Unavailable)',
      (tester) async {
    await pumpFin(tester, _card(_kpi(budget: null), budgetAvailable: false),
        english: true);
    final t = tester
        .widget<Text>(find.byKey(const ValueKey('kpi-revenue-budget')))
        .data!;
    expect(t, 'Unavailable');
    expect(find.text('vs prior period'), findsOneWidget);
    expect(find.text('vs budget'), findsOneWidget);
  });

  testWidgets('مؤاتٌ ⇒ أخضر (الأعلى أفضل والفعليّ أعلى من الموازنة)',
      (tester) async {
    await pumpFin(tester, _card(_kpi(actual: 120, prior: 100, budget: 100)));
    expect(
      textColorByKey(tester, const ValueKey('kpi-revenue-budget')),
      AppColors.success,
    );
    expect(
      textColorByKey(tester, const ValueKey('kpi-revenue-prior')),
      AppColors.success,
    );
    expect(find.byIcon(Icons.arrow_upward), findsWidgets);
  });

  testWidgets('غير مؤاتٍ ⇒ أحمر', (tester) async {
    await pumpFin(tester, _card(_kpi(actual: 80, prior: 100, budget: 100)));
    expect(
      textColorByKey(tester, const ValueKey('kpi-revenue-budget')),
      AppColors.error,
    );
    expect(
      textColorByKey(tester, const ValueKey('kpi-revenue-prior')),
      AppColors.error,
    );
    expect(find.byIcon(Icons.arrow_downward), findsWidgets);
  });

  testWidgets('الأقلّ أفضل: ارتفاعٌ ⇒ أحمر، انخفاضٌ ⇒ أخضر', (tester) async {
    await pumpFin(
        tester,
        _card(_kpi(
            actual: 120, prior: 100, budget: 150, dir: GoodDirection.lowerBetter)));
    expect(
      textColorByKey(tester, const ValueKey('kpi-revenue-prior')),
      AppColors.error,
    );
    expect(
      textColorByKey(tester, const ValueKey('kpi-revenue-budget')),
      AppColors.success,
    );
  });

  testWidgets('وفي الداكن: نفسُ الألوان الدلاليّة', (tester) async {
    await pumpFin(tester, _card(_kpi(actual: 80, prior: 100, budget: 100)),
        dark: true);
    expect(
      textColorByKey(tester, const ValueKey('kpi-revenue-budget')),
      AppColors.error,
    );
  });

  testWidgets('الأساسُ صفرٌ ⇒ فرقٌ بالمبلغ لا نسبة، ولا يظهر صفر', (tester) async {
    await pumpFin(tester, _card(_kpi(actual: 50, prior: 0)));
    final text = tester
        .widget<Text>(find
            .descendant(
              of: find.byKey(const ValueKey('kpi-revenue-prior')),
              matching: find.byType(Text),
            )
            .first)
        .data!;
    expect(text, contains('+50'));
    expect(text, isNot(contains('%')));
  });

  testWidgets('RTL عربيّ: الاتجاهُ من اليمين، والقيمةُ تظهر', (tester) async {
    await pumpFin(tester, _card(_kpi(actual: 1234.5, budget: 1000)));
    final ctx = tester.element(find.byType(FinancialKpiCard));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(find.text('الإيرادات'), findsOneWidget);
    expect(find.text('مقارنة بالفترة السابقة'), findsOneWidget);
    expect(find.text('مقارنة بالموازنة'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('kpi-revenue-value')))
          .data,
      contains('1,234.5'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('الإنجليزيّة: LTR', (tester) async {
    await pumpFin(tester, _card(_kpi(budget: 100)), english: true);
    final ctx = tester.element(find.byType(FinancialKpiCard));
    expect(Directionality.of(ctx), TextDirection.ltr);
    expect(find.text('vs prior period'), findsOneWidget);
  });
}
