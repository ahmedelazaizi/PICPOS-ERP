import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Signed per-user session tokens for the embedded LAN server (Spec 151 / P1-8).
///
/// Replaces the forgeable, client-asserted `X-User-Id` header. The server mints
/// a token ONLY AFTER verifying the user's credentials (`POST /api/auth/session`),
/// HMAC-signing `{uid, exp}` with a server-only key derived from the machine
/// seed. Clients receive the resulting **opaque** token and echo it back in the
/// `X-Session-Token` header on every request; they never hold the signing key,
/// so they cannot forge an arbitrary `uid` (e.g. admin `1`) or mutate one.
///
/// **Stateless** — no table, no migration. The signing key is stable across
/// restarts (derived from the SAME machine seed as the shared bearer token, but
/// a DISTINCT salt), so tokens minted before a restart keep verifying. Rotating
/// the machine seed (or key salt) invalidates every outstanding session.
///
/// Layering: this is the IDENTITY layer. The shared per-machine bearer token
/// (`ApiAuthMiddleware`) remains the TRANSPORT gate — both are required. The
/// bearer proves "a paired device"; the session token proves "which user".
class ApiSessionToken {
  ApiSessionToken._();

  /// Header the client sends the opaque token in (shelf lowercases lookups).
  static const String headerName = 'x-session-token';

  // ⚠ ملح تشفير — ثابت حرفي بشكل مقصود. **ممنوع** يتحول لـ `Brand.name` أو
  // أي قيمة مرتبطة بالعلامة: مفتاح التوقيع مشتق منه، فتغييره بيبطّل كل
  // جلسات المستخدمين القائمة فوراً. يفضل 'UralCash' مهما كانت العلامة.
  static const String _salt = 'UralCash-Session-v1';
  static const Duration _ttl = Duration(days: 30);

  /// Server-only HMAC key. NEVER sent to a client. Null until the server calls
  /// [deriveKey] at startup — [verify] returns null while unset (fail-closed).
  static List<int>? _signingKey;

  /// Milliseconds a freshly-minted token stays valid — returned to the client
  /// so it can refresh proactively.
  static int get ttlMs => _ttl.inMilliseconds;

  /// Derive + store the server-only signing key. Called once at server start
  /// with the SAME `machineSeed` as [ApiAuthMiddleware.generateToken].
  static void deriveKey(String machineSeed) {
    _signingKey = sha256.convert(utf8.encode('$machineSeed:$_salt')).bytes;
  }

  /// Whether the signing key has been derived (server is issuing sessions).
  static bool get isReady => _signingKey != null;

  /// Test hook — set a deterministic key without a machine seed.
  static void setKeyForTesting(String key) =>
      _signingKey = sha256.convert(utf8.encode(key)).bytes;

  /// Test/shutdown hook — drop the key (subsequent [verify] fail closed).
  static void clearKey() => _signingKey = null;

  static String _sign(String payloadB64) {
    final mac = Hmac(sha256, _signingKey!).convert(utf8.encode(payloadB64));
    return base64Url.encode(mac.bytes);
  }

  /// Mint a signed token for [userId], valid for [_ttl]. [nowMs] is injectable
  /// for tests. Throws [StateError] if the key isn't derived yet — callers
  /// (the issue endpoint) must guard on [isReady] first.
  static String mint(int userId, {int? nowMs}) {
    if (_signingKey == null) {
      throw StateError('ApiSessionToken.mint before deriveKey');
    }
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final exp = now + _ttl.inMilliseconds;
    final payload =
        base64Url.encode(utf8.encode(jsonEncode({'uid': userId, 'exp': exp})));
    return '$payload.${_sign(payload)}';
  }

  /// Verify [token]; return its `uid` iff the signature is valid AND the token
  /// is unexpired, else null. Fail-closed on a null token, an unset key, a
  /// malformed token, a bad signature, or expiry. [nowMs] is injectable.
  static int? verify(String? token, {int? nowMs}) {
    if (token == null || _signingKey == null) return null;
    final dot = token.indexOf('.');
    if (dot <= 0 || dot == token.length - 1) return null;
    final payloadB64 = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    // Verify the signature BEFORE trusting the payload bytes.
    if (!_constantTimeEquals(sig, _sign(payloadB64))) return null;
    try {
      final map = jsonDecode(utf8.decode(base64Url.decode(payloadB64)))
          as Map<String, dynamic>;
      final uid = map['uid'];
      final exp = map['exp'];
      if (uid is! int || uid <= 0 || exp is! int) return null;
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      if (now >= exp) return null;
      return uid;
    } catch (_) {
      return null;
    }
  }

  /// Length-independent constant-time compare (both are fixed-length base64url
  /// SHA-256 macs anyway, but keep the timing side-channel closed regardless).
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
