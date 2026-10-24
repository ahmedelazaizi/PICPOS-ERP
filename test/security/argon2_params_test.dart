// SEC-010 — Argon2id cost at the OWASP minimum (m>=19 MiB, t>=2) with
// transparent upgrade of older hashes and a bounded parameter parser.

import 'dart:convert';

import 'package:cryptography/cryptography.dart' as c;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/security_service.dart';

Future<String> _phc(String password, {required int m, required int t, required int p}) async {
  final salt = List<int>.generate(16, (i) => i + 1);
  final key = await c.Argon2id(parallelism: p, memory: m, iterations: t, hashLength: 32)
      .deriveKey(secretKey: c.SecretKey(utf8.encode(password)), nonce: salt);
  return '\$argon2id\$v=19\$m=$m,t=$t,p=$p\$${base64.encode(salt)}\$${base64.encode(await key.extractBytes())}';
}

void main() {
  test('new hashes are OWASP-minimum: m>=19456, t>=2', () async {
    final h = await SecurityService.hashPasswordArgon2('Correct-Horse-1');
    final prm = SecurityService.parseArgon2Params(h)!;
    expect(prm.m, greaterThanOrEqualTo(19456));
    expect(prm.t, greaterThanOrEqualTo(2));
    expect(SecurityService.argon2NeedsRehash(h), isFalse);
    expect(h, contains('m=19456,t=2,p=1'));
    expect((await SecurityService.verifyPasswordFull('Correct-Horse-1', '', h)).verified, isTrue);
    expect((await SecurityService.verifyPasswordFull('wrong', '', h)).verified, isFalse);
  });

  test('a pre-SEC-010 hash (m=4096,t=3,p=1) still verifies and is flagged for rehash', () async {
    final old = await _phc('Old-Pass-1', m: 4096, t: 3, p: 1);
    final ok = await SecurityService.verifyPasswordFull('Old-Pass-1', '', old);
    expect(ok.verified, isTrue);
    expect(ok.needsRehash, isTrue);
    final bad = await SecurityService.verifyPasswordFull('nope', '', old);
    expect(bad.verified, isFalse);
    expect(bad.needsRehash, isFalse, reason: 'a wrong password must never trigger a rehash write');
  });

  test('verification honours the parameters stored in the hash (not the constants)', () async {
    final custom = await _phc('x', m: 8192, t: 2, p: 1);
    expect((await SecurityService.verifyPasswordFull('x', '', custom)).verified, isTrue);
  });

  test('hostile parameters in a synced hash are bounded (no memory bomb)', () async {
    const bomb = r'$argon2id$v=19$m=4000000000,t=1000,p=64$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    expect(SecurityService.parseArgon2Params(bomb), isNull);
    final sw = Stopwatch()..start();
    expect(await SecurityService.verifyArgon2('x', bomb), isFalse);
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('parser rejects malformed descriptors', () {
    expect(SecurityService.parseArgon2Params('garbage'), isNull);
    expect(SecurityService.parseArgon2Params(r'$argon2id$v=19$m=abc,t=2,p=1$s$h'), isNull);
    expect(SecurityService.parseArgon2Params(r'$argon2id$v=19$m=19456,t=2$s$h'), isNull);
  });
}
