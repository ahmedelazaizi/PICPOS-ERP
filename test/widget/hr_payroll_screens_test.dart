// J4 (الجزء ٣) — شاشاتُ الرواتب والسلف والعمولات في PicPos:
//  * «الرواتب» بتبويباتها الأربعة (المسيّرات، بنود الراتب، القواعد، ربط
//    الحسابات)، وصفحةُ المسيّر وقسيمةُ الموظف، و«السلف والجزاءات»، و«عمولات
//    المندوبين» بالخطط والكشف، وتبويبُ «الرواتب» في ملفّ الموظف — تُرسَم بلا
//    فيضٍ ولا استثناءٍ عند 1366×768 في RTL/LTR × فاتح/غامق؛
//  * دورةُ المسيّر من الواجهة (مراجعة ← اعتماد)، والتسويةُ اليدويّةُ بسببٍ
//    إلزاميّ من القسيمة؛
//  * حفظُ القواعد من الواجهة.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/hr_employee_file.dart';
import 'package:picpos_erp/domain/models/hr_payroll.dart';
import 'package:picpos_erp/presentation/hr_picpos/screens/hr_advances_picpos_screen.dart';
import 'package:picpos_erp/presentation/hr_picpos/screens/hr_commissions_picpos_screen.dart';
import 'package:picpos_erp/presentation/hr_picpos/screens/hr_employee_file_screen.dart';
import 'package:picpos_erp/presentation/hr_picpos/screens/hr_payroll_picpos_screen.dart';
import 'package:picpos_erp/presentation/hr_picpos/screens/payroll_run_screen.dart';

