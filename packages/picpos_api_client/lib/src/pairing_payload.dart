/// The pairing payload shown by the desktop (QR / copied JSON), v1 and v2.
///
/// v2 (plan 2026-10-23, SEC-006/SEC-007): `{v:2, kind, url, code, exp, fp,
/// branchId?}`. It carries NO long-lived secret - `code` is the one-time,
/// ten-minute pairing code and `fp` is the SHA-256 fingerprint of the host's
/// self-signed TLS certificate, which the app pins
/// (see `lan_pinning.dart`). The desktop also keeps the v1 keys
/// (`serverHost`, `port`, `pairingCode`, `serverFingerprint`) so older clients
/// still parse it; this parser prefers v2 and falls back to v1.
library;

import 'dart:convert';

import 'lan_pinning.dart';

/// Device kinds a payload can be issued for.
enum PairingKind { lan, admin, pos, warehouse }

class PairingPayload {
  const PairingPayload({
    required this.version,
    required this.kind,
    required this.url,
    required this.code,
    required this.fingerprint,
    this.expiresAt,
    this.branchId,
  });

  final int version;
  final PairingKind kind;

  /// `https://host:port` of the desktop LAN server.
  final Uri url;
  final String code;

  /// SHA-256 (lower-case hex) of the server certificate. Always present: a
  /// payload without it is refused (the host is not using TLS).
  final String fingerprint;
  final DateTime? expiresAt;
  final int? branchId;

  bool isExpired(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  /// Throws [FormatException] with a stable reason: `not_json`, `not_object`,
  /// `incomplete`, `no_fingerprint`, `not_https`, `bad_kind`.
  factory PairingPayload.parse(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw.trim());
    } on FormatException {
      throw const FormatException('not_json');
    }
    if (json is! Map) throw const FormatException('not_object');
    return json['v'] == 2 ? _parseV2(json) : _parseV1(raw);
  }

  static PairingPayload _parseV2(Map json) {
    final url = Uri.tryParse('${json['url'] ?? ''}'.trim());
    final code = '${json['code'] ?? ''}'.trim().toUpperCase();
    if (url == null || url.host.isEmpty || code.isEmpty) throw const FormatException('incomplete');
    final fp = normalizeFingerprint(json['fp'] as String?);
    if (fp == null) throw const FormatException('no_fingerprint');
    if (url.scheme != 'https') throw const FormatException('not_https');
    final kind = PairingKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (kind == null) throw const FormatException('bad_kind');
    final exp = json['exp'];
    final branch = json['branchId'];
    return PairingPayload(
      version: 2,
      kind: kind,
      url: Uri(scheme: 'https', host: url.host, port: url.hasPort ? url.port : 443),
      code: code,
      fingerprint: fp,
      expiresAt: exp is int ? DateTime.fromMillisecondsSinceEpoch(exp) : null,
      branchId: branch is int ? branch : null,
    );
  }

  static PairingPayload _parseV1(String raw) {
    final LanPairingPayload v1;
    try {
      v1 = LanPairingPayload.parse(raw);
    } on FormatException catch (e) {
      throw FormatException(e.message.contains('fingerprint') ? 'no_fingerprint' : 'incomplete');
    }
    return PairingPayload(
      version: 1,
      kind: PairingKind.lan,
      url: v1.baseUri,
      code: v1.pairingCode,
      fingerprint: v1.fingerprint,
    );
  }
}
