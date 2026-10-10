import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../service/admin_service.dart';
import '../service/desktop_service.dart';
import '../service/errors.dart';

/// M-1 routes of «PicPos إدارة» (ARCHITECTURE-M §2.2/§2.3, read-only part):
/// `/desktop/link/signing-key`, `/desktop/users`, `/desktop/snapshots`,
/// `/desktop/admin-pairing-codes`, `/desktop/admin-devices` and
/// `/manage/pair|login|snapshots`.
void mountAdminRoutes(
  Router r, {
  required AdminService admin,
  required Future<DesktopContext> Function(Request) desktop,
}) {
  Future<AdminContext> device(Request req, {bool allowRevoked = false}) {
    final authz = req.headers['authorization'] ?? '';
    final bearer = authz.startsWith('Bearer ') ? authz.substring(7).trim() : null;
    return admin.authenticateDevice(bearer, req.headers['x-device-id'], ip: _ip(req), allowRevoked: allowRevoked);
  }

  // ── desktop ──
  r.post('/desktop/link/signing-key', (Request req) async {
    final d = await desktop(req);
    await admin.setSigningKey(d, await _body(req));
    return Response(204);
  });
  r.post('/desktop/users', (Request req) async {
    final d = await desktop(req);
    return _json(200, await admin.upsertUsers(d, (await _body(req))['users']));
  });
  r.post('/desktop/snapshots', (Request req) async {
    final d = await desktop(req);
    return _json(200, await admin.storeSnapshots(d, (await _body(req))['items']));
  });
  r.post('/desktop/admin-pairing-codes', (Request req) async {
    final d = await desktop(req);
    final gid = (await _body(req))['userGlobalId'];
    if (gid is! String || gid.isEmpty) throw ApiError(400, 'user_global_id_required');
    final res = await admin.issuePairingCode(d, gid);
    return _json(201, {'code': res.code, 'expiresAt': res.expiresAt});
  });
  r.get('/desktop/admin-devices', (Request req) async {
    final d = await desktop(req);
    return _json(200, {'devices': await admin.listDevices(d)});
  });
  r.post('/desktop/admin-devices/<deviceId>/revoke', (Request req, String deviceId) async {
    final d = await desktop(req);
    await admin.revokeDevice(d, deviceId);
    return _json(200, {'revoked': deviceId});
  });

  // ── «PicPos إدارة» ──
  r.post('/manage/pair', (Request req) async {
    final b = await _body(req);
    return _json(
        200,
        await admin.pair(
          code: '${b['code'] ?? ''}',
          deviceId: '${b['deviceId'] ?? ''}',
          deviceName: b['deviceName'] as String?,
          appVersion: b['appVersion'] as String?,
          ip: _ip(req),
        ));
  });
  r.post('/manage/login', (Request req) async {
    final a = await device(req);
    final b = await _body(req);
    return _json(200, await admin.login(a, '${b['username'] ?? ''}', '${b['password'] ?? ''}'));
  });
  r.post('/manage/logout', (Request req) async {
    final a = await device(req);
    final token = req.headers['x-session-token'];
    await admin.requireSession(a, token);
    await admin.logout(a, token);
    return Response(204);
  });
  r.post('/manage/unpair', (Request req) async {
    await admin.unpairDevice(await device(req, allowRevoked: true));
    return Response(204);
  });
  r.get('/manage/snapshots', (Request req) async {
    final a = await device(req);
    final u = await admin.requireSession(a, req.headers['x-session-token']);
    final q = req.url.queryParameters;
    final kinds = q['kinds']?.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    final branch = q['branch'] == null || q['branch']!.isEmpty ? null : int.tryParse(q['branch']!);
    if (q['branch'] != null && q['branch']!.isNotEmpty && branch == null) throw ApiError(400, 'invalid_branch');
    return _json(200, await admin.snapshots(a, u, kinds: kinds, branch: branch));
  });
}

String _ip(Request req) {
  final info = req.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
}

Future<Map<String, Object?>> _body(Request req) async {
  try {
    final v = jsonDecode(await req.readAsString());
    if (v is Map) return v.cast<String, Object?>();
  } catch (_) {}
  throw ApiError(400, 'invalid_json');
}

Response _json(int status, Object body) =>
    Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json; charset=utf-8'});
