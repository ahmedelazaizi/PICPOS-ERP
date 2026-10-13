import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';

/// Credentials and the pinned key are stored in the Android Keystore.
final adminSessionProvider = Provider<AdminSession>(
  (ref) => AdminSession(KeystoreSecretStore()),
);

class AdminSession extends ChangeNotifier {
  AdminSession(
    this.secrets, {
    CloudManageClient Function(Uri, ApiCredentials)? clientFactory,
  }) : _clientFactory = clientFactory;
  final SecretStore secrets;
  final CloudManageClient Function(Uri, ApiCredentials)? _clientFactory;
  CloudManageClient? client;
  PayloadVerifier? verifier;
  VerifiedSnapshots? snapshots;
  String? username;
  String? displayName;
  Uri? serverUrl;
  static const localPinKey = 'admin.localPinVerifier';

  bool? _localPinConfigured;

  bool get paired => client != null;
  bool get loggedIn => client?.credentials.sessionToken != null;
  bool get localPinConfigured => _localPinConfigured == true;

  CloudManageClient _client(
    Uri url, [
    ApiCredentials credentials = const ApiCredentials(),
  ]) =>
      _clientFactory?.call(url, credentials) ??
      CloudManageClient(
        transport: HttpApiTransport(
          kind: TransportKind.cloud,
          baseUri: url,
          policy: kReleaseMode ? UrlPolicy.release : UrlPolicy.development,
        ),
        headers: const ApiHeaderBuilder(appVersion: '0.1.0+1'),
        credentials: credentials,
      );

  Future<void> restore() async {
    final url = await secrets.read('admin.url');
    final token = await secrets.read('admin.deviceToken');
    final deviceId = await secrets.read('admin.deviceId');
    final key = await secrets.read('admin.signingKey');
    if (url == null || token == null || deviceId == null || key == null) return;
    verifier = PayloadVerifier.fromBase64(key);
    client = _client(
      Uri.parse(url),
      ApiCredentials(
        deviceId: deviceId,
        deviceToken: token,
        sessionToken: await secrets.read('admin.sessionToken'),
      ),
    );
    username = await secrets.read('admin.username');
    displayName = await secrets.read('admin.displayName');
    _localPinConfigured = await _hasStoredLocalPin();
    serverUrl = Uri.parse(url);
    notifyListeners();
  }

  Future<bool> _hasStoredLocalPin() async {
    final verifier = await secrets.read(localPinKey);
    return verifier != null && verifier.startsWith('pbkdf2\$');
  }

  Future<bool> hasLocalPin() async {
    _localPinConfigured = await _hasStoredLocalPin();
    return _localPinConfigured!;
  }

  Future<void> setLocalPin(String pin) async {
    final normalized = _normalizePin(pin);
    if (normalized == null) {
      throw const FormatException('invalid_app_pin');
    }
    await secrets.write(localPinKey, await hashMobilePassword(normalized));
    _localPinConfigured = true;
    notifyListeners();
  }

  Future<bool> verifyLocalPin(String pin) async {
    final normalized = _normalizePin(pin);
    final stored = await secrets.read(localPinKey);
    if (normalized == null || stored == null) return false;
    return verifyMobilePassword(normalized, stored);
  }

  String? _normalizePin(String pin) {
    final normalized = normalizeCredential(pin);
    return RegExp(r'^\d{4,6}$').hasMatch(normalized) ? normalized : null;
  }

