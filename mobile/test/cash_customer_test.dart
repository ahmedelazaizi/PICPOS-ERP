import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/domain/sale_math.dart';
import 'package:picpos_van/printing/receipt_composer.dart';
import 'package:picpos_van/state/app_controller.dart';

import 'support/fakes.dart';

/// J3 — the system cash customer (served to every rep), the one-time
/// customer name, and «حفظ كعميل دائم» created offline then pushed.
CartLine water(double q) => CartLine(productGlobalId: 'p1', name: 'مياه ٦ لتر', unitPrice: 2.5, taxRate: 16, quantity: q);

Future<(AppController, FakeCloudApi)> withCashCustomer() async {
  final (c, api) = await readyController();
  await c.applyServerPayload({
    'routes': [
      {'globalId': 'r1', 'name': 'خط الشمال'},
    ],
    'customers': [
      {'globalId': 'c1', 'name': 'بقالة الأمل', 'balance': 90.0, 'creditLimit': 100.0, 'sequence': 1, 'routeGlobalId': 'r1'},
      {'globalId': 'c2', 'name': 'سوبرماركت النور', 'balance': 0.0, 'creditLimit': 0.0, 'sequence': 2, 'routeGlobalId': 'r1'},
      {'globalId': 'cash', 'name': 'عميل نقدي', 'balance': 0.0, 'creditLimit': 0.0, 'sequence': 0,
       'systemRole': 'cash_customer', 'cashOnly': true},
    ],
    'customerScope': ['c1', 'c2', 'cash'],
  });
  return (c, api);
}

void main() {
  test('one-time name on a cash-customer sale: stored, pushed, printed instead of «عميل نقدي»', () async {
    final (c, api) = await withCashCustomer();
    final e = await c.createSale(
        customerGlobalId: 'cash', lines: [water(2)], paid: 5.8, customerName: '  سليمان ', customerPhone: '0791234567');
    expect(e.payload['customerName'], 'سليمان');
    expect(e.payload['customerPhone'], '0791234567');

    final r = await ReceiptComposer(c).compose(e);
    expect(r.valueOf('العميل'), 'سليمان');

    await c.syncNow();
    final wire = api.pushed.last.single;
    expect(wire['customerName'], 'سليمان');
    expect(wire['customerPhone'], '0791234567');
  });

  test('cash customer sells cash only; a route customer never carries a one-time name', () async {
    final (c, _) = await withCashCustomer();
    await expectLater(c.createSale(customerGlobalId: 'cash', lines: [water(2)], paid: 1),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'cashOnly')));
    final e = await c.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 0, customerName: 'x');
    expect(e.payload.containsKey('customerName'), isFalse);
  });

  test('«حفظ كعميل دائم» offline: pending cash-only customer at the end of the route, '
      'kept on pull, pushed before its sale', () async {
    final (c, api) = await withCashCustomer();
    api.offline = true;
    final gid = await c.createFieldCustomer(name: ' محل الوادي ', phone: '0795555555', address: 'شارع ١');
    final local = (await c.store.get(Kinds.customers, gid))!;
    expect(local['name'], 'محل الوادي');
    expect(local['routeGlobalId'], 'r1');
    expect(local['sequence'], 3, reason: 'after c1 (1) and c2 (2)');
    expect(local['creditLimit'], 0.0);
    expect(isCashOnlyCustomer(local), isTrue);

    // The rep sells to it right away — cash only.
    await expectLater(c.createSale(customerGlobalId: gid, lines: [water(1)], paid: 0),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'cashOnly')));
    final sale = await c.createSale(customerGlobalId: gid, lines: [water(1)], paid: 2.9);

    // A pull while the document is still pending does not drop it.
    await c.applyServerPayload({'customerScope': ['c1', 'c2', 'cash']});
    expect(await c.store.get(Kinds.customers, gid), isNotNull);

    final outbox = await c.pendingDocs();
    expect(outbox.map((e) => e.kind), containsAll(['customer', 'sales_invoice']));
    final custDoc = outbox.firstWhere((e) => e.kind == 'customer');
    expect(custDoc.payload, containsPair('name', 'محل الوادي'));
    expect(custDoc.payload, containsPair('routeGlobalId', 'r1'));

    api.offline = false;
    expect(await c.syncNow(), isTrue);
    final batch = api.pushed.last;
    expect(batch.map((d) => d['kind']).toList(), ['customer', 'sales_invoice'],
        reason: 'the customer reaches the cloud before the sale made to it');
    expect(batch.first['globalId'], gid);
    expect(batch.last['customerGlobalId'], gid);
    expect(batch.last['globalId'], sale.globalId);
    expect(batch.first.keys.where((k) => k.startsWith('_')), isEmpty);
    expect(await c.pendingDocs(), isEmpty);
  });

  test('a field customer needs a name and a route', () async {
    final (c, _) = await readyController();
    await expectLater(c.createFieldCustomer(name: '  '),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'nameRequired')));
    await expectLater(c.createFieldCustomer(name: 'محل'),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'noRoute')));
  });
}
