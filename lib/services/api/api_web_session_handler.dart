// مصادقة الويب في الخادم (م3-4 من docs/superpowers/specs/2026-09-01-saas-web-design.md).
//
// مساران:
//   * POST /api/web/session   — اسم مستخدم + كلمة مرور → رمز جلسة ويب (12 ساعة)
//                               + الدور + أكواد الصلاحيات.
//   * POST /api/web/ws-ticket — بترويسة الجلسة → تذكرة تُستعمل **مرة واحدة**
//                               وتنتهي خلال 30 ثانية، تُقدَّم إلى `/webdb?ticket=`.
//
// التحقّق من الدخول هو نفسه `AppDatabase.authenticateUser` (الذي تستعمله
// `POST /api/auth/session`) — لا تجزئة كلمات مرور هنا. ومحدِّد المحاولات
// `ServerLoginThrottle` مشترك مع مسار الأجهزة بنفس صيغة المفتاح.
//
// لماذا تذكرة؟ المتصفح لا يضيف ترويسات مخصّصة إلى WebSocket، ووضعُ رمز الجلسة
// في الـURL يسرّبه إلى السجلات. فالتذكرةُ قصيرة العمر وأحاديّة الاستعمال هي
// التي تظهر في الـURL.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

import '../../data/database/database.dart';
import 'api_session_token.dart';
import 'server_login_throttle.dart';

/// مفاتيح سياق الطلب التي يضعها `ApiAuthMiddleware` لجلسة الويب.
class ApiWebCtx {
  ApiWebCtx._();

  /// قيمته [WebSessionClaims].
  static const String claimsKey = 'webSessionClaims';
}

/// قائمة Origin المسموحة لمسارات الويب (`/api/web/*` و`/webdb`).
///
/// الأصلُ موحَّد (الصفحة والـAPI من نفس المضيف) فلا CORS. لذلك:
///   * [allowedOrigins] فارغة (الافتراضي) = **نفس الأصل فقط**: يُقبل الطلب إن
///     لم يحمل ترويسة `Origin` (عميل غير متصفّح) أو كان `Origin` مطابقاً لترويسة
///     `Host` للطلب.
///   * غير فارغة = تُقبل كذلك أصولٌ مذكورة حرفياً (`https://erp.example.com`).
class WebOriginPolicy {
  WebOriginPolicy._();

  static Set<String> _allowed = <String>{};

  static Set<String> get allowedOrigins => Set.unmodifiable(_allowed);

  /// يضبط القائمة (يُطبَّع: أحرف صغيرة بلا `/` أخيرة).
  static void configure(Iterable<String> origins) {
    _allowed = {
      for (final o in origins)
        if (o.trim().isNotEmpty) _normalize(o),
    };
  }

  static String _normalize(String o) {
    var s = o.trim().toLowerCase();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// هل يُقبل [request] من حيث الأصل؟
  static bool isAllowed(Request request) {
    final origin = request.headers['origin'];
    if (origin == null) return true;
    final normalized = _normalize(origin);
    if (_allowed.contains(normalized)) return true;
    final uri = Uri.tryParse(normalized);
    final host = request.headers['host']?.toLowerCase();
    if (uri == null || !uri.hasAuthority || host == null || host.isEmpty) {
      return false;
    }
    final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    return authority == host;
  }
}

/// تذكرة WebSocket بعد استهلاكها.
class WebWsTicket {
  const WebWsTicket({
    required this.userId,
    required this.sid,
    required this.sessionExpiresAtMs,
  });

  final int userId;
  final String sid;

  /// انتهاء جلسة الويب الأصلية (تُغلق القناة عنده).
  final int sessionExpiresAtMs;
}

/// مخزن تذاكر أحاديّة الاستعمال في الذاكرة.
class WebWsTicketStore {
  WebWsTicketStore._();

  static const Duration ttl = Duration(seconds: 30);

  static final Map<String, _Entry> _tickets = {};

  /// تذكرة جديدة؛ [nowMs] قابل للحقن في الاختبار.
  static String issue(WebSessionClaims claims, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _tickets.removeWhere((_, e) => now >= e.expiresAtMs);
    final rnd = Random.secure();
    final ticket = base64Url
        .encode(List<int>.generate(32, (_) => rnd.nextInt(256)))
        .replaceAll('=', '');
    _tickets[ticket] = _Entry(
      WebWsTicket(
        userId: claims.userId,
        sid: claims.sid,
        sessionExpiresAtMs: claims.expiresAtMs,
      ),
      now + ttl.inMilliseconds,
    );
    return ticket;
  }