  /// Manual pairing (no QR) receives the signing key from the cloud, which the
  /// whole signature scheme is meant not to trust (M-5). [confirmKey] gets the
  /// key's fingerprint and must return true only after the user compared it
  /// with the one shown on the office computer; without it (or on false) the
  /// pairing is undone and nothing is saved. A QR offer carries the key from
  /// the desktop itself, so it needs no confirmation.
  Future<void> pair(
    PairingOffer offer, {
    Future<bool> Function(String fingerprint)? confirmKey,
  }) async {
    final api = _client(offer.cloudUrl);
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final paired = await api.pair(
      code: offer.code,
      deviceId: id,
      deviceName: 'PicPos Admin',
      appVersion: '0.1.0+1',
    );
    if (offer.desktopSigningKey != null &&
        offer.desktopSigningKey != paired.desktopSigningKey) {
      try {
        await api.unpair();
      } on Object {
        // Best effort: the office computer can still revoke the device.
      }
      throw const FormatException('desktop_signing_key_mismatch');
    }
    final key = offer.desktopSigningKey ?? paired.desktopSigningKey;
    final candidate = PayloadVerifier.fromBase64(
      key,
    ); // also validates the encoding
    if (offer.desktopSigningKey == null) {
      final fingerprint = await signingKeyFingerprint(key);
      final accepted = confirmKey != null && await confirmKey(fingerprint);
      if (!accepted) {
        try {
          await api
              .unpair(); // do not leave a device paired to a key nobody vouched for
        } on Object {
          // best effort: the office computer can still revoke the device
        }
        throw const FormatException('signing_key_not_confirmed');
      }
    }
    verifier = candidate;
    await secrets.write('admin.url', offer.cloudUrl.toString());
    await secrets.write('admin.deviceToken', paired.deviceToken);
    await secrets.write('admin.deviceId', paired.deviceId);
    await secrets.write('admin.signingKey', key);
    if (paired.user != null) {
      await secrets.write('admin.username', paired.user!.username);
      await secrets.write('admin.displayName', paired.user!.displayName);
    }
    username = paired.user?.username;
    displayName = paired.user?.displayName;
    serverUrl = offer.cloudUrl;
    client = api;
    notifyListeners();
  }

  Future<void> login(String user, String password, {String? totp}) async {
    final api = client!;
    final normalizedTotp = totp == null || totp.trim().isEmpty
        ? null
        : normalizeCredential(totp);
    if (normalizedTotp != null &&
        !RegExp(r'^\d{6}$').hasMatch(normalizedTotp)) {
      throw const FormatException('invalid_totp');
    }
    try {
      final signedIn = await api.login(
        username: user,
        password: password,
        totp: normalizedTotp,
      );
      await secrets.write('admin.username', signedIn.user.username);
      await secrets.write('admin.displayName', signedIn.user.displayName);
      await secrets.write('admin.sessionToken', api.credentials.sessionToken!);
      username = signedIn.user.username;
      displayName = signedIn.user.displayName;
      notifyListeners();
      await refresh();
    } on ApiError catch (error) {
      if (error.kind == ApiErrorKind.deviceRevoked) {
        await wipe();
      } else if (error.kind == ApiErrorKind.unauthorized) {
        await clearSession();
      }
      rethrow;
    }
  }

  /// Clears authenticated state while retaining the device pairing.
  Future<void> clearSession() async {
    final api = client;
    if (api != null) api.credentials = api.credentials.signedOut();
    snapshots = null;
    await secrets.delete('admin.sessionToken');
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!loggedIn) return;
    try {
      snapshots = await client!.verifiedSnapshots(verifier!);
      notifyListeners();
    } on ApiError catch (error) {
      if (error.kind == ApiErrorKind.deviceRevoked) {
        await wipe();
      } else if (error.kind == ApiErrorKind.unauthorized) {
        await clearSession();
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final api = client;
    try {
      if (api != null && loggedIn) await api.logout();
    } on Exception {
      // Sign-out must also work without a connection.
    } finally {
      if (api != null) api.credentials = api.credentials.signedOut();
      snapshots = null;
      await secrets.delete('admin.sessionToken');
      notifyListeners();
    }
  }

  /// Returns false when the server could not revoke the device (e.g. offline).
  Future<bool> unpairAndWipe() async {
    var revoked = false;
    try {
      if (client != null) {
        await client!.unpair();
        revoked = true;
      }
    } on Exception {
      // Local credentials must be removed even if server revocation fails.
    } finally {
      await wipe();
    }
    return revoked;
  }

  Future<void> wipe() async {
    for (final key in [
      'admin.url',
      'admin.deviceToken',
      'admin.deviceId',
      'admin.signingKey',
      'admin.username',
      'admin.displayName',
      'admin.sessionToken',
      localPinKey,
    ]) {
      await secrets.delete(key);
    }
    client = null;
    verifier = null;
    snapshots = null;
    username = null;
    displayName = null;
    serverUrl = null;
    _localPinConfigured = false;
    notifyListeners();
  }
}
