/// Client of the desktop's warehouse-app routes over the pinned LAN transport.
///
/// The transport must be an `HttpApiTransport` built on
/// `createPinnedLanClient(fingerprint)`; this class only speaks the protocol:
///   pair -> POST /api/pair            (one-time code, kind `warehouse`)
///   login -> POST /api/auth/session   (device bearer + user credentials)
///   session / items -> GET /api/m1/wh/*  (device bearer + session token)
/// Document operations (W2-W5) live in `wh_client_ops.dart`; every write
/// attaches `x-idempotency-key` = the caller's command id.
library;

import 'api_error.dart';
import 'headers.dart';
import 'transport.dart';
import 'wh_contracts.dart';
import 'wh_doc_contracts.dart';

part 'wh_client_ops.dart';

/// What `POST /api/pair` returns for a warehouse phone.
class WhPairingResult {
  const WhPairingResult({required this.deviceId, required this.deviceToken, required this.branchId});
  final String deviceId;
  final String deviceToken;
  final int branchId;
}

class WarehouseLanClient {
  WarehouseLanClient({
    required this.transport,
    required this.headers,
    this.credentials = const ApiCredentials(),
  });

  final ApiTransport transport;
  final ApiHeaderBuilder headers;
  ApiCredentials credentials;

  Map<String, Object?> _object(ApiResponse r) {
    final j = r.json;
    if (j is! Map) throw const FormatException('response is not an object');
    return j.cast<String, Object?>();
  }

  /// `GET /api/m1/info` - public; used to refuse a host without TLS.
  Future<LanInfo> info() async =>
      LanInfo.fromJson(_object(await transport.send(ApiRequest('GET', WhPaths.info, headers: headers.anonymous(json: false)))));

  Future<WhPairingResult> pair({
    required String code,
    required String deviceId,
    required String deviceName,
  }) async {
    final res = await transport.send(ApiRequest(
      'POST',
      WhPaths.pair,
      headers: headers.anonymous(),
      body: {'pairingCode': code, 'deviceId': deviceId, 'deviceName': deviceName, 'deviceKind': 'warehouse'},
    ));
    final m = _object(res);
    final token = m['token'];
    final branch = m['branchId'];
    if (token is! String || token.isEmpty || branch is! num) throw const FormatException('pairing response incomplete');
    credentials = ApiCredentials(deviceId: deviceId, deviceToken: token);
    return WhPairingResult(deviceId: deviceId, deviceToken: token, branchId: branch.toInt());
  }

  /// Signs the user in on this paired phone; keeps the session token.
  Future<void> login({required String username, required String password}) async {
    final res = await transport.send(ApiRequest(
      'POST',
      WhPaths.authSession,
      headers: headers.build(credentials, session: false),
      body: {'username': username, 'password': password},
    ));
    final token = _object(res)['token'];
    if (token is! String || token.isEmpty) throw const FormatException('session response incomplete');
    credentials = credentials.copyWith(sessionToken: token);
  }

  Future<WhSessionInfo> session() async =>
      WhSessionInfo.fromJson(_object(await transport.send(ApiRequest('GET', WhPaths.session, headers: headers.build(credentials)))));

  Future<List<WhItem>> itemsByBarcode(String barcode) => _items({'barcode': barcode});
  Future<List<WhItem>> searchItems(String text) => _items({'q': text});

  Future<List<WhItem>> _items(Map<String, String> query) async {
    final res = await transport.send(ApiRequest('GET', WhPaths.items, query: query, headers: headers.build(credentials)));
    return [
      for (final i in (_object(res)['items'] as List? ?? const [])) WhItem.fromJson((i as Map).cast<String, Object?>()),
    ];
  }

  /// Signs out locally (the session token stays valid until it expires; the
  /// desktop has no logout route for the signed-token scheme).
  void signOut() => credentials = credentials.signedOut();

  /// Whether [e] means this device is no longer paired (wipe and re-pair).
  static bool isRevoked(Object e) => e is ApiError && e.kind == ApiErrorKind.deviceRevoked;
}
