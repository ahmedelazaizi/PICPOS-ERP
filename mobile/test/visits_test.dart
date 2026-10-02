import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/app.dart';
import 'package:picpos_van/domain/sale_math.dart';
import 'package:picpos_van/state/app_controller.dart';

import 'support/fakes.dart';

void main() {
  test('visit states: planned → no sale (reason required) → visited after a sale', () async {
    final (c, api) = await readyController();
    expect((await c.visitState('c1')).$1, VisitState.planned);
    await expectLater(() => c.createVisit(customerGlobalId: 'c1', outcome: 'no_sale'),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'reasonRequired')));
    await expectLater(() => c.createVisit(customerGlobalId: 'c1', outcome: 'no_sale', noSaleReason: 'bored'),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'reasonRequired')));

    await c.createVisit(customerGlobalId: 'c1', outcome: 'no_sale', noSaleReason: 'has_stock');
    expect(await c.visitState('c1'), (VisitState.noSale, 'has_stock'));
    expect((await c.visitState('c2')).$1, VisitState.planned);

    await c.createSale(
        customerGlobalId: 'c1',
        lines: [CartLine(productGlobalId: 'p2', name: 'b', unitPrice: 1, taxRate: 0)],
        paid: 1);
    expect((await c.visitState('c1')).$1, VisitState.visited);
    await c.createVisit(customerGlobalId: 'c2', outcome: 'visited');
    expect((await c.visitState('c2')).$1, VisitState.visited);

    await c.syncNow();
    final visits = api.pushed.single.where((d) => d['kind'] == 'visit').toList();
    expect(visits.first, allOf(containsPair('outcome', 'no_sale'), containsPair('noSaleReason', 'has_stock'),
        containsPair('customerGlobalId', 'c1')));
    expect(visits.last.containsKey('noSaleReason'), isFalse);
  });

  testWidgets('route lists customers in route order; no-sale with reason shows on the route', (tester) async {
    final (c, _) = await readyController();
    await tester.pumpWidget(PicposVanApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('مخطط'), findsNWidgets(2));
    final first = tester.getTopLeft(find.text('بقالة الأمل')).dy;
    final second = tester.getTopLeft(find.text('سوبرماركت النور')).dy;
    expect(first, lessThan(second), reason: 'sequence 1 before 2');

    await tester.tap(find.text('بقالة الأمل'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('noSale')));
    await tester.tap(find.byKey(const Key('noSale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nsr-closed')));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('لا بيع · المحل مغلق'), findsOneWidget);
    expect(find.text('مخطط'), findsOneWidget);
  });
}
