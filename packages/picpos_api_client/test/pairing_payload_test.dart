import 'dart:convert';

import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:test/test.dart';

final _fp = 'ab' * 32;

String _v2({String kind = 'warehouse', String? fp, String url = 'https://192.168.1.5:8443', int? exp, int? branch = 3}) =>
    jsonEncode({'v': 2, 'kind': kind, 'url': url, 'code': 'pair1234', 'exp': exp, 'fp': fp ?? _fp, 'branchId': branch});

Matcher _reason(String why) => throwsA(isA<FormatException>().having((e) => e.message, 'message', why));

void main() {
  test('v2: parses kind, https url, upper-cased code, fingerprint, branch and expiry', () {
    final exp = DateTime(2030).millisecondsSinceEpoch;
    final p = PairingPayload.parse(_v2(exp: exp));
    expect(p.version, 2);
    expect(p.kind, PairingKind.warehouse);
    expect(p.url, Uri.parse('https://192.168.1.5:8443'));
    expect(p.code, 'PAIR1234');
    expect(p.fingerprint, _fp);
    expect(p.branchId, 3);
    expect(p.isExpired(DateTime(2029)), isFalse);
    expect(p.isExpired(DateTime(2031)), isTrue);
  });

  test('v2: AB:CD colon fingerprints are normalised', () {
    final colon = List.generate(32, (_) => 'AB').join(':');
    expect(PairingPayload.parse(_v2(fp: colon)).fingerprint, _fp);
  });

  test('refuses a payload without a valid fingerprint or over plain http', () {
    expect(() => PairingPayload.parse(_v2(fp: 'nothex')), _reason('no_fingerprint'));
    expect(() => PairingPayload.parse(_v2(url: 'http://192.168.1.5:8080')), _reason('not_https'));
  });

  test('refuses junk, wrong shapes and unknown kinds', () {
    expect(() => PairingPayload.parse('not json'), _reason('not_json'));
    expect(() => PairingPayload.parse('[1]'), _reason('not_object'));
    expect(() => PairingPayload.parse(jsonEncode({'v': 2, 'kind': 'warehouse', 'url': '', 'code': 'X', 'fp': _fp})),
        _reason('incomplete'));
    expect(() => PairingPayload.parse(_v2(kind: 'toaster')), _reason('bad_kind'));
  });

  test('v1 payload still parses as kind lan; v1 without fingerprint is refused', () {
    final p = PairingPayload.parse(
        jsonEncode({'serverHost': 'h', 'port': 8443, 'pairingCode': 'ab12', 'serverFingerprint': _fp}));
    expect(p.version, 1);
    expect(p.kind, PairingKind.lan);
    expect(p.code, 'AB12');
    expect(p.url, Uri.parse('https://h:8443'));
    expect(
        () => PairingPayload.parse(
            jsonEncode({'serverHost': 'h', 'port': 1, 'pairingCode': 'x', 'serverFingerprint': null})),
        _reason('no_fingerprint'));
  });

  test('the desktop dual-format payload parses as v2', () {
    final dual = jsonEncode({
      'v': 2, 'kind': 'warehouse', 'url': 'https://h:1', 'code': 'C1', 'exp': 1, 'fp': _fp, 'branchId': 2,
      'serverHost': 'h', 'port': 1, 'pairingCode': 'C1', 'serverFingerprint': _fp,
    });
    expect(PairingPayload.parse(dual).version, 2);
  });
}
