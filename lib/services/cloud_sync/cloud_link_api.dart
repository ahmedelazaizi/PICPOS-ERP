import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';

/// The desktop's credential on the cloud API (I-3): a link id + secret issued
/// for the company (only the secret's SHA-256 is stored server-side).
class CloudLinkCredentials {
  const CloudLinkCredentials({
    required this.baseUrl,
    required this.linkId,
    required this.secret,
  });

  final String baseUrl;
  final String linkId;
  final String secret;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      linkId.trim().isNotEmpty &&
      secret.trim().isNotEmpty;
}

/// A cloud call failed: HTTP status + the API error code (or a transport
/// error with status 0).
class CloudLinkException implements Exception {
  CloudLinkException(this.status, this.code, [this.message]);
  final int status;
  final String code;
  final String? message;

  @override
  String toString() =>
      'CloudLinkException($status, $code${message == null ? '' : ', $message'})';
}

/// HTTP client of the cloud `/desktop/*` endpoints
/// (server/lib/src/service/desktop_service.dart).
class CloudLinkApi {
  CloudLinkApi(this.credentials,
      {http.Client? client, this.timeout = const Duration(seconds: 30)})
      : _client = client ?? http.Client();

  final CloudLinkCredentials credentials;
  final http.Client _client;
  final Duration timeout;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = credentials.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'authorization': 'Bearer ${credentials.secret.trim()}',
        'x-desktop-link': credentials.linkId.trim(),
        'content-type': 'application/json; charset=utf-8',
      };

  Future<Map<String, dynamic>> _send(String method, String path,
      {Object? body, Map<String, String>? query}) async {
    final http.Response res;
    try {
      final req = http.Request(method, _uri(path, query))
        ..headers.addAll(_headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(
          await _client.send(req).timeout(timeout));
    } catch (e) {
      throw CloudLinkException(0, 'network_error', '$e');
    }
    Map<String, dynamic> json;
    try {
      final v = jsonDecode(utf8.decode(res.bodyBytes));
      json = v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    } catch (_) {
      json = <String, dynamic>{};
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw CloudLinkException(res.statusCode,
          '${json['error'] ?? 'http_${res.statusCode}'}', json['message'] as String?);
    }
    return json;
  }

  /// Test connection: company + pending counts on the cloud.
  Future<Map<String, dynamic>> ping() => _send('GET', '/desktop/ping');

  Future<Map<String, dynamic>> pushMaster(Map<String, Object?> batch) =>
      _send('POST', '/desktop/master', body: batch);

  Future<List<Map<String, dynamic>>> pendingDocuments({int limit = 100}) async {
    final b = await _send('GET', '/desktop/documents/pending',
        query: {'limit': '$limit'});
    return [
      for (final d in (b['documents'] as List? ?? const []))
        if (d is Map) d.cast<String, dynamic>(),
    ];
  }

  Future<List<Map<String, dynamic>>> ack(
      List<Map<String, Object?>> results) async {
    if (results.isEmpty) return const [];
    final b =
        await _send('POST', '/desktop/documents/ack', body: {'results': results});
    return [
      for (final r in (b['results'] as List? ?? const []))
        if (r is Map) r.cast<String, dynamic>(),
    ];
  }

  /// Registers the desktop's pinned Ed25519 public key for admin snapshots.
  Future<void> pushAdminSigningKey(String publicKey) async {
    await _send('POST', '/desktop/link/signing-key',
        body: {'publicKey': publicKey, 'decimals': AppConstants.decimalPlaces});
  }

  /// SEC-017: registers a NEW signing key and revokes every paired admin phone
  /// of the company in one call. Returns the number of devices revoked.
  Future<int> rotateAdminSigningKey(String publicKey) async {
    final b = await _send('POST', '/desktop/link/rotate-signing-key',
        body: {'publicKey': publicKey});
    return (b['revokedDevices'] as num?)?.toInt() ?? 0;
  }

  /// Mirrors every desktop user, including disabled users for revocation.
  Future<Map<String, dynamic>> pushAdminUsers(
          List<Map<String, Object?>> users) =>
      _send('POST', '/desktop/users', body: {'users': users});

  /// Publishes signed read-only admin snapshots.
  Future<Map<String, dynamic>> pushAdminSnapshots(
          List<Map<String, Object?>> items) =>
      _send('POST', '/desktop/snapshots', body: {'items': items});

  Future<Map<String, dynamic>> adminPairingCode(String userGlobalId) =>
      _send('POST', '/desktop/admin-pairing-codes',
          body: {'userGlobalId': userGlobalId});

  Future<List<Map<String, dynamic>>> adminDevices() async {
    final response = await _send('GET', '/desktop/admin-devices');
    return [
      for (final device in response['devices'] as List? ?? const [])
        if (device is Map) device.cast<String, dynamic>(),
    ];
  }

  Future<void> revokeAdminDevice(String deviceId) async {
    await _send('POST',
        '/desktop/admin-devices/${Uri.encodeComponent(deviceId)}/revoke');
  }

  /// Issues a rep pairing code (and sets the rep's app PIN when given).
  Future<Map<String, dynamic>> pairingCode(String employeeGlobalId,
          {String? pin}) =>
      _send('POST', '/desktop/pairing-codes', body: {
        'employeeGlobalId': employeeGlobalId,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
      });

  /// Rep-app devices paired on this company (`GET /desktop/devices`).
  Future<List<Map<String, dynamic>>> devices() async {
    final b = await _send('GET', '/desktop/devices');
    return [
      for (final d in (b['devices'] as List? ?? const []))
        if (d is Map) d.cast<String, dynamic>(),
    ];
  }

  /// Revokes one rep-app device of this company.
  Future<void> revokeDevice(String deviceId) => _send(
      'POST', '/desktop/devices/${Uri.encodeComponent(deviceId)}/revoke');

  void close() => _client.close();
}
