/// LAN transport security for the Android apps (SEC-007).
///
/// The desktop host serves HTTPS with a self-signed certificate generated on
/// first run. There is no CA chain to validate, so identity is the SHA-256
/// fingerprint of the host certificate (DER), delivered out-of-band in the
/// pairing QR / code. This file turns that fingerprint into a pinned
/// `http.Client`:
///
///  * a certificate whose fingerprint equals the pin is accepted;
///  * anything else (including a CA-signed certificate for the same host) is
///    rejected - a pin is exact, so a man in the middle cannot get in;
///  * there is no "no pin => accept" mode here: [createPinnedLanClient]
///    requires a valid fingerprint, and [LanPairingPayload.parse] refuses a
///    payload without one.
///
/// Combine with `UrlPolicy.release` (https only) - the Android
/// network-security-config does not apply to Dart's `HttpClient`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

/// Normalises "AB:CD:..." / upper-case input to lower-case hex, or returns
/// null when it is not a SHA-256 digest.
String? normalizeFingerprint(String? raw) {
  if (raw == null) return null;
  final fp = raw.trim().toLowerCase().replaceAll(':', '');
  return _sha256Hex.hasMatch(fp) ? fp : null;
}

/// SHA-256 of a DER certificate, lower-case hex.
String certificateFingerprint(List<int> der) => sha256.convert(der).toString();

/// `badCertificateCallback` that accepts exactly the pinned certificate.
bool Function(X509Certificate, String, int) pinnedCertificateCallback(
  String fingerprintHex,
) {
  final pin = normalizeFingerprint(fingerprintHex);
  if (pin == null) {
    throw ArgumentError.value(fingerprintHex, 'fingerprintHex', 'not a SHA-256 fingerprint');
  }
  return (cert, host, port) => certificateFingerprint(cert.der) == pin;
}

/// HTTP client pinned to one LAN host certificate. Never use it for the cloud
/// (public CA) - use a normal client there.
http.Client createPinnedLanClient(
  String fingerprintHex, {
  Duration connectionTimeout = const Duration(seconds: 5),
}) {
  final inner = HttpClient()
    ..connectionTimeout = connectionTimeout
    ..badCertificateCallback = pinnedCertificateCallback(fingerprintHex);
  return IOClient(inner);
}

/// The pairing payload shown by the desktop (QR / clipboard JSON).
class LanPairingPayload {
  const LanPairingPayload({
    required this.host,
    required this.port,
    required this.pairingCode,
    required this.fingerprint,
  });

  final String host;
  final int port;
  final String pairingCode;

  /// SHA-256 (lower-case hex) of the host certificate.
  final String fingerprint;

  Uri get baseUri => Uri(scheme: 'https', host: host, port: port);

  /// Throws [FormatException] when a field is missing or when the payload has
  /// no certificate fingerprint (the host runs legacy plain HTTP): the apps
  /// refuse such a host rather than pair over cleartext.
  factory LanPairingPayload.parse(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('pairing payload is not JSON');
    }
    if (json is! Map) throw const FormatException('pairing payload is not an object');
    final host = (json['serverHost'] as String?)?.trim() ?? '';
    final port = json['port'] is int ? json['port'] as int : int.tryParse('${json['port']}');
    final code = (json['pairingCode'] as String?)?.trim().toUpperCase() ?? '';
    final fp = normalizeFingerprint(json['serverFingerprint'] as String?);
    if (host.isEmpty || port == null || code.isEmpty) {
      throw const FormatException('pairing payload is incomplete');
    }
    if (fp == null) {
      throw const FormatException(
        'pairing payload has no certificate fingerprint: the host is not using TLS',
      );
    }
    return LanPairingPayload(host: host, port: port, pairingCode: code, fingerprint: fp);
  }
}
