// W2-W5 screens against a scripted office: receive, count (blind), transfers,
// approvals, labels. Every write must carry its idempotency key.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';
import 'package:picpos_warehouse/app.dart';
import 'package:picpos_warehouse/printing/label_printer.dart';
import 'package:picpos_warehouse/session/wh_session.dart';
import 'package:picpos_warehouse/store/wh_local_store.dart';
import 'package:picpos_warehouse/sync/wh_outbox.dart';

import 'fake_office.dart';
import 'support.dart';

const kClerk = ['warehouse_mobile_access', 'inventory_view', 'goods_receipt_mobile', 'stock_count_submit'];
const kSupervisor = [...kClerk, 'inventory_edit', 'inventory_transfer', 'stock_adjust_approve'];

class RecordingPrinter implements LabelPrinter {
  RecordingPrinter({this.connected = true});
  final bool connected;
  final printed = <(String, int)>[];
  @override
  bool get hasPrinter => connected;
  @override
  String? get printerName => connected ? 'Test printer' : null;
  @override
  Future<LabelPrintResult> printLabel(WhLabelData label, {int copies = 1, String locale = 'ar'}) async {
    if (!connected) return const LabelPrintResult(LabelPrintStatus.noPrinter);
    printed.add((label.barcode, copies));
    return const LabelPrintResult(LabelPrintStatus.printed);
  }
}

Future<WhSession> signedIn(FakeOffice office) async {
  final s = office.session(MemorySecretStore());
  await s.restore();
  await s.pair(PairingPayload.parse(office.qr()));
  await s.login('ali', 'pw');
  return s;
}

Future<void> openApp(
  WidgetTester tester,
  FakeOffice office, {
  int dest = 2,
  LabelPrinter? printer,
  WhLocalStore? store,
  WhSession? session,
  Locale locale = const Locale('en'),
  ThemeMode mode = ThemeMode.light,
  Size size = kPhone,
}) async {
  setSurface(tester, size);
  await tester.pumpWidget(PicPosWarehouseApp(
    key: UniqueKey(),
    settings: PicPosAppSettings(locale: locale, themeMode: mode),
    session: session ?? await signedIn(office),
    store: store ?? WhLocalStore.memory(),
    initialDestination: dest,
    lockEnabled: false,
    printer: printer ?? const NoPrinter(),
  ));
  await tester.pumpAndSettle();
}

