import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shelf/shelf.dart';

import 'api_session_token.dart';
import 'api_user_context.dart';
import 'api_web_session_handler.dart';
import 'lan_pairing_api_handler.dart';
import 'lan_pairing_service.dart';
import 'client_address.dart';
import 'path_prefix_match.dart';
import 'web_session_guard.dart';

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

  /// م3-7: مسارات الكتابة (وقراءاتها المرافقة) التي يفتحها المضيف لعميل الويب
  /// عبر [enableWebSessionWrites]. تشمل شاشات نطاق الويب فقط؛ مستبعدٌ عمداً:
  /// POS (`/api/shifts`, `/api/sales/held`…)، الطاولات/المطبخ (`/api/table-*`)،
  /// الإقران/الأجهزة (`/api/pair`, `/api/pos-terminals`, `/api/auth`)،
  /// النسخ الاحتياطي، المزامنة، التصنيع (مؤجّل) والحجوزات.
  /// البادئة تطابق بـ`startsWith` فـ`/api/sales` تشمل `/api/sales/return` إلخ؛
  /// ويُستثنى منها [webWriteDeniedPrefixes] (مسارات POS داخل `/api/sales`).
  static const List<String> webWritePrefixes = <String>[
    '/api/accounts',
    '/api/account-mappings',
    '/api/accounting-periods',
    '/api/activity-logs',
    '/api/attachments',
    '/api/branches',
    '/api/categories',
    '/api/commercial-papers',
    '/api/cost_centers',
    '/api/document-sequences',
    '/api/expenses',
    '/api/fiscal-years',
    '/api/fixed-assets',
    '/api/inventory',
    '/api/journals',
    '/api/landed-costs',
    '/api/offers',
    '/api/op-expenses',
    '/api/parties',
    '/api/party-groups',
    '/api/payments',
    '/api/permissions',
    '/api/price-list-items',
    '/api/price-lists',
    '/api/product-barcodes',
    '/api/product-units',
    '/api/products',
    '/api/purchase-orders',
    '/api/purchases',
    '/api/quotations',
    '/api/receipts',
    '/api/regions',
    '/api/role_permissions',
    '/api/roles',
    '/api/safes',
    '/api/sales',
    '/api/sales-orders',
    '/api/settings',
    '/api/stock-movements',
    '/api/units',
    '/api/user-branch-access',
    '/api/user-region-access',
    '/api/user-warehouse-access',
    '/api/users',
    '/api/vouchers',
    '/api/warehouses',
  ];

  /// مسارات تحت [webWritePrefixes] لا يقبلها رمزُ الويب أبداً: طلبات POS
  /// المعلّقة (`/api/sales/held` و`/api/sales/held-items`). تُفحص قبل المطابقة.
  static const List<String> webWriteDeniedPrefixes = <String>[
    '/api/sales/held',
  ];

  static bool _isWebSessionPath(String path) =>
      webSessionPrefixes.any(path.startsWith) &&
      !webWriteDeniedPrefixes.any(path.startsWith);

  /// يفتح [webWritePrefixes] لرمز جلسة الويب. يستدعيه المضيف عند تفعيل
  /// وضع الويب (م3-9)؛ يبقى الافتراضي فارغاً.
  static void enableWebSessionWrites() =>
      webSessionPrefixes = List<String>.of(webWritePrefixes);

  /// يُغلق مسارات الكتابة لرمز الويب (الافتراضي؛ عند تعطيل الوصول من المتصفح).
  static void disableWebSessionWrites() => webSessionPrefixes = <String>[];

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

  /// يتحقق من رمز حامل (جهاز مقترن أو الرمز القديم داخل نافذته) دون تسجيل
  /// الجهاز؛ يُستعمل لقناة `/ws` التي لا تمرّ بالميدلوير.
  static Future<bool> verifyCredential(String token, String deviceId) async {
    if (!_isAccepting) return false;
    final pairing = _pairingService;
    if (pairing != null &&
        await pairing.verifyDeviceToken(token: token, deviceId: deviceId)) {
      return true;
    }
    if (token == _activeToken) {
      return pairing == null || await pairing.legacyAllowed();
    }
    return false;
  }

  /// Get the currently active token (for sharing with clients via health check).
  static String? get activeToken => _activeToken;

  /// E-02 (§3.3): علمُ جاهزيةٍ مستقلٌّ عن الـbearer القديم. يُضبط في
  /// `startServer` بعد تهيئة `ServerSecrets` و`LanPairingService`، فيُقبل
  /// الجهازُ المقترنُ حتى حين لا يوجد `_activeToken` (انتهت نافذة الانتقال).
  /// الفشلُ يبقى مغلقاً: بلا `markReady` ولا `_activeToken` ⇒ 403.
  static bool _ready = false;

  static void markReady() => _ready = true;

  @visibleForTesting
  static void clearReady() => _ready = false;

  static bool get _isAccepting => _ready || _activeToken != null;

  /// معرّفُ مفتاح الجلسات للإعلان في `/api/health` (ليس سرًّا).
  static String? get sessionKeyId => ApiSessionToken.keyId;

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
          if (claims == null || !await WebSessionGuard.isValid(claims)) {
            return _json(401, 'Invalid or expired web session');
          }
          return innerHandler(request.change(context: {
            ApiUserCtx.userIdKey: claims.userId,
            ApiWebCtx.claimsKey: claims,
          }));
        }
        if (path.startsWith('/api/') &&
            !request.headers.containsKey('authorization') &&
            _isWebSessionPath(path)) {
          if (!WebOriginPolicy.isAllowed(request)) {
            return _json(403, 'Origin not allowed');
          }
          final claims = ApiSessionToken.verifyWeb(
            request.headers[ApiSessionToken.headerName],
          );
          // المستخدم عُطِّل/قُفل/حُذف أو تغيّر دوره ⇒ الرمز مرفوض (كاش ≤ 10 ث).
          if (claims == null || !await WebSessionGuard.isValid(claims)) {
            return _json(401, 'Invalid or expired web session');
          }
          // قراءة GET/HEAD برمز ويب: بوابة صلاحية صريحة (قائمة سماح + سياسة
          // الجداول نفسها كقناة /webdb) بدل فتحها لكلّ مستخدم نشط.
          if (request.method == 'GET' || request.method == 'HEAD') {
            final denied = await WebHttpReadGate.check(claims, path);
            if (denied != null) return _json(403, denied);
          }
          return innerHandler(request.change(context: {
            ApiUserCtx.userIdKey: claims.userId,
            ApiWebCtx.claimsKey: claims,
          }));
        }
        if (matchesAnyPathPrefix(path, _exemptPrefixes)) {
          return innerHandler(request);
        }
        if (!path.startsWith('/api/')) return innerHandler(request);
        if (!_isAccepting) {
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
        // عنوان الاتصال الفعلي (XFF/X-Real-IP/Host لا تُصدَّق من العميل).
        final ip = ClientAddress.of(request);

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
