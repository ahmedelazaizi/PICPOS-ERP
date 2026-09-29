import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/lan_pairing_api_handler.dart';
import 'package:ural_erp/services/api/lan_pairing_service.dart';

void main() {
  late DateTime now;
  late LanPairingService pairing;

  setUp(() async {
    now = DateTime(2026, 1, 1);
    pairing = LanPairingService.forTesting(
      installSecret: 'per-install-secret-with-at-least-32-bytes',
      now: () => now,
      makeCode: () => 'ABCD2345',
    );
  });

  test('pairing code is one-time and expires after ten minutes', () async {
    final offer = pairing.issuePairingCode(
      serverHost: '192.168.1.2',
      port: 8080,
      serverFingerprint: 'fp',
    );
    expect((jsonDecode(offer.qrPayload) as Map)['pairingCode'], offer.code);
    final first = await pairing.pair(
      code: offer.code,
      deviceId: 'device-a',
      deviceName: 'Cashier A',
      ip: '10.0.0.2',
    );
    expect(first.status, LanPairingStatus.success);
    final second = await pairing.pair(
      code: offer.code,
      deviceId: 'device-b',
      deviceName: 'Cashier B',
      ip: '10.0.0.3',
    );
    expect(second.status, LanPairingStatus.invalidCode);

    final expired = pairing.issuePairingCode(
      serverHost: 'host',
      port: 8080,
    );
    now = now.add(const Duration(minutes: 11));
    final expiredResult = await pairing.pair(
      code: expired.code,
      deviceId: 'device-c',
      deviceName: 'Cashier C',
      ip: '10.0.0.4',
    );
    expect(expiredResult.status, LanPairingStatus.invalidCode);
  });

  test('pairing attempts are limited to five per IP per ten minutes', () async {
    for (var i = 0; i < 5; i++) {
      pairing.issuePairingCode(serverHost: 'host', port: 8080);
      final result = await pairing.pair(
        code: 'WRONG$i',
        deviceId: 'device-$i',
        deviceName: 'Cashier',
        ip: '10.0.0.5',
      );
      expect(result.status, LanPairingStatus.invalidCode);
    }
    pairing.issuePairingCode(serverHost: 'host', port: 8080);
    final limited = await pairing.pair(
      code: 'WRONG',
      deviceId: 'device-6',
      deviceName: 'Cashier',
      ip: '10.0.0.5',
    );
    expect(limited.status, LanPairingStatus.rateLimited);
  });

  test('derived token verifies and a revoked token is rejected', () async {
    final offer = pairing.issuePairingCode(serverHost: 'host', port: 8080);
    final result = await pairing.pair(
      code: offer.code,
      deviceId: 'device-a',
      deviceName: 'Cashier A',
      ip: '10.0.0.2',
    );
    expect(
      await pairing.verifyDeviceToken(
        token: result.token!,
        deviceId: 'device-a',
      ),
      isTrue,
    );
    await pairing.revoke('device-a');
    expect(
      await pairing.verifyDeviceToken(
        token: result.token!,
        deviceId: 'device-a',
      ),
      isFalse,
    );
  });

  group('legacy transition and API middleware', () {
    late AppDatabase db;
    late DateTime transitionNow;
    late LanPairingService dbPairing;

    setUp(() async {
      transitionNow = DateTime(2026, 1, 1);
      db = AppDatabase.forTesting();
      await db.ensureLanPairingSchema();
      dbPairing = LanPairingService.forTesting(
        db: db,
        installSecret: 'per-install-secret-with-at-least-32-bytes',
        now: () => transitionNow,
        makeCode: () => 'PAIR1234',
      );
      await dbPairing.initializeLegacyTransition();
      ApiAuthMiddleware.setToken('legacy-token');
      ApiAuthMiddleware.setPairingService(dbPairing);
      LanPairingApiHandler.setService(dbPairing);
    });

    tearDown(() async {
      ApiAuthMiddleware.clearPairingService();
      LanPairingApiHandler.clearService();
      ApiAuthMiddleware.clearToken();
      await db.close();
    });

    Future<Response> run(Request request) {
      final handler = ApiAuthMiddleware.createMiddleware()(
        (request) async => Response.ok(request.context['lanDeviceId'] ?? 'none'),
      );
      return Future.value(handler(request));
    }

    test('legacy token is accepted in-window and records an unpaired device',
        () async {
      final response = await run(Request(
        'GET',
        Uri.parse('http://localhost/api/settings'),
        headers: {
          'authorization': 'Bearer legacy-token',
          'x-device-id': 'legacy-device',
          'x-device-name': 'Old terminal',
        },
      ));
      expect(response.statusCode, 200);
      expect((await dbPairing.listUnpairedDevices()).single.deviceId,
          'legacy-device');
    });

    test('legacy token is rejected after the transition window', () async {
      transitionNow = transitionNow.add(const Duration(days: 31));
      final response = await run(Request(
        'GET',
        Uri.parse('http://localhost/api/settings'),
        headers: {'authorization': 'Bearer legacy-token'},
      ));
      expect(response.statusCode, 403);
      expect(await response.readAsString(), contains('إقران'));
    });

    test('API handler pipeline accepts paired and rejects unpaired token',
        () async {
      final offer = dbPairing.issuePairingCode(serverHost: 'host', port: 8080);
      final router = ApiHandler(db).buildRouter();
      final protected = ApiAuthMiddleware.createMiddleware()(router.call);
      final pairResponse = await protected(Request(
        'POST',
        Uri.parse('http://localhost/api/pair'),
        body: jsonEncode({
          'pairingCode': offer.code,
          'deviceId': 'paired-device',
          'deviceName': 'Paired terminal',
        }),
      ));
      expect(pairResponse.statusCode, 200);
      final token = (jsonDecode(await pairResponse.readAsString())
          as Map<String, dynamic>)['token'] as String;
      final pairedResponse = await protected(Request(
        'GET',
        Uri.parse('http://localhost/api/settings'),
        headers: {
          'authorization': 'Bearer $token',
          'x-device-id': 'paired-device',
        },
      ));
      expect(pairedResponse.statusCode, 200);
      final unpairedResponse = await protected(Request(
        'GET',
        Uri.parse('http://localhost/api/settings'),
        headers: {
          'authorization': 'Bearer $token',
          'x-device-id': 'other-device',
        },
      ));
      expect(unpairedResponse.statusCode, 403);
    });
  });
}
