// ═══════════════════════════════════════════════════════════════════════════
// POST /api/auth/change-password - a user sets his OWN password (plan
// 2026-10-24, P1 / B.7.1).
//
// Why it exists: a user created with a temporary password (`force_password_
// change`) is refused a session (403 password_change_required), and the only
// other password endpoint is the administrative `/api/users/<id>/password`
// (needs `users_manage`). Without this endpoint a branch cashier can never get
// out of the forced-change loop.
//
// Contract (see docs/plans/2026-10-24-users-login-sync-logic-plan.md §C
// "implemented contract"):
//   request  : bearer of a paired device (NO user session - the caller proves
//              identity with the current credential, like /api/auth/session)
//              { username, currentPassword, newPassword }
//           or { cardCode, newPassword }   (only while the account is forced)
//   200      : { token, userId, expiresInMs, passwordHash, serverTime,
//                alreadyApplied }  - a fresh session for the user
//   400      : invalid_request | password_too_short | password_same_as_current
//              | password_same_as_username
//   401      : invalid_credentials
//   403      : branch_access_denied | mirror_console_denied
//              | card_change_not_allowed
//   409      : password_rejected   (the password is in use; never names whom)
//   429      : locked_out          (same bucket as /api/auth/session)
//   503      : session auth not ready
// Never queued: the plaintext password is never stored on a device.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

import '../../core/auth/password_policy.dart';
import '../../data/database/database.dart';
import 'api_auth_handler.dart';
import 'api_auth_support.dart';
import 'api_errors.dart';
import 'api_handler_base.dart';
import 'api_session_token.dart';
import 'server_login_throttle.dart';
import 'web_session_guard.dart';

class ApiPasswordChangeHandler extends ApiHandlerBase {
  ApiPasswordChangeHandler(super.db, super.wsClients);

  Response _fail(int status, String error, String code) =>
      jsonResponse({'error': error, 'code': code}, statusCode: status);

  // EXEMPT-PER-USER: proves identity by the current credential (like
  // issueSession); there is no signed-in user yet. Sits behind the device bearer.
  Future<Response> changePassword(Request request) async {
    try {
      if (!ApiSessionToken.isReady) {
        return _fail(503, 'Session auth not ready', 'not_ready');
      }
      final decoded = json.decode(await request.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return _fail(400, 'invalid body', 'invalid_request');
      }
      final username = (decoded['username'] as String?)?.trim();
      final current = decoded['currentPassword'] as String?;
      final cardCode = (decoded['cardCode'] as String?)?.trim();
      final next = decoded['newPassword'] as String?;
      final useCard = cardCode != null && cardCode.isNotEmpty;
      final useUserPass = username != null &&
          username.isNotEmpty &&
          current != null &&
          current.isNotEmpty;
      if (next == null || next.isEmpty || !(useCard || useUserPass)) {
        return _fail(
          400,
          'username+currentPassword (or cardCode) and newPassword required',
          'invalid_request',
        );
      }

      final key = useCard
          ? ApiAuthHandler.cardThrottleKey(cardCode)
          : ApiAuthHandler.userThrottleKey(username!);
      if (ServerLoginThrottle.isLockedOut(key)) {
        return _fail(429, 'Too many attempts, try again later', 'locked_out');
      }

      var alreadyApplied = false;
      UserWithRole? result = useCard
          ? await db.authenticateByCardCode(cardCode)
          : await db.authenticateUser(username!, current!);
      if (result == null && useUserPass) {
        // Idempotent replay: the first answer was lost and the client retries
        // with the same body. The new password already works and the forced
        // flag is gone => treat the change as applied (a guess still counts
        // as a failure below when it does not match).
        final replay = await db.authenticateUser(username, next);
        if (replay != null && !replay.user.forcePasswordChange) {
          result = replay;
          alreadyApplied = true;
        }
      }
      if (result == null) {
        ServerLoginThrottle.recordFailure(key);
        return _fail(401, 'Invalid credentials', 'invalid_credentials');
      }
      ServerLoginThrottle.recordSuccess(key);
      final user = result.user;

      final denial = await deviceSessionDenial(db, request, user);
      if (denial != null) return _fail(403, denial, denial);
      if (useCard && !user.forcePasswordChange) {
        return _fail(
          403,
          'a card alone may only set the initial password',
          'card_change_not_allowed',
        );
      }

      if (!alreadyApplied) {
        final policy = validateNewPassword(user.username, current, next);
        if (policy != null) return _fail(400, policy, policy);
        try {
          await db.updateUserPassword(userId: user.id, newPassword: next);
        } on DuplicatePasswordException {
          return _fail(409, 'password rejected', 'password_rejected');
        }
        // Old sessions die; the new one is minted strictly after the cut-off.
        WebSessionGuard.userChanged(user.id, revokeSessions: true);
        await ApiHandlerBase.withBroadcast(
          endpointLabel: 'auth.change-password',
          tables: {'users'},
          body: () async {},
        );
      }
      await AuthAudit.log(
        db,
        request,
        action: alreadyApplied ? 'password_change_replayed' : 'password_changed_self',
        user: user,
      );

      final fresh = await (db.select(db.users)
            ..where((u) => u.id.equals(user.id)))
          .getSingle();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      return jsonResponse({
        'token': ApiSessionToken.mint(user.id, nowMs: nowMs + 1),
        'userId': user.id,
        'expiresInMs': ApiSessionToken.ttlMs,
        'passwordHash': fresh.passwordHash,
        'serverTime': nowMs,
        'alreadyApplied': alreadyApplied,
      });
    } catch (e) {
      debugPrint('[API] changePassword error: $e');
      return ApiErrors.fail(e, 'Failed to change password');
    }
  }
}
