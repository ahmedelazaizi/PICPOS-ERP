import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'lan_pairing_service.dart';

/// Small route handler kept outside the API god-file.
class LanPairingApiHandler {
  LanPairingApiHandler._();

  static LanPairingService? _service;

  static void setService(LanPairingService service) => _service = service;
  static void clearService() => _service = null;

  static Future<Response> pair(Request request) async {
    final pairing = _service;
    if (pairing == null) {
      return _json(503, {'error': 'إقران الأجهزة غير متاح على هذا الخادم'});
    }
    final body = await _decodeBody(request);
    if (body == null || body is! Map) {
      return _json(400, {'error': 'بيانات الإقران غير صالحة'});
    }
    final result = await pairing.pair(
      code: '${body['pairingCode'] ?? body['code'] ?? ''}',
      deviceId: '${body['deviceId'] ?? ''}',
      deviceName: '${body['deviceName'] ?? body['name'] ?? ''}',
      ip: _clientIp(request),
    );
    switch (result.status) {
      case LanPairingStatus.success:
        return _json(200, {'token': result.token, 'deviceId': result.deviceId});
      case LanPairingStatus.rateLimited:
        return _json(429, {'error': 'تم تجاوز محاولات الإقران؛ أعد المحاولة بعد 10 دقائق'});
      case LanPairingStatus.invalidDevice:
        return _json(400, {'error': 'معرّف الجهاز مطلوب'});
      case LanPairingStatus.invalidCode:
        return _json(401, {'error': 'رمز الإقران غير صحيح أو منتهي'});
    }
  }

  static Future<Object?> _decodeBody(Request request) async {
    try {
      return jsonDecode(await request.readAsString());
    } on FormatException {
      return null;
    }
  }

  static Response _json(int status, Map<String, dynamic> body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );

  static String _clientIp(Request request) =>
      (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
          ?.remoteAddress.address ??
      'unknown';
}
