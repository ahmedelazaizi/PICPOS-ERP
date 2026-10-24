// ═══════════════════════════════════════════════════════════════════════════
// API AUTH HANDLER — Mirror-mode admin verification endpoint
// ═══════════════════════════════════════════════════════════════════════════
//
// Hosts authentication endpoints that don't fit the CRUD-shaped pattern of
// the data handlers — currently just `POST /api/auth/verify-admin` for
// Feature 006 mirror-mode pairing (MM.C).
//
// The mirror laptop hits this endpoint during the wizard pairing step to:
//   1. Confirm the operator is who they say they are (username + password
//      against the HQ server, NOT the local DB).
//   2. Confirm that operator carries the admin role on HQ — mirror mode
//      makes every write authoritative on HQ, so a non-admin operator
//      should never reach mirror.
//   3. Receive HQ's user id back so MirrorState.adminUserId can be stamped
//      into every subsequent write payload (C4) for audit attribution.
//
// This endpoint sits behind the same Bearer-token middleware as every
// other /api/* route — the mirror laptop must have completed the
// /api/health handshake (which delivers the API token) before calling
// verify-admin. That property is what lets the endpoint trust the caller
// is reaching the right HQ instance and not a spoofed peer on the LAN.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'api_errors.dart';
import '../../data/database/database.dart';
import '../security_service.dart';
import 'api_handler_base.dart';
import 'api_auth_support.dart';
import 'api_session_token.dart';
import 'server_login_throttle.dart';

class ApiAuthHandler extends ApiHandlerBase {
  ApiAuthHandler(super.db, super.wsClients);

  /// Spec 151 P1-8b — uniform 429 body for a server-side brute-force lockout.
  /// Distinct from the 401 `Invalid credentials` text (which must NOT reveal
  /// whether the user exists); the lockout text is deliberately generic.
  static const String _lockoutMessage = 'Too many attempts, try again later';

  /// Per-username throttle key (lower-cased so `Admin`/`admin` share a bucket).
  static String userThrottleKey(String username) =>
      'u:${username.toLowerCase()}';

  /// Per-card-code throttle key. The raw card code is NEVER used as the key
  /// (and never logged) — it is one-way hashed and truncated so the in-memory
  /// map cannot leak card codes.
  static String cardThrottleKey(String cardCode) =>
      'c:${SecurityService.hashApiKey(cardCode).substring(0, 16)}';

  /// Same admin-classification predicate as `AuthState.isAdmin` in the UI
  /// layer. Kept literal here (not imported) so the server handler stays
  /// independent of Riverpod and the presentation layer.
  static bool _roleIsAdmin(String? roleName) {
    if (roleName == null) return false;
    final lc = roleName.toLowerCase();
    return lc.contains('admin') ||
        lc.contains('مدير النظام') ||
        lc.contains('مسؤول');
  }

  /// 403 returned instead of a session when `force_password_change` is set.
  Response _passwordChangeRequired() => jsonResponse(
        {
          'error': 'password change required',
          'code': 'password_change_required',
        },
        statusCode: 403,
      );

  /// `POST /api/auth/verify-admin`
  ///
  /// Body: `{ "username": "...", "password": "..." }`
  ///
  /// Responses:
  ///   • 200 — `{ "userId": <int>, "displayName": "...", "roleName": "..." }`
  ///   • 400 — missing/blank username or password.
  ///   • 401 — invalid credentials (user not found, wrong password, locked,
  ///           or inactive).
  ///   • 403 — credentials valid but the user does not carry an admin role.
  ///   • 429 — too many failed attempts for this username (P1-8b lockout).
  // EXEMPT-PER-USER: pre-login mirror handshake; no authenticated user
  // exists yet. (Spec 077 Batch 5 allow-list — see §6 of endpoint-permission-map.md)
  Future<Response> verifyAdmin(Request request) async {
    try {
      final raw = await request.readAsString();
      final data = json.decode(raw) as Map<String, dynamic>;

      final username = (data['username'] as String?)?.trim();
      final password = data['password'] as String?;

      if (username == null || username.isEmpty) {
        return errorResponse('username required', statusCode: 400);
      }
      if (password == null || password.isEmpty) {
        return errorResponse('password required', statusCode: 400);
      }

      // Spec 151 P1-8b — server-side per-username brute-force lockout.
      final throttleKey = userThrottleKey(username);
      if (ServerLoginThrottle.isLockedOut(throttleKey)) {
        return errorResponse(_lockoutMessage, statusCode: 429);
      }

      final result = await db.authenticateUser(username, password);
      if (result == null) {
        ServerLoginThrottle.recordFailure(throttleKey);
        if (kDebugMode) {
          debugPrint('[API] verifyAdmin: auth failed for "$username"');
        }
        return errorResponse('Invalid credentials', statusCode: 401);
      }
      // Credentials are valid (even if the role check below rejects the
      // pairing) — clear the failed-attempt counter so a legitimate operator
      // is never locked out by their own successful logins.
      ServerLoginThrottle.recordSuccess(throttleKey);

      // SEC-002: a default/temporary-credential account must change its
      // password first — it never gets to prove "admin" over the API.
      if (result.user.forcePasswordChange) return _passwordChangeRequired();

      final roleName = result.role?.name;
      if (!_roleIsAdmin(roleName)) {
        if (kDebugMode) {
          debugPrint('[API] verifyAdmin: "$username" authenticated but '
              'role="$roleName" is not admin — denying mirror pairing');
        }
        return errorResponse(
          'User is not an admin',
          statusCode: 403,
        );
      }

      return jsonResponse({
        'userId': result.user.id,
        'displayName': result.user.displayName,
        'roleName': roleName,
      });
    } catch (e) {
      debugPrint('[API] verifyAdmin error: $e');
      return ApiErrors.fail(e, 'Failed to verify admin');
    }
  }

