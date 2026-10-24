// SEC-007 — LAN transport security: mode resolution + the host's managed
// self-signed certificate.
//
// * Default (`secureSelfSigned`): the embedded server serves HTTPS with a
//   certificate generated on first run. Key + certificate live in the app's
//   secure storage (never in the repository, never as a loose file). Clients
//   pin the SHA-256 fingerprint delivered in the pairing QR / code (TOFU).
// * `customCertificate`: the operator supplied cert/key files (previous
//   behaviour, kept for CA-issued or tunnelled setups).
// * `legacyHttp`: explicit opt-out for fleets that still contain clients which
//   cannot do TLS. Plain HTTP; the host logs a SECURITY warning on every start.
//
// Pure policy + storage code: no `NetworkService` import, fully unit-testable.

import 'dart:io';

import '../secure_storage_service.dart';
import '../tls_trust.dart';
import 'x509_self_signed.dart';

/// SharedPreferences key holding the explicit operator choice.
const String kLanTransportPref = 'network_lan_transport';

enum LanTransportMode {
  /// HTTPS with the managed self-signed certificate (default, secure).
  secureSelfSigned('secure'),

  /// HTTPS with operator-supplied certificate/key files.
  customCertificate('custom'),

  /// Plain HTTP (explicit, insecure legacy option).
  legacyHttp('legacy_http');

  const LanTransportMode(this.storageValue);
  final String storageValue;

  bool get usesTls => this != legacyHttp;
}

/// Resolves the effective transport mode.
///
/// * stored `legacy_http` -> legacy (explicit opt-out wins);
/// * stored `custom`, or a previously enabled custom certificate -> custom,
///   but only while cert/key paths are still configured;
/// * everything else (nothing stored, `secure`) -> managed self-signed TLS.
///   So an installation that never chose anything is secure by default.
LanTransportMode resolveLanTransportMode({
  String? stored,
  required bool legacyCustomTlsEnabled,
  required bool customCertConfigured,
}) {
  if (stored == LanTransportMode.legacyHttp.storageValue) {
    return LanTransportMode.legacyHttp;
  }
  final wantsCustom = stored == LanTransportMode.customCertificate.storageValue ||
      (stored == null && legacyCustomTlsEnabled);
  if (wantsCustom && customCertConfigured) {
    return LanTransportMode.customCertificate;
  }
  return LanTransportMode.secureSelfSigned;
}

/// Minimal key/value storage the manager needs (secure storage in production).
abstract class LanTlsStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureLanTlsStorage implements LanTlsStorage {
  SecureLanTlsStorage([SecureStorageService? storage])
      : _storage = storage ?? SecureStorageService();
  final SecureStorageService _storage;

  @override
  Future<String?> read(String key) => _storage.read(key);
  @override
  Future<void> write(String key, String value) => _storage.write(key, value);
  @override
  Future<void> delete(String key) => _storage.delete(key);
}

/// Loaded server TLS material.
class LanTlsMaterial {
  const LanTlsMaterial({
    required this.context,
    required this.fingerprint,
    required this.newlyGenerated,
    this.notAfter,
  });

  final SecurityContext context;

  /// SHA-256 (hex, lower-case) of the DER certificate: what clients pin.
  final String fingerprint;
  final bool newlyGenerated;
  final DateTime? notAfter;
}

/// Outcome of preparing TLS for the server start.
class LanServerTls {
  const LanServerTls._({required this.mode, this.context, this.fingerprint, this.error});

  factory LanServerTls.plain() => const LanServerTls._(mode: LanTransportMode.legacyHttp);
  factory LanServerTls.failed(LanTransportMode mode, String error) =>
      LanServerTls._(mode: mode, error: error);
  factory LanServerTls.ready(LanTransportMode mode, SecurityContext context, String? fingerprint) =>
      LanServerTls._(mode: mode, context: context, fingerprint: fingerprint);

  final LanTransportMode mode;
  final SecurityContext? context;
  final String? fingerprint;
  final String? error;
  bool get isTls => context != null;
}

