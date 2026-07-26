import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import 'api_session_token.dart';
import 'api_user_context.dart';

/// API Authentication middleware for the embedded multi-device server.
///
/// Generates a shared secret token based on the server's machine fingerprint
/// and validates it on every `/api/*` request (except health check).
///
/// **Flow:**
/// 1. Server starts → generates token from machine ID + app salt
/// 2. Health endpoint returns the token for client handshake
/// 3. Client stores token → sends as `Authorization: Bearer <token>` header
/// 4. Middleware validates on every request
///
/// **Exempt paths:** `/api/health`, `/cfd`, `/menu`, `/ws`
class ApiAuthMiddleware {
  ApiAuthMiddleware._();

  /// The current valid API token (generated at server startup).
  static String? _activeToken;

  /// Paths that do NOT require authentication.
  static const _exemptPrefixes = ['/api/health', '/cfd', '/menu', '/ws'];

  /// Generate and store the API token from a machine-specific seed.
  ///
  /// Called once at server startup. The token is derived from the machine's
  /// unique identifier so it's stable across restarts but unique per machine.
  static String generateToken(String machineSeed) {
    // ⚠ ملح تشفير — ثابت حرفي بشكل مقصود. **ممنوع** يتحول لـ `Brand.name`
    // أو أي قيمة مرتبطة بالعلامة: التوكن مشتق منه، فتغييره بيبطّل كل توكنز
    // الأجهزة المقترنة القائمة وتحتاج إقران من جديد. يفضل 'UralCash' مهما
    // كانت العلامة اللي بتتبني.
    const salt = 'UralCash-API-v1';
    final bytes = utf8.encode('$machineSeed:$salt');
    final digest = sha256.convert(bytes);
    _activeToken = digest.toString().substring(0, 32);
    return _activeToken!;
  }

  /// Get the currently active token (for sharing with clients via health check).
  static String? get activeToken => _activeToken;

  /// A-SEC-1: the API token is only exposed via `/api/health` while a device
  /// pairing window is open. Steady-state health omits it so a passive LAN peer
  /// can't read the bearer token and impersonate a trusted device. The window
  /// is opened deliberately by the server operator when adding a new device.
  static DateTime? _pairingOpenUntil;

  /// Open a short window during which `/api/health` will include the token.
  static void openPairingWindow([Duration ttl = const Duration(minutes: 5)]) {
    _pairingOpenUntil = DateTime.now().add(ttl);
  }

  /// Close the pairing window immediately.
  static void closePairingWindow() => _pairingOpenUntil = null;

  /// Whether the token may currently be handed out via `/api/health`.
  static bool get isPairingOpen {
    final until = _pairingOpenUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Set a token directly (for testing or manual configuration).
  static void setToken(String token) => _activeToken = token;

  /// Clear the active token (for testing).
  static void clearToken() => _activeToken = null;

  /// Create a shelf [Middleware] that validates the Authorization header.
  static Middleware createMiddleware() {
    return (Handler innerHandler) {
      return (Request request) {
        final path = '/${request.url.path}';

        // Allow exempt paths
        for (final prefix in _exemptPrefixes) {
          if (path.startsWith(prefix) || path == prefix) {
            return innerHandler(request);
          }
        }

        // Non-API paths pass through
        if (!path.startsWith('/api/')) {
          return innerHandler(request);
        }

        // A-SEC-2 (H-3): FAIL CLOSED. A null token used to pass every /api/*
        // request through unauthenticated — a mis-started/never-generated
        // token turned the server wide open. In production the token is always
        // generated at server startup (NetworkService.startServer), so a null
        // token here means "not a live server" and must be rejected. Exempt
        // paths (health/cfd/menu/ws) already returned above.
        if (_activeToken == null) {
          return Response(
            403,
            body: '{"error": "Server not accepting API requests"}',
            headers: {'content-type': 'application/json'},
          );
        }

        // Validate Authorization header
        final authHeader = request.headers['authorization'];
        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return Response(
            401,
            body: '{"error": "Missing or invalid Authorization header"}',
            headers: {'content-type': 'application/json'},
          );
        }

        final token = authHeader.substring(7); // Remove 'Bearer '
        if (token != _activeToken) {
          return Response(
            403,
            body: '{"error": "Invalid API token"}',
            headers: {'content-type': 'application/json'},
          );
        }

        // Spec 151 (P1-8): derive the acting userId from a SIGNED session
        // token, NOT the old forgeable, client-asserted `X-User-Id`. The token
        // is minted server-side by `POST /api/auth/session` only after a
        // credential check, and HMAC-signed with a server-only key
        // ([ApiSessionToken]) — so a holder of the shared bearer token can no
        // longer assert an arbitrary uid (e.g. admin `1`) nor omit identity to
        // read cross-branch. Absent/invalid/expired token → no identity stamped
        // (uid null); `_extractBranchId` then fails CLOSED and
        // `requirePermission` returns 401. `X-User-Id` is no longer trusted.
        final uid = ApiSessionToken.verify(
          request.headers[ApiSessionToken.headerName],
        );
        Request enriched = request;
        if (uid != null) {
          enriched = request.change(context: {ApiUserCtx.userIdKey: uid});
        }

        return innerHandler(enriched);
      };
    };
  }
}
