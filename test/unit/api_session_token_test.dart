// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Track 1 · P1-8 — signed per-user session tokens (the CODEC).
// ═══════════════════════════════════════════════════════════════════════════
//
// [ApiSessionToken] replaces the forgeable, client-asserted `X-User-Id` header.
// The server mints an HMAC-signed `{uid, exp}` with a server-only key and hands
// the client an OPAQUE token; the client can neither read the key nor forge an
// arbitrary uid. These tests exercise the pure codec in isolation:
//   • mint → verify roundtrip,
//   • every fail-closed path (wrong key, tampered payload/sig, malformed,
//     expired, null, unset key),
//   • the exact expiry boundary,
//   • distinct uids ⇒ distinct tokens.
//
// FULLY DETERMINISTIC: `nowMs` is injected everywhere — no wall-clock reliance.
// The signing key is set via `setKeyForTesting` in setUp and dropped in
// tearDown so no static state leaks between tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/api/api_session_token.dart';

void main() {
  // A fixed, arbitrary epoch-ms anchor. Every mint/verify pins its clock to
  // this (± offsets) so the suite never depends on DateTime.now().
  const int t0 = 1700000000000;

  /// Flip the FIRST character of the payload segment (before the '.'), leaving
  /// the signature untouched → the recomputed signature no longer matches.
  String tamperPayload(String token) {
    final dot = token.indexOf('.');
    final payload = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    final flipped = (payload[0] == 'A' ? 'B' : 'A') + payload.substring(1);
    return '$flipped.$sig';
  }

  /// Flip the FIRST character of the signature segment (after the '.'),
  /// leaving the payload untouched → constant-time compare fails.
  String tamperSig(String token) {
    final dot = token.indexOf('.');
    final payload = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    final flipped = (sig[0] == 'A' ? 'B' : 'A') + sig.substring(1);
    return '$payload.$flipped';
  }

  group('ApiSessionToken codec (Spec 151 P1-8)', () {
    setUp(() => ApiSessionToken.setKeyForTesting('k1'));
    tearDown(() => ApiSessionToken.clearKey());

    test('mint → verify roundtrip recovers the same uid', () {
      final token = ApiSessionToken.mint(42, nowMs: t0);
      expect(ApiSessionToken.verify(token, nowMs: t0 + 1000), 42);
    });

    test('two different uids mint different tokens; each verifies back', () {
      final t1 = ApiSessionToken.mint(7, nowMs: t0);
      final t2 = ApiSessionToken.mint(99, nowMs: t0);
      expect(t1, isNot(equals(t2)),
          reason: 'distinct uids must not collide to the same token');
      expect(ApiSessionToken.verify(t1, nowMs: t0 + 1000), 7);
      expect(ApiSessionToken.verify(t2, nowMs: t0 + 1000), 99);
    });

    test('token signed under a DIFFERENT key → null (no cross-key forgery)', () {
      final token = ApiSessionToken.mint(1, nowMs: t0);
      ApiSessionToken.setKeyForTesting('k2'); // attacker key ≠ server key
      expect(ApiSessionToken.verify(token, nowMs: t0 + 1000), isNull,
          reason: 'a token minted under another key must not verify');
    });

    test('tampered payload → null', () {
      final token = ApiSessionToken.mint(5, nowMs: t0);
      expect(ApiSessionToken.verify(tamperPayload(token), nowMs: t0 + 1000),
          isNull);
    });

    test('tampered signature → null', () {
      final token = ApiSessionToken.mint(5, nowMs: t0);
      expect(
          ApiSessionToken.verify(tamperSig(token), nowMs: t0 + 1000), isNull);
    });

    test('malformed tokens → null', () {
      for (final bad in ['', '.', 'no-dot-here', 'abc.', '.xyz']) {
        expect(ApiSessionToken.verify(bad, nowMs: t0 + 1000), isNull,
            reason: 'malformed "$bad" must fail closed');
      }
    });

    test('null token → null', () {
      expect(ApiSessionToken.verify(null, nowMs: t0 + 1000), isNull);
    });

    test('expired token → null', () {
      final token = ApiSessionToken.mint(1, nowMs: t0);
      final wellPast = t0 + ApiSessionToken.ttlMs + 1;
      expect(ApiSessionToken.verify(token, nowMs: wellPast), isNull,
          reason: 'a token past its exp must not verify');
    });

    test('verify honors the expiry boundary exactly', () {
      final token = ApiSessionToken.mint(3, nowMs: t0);
      // exp = t0 + ttlMs. Valid while now < exp; rejected once now >= exp.
      expect(ApiSessionToken.verify(token, nowMs: t0 + ApiSessionToken.ttlMs - 1),
          3,
          reason: 'one ms before expiry is still valid');
      expect(
          ApiSessionToken.verify(token, nowMs: t0 + ApiSessionToken.ttlMs), isNull,
          reason: 'at exactly exp the token is expired (now >= exp)');
    });

    test('verify fails closed when the signing key is unset', () {
      final token = ApiSessionToken.mint(1, nowMs: t0);
      ApiSessionToken.clearKey();
      expect(ApiSessionToken.verify(token, nowMs: t0 + 1000), isNull,
          reason: 'no key derived → server issues no identity (fail closed)');
    });

    test('mint throws StateError when the signing key is unset', () {
      ApiSessionToken.clearKey();
      expect(() => ApiSessionToken.mint(1, nowMs: t0), throwsStateError);
    });

    test('isReady reflects whether the key is derived', () {
      expect(ApiSessionToken.isReady, isTrue); // set in setUp
      ApiSessionToken.clearKey();
      expect(ApiSessionToken.isReady, isFalse);
    });
  });
}
