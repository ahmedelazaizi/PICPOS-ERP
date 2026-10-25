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
  Locale locale = const Locale('en'),
  ThemeMode mode = ThemeMode.light,
  Size size = kPhone,
}) async {
  setSurface(tester, size);
  await tester.pumpWidget(PicPosWarehouseApp(
    key: UniqueKey(),
    settings: PicPosAppSettings(locale: locale, themeMode: mode),
    session: await signedIn(office),
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
    expect(find.textContaining('Expected 137'), findsOneWidget);
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
