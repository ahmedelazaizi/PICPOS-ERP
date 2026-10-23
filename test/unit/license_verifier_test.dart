import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/license_service.dart';
import 'package:picpos_erp/core/utils/license_encoding.dart';

void main() {
  test('accepts a valid signed key for its machine', () async {
    final fixture = await _LicenseFixture.create('MACHINE-A');
    expect(await fixture.verifier.verify(fixture.key, 'MACHINE-A'), isTrue);
  });

  test('rejects a key issued for another machine', () async {
    final fixture = await _LicenseFixture.create('MACHINE-A');
    expect(await fixture.verifier.verify(fixture.key, 'MACHINE-B'), isFalse);
  });

  test('rejects a tampered payload', () async {
    final fixture = await _LicenseFixture.create('MACHINE-A');
    final separator = fixture.key.indexOf('.');
    final tampered = '${fixture.key.substring(0, 4)}X'
        '${fixture.key.substring(5, separator)}${fixture.key.substring(separator)}';
    expect(await fixture.verifier.verify(tampered, 'MACHINE-A'), isFalse);
  });

  test('rejects legacy keys', () async {
    final fixture = await _LicenseFixture.create('MACHINE-A');
    expect(
      await fixture.verifier.verify('ABCD-EFGH-IJKL-MNOP', 'MACHINE-A'),
      isFalse,
    );
  });

  test('tool-compatible unpadded encoding round-trips', () async {
    final fixture = await _LicenseFixture.create('MACHINE-A');
    final parts = fixture.key.split('.');
    expect(parts.every((part) => !part.contains('=')), isTrue);
    expect(await fixture.verifier.verify(fixture.key, 'MACHINE-A'), isTrue);
  });

  test('placeholder public key fails closed', () async {
    final fixture = await _LicenseFixture.create('MACHINE-A');
    expect(
      await LicenseVerifier('REPLACE_WITH_ED25519_PUBLIC_KEY')
          .verify(fixture.key, 'MACHINE-A'),
      isFalse,
    );
  });
}

class _LicenseFixture {
  final LicenseVerifier verifier;
  final String key;

  const _LicenseFixture(this.verifier, this.key);

  static Future<_LicenseFixture> create(String machineId) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final payload = utf8.encode(jsonEncode({
      'v': 2,
      'machineId': machineId,
      'issuedAt': '2026-01-01T00:00:00.000Z',
    }));
    final signature = await algorithm.sign(payload, keyPair: keyPair);
    final encoded =
        'PP2-${encodeUnpaddedBase64Url(payload)}.${encodeUnpaddedBase64Url(signature.bytes)}';
    return _LicenseFixture(
      LicenseVerifier(encodeUnpaddedBase64Url(publicKey.bytes)),
      encoded,
    );
  }
}
