// End-to-end flows of the Warehouse app, driven through the real screens, the
// real outbox and the real client over a scripted office (`FakeOffice` keeps a
// command log keyed by x-idempotency-key like the desktop). The desktop side
// itself is proven against the REAL router and database by
// `test/e2e/warehouse_docs_lan_e2e_test.dart` and `test/integration/wh_*` in the
// repository root.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_warehouse/store/wh_local_store.dart';
import 'package:picpos_warehouse/sync/wh_outbox.dart';

import '../docs_flow_test.dart' show RecordingPrinter, kClerk, kSupervisor, openApp, scan, signedIn, typeQty;
import '../fake_office.dart';
import '../support.dart';

void main() {
  setUpAll(loadTestFonts);

  testWidgets('W2: receive a purchase order offline, outbox drains with the same idempotency key', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    final store = WhLocalStore.memory();
    await openApp(tester, office, store: store);
    await tester.tap(find.byKey(const Key('doc.receive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('po.PO1')));
    await tester.pumpAndSettle();
    await scan(tester, '6221234567890');
    await typeQty(tester, '6');
    await tester.tap(find.byKey(const Key('line.add')));
    await tester.pumpAndSettle();

    // The wifi drops while the clerk presses send.
    for (final t in office.transports) {
      t.failWith = const ApiError(kind: ApiErrorKind.network, code: 'network');
    }
    await tester.tap(find.byKey(const Key('receive.send')));
    await tester.pumpAndSettle();
    expect(office.posts, isEmpty);
    final queued = await store.store.outbox();
    expect(queued.map((e) => e.status), [OutboxStatus.pending, OutboxStatus.pending], reason: 'saved, not lost');
    final keys = queued.map((e) => e.globalId).toList();

    // Connection back: reopening the app sends what was saved, once, under the saved ids.
    for (final t in office.transports) {
      t.failWith = null;
    }
    await openApp(tester, office, store: store);
    expect(office.posts.map((p) => p.key), keys);
    expect(office.applied, 2);

    // And a second open (or a retry) cannot apply anything again.
    await openApp(tester, office, store: store);
    expect(office.applied, 2);
    expect((await store.store.outbox()).every((e) => e.status == OutboxStatus.accepted), isTrue);
  });

  testWidgets('W3: request -> approve -> dispatch -> receive a transfer across two phones', (tester) async {
    final office = FakeOffice()..permissions = kSupervisor;
    // Phone A (keeper) makes the request through its outbox; phone B (supervisor) works the screens.
    final phoneA = WhOutbox(WhLocalStore.memory(), await signedIn(office), WhSyncState());
    await phoneA.enqueue('transfer_request', '/api/m1/wh/transfers', {
      'globalId': 'transfer-e2e-0001',
      'fromWarehouseId': 1,
      'toWarehouseId': 2,
      'lines': [
        {'lineGlobalId': 'tline-e2e-0001', 'productId': 5, 'quantity': '4'},
      ],
    });
    await phoneA.drain();
    expect(office.transfers['transfer-e2e-0001']!['state'], 'requested');

    await openApp(tester, office); // phone B
    await tester.tap(find.byKey(const Key('doc.transfers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transfer-e2e-0001.approve')));
    await tester.pumpAndSettle();
    expect(office.transfers['transfer-e2e-0001']!['state'], 'approved');
    await tester.tap(find.byKey(const Key('transfer-e2e-0001.dispatch')));
    await tester.pumpAndSettle();
    expect(office.transfers['transfer-e2e-0001']!['state'], 'in_transit');
    await tester.tap(find.byKey(const Key('transfer-e2e-0001.receive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qty.confirm')));
    await tester.pumpAndSettle();
    expect(office.transfers['transfer-e2e-0001']!['state'], 'received');
    expect(office.posts.map((p) => p.key).toSet(), hasLength(office.posts.length), reason: 'every command has its own key');
  });

  testWidgets('W4: blind count never exposes expected quantities to the counter', (tester) async {
    final office = FakeOffice()..permissions = kClerk; // review holds 137 as expected
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.count')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task.T1')));
    await tester.pumpAndSettle();
    await scan(tester, '6221234567890');
    await typeQty(tester, '130');
    await tester.tap(find.byKey(const Key('count.item.6')));
    await tester.pumpAndSettle();
    await typeQty(tester, '5');
    expect(find.textContaining('137'), findsNothing);
    await tester.tap(find.byKey(const Key('count.send')));
    await tester.pumpAndSettle();
    for (final p in office.posts) {
      expect(p.body.toString().contains('137'), isFalse);
    }
    // The counter has no route to the review at all.
    expect(find.byKey(const Key('doc.approvals')), findsNothing);
  });

  testWidgets('W5: label printing (wedge scanner types the code) and the honest no-printer state', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    final printer = RecordingPrinter();
    await openApp(tester, office, printer: printer);
    await tester.tap(find.byKey(const Key('doc.labels')));
    await tester.pumpAndSettle();
    await scan(tester, '6221234567890'); // a hardware scanner types the digits and Enter
    await tester.tap(find.byKey(const Key('label.print')));
    await tester.pumpAndSettle();
    expect(printer.printed, [('6221234567890', 1)]);
  });

  test('W5: Zebra / Honeywell / Urovo intent profiles', () {},
      skip: 'NOT IMPLEMENTED: needs the physical handhelds (plan E-11); release 1 supports camera + keyboard-wedge scanners only');
}
