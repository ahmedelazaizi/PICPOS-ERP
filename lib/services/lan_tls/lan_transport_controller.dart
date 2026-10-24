// SEC-007 — holds the LAN transport choice for `NetworkService` so that the
// (size-ratcheted) service only needs a handful of delegating calls.

import 'package:shared_preferences/shared_preferences.dart';

import 'lan_tls_manager.dart';

class LanTransportController {
  LanTransportController([LanTlsManager? manager]) : manager = manager ?? LanTlsManager();

  final LanTlsManager manager;

  /// Effective mode. Defaults to the managed self-signed TLS (secure).
  LanTransportMode mode = LanTransportMode.secureSelfSigned;

  bool get isLegacyHttp => mode == LanTransportMode.legacyHttp;

  /// Called from `loadSettings`.
  void load(
    SharedPreferences prefs, {
    required bool customTlsEnabled,
    String? certPath,
    String? keyPath,
  }) {
    mode = resolveLanTransportMode(
      stored: prefs.getString(kLanTransportPref),
      legacyCustomTlsEnabled: customTlsEnabled,
      customCertConfigured: _hasPaths(certPath, keyPath),
    );
  }

  /// Called from `saveSettings`.
  Future<void> save(SharedPreferences prefs) =>
      prefs.setString(kLanTransportPref, mode.storageValue);

  /// Called from `configureTls` (operator supplied / cleared a custom cert).
  void onCustomTlsConfigured({required bool enabled, String? certPath, String? keyPath}) {
    if (mode == LanTransportMode.legacyHttp) return; // explicit choice stays
    mode = enabled && _hasPaths(certPath, keyPath)
        ? LanTransportMode.customCertificate
        : LanTransportMode.secureSelfSigned;
  }

  /// Explicit, insecure opt-out (or back to secure).
  void setLegacyHttp(bool legacy) {
    mode = legacy ? LanTransportMode.legacyHttp : LanTransportMode.secureSelfSigned;
  }

  Future<LanServerTls> prepare({
    String? certPath,
    String? keyPath,
    String? keyPassword,
    List<String> ipAddresses = const [],
  }) =>
      resolveLanServerTls(
        mode: mode,
        manager: manager,
        customCertPath: certPath,
        customKeyPath: keyPath,
        customKeyPassword: keyPassword,
        ipAddresses: ipAddresses,
      );

  static bool _hasPaths(String? cert, String? key) =>
      (cert?.isNotEmpty ?? false) && (key?.isNotEmpty ?? false);
}
