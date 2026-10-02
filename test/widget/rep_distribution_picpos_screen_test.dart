// المرحلة و — «إدارة المناديب والتوزيع»: التبويباتُ الأربعة تُرسَم بلا فيضٍ
// ولا استثناءٍ عند 1366×768 في RTL/LTR × فاتح/غامق، وتعرض ما في القاعدة.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/distribution_picpos/distribution_picpos_providers.dart';
import 'package:ural_erp/presentation/distribution_picpos/screens/dm_targets_tab.dart';
import 'package:ural_erp/presentation/distribution_picpos/screens/rep_distribution_picpos_screen.dart';

void main() {
  late AppDatabase db;
  late List<Employee> employees;
  late List<Party> customers;

  Future<void> seed(WidgetTester tester) async {
    db = AppDatabase.forTesting();
    await tester.runAsync(() async {
      await db.getBranches();
      final rep = await db
          .into(db.employees)
          .insert(EmployeesCompanion.insert(name: 'مندوب الشرق'));
      final area = await db.saveDistributionArea(
          name: 'المنطقة الشرقية', code: 'E1', boundary: 'شارع الجامعة');
      final route = await db.saveDistributionRoute(
          name: 'مسار السبت', repEmployeeId: rep, areaId: area, visitDays: [6]);
      for (final name in ['بقالة النور', 'سوبرماركت الأمل']) {
        final c = await db.into(db.parties).insert(PartiesCompanion.insert(
            name: name, isCustomer: const Value(true)));
        await db.assignCustomerToRoute(customerId: c, routeId: route);
      }
      final van = await db
          .into(db.warehouses)
          .insert(WarehousesCompanion.insert(name: 'سيارة الشرق'));
      await db.saveRepResources(employeeId: rep, vanWarehouseId: van);
      employees = await db.select(db.employees).get();
      customers = await (db.select(db.parties)
            ..where((p) => p.isCustomer.equals(true)))
          .get();
    });
    addTearDown(() => tester.runAsync(db.close));
  }

  Future<void> pump(
    WidgetTester tester, {
    required Locale locale,
    required ThemeData theme,
  }) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dmEmployeesProvider.overrideWith((ref) async => employees),
        dmCustomersProvider.overrideWith((ref) async => customers),
        hasPermissionProvider.overrideWith((ref, code) async => true),
        dmMonthTargetsProvider.overrideWith((ref) => Stream.value(const [])),
        dmMonthCollectionsProvider
            .overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: theme,
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const RepDistributionPicPosScreen(),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    for (final dark in [false, true]) {
      final label = '${locale.languageCode}/${dark ? 'dark' : 'light'}';
      testWidgets('التبويباتُ الأربعة تُرسَم — $label', (tester) async {
        await seed(tester);
        await pump(tester,
            locale: locale,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme);

        final dir = Directionality.of(
            tester.element(find.byKey(const Key('dm_tab_areas'))));
        expect(dir,
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr);

        expect(find.text('المنطقة الشرقية'), findsOneWidget);
        expect(find.text('شارع الجامعة'), findsOneWidget);

        await openTab(tester, 'dm_tab_routes');
        expect(find.text('مسار السبت'), findsWidgets);
        expect(find.text('بقالة النور'), findsOneWidget);
        expect(find.text('سوبرماركت الأمل'), findsOneWidget);

        await openTab(tester, 'dm_tab_reps');
        expect(find.text('مندوب الشرق'), findsOneWidget);
        expect(find.text('سيارة الشرق'), findsOneWidget);

        await openTab(tester, 'dm_tab_targets');
        expect(find.byKey(const Key('dm_collection_new')), findsOneWidget);

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('الترتيبُ بأعلى/أسفل يُحفَظ في القاعدة', (tester) async {
    await seed(tester);
    await pump(tester, locale: const Locale('ar'), theme: AppTheme.lightTheme);
    await openTab(tester, 'dm_tab_routes');
    // «سوبرماركت الأمل» ثانيةٌ ⇒ أعلى تجعلها أولى.
    await tester.tap(find.byTooltip('أعلى').last);
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final routeId = (await tester
            .runAsync(() => db.listDistributionRoutes()))!
        .single
        .id;
    final order = (await tester.runAsync(() => db.listRouteCustomers(routeId)))!
        .map((c) => c.customerName)
        .toList();
    expect(order, ['سوبرماركت الأمل', 'بقالة النور']);
  });
}
