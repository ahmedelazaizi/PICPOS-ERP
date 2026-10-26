// WH-030 (owner decision 2026-10-26): the user who dispatched a transfer does
// not confirm its receipt (four-eyes on the movement of goods). Nothing moves
// on the refused attempt; another user receives normally.
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice;

  Future<WhReply> post(String path, int user, [Object? body]) => h.call('POST', path, user: user, body: body ?? {});

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE', cost: 10);
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await h.db.setSetting('wh_staged_transfers_enabled', 'true');
    await post('/api/m1/wh/transfers', h.keeper, {
      'globalId': 'transfer-dist-1', 'fromWarehouseId': h.a1, 'toWarehouseId': h.a2,
      'lines': [{'lineGlobalId': 'tline-dist-1', 'productId': rice, 'quantity': '4'}],
    });
    await post('/api/m1/wh/transfers/transfer-dist-1/approve', h.supervisor);
    expect((await post('/api/m1/wh/transfers/transfer-dist-1/dispatch', h.keeper)).status, 200);
  });
  tearDown(() => h.dispose());

  final lines = {'lines': [{'lineGlobalId': 'tline-dist-1', 'received': '4', 'damaged': '0'}]};

  test('the dispatcher cannot receive his own transfer; the destination stays untouched', () async {
    final r = await post('/api/m1/wh/transfers/transfer-dist-1/receive', h.keeper, lines);
    expect(r.status, 403, reason: r.text);
    expect(r.error, 'self_approval');
    expect(await h.stock(rice, h.a2), 0);
    expect(await h.stock(rice, h.a1), 6);
    final row = await h.db.customSelect("SELECT state FROM wh_mobile_docs WHERE global_id = 'transfer-dist-1'").getSingle();
    expect(row.data['state'], 'in_transit');
  });

  test('another user receives it', () async {
    final r = await post('/api/m1/wh/transfers/transfer-dist-1/receive', h.supervisor2, lines);
    expect(r.status, 200, reason: r.text);
    expect(await h.stock(rice, h.a2), 4);
  });
}