  /// `POST /api/auth/session`
  ///
  /// Spec 151 (P1-8) — issue a signed per-user session token. The client
  /// presents the SAME credential it just used to log in locally; the server
  /// re-verifies it against its own (serverWins-synced) user table, then mints
  /// an HMAC-signed token the client echoes in `X-Session-Token`. This replaces
  /// the forgeable, client-asserted `X-User-Id` header as the identity source —
  /// a holder of the shared bearer token can no longer assert an arbitrary uid.
  ///
  /// Body (one of):
  ///   • `{ "username": "...", "password": "..." }`
  ///   • `{ "cardCode": "..." }`  (POS card-swipe cashiers)
  ///
  /// Responses:
  ///   • 200 — `{ "token": "...", "userId": <int>, "expiresInMs": <int> }`
  ///   • 400 — no usable credential in the body.
  ///   • 401 — invalid credentials (not found / wrong password / locked /
  ///           inactive).
  ///   • 429 — too many failed attempts for this credential (P1-8b lockout).
  ///   • 503 — the server hasn't derived its session-signing key yet
  ///           (server not fully started).
  // EXEMPT-PER-USER: this endpoint ISSUES identity — it authenticates by
  // credential, not by an existing session. Sits behind the shared bearer.
  Future<Response> issueSession(Request request) async {
    try {
      if (!ApiSessionToken.isReady) {
        return errorResponse('Session auth not ready', statusCode: 503);
      }
      final raw = await request.readAsString();
      final data = json.decode(raw) as Map<String, dynamic>;

      final username = (data['username'] as String?)?.trim();
      final password = data['password'] as String?;
      final cardCode = (data['cardCode'] as String?)?.trim();

      // Spec 151 P1-8b — resolve the brute-force throttle key from whichever
      // credential the caller supplied. A 400 (missing fields) is NOT throttled
      // — only real credential attempts count. Key is username when present,
      // else the hashed card code.
      final String throttleKey;
      final bool useCard = cardCode != null && cardCode.isNotEmpty;
      final bool useUserPass = username != null &&
          username.isNotEmpty &&
          password != null &&
          password.isNotEmpty;
      if (useCard) {
        throttleKey = cardThrottleKey(cardCode);
      } else if (useUserPass) {
        throttleKey = userThrottleKey(username);
      } else {
        return errorResponse(
          'username+password or cardCode required',
          statusCode: 400,
        );
      }

      if (ServerLoginThrottle.isLockedOut(throttleKey)) {
        return jsonResponse({'error': _lockoutMessage, 'code': 'locked_out'},
            statusCode: 429);
      }

      final UserWithRole? result = useCard
          ? await db.authenticateByCardCode(cardCode)
          : await db.authenticateUser(username!, password!);

      if (result == null) {
        ServerLoginThrottle.recordFailure(throttleKey);
        return jsonResponse(
            {'error': 'Invalid credentials', 'code': 'invalid_credentials'},
            statusCode: 401);
      }
      ServerLoginThrottle.recordSuccess(throttleKey);

      // P1: the PAIRED DEVICE decides who may sign in on it (device branch,
      // mirror_console on a mirror). Checked before the forced-change 403.
      final denial = await deviceSessionDenial(db, request, result.user);
      if (denial != null) {
        return jsonResponse({'error': denial, 'code': denial}, statusCode: 403);
      }

      // SEC-002: no session for accounts still on default/temporary
      // credentials. The change must happen on the host first.
      if (result.user.forcePasswordChange) return _passwordChangeRequired();

      final token = ApiSessionToken.mint(result.user.id);
      final deviceId = request.context['lanDeviceId'] as String?;
      if (AuthAudit.shouldLogSession(result.user.id, deviceId)) {
        await AuthAudit.log(db, request, action: 'session_issued', user: result.user);
      }
      return jsonResponse({
        'token': token,
        'userId': result.user.id,
        'expiresInMs': ApiSessionToken.ttlMs,
      });
    } catch (e) {
      debugPrint('[API] issueSession error: $e');
      return ApiErrors.fail(e, 'Failed to issue session');
    }
  }
}
