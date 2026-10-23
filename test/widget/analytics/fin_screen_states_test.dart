// حالات الشاشة الكاملة (تحميل / خطأ / فارغ / بيانات) بنتيجةٍ مبنيّةٍ يدويّاً
// عبر override للمزوّد — بلا قاعدة بيانات.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/branch_scope_provider.dart';
import 'package:picpos_erp/data/providers/financial_analytics_provider.dart';
import 'package:picpos_erp/data/providers/manufacturing_providers.dart'
    show branchListProvider;
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/analytics/budget_targets.dart';
import 'package:picpos_erp/domain/analytics/financial_snapshot.dart';
import 'package:picpos_erp/domain/analytics/ratio_engine.dart';
import 'package:picpos_erp/presentation/analytics_picpos/fin_analytics_state.dart';
import 'package:picpos_erp/presentation/analytics_picpos/financial_indicators_picpos_screen.dart';

import 'fin_test_support.dart';

FinancialAnalyticsResult _result({
  FinancialSnapshot cur = const FinancialSnapshot(),
  FinancialSnapshot prior = const FinancialSnapshot(),
  bool budgetAvailable = true,
}) =>
    FinancialAnalyticsResult(
      current: cur,
      prior: prior,
      ratios: RatioEngine.computeAll(cur, prior: prior),
      budgetAvailable: budgetAvailable,
      budget: const BudgetTargets.none(),
      priorBudget: const BudgetTargets.none(),
    );

Future<void> _pump(
  WidgetTester tester,
  Future<FinancialAnalyticsResult> Function() load,
) async {
  setUiLocale(english: false);
  tester.view.physicalSize = const Size(1400, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      branchScopeProvider
          .overrideWith((ref) async => const BranchScope.fullAccess()),
      branchListProvider.overrideWith((ref) async => []),
      finIndicatorsProvider.overrideWith((ref, p) => load()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const FinancialIndicatorsPicPosScreen(),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('تحميل ⇒ مؤشّر وعنوان الشاشة', (tester) async {
    final never = Completer<FinancialAnalyticsResult>();
    await _pump(tester, () => never.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('المؤشرات والنسب المالية'), findsOneWidget);
    expect(find.text('جارٍ احتساب المؤشرات...'), findsOneWidget);
  });

  testWidgets('خطأ ⇒ رسالةٌ وزرّ إعادة المحاولة (لا نصَّ الاستثناء)',
      (tester) async {
    await _pump(tester, () => Future.error(StateError('boom-secret')));
    await tester.pump();
    expect(find.text('تعذر احتساب المؤشرات المالية'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.textContaining('boom-secret'), findsNothing);
  });

  testWidgets('لا قيودَ مرحَّلة ⇒ حالةٌ فارغةٌ إرشاديّة بدل أصفار',
      (tester) async {
    await _pump(tester, () async => _result());
    await tester.pump();
    expect(find.text('لا توجد بيانات مرحَّلة في هذه الفترة'), findsOneWidget);
    expect(find.text('تغيير الفترة'), findsOneWidget);
    expect(find.byKey(const ValueKey('risk-panel')), findsNothing);
  });

  testWidgets('بياناتٌ ⇒ أربعُ بطاقات + لوحةُ مخاطر + ستُّ مجموعات',
      (tester) async {
    await _pump(
      tester,
      () async => _result(
        cur: const FinancialSnapshot(
          periodDays: 30,
          revenue: 1000,
          cogs: 600,
          grossProfit: 400,
          netIncome: 100,
          currentAssets: 500,
          cash: 200,
          currentLiabilities: 400,
          totalAssets: 900,
          totalLiabilities: 400,
          equity: 500,
          operatingCashFlow: 150,
        ),
        prior: const FinancialSnapshot(periodDays: 30, revenue: 800),
        budgetAvailable: false,
      ),
    );
    await tester.pump();
    for (final k in ['revenue', 'gross_profit', 'net_income', 'operating_cash_flow']) {
      expect(find.byKey(ValueKey('kpi-$k-value')), findsOneWidget, reason: k);
      expect(tester.widget<Text>(find.byKey(ValueKey('kpi-$k-budget'))).data,
          'غير متاح',
          reason: '$k: الموازنةُ غير متاحة');
    }
    expect(find.byKey(const ValueKey('budget-unavailable-note')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('risk-panel')), findsOneWidget);
    for (final g in RatioGroup.values) {
      expect(find.byKey(ValueKey('ratio-group-${g.name}')), findsOneWidget,
          reason: g.name);
    }
    expect(tester.takeException(), isNull);
  });
}
