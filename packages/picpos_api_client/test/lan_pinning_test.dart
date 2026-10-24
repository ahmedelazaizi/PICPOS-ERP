import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:test/test.dart';

class _FakeCert implements X509Certificate {
  _FakeCert(this._der);
  final Uint8List _der;
  @override
  Uint8List get der => _der;
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final der = Uint8List.fromList(List<int>.generate(300, (i) => i % 251));
  final fp = sha256.convert(der).toString();

  group('pinned certificate callback (SEC-007)', () {
    test('accepts exactly the pinned certificate', () {
      final cb = pinnedCertificateCallback(fp);
      expect(cb(_FakeCert(der), '192.168.1.10', 8080), isTrue);
    });

    test('rejects any other certificate (man in the middle)', () {
      final cb = pinnedCertificateCallback(fp);
      final other = Uint8List.fromList([...der, 1]);
      expect(cb(_FakeCert(other), '192.168.1.10', 8080), isFalse);
    });

    test('accepts the colon / upper-case form of the same fingerprint', () {
      final colon = [for (var i = 0; i < fp.length; i += 2) fp.substring(i, i + 2)].join(':').toUpperCase();
      expect(pinnedCertificateCallback(colon)(_FakeCert(der), 'h', 1), isTrue);
    });

    test('there is no "no pin => accept" mode: a malformed pin throws', () {
      expect(() => pinnedCertificateCallback(''), throwsArgumentError);
      expect(() => pinnedCertificateCallback('abc'), throwsArgumentError);
      expect(() => createPinnedLanClient('zz'), throwsArgumentError);
    });

    test('createPinnedLanClient builds a client for a valid pin', () {
      final c = createPinnedLanClient(fp);
      c.close();
    });
  });

  group('LanPairingPayload.parse', () {
    String payload({String? fingerprint}) => jsonEncode({
          'serverHost': '192.168.1.10',
          'port': 8080,
          'pairingCode': 'abcd2345',
          'serverFingerprint': fingerprint,
        });

    test('reads host, port, code and the pinned fingerprint', () {
      final p = LanPairingPayload.parse(payload(fingerprint: fp));
      expect(p.baseUri.toString(), 'https://192.168.1.10:8080');
      expect(p.pairingCode, 'ABCD2345');
      expect(p.fingerprint, fp);
      expect(const UrlPolicy(allowDevCleartext: false).allows(p.baseUri), isTrue);
    });

    test('REFUSES a payload without a fingerprint (legacy HTTP host): no cleartext pairing', () {
      expect(() => LanPairingPayload.parse(payload()), throwsFormatException);
      expect(() => LanPairingPayload.parse(payload(fingerprint: 'not-hex')), throwsFormatException);
    });

    test('rejects broken or incomplete payloads', () {
      expect(() => LanPairingPayload.parse('nope'), throwsFormatException);
      expect(() => LanPairingPayload.parse('[]'), throwsFormatException);
      expect(() => LanPairingPayload.parse(jsonEncode({'serverFingerprint': fp})), throwsFormatException);
    });

    test('release URL policy still forbids cleartext to the LAN host', () {
      expect(UrlPolicy.release.allows(Uri.parse('http://192.168.1.10:8080')), isFalse);
    });
  });
}