  /// يستهلك [ticket]: يرجع بياناتها مرةً واحدة فقط، ثم null (مستعملة/منتهية/
  /// مجهولة/جلستها أُلغيت أو انتهت).
  static WebWsTicket? consume(String? ticket, {int? nowMs}) {
    if (ticket == null || ticket.isEmpty) return null;
    final entry = _tickets.remove(ticket);
    if (entry == null) return null;
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (now >= entry.expiresAtMs) return null;
    final t = entry.ticket;
    if (now >= t.sessionExpiresAtMs || ApiSessionToken.isSidRevoked(t.sid)) {
      return null;
    }
    return t;
  }

  @visibleForTesting
  static void clear() => _tickets.clear();
}

class _Entry {
  _Entry(this.ticket, this.expiresAtMs);
  final WebWsTicket ticket;
  final int expiresAtMs;
}

/// معالج مساري `/api/web/session` و`/api/web/ws-ticket`.
class ApiWebSessionHandler {
  ApiWebSessionHandler(this._db);

  final AppDatabase _db;

  // نفس صيغة مفتاح `ApiAuthHandler` فيتقاسمان حصّة المحاولات الفاشلة.
  static String _userThrottleKey(String username) =>
      'u:${username.toLowerCase()}';

  /// `POST /api/web/session` — body: `{username, password}`.
  ///
  /// 200 → `{token, userId, displayName, roleName, permissionCodes,
  /// expiresInMs, isPostgres}`؛ 400 بيانات ناقصة؛ 401 اعتماد خاطئ؛ 429 قفل؛
  /// 503 مفتاح التوقيع غير جاهز.
  // EXEMPT-PER-USER: يُصدر الهوية بالاعتماد لا بجلسة قائمة.
  Future<Response> login(Request request) async {
    try {
      if (!ApiSessionToken.isReady) {
        return _error('Session auth not ready', 503);
      }
      final data = json.decode(await request.readAsString());
      if (data is! Map) return _error('JSON object required', 400);
      final username = (data['username'] as String?)?.trim();
      final password = data['password'] as String?;
      if (username == null ||
          username.isEmpty ||
          password == null ||
          password.isEmpty) {
        return _error('username+password required', 400);
      }

      final key = _userThrottleKey(username);
      if (ServerLoginThrottle.isLockedOut(key)) {
        return _error('Too many attempts, try again later', 429);
      }
      final result = await _db.authenticateUser(username, password);
      if (result == null) {
        ServerLoginThrottle.recordFailure(key);
        return _error('Invalid credentials', 401);
      }
      ServerLoginThrottle.recordSuccess(key);

      final codes = await _db.getUserPermissionCodes(result.user.id);
      return _ok({
        'token': ApiSessionToken.mintWeb(result.user.id),
        'userId': result.user.id,
        'username': result.user.username,
        'displayName': result.user.displayName,
        'roleId': result.user.roleId,
        'roleName': result.role?.name,
        // يلزم العميلَ لقرار تجاوز مدير النظام (AuthStateBypass).
        'roleIsSystem': result.role?.isSystemRole ?? false,
        'permissionCodes': codes,
        'expiresInMs': ApiSessionToken.webTtlMs,
        // يحدّد نمط SQL في عميل الويب (انظر lib/web/web_remote_connection.dart).
        'isPostgres': _db.isPostgres,
      });
    } catch (e) {
      debugPrint('[API] web login error: $e');
      return _error('Failed to issue web session', 500);
    }
  }

  /// `POST /api/web/ws-ticket` — الجلسة تُتحقَّق في `ApiAuthMiddleware`
  /// (ترويسة `X-Session-Token`)؛ يرجع `{ticket, expiresInMs}`.
  Future<Response> issueTicket(Request request) async {
    final claims = request.context[ApiWebCtx.claimsKey];
    if (claims is! WebSessionClaims) {
      return _error('Web session required', 401);
    }
    return _ok({
      'ticket': WebWsTicketStore.issue(claims),
      'expiresInMs': WebWsTicketStore.ttl.inMilliseconds,
    });
  }

  Response _ok(Map<String, dynamic> body) => Response.ok(
        json.encode(body),
        headers: {'content-type': 'application/json'},
      );

  Response _error(String message, int status) => Response(
        status,
        body: json.encode({'error': message}),
        headers: {'content-type': 'application/json'},
      );
}
