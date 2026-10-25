// WH-002 (review 2026-10-25): the accountant converts submitted phone receipts
// from the DESKTOP (service + desktop route), not through a phone.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_http.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_receipts_inbox.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, po;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
    po = await h.purchaseOrder(h.a1, {rice: 10}, status: 'confirmed');
    await h.call('POST', '/api/m1/wh/po/$po/receipts', user: h.clerk, body: {
      'globalId': 'doc-00000001',
      'lines': [
        {'lineGlobalId': 'line-0001-a', 'productId': rice, 'quantity': '4', 'condition': 'ok'},
        {'lineGlobalId': 'line-0002-a', 'productId': rice, 'quantity': '1', 'condition': 'damaged'},
      ],
    });
    await h.call('POST', '/api/m1/wh/receipts/doc-00000001/submit', user: h.clerk);
  });
  tearDown(() => h.dispose());

  test('the inbox lists the submitted receipt with order, supplier, warehouse and lines', () async {
    final list = await WhReceiptsInbox(h.db).list(h.admin);
    expect(list, hasLength(1));
    expect(list.single['globalId'], 'doc-00000001');
    expect(list.single['warehouse'], 'A-main');
    expect((list.single['lines'] as List), hasLength(2));
  });

  test('a user without purchases_create is refused by the service itself', () async {
    await expectLater(WhReceiptsInbox(h.db).list(h.clerk), throwsA(isA<WhError>().having((e) => e.code, 'code', 'permission_denied')));
    await expectLater(WhReceiptsInbox(h.db).convert('doc-00000001', h.clerk), throwsA(isA<WhError>()));
    expect(await h.db.select(h.db.purchaseInvoices).get(), isEmpty);
  });

  test('convert posts the invoice with accepted quantity only, marks the receipt posted, once', () async {
    final r = await WhReceiptsInbox(h.db).convert('doc-00000001', h.admin);
    expect(r['invoiceId'], isNotNull);
    expect(await h.stock(rice, h.a1), 4, reason: 'the damaged unit never enters good stock');
    expect(await WhReceiptsInbox(h.db).list(h.admin), isEmpty);
    await expectLater(WhReceiptsInbox(h.db).convert('doc-00000001', h.admin), throwsA(isA<WhError>()));
    expect(await h.stock(rice, h.a1), 4);
    expect(await h.db.select(h.db.purchaseInvoices).get(), hasLength(1));
  });

  group('desktop LAN route', () {
    Future<WhReply> desk(String method, String path, {required int user, String device = 'pos-1'}) async {
      final res = await h.app(Request(method, Uri.parse('http://lan$path'), headers: {
        'authorization': 'Bearer ${h.tokens[device]}',
        'x-device-id': device,
        'x-session-token': ApiSessionToken.mint(user),
        if (method != 'GET') 'x-idempotency-key': 'desk-key-0001',
      }));
      return WhReply(res.statusCode, await res.readAsString());
    }

    test('a paired DESKTOP (pos) device converts; a warehouse phone is refused device_scope', () async {
      await h.pairKind('pos-1', 'pos');
      final phone = await desk('POST', '/api/m1/wh/desk/receipts/doc-00000001/convert', user: h.admin, device: 'wh-A');
      expect(phone.status, 403);
      expect(phone.error, 'device_scope');

      final list = await desk('GET', '/api/m1/wh/desk/receipts', user: h.admin);
      expect(list.status, 200, reason: list.text);
      expect(((jsonDecode(list.text) as Map)['receipts'] as List), hasLength(1));

      final noPerm = await desk('POST', '/api/m1/wh/desk/receipts/doc-00000001/convert', user: h.clerk);
      expect(noPerm.status, 403);

      final ok = await desk('POST', '/api/m1/wh/desk/receipts/doc-00000001/convert', user: h.admin);
      expect(ok.status, 200, reason: ok.text);
      expect(await h.stock(rice, h.a1), 4);
      final replay = await desk('POST', '/api/m1/wh/desk/receipts/doc-00000001/convert', user: h.admin);
      expect(replay.json['replayed'], isTrue);
      expect(await h.stock(rice, h.a1), 4);
    });
  });
}
