import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_api_client/testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeTransport transport;
  late WarehouseLanClient client;

  ApiResponse reply(ApiRequest r) {
    if (r.path.endsWith('/tasks')) {
      return const ApiResponse(
          200,
          '{"tasks":[{"ref":"T1","warehouseId":1,"warehouse":"A","items":'
          '[{"productId":5,"code":"P","name":"Milk","barcode":"6"}]}]}');
    }
    if (r.path == '/api/m1/wh/po') {
      return const ApiResponse(
          200,
          '{"orders":[{"ref":"PO1","id":1,"orderNumber":"PO-1","status":"sent","warehouseId":1,"items":'
          '[{"itemId":9,"productId":5,"name":"Milk","barcode":"6","trackExpiry":true,"ordered":"12","received":"4"}]}]}');
    }
    if (r.path.endsWith('/submit')) return const ApiResponse(200, '{"receipt":{"globalId":"R1","kind":"po_receipt","state":"submitted","version":2,"warehouseId":1,"lines":[]},"replayed":true}');
    return const ApiResponse(200, '{}');
  }

  setUp(() async {
    transport = FakeTransport(TransportKind.lan, handler: reply);
    client = WarehouseLanClient(
      transport: transport,
      headers: const ApiHeaderBuilder(appVersion: 't'),
      credentials: const ApiCredentials(deviceId: 'd1', deviceToken: 'TKN', sessionToken: 'SESS'),
    );
  });

  test('every write carries x-idempotency-key = the command id; reads do not', () async {
    await client.saveReceiptLines(
      poRef: 'PO1',
      receiptGlobalId: 'R1',
      commandId: 'cmd-1',
      lines: const [WhReceiptLineInput(lineGlobalId: 'L1', productId: 5, quantity: '3')],
    );
    expect(transport.requests.last.headers['x-idempotency-key'], 'cmd-1');
    expect(transport.requests.last.path, '/api/m1/wh/po/PO1/receipts');
    expect((transport.requests.last.body as Map)['lines'], [
      {'lineGlobalId': 'L1', 'productId': 5, 'quantity': '3', 'condition': 'ok'},
    ]);
    await client.purchaseOrders();
    expect(transport.requests.last.headers.containsKey('x-idempotency-key'), isFalse);
  });

  test('a manager approval proof travels as x-approval-proof', () async {
    await client.voucherAction('V1', 'approve', commandId: 'cmd-2', approvalProof: 'PROOF');
    expect(transport.requests.last.headers['x-approval-proof'], 'PROOF');
    expect(transport.requests.last.path, '/api/m1/wh/vouchers/V1/approve');
    await client.transferAction('T1', 'dispatch', commandId: 'cmd-3');
    expect(transport.requests.last.headers.containsKey('x-approval-proof'), isFalse);
  });

  test('purchase orders parse with ordered / received / remaining', () async {
    final po = (await client.purchaseOrders()).single;
    expect(po.items.single.ordered, '12');
    expect(po.items.single.remaining, 8);
    expect(po.items.single.trackExpiry, isTrue);
  });

  test('a replayed answer is flagged', () async {
    final r = await client.submitReceipt('R1', commandId: 'cmd-4');
    expect(r.replayed, isTrue);
    expect(r.doc!.state, 'submitted');
  });

  test('count tasks parse into items without any quantity (the type has none)', () async {
    final t = (await client.countTasks()).single;
    expect(t.ref, 'T1');
    expect(t.items.single.name, 'Milk');
  });

  test('a blind stock line carries no quantity', () {
    final s = WhStockLine.fromJson(const {'warehouseId': 1, 'warehouse': 'A', 'blind': true});
    expect(s.blind, isTrue);
    expect(s.quantity, isEmpty);
  });
}
