// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Track 1 · P1-8 — signed session tokens, END-TO-END forgery closure.
// ═══════════════════════════════════════════════════════════════════════════
//
// Proves the whole identity path holds together against a forger who already
// owns the shared bearer token:
//
//   1. `POST /api/auth/session` mints a token ONLY after a real credential
//      check (username+password OR cardCode); bad creds ⇒ 401, no token.
//   2. The token minted by the endpoint verifies back to the right uid.
//   3. Through the REAL `ApiAuthMiddleware`, only a valid `X-Session-Token`
//      stamps an identity on the request. No token, a garbage token, and the
//      legacy `X-User-Id` header all yield NO identity (uid null) — so a bearer
//      holder can neither forge `uid=1` nor omit identity to read cross-branch.
//
// Users are seeded via `db.createUser` (real Argon2id hash), so
// `authenticateUser` / `authenticateByCardCode` verify them exactly as in prod.
// Runs against SQLite in-memory.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_auth_handler.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late int aliceId; // username+password login
  late int bobId; // cardCode login

  const bearer = 'bearer-xyz';

  setUp(() async {
    db = AppDatabase.forTesting();
    // Both the TRANSPORT gate (bearer) and the IDENTITY key (session) must be
    // live for the middleware+endpoint to function.
    ApiAuthMiddleware.setToken(bearer);
    ApiSessionToken.deriveKey('seed');

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير', isSystemRole: const Value(false)),
        );
    aliceId = await db.createUser(
      username: 'alice',
      password: 'pw-correct',
      displayName: 'Alice',
      roleId: roleId,
    );
    bobId = await db.createUser(
      username: 'bob',
      password: 'pw-bob',
      displayName: 'Bob',
      roleId: roleId,
      cardCode: 'CARD-XYZ',
    );
  });

  tearDown(() async {
    ApiAuthMiddleware.clearToken();
    ApiSessionToken.clearKey();
    await db.close();
  });

  // ── The issue endpoint ────────────────────────────────────────────────────

  Future<shelf.Response> issue(Map<String, dynamic> body) {
    return ApiAuthHandler(db, const {}).issueSession(shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/auth/session'),
      body: jsonEncode(body),
    ));
  }

  Future<Map<String, dynamic>> issueJson(Map<String, dynamic> body) async {
    final resp = await issue(body);
    return jsonDecode(await resp.readAsString()) as Map<String, dynamic>;
  }

  test('valid username+password issues a token that verifies back to the uid',
      () async {
    final resp = await issue({'username': 'alice', 'password': 'pw-correct'});
    expect(resp.statusCode, 200);
    final body =
        jsonDecode(await resp.readAsString()) as Map<String, dynamic>;
    final token = body['token'] as String?;
    expect(token, isNotNull);
    expect(token, isNotEmpty);
    expect(body['userId'], aliceId);
    expect(body['expiresInMs'], ApiSessionToken.ttlMs);
    // The issued token is a REAL, verifiable session for Alice.
    expect(ApiSessionToken.verify(token), aliceId);
  });

  test('wrong password → 401 and no token', () async {
    final resp = await issue({'username': 'alice', 'password': 'WRONG'});
    expect(resp.statusCode, 401);
    final body =
        jsonDecode(await resp.readAsString()) as Map<String, dynamic>;
    expect(body.containsKey('token'), isFalse,
        reason: 'a rejected credential must never receive a session token');
  });

  test('cardCode login issues a token for the card holder', () async {
    final body = await issueJson({'cardCode': 'CARD-XYZ'});
    expect(body['userId'], bobId);
    final token = body['token'] as String;
    expect(ApiSessionToken.verify(token), bobId);
  });

  test('unknown cardCode → 401, no token', () async {
    final resp = await issue({'cardCode': 'NO-SUCH-CARD'});
    expect(resp.statusCode, 401);
  });

  test('empty body (no usable credential) → 400', () async {
    final resp = await issue(<String, dynamic>{});
    expect(resp.statusCode, 400);
  });

  test('session auth not ready (key undrived) → 503', () async {
    ApiSessionToken.clearKey(); // simulate a not-fully-started server
    final resp = await issue({'username': 'alice', 'password': 'pw-correct'});
    expect(resp.statusCode, 503);
    // Next test's setUp re-derives the key.
  });

  // ── Forgery closure through the real middleware ─────────────────────────────

  /// Drive a request (bearer already valid) through the REAL middleware and
  /// return the identity the inner handler observes.
  Future<int?> userIdSeenByInner(Map<String, String> headers) async {
    int? seen;
    final handler = ApiAuthMiddleware.createMiddleware()((req) async {
      seen = ApiUserCtx.userIdOf(req);
      return shelf.Response.ok('inner');
    });
    await handler(shelf.Request(
      'GET',
      Uri.parse('http://localhost/api/products'),
      headers: {'authorization': 'Bearer $bearer', ...headers},
    ));
    return seen;
  }

  test('a valid X-Session-Token stamps the acting uid on the request',
      () async {
    final token = ApiSessionToken.mint(1);
    expect(await userIdSeenByInner({'x-session-token': token}), 1,
        reason: 'the middleware must derive uid=1 from the signed token');
  });

  test('NO X-Session-Token → inner handler sees no identity (null)', () async {
    expect(await userIdSeenByInner(const {}), isNull,
        reason: 'without a signed token the request carries no identity');
  });

  test('a forged/garbage X-Session-Token → null (verify rejects it)', () async {
    expect(await userIdSeenByInner({'x-session-token': 'not-a-real-token'}),
        isNull,
        reason: 'an unsigned/garbage token buys the forger nothing');
  });

  test('legacy X-User-Id header is IGNORED — never trusted for identity',
      () async {
    expect(await userIdSeenByInner({'x-user-id': '1'}), isNull,
        reason: 'the old forgeable header must no longer stamp an identity');
  });

  // ── P1-8b timing-defense sanity ─────────────────────────────────────────────

  test(
      'Spec 151 P1-8b — authenticateUser on a NON-EXISTENT user returns null '
      'without throwing (the dummy-Argon2 timing-defense path runs)',
      () async {
    // The "no matching user" branch now runs a THROWAWAY Argon2id verify so it
    // costs ~the same as the wrong-password path, closing the timing side channel
    // that let a caller enumerate valid usernames. This asserts the safety
    // invariant only (a pure timing assertion would be flaky): the dummy-verify
    // path is exercised, returns null, and does not throw.
    expect(await db.authenticateUser('no-such-user-xyz', 'whatever'), isNull,
        reason: 'an unknown user must still authenticate to null, not error');
    // A second, distinct unknown user — proves the dummy verify is repeatable /
    // side-effect free (it does not mutate state or throw on the 2nd call).
    expect(await db.authenticateUser('also-missing', 'anything'), isNull);
  });
}
