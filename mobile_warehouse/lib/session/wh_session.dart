import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';

/// Builds the client of the paired desktop. Production: a transport pinned to
/// the certificate fingerprint from the pairing payload (lan_pinning.dart).
typedef WhClientFactory = WarehouseLanClient Function(Uri baseUri, String fingerprint, ApiCredentials credentials);

/// Domain refusals of the warehouse documents (server `error` codes) that have
/// their own message in `S.table` (`err_<code>`); a structural test keeps the
/// two lists equal.
const kDomainCodes = <String>{
  'idempotency_conflict', 'stale', 'invalid_transition', 'stock_changed', 'batch_expired', 'over_receipt',
  'po_not_receivable', 'po_not_found', 'product_not_in_order', 'batch_required', 'invalid_condition',
  'invalid_quantity', 'bins_disabled', 'location_not_found', 'warehouse_forbidden', 'doc_not_found',
  'doc_mismatch', 'not_owner', 'empty_document', 'self_approval', 'staged_transfers_disabled', 'same_warehouse',
  'warehouse_not_found', 'product_not_found', 'reason_required', 'count_not_open', 'incomplete_count',
  'recount_required', 'already_finalized', 'count_not_submitted', 'task_not_found', 'nothing_to_post',
  'accounts_not_mapped', 'no_barcode', 'item_not_found', 'period_closed', 'duplicate_document', 'busy',
  'dead_letter', 'dependency_rejected',
};

