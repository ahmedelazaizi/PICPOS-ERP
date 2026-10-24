import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'lan_pairing_authz.dart' show kPairableDeviceKinds;
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
    final parsed = await _parsePairingRequest(request);
    if (parsed.error != null) return parsed.error!;
    final result = await pairing.pair(parsed.request!);
    return _pairingResponse(result);
  }

  static Future<({LanPairingRequest? request, Response? error})>
  _parsePairingRequest(Request request) async {
    final body = await _decodeBody(request);
    if (body == null || body is! Map) return _invalidPairingBody();
    final options = _pairingOptions(body);
    if (options.error != null) return (request: null, error: options.error);
    return (
      request: LanPairingRequest(
        code: '${body['pairingCode'] ?? body['code'] ?? ''}',
        deviceId: '${body['deviceId'] ?? ''}',
        deviceName: '${body['deviceName'] ?? body['name'] ?? ''}',
        ip: _clientIp(request),
        deviceKind: options.kind,
        branchId: options.branchId,
      ),
      error: null,
    );
  }

  static ({String? kind, int? branchId, Response? error}) _pairingOptions(
    Map body,
  ) {
    final kind = body['deviceKind'];
    if (kind != null && !kPairableDeviceKinds.contains(kind)) {
      return (
        kind: null,
        branchId: null,
        error: _json(400, {'error': 'نوع الجهاز غير صالح'}),
      );
    }
    final branchId = _parseBranchId(body['branchId']);
    if (body['branchId'] != null && branchId == null) {
      return (
        kind: null,
        branchId: null,
        error: _json(400, {
          'error': 'معرّف الفرع يجب أن يكون رقماً صحيحاً موجباً',
        }),
      );
    }
    return (kind: kind as String?, branchId: branchId, error: null);
  }

  static ({LanPairingRequest? request, Response? error})
  _invalidPairingBody() =>
      (request: null, error: _json(400, {'error': 'بيانات الإقران غير صالحة'}));

  static Response _pairingResponse(LanPairingResult result) {
    if (result.status == LanPairingStatus.success) {
      return _successResponse(result);
    }
    final failure = _pairingError(result.status);
    return _json(failure.status, {'error': failure.message});
  }

  static Response _successResponse(LanPairingResult result) {
    final Map<String, dynamic> body = {
      'token': result.token,
      'deviceId': result.deviceId,
    };
    // The kinds introduced with M1 echo themselves; the older kinds' response
    // shape is unchanged.
    if (result.deviceKind == 'client' || result.deviceKind == 'mirror') {
      body['deviceKind'] = result.deviceKind;
    }
    if (result.branchId != null) {
      body.addAll({
        'branchId': result.branchId,
        'branchCode': result.branchCode,
        'terminalCode': result.terminalCode,
      });
    }
    return _json(200, body);
  }

  static ({int status, String message}) _pairingError(
    LanPairingStatus status,
  ) => switch (status) {
    LanPairingStatus.rateLimited => (
      status: 429,
      message: 'تم تجاوز محاولات الإقران؛ أعد المحاولة بعد 10 دقائق',
    ),
    LanPairingStatus.invalidDevice => (
      status: 400,
      message: 'معرّف الجهاز مطلوب',
    ),
    LanPairingStatus.invalidCode => (
      status: 401,
      message: 'رمز الإقران غير صحيح أو منتهي',
    ),
    LanPairingStatus.branchRequired => (
      status: 400,
      message: 'معرّف الفرع مطلوب لإقران جهاز POS',
    ),
    LanPairingStatus.branchUnavailable => (
      status: 404,
      message: 'الفرع غير موجود أو غير نشط',
    ),
    LanPairingStatus.branchCodeUnavailable => (
      status: 409,
      message: 'لا يمكن إقران جهاز POS بفرع دون رمز',
    ),
    LanPairingStatus.kindMismatch => (
      status: 401,
      message: 'رمز الإقران لا يخصّ هذا النوع من الأجهزة',
    ),
    LanPairingStatus.success => throw StateError(
      'Success has no pairing error',
    ),
  };

  static int? _parseBranchId(Object? value) {
    if (value is int) return value > 0 ? value : null;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      final parsed = value.toInt();
      return parsed > 0 ? parsed : null;
    }
    return null;
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
          ?.remoteAddress
          .address ??
      'unknown';
}
