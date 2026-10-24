// SEC-007 — the pairing flow pins the host certificate fingerprint carried in
// the pairing payload (QR / clipboard JSON) before the first request, and
// never downgrades to HTTP after a certificate rejection.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/api/lan_pairing_client.dart';
import 'package:picpos_erp/services/api/lan_pairing_input.dart';
import 'package:picpos_erp/services/device_identity_service.dart';
import 'package:picpos_erp/services/lan_tls/lan_tls_manager.dart';
import 'package:picpos_erp/services/tls_trust.dart';

class _Mem implements LanTlsStorage {
  final m = <String, String>{};
  @override
  Future<String?> read(String k) async => m[k];
  @override
  Future<void> write(String k, String v) async => m[k] = v;
  @override
  Future<void> delete(String k) async => m.remove(k);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null); // real sockets, not flutter_test's 400 stub

  group('LanPairingInput.parse', () {
    test('bare code is upper-cased and has no fingerprint', () {
      final i = LanPairingInput.parse(' abcd2345 ');
      expect(i.code, 'ABCD2345');
      expect(i.hasFingerprint, isFalse);
    });

    test('QR payload yields code + fingerprint + host + port', () {
      final fp = 'ab' * 32;
      final i = LanPairingInput.parse(jsonEncode({
        'serverHost': '192.168.1.5',
        'port': 8080,
        'pairingCode': 'zzzz9999',
        'serverFingerprint': fp,
      }));
      expect(i.code, 'ZZZZ9999');
      expect(i.fingerprint, fp);
      expect(i.host, '192.168.1.5');
      expect(i.port, 8080);
    });

    test('a malformed fingerprint is ignored (never pins garbage)', () {
      final i = LanPairingInput.parse(jsonEncode({'pairingCode': 'A', 'serverFingerprint': 'xyz'}));
      expect(i.hasFingerprint, isFalse);
    });

    test('broken JSON falls back to a plain code', () {
      expect(LanPairingInput.parse('{oops').code, '{OOPS');
    });
  });

  group('LanPairingClient.pair over real TLS', () {
    late HttpServer server;
    late String fingerprint;

    setUp(() async {
      TlsTrust.clearAllForTest();
      DeviceIdentityService.instance.adoptForPairing('test-device');
      final tls = await resolveLanServerTls(
        mode: LanTransportMode.secureSelfSigned,
        manager: LanTlsManager(_Mem()),
      );
      fingerprint = tls.fingerprint!;
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, tls.context!);
      server.listen((req) async {
        await utf8.decoder.bind(req).join();
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'token': 'device-token'}));
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('payload with the right fingerprint pairs and pins (HTTPS only)', () async {
      final result = await LanPairingClient.pair(
        address: '127.0.0.1',
        port: server.port,
        code: jsonEncode({'pairingCode': 'ABCD2345', 'serverFingerprint': fingerprint}),
      );
      expect(result['success'], isTrue, reason: '$result');
      expect(result['secure'], isTrue);
      expect(TlsTrust.pinFor('127.0.0.1', server.port), fingerprint);
    });

    test('payload with a WRONG fingerprint is rejected and not downgraded to HTTP', () async {
      final result = await LanPairingClient.pair(
        address: '127.0.0.1',
        port: server.port,
        code: jsonEncode({'pairingCode': 'ABCD2345', 'serverFingerprint': 'cd' * 32}),
      );
      expect(result['success'], isFalse);
      expect(result['error'].toString(), contains('TLS'));
    });

    test('a bare code uses trust-on-first-use and pins what the host presented', () async {
      final result = await LanPairingClient.pair(
        address: '127.0.0.1',
        port: server.port,
        code: 'ABCD2345',
      );
      expect(result['success'], isTrue, reason: '$result');
      expect(TlsTrust.pinFor('127.0.0.1', server.port), fingerprint);
    });
  });
}