void main() {
  late AppDatabase db;
  late int empA;
  late int runId;
  late int advanceId;
  late int planId;
  late int adjustmentId;

  Future<void> seed(WidgetTester tester) async {
    db = AppDatabase.forTesting();
    await tester.runAsync(() async {
      await db.getBranches();
      await db.syncDefaultAccounts();
      for (var y = 2025; y <= DateTime.now().year + 1; y++) {
        await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
              name: '$y',
              startDate: DateTime(y, 1, 1),
              endDate: DateTime(y, 12, 31),
              isClosed: const Value(false),
            ));
      }
      final safe = await db.into(db.safes).insert(SafesCompanion.insert(
          name: 'الخزنة', safeType: const Value('cash')));
      final dept = await db.saveHrDepartment(name: 'المبيعات');
      empA = await db.saveEmployeeProfile(
        EmployeeProfile(
            name: 'أحمد',
            code: 'EMP-1',
            departmentId: dept,
            basicSalary: 3000,
            hoursPerDay: 8,
            hireDate: DateTime(2020)),
        allowances: const [EmployeeAllowance(name: 'بدل نقل', amount: 200)],
      );
      await db.saveEmployeeProfile(EmployeeProfile(
          name: 'مندوب',
          code: 'EMP-2',
          basicSalary: 2000,
          roleTags: const {HrRoleTag.rep},
          hireDate: DateTime(2020)));
      await db.saveSalaryComponent(const SalaryComponent(
          name: 'بدل سكن', calc: ComponentCalc.percentBasic, amount: 10));
      planId = await db.saveCommissionPlan(const CommissionPlan(
          name: 'افتراضية',
          salesRatePct: 2,
          collectionsRatePct: 1,
          tiers: [CommissionTier(minAchievementPct: 100, salesRatePct: 3)]));
      advanceId = await db.createEmployeeAdvance(
          employeeId: empA,
          amount: 600,
          installments: 3,
          safeId: safe,
          date: DateTime(2025, 5, 10));
      adjustmentId = await db.createPayrollAdjustment(PayrollAdjustment(
          employeeId: empA,
          kind: AdjustmentKind.bonus,
          amount: 150,
          year: 2025,
          month: 6,
          reason: 'تميز'));
      runId = await db.createPayrollRun(
          year: 2025, month: 6, now: DateTime(2026));
    });
    addTearDown(() => tester.runAsync(db.close));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('ar'),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (locale.languageCode == 'en') {
      I18nCatalog.setCatalog(Map<String, String>.from(jsonDecode(
          File('assets/i18n/en.json').readAsStringSync()) as Map));
      I18nCatalog.setLocale(const Locale('en'));
      addTearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        hasPermissionProvider.overrideWith((ref, code) async => true),
        branchScopeProvider
            .overrideWith((ref) async => const BranchScope.fullAccess()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    ));
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await settle(tester);
  }

  int rows(String prefix) => find
      .byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(prefix))
      .evaluate()
      .length;

  Future<int> lineOf(WidgetTester tester, int emp) async =>
      (await tester.runAsync(() => db.listPayrollLines(runId: runId)))!
          .singleWhere((l) => l.employeeId == emp)
          .id;

  for (final locale in const [Locale('ar'), Locale('en')]) {
    for (final dark in [false, true]) {
      final label = '${locale.languageCode}/${dark ? 'dark' : 'light'}';
      ThemeData theme() => dark ? AppTheme.darkTheme : AppTheme.lightTheme;

      testWidgets('الرواتب: المسيّرات والبنود والقواعد والحسابات بلا فيض — $label',
          (tester) async {
        await seed(tester);
        await pump(tester, const HrPayrollPicPosScreen(),
            locale: locale, theme: theme());
        final dir = Directionality.of(
            tester.element(find.byKey(const Key('payroll_tab_runs'))));
        expect(dir,
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr);
        expect(find.byKey(Key('payroll_run_row_$runId')), findsOneWidget);
        expect(find.text(tr('مسودة')), findsWidgets);
        await tap(tester, find.byKey(const Key('payroll_tab_components')));
        expect(rows('payroll_component_row_'), 1);
        await tap(tester, find.byKey(const Key('payroll_tab_rules')));
        expect(find.byKey(const Key('payroll_rules_save')), findsOneWidget);
        await tester.scrollUntilVisible(
            find.byKey(const Key('payroll_preset_jo')), 200,
            scrollable: find.byType(Scrollable).last);
        await settle(tester);
        await tap(tester, find.byKey(const Key('payroll_tab_accounts')));
        expect(find.byKey(const Key('payroll_account_salaries_expense')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('صفحةُ المسيّر وقسيمةُ الموظف بلا فيض — $label',
          (tester) async {
        await seed(tester);
        await pump(tester, PayrollRunScreen(runId: runId),
            locale: locale, theme: theme());
        expect(rows('payroll_line_'), 2);
        expect(find.byKey(const Key('payroll_review')), findsOneWidget);
        final line = await lineOf(tester, empA);
        await tap(tester, find.byKey(Key('payroll_line_$line')));
        expect(find.byKey(const Key('payslip_earnings')), findsOneWidget);
        expect(find.byKey(const Key('payslip_deductions')), findsOneWidget);
        expect(find.text(tr('قسط سلفة')), findsOneWidget);
        expect(find.text(tr('الراتب الأساسي')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('السلف والجزاءات بلا فيض — $label', (tester) async {
        await seed(tester);
        await pump(tester, const HrAdvancesPicPosScreen(),
            locale: locale, theme: theme());
        expect(find.byKey(Key('advance_row_$advanceId')), findsOneWidget);
        expect(find.byKey(Key('advance_settle_$advanceId')), findsOneWidget);
        await tap(tester, find.byKey(const Key('advance_new')));
        expect(find.byKey(const Key('advance_amount')), findsOneWidget);
        await tap(tester, find.text(tr('إلغاء')).last);
        await tap(tester, find.byKey(const Key('advances_tab_adjustments')));
        expect(find.byKey(Key('adjustment_row_$adjustmentId')), findsOneWidget);
        expect(find.byKey(Key('adjustment_approve_$adjustmentId')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('خطط العمولة والكشف بلا فيض — $label', (tester) async {
        await seed(tester);
        await pump(tester, const HrCommissionsPicPosScreen(),
            locale: locale, theme: theme());
        expect(find.byKey(Key('commission_plan_row_$planId')), findsOneWidget);
        await tap(tester, find.byKey(Key('commission_plan_row_$planId')));
        expect(find.byKey(const Key('commission_tier_0_min')), findsOneWidget);
        await tap(tester, find.text(tr('إلغاء')).last);
        await tap(tester, find.byKey(const Key('commission_tab_statement')));
        expect(find.byKey(const Key('commission_statement_rep')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('تبويبُ الرواتب في ملفّ الموظف بلا فيض — $label',
          (tester) async {
        await seed(tester);
        await pump(tester, HrEmployeeFileScreen(employeeId: empA, initialTab: 8),
            locale: locale, theme: theme());
        final line = await lineOf(tester, empA);
        expect(find.byKey(Key('ef_payslip_$line')), findsOneWidget);
        expect(find.byKey(Key('advance_row_$advanceId')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('دورةُ المسيّر من الواجهة، والتسويةُ تحتاج سبباً', (tester) async {
    await seed(tester);
    await pump(tester, PayrollRunScreen(runId: runId));
    final line = await lineOf(tester, empA);
    await tap(tester, find.byKey(Key('payroll_line_$line')));
    await tap(tester, find.text('تسوية'));
    await tester.enterText(find.byKey(const Key('payroll_adj_amount')), '75');
    await tap(tester, find.text('حفظ'));
    expect(find.text('سبب التسوية مطلوب.'), findsOneWidget,
        reason: 'no reason ⇒ refused, the dialog stays');
    await tester.enterText(
        find.byKey(const Key('payroll_adj_reason')), 'ساعات جرد');
    await tap(tester, find.text('حفظ'));
    final items = (await tester.runAsync(() => db.listPayrollLines(runId: runId)))!
        .singleWhere((l) => l.employeeId == empA)
        .items;
    final manual = items.singleWhere((i) => i.code == PayItemCode.manual);
    expect(manual.amount, 75);
    expect(manual.reason, 'ساعات جرد');
    await tap(tester, find.text('إغلاق'));

    await tap(tester, find.byKey(const Key('payroll_review')));
    expect((await tester.runAsync(() => db.getPayrollRun(runId)))!.status,
        PayrollRunStatus.reviewed);
    await tap(tester, find.byKey(const Key('payroll_approve')));
    expect((await tester.runAsync(() => db.getPayrollRun(runId)))!.status,
        PayrollRunStatus.approved);
    expect(find.byKey(const Key('payroll_post')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('القواعدُ تُحفظ من الواجهة', (tester) async {
    await seed(tester);
    await pump(tester, const HrPayrollPicPosScreen(initialTab: 2));
    await tester.enterText(find.byKey(const Key('payroll_rule_ot_rate')), '1.5');
    await tap(tester, find.byKey(const Key('payroll_rules_save')));
    final rules = (await tester.runAsync(db.payrollRules))!;
    expect(rules.overtimeRate, 1.5);
    expect(rules.insuranceEnabled, isFalse,
        reason: 'insurance stays off until the user enables it');
    await tester.pump(const Duration(seconds: 3)); // the toast's timer
    expect(tester.takeException(), isNull);
  });
}
