// J4 — شاشاتُ الموارد البشريّة في PicPos:
//  * سجلُّ الموظفين يرشّح بالقسم والحالة والدور والبحث؛
//  * ملفُّ الموظف بتبويباته الستّة يُرسَم بلا فيضٍ ولا استثناءٍ عند
//    1366×768 في RTL/LTR × فاتح/غامق؛
//  * لوحةُ «الدور في النظام» تعرض المستخدمَ المربوط ولوحةَ المندوب، وتربط
//    مستخدماً قائماً من الواجهة؛
//  * شاشةُ الأقسام والمسمّيات والهيكلُ التنظيميّ.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/models/hr_employee_file.dart';
import 'package:ural_erp/presentation/hr_picpos/screens/hr_employee_file_screen.dart';
import 'package:ural_erp/presentation/hr_picpos/screens/hr_employees_picpos_screen.dart';
import 'package:ural_erp/presentation/hr_picpos/screens/hr_organization_picpos_screen.dart';

void main() {
  late AppDatabase db;
  late int repId;
  late int cashierId;
  late int unlinkedId;
  late int freeUserId;

  Future<void> seed(WidgetTester tester) async {
    db = AppDatabase.forTesting();
    await tester.runAsync(() async {
      await db.getBranches();
      final sales = await db.saveHrDepartment(name: 'المبيعات');
      final store = await db.saveHrDepartment(name: 'المخازن');
      final repTitle =
          await db.saveHrJobTitle(name: 'مندوب', departmentId: sales);
      final keeper = await db.saveHrJobTitle(name: 'أمين', departmentId: store);
      final manager = await db.saveEmployeeProfile(EmployeeProfile(
          name: 'مدير المبيعات', departmentId: sales, basicSalary: 9000));
      repId = await db.saveEmployeeProfile(
        EmployeeProfile(
          name: 'مندوب الشرق',
          departmentId: sales,
          jobTitleId: repTitle,
          managerId: manager,
          basicSalary: 4000,
          paymentMethod: SalaryPaymentMethod.bank,
          iban: 'EG12',
        ),
        allowances: const [EmployeeAllowance(name: 'سكن', amount: 500)],
      );
      await db.setEmployeeRoleTags(repId, {HrRoleTag.rep});
      final u = await db.createUser(
          username: 'rep.east', password: 'pw-rep-1', displayName: 'Rep');
      await db.linkEmployeeUser(employeeId: repId, userId: u);
      await db.saveDistributionRoute(name: 'خط السبت', repEmployeeId: repId);
      await db.saveEmployeeDocument(
          repId,
          EmployeeDocument(
              docType: 'رخصة قيادة',
              expiryDate: DateTime.now().add(const Duration(days: 5))));
      cashierId = await db.saveEmployeeProfile(EmployeeProfile(
          name: 'أمين المخزن',
          departmentId: store,
          jobTitleId: keeper,
          status: EmployeeStatus.suspended));
      await db.setEmployeeRoleTags(cashierId, {HrRoleTag.warehouseKeeper});
      unlinkedId = await db.saveEmployeeProfile(
          const EmployeeProfile(name: 'موظف بلا مستخدم'));
      freeUserId = await db.createUser(
          username: 'free.user', password: 'pw-free-1', displayName: 'Free');
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

  Future<void> pick(WidgetTester tester, String key, String item) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await settle(tester);
  }

  int rowCount() => find
      .byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('hr_row_'))
      .evaluate()
      .length;

  group('سجلُّ الموظفين', () {
    testWidgets('يعرض الكلَّ ويرشّح بالقسم والحالة والدور والبحث',
        (tester) async {
      await seed(tester);
      await pump(tester, const HrEmployeesPicPosScreen());
      expect(rowCount(), 4);
      expect(find.text('rep.east'), findsOneWidget,
          reason: 'the linked login user shows in the list');
      expect(find.byKey(Key('hr_docs_warning_$repId')), findsOneWidget,
          reason: 'a document expiring within 30 days warns');

      await pick(tester, 'hr_filter_department', 'المخازن');
      expect(rowCount(), 1);
      expect(find.byKey(Key('hr_row_$cashierId')), findsOneWidget);

      await tester.tap(find.byKey(const Key('hr_filter_clear')));
      await settle(tester);
      expect(rowCount(), 4);

      await pick(tester, 'hr_filter_status', 'موقوف');
      expect(rowCount(), 1);
      await tester.tap(find.byKey(const Key('hr_filter_clear')));
      await settle(tester);

      await pick(tester, 'hr_filter_role', 'مندوب مبيعات');
      expect(rowCount(), 1);
      expect(find.byKey(Key('hr_row_$repId')), findsOneWidget);
      await tester.tap(find.byKey(const Key('hr_filter_clear')));
      await settle(tester);

      await tester.enterText(find.byKey(const Key('hr_search')), 'بلا مستخدم');
      await settle(tester);
      expect(rowCount(), 1);
      expect(find.byKey(Key('hr_row_$unlinkedId')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ملفُّ الموظف', () {
    for (final locale in const [Locale('ar'), Locale('en')]) {
      for (final dark in [false, true]) {
        final label = '${locale.languageCode}/${dark ? 'dark' : 'light'}';
        testWidgets('التبويباتُ الستّة بلا فيض — $label', (tester) async {
          await seed(tester);
          await pump(tester, HrEmployeeFileScreen(employeeId: repId),
              locale: locale,
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme);
          final dir = Directionality.of(
              tester.element(find.byKey(const Key('ef_tab_personal'))));
          expect(dir,
              locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr);
          expect(find.byKey(const Key('ef_name')), findsOneWidget);
          for (final tab in [
            'job',
            'pay',
            'documents',
            'history',
            'roles',
          ]) {
            await tester.tap(find.byKey(Key('ef_tab_$tab')));
            await settle(tester);
            expect(tester.takeException(), isNull, reason: 'tab $tab');
          }
          // Roles tab: the linked user and the rep panel.
          expect(find.text('rep.east'), findsOneWidget);
          expect(find.byKey(const Key('ef_rep_pairing')), findsOneWidget);
          expect(find.textContaining('خط السبت'), findsWidgets);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('العقدُ والأجر يعرض البدلات والإجماليّ والآيبان', (tester) async {
      await seed(tester);
      await pump(tester, HrEmployeeFileScreen(employeeId: repId));
      await tester.tap(find.byKey(const Key('ef_tab_pay')));
      await settle(tester);
      expect(find.text('500.00'), findsOneWidget);
      expect(find.text('EG12'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ef_allowance_add')));
      await settle(tester);
      await tester.enterText(
          find.byKey(const Key('ef_allowance_name_1')), 'انتقال');
      await tester.enterText(
          find.byKey(const Key('ef_allowance_amount_1')), '250');
      await settle(tester);
      expect(find.text('750.00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ef_save')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      final allowances =
          (await tester.runAsync(() => db.listEmployeeAllowances(repId)))!;
      expect(allowances.map((a) => a.name), ['سكن', 'انتقال']);
    });

    testWidgets('موظفٌ جديد يُحفَظ من الواجهة ويُسجَّل تعيينه', (tester) async {
      await seed(tester);
      await pump(tester, const HrEmployeeFileScreen());
      await tester.enterText(find.byKey(const Key('ef_name')), 'موظف جديد للاختبار');
      await tester.tap(find.byKey(const Key('ef_save')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      final all = (await tester.runAsync(db.listEmployeeProfiles))!;
      final created = all.singleWhere((p) => p.name == 'موظف جديد للاختبار');
      expect(created.code, startsWith('EMP-'));
      final history =
          (await tester.runAsync(() => db.listEmployeeHistory(created.id!)))!;
      expect(history.single.eventType, HrEventType.appointment);
    });
  });

  group('لوحةُ الدور في النظام', () {
    testWidgets('ربطُ مستخدمٍ قائمٍ من الواجهة', (tester) async {
      await seed(tester);
      await pump(tester,
          HrEmployeeFileScreen(employeeId: unlinkedId, initialTab: 5));
      expect(find.byKey(const Key('ef_create_user')), findsOneWidget);
      expect(find.byKey(const Key('ef_rep_pairing')), findsNothing,
          reason: 'no rep tag ⇒ no rep panel');
      await pick(tester, 'ef_link_user', 'Free (free.user)');
      await tester.tap(find.byKey(const Key('ef_link_user_save')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(
          await tester.runAsync(() => db.employeeIdForUser(freeUserId)),
          unlinkedId);
      expect(find.text('free.user'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('وسمُ «مندوب مبيعات» يُظهر لوحةَ المندوب', (tester) async {
      await seed(tester);
      await pump(tester,
          HrEmployeeFileScreen(employeeId: unlinkedId, initialTab: 5));
      await tester.tap(find.byKey(const Key('ef_tag_rep')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.byKey(const Key('ef_rep_pairing')), findsOneWidget);
      expect(
          (await tester.runAsync(() => db.getEmployeeProfile(unlinkedId)))!
              .isRep,
          isTrue);
    });
  });

  group('الأقسامُ والمسمّياتُ والهيكل', () {
    for (final dark in [false, true]) {
      testWidgets('التبويباتُ الثلاثة — ${dark ? 'dark' : 'light'}',
          (tester) async {
        await seed(tester);
        await pump(tester, const HrOrganizationPicPosScreen(),
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme);
        expect(find.text('المبيعات'), findsWidgets);
        await tester.tap(find.byKey(const Key('hr_org_tab_titles')));
        await settle(tester);
        expect(find.text('مندوب'), findsWidgets);
        await tester.tap(find.byKey(const Key('hr_org_tab_chart')));
        await settle(tester);
        expect(find.textContaining('مدير المبيعات'), findsWidgets);
        expect(find.textContaining('مندوب الشرق'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
