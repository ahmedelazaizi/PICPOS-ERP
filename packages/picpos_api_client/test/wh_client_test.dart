import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_api_client/testing.dart';
import 'package:test/test.dart';

const _session = '{"user":{"id":7,"username":"clerk","displayName":"Ali","roleName":"clerk"},'
    '"device":{"id":"d1","kind":"warehouse","branchId":3,"branchName":"Main"},'
    '"permissions":["warehouse_mobile_access","inventory_view"],'
    '"warehouses":[{"id":1,"name":"A-main"}],"serverTime":1}';

void main() {
  late FakeTransport transport;
  late WarehouseLanClient client;

  setUp(() {
    transport = FakeTransport(TransportKind.lan, handler: (r) {
      switch (r.path) {
        case '/api/pair':
          return const ApiResponse(200, '{"token":"TKN","deviceId":"d1","branchId":3}');
        case '/api/auth/session':
          return const ApiResponse(200, '{"token":"SESS","userId":7,"expiresInMs":1000}');
        case '/api/m1/wh/session':
          return const ApiResponse(200, _session);
        case '/api/m1/wh/items':
          return const ApiResponse(
              200,
              '{"items":[{"id":1,"code":"P","barcode":"6","name":"Milk","stock":'
              '[{"warehouseId":1,"warehouse":"A-main","quantity":"12.0","reserved":"0.0"}]}]}');
      }
      return const ApiResponse(404, '{"error":"nf"}');
    });
    client = WarehouseLanClient(transport: transport, headers: const ApiHeaderBuilder(appVersion: 't'));
  });

  test('pair sends kind warehouse + code and keeps the device credentials', () async {
    final r = await client.pair(code: 'C1', deviceId: 'd1', deviceName: 'Phone');
    expect(r.branchId, 3);
    expect(transport.requests.single.body,
        {'pairingCode': 'C1', 'deviceId': 'd1', 'deviceName': 'Phone', 'deviceKind': 'warehouse'});
    expect(transport.requests.single.headers.containsKey('authorization'), isFalse);
    expect(client.credentials.isPaired, isTrue);
  });

  test('login uses the device bearer; session + items add the session token', () async {
    await client.pair(code: 'C1', deviceId: 'd1', deviceName: 'Phone');
    await client.login(username: 'clerk', password: 'pw');
    final login = transport.requests.last;
    expect(login.headers['authorization'], 'Bearer TKN');
    expect(login.headers.containsKey('x-session-token'), isFalse);

    final info = await client.session();
    expect(info.displayName, 'Ali');
    expect(info.branchId, 3);
    expect(info.warehouses.single.name, 'A-main');
    expect(info.can('warehouse_mobile_access'), isTrue);
    expect(info.isSupervisorLevel, isFalse);
    expect(transport.requests.last.headers['x-session-token'], 'SESS');
    expect(transport.requests.last.headers['x-device-id'], 'd1');

    final items = await client.itemsByBarcode('6');
    expect(items.single.stock.single.quantity, '12.0', reason: 'decimals stay strings');
    expect(transport.requests.last.query, {'barcode': '6'});
  });

  test('a session call before login is a programming error, not a request', () async {
    await client.pair(code: 'C1', deviceId: 'd1', deviceName: 'Phone');
    await expectLater(client.session(), throwsArgumentError);
    expect(transport.requests.length, 1);
  });

  test('401 device_revoked is recognised; signOut drops only the session token', () async {
    await client.pair(code: 'C1', deviceId: 'd1', deviceName: 'Phone');
    await client.login(username: 'u', password: 'p');
    client.signOut();
    expect(client.credentials.sessionToken, isNull);
    expect(client.credentials.isPaired, isTrue);
    expect(WarehouseLanClient.isRevoked(ApiError.fromResponse(401, '{"error":"device_revoked"}')), isTrue);
    expect(WarehouseLanClient.isRevoked(ApiError.fromResponse(401, '{"error":"Session no longer valid"}')), isFalse);
  });
}
