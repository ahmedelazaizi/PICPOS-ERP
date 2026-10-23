// QA: the reports hub KPI cards (sales / net profit / returns) hard-coded the
// Egyptian pound «ج.م» even on a JOD install. The unit must be the company
// currency code (AppConstants.currencySymbolEn).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/data/providers/reports_hub_kpi_provider.dart';
import 'package:picpos_erp/presentation/reports_picpos/screens/reports_picpos_screen.dart';

const _kpi = ReportsHubKpi(
  revenue: (today: 1200, yesterday: 1000),
  netProfit: (today: 300, yesterday: 250),
  invoices: (today: 7, yesterday: 5),
  salesReturns: (today: 40, yesterday: 20),
);

Future<void> _pump(WidgetTester tester, String currency) async {
  AppConstants.setCurrency(currency);
  addTearDown(() => AppConstants.setCurrency('JOD'));
  tester.view.physicalSize = const Size(3840, 2160);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previous = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('A RenderFlex overflowed')) return;
    previous?.call(d);
  };
  addTearDown(() => FlutterError.onError = previous);
  await tester.pumpWidget(ProviderScope(
    overrides: [reportsHubKpiProvider.overrideWith((ref) async => _kpi)],
    child: const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: ReportsPicposScreen()),
      ),
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('KPI cards show JOD, never «ج.م», on a JOD install',
      (tester) async {
    await _pump(tester, 'JOD');
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('JOD'), findsNWidgets(3));
    expect(find.text('ج.م'), findsNothing);
  });

  testWidgets('KPI cards follow the configured currency (EGP)',
      (tester) async {
    await _pump(tester, 'EGP');
    expect(find.text('EGP'), findsNWidgets(3));
    expect(find.text('JOD'), findsNothing);
  });
}
