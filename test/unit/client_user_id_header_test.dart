// Spec 060 Phase 2 → Spec 151 P1-8 — client identity header threading.
//
// ORIGINAL (Spec 060): the client stamped `X-User-Id: <id>` and the middleware
// trusted it. That header is CLIENT-ASSERTED and forgeable — a bearer holder
// could claim any uid (e.g. admin `1`) or omit it to read cross-branch.
//
// NOW (Spec 151 P1-8): identity rides an UNFORGEABLE, server-minted
// `X-Session-Token` (see [ApiSessionToken]). The middleware derives the acting
// uid from that token and NO LONGER reads `X-User-Id`. The client stamps
// `X-Session-Token` (from `ServerProxy._sessionTokens[currentUserId]`) and
// never `X-User-Id`.
//
// These tests cover:
//   1. `SyncInterceptor.currentUserId` (still the client-side "who am I"
//      selector that picks which cached session token to send).
//   2. The middleware derives identity from a valid `X-Session-Token`, and
//      IGNORES `X-User-Id` / a missing / a forged token (fail closed).
//   3. A grep-style guard that `ServerProxy` stamps `X-Session-Token` on both
//      of its outbound code paths and NEVER stamps `X-User-Id`.
//
// The positive end-to-end path (real endpoint mint → verify) is covered by
// test/integration/api_session_auth_test.dart.

import 'package:flutter_test/flutter_test.dart';
import '../helpers/library_source.dart';
import 'package:shelf/shelf.dart';

import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  group('SyncInterceptor.currentUserId (client-side session selector)', () {
    setUp(() {
      SyncInterceptor.currentUserId = null;
    });

    tearDown(() {
      SyncInterceptor.currentUserId = null;
    });

    test('defaults to null pre-login', () {
      expect(SyncInterceptor.currentUserId, isNull);
    });

    test('accepts a positive int and reads it back', () {
      SyncInterceptor.currentUserId = 42;
      expect(SyncInterceptor.currentUserId, equals(42));
    });

    test('clears back to null on logout', () {
      SyncInterceptor.currentUserId = 7;
      SyncInterceptor.currentUserId = null;
      expect(SyncInterceptor.currentUserId, isNull);
    });
  });

  group('ApiAuthMiddleware derives identity from X-Session-Token (P1-8)', () {
    setUp(() {
      ApiAuthMiddleware.setToken('tok123');
      ApiSessionToken.setKeyForTesting('mw-key');
    });
    tearDown(() {
      ApiAuthMiddleware.clearToken();
      ApiSessionToken.clearKey();
    });

    Future<Request> runMiddleware(Request input) async {
      Request? captured;
      final handler = ApiAuthMiddleware.createMiddleware()((req) async {
        captured = req;
        return Response.ok('');
      });
      await handler(input);
      return captured!;
    }

    Request req(Map<String, String> extraHeaders) => Request(
          'POST',
          Uri.parse('http://localhost:8080/api/sales/1'),
          headers: {'authorization': 'Bearer tok123', ...extraHeaders},
        );

    test('uid derived from a valid X-Session-Token', () async {
      final token = ApiSessionToken.mint(42);
      final out = await runMiddleware(req({'x-session-token': token}));
      expect(ApiUserCtx.userIdOf(out), equals(42));
    });

    test('context is empty when the client sends no session token', () async {
      final out = await runMiddleware(req(const {}));
      expect(ApiUserCtx.userIdOf(out), isNull,
          reason: 'no signed token → no identity stamped (fail closed)');
    });

    test('a forged/garbage X-Session-Token is rejected → null', () async {
      final out = await runMiddleware(req({'x-session-token': 'garbage'}));
      expect(ApiUserCtx.userIdOf(out), isNull,
          reason: 'an unsigned token must not poison request.context');
    });

    test('legacy X-User-Id header is IGNORED (no longer trusted)', () async {
      // Even a "well-formed" X-User-Id must buy nothing now.
      for (final v in ['1', '42', 'admin']) {
        final out = await runMiddleware(req({'x-user-id': v}));
        expect(ApiUserCtx.userIdOf(out), isNull,
            reason: 'X-User-Id "$v" must NOT stamp an identity post-P1-8');
      }
    });
  });

  group('ServerProxy stamps X-Session-Token, never X-User-Id (grep guard)', () {
    late String src;
    setUp(() {
      src = readLibrarySource('lib/services/server_proxy.dart');
    });

    test('no longer stamps the forgeable X-User-Id header', () {
      // Comments still mention `X-User-Id` (backtick-quoted) to explain the
      // migration; guard against the actual header LITERAL only.
      expect(src.contains("'X-User-Id'"), isFalse,
          reason: 'the client must not emit X-User-Id anymore — identity now '
              'rides the signed X-Session-Token.');
    });

    test('stamps X-Session-Token on both outbound code paths', () {
      // 1) _authHeaders map path — covers GET/post/put/delete. Uses a
      //    null-aware map element (`?sessionToken`) so the entry is omitted
      //    when no token is cached (pre-login / offline).
      expect(
        src.contains("'X-Session-Token': ?sessionToken"),
        isTrue,
        reason: '_authHeaders must stamp the signed session token so the '
            'server can derive the user behind the shared Bearer token.',
      );
      // 2) fetchUsers HttpClient path — separate request builder that does not
      //    go through _authHeaders (easy to forget).
      expect(
        src.contains("request.headers.set('X-Session-Token', sessionToken)"),
        isTrue,
        reason: 'fetchUsers HttpClient path must also stamp X-Session-Token.',
      );
    });
  });
}
