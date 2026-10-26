import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';

/// Builds the client of the paired desktop. Production: a transport pinned to
/// the certificate fingerprint of the pairing payload (lan_pinning.dart).
typedef PosClientFactory = DeviceLanClient Function(Uri baseUri, String fingerprint, ApiCredentials credentials);

/// A pairing refusal decided locally (expired, wrong kind, no TLS, bad code).
class PosPairingError implements Exception {
  const PosPairingError(this.code);
  final String code;
  @override
  String toString() => 'PosPairingError($code)';
}

/// Stable code of an error, for `S.errorText`.
String posErrorCode(Object e) {
  if (e is PosPairingError) return e.code;
  if (e is FormatException) return e.message.isEmpty ? 'incomplete' : e.message;
  if (e is UrlPolicyException) return 'not_https';
  if (e is ApiError) {
    if (const {'pos_access_denied', 'branch_access_denied', 'invalid_credentials', 'locked_out', 'password_change_required'}
        .contains(e.code)) {
      return e.code;
    }
    return switch (e.kind) {
      ApiErrorKind.network => 'network',
      ApiErrorKind.unauthorized => 'unauthorized',
      ApiErrorKind.deviceRevoked => 'device_revoked',
      ApiErrorKind.forbidden => e.code == 'device_scope' ? 'device_scope' : 'permission_denied',
      ApiErrorKind.rateLimited => 'rate_limited',
      ApiErrorKind.unavailable => 'unavailable',
      ApiErrorKind.rejected => 'rejected',
      _ => 'unknown',
    };
  }
  return 'unknown';
}

/// Why the tablet is back on the pairing screen: the office unpaired it.
class PosUnpairNotice {
  const PosUnpairNotice();
}

/// State of this Cashier tablet: the pairing with the desktop (kind `pos`,
/// branch bound by the code, pinned to the certificate fingerprint, a
/// per-device token) and the signed-in cashier. Secrets live in the Android
/// Keystore ([SecretStore]). Nothing about the user's role is cached: the
/// desktop decides at every sign-in (branch + point-of-sale access).
class PosSession extends ChangeNotifier {
  PosSession(this.secrets, {PosClientFactory? clientFactory, this.onWipe, DateTime Function()? now})
      : _factory = clientFactory ?? _pinnedClient,
        _now = now ?? DateTime.now;

  final SecretStore secrets;
  final PosClientFactory _factory;
  final Future<void> Function()? onWipe;
  final DateTime Function() _now;

  static const kind = 'pos';
  static const _kUrl = 'pos.url';
  static const _kFp = 'pos.fingerprint';
  static const _kDeviceId = 'pos.deviceId';
  static const _kDeviceToken = 'pos.deviceToken';
  static const _kBranch = 'pos.branchId';
  static const _kTerminal = 'pos.terminalCode';
  static const _kSession = 'pos.sessionToken';
  static const _kUser = 'pos.username';
  static const _allKeys = [_kUrl, _kFp, _kDeviceId, _kDeviceToken, _kBranch, _kTerminal, _kSession, _kUser];

  DeviceLanClient? client;
  Uri? serverUrl;
  int? branchId;
  String? terminalCode;
  String? username;
  bool restored = false;
  PosUnpairNotice? unpairNotice;

  bool get paired => client != null;
  bool get loggedIn => paired && (client!.credentials.sessionToken ?? '').isNotEmpty;

  static DeviceLanClient _pinnedClient(Uri baseUri, String fingerprint, ApiCredentials credentials) {
    return DeviceLanClient(
      kind: kind,
      transport: HttpApiTransport(
        kind: TransportKind.lan,
        baseUri: baseUri,
        // Release: https only. Debug may talk to the dev LAN.
        policy: kReleaseMode ? UrlPolicy.release : UrlPolicy.development,
        client: createPinnedLanClient(fingerprint),
      ),
      headers: const ApiHeaderBuilder(appVersion: '0.1.0+1'),
      credentials: credentials,
    );
  }

