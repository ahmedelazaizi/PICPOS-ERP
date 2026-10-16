// بوّابةُ نطاق الفروع في شاشة «المؤشرات والنسب المالية»: لا أسماءَ فروعٍ قبل
// حسم النطاق، وخطأٌ بإعادة محاولة، ورسالةٌ إرشاديّة للنطاق الفارغ، و`null`
// المحسومة وحدَها تعني «كل الفروع».
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/branch_scope_provider.dart';
import 'package:ural_erp/data/providers/financial_analytics_provider.dart';
import 'package:ural_erp/data/providers/manufacturing_providers.dart'
    show branchListProvider;
import 'package:ural_erp/domain/analytics/budget_targets.dart';
import 'package:ural_erp/domain/analytics/financial_snapshot.dart';
import 'package:ural_erp/domain/analytics/ratio_engine.dart';
import 'package:ural_erp/presentation/analytics_picpos/fin_analytics_state.dart';
import 'package:ural_erp/presentation/analytics_picpos/financial_indicators_picpos_screen.dart';

import 'fin_test_support.dart';

Branche _branch(int id, String name) => Branche(
      id: id,
      name: name,
      isActive: true,
      isSystemDefault: false,
      rowVersion: 1,
    );

final _branches = [
  _branch(1, 'فرع الشمال'),
  _branch(2, 'فرع الجنوب'),
  _branch(3, 'فرع الشرق'),
];
const _names = ['فرع الشمال', 'فرع الجنوب', 'فرع الشرق'];

Future<void> _pump(
  WidgetTester tester,
  Future<BranchScope> Function() scope, {
  void Function()? onFinLoad,
}) async {
  setUiLocale(english: false);
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  const snap = FinancialSnapshot(periodDays: 30, revenue: 1000);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      branchScopeProvider.overrideWith((ref) => scope()),
      branchListProvider.overrideWith((ref) async => _branches),
      finIndicatorsProvider.overrideWith((ref, p) async {
        onFinLoad?.call();
        return FinancialAnalyticsResult(
          current: snap,
          prior: snap,
          ratios: RatioEngine.computeAll(snap, prior: snap),
          budget: const BudgetTargets.none(),
          priorBudget: const BudgetTargets.none(),
        );
      }),
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
  await tester.pump();
}

Future<void> _openBranchMenu(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButton<int?>));
  await tester.pumpAndSettle();
}

Finder _text(String s) => find.text(s, skipOffstage: false);

void main() {
  testWidgets('نطاقٌ قيد التحميل ⇒ لا أسماءَ فروعٍ ولا شريط ولا جلب بيانات',
      (tester) async {
    var fetched = 0;
    final never = Completer<BranchScope>();
    await _pump(tester, () => never.future, onFinLoad: () => fetched++);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(DropdownButton<int?>), findsNothing);
    for (final n in _names) {
      expect(_text(n), findsNothing);
    }
    expect(fetched, 0);
  });

  testWidgets('خطأٌ في النطاق ⇒ رسالةٌ وإعادة محاولة، لا فروع ولا نصَّ الاستثناء',
      (tester) async {
    var calls = 0;
    await _pump(tester, () {
      calls++;
      return Future<BranchScope>.error(StateError('scope-secret'));
    });
    expect(find.text('تعذر تحديد الفروع المسموحة لحسابك'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.textContaining('scope-secret'), findsNothing);
    expect(find.byType(DropdownButton<int?>), findsNothing);
    for (final n in _names) {
      expect(_text(n), findsNothing);
    }
    final before = calls;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump();
    expect(calls, greaterThan(before), reason: 'الضغط يعيد حسم النطاق');
  });

  testWidgets('نطاقٌ فارغ ⇒ رسالةٌ إرشاديّة بلا «كل الفروع» ولا جلب بيانات',
      (tester) async {
    var fetched = 0;
    await _pump(
      tester,
      () async =>
          const BranchScope(allowedBranchIds: <int>{}, primaryBranchId: null),
      onFinLoad: () => fetched++,
    );
    expect(find.text('لا فروعَ مُسنَدةٌ لحسابك'), findsOneWidget);
    expect(
        find.textContaining('اطلب من مدير النظام إسنادَ فرعٍ واحدٍ'),
        findsOneWidget);
    expect(find.textContaining('كل الفروع'), findsNothing);
    expect(find.byType(DropdownButton<int?>), findsNothing);
    expect(fetched, 0);
  });

  testWidgets('نطاقٌ محسوم null (صلاحية كاملة) ⇒ كل الفروع + خيار «كل الفروع»',
      (tester) async {
    await _pump(tester, () async => const BranchScope.fullAccess());
    await _openBranchMenu(tester);
    expect(_text('كل الفروع'), findsWidgets);
    for (final n in _names) {
      expect(_text(n), findsWidgets, reason: n);
    }
  });

  testWidgets('نطاقٌ مقيَّد ⇒ فروعُه وحدَها، والافتراضيّ «كل فروعي» لا فرعٌ بعينه',
      (tester) async {
    await _pump(
      tester,
      () async => const BranchScope(allowedBranchIds: {2}, primaryBranchId: 2),
    );
    await _openBranchMenu(tester);
    expect(_text('فرع الجنوب'), findsWidgets);
    expect(_text('فرع الشمال'), findsNothing);
    expect(_text('فرع الشرق'), findsNothing);
    expect(_text('كل الفروع'), findsWidgets);
  });
}
