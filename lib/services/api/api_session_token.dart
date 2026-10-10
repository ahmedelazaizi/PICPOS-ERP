import 'dart:convert';
import 'dart:math' show Random;
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
      // رمزُ الويب (`aud:'web'`) لا يصلح رمزَ جلسة جهاز — يُتحقَّق منه عبر
      // [verifyWeb] فقط. الرموزُ القائمة بلا `aud` فسلوكُها لم يتغيّر.
      if (map.containsKey('aud')) return null;
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

  // ───────────────────────────── جلسات الويب ─────────────────────────────
  //
  // رمزٌ منفصل (ud:'web') لمتصفّح الويب: مدّته 12 ساعة، ويحمل معرّف جلسة
  // sid عشوائياً يمكن إلغاؤه (تسجيل خروج/تعطيل) قبل انتهاء المدّة. الإلغاءُ
  // في ذاكرة العملية فقط (إعادة تشغيل المضيف تُفرغ القائمة، والرمز يبقى
  // صالحاً حتى exp) — القناة تفحص المستخدم دورياً فتُغلق عند التعطيل.

  /// الجمهور الذي يحمله رمز الويب.
  static const String webAudience = 'web';

  static const Duration _webTtl = Duration(hours: 12);

  /// مدّة جلسة الويب بالميلي ثانية.
  static int get webTtlMs => _webTtl.inMilliseconds;

  /// sid → وقت انتهاء الرمز (للتنظيف: بعد الانتهاء لا حاجة لإبقائه).
  static final Map<String, int> _revokedSids = <String, int>{};

  /// userId → لحظة الإبطال: كلُّ رمزٍ أُصدر (iat) عندها أو قبلها يفشل.
  static final Map<int, int> _userRevokedAtMs = <int, int>{};

  /// أيقِف الجلسة [sid]: كلُّ رمزٍ بها يفشل في [verifyWeb] من الآن.
  /// [expiresAtMs] انتهاء الرمز (افتراضه الآن + مدّة الجلسة) لتنظيف القائمة.
  static void revokeSid(String sid, {int? expiresAtMs, int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _revokedSids.removeWhere((_, exp) => now >= exp);
    _revokedSids[sid] = expiresAtMs ?? now + _webTtl.inMilliseconds;
  }

  /// هل أُلغيت الجلسة [sid]؟
  static bool isSidRevoked(String sid) => _revokedSids.containsKey(sid);

  /// يُبطل كلَّ جلسات ويب [userId] المُصدَرة حتى الآن (تعطيل/كلمة مرور).
  static void revokeUser(int userId, {int? nowMs}) {
    _userRevokedAtMs[userId] = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  }

  /// Test hook — تفريغ قوائم الإلغاء.
  static void clearRevokedForTesting() {
    _revokedSids.clear();
    _userRevokedAtMs.clear();
  }

  /// رمزُ جلسة ويب للمستخدم [userId]؛ [sid] يُولَّد عشوائياً إن لم يُمرَّر.
  /// [bindRole] يربط الرمز بـ[roleId] وقت الإصدار (null = بلا دور): تغيّر الدور
  /// لاحقاً يُبطله في `WebSessionGuard`.
  static String mintWeb(
    int userId, {
    String? sid,
    int? nowMs,
    int? roleId,
    bool bindRole = false,
  }) {
    if (_signingKey == null) {
      throw StateError('ApiSessionToken.mintWeb before deriveKey');
    }
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'uid': userId,
      'exp': now + _webTtl.inMilliseconds,
      'iat': now,
      'aud': webAudience,
      'sid': sid ?? _newSid(),
      if (bindRole) 'rid': roleId ?? -1,
    })));
    return '$payload.${_sign(payload)}';
  }

  /// يتحقّق من رمز ويب؛ null عند أيّ فشل (توقيع/انتهاء/aud/sid ملغى/تالف).
  static WebSessionClaims? verifyWeb(String? token, {int? nowMs}) {
    if (token == null || _signingKey == null) return null;
    final dot = token.indexOf('.');
    if (dot <= 0 || dot == token.length - 1) return null;
    final payloadB64 = token.substring(0, dot);
    if (!_constantTimeEquals(token.substring(dot + 1), _sign(payloadB64))) {
      return null;
    }
    try {
      final map = jsonDecode(utf8.decode(base64Url.decode(payloadB64)))
          as Map<String, dynamic>;
      final uid = map['uid'];
      final exp = map['exp'];
      final sid = map['sid'];
      if (map['aud'] != webAudience) return null;
      if (uid is! int || uid <= 0 || exp is! int) return null;
      if (sid is! String || sid.isEmpty || _revokedSids.containsKey(sid)) {
        return null;
      }
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      if (now >= exp) return null;
      final iatRaw = map['iat'];
      final iat = iatRaw is int ? iatRaw : exp - _webTtl.inMilliseconds;
      final userRevokedAt = _userRevokedAtMs[uid];
      if (userRevokedAt != null && iat <= userRevokedAt) return null;
      final rid = map['rid'];
      return WebSessionClaims(
        userId: uid,
        sid: sid,
        expiresAtMs: exp,
        issuedAtMs: iat,
        roleBound: rid is int,
        roleId: rid is int && rid > 0 ? rid : null,
      );
    } catch (_) {
      return null;
    }
  }

  static String _newSid() {
    final rnd = Random.secure();
    return base64Url
        .encode(List<int>.generate(18, (_) => rnd.nextInt(256)))
        .replaceAll('=', '');
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

/// مطالبات رمز جلسة ويب بعد التحقّق.
class WebSessionClaims {
  const WebSessionClaims({
    required this.userId,
    required this.sid,
    required this.expiresAtMs,
    this.issuedAtMs = 0,
    this.roleBound = false,
    this.roleId,
  });

  final int userId;
  final String sid;
  final int expiresAtMs;
  final int issuedAtMs;

  /// هل رُبط الرمز بدورٍ وقت الإصدار؟ ([roleId] قد يكون null = بلا دور.)
  final bool roleBound;
  final int? roleId;
}
