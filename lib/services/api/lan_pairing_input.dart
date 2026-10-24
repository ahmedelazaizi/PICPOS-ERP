// SEC-007 — what an operator types / pastes when pairing a LAN client.
//
// Two shapes are accepted in the "pairing code" box:
//   * the 8-character one-time code (legacy; no fingerprint -> trust on first use);
//   * the full pairing payload the host copies to the clipboard / shows as a QR:
//       {"serverHost":"192.168.1.10","port":8080,"pairingCode":"ABCD2345",
//        "serverFingerprint":"<sha256 hex of the host certificate>"}
//     which carries the certificate fingerprint out-of-band, so the very first
//     connection is already pinned (no TOFU window for a man in the middle).

import 'dart:convert';

class LanPairingInput {
  const LanPairingInput({
    required this.code,
    this.fingerprint,
    this.host,
    this.port,
  });

  final String code;

  /// SHA-256 (hex, lower-case) of the host certificate, when the payload had one.
  final String? fingerprint;
  final String? host;
  final int? port;

  bool get hasFingerprint => fingerprint != null;

  static final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  static LanPairingInput parse(String raw) {
    final text = raw.trim();
    if (text.startsWith('{')) {
      try {
        final j = jsonDecode(text);
        if (j is Map) {
          final fp = '${j['serverFingerprint'] ?? ''}'.trim().toLowerCase().replaceAll(':', '');
          return LanPairingInput(
            code: '${j['pairingCode'] ?? j['code'] ?? ''}'.trim().toUpperCase(),
            fingerprint: _sha256Hex.hasMatch(fp) ? fp : null,
            host: (j['serverHost'] as String?)?.trim(),
            port: j['port'] is int ? j['port'] as int : int.tryParse('${j['port'] ?? ''}'),
          );
        }
      } on FormatException {
        // fall through: treat as a plain code
      }
    }
    return LanPairingInput(code: text.toUpperCase());
  }
}
