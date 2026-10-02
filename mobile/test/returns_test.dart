import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/app.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/state/app_controller.dart';

import 'support/fakes.dart';

// Fixture invoice VS-99 (customer c2): water 4 sold (11.60, tax 1.60), 1
// already returned (2.90 offset); bread 2 (2.00); total 13.60, paid 5.00.
void main() {
  test('return against invoice lines: amounts, settlement, pending effects, qty ≤ sold − returned', () async {
    final (c, api) = await readyController();
    expect((await c.returnableInvoices('c2')).single['number'], 'VS-99');
    expect(await c.returnableInvoices('c1'), isEmpty);

    final r1 = await c.createReturn(invoiceGlobalId: 'inv1', quantities: {'p1': 1}, reason: 'damaged');
    expect(r1.payload['number'], 'VR-100000');
    expect((r1.payload['total'], r1.payload['cashRefund'], r1.payload['_arOffset']), (2.9, 0.0, 2.9));
    expect(r1.payload['customerGlobalId'], 'c2');

    // Remaining 2 waters: takes exactly what is left (no rounding drift);
    // open amount 13.60 − 5.00 − 2.90 − 2.90 = 2.80 is offset, rest refunded.
    final p = await c.previewReturn('inv1', {'p1': 2});
    expect((p.total, p.tax, p.arOffset, p.cashRefund), (5.8, 0.8, 2.8, 3.0));
    final r2 = await c.createReturn(invoiceGlobalId: 'inv1', quantities: {'p1': 2});
    expect(r2.payload['number'], 'VR-100001');

    await expectLater(() => c.createReturn(invoiceGlobalId: 'inv1', quantities: {'p1': 1}),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'returnQtyExceeds')));
    await expectLater(() => c.createReturn(invoiceGlobalId: 'inv1', quantities: {'p9': 1}),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'returnQtyExceeds')));
    await expectLater(() => c.createReturn(invoiceGlobalId: 'inv1', quantities: {'p1': 0}),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'emptyReturn')));

    // Nothing unpaid left: the bread is refunded in cash.
    final bread = await c.previewReturn('inv1', {'p2': 2});
    expect((bread.total, bread.arOffset, bread.cashRefund), (2.0, 0.0, 2.0));

    expect(await c.effectiveBalance('c2'), -5.7, reason: 'offsets of unsent returns');
    expect(await c.availableStock('p1'), 8.0, reason: 'returned goods go back into the van');

    // Local bookkeeping (`_…`) never reaches the server.
    await c.syncNow();
    final sent = api.pushed.single;
    expect(sent.map((d) => d['kind']), ['sales_return', 'sales_return']);
    expect(sent.first.keys.where((k) => k.startsWith('_')), isEmpty);
    expect((sent.first['lines'] as List).single, {'productGlobalId': 'p1', 'quantity': 1.0});
    expect(sent.first['originalInvoiceGlobalId'], 'inv1');
    expect((await c.store.outbox()).every((e) => e.status == OutboxStatus.accepted), isTrue);
  });

  testWidgets('return screen: pick invoice, return 1 water, save to outbox', (tester) async {
    final (c, _) = await readyController();
    await tester.pumpWidget(PicposVanApp(controller: c, initialLocale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سوبرماركت النور'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('openReturn')));
    await tester.tap(find.byKey(const Key('openReturn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invoice-VS-99')));
    await tester.pumpAndSettle();
    expect(find.text('Sold: 4 · Returnable: 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ret-inc-p1')));
    await tester.pumpAndSettle();
    expect(find.text('2.90'), findsNWidgets(2)); // return total + offset
    await tester.tap(find.byKey(const Key('saveReturn')));
    await tester.pumpAndSettle();
    final e = (await c.store.outbox()).single;
    expect((e.kind, e.payload['number'], e.payload['total']), ('sales_return', 'VR-100000', 2.9));
  });
}
