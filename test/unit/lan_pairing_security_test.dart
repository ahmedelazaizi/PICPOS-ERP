import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/lan_pairing_api_handler.dart';
import 'package:ural_erp/services/api/lan_pairing_service.dart';

class _SocketConnection implements HttpConnectionInfo {
  _SocketConnection(String address) : remoteAddress = InternetAddress(address);

  @override
  final InternetAddress remoteAddress;
  @override
  int get remotePort => 45678;
  @override
  int get localPort => 8080;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secret = 'per-install-secret-with-at-least-32-bytes';
  const injection = "' OR 1=1 --";

  test('pairing limits by socket address despite forged forwarding and Host', () async {
    final pairing = LanPairingService.forTesting(
      installSecret: secret,
      makeCode: () => 'ABCD2345',
    );
    LanPairingApiHandler.setService(pairing);
    addTearDown(LanPairingApiHandler.clearService);
    pairing.issuePairingCode(serverHost: 'server', port: 8080);

    Future<int> attempt(String remoteIp, String forgedIp) async {
      final response = await LanPairingApiHandler.pair(Request(
        'POST',
        Uri.parse('http://localhost/api/pair'),
        headers: {
          'content-type': 'application/json',
          'x-forwarded-for': forgedIp,
          'x-real-ip': forgedIp,
          'host': forgedIp,
        },
        context: {'shelf.io.connection_info': _SocketConnection(remoteIp)},
        body: jsonEncode({'code': 'WRONG', 'deviceId': 'device', 'deviceName': 'name'}),
      ));
      return response.statusCode;
    }

    for (var attemptNumber = 0; attemptNumber < 5; attemptNumber++) {
      expect(await attempt('10.0.0.5', '192.0.2.$attemptNumber'), 401);
    }
    expect(await attempt('10.0.0.5', '192.0.2.99'), 429);
    expect(await attempt('10.0.0.6', '192.0.2.0'), 401);
  });

  test('SQL-looking pairing identifiers and names remain data', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.ensureLanPairingSchema();
    final pairing = LanPairingService.forTesting(
      db: db,
      installSecret: secret,
      makeCode: () => 'ABCD2345',
    );
    final offer = pairing.issuePairingCode(serverHost: 'server', port: 8080);
    expect(
      (await pairing.pair(
        code: injection,
        deviceId: 'attacker',
        deviceName: injection,
        ip: injection,
      )).status,
      LanPairingStatus.invalidCode,
    );

    expect(
      (await pairing.pair(
        code: offer.code,
        deviceId: 'device-$injection',
        deviceName: injection,
        ip: injection,
      )).status,
      LanPairingStatus.success,
    );
    final safeOffer = pairing.issuePairingCode(serverHost: 'server', port: 8080);
    expect(
      (await pairing.pair(
        code: safeOffer.code,
        deviceId: 'safe-device',
        deviceName: 'Safe',
        ip: '10.0.0.2',
      )).status,
      LanPairingStatus.success,
    );

    await pairing.recordSeen(
      deviceId: 'device-$injection', name: injection, ip: injection,
    );
    await pairing.recordLegacyDevice(
      deviceId: 'legacy-$injection', name: injection, ip: injection,
    );
    final devices = await pairing.listDevices();
    expect(devices, hasLength(3));
    final injectedDevice = devices.singleWhere(
      (device) => device.deviceId == 'device-$injection',
    );
    expect(injectedDevice.name, injection);
    expect(injectedDevice.ip, injection);
    expect(
      devices.singleWhere((device) => device.deviceId == 'legacy-$injection').pairedAt,
      isNull,
    );

    await pairing.revoke(injection);
    expect((await pairing.listDevices()).every((device) => !device.revoked), isTrue);
    await pairing.revoke('device-$injection');
    final afterRevoke = await pairing.listDevices();
    expect(afterRevoke.singleWhere((device) => device.deviceId == 'safe-device').revoked,
        isFalse);
    expect(afterRevoke.singleWhere((device) => device.deviceId == 'device-$injection').revoked,
        isTrue);
  });
}
