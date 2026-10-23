// اختبار لوحة المخاطر: العدّاد لكلّ مجموعة، ترتيب الخطر قبل التحذير، RTL/EN.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/analytics/ratio_engine.dart';
import 'package:picpos_erp/presentation/analytics_picpos/fin_risk_panel.dart';

import 'fin_test_support.dart';

List<Ratio> _mixed() => [
      mkRatio(key: 'w1', status: RatioStatus.warning, group: RatioGroup.liquidity),
      mkRatio(key: 'g1', status: RatioStatus.good, group: RatioGroup.liquidity),
      mkRatio(key: 'b1', status: RatioStatus.bad, group: RatioGroup.profitability),
      mkRatio(key: 'w2', status: RatioStatus.warning, group: RatioGroup.profitability),
      mkRatio(key: 'b2', status: RatioStatus.bad, group: RatioGroup.leverage),
      mkRatio(
          key: 'u1',
          status: RatioStatus.unknown,
          value: null,
          group: RatioGroup.growth),
    ];

void main() {
  test('الملخّص: الخطرُ ثمّ التحذير بترتيب المحرّك، والمجهولُ يُعدّ فقط', () {
    final s = buildFinRiskSummary(_mixed());
    expect([for (final r in s.worst) r.key], ['b1', 'b2', 'w1', 'w2']);
    expect(s.badCount, 2);
    expect(s.warningCount, 2);
    expect(s.unknownCount, 1);
    expect(s.totalCount, 6);
    final liq = s.perGroup.firstWhere((g) => g.group == RatioGroup.liquidity);
    expect((liq.bad, liq.warning), (0, 1));
    final prof =
        s.perGroup.firstWhere((g) => g.group == RatioGroup.profitability);
    expect((prof.bad, prof.warning), (1, 1));
  });

  testWidgets('القائمةُ المرتّبة: الخطر أوّلاً ثمّ التحذير', (tester) async {
    await pumpFin(tester, FinancialRiskPanel(ratios: _mixed()));
    // ترتيبُ الظهور الرأسيّ = ترتيب الرتبة.
    final order = ['b1', 'b2', 'w1', 'w2'];
    final ys = [
      for (var i = 0; i < order.length; i++)
        tester
            .getTopLeft(find.byKey(ValueKey('risk-item-${i + 1}-${order[i]}')))
            .dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(ys.toSet().length, 4);
    // لا عنصرَ للسليم ولا للمجهول.
    expect(find.byKey(const ValueKey('risk-item-5-g1')), findsNothing);
    expect(find.byKey(const ValueKey('risk-item-5-u1')), findsNothing);
  });

  testWidgets('عدّادات المجموعات والتفسيرُ الظاهر والمجهولُ المعدود',
      (tester) async {
    await pumpFin(tester, FinancialRiskPanel(ratios: _mixed()));
    Text c(String k) => tester.widget<Text>(find.byKey(ValueKey(k)));
    expect(c('risk-group-liquidity-bad').data, '0 خطر');
    expect(c('risk-group-liquidity-warning').data, '1 تحذير');
    expect(c('risk-group-profitability-bad').data, '1 خطر');
    expect(c('risk-group-profitability-warning').data, '1 تحذير');
    expect(c('risk-group-leverage-bad').data, '1 خطر');
    expect(find.text('السيولة كافية'), findsWidgets);
    expect(c('risk-unknown').data, '1 نسب غير محتسبة');
  });

  testWidgets('لا خطرَ ولا تحذير ⇒ رسالةٌ إيجابيّة', (tester) async {
    await pumpFin(
      tester,
      FinancialRiskPanel(ratios: [mkRatio(status: RatioStatus.good)]),
    );
    expect(find.byKey(const ValueKey('risk-none')), findsOneWidget);
    expect(find.text('أسوأ النسب'), findsNothing);
  });

  testWidgets('كلُّها مجهولة ⇒ «لا بيانات كافية» لا «سليم»', (tester) async {
    await pumpFin(
      tester,
      FinancialRiskPanel(ratios: [
        mkRatio(status: RatioStatus.unknown, value: null),
      ]),
    );
    expect(find.byKey(const ValueKey('risk-no-data')), findsOneWidget);
    expect(find.byKey(const ValueKey('risk-none')), findsNothing);
  });

  testWidgets('قائمة فارغة ⇒ لا بيانات كافية بلا استثناء', (tester) async {
    await pumpFin(tester, const FinancialRiskPanel(ratios: []));
    expect(find.byKey(const ValueKey('risk-no-data')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL عربيّ', (tester) async {
    await pumpFin(tester, FinancialRiskPanel(ratios: _mixed()));
    final ctx = tester.element(find.byType(FinancialRiskPanel));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(find.text('ملخص المخاطر'), findsOneWidget);
    expect(find.textContaining('نسبة التداول · '), findsNWidgets(4));
    expect(find.textContaining('1.80×'), findsNWidgets(4));
  });

  testWidgets('الإنجليزيّة: LTR وعناوين وتسميات إنجليزيّة', (tester) async {
    await pumpFin(tester, FinancialRiskPanel(ratios: _mixed()),
        english: true, dark: true);
    final ctx = tester.element(find.byType(FinancialRiskPanel));
    expect(Directionality.of(ctx), TextDirection.ltr);
    expect(find.text('Risk summary'), findsOneWidget);
    expect(find.text('Worst ratios'), findsOneWidget);
    expect(find.textContaining('Current ratio · '), findsNWidgets(4));
    expect(find.text('Liquidity is sufficient'), findsNWidgets(4));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('risk-group-leverage-bad')))
          .data,
      '1 Risk',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('risk-unknown'))).data,
      '1 ratios not computed',
    );
  });
}
