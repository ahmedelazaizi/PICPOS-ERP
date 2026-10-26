// NEW-02 SQLite twin: two requests with the SAME X-Idempotency-Key racing
// (a phone retry while the first is still running) both answer 200 and the
// second is flagged `replayed`; one document exists. Never a 409.
import 'package:flutter_test/flutter_test.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice;
  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
  });
  tearDown(() => h.dispose());

  test('same key twice at once: 200 + 200(replayed), one document', () async {
    final po = await h.purchaseOrder(h.a1, {rice: 12}, status: 'confirmed');
    final body = {
      'globalId': 'doc-race-0001',
      'lines': [
        {'lineGlobalId': 'line-race-1', 'productId': rice, 'quantity': '6', 'condition': 'ok'}
      ],
    };
    final r = await Future.wait([
      h.call('POST', '/api/m1/wh/po/$po/receipts', user: h.clerk, body: body, key: 'race-key-00001'),
      h.call('POST', '/api/m1/wh/po/$po/receipts', user: h.clerk, body: body, key: 'race-key-00001'),
    ]);
    expect(r.map((x) => x.status), [200, 200], reason: r.map((x) => x.text).join(' | '));
    expect(r.where((x) => x.json['replayed'] == true), hasLength(1));
    final docs = await h.db.customSelect("SELECT id FROM wh_mobile_docs WHERE global_id = 'doc-race-0001'").get();
    expect(docs, hasLength(1));
  });
}
