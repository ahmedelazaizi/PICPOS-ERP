import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/reports/inventory_report_screen.dart';

void main() {
  testWidgets('يعرض التحميل ثم محتوى تقرير المخزون بلا أخطاء', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting();
    await tester.runAsync(() async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            code: 'LOAD-1',
            name: 'صنف اختبار التحميل',
            currentStock: const Value(4),
            costPrice: const Value(10),
            salePrice: const Value(15),
          ));
    });
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      branchScopeProvider.overrideWithValue(
        const AsyncData(BranchScope.fullAccess()),
      ),
      activeBranchIdProvider.overrideWith(
        (ref) => Future<int?>.delayed(
          const Duration(milliseconds: 50),
          () => 1,
        ),
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar'), Locale('en')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: InventoryReportScreen(),
      ),
    ));
    expect(find.byType(ListView), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('صنف اختبار التحميل'), findsOneWidget);
    expect(find.text('LOAD-1'), findsOneWidget);
    expect(tester.takeException(), isNull);

  });
}
