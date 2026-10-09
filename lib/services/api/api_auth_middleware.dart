import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import 'api_session_token.dart';
import 'api_user_context.dart';
import 'api_web_session_handler.dart';
import 'lan_pairing_api_handler.dart';
import 'lan_pairing_service.dart';

/// API Authentication middleware for the embedded multi-device server.
///
/// Verifies per-device pairing tokens and, during migration, the old shared
/// token on every `/api/*` request (except health and pairing).
///
/// **Flow:**
/// 1. Server starts → loads a random install secret from secure storage
/// 2. Operator issues a one-time code at `/api/pair`
/// 3. Client stores its HMAC-derived token and sends it with its device id
/// 4. Middleware validates the paired device, or the legacy token in-window
///
/// **Exempt paths:** `/api/health`, `/cfd`, `/menu`, `/ws`
/// (and the web paths `/api/web/*` / `/webdb`, authenticated by web session/ticket)
class ApiAuthMiddleware {
  ApiAuthMiddleware._();

  /// The legacy shared token, retained only during the migration window.
  static String? _activeToken;
  static LanPairingService? _pairingService;

  static void setPairingService(LanPairingService service) {
    _pairingService = service;
  }

  static void clearPairingService() => _pairingService = null;

  /// Paths that do NOT require authentication.
  ///
  /// ⚠️ `/api/table-bill` — حسابُ الطاولة على هاتف الزبون (2026-09-12).
  /// الزبونُ ليس جهازاً مقترناً ولا مستخدماً، فلا حاملَ عنده يقدّمه. وبديلُ
  /// المصادقة **ثلاثةُ حرّاسٍ أخرى**: رايةٌ مطفأةٌ افتراضاً، وتوقيعُ HMAC على
  /// رقم الطاولة، ورمزُ جلسةٍ يموت بإغلاق الطلب تُشترَط فيه الكتابة. وهي
  /// **ليست** معفاةً من محدّد المعدّل — بخلاف `/menu` و`/cfd`.
  static const _exemptPrefixes = [
    '/api/health',
    '/api/pair',
    '/cfd',
    '/menu',
    '/ws',
    '/api/table-bill',
  ];

  /// مسارات /api/* (غير /api/web/*) التي تقبل **رمز جلسة ويب** في
  /// X-Session-Token بدل bearer الجهاز (م3-7: الكتابة عبر HTTP تُسجَّل هنا).
  /// فارغةٌ افتراضياً: لا يصل متصفّحُ الويب إلا إلى /api/web/* و/webdb.
  /// صلاحيات المستخدم تبقى مفحوصةً في كلّ معالج عبر ApiUserCtx.
  static List<String> webSessionPrefixes = <String>[];

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

  /// Create a shelf [Middleware] that validates paired or legacy credentials.
  static Middleware createMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final path = '/${request.url.path}';
        if (path == '/api/pair' && request.method == 'POST') {
          return LanPairingApiHandler.pair(request);
        }
        // ── الويب: /api/web/* و/webdb (القناة؛ لا تبدأ بـ/ws فلا يشملها
        // الإعفاء بالبادئة أدناه). فحصُ Origin أولاً، ثم رمزُ جلسة الويب.
        final isWebPath = path == '/webdb' || path.startsWith('/api/web/');
        if (isWebPath && !WebOriginPolicy.isAllowed(request)) {
          return _json(403, 'Origin not allowed');
        }
        if (path == '/webdb' || path == '/api/web/session') {
          // /webdb تتحقق من التذكرة بنفسها؛ /api/web/session يدخل بالاعتماد.
          return innerHandler(request);
        }
        if (path.startsWith('/api/web/') && path != '/api/web/session') {
          final claims = ApiSessionToken.verifyWeb(
            request.headers[ApiSessionToken.headerName],
          );
          if (claims == null) return _json(401, 'Invalid or expired web session');
          return innerHandler(request.change(context: {
            ApiUserCtx.userIdKey: claims.userId,
            ApiWebCtx.claimsKey: claims,
          }));
        }
        if (path.startsWith('/api/') &&
            !request.headers.containsKey('authorization') &&
            webSessionPrefixes.any(path.startsWith)) {
          if (!WebOriginPolicy.isAllowed(request)) {
            return _json(403, 'Origin not allowed');
          }
          final claims = ApiSessionToken.verifyWeb(
            request.headers[ApiSessionToken.headerName],
          );
          if (claims == null) return _json(401, 'Invalid or expired web session');
          return innerHandler(request.change(context: {
            ApiUserCtx.userIdKey: claims.userId,
            ApiWebCtx.claimsKey: claims,
          }));
        }
        for (final prefix in _exemptPrefixes) {
          if (path.startsWith(prefix) || path == prefix) return innerHandler(request);
        }
        if (!path.startsWith('/api/')) return innerHandler(request);
        if (_activeToken == null) {
          return _json(403, 'Server not accepting API requests');
        }

        final authHeader = request.headers['authorization'];
        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return _json(401, 'Missing or invalid Authorization header');
        }
        final token = authHeader.substring(7);
        final pairing = _pairingService;
        final deviceId = request.headers['x-device-id'] ?? '';
        final deviceName = request.headers['x-device-name'] ?? '';
        final ip = request.headers['x-forwarded-for']?.split(',').first.trim() ??
            request.headers['x-real-ip'] ??
            request.headers['host']?.split(':').first ??
            'unknown';

        if (pairing != null &&
            await pairing.verifyDeviceToken(token: token, deviceId: deviceId)) {
          await pairing.recordSeen(deviceId: deviceId, name: deviceName, ip: ip);
        } else if (token == _activeToken) {
          if (pairing != null) {
            if (!await pairing.legacyAllowed()) {
              return _json(403, 'انتهت فترة المفتاح القديم. يجب إقران هذا الجهاز أولاً.');
            }
            await pairing.recordLegacyDevice(
              deviceId: deviceId,
              name: deviceName,
              ip: ip,
            );
          }
        } else {
          return _json(403, 'Invalid API token');
        }

        // The signed session token remains the user-identity layer.
        final uid = ApiSessionToken.verify(
          request.headers[ApiSessionToken.headerName],
        );
        Request enriched = request.change(context: {
          if (deviceId.isNotEmpty) 'lanDeviceId': deviceId,
          if (deviceName.isNotEmpty) 'lanDeviceName': deviceName,
        });
        if (uid != null) {
          enriched = enriched.change(context: {ApiUserCtx.userIdKey: uid});
        }
        return innerHandler(enriched);
      };
    };
  }

  static Response _json(int status, String error) => Response(
        status,
        body: jsonEncode({'error': error}),
        headers: {'content-type': 'application/json'},
      );
}
