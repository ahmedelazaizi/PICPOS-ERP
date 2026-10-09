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
  bool get paired => client != null;
  bool get loggedIn => client?.credentials.sessionToken != null;

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
    serverUrl = Uri.parse(url);
    notifyListeners();
  }

  Future<void> pair(PairingOffer offer) async {
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
      throw const FormatException('desktop_signing_key_mismatch');
    }
    final key = offer.desktopSigningKey ?? paired.desktopSigningKey;
    verifier = PayloadVerifier.fromBase64(key);
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
    try {
      final signedIn = await api.login(username: user, password: password, totp: totp);
      await secrets.write('admin.username', signedIn.user.username);
      await secrets.write('admin.displayName', signedIn.user.displayName);
      await secrets.write('admin.sessionToken', api.credentials.sessionToken!);
      username = signedIn.user.username;
      displayName = signedIn.user.displayName;
      notifyListeners();
      await refresh();
    } on ApiError catch (error) {
      if (error.kind == ApiErrorKind.deviceRevoked) await wipe();
      rethrow;
    }
  }

  Future<void> refresh() async {
    if (!loggedIn) return;
    try {
      snapshots = await client!.verifiedSnapshots(verifier!);
      notifyListeners();
    } on ApiError catch (error) {
      if (error.kind == ApiErrorKind.deviceRevoked) await wipe();
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
    ]) {
      await secrets.delete(key);
    }
    client = null;
    verifier = null;
    snapshots = null;
    username = null;
    displayName = null;
    serverUrl = null;
    notifyListeners();
  }
}
