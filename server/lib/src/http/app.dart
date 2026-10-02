import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/database.dart';
import '../security.dart';
import '../service/auth_service.dart';
import '../service/errors.dart';
import '../service/rate_limiter.dart';
import '../service/sync_service.dart';
import '../whatsapp/whatsapp.dart';

/// HTTP surface of the cloud API (I-1 + I-2). Header conventions follow the desktop
/// LAN API: `Authorization: Bearer <device token>`, `X-Device-Id`,
/// `X-Session-Token`.
class CloudApp {
  CloudApp({
    required this.db,
    required this.auth,
    required this.sync,
    required this.outbox,
    required this.adminKey,
    RateLimiter? pushLimiter,
  }) : pushLimiter = pushLimiter ?? RateLimiter(max: 60, window: const Duration(minutes: 1));

  final CloudDatabase db;
  final AuthService auth;
  final SyncService sync;
  final WhatsAppOutbox outbox;

  /// Test-stack admin key (production admin flows come from desktop, I-3).
  final String adminKey;

  /// 60 pushes per device per minute (ARCHITECTURE-I §11).
  final RateLimiter pushLimiter;

  Handler get handler => const Pipeline()
      .addMiddleware(_errors())
      .addHandler(_router().call);

  Router _router() {
    final r = Router();

    r.get('/health', (Request req) async {
      try {
        await db.query('SELECT 1');
        return _json(200, {'status': 'ok', 'db': 'ok', 'whatsappProvider': outbox.provider.name});
      } catch (e) {
        return _json(503, {'status': 'degraded', 'db': 'down'});
      }
    });

    // ── admin (test stack) ──
    r.post('/admin/pairing-codes', (Request req) async {
      _requireAdmin(req);
      final body = await _body(req);
      final company = await db.query('SELECT id FROM companies WHERE global_id=@g',
          {'g': body['companyGlobalId']});
      if (company.isEmpty) throw ApiError(404, 'company_not_found');
      final res = await auth.issuePairingCode(
          companyId: company.first[0] as int, employeeGlobalId: '${body['employeeGlobalId']}');
      return _json(201, {'code': res.code, 'expiresAt': res.expiresAt});
    });
    r.post('/admin/devices/<deviceId>/revoke', (Request req, String deviceId) async {
      _requireAdmin(req);
      await auth.revokeDevice(deviceId, ip: _ip(req), reason: 'admin');
      return _json(200, {'revoked': deviceId});
    });
    r.get('/admin/whatsapp/outbox', (Request req) async {
      _requireAdmin(req);
      final rows = await db.query(
          'SELECT id, to_phone, template, params, status, attempts, provider_message_id, document_global_id '
          'FROM whatsapp_outbox ORDER BY id DESC LIMIT 100');
      return _json(200, {'messages': [for (final x in rows) x.toColumnMap()]});
    });
    r.post('/admin/whatsapp/process', (Request req) async {
      _requireAdmin(req);
      return _json(200, {'processed': await outbox.processDue()});
    });

    // ── mobile ──
    r.post('/mobile/pair', (Request req) async {
      final b = await _body(req);
      final res = await auth.pair(
        code: '${b['code'] ?? ''}',
        deviceId: '${b['deviceId'] ?? ''}',
        deviceName: b['deviceName'] as String?,
        ip: _ip(req),
      );
      return _json(200, {
        'deviceToken': res.deviceToken,
        'deviceId': res.deviceId,
        'employeeGlobalId': res.employeeGlobalId,
      });
    });
    r.post('/mobile/login', (Request req) async {
      final d = await _device(req);
      final b = await _body(req);
      final token = await auth.login(d, '${b['pin'] ?? ''}');
      return _json(200, {'sessionToken': token});
    });
    r.post('/mobile/token/rotate', (Request req) async {
      final d = await _device(req);
      return _json(200, {'deviceToken': await auth.rotateToken(d), 'deviceId': d.deviceId});
    });
    r.get('/mobile/bootstrap', (Request req) async {
      final d = await _session(req);
      return _json(200, await sync.bootstrap(d));
    });
    r.get('/mobile/sync/pull', (Request req) async {
      final d = await _session(req);
      final since = int.tryParse(req.url.queryParameters['since'] ?? '0') ?? 0;
      return _json(200, await sync.pull(d, since: since));
    });
    r.post('/mobile/sync/push', (Request req) async {
      final d = await _session(req);
      pushLimiter.hit(d.deviceId);
      final b = await _body(req);
      final docs = b['documents'];
      if (docs is! List || docs.length > 50) throw ApiError(400, 'documents_required_max_50');
      return _json(200, {'results': await sync.push(d, docs)});
    });

    r.all('/<ignored|.*>', (Request req) => _json(404, {'error': 'not_found'}));
    return r;
  }

  void _requireAdmin(Request req) {
    final k = req.headers['x-admin-key'];
    if (adminKey.isEmpty || k == null || !constantTimeEquals(k, adminKey)) {
      throw ApiError(401, 'admin_key_required');
    }
  }

  Future<DeviceContext> _device(Request req) {
    final authz = req.headers['authorization'] ?? '';
    final bearer = authz.startsWith('Bearer ') ? authz.substring(7).trim() : null;
    return auth.authenticateDevice(bearer, req.headers['x-device-id'], ip: _ip(req));
  }

  Future<DeviceContext> _session(Request req) async {
    final d = await _device(req);
    auth.requireSession(d, req.headers['x-session-token']);
    return d;
  }

  static String _ip(Request req) {
    final info = req.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
  }

  static Future<Map<String, Object?>> _body(Request req) async {
    try {
      final v = jsonDecode(await req.readAsString());
      if (v is Map) return v.cast<String, Object?>();
    } catch (_) {}
    throw ApiError(400, 'invalid_json');
  }

  static Response _json(int status, Object body, [Map<String, String> extra = const {}]) => Response(status,
      body: jsonEncode(body), headers: {'content-type': 'application/json; charset=utf-8', ...extra});

  static Middleware _errors() => (inner) => (req) async {
        try {
          return await inner(req);
        } on ApiError catch (e) {
          return _json(e.status, e.toJson(),
              {if (e.retryAfterSeconds != null) 'retry-after': '${e.retryAfterSeconds}'});
        } catch (e, st) {
          stderr.writeln('[api] ${req.method} ${req.requestedUri.path}: $e\n$st');
          return _json(500, {'error': 'internal_error'});
        }
      };
}
