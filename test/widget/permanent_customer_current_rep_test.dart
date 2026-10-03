// J4 — «حفظ كعميل دائم»: مسارُ المندوب الحاليّ (من ربط المستخدم بموظفه)
// يُختار مسبقاً، ويبقى المنتقي احتياطاً لمن ليس مندوباً.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/distribution_model.dart';
import 'package:ural_erp/presentation/sales_invoices_picpos/screens/permanent_customer_dialog.dart';

void main() {
  const routes = [
    DistributionRoute(id: 1, name: 'خط الأحد'),
    DistributionRoute(id: 2, name: 'خط السبت'),
  ];

  Future<PermanentCustomerInput?> open(
      WidgetTester tester, int? preferredRouteId) async {
    PermanentCustomerInput? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showPermanentCustomerDialog(
              context,
              name: 'بقالة',
              routes: routes,
              preferredRouteId: preferredRouteId),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('permanent_customer_save')));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('مسارُ المندوب الحاليّ مختارٌ مسبقاً', (tester) async {
    final input = await open(tester, 2);
    expect(input!.routeId, 2);
  });

  testWidgets('غيرُ المندوب: لا اختيارَ مسبق مع أكثر من مسار', (tester) async {
    final input = await open(tester, null);
    expect(input!.routeId, isNull);
  });

  testWidgets('مسارٌ مقترَحٌ غيرُ متاح لا يُفرَض', (tester) async {
    final input = await open(tester, 99);
    expect(input!.routeId, isNull);
  });
}
