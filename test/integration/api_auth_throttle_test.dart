// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · P1-8b — server-side brute-force lockout on the credential
// endpoints. `issueSession` (and `verifyAdmin`) now consult a SEPARATE static
// in-memory tracker (ServerLoginThrottle, distinct from the client-side
// LoginRateLimiter): 5 consecutive failures per key → a 15-minute lockout; a
// successful auth clears the counter; a 400 (missing fields) is NOT counted.
//
// Keying: username logins → `u:<lowercased-username>`; card-code logins →
// `c:<hash16>`. The tests drive `ApiAuthHandler(db, const {}).issueSession(req)`
// directly (as api_session_auth_test does). The session-signing key is set via
// ApiSessionToken.setKeyForTesting so issueSession doesn't short-circuit to 503.
//
// The throttle is a process-wide static, so it is reset in setUp AND tearDown to
// keep the cases deterministic and order-independent.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_auth_handler.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/server_login_throttle.dart';

void main() {
  late AppDatabase db;

  const username = 'lockme';
  const correctPassword = 'pw-correct';

  setUp(() async {
    ServerLoginThrottle.reset();
    ApiSessionToken.setKeyForTesting('p18b-throttle-seed');

    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير', isSystemRole: const Value(false)),
        );
    await db.createUser(
      username: username,
      password: correctPassword,
      displayName: 'Lock Me',
      roleId: roleId,
    );
  });

  tearDown(() async {
    ServerLoginThrottle.reset();
    ApiSessionToken.clearKey();
    await db.close();
  });

  Future<shelf.Response> issue(Map<String, dynamic> body) {
    return ApiAuthHandler(db, const {}).issueSession(shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/auth/session'),
      body: jsonEncode(body),
    ));
  }

  test(
      '5 consecutive WRONG-password attempts return 401; the 6th is LOCKED (429)',
      () async {
    for (var i = 1; i <= 5; i++) {
      final resp = await issue({'username': username, 'password': 'WRONG'});
      expect(resp.statusCode, 401,
          reason: 'attempt $i is a real failed credential → 401, not yet locked');
    }
    // The 6th attempt is blocked BEFORE the credential is even checked.
    final locked = await issue({'username': username, 'password': 'WRONG'});
    expect(locked.statusCode, 429,
        reason: 'after 5 failures the key is locked → 429 (generic message)');

    // Even the CORRECT password is refused while the lockout window is open —
    // the lockout gate runs before authentication.
    final stillLocked =
        await issue({'username': username, 'password': correctPassword});
    expect(stillLocked.statusCode, 429,
        reason: 'a correct password cannot bypass an active lockout window');
  });

  test('a CORRECT password before lockout succeeds and CLEARS the counter',
      () async {
    // 3 failures — one short of the 5-failure threshold.
    for (var i = 0; i < 3; i++) {
      final resp = await issue({'username': username, 'password': 'WRONG'});
      expect(resp.statusCode, 401);
    }
    // A correct login clears the counter (recordSuccess).
    final ok = await issue({'username': username, 'password': correctPassword});
    expect(ok.statusCode, 200,
        reason: 'valid credentials issue a token — 3 prior failures < 5');
    final okBody = jsonDecode(await ok.readAsString()) as Map<String, dynamic>;
    expect(okBody['token'], isNotNull);

    // The counter restarted: a single wrong attempt is only failure #1, so it
    // returns 401 — NOT 429. (Without the reset, this would be failure #4→ still
    // 401 too, so prove the reset by exhausting a FRESH full run below.)
    final afterReset =
        await issue({'username': username, 'password': 'WRONG'});
    expect(afterReset.statusCode, 401,
        reason: 'post-success the count restarts at 1, so this is not locked');

    // 4 more wrong attempts (total 5 in the fresh window) → then locked on #6.
    for (var i = 0; i < 4; i++) {
      final resp = await issue({'username': username, 'password': 'WRONG'});
      expect(resp.statusCode, 401);
    }
    final relocked = await issue({'username': username, 'password': 'WRONG'});
    expect(relocked.statusCode, 429,
        reason: '5 failures in the fresh window re-arm the lockout, proving the '
            'success genuinely reset the counter');
  });

  test('a 400 (missing credential fields) does NOT count toward lockout',
      () async {
    // Empty body → no usable credential → 400, and the throttle key is never
    // even resolved, so nothing is recorded. Repeat well past the threshold.
    for (var i = 0; i < 8; i++) {
      final resp = await issue(<String, dynamic>{});
      expect(resp.statusCode, 400,
          reason: 'a malformed request must never be throttled');
    }
    // A single wrong credential afterwards is failure #1 (401), proving the 8
    // 400s did not pre-charge the counter toward the 5-failure lockout.
    final firstRealFailure =
        await issue({'username': username, 'password': 'WRONG'});
    expect(firstRealFailure.statusCode, 401,
        reason: 'the counter starts fresh — the 400s were not counted');
  });

  test('lockout is keyed per-username — a different username is unaffected',
      () async {
    // Lock out `username`.
    for (var i = 0; i < 5; i++) {
      await issue({'username': username, 'password': 'WRONG'});
    }
    expect(
        (await issue({'username': username, 'password': 'WRONG'})).statusCode,
        429);

    // A DIFFERENT (also-nonexistent) username has its own bucket → 401, not 429.
    final other = await issue({'username': 'someone-else', 'password': 'x'});
    expect(other.statusCode, 401,
        reason: 'the lockout is per-key, so it must not bleed across usernames');
  });
}
