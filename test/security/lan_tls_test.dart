// SEC-007 — LAN transport is TLS by default with a managed self-signed
// certificate and fingerprint pinning (TOFU). Includes REAL TLS handshakes on
// loopback: pinned client succeeds, wrong pin and an unpinned strict client fail.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/lan_tls/lan_tls_manager.dart';
import 'package:picpos_erp/services/lan_tls/x509_self_signed.dart';
import 'package:picpos_erp/services/tls_trust.dart';

class _MemoryStorage implements LanTlsStorage {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

Future<HttpServer> _serve(SecurityContext ctx) async {
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
  server.listen((req) async {
    req.response
      ..statusCode = 200
      ..write('ok');
    await req.response.close();
  });
  return server;
}

void main() {
  setUp(TlsTrust.clearAllForTest);

  group('self-signed certificate generator', () {
    test('produces a loadable ECDSA P-256 cert whose fingerprint is sha256(DER)', () {
      final c = generateSelfSignedCertificate(ipAddresses: ['192.168.1.20']);
      expect(c.certificatePem, startsWith('-----BEGIN CERTIFICATE-----'));
      expect(c.privateKeyPem, startsWith('-----BEGIN PRIVATE KEY-----'));
      final der = certificateDerFromPem(c.certificatePem)!;
      expect(c.fingerprintSha256, sha256.convert(der).toString());
      expect(c.fingerprintSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      // loads into a SecurityContext (BoringSSL parses cert + PKCS#8 key)
      SecurityContext()
        ..useCertificateChainBytes(utf8.encode(c.certificatePem))
        ..usePrivateKeyBytes(utf8.encode(c.privateKeyPem));
      final notAfter = certificateNotAfter(der)!;
      expect(notAfter.difference(DateTime.now()).inDays, greaterThan(3600));
    });

    test('every generation is a fresh key (fingerprints differ)', () {
      expect(generateSelfSignedCertificate().fingerprintSha256,
          isNot(generateSelfSignedCertificate().fingerprintSha256));
    });
  });

  group('mode resolution: secure by default, explicit legacy option', () {
    test('nothing stored -> managed self-signed TLS', () {
      expect(
        resolveLanTransportMode(legacyCustomTlsEnabled: false, customCertConfigured: false),
        LanTransportMode.secureSelfSigned,
      );
    });

    test('an old install that saved "network_tls_enabled=false" is upgraded to secure', () {
      // saveSettings() always wrote tls=false for installs that never used TLS.
      expect(
        resolveLanTransportMode(stored: null, legacyCustomTlsEnabled: false, customCertConfigured: false),
        LanTransportMode.secureSelfSigned,
      );
    });

    test('previously configured custom certificate keeps working', () {
      expect(
        resolveLanTransportMode(legacyCustomTlsEnabled: true, customCertConfigured: true),
        LanTransportMode.customCertificate,
      );
      // ...but not when the paths vanished: never silently downgrade to HTTP.
      expect(
        resolveLanTransportMode(legacyCustomTlsEnabled: true, customCertConfigured: false),
        LanTransportMode.secureSelfSigned,
      );
    });

    test('legacy HTTP only when the operator explicitly chose it', () {
      expect(
        resolveLanTransportMode(
          stored: 'legacy_http',
          legacyCustomTlsEnabled: true,
          customCertConfigured: true,
        ),
        LanTransportMode.legacyHttp,
      );
      expect(LanTransportMode.legacyHttp.usesTls, isFalse);
      expect(LanTransportMode.secureSelfSigned.usesTls, isTrue);
    });
  });

  group('LanTlsManager (secure storage only)', () {
    test('first run generates and stores; second run reuses the same identity', () async {
      final storage = _MemoryStorage();
      final m = LanTlsManager(storage);
      final first = await m.loadOrCreate();
      expect(first.newlyGenerated, isTrue);
      expect(storage.data.keys, containsAll([LanTlsManager.certStorageKey, LanTlsManager.keyStorageKey]));
      final second = await LanTlsManager(storage).loadOrCreate();
      expect(second.newlyGenerated, isFalse);
      expect(second.fingerprint, first.fingerprint);
      expect(await m.storedFingerprint(), first.fingerprint);
    });

    test('rotate replaces the identity (clients must re-pin)', () async {
      final storage = _MemoryStorage();
      final m = LanTlsManager(storage);
      final a = await m.loadOrCreate();
      final b = await m.rotate();
      expect(b.fingerprint, isNot(a.fingerprint));
      expect((await m.loadOrCreate()).fingerprint, b.fingerprint);
    });

    test('a corrupted stored pair is regenerated instead of crashing the server', () async {
      final storage = _MemoryStorage()
        ..data[LanTlsManager.certStorageKey] = 'garbage'
        ..data[LanTlsManager.keyStorageKey] = 'garbage';
      final material = await LanTlsManager(storage).loadOrCreate();
      expect(material.newlyGenerated, isTrue);
    });
  });

  group('resolveLanServerTls', () {
    test('legacy -> plain HTTP; secure -> TLS; custom with a bad file -> error (no silent downgrade)', () async {
      final manager = LanTlsManager(_MemoryStorage());
      expect((await resolveLanServerTls(mode: LanTransportMode.legacyHttp, manager: manager)).isTls, isFalse);

      final secure = await resolveLanServerTls(mode: LanTransportMode.secureSelfSigned, manager: manager);
      expect(secure.isTls, isTrue);
      expect(secure.fingerprint, hasLength(64));

      final bad = await resolveLanServerTls(
        mode: LanTransportMode.customCertificate,
        manager: manager,
        customCertPath: '/nonexistent/cert.pem',
        customKeyPath: '/nonexistent/key.pem',
      );
      expect(bad.error, isNotNull);
      expect(bad.isTls, isFalse);
    });
  });

  group('real TLS handshake with fingerprint pinning', () {
    late HttpServer server;
    late String fingerprint;

    setUp(() async {
      final tls = await resolveLanServerTls(
        mode: LanTransportMode.secureSelfSigned,
        manager: LanTlsManager(_MemoryStorage()),
      );
      fingerprint = tls.fingerprint!;
      server = await _serve(tls.context!);
    });
    tearDown(() => server.close(force: true));

    Future<String> get(HttpClient c) async {
      final req = await c.getUrl(Uri.parse('https://127.0.0.1:${server.port}/'));
      final res = await req.close();
      return res.transform(utf8.decoder).join();
    }

    test('a client pinned to the QR fingerprint connects', () async {
      await TlsTrust.pin('127.0.0.1', server.port, fingerprint);
      final client = TlsTrust.ioClient();
      expect(await get(client), 'ok');
      client.close(force: true);
    });

    test('MITM: a client pinned to a different fingerprint is rejected', () async {
      await TlsTrust.pin('127.0.0.1', server.port, 'a' * 64);
      final client = TlsTrust.ioClient();
      await expectLater(get(client), throwsA(isA<HandshakeException>()));
      client.close(force: true);
    });

    test('a strict client without a pin rejects the self-signed certificate', () async {
      final client = HttpClient(); // no badCertificateCallback = system trust only
      await expectLater(get(client), throwsA(isA<HandshakeException>()));
      client.close(force: true);
    });
  });
}