Future<void> scan(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const Key('scan.field')), code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Future<void> typeQty(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.byKey(Key('qty.key.$d')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('qty.confirm')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('receive: scan -> keypad -> damaged -> send; both commands carry distinct idempotency keys', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.receive')));
    await tester.pumpAndSettle();
    expect(find.text('PO-0042'), findsOneWidget);
    await tester.tap(find.byKey(const Key('po.PO1')));
    await tester.pumpAndSettle();
    expect(find.text('4 / 12'), findsOneWidget, reason: 'progress = received / ordered from the office');

    await scan(tester, '6221234567890');
    await typeQty(tester, '6');
    await tester.tap(find.text('Damaged'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('line.add')));
    await tester.pumpAndSettle();
    expect(find.text('10 / 12'), findsOneWidget, reason: 'the draft counts towards progress');

    await tester.tap(find.byKey(const Key('receive.send')));
    await tester.pumpAndSettle();
    expect(office.posts.map((p) => p.path), ['/api/m1/wh/po/PO1/receipts', predicate<String>((p) => p.endsWith('/submit'))]);
    expect(office.posts.map((p) => p.key).toSet(), hasLength(2));
    final lines = office.posts.first.body['lines'] as List;
    expect((lines.single as Map)['quantity'], '6');
    expect((lines.single as Map)['condition'], 'damaged');
  });

  testWidgets('receive: an item that is not in the order is refused on the spot; expiry items need batch + date', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.receive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('po.PO1')));
    await tester.pumpAndSettle();
    await scan(tester, '0000000000');
    expect(find.byKey(const Key('receive.note')), findsOneWidget);

    await scan(tester, '6229999999999'); // yogurt: trackExpiry
    await typeQty(tester, '5');
    expect(tester.widget<FilledButton>(find.byKey(const Key('line.add'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('line.batch')), 'L7');
    await tester.enterText(find.byKey(const Key('line.expiry')), '2027-02-01');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('line.add'))).onPressed, isNotNull);
  });

  testWidgets('receive: without the office the list says so instead of showing stale orders', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    await openApp(tester, office);
    for (final t in office.transports) {
      t.failWith = const ApiError(kind: ApiErrorKind.network, code: 'network');
    }
    await tester.tap(find.byKey(const Key('doc.receive')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('po.error')), findsOneWidget);
    expect(find.textContaining('needs the office connection'), findsOneWidget);
  });

  testWidgets('blind count: items to count, no expected quantity, submit only when everything is counted', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.count')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task.T1')));
    await tester.pumpAndSettle();
    expect(find.text('Not counted'), findsNWidgets(2));
    expect(tester.widget<FilledButton>(find.byKey(const Key('count.send'))).onPressed, isNull);

    await scan(tester, '6221234567890');
    await typeQty(tester, '130');
    await tester.tap(find.byKey(const Key('count.item.6')));
    await tester.pumpAndSettle();
    await typeQty(tester, '5');
    expect(find.text('130'), findsOneWidget);
    expect(find.textContaining('137'), findsNothing, reason: 'the counter never sees the system quantity');
    await tester.tap(find.byKey(const Key('count.send')));
    await tester.pumpAndSettle();

    expect(office.posts, hasLength(2));
    final entries = (office.posts.first.body['entries'] as List).cast<Map>();
    expect(entries.map((e) => e['quantity']), ['130', '5']);
    for (final p in office.posts) {
      expect(p.body.keys.where((k) => RegExp('expected|variance').hasMatch(k)), isEmpty);
    }
  });

  testWidgets('lookup shows "hidden during a count" for a blind stock line', (tester) async {
    final office = FakeOffice()
      ..permissions = kClerk
      ..blindLookup = true;
    await openApp(tester, office, dest: 1);
    await tester.enterText(find.byKey(const Key('lookup.field')), '6221234567890');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Milk 1L'), findsOneWidget);
    expect(find.byKey(const Key('lookup.blind')), findsOneWidget);
    expect(find.text('Quantity hidden during a count'), findsOneWidget);
  });

  testWidgets('transfers: switched-off feature is explained; approved -> dispatch -> receive go through the outbox', (tester) async {
    final office = FakeOffice()
      ..permissions = kSupervisor
      ..transfersDisabled = true;
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.transfers')));
    await tester.pumpAndSettle();
    expect(find.textContaining('switched off at the office'), findsOneWidget);

    office.transfersDisabled = false;
    office.transfers['transfer-0001'] = {
      'state': 'approved',
      'lines': [
        {'lineGlobalId': 'tline-0001-a', 'productId': 5, 'quantity': '4', 'condition': 'ok'},
      ],
    };
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transfer-0001.dispatch')));
    await tester.pumpAndSettle();
    expect(office.posts.single.path, '/api/m1/wh/transfers/transfer-0001/dispatch');
    expect(office.transfers['transfer-0001']!['state'], 'in_transit');

    await tester.tap(find.byKey(const Key('transfer-0001.receive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qty.confirm'))); // initial = dispatched quantity
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qty.confirm'))); // damaged: initial 0
    await tester.pumpAndSettle();
    final receive = office.posts.last;
    expect(receive.path, endsWith('/receive'));
    expect(((receive.body['lines'] as List).single as Map)['received'], '4');
  });

  testWidgets('approvals: a voucher is approved with its own key; a count shows expected/counted to the approver only', (tester) async {
    final office = FakeOffice()..permissions = kSupervisor;
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.approvals')));
    await tester.pumpAndSettle();
    expect(find.text('damaged in aisle 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approval.voucher-0001')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(office.posts.single.path, '/api/m1/wh/vouchers/voucher-0001/approve');
    expect(office.posts.single.key.length, greaterThan(8));

    await tester.tap(find.byKey(const Key('approval.T1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Expected \u2066137\u2069'), findsOneWidget, reason: 'numbers are isolated LTR runs');
    await tester.tap(find.byKey(const Key('review.approve')));
    await tester.pumpAndSettle();
    expect(office.posts.last.path, '/api/m1/wh/counts/T1/approve');
  });

  testWidgets('a refusal from the office (four-eyes) is shown in words, not codes', (tester) async {
    final office = FakeOffice()
      ..permissions = kSupervisor
      ..rejectWith = 'self_approval';
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.approvals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approval.voucher-0001')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('someone else must'), findsOneWidget);
  });

  testWidgets('labels: with no printer the screen says so and never claims to have printed', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.labels')));
    await tester.pumpAndSettle();
    await scan(tester, '6221234567890');
    expect(find.byKey(const Key('label.barcode')), findsOneWidget);
    expect(find.byKey(const Key('label.noPrinter')), findsOneWidget);
    await tester.tap(find.byKey(const Key('label.print')));
    await tester.pumpAndSettle();
    expect(find.text('No printer connected. Choose a printer in Settings.'), findsWidgets);
    expect(find.text('The label was printed.'), findsNothing);
  });

  testWidgets('labels: with a printer the label goes out with the chosen number of copies', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    final printer = RecordingPrinter();
    await openApp(tester, office, printer: printer);
    await tester.tap(find.byKey(const Key('doc.labels')));
    await tester.pumpAndSettle();
    await scan(tester, '6221234567890');
    await tester.tap(find.byTooltip('More'));
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('label.print')));
    await tester.pumpAndSettle();
    expect(printer.printed, [('6221234567890', 3)]);
    expect(find.text('The label was printed.'), findsOneWidget);
  });

  testWidgets('labels: an unknown item shows the reason from the office', (tester) async {
    final office = FakeOffice()
      ..permissions = kClerk
      ..label = null;
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.labels')));
    await tester.pumpAndSettle();
    await scan(tester, '123');
    expect(find.byKey(const Key('label.error')), findsOneWidget);
    expect(find.text('Item not found.'), findsOneWidget);
  });

  Future<void> addMilk(WidgetTester tester, String qty) async {
    await tester.tap(find.byKey(const Key('doc.receive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('po.PO1')));
    await tester.pumpAndSettle();
    await scan(tester, '6221234567890');
    await typeQty(tester, qty);
    await tester.tap(find.byKey(const Key('line.add')));
    await tester.pumpAndSettle();
  }

  testWidgets('W2.3c: a receipt the office REFUSES (excess) is never shown as sent; the reason is', (tester) async {
    final office = FakeOffice()..permissions = kClerk; // milk: ordered 12, received 4 -> 9 would make 13
    await openApp(tester, office);
    await addMilk(tester, '9');
    await tester.tap(find.byKey(const Key('receive.send')));
    await tester.pumpAndSettle();
    expect(find.text('The receipt was sent to the office.'), findsNothing);
    expect(find.byKey(const Key('rejected.snack')), findsOneWidget);
    expect(find.textContaining('exceeds what was ordered'), findsOneWidget);
    expect(office.posts.map((p) => p.path), ['/api/m1/wh/po/PO1/receipts'], reason: 'the lines were accepted, the submit was refused and not applied');
  });

  testWidgets('W2.3c: when the LINES are refused the dependent submit is not sent and the receipt can be corrected', (tester) async {
    final office = FakeOffice()
      ..permissions = kClerk
      ..rejectWith = 'po_not_receivable';
    await openApp(tester, office);
    await addMilk(tester, '2');
    await tester.tap(find.byKey(const Key('receive.send')));
    await tester.pumpAndSettle();
    expect(find.text('The receipt was sent to the office.'), findsNothing);
    expect(find.textContaining('not open for receiving'), findsOneWidget);
    expect(office.posts, isEmpty, reason: 'nothing applied; the submit was not even sent');
    expect(tester.widget<FilledButton>(find.byKey(const Key('receive.send'))).onPressed, isNotNull,
        reason: 'the page is usable again');
  });

  testWidgets('W2.3c: accepted receipt says sent; an unreachable office says saved, not sent', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    await openApp(tester, office);
    await addMilk(tester, '2');
    await tester.tap(find.byKey(const Key('receive.send')));
    await tester.pumpAndSettle();
    expect(find.text('The receipt was sent to the office.'), findsOneWidget);
    expect(office.applied, 2);
  });

  testWidgets('a closed period at the office is shown as such for a dispatch', (tester) async {
    final office = FakeOffice()
      ..permissions = kSupervisor
      ..periodClosed = true;
    office.transfers['transfer-0001'] = {
      'state': 'approved',
      'lines': [
        {'lineGlobalId': 'tline-0001-a', 'productId': 5, 'quantity': '4', 'condition': 'ok'},
      ],
    };
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.transfers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transfer-0001.dispatch')));
    await tester.pumpAndSettle();
    expect(find.textContaining('accounting period is closed'), findsOneWidget);
    expect(find.text('Sent to the office.'), findsNothing);
  });

  testWidgets('WH-012: the damaged quantity of a transfer receipt is sent to the office', (tester) async {
    final office = FakeOffice()..permissions = kSupervisor;
    office.transfers['transfer-0001'] = {
      'state': 'in_transit',
      'lines': [
        {'lineGlobalId': 'tline-0001-a', 'productId': 5, 'quantity': '4', 'condition': 'ok'},
      ],
    };
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.transfers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transfer-0001.receive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qty.key.<'))); // 4 -> ''
    await tester.pump();
    await typeQty(tester, '3'); // received 3 good
    await typeQty(tester, '1'); // of which... damaged 1 (initial '0' -> '01' is shown as 1)
    final line = ((office.posts.last.body['lines'] as List).single as Map);
    expect(line['received'], '3');
    expect(double.parse('${line['damaged']}'), 1);
  });

  testWidgets('WH-010: a keeper without the approval right obtains a supervisor proof on the phone and attaches it', (tester) async {
    final office = FakeOffice()..permissions = [...kClerk, 'inventory_transfer'];
    office.transfers['transfer-0001'] = {
      'state': 'requested',
      'lines': [
        {'lineGlobalId': 'tline-0001-a', 'productId': 5, 'quantity': '4', 'condition': 'ok'},
      ],
    };
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.transfers')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transfer-0001.approve')), findsNothing, reason: 'no direct approve without the right');

    // wrong supervisor password: refused, nothing sent, still requested
    await tester.tap(find.byKey(const Key('transfer-0001.askApproval')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('proof.user')), 'sup');
    await tester.enterText(find.byKey(const Key('proof.password')), 'wrong');
    await tester.tap(find.byKey(const Key('proof.ok')));
    await tester.pumpAndSettle();
    expect(find.textContaining('credentials are wrong'), findsOneWidget);
    expect(office.proofsUsed, isEmpty);
    expect(office.transfers['transfer-0001']!['state'], 'requested');

    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byKey(const Key('transfer-0001.askApproval')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('proof.user')), 'sup');
    await tester.enterText(find.byKey(const Key('proof.password')), office.supervisorPassword);
    await tester.tap(find.byKey(const Key('proof.ok')));
    await tester.pumpAndSettle();
    expect(office.proofRequests.last, {'kind': 'transfer', 'ref': 'transfer-0001', 'action': 'approve', 'username': 'sup', 'password': 'sup-pw'});
    expect(office.proofsUsed.single, (path: '/api/m1/wh/transfers/transfer-0001/approve', proof: 'PROOF-transfer-0001-approve'));
    expect(office.transfers['transfer-0001']!['state'], 'approved');
  });
  testWidgets('transfers switched off: the request button is disabled and the page explains why', (tester) async {
    final office = FakeOffice()
      ..permissions = kSupervisor
      ..transfersDisabled = true;
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.transfers')));
    await tester.pumpAndSettle();
    expect(find.textContaining('switched off at the office'), findsOneWidget);
    final fab = tester.widget<FloatingActionButton>(find.byKey(const Key('transfer.new')));
    expect(fab.onPressed, isNull);
  });

  testWidgets('WH-011: a double tap on «send for approval» queues ONE voucher document', (tester) async {
    final office = FakeOffice()..permissions = kSupervisor;
    await openApp(tester, office);
    await tester.tap(find.byKey(const Key('doc.voucher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voucher.wh')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main store').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('voucher.reason')), 'broken');
    await scan(tester, '6221234567890');
    await typeQty(tester, '2');
    final send = find.byKey(const Key('voucher.send'));
    await tester.tap(send);
    await tester.tap(send, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(office.posts.where((p) => p.path == '/api/m1/wh/vouchers'), hasLength(1));
  });

  testWidgets('W5.4b: the office unpairs the phone -> the pairing screen says so and how many operations were discarded', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    final session = await signedIn(office);
    final store = WhLocalStore.memory();
    final outbox = WhOutbox(store, session, WhSyncState());
    await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v1'});
    await outbox.enqueue('voucher_create', '/api/m1/wh/vouchers', {'globalId': 'v2'});

    for (final tr in office.transports) {
      tr.failWith = const ApiError(kind: ApiErrorKind.network, code: 'network'); // offline: the 2 operations stay queued
    }
    setSurface(tester, kPhone);
    await tester.pumpWidget(PicPosWarehouseApp(
      key: UniqueKey(),
      settings: PicPosAppSettings(locale: const Locale('en'), themeMode: ThemeMode.light),
      session: session,
      store: store,
      initialDestination: 3,
      lockEnabled: false,
    ));
    await tester.pumpAndSettle();
    for (final tr in office.transports) {
      tr.failWith = null;
    }
    office.revoked = true;
    await tester.tap(find.byKey(const Key('outbox.send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding.unpaired')), findsOneWidget);
    expect(find.textContaining('unpaired from the office. 2 unsent operations were discarded'), findsOneWidget);
  });

  testWidgets('a clerk sees receive, count and labels, but not transfers, vouchers or approvals', (tester) async {
    final office = FakeOffice()..permissions = kClerk;
    await openApp(tester, office);
    for (final k in ['receive', 'count', 'labels']) {
      expect(find.byKey(Key('doc.$k')), findsOneWidget, reason: k);
    }
    for (final k in ['transfers', 'voucher', 'approvals']) {
      expect(find.byKey(Key('doc.$k')), findsNothing, reason: k);
    }
  });
}
