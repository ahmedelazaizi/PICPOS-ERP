// WH-012 on the SERVER: the damaged part of a transfer receipt is recorded with
// the receipt (not folded into the shortage or into good stock silently): the
// destination gets only what was physically received, a pending damage voucher
// carries the damaged quantity, and the journal stays balanced.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE', cost: 10);
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 10, type: 'purchase', unitCost: 10);
    await h.db.setSetting('wh_staged_transfers_enabled', 'true');
  });
  tearDown(() => h.dispose());

  Future<WhReply> post(String path, int user, [Object? body]) => h.call('POST', path, user: user, body: body ?? {});

  test('receive 3 ok + 1 damaged of 5 dispatched: stock, short, damage voucher and journal are exact', () async {
    final req = await post('/api/m1/wh/transfers', h.keeper, {
      'globalId': 'transfer-dmg-1',
      'fromWarehouseId': h.a1,
      'toWarehouseId': h.a2,
      'lines': [
        {'lineGlobalId': 'tline-dmg-1', 'productId': rice, 'quantity': '5'},
      ],
    });
    expect(req.status, 200, reason: req.text);
    expect((await post('/api/m1/wh/transfers/transfer-dmg-1/approve', h.supervisor)).status, 200);
    final disp = await post('/api/m1/wh/transfers/transfer-dmg-1/dispatch', h.keeper);
    expect(disp.status, 200, reason: disp.text);
    expect(await h.stock(rice, h.a1), 5, reason: '5 left the source');

    final rcv = await post('/api/m1/wh/transfers/transfer-dmg-1/receive', h.supervisor2, {
      'lines': [
        {'lineGlobalId': 'tline-dmg-1', 'received': '3', 'damaged': '1'},
      ],
    });
    expect(rcv.status, 200, reason: rcv.text);
    expect((rcv.json['doc'] as Map)['state'], 'received_short', reason: '5 dispatched, 4 accounted for: 1 short');

    // the 3 good + 1 damaged unit are in the destination until the damage voucher is approved
    expect(await h.stock(rice, h.a2), 4);
    final vouchers = await h.db.customSelect(
        "SELECT d.state AS state, l.qty_base AS q FROM wh_mobile_docs d JOIN wh_mobile_doc_lines l ON l.doc_id = d.id "
        "WHERE d.kind = 'voucher'").get();
    expect(vouchers, hasLength(1));
    expect(vouchers.single.data['state'], 'pending');
    expect((vouchers.single.data['q'] as num).toDouble(), 1.0);

    final lines = await h.db.select(h.db.journalEntryLines).get();
    expect(lines.fold<double>(0, (s, l) => s + l.debit), closeTo(lines.fold<double>(0, (s, l) => s + l.credit), 0.01));

    // the damage voucher, approved by someone else, takes the unit out of stock
    final gid = (await h.db.customSelect("SELECT global_id AS g FROM wh_mobile_docs WHERE kind = 'voucher'").getSingle()).data['g'] as String;
    final ap = await post('/api/m1/wh/vouchers/$gid/approve', h.supervisor);
    expect(ap.status, 200, reason: ap.text);
    expect(await h.stock(rice, h.a2), 3, reason: 'only the 3 good units remain');
  });

  test('received + damaged above the dispatched quantity is refused 409 over_receipt and nothing moves', () async {
    await post('/api/m1/wh/transfers', h.keeper, {
      'globalId': 'transfer-dmg-2',
      'fromWarehouseId': h.a1,
      'toWarehouseId': h.a2,
      'lines': [
        {'lineGlobalId': 'tline-dmg-2', 'productId': rice, 'quantity': '5'},
      ],
    });
    await post('/api/m1/wh/transfers/transfer-dmg-2/approve', h.supervisor);
    await post('/api/m1/wh/transfers/transfer-dmg-2/dispatch', h.keeper);
    final rcv = await post('/api/m1/wh/transfers/transfer-dmg-2/receive', h.supervisor2, {
      'lines': [
        {'lineGlobalId': 'tline-dmg-2', 'received': '4', 'damaged': '2'},
      ],
    });
    expect(rcv.status, 409, reason: rcv.text);
    expect(rcv.error, 'over_receipt');
    expect(await h.stock(rice, h.a2), 0);
  });
}