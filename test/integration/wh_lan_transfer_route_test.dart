// WH-028: `POST /api/inventory/transfer` (LAN desktops / mirrors / replays) used
// to call adjustStock twice: a negative quantity reversed the direction and an
// empty source went negative. It now runs the desktop pipeline (`transferStock`).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await h.pairKind('pos-1', 'pos');
  });
  tearDown(() => h.dispose());

  Future<WhReply> transfer(int user, Map<String, Object?> body, {String device = 'pos-1'}) async {
    final res = await h.app(Request('POST', Uri.parse('http://lan/api/inventory/transfer'),
        headers: {
          'authorization': 'Bearer ${h.tokens[device]}',
          'x-device-id': device,
          'x-session-token': ApiSessionToken.mint(user),
          'content-type': 'application/json',
        },
        body: jsonEncode(body)));
    return WhReply(res.statusCode, await res.readAsString());
  }

  Map<String, Object?> body(num qty, {String? gid}) => {
        'fromWarehouseId': h.a1,
        'toWarehouseId': h.a2,
        'globalId': ?gid,
        'items': [
          {'productId': rice, 'quantity': qty},
        ],
      };

  test('a negative quantity no longer reverses the transfer', () async {
    final r = await transfer(h.admin, body(-3));
    expect(r.status, 400, reason: r.text);
    expect(await h.stock(rice, h.a1), 10);
    expect(await h.stock(rice, h.a2), 0);
  });

  test('stock never goes negative, even with enable_negative_sales', () async {
    await h.db.setSetting('enable_negative_sales', 'true');
    final r = await transfer(h.admin, body(11));
    expect(r.status, 409, reason: r.text);
    expect(await h.stock(rice, h.a1), 10);
    expect(await h.stock(rice, h.a2), 0);
  });

  test('a valid transfer moves the stock once and a replay with the same globalId does not repeat it', () async {
    final ok = await transfer(h.admin, body(4, gid: 'trf-gid-0001'));
    expect(ok.status, 200, reason: ok.text);
    expect(await h.stock(rice, h.a1), 6);
    expect(await h.stock(rice, h.a2), 4);
    final replay = await transfer(h.admin, body(4, gid: 'trf-gid-0001'));
    expect(replay.status, 200);
    expect(await h.stock(rice, h.a1), 6);
    final lines = await h.db.select(h.db.journalEntryLines).get();
    expect(lines.fold<double>(0, (s, l) => s + l.debit), closeTo(lines.fold<double>(0, (s, l) => s + l.credit), 0.01));
  });

  test('the same warehouse on both sides is refused', () async {
    final r = await transfer(h.admin, {...body(1), 'toWarehouseId': h.a1});
    expect(r.status, 400);
  });

  test('without inventory_transfer the call is refused; a warehouse phone never reaches the route', () async {
    expect((await transfer(h.clerk, body(1))).status, 403);
    final phone = await transfer(h.admin, body(1), device: 'wh-A');
    expect(phone.status, 403);
    expect(phone.error, 'device_scope');
    expect(await h.stock(rice, h.a1), 10);
  });
}