  Future<void> restore() async {
    final url = await secrets.read(_kUrl);
    final fp = await secrets.read(_kFp);
    final id = await secrets.read(_kDeviceId);
    final token = await secrets.read(_kDeviceToken);
    if (url != null && fp != null && id != null && token != null) {
      serverUrl = Uri.parse(url);
      branchId = int.tryParse(await secrets.read(_kBranch) ?? '');
      terminalCode = await secrets.read(_kTerminal);
      username = await secrets.read(_kUser);
      client = _factory(
        serverUrl!,
        fp,
        ApiCredentials(deviceId: id, deviceToken: token, sessionToken: await secrets.read(_kSession)),
      );
    }
    restored = true;
    notifyListeners();
  }

  /// Pairs with the desktop from a scanned/typed payload. Refuses an expired
  /// payload, a payload for another kind of device and a host without TLS.
  /// Nothing is saved unless the desktop accepted the one-time code AND bound
  /// the tablet to a branch.
  Future<void> pair(PairingPayload payload) async {
    if (payload.kind != PairingKind.pos) throw const PosPairingError('wrong_kind');
    if (payload.isExpired(_now())) throw const PosPairingError('expired');
    final api = _factory(payload.url, payload.fingerprint, const ApiCredentials());
    final probe = await api.info();
    if (!probe.tls) throw const PosPairingError('no_tls');
    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final DevicePairingResult result;
    try {
      result = await api.pair(code: payload.code, deviceId: id, deviceName: 'PicPos Cashier');
    } on ApiError catch (e) {
      // 401 on /api/pair = unknown / used / expired code or a code for another kind.
      if (e.kind == ApiErrorKind.unauthorized) throw const PosPairingError('invalid_code');
      rethrow;
    }
    await secrets.write(_kUrl, payload.url.toString());
    await secrets.write(_kFp, payload.fingerprint);
    await secrets.write(_kDeviceId, result.deviceId);
    await secrets.write(_kDeviceToken, result.deviceToken);
    await secrets.write(_kBranch, '${result.branchId}');
    if (result.terminalCode != null) await secrets.write(_kTerminal, result.terminalCode!);
    serverUrl = payload.url;
    branchId = result.branchId;
    terminalCode = result.terminalCode;
    client = api;
    unpairNotice = null;
    notifyListeners();
  }

  /// Signs the cashier in. The desktop refuses a user outside this branch or
  /// without point-of-sale access (`branch_access_denied`, `pos_access_denied`)
  /// and the tablet stays signed out (no half-signed-in state).
  Future<void> login(String name, String password) async {
    final api = client!;
    try {
      await api.login(username: name.trim(), password: password);
      username = name.trim();
      await secrets.write(_kSession, api.credentials.sessionToken!);
      await secrets.write(_kUser, username!);
      notifyListeners();
    } on Object catch (e) {
      await _afterFailure(e);
      rethrow;
    }
  }

  /// Asks the desktop whether this tablet is still paired (an authenticated
  /// call: a revoked device gets `401 device_revoked` and is wiped). Offline
  /// and every other answer leave the pairing as it is.
  Future<void> verifyStillPaired() async {
    final api = client;
    if (api == null) return;
    try {
      await api.probe('/api/branches');
    } on Object catch (e) {
      if (DeviceLanClient.isRevoked(e)) await handleRevoked();
    }
  }

  /// The office revoked this device: wipe and leave the notice for the
  /// pairing screen.
  Future<void> handleRevoked() async {
    await wipe();
    unpairNotice = const PosUnpairNotice();
    notifyListeners();
  }

  Future<void> _afterFailure(Object e) async {
    if (DeviceLanClient.isRevoked(e)) {
      await handleRevoked();
    } else {
      await signOut();
    }
  }

  Future<void> signOut() async {
    client?.signOut();
    username = null;
    await secrets.delete(_kSession);
    await secrets.delete(_kUser);
    notifyListeners();
  }

  /// Local wipe: credentials, pinned fingerprint and cached data.
  Future<void> wipe() async {
    for (final k in _allKeys) {
      await secrets.delete(k);
    }
    await onWipe?.call();
    client = null;
    serverUrl = null;
    branchId = null;
    terminalCode = null;
    username = null;
    notifyListeners();
  }
}
