import 'dart:io';

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';

/// SEC-014: the cloud server can terminate TLS itself (TLS_CERT_FILE /
/// TLS_KEY_FILE) or bind loopback only behind a reverse proxy (BIND_ADDRESS).
void main() {
  group('CloudConfig TLS', () {
    test('defaults: no TLS, all IPv4 interfaces (docker compose compatible)', () {
      final c = CloudConfig({});
      expect(c.tlsEnabled, isFalse);
      expect(c.tlsProblem, isNull);
      expect(c.bindAddress, InternetAddress.anyIPv4);
    });

    test('both files set -> TLS enabled; the context loader uses them', () {
      final c = CloudConfig({'TLS_CERT_FILE': '/c.pem', 'TLS_KEY_FILE': '/k.pem', 'TLS_KEY_PASSWORD': 'pw'});
      expect(c.tlsEnabled, isTrue);
      expect(c.tlsCertFile, '/c.pem');
      expect(c.tlsKeyFile, '/k.pem');
      expect(c.tlsKeyPassword, 'pw');
    });

    test('exactly one of cert/key is a startup error (never a silent HTTP fallback)', () {
      expect(CloudConfig({'TLS_CERT_FILE': '/c.pem'}).tlsProblem, contains('TLS_KEY_FILE'));
      expect(CloudConfig({'TLS_KEY_FILE': '/k.pem'}).tlsProblem, contains('TLS_CERT_FILE'));
    });

    test('unreadable files are reported by buildSecurityContext, not ignored', () {
      final c = CloudConfig({'TLS_CERT_FILE': '/nonexistent/c.pem', 'TLS_KEY_FILE': '/nonexistent/k.pem'});
      expect(() => c.buildSecurityContext(), throwsA(anything));
    });

    test('BIND_ADDRESS accepts an IP; garbage is a startup problem', () {
      expect(CloudConfig({'BIND_ADDRESS': '127.0.0.1'}).bindAddress, InternetAddress.loopbackIPv4);
      expect(CloudConfig({'BIND_ADDRESS': 'not-an-ip'}).tlsProblem, contains('BIND_ADDRESS'));
    });

    test('plain HTTP on a non-loopback address is flagged for a warning', () {
      expect(CloudConfig({}).plainHttpExposed, isTrue);
      expect(CloudConfig({'BIND_ADDRESS': '127.0.0.1'}).plainHttpExposed, isFalse);
      expect(CloudConfig({'TLS_CERT_FILE': 'c', 'TLS_KEY_FILE': 'k'}).plainHttpExposed, isFalse);
    });
  });
}
