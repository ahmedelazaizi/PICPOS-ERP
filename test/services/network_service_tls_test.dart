import 'dart:io';

import 'package:picpos_erp/services/network_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NetworkService.instance.loadSettings();
  });

  group('NetworkService TLS configuration', () {
    test('TLS disabled by default', () async {
      expect(NetworkService.instance.tlsEnabled, isFalse);
      expect(NetworkService.instance.httpScheme, 'http');
      expect(NetworkService.instance.wsScheme, 'ws');
    });

    test('configureTls persists values', () async {
      await NetworkService.instance.configureTls(
        enabled: true,
        certPath: '/tmp/cert.pem',
        keyPath: '/tmp/key.pem',
      );
      expect(NetworkService.instance.tlsEnabled, isTrue);
      expect(NetworkService.instance.tlsCertPath, '/tmp/cert.pem');
      expect(NetworkService.instance.tlsKeyPath, '/tmp/key.pem');
    });

    test('validateTlsConfig returns null when disabled', () async {
      await NetworkService.instance.configureTls(enabled: false);
      expect(NetworkService.instance.validateTlsConfig(), isNull);
    });

    test('validateTlsConfig rejects missing cert path', () async {
      await NetworkService.instance.configureTls(
        enabled: true,
        certPath: null,
        keyPath: '/tmp/key.pem',
      );
      final err = NetworkService.instance.validateTlsConfig();
      expect(err, isNotNull);
      expect(err, contains('شهادة'));
    });

    test('validateTlsConfig rejects non-existent files', () async {
      await NetworkService.instance.configureTls(
        enabled: true,
        certPath: '/nonexistent/cert.pem',
        keyPath: '/nonexistent/key.pem',
      );
      final err = NetworkService.instance.validateTlsConfig();
      expect(err, isNotNull);
      expect(err, contains('غير موجود'));
    });

    test('validateTlsConfig passes when files exist', () async {
      final tmpCert = File('${Directory.systemTemp.path}/tls_test_cert.pem')
        ..writeAsStringSync('-----BEGIN CERTIFICATE-----\nfake\n');
      final tmpKey = File('${Directory.systemTemp.path}/tls_test_key.pem')
        ..writeAsStringSync('-----BEGIN PRIVATE KEY-----\nfake\n');
      try {
        await NetworkService.instance.configureTls(
          enabled: true,
          certPath: tmpCert.path,
          keyPath: tmpKey.path,
        );
        expect(NetworkService.instance.validateTlsConfig(), isNull);
      } finally {
        if (tmpCert.existsSync()) tmpCert.deleteSync();
        if (tmpKey.existsSync()) tmpKey.deleteSync();
      }
    });

    test('httpScheme reflects active TLS state', () {
      // Before server start, active TLS is false regardless of config
      expect(NetworkService.instance.isServerUsingTls, isFalse);
      expect(NetworkService.instance.httpScheme, 'http');
      expect(NetworkService.instance.wsScheme, 'ws');
    });
  });
}
