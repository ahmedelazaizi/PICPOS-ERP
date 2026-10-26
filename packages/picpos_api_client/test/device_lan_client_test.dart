import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_api_client/testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeTransport transport;
  late DeviceLanClient client;

  setUp(() {
    transport = FakeTransport(TransportKind.lan, handler: (r) {
      switch (r.path) {
        case '/api/pair':
          return const ApiResponse(200,
              '{"token":"TKN","deviceId":"d1","branchId":3,"branchCode":"B1","terminalCode":"B1-T01"}');
        case '/api/auth/session':
          return const ApiResponse(
              200, '{"token":"SESS","userId":7,"expiresInMs":1000}');
      }
      return const ApiResponse(404, '{"error":"nf"}');
    });
    client = DeviceLanClient(
        transport: transport,
        headers: const ApiHeaderBuilder(appVersion: 't'),
        kind: 'pos');
  });

  test('pair echoes the kind it was built for, sends no bearer and keeps '
      'the per-device credentials + terminal', () async {
    final r = await client.pair(code: 'C1', deviceId: 'd1', deviceName: 'Tab');
    expect(r.branchId, 3);
    expect(r.terminalCode, 'B1-T01');
    expect(transport.requests.single.body, {
      'pairingCode': 'C1',
      'deviceId': 'd1',
      'deviceName': 'Tab',
      'deviceKind': 'pos',
    });
    expect(transport.requests.single.headers.containsKey('authorization'), isFalse);
    expect(client.credentials.deviceToken, 'TKN');
  });

  test('a branch device whose pairing answer has no branch is refused', () async {
    final t = FakeTransport(TransportKind.lan,
        handler: (_) => const ApiResponse(200, '{"token":"T","deviceId":"d"}'));
    final c = DeviceLanClient(
        transport: t, headers: const ApiHeaderBuilder(appVersion: 't'), kind: 'pos');
    await expectLater(
        c.pair(code: 'C', deviceId: 'd', deviceName: 'n'), throwsFormatException);
    expect(c.credentials.isPaired, isFalse);
  });

  test('login uses the device bearer, keeps the session and returns the user',
      () async {
    await client.pair(code: 'C1', deviceId: 'd1', deviceName: 'Tab');
    final uid = await client.login(username: 'cashier', password: 'pw');
    expect(uid, 7);
    expect(transport.requests.last.headers['authorization'], 'Bearer TKN');
    expect(client.credentials.sessionToken, 'SESS');
    client.signOut();
    expect(client.credentials.sessionToken, isNull);
    expect(client.credentials.deviceToken, 'TKN');
  });

  test('a 403 pos_access_denied surfaces as a forbidden ApiError with its code',
      () async {
    final t = FakeTransport(TransportKind.lan, handler: (r) {
      if (r.path == '/api/auth/session') {
        return const ApiResponse(
            403, '{"error":"pos_access_denied","code":"pos_access_denied"}');
      }
      return const ApiResponse(200, '{"token":"T","deviceId":"d","branchId":1}');
    });
    final c = DeviceLanClient(
        transport: t, headers: const ApiHeaderBuilder(appVersion: 't'), kind: 'pos');
    await c.pair(code: 'C', deviceId: 'd', deviceName: 'n');
    try {
      await c.login(username: 'u', password: 'p');
      fail('expected ApiError');
    } on ApiError catch (e) {
      expect(e.kind, ApiErrorKind.forbidden);
      expect(e.code, 'pos_access_denied');
    }
  });

  test('revocation is recognised', () {
    expect(
        DeviceLanClient.isRevoked(
            const ApiError(kind: ApiErrorKind.deviceRevoked, status: 401, code: 'device_revoked')),
        isTrue);
    expect(DeviceLanClient.isRevoked(Exception('x')), isFalse);
  });
}