/// Stable code of an error, for `S.errorText`.
String errorCode(Object e) {
  if (e is PairingFormatError) return e.code;
  if (e is FormatException) return e.message.isEmpty ? 'incomplete' : e.message;
  if (e is UrlPolicyException) return 'not_https';
  if (e is ApiError) {
    if (kDomainCodes.contains(e.code)) return e.code;
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

/// Why the phone is back on the pairing screen: the office unpaired it.
class UnpairNotice {
  const UnpairNotice({required this.discardedOperations});
  final int discardedOperations;
}

/// A pairing refusal decided locally (expired, wrong kind, no TLS).
class PairingFormatError implements Exception {
  const PairingFormatError(this.code);
  final String code;
  @override
  String toString() => 'PairingFormatError($code)';
}

/// State of this phone: pairing, the signed-in user and the scope the
/// desktop granted. Secrets live in the Android Keystore ([SecretStore]).
/// Nothing is cached about the user's permissions: [info] always comes from
/// the desktop, so a changed role or a deactivated account takes effect on the
/// next refresh.
class WhSession extends ChangeNotifier {
  WhSession(this.secrets, {WhClientFactory? clientFactory, this.onWipe, DateTime Function()? now})
      : _factory = clientFactory ?? _pinnedClient,
        _now = now ?? DateTime.now;

  final SecretStore secrets;
  final WhClientFactory _factory;
  final Future<void> Function()? onWipe;
  final DateTime Function() _now;

  static const _kUrl = 'wh.url';
  static const _kFp = 'wh.fingerprint';
  static const _kDeviceId = 'wh.deviceId';
  static const _kDeviceToken = 'wh.deviceToken';
  static const _kBranch = 'wh.branchId';
  static const _kSession = 'wh.sessionToken';
  static const _kPin = 'wh.localPinVerifier';

  WarehouseLanClient? client;
  Uri? serverUrl;
  int? branchId;
  WhSessionInfo? info;
  bool restored = false;
  bool? _hasPin;

  bool get paired => client != null;
  bool get loggedIn => paired && (client!.credentials.sessionToken ?? '').isNotEmpty;

  static WarehouseLanClient _pinnedClient(Uri baseUri, String fingerprint, ApiCredentials credentials) {
    return WarehouseLanClient(
      transport: HttpApiTransport(
        kind: TransportKind.lan,
        baseUri: baseUri,
        // Release: https only. Debug may talk to the dev LAN, but a pinned
        // https host is still the normal case (the payload always has a pin).
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
      client = _factory(
        serverUrl!,
        fp,
        ApiCredentials(deviceId: id, deviceToken: token, sessionToken: await secrets.read(_kSession)),
      );
    }
    _hasPin = await _storedPin();
    restored = true;
    notifyListeners();
  }

  /// Pairs with the desktop from a scanned/typed payload. Refuses an expired
  /// payload, a payload for another kind of device and a host without TLS.
  /// Nothing is saved unless the desktop accepted the one-time code.
  Future<void> pair(PairingPayload payload) async {
    if (payload.kind != PairingKind.warehouse) throw const PairingFormatError('wrong_kind');
    if (payload.isExpired(_now())) throw const PairingFormatError('expired');
    final api = _factory(payload.url, payload.fingerprint, const ApiCredentials());
    final probe = await api.info();
    if (!probe.tls) throw const PairingFormatError('no_tls');
    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final result = await api.pair(code: payload.code, deviceId: id, deviceName: 'PicPos Warehouse');
    await secrets.write(_kUrl, payload.url.toString());
    await secrets.write(_kFp, payload.fingerprint);
    await secrets.write(_kDeviceId, result.deviceId);
    await secrets.write(_kDeviceToken, result.deviceToken);
    await secrets.write(_kBranch, '${result.branchId}');
    serverUrl = payload.url;
    branchId = result.branchId;
    client = api;
    unpairNotice = null;
    notifyListeners();
  }

  /// Signs in and loads the scope. A user without Warehouse access is signed
  /// straight out again (no half-signed-in state).
  Future<void> login(String username, String password) async {
    final api = client!;
    try {
      await api.login(username: username.trim(), password: password);
      info = await api.session();
      await secrets.write(_kSession, api.credentials.sessionToken!);
      notifyListeners();
    } on Object catch (e) {
      await _afterFailure(e, signOutOnError: true);
      rethrow;
    }
  }

  /// Re-reads the scope from the desktop. Offline keeps the previous [info].
  Future<void> refresh() async {
    if (!loggedIn) return;
    try {
      info = await client!.session();
      notifyListeners();
    } on Object catch (e) {
      await _afterFailure(e, signOutOnError: false);
      rethrow;
    }
  }

  /// Set when the office unpaired this phone (revoked): the pairing screen
  /// says so and how many unsent operations were thrown away (W5.4b). A wipe
  /// the user asked for himself leaves it null.
  UnpairNotice? unpairNotice;

  /// Counts the operations still waiting in the outbox; the outbox registers
  /// itself here so a revocation can tell the user what was lost.
  Future<int> Function()? unsentCount;

  /// The office revoked this device: remember how many unsent operations the
  /// wipe discards, wipe, and leave the notice for the pairing screen.
  Future<void> handleRevoked() async {
    final lost = await unsentCount?.call() ?? 0;
    unpairNotice = UnpairNotice(discardedOperations: lost);
    await wipe();
  }

  Future<void> _afterFailure(Object e, {required bool signOutOnError}) async {
    if (WarehouseLanClient.isRevoked(e)) {
      await handleRevoked();
    } else if (signOutOnError ||
        (e is ApiError && (e.kind == ApiErrorKind.unauthorized || e.kind == ApiErrorKind.forbidden))) {
      await signOut();
    }
  }

  Future<void> signOut() async {
    client?.signOut();
    info = null;
    await secrets.delete(_kSession);
    notifyListeners();
  }

  /// Local wipe: credentials, PIN, cached data (the outbox is dropped too).
  Future<void> wipe() async {
    for (final k in [_kUrl, _kFp, _kDeviceId, _kDeviceToken, _kBranch, _kSession, _kPin]) {
      await secrets.delete(k);
    }
    await onWipe?.call();
    client = null;
    serverUrl = null;
    branchId = null;
    info = null;
    _hasPin = false;
    notifyListeners();
  }

  // ---- local PIN (same scheme as mobile_admin's app lock) ----

  Future<bool> _storedPin() async => (await secrets.read(_kPin) ?? '').startsWith('pbkdf2\$');
  bool get localPinConfigured => _hasPin == true;

  Future<bool> hasLocalPin() async => _hasPin = await _storedPin();

  String? _normalizePin(String pin) {
    final n = normalizeCredential(pin);
    return RegExp(r'^\d{4,6}$').hasMatch(n) ? n : null;
  }

  Future<void> setLocalPin(String pin) async {
    final n = _normalizePin(pin);
    if (n == null) throw const FormatException('invalid_app_pin');
    await secrets.write(_kPin, await hashMobilePassword(n));
    _hasPin = true;
    notifyListeners();
  }

  Future<bool> verifyLocalPin(String pin) async {
    final n = _normalizePin(pin);
    final stored = await secrets.read(_kPin);
    if (n == null || stored == null) return false;
    return verifyMobilePassword(n, stored);
  }
}
