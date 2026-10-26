/// Kind-generic client of the desktop's pairing + sign-in routes over the
/// pinned LAN transport. The warehouse phone ([WarehouseLanClient]) and the
/// Cashier tablet share this protocol; only the device `kind` differs:
///   info  -> GET  /api/m1/info        (public; refuse a host without TLS)
///   pair  -> POST /api/pair           (one-time, branch-bound code + kind)
///   login -> POST /api/auth/session   (device bearer + user credentials)
/// The desktop decides the kind and the branch from the CODE, never from the
/// device; this client only echoes the kind it was built for.
library;

import 'api_error.dart';
import 'headers.dart';
import 'transport.dart';
import 'wh_contracts.dart';

/// What `POST /api/pair` returns.
class DevicePairingResult {
  const DevicePairingResult({
    required this.deviceId,
    required this.deviceToken,
    this.branchId,
    this.branchCode,
    this.terminalCode,
  });
  final String deviceId;
  final String deviceToken;
  final int? branchId;
  final String? branchCode;
  final String? terminalCode;
}

class DeviceLanClient {
  DeviceLanClient({
    required this.transport,
    required this.headers,
    required this.kind,
    this.credentials = const ApiCredentials(),
  });

  final ApiTransport transport;
  final ApiHeaderBuilder headers;

  /// `pos` | `warehouse` | `admin` ... as the desktop names the kind.
  final String kind;
  ApiCredentials credentials;

  Map<String, Object?> _object(ApiResponse r) {
    final j = r.json;
    if (j is! Map) throw const FormatException('response is not an object');
    return j.cast<String, Object?>();
  }

  Future<LanInfo> info() async => LanInfo.fromJson(_object(await transport
      .send(ApiRequest('GET', WhPaths.info, headers: headers.anonymous(json: false)))));

  /// Claims the one-time [code]. Keeps the device credentials on success.
  /// [requireBranch]: a branch device must come back bound to a branch.
  Future<DevicePairingResult> pair({
    required String code,
    required String deviceId,
    required String deviceName,
    bool requireBranch = true,
  }) async {
    final res = await transport.send(ApiRequest(
      'POST',
      WhPaths.pair,
      headers: headers.anonymous(),
      body: {
        'pairingCode': code,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceKind': kind,
      },
    ));
    final m = _object(res);
    final token = m['token'];
    final branch = m['branchId'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('pairing response incomplete');
    }
    if (requireBranch && branch is! num) {
      throw const FormatException('pairing response incomplete');
    }
    credentials = ApiCredentials(deviceId: deviceId, deviceToken: token);
    return DevicePairingResult(
      deviceId: deviceId,
      deviceToken: token,
      branchId: branch is num ? branch.toInt() : null,
      branchCode: m['branchCode'] as String?,
      terminalCode: m['terminalCode'] as String?,
    );
  }

  /// Signs the user in on this paired device; keeps the session token and
  /// returns the user id. The desktop refuses a user the device does not admit
  /// (`branch_access_denied`, `pos_access_denied`) with a 403 [ApiError].
  Future<int> login({required String username, required String password}) async {
    final res = await transport.send(ApiRequest(
      'POST',
      WhPaths.authSession,
      headers: headers.build(credentials, session: false),
      body: {'username': username, 'password': password},
    ));
    final m = _object(res);
    final token = m['token'];
    final uid = m['userId'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('session response incomplete');
    }
    credentials = credentials.copyWith(sessionToken: token);
    return uid is num ? uid.toInt() : 0;
  }

  /// Authenticated read with the device bearer (no user session): any 401
  /// device_revoked surfaces as an [ApiError] ([isRevoked]).
  Future<Object?> probe(String path) async => (await transport.send(
          ApiRequest('GET', path, headers: headers.build(credentials, session: false))))
      .json;

  /// Signs out locally (the desktop has no logout route for signed tokens).
  void signOut() => credentials = credentials.signedOut();

  /// Whether [e] means this device is no longer paired (wipe and re-pair).
  static bool isRevoked(Object e) =>
      e is ApiError && e.kind == ApiErrorKind.deviceRevoked;
}
