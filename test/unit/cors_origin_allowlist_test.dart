// A-SEC-5 (M-3): the embedded server used `Access-Control-Allow-Origin: *`
// alongside `Authorization`, letting any website's JS read the LAN API from a
// victim's browser. CORS is now reflected only for trusted origins (loopback +
// private LAN ranges). Non-browser desktop clients send no Origin and are
// unaffected (they don't do CORS).

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/network_service.dart';

void main() {
  group('A-SEC-5 CORS origin allowlist', () {
    test('loopback origins are allowed', () {
      expect(NetworkService.isAllowedCorsOrigin('http://localhost:8080'), isTrue);
      expect(NetworkService.isAllowedCorsOrigin('http://127.0.0.1:8080'), isTrue);
    });

    test('private LAN origins are allowed', () {
      expect(NetworkService.isAllowedCorsOrigin('http://192.168.1.10:8080'), isTrue);
      expect(NetworkService.isAllowedCorsOrigin('http://10.0.0.5'), isTrue);
      expect(NetworkService.isAllowedCorsOrigin('http://172.16.0.1'), isTrue);
      expect(NetworkService.isAllowedCorsOrigin('http://172.31.255.254'), isTrue);
    });

    test('public and near-miss origins are rejected', () {
      expect(NetworkService.isAllowedCorsOrigin('https://evil.com'), isFalse);
      expect(NetworkService.isAllowedCorsOrigin('http://8.8.8.8'), isFalse);
      expect(NetworkService.isAllowedCorsOrigin('http://172.15.0.1'), isFalse);
      expect(NetworkService.isAllowedCorsOrigin('http://172.32.0.1'), isFalse);
      expect(NetworkService.isAllowedCorsOrigin(''), isFalse);
      expect(NetworkService.isAllowedCorsOrigin('not a url'), isFalse);
    });

    test('F-SEC-1: prefix-spoof DNS names are rejected (not IP literals)', () {
      // Attacker-registrable public hostnames whose label begins with a private
      // prefix must NOT be treated as trusted LAN.
      expect(NetworkService.isAllowedCorsOrigin('http://10.evil.com'), isFalse);
      expect(NetworkService.isAllowedCorsOrigin('http://10.attacker.io'), isFalse);
      expect(NetworkService.isAllowedCorsOrigin('http://192.168.evil.com'), isFalse);
      expect(NetworkService.isAllowedCorsOrigin('http://172.16.evil.com'), isFalse);
      expect(NetworkService.isAllowedCorsOrigin('http://192.168.1.10.evil.com'), isFalse);
      expect(NetworkService.isAllowedCorsOrigin('http://999.1.1.1'), isFalse);
    });
  });
}
