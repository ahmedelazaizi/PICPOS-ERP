import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:picpos_api_client/picpos_api_client.dart' show UrlPolicy, UrlPolicyException;

class CloudApiException implements Exception {
  CloudApiException(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => 'CloudApiException($status, $code)';
}

class DeviceCredentials {
  DeviceCredentials({required this.baseUrl, required this.deviceId, required this.deviceToken});
  final String baseUrl;
  final String deviceId;
  final String deviceToken;
}

/// Contract of the cloud API (server/README.md).
abstract class CloudApi {
  Future<({String deviceToken, String employeeGlobalId})> pair(
      String baseUrl, String code, String deviceId, String deviceName);
  Future<String> login(DeviceCredentials c, String pin);

  /// `POST /mobile/token/rotate` → new device token (the old one stays valid
  /// until the new one is first used, so a lost response is harmless).
  Future<String> rotateToken(DeviceCredentials c);
  Future<Map<String, dynamic>> bootstrap(DeviceCredentials c, String session);
  Future<Map<String, dynamic>> pull(DeviceCredentials c, String session, int since);
  Future<List<Map<String, dynamic>>> push(
      DeviceCredentials c, String session, List<Map<String, Object?>> documents);
}

class HttpCloudApi implements CloudApi {
  /// [policy] defaults to HTTPS-only in release builds (M-1); debug/test builds
  /// also allow plain HTTP to the emulator host, loopback and the 192.168/16 LAN.
  HttpCloudApi([http.Client? client, UrlPolicy? policy])
      : _client = client ?? http.Client(),
        _policy = policy ?? (kReleaseMode ? UrlPolicy.release : UrlPolicy.development);
  final http.Client _client;
  final UrlPolicy _policy;

  /// Parses and vets a request URL; Dart's HttpClient ignores Android's
  /// network-security-config, so this is the enforcement point.
  Uri _uri(String url) {
    final uri = Uri.parse(url);
    try {
      _policy.check(uri);
    } on UrlPolicyException {
      throw CloudApiException(0, 'url_not_allowed');
    }
    return uri;
  }
  static const _timeout = Duration(seconds: 20);

  Map<String, String> _h(DeviceCredentials c, [String? session]) => {
        'content-type': 'application/json',
        'authorization': 'Bearer ${c.deviceToken}',
        'x-device-id': c.deviceId,
        'x-session-token': ?session,
      };

  Future<Map<String, dynamic>> _decode(http.Response r) async {
    final body = r.body.isEmpty ? <String, dynamic>{} : (jsonDecode(r.body) as Map).cast<String, dynamic>();
    if (r.statusCode != 200) throw CloudApiException(r.statusCode, '${body['error'] ?? 'http_${r.statusCode}'}');
    return body;
  }

  @override
  Future<({String deviceToken, String employeeGlobalId})> pair(
      String baseUrl, String code, String deviceId, String deviceName) async {
    final r = await _client
        .post(_uri('$baseUrl/mobile/pair'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'code': code, 'deviceId': deviceId, 'deviceName': deviceName}))
        .timeout(_timeout);
    final b = await _decode(r);
    return (deviceToken: b['deviceToken'] as String, employeeGlobalId: b['employeeGlobalId'] as String);
  }

  @override
  Future<String> login(DeviceCredentials c, String pin) async {
    final r = await _client
        .post(_uri('${c.baseUrl}/mobile/login'), headers: _h(c), body: jsonEncode({'pin': pin}))
        .timeout(_timeout);
    return (await _decode(r))['sessionToken'] as String;
  }

  @override
  Future<String> rotateToken(DeviceCredentials c) async {
    final r = await _client.post(_uri('${c.baseUrl}/mobile/token/rotate'), headers: _h(c)).timeout(_timeout);
    return (await _decode(r))['deviceToken'] as String;
  }

  @override
  Future<Map<String, dynamic>> bootstrap(DeviceCredentials c, String session) async =>
      _decode(await _client.get(_uri('${c.baseUrl}/mobile/bootstrap'), headers: _h(c, session)).timeout(_timeout));

  @override
  Future<Map<String, dynamic>> pull(DeviceCredentials c, String session, int since) async => _decode(await _client
      .get(_uri('${c.baseUrl}/mobile/sync/pull?since=$since'), headers: _h(c, session))
      .timeout(_timeout));

  @override
  Future<List<Map<String, dynamic>>> push(
      DeviceCredentials c, String session, List<Map<String, Object?>> documents) async {
    final b = await _decode(await _client
        .post(_uri('${c.baseUrl}/mobile/sync/push'),
            headers: _h(c, session), body: jsonEncode({'documents': documents}))
        .timeout(_timeout));
    return (b['results'] as List).cast<Map<String, dynamic>>();
  }
}
