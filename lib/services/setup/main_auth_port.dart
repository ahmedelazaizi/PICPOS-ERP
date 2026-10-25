// A1 / P4 (users plan B.7.3): the device side of "verify the first user ON THE
// MAIN". Three calls against the main, authenticated by this device's own
// bearer (its pairing token) - no shared key, no pairing window:
//   POST /api/auth/session          user + password  -> signed session
//   POST /api/auth/change-password  temporary password -> new password + session
//   GET  /api/users  (X-Session-Token)  -> that branch's users WITH credentials
//
// A narrow port so the verifier is tested without a network; [HttpMainAuthPort]
// is the production / integration (real in-process host) implementation.
library;

import 'dart:convert';
import 'dart:io';

import '../device_identity_service.dart';
import '../network_service.dart';
import '../server_proxy.dart';
import '../tls_trust.dart';

enum MainAuthOutcome {
  ok,
  invalidCredentials,
  passwordChangeRequired,
  branchDenied,
  mirrorConsoleDenied,
  lockedOut,
  passwordRejected,
  passwordPolicy,
  offline,
  error,
}

class MainSession {
  const MainSession(this.outcome, {this.token, this.userId, this.detail});
  final MainAuthOutcome outcome;
  final String? token;
  final int? userId;
  final String? detail;
  bool get ok => outcome == MainAuthOutcome.ok;
}

abstract interface class MainAuthPort {
  Future<MainSession> createSession(String username, String password);

  Future<MainSession> changePassword(
      String username, String currentPassword, String newPassword);

  /// `GET /api/users` as the session's owner; `null` when it failed.
  Future<Map<String, dynamic>?> fetchUsers(String sessionToken);
}

class HttpMainAuthPort implements MainAuthPort {
  HttpMainAuthPort({
    required this.baseUrl,
    required this.deviceToken,
    this.deviceId,
    this.deviceName,
  });

  /// The runtime wiring: the paired server + this device's token / id.
  factory HttpMainAuthPort.fromRuntime() => HttpMainAuthPort(
        baseUrl: NetworkService.instance.buildServerUrl(),
        deviceToken: ServerProxy.instance.apiToken ?? '',
        deviceId: DeviceIdentityService.instance.tryGetDeviceId(),
      );

  final String baseUrl;
  final String deviceToken;
  final String? deviceId;
  final String? deviceName;

  @override
  Future<MainSession> createSession(String username, String password) async {
    final r = await _send('POST', '/api/auth/session',
        body: {'username': username, 'password': password});
    return _session(r);
  }

  @override
  Future<MainSession> changePassword(
      String username, String currentPassword, String newPassword) async {
    final r = await _send('POST', '/api/auth/change-password', body: {
      'username': username,
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
    return _session(r);
  }

  @override
  Future<Map<String, dynamic>?> fetchUsers(String sessionToken) async {
    final r = await _send('GET', '/api/users', session: sessionToken);
    return r.status == 200 ? r.json : null;
  }

  MainSession _session(_Resp r) {
    final code = r.json['code'] as String?;
    if (r.status == 200) {
      return MainSession(MainAuthOutcome.ok,
          token: r.json['token'] as String?,
          userId: (r.json['userId'] as num?)?.toInt());
    }
    final outcome = switch ((r.status, code)) {
      (0, _) => MainAuthOutcome.offline,
      (401, _) => MainAuthOutcome.invalidCredentials,
      (403, 'password_change_required') => MainAuthOutcome.passwordChangeRequired,
      (403, 'branch_access_denied') => MainAuthOutcome.branchDenied,
      (403, 'mirror_console_denied') => MainAuthOutcome.mirrorConsoleDenied,
      (429, _) => MainAuthOutcome.lockedOut,
      (409, _) => MainAuthOutcome.passwordRejected,
      (400, 'password_too_short' || 'password_same_as_current' ||
          'password_same_as_username') =>
        MainAuthOutcome.passwordPolicy,
      _ => MainAuthOutcome.error,
    };
    return MainSession(outcome, detail: '${r.status} ${code ?? ''}');
  }

  Future<_Resp> _send(String method, String path,
      {Map<String, dynamic>? body, String? session}) async {
    final client = TlsTrust.ioClientTofu(
      connectionTimeout: const Duration(seconds: 15),
      onFirstUse: (_, _, _) {},
    );
    try {
      final req = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      req.headers.contentType = ContentType.json;
      if (deviceToken.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $deviceToken');
      }
      if ((deviceId ?? '').isNotEmpty) req.headers.set('X-Device-Id', deviceId!);
      if ((deviceName ?? '').isNotEmpty) {
        req.headers.set('X-Device-Name', deviceName!);
      }
      if (session != null) req.headers.set('X-Session-Token', session);
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      Map<String, dynamic> json = const {};
      try {
        final d = text.isEmpty ? null : jsonDecode(text);
        if (d is Map<String, dynamic>) json = d;
      } catch (_) {}
      return _Resp(res.statusCode, json);
    } on SocketException {
      return const _Resp(0, {});
    } on HandshakeException {
      return const _Resp(0, {});
    } catch (_) {
      return const _Resp(-1, {});
    } finally {
      client.close(force: true);
    }
  }
}

class _Resp {
  const _Resp(this.status, this.json);
  final int status;
  final Map<String, dynamic> json;
}