/// Creates / loads / rotates the host's managed self-signed certificate.
class LanTlsManager {
  LanTlsManager([LanTlsStorage? storage]) : _storage = storage ?? SecureLanTlsStorage();

  final LanTlsStorage _storage;

  static const certStorageKey = 'lan_tls_cert_pem';
  static const keyStorageKey = 'lan_tls_key_pem';

  /// Loads the stored certificate, or generates one on first run (or when the
  /// stored pair is unreadable). The server address is NOT part of the pin, so
  /// an IP change never invalidates paired clients.
  Future<LanTlsMaterial> loadOrCreate({List<String> ipAddresses = const []}) async {
    final certPem = await _storage.read(certStorageKey);
    final keyPem = await _storage.read(keyStorageKey);
    if (certPem != null && keyPem != null) {
      final loaded = _tryBuild(certPem, keyPem, newlyGenerated: false);
      if (loaded != null) return loaded;
    }
    return _generateAndStore(ipAddresses);
  }

  /// Replaces the certificate. Every paired client must re-pin afterwards
  /// (their stored fingerprint no longer matches) - use after a suspected key
  /// compromise.
  Future<LanTlsMaterial> rotate({List<String> ipAddresses = const []}) =>
      _generateAndStore(ipAddresses);

  /// Fingerprint of the stored certificate, without building a context.
  Future<String?> storedFingerprint() async {
    final pem = await _storage.read(certStorageKey);
    if (pem == null) return null;
    final der = certificateDerFromPem(pem);
    return der == null ? null : TlsTrust.fingerprintOfDer(der);
  }

  Future<LanTlsMaterial> _generateAndStore(List<String> ips) async {
    final generated = generateSelfSignedCertificate(
      ipAddresses: <String>{'127.0.0.1', ...ips}.toList(),
    );
    await _storage.write(certStorageKey, generated.certificatePem);
    await _storage.write(keyStorageKey, generated.privateKeyPem);
    final material = _tryBuild(generated.certificatePem, generated.privateKeyPem, newlyGenerated: true);
    if (material == null) {
      throw StateError('generated LAN TLS certificate could not be loaded');
    }
    return material;
  }

  LanTlsMaterial? _tryBuild(String certPem, String keyPem, {required bool newlyGenerated}) {
    try {
      final der = certificateDerFromPem(certPem);
      if (der == null) return null;
      final context = SecurityContext()
        ..useCertificateChainBytes(certPem.codeUnits)
        ..usePrivateKeyBytes(keyPem.codeUnits);
      return LanTlsMaterial(
        context: context,
        fingerprint: TlsTrust.fingerprintOfDer(der),
        newlyGenerated: newlyGenerated,
        notAfter: certificateNotAfter(der),
      );
    } on Object {
      return null;
    }
  }
}

/// Prepares the server's TLS state for [mode]. Returns `error` (never throws)
/// so the caller can refuse to start instead of silently falling back to HTTP.
Future<LanServerTls> resolveLanServerTls({
  required LanTransportMode mode,
  required LanTlsManager manager,
  String? customCertPath,
  String? customKeyPath,
  String? customKeyPassword,
  List<String> ipAddresses = const [],
}) async {
  switch (mode) {
    case LanTransportMode.legacyHttp:
      return LanServerTls.plain();
    case LanTransportMode.customCertificate:
      try {
        final context = SecurityContext()
          ..useCertificateChain(customCertPath!)
          ..usePrivateKey(customKeyPath!, password: customKeyPassword);
        return LanServerTls.ready(mode, context, TlsTrust.fingerprintOfPemFile(customCertPath));
      } on Object catch (e) {
        return LanServerTls.failed(mode, 'Failed to load TLS cert/key: $e');
      }
    case LanTransportMode.secureSelfSigned:
      try {
        final material = await manager.loadOrCreate(ipAddresses: ipAddresses);
        return LanServerTls.ready(mode, material.context, material.fingerprint);
      } on Object catch (e) {
        // Fail closed: a secure-by-default server must not quietly serve HTTP.
        return LanServerTls.failed(mode, 'Failed to prepare the managed LAN TLS certificate: $e');
      }
  }
}
