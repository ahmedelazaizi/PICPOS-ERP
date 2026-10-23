// اختبار صفّ النسبة: «—» للمجهول، الشارةُ، التفصيلُ القابلُ للفتح، RTL/EN.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/domain/analytics/ratio_engine.dart';
import 'package:picpos_erp/presentation/analytics_picpos/fin_ratio_group_section.dart';
import 'package:picpos_erp/presentation/analytics_picpos/fin_ratio_row.dart';

import 'fin_test_support.dart';

Text _t(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key)));

void main() {
  testWidgets('قيمةٌ null ⇒ «—» لا صفر، والحالةُ «غير محدد»', (tester) async {
    final r = mkRatio(value: null, status: RatioStatus.unknown);
    await pumpFin(tester, FinancialRatioRow(ratio: r, prior: null));
    expect(_t(tester, 'ratio-current_ratio-value').data, '—');
    expect(_t(tester, 'ratio-current_ratio-prior').data, '—');
    expect(find.text('غير محدد'), findsOneWidget);
    expect(find.textContaining('0.00'), findsNothing);
  });

  testWidgets('الحالي معلوم والسابق مجهول ⇒ سابقٌ «—»', (tester) async {
    await pumpFin(
      tester,
      FinancialRatioRow(
        ratio: mkRatio(value: 1.8),
        prior: mkRatio(value: null, status: RatioStatus.unknown),
      ),
    );
    expect(_t(tester, 'ratio-current_ratio-value').data, contains('1.80×'));
    expect(_t(tester, 'ratio-current_ratio-prior').data, '—');
  });

  testWidgets('الوحداتُ: نسبة مئوية وأيام ومرّات', (tester) async {
    await pumpFin(
      tester,
      Column(children: [
        FinancialRatioRow(
          ratio: mkRatio(key: 'p', value: 12.34, unit: RatioUnit.percent),
        ),
        FinancialRatioRow(
          ratio: mkRatio(key: 'd', value: 45, unit: RatioUnit.days),
        ),
      ]),
    );
    expect(_t(tester, 'ratio-p-value').data, contains('12.3%'));
    expect(_t(tester, 'ratio-d-value').data, contains('45.0'));
    expect(_t(tester, 'ratio-d-value').data, contains('يوم'));
  });

  testWidgets('الشارةُ: نصٌّ ولونٌ لكلّ حالة', (tester) async {
    for (final (s, label, color) in [
      (RatioStatus.good, 'جيد', AppColors.success),
      (RatioStatus.warning, 'تحذير', AppColors.warning),
      (RatioStatus.bad, 'خطر', AppColors.error),
    ]) {
      await pumpFin(
        tester,
        FinancialRatioRow(ratio: mkRatio(status: s)),
      );
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.color, color, reason: label);
    }
  });

  testWidgets('النقرُ يفتح المعادلة والتفسير ويغلقهما', (tester) async {
    await pumpFin(
      tester,
      FinancialRatioRow(
        ratio: mkRatio(formula: 'a / b  [good ≥ 1.5, warn ≥ 1.0]'),
      ),
    );
    expect(find.byKey(const ValueKey('ratio-current_ratio-detail')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('ratio-current_ratio-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ratio-current_ratio-detail')),
        findsOneWidget);
    expect(find.textContaining('a / b'), findsOneWidget);
    expect(_t(tester, 'ratio-current_ratio-interpretation').data,
        'السيولة كافية');
    await tester.tap(find.byKey(const ValueKey('ratio-current_ratio-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ratio-current_ratio-detail')),
        findsNothing);
  });

  testWidgets('الإنجليزيّة: التسمية والتفسير بالإنجليزيّة وLTR',
      (tester) async {
    await pumpFin(
      tester,
      FinancialRatioRow(ratio: mkRatio(), initiallyExpanded: true),
      english: true,
    );
    final ctx = tester.element(find.byType(FinancialRatioRow));
    expect(Directionality.of(ctx), TextDirection.ltr);
    expect(find.text('Current ratio'), findsOneWidget);
    expect(_t(tester, 'ratio-current_ratio-interpretation').data,
        'Liquidity is sufficient');
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Formula'), findsOneWidget);
    expect(find.text('Interpretation'), findsOneWidget);
  });

  testWidgets('العربيّة: RTL والتسمية العربيّة', (tester) async {
    await pumpFin(tester, FinancialRatioRow(ratio: mkRatio()));
    final ctx = tester.element(find.byType(FinancialRatioRow));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(find.text('نسبة التداول'), findsOneWidget);
  });

  testWidgets('عرضٌ ضيّق (هاتف/نافذة صغيرة) بلا فيض', (tester) async {
    await pumpFin(
      tester,
      FinancialRatioRow(ratio: mkRatio(), prior: mkRatio(value: 1.2)),
      width: 360,
      dark: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('الفترة السابقة'), findsOneWidget);
  });

  testWidgets('قسمُ مجموعة: يعرض الصفوفَ وبيانات السابق بمفتاح النسبة',
      (tester) async {
    await pumpFin(
      tester,
      FinancialRatioGroupSection(
        group: RatioGroup.liquidity,
        ratios: [
          mkRatio(key: 'a', value: 2),
          mkRatio(key: 'b', value: null, status: RatioStatus.unknown),
        ],
        priorByKey: {'a': mkRatio(key: 'a', value: 1.5)},
      ),
    );
    expect(find.text('السيولة'), findsOneWidget);
    expect(_t(tester, 'ratio-a-prior').data, contains('1.50×'));
    expect(_t(tester, 'ratio-b-value').data, '—');
    expect(_t(tester, 'ratio-b-prior').data, '—');
  });
}
