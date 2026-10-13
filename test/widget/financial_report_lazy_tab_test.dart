import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/accounting_picpos/financial_report_lazy_tab.dart';

void main() {
  testWidgets('يعرض حالة التحميل ثم محتوى التبويب النشط فقط', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialReportLazyTab(
          active: false,
          builder: (_) {
            builds++;
            return const Text('محتوى التقرير');
          },
        ),
      ),
    );

    expect(find.text('محتوى التقرير'), findsNothing);
    expect(builds, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: FinancialReportLazyTab(
          active: true,
          builder: (_) {
            builds++;
            return const Center(child: Text('محتوى التقرير'));
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('محتوى التقرير'), findsOneWidget);
    expect(builds, 1);
  });
}
