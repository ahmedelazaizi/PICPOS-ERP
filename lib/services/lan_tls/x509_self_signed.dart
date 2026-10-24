// SEC-007 — minimal pure-Dart self-signed X.509 certificate generator.
//
// Dart's `dart:io` can load a certificate into a `SecurityContext` but cannot
// create one, and Windows has no `openssl`. The embedded LAN server therefore
// generates its own certificate on first run: ECDSA P-256 / SHA-256, v3,
// serverAuth, with SAN entries for the addresses the host is reached on.
//
// Trust is NOT chain based: clients pin the SHA-256 fingerprint of the DER
// certificate (see `TlsTrust`), delivered in the pairing QR / code. So the
// certificate being self-signed is by design; only its fingerprint matters.
//
// The private key is returned as PEM for the caller to keep in secure storage;
// this file never touches disk.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// A freshly generated certificate + key pair.
class SelfSignedCertificate {
  const SelfSignedCertificate({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprintSha256,
    required this.notBefore,
    required this.notAfter,
  });

  final String certificatePem;
  final String privateKeyPem;

  /// SHA-256 of the DER certificate, lower-case hex (what `TlsTrust` pins).
  final String fingerprintSha256;
  final DateTime notBefore;
  final DateTime notAfter;
}

/// Generates a self-signed ECDSA P-256 server certificate.
///
/// [dnsNames] / [ipAddresses] go into the SubjectAltName extension.
SelfSignedCertificate generateSelfSignedCertificate({
  String commonName = 'PicPos LAN Server',
  List<String> dnsNames = const ['localhost'],
  List<String> ipAddresses = const ['127.0.0.1'],
  int validityDays = 3650,
  DateTime? now,
  Random? random,
}) {
  final rng = random ?? Random.secure();
  final secureRandom = _seededRandom(rng);
  final domain = ECDomainParameters('prime256v1');

  final keyGen = ECKeyGenerator()
    ..init(ParametersWithRandom(ECKeyGeneratorParameters(domain), secureRandom));
  final pair = keyGen.generateKeyPair();
  final publicKey = pair.publicKey;
  final privateKey = pair.privateKey;
  final publicPoint = publicKey.Q!.getEncoded(false); // 04 || X || Y

  final notBefore = (now ?? DateTime.now()).toUtc().subtract(const Duration(hours: 1));
  final notAfter = notBefore.add(Duration(days: validityDays));

  final serial = Uint8List.fromList(
    List<int>.generate(16, (_) => rng.nextInt(256)),
  )..[0] &= 0x7f; // positive
  if (serial[0] == 0) serial[0] = 1;

  final name = _seq([
    _set([
      _seq([_oid(const [2, 5, 4, 3]), _utf8(commonName)]),
    ]),
  ]);
  final sigAlg = _seq([_oid(const [1, 2, 840, 10045, 4, 3, 2])]); // ecdsa-with-SHA256

  final spki = _seq([
    _seq([
      _oid(const [1, 2, 840, 10045, 2, 1]), // id-ecPublicKey
      _oid(const [1, 2, 840, 10045, 3, 1, 7]), // prime256v1
    ]),
    _bitString(publicPoint),
  ]);

  final san = _seq([
    for (final d in dnsNames) _tlv(0x82, ascii.encode(d)),
    for (final ip in ipAddresses)
      if (_ipBytes(ip) case final bytes?) _tlv(0x87, bytes),
  ]);

  final extensions = _tlv(0xa3, _seq([
    // basicConstraints: critical, CA:FALSE
    _seq([
      _oid(const [2, 5, 29, 19]),
      _boolTrue(),
      _octet(_seq(const [])),
    ]),
    // keyUsage: critical, digitalSignature
    _seq([
      _oid(const [2, 5, 29, 15]),
      _boolTrue(),
      _octet(_tlv(0x03, Uint8List.fromList(const [0x07, 0x80]))),
    ]),
    // extendedKeyUsage: serverAuth
    _seq([
      _oid(const [2, 5, 29, 37]),
      _octet(_seq([_oid(const [1, 3, 6, 1, 5, 5, 7, 3, 1])])),
    ]),
    // subjectAltName
    _seq([_oid(const [2, 5, 29, 17]), _octet(san)]),
  ]));

  final tbs = _seq([
    _tlv(0xa0, _int(BigInt.from(2))), // version v3
    _tlv(0x02, serial),
    sigAlg,
    name, // issuer == subject (self-signed)
    _seq([_time(notBefore), _time(notAfter)]),
    name,
    spki,
    extensions,
  ]);

  final signer = ECDSASigner(SHA256Digest())
    ..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(privateKey), secureRandom));
  final signature = signer.generateSignature(tbs) as ECSignature;
  final sigDer = _seq([_int(signature.r), _int(signature.s)]);

  final certDer = _seq([tbs, sigAlg, _bitString(sigDer)]);

  // PKCS#8 PrivateKeyInfo wrapping the SEC1 ECPrivateKey.
  final sec1 = _seq([
    _int(BigInt.one),
    _octet(_bigIntBytes(privateKey.d!, 32)),
    _tlv(0xa0, _oid(const [1, 2, 840, 10045, 3, 1, 7])),
    _tlv(0xa1, _bitString(publicPoint)),
  ]);
  final pkcs8 = _seq([
    _int(BigInt.zero),
    _seq([
      _oid(const [1, 2, 840, 10045, 2, 1]),
      _oid(const [1, 2, 840, 10045, 3, 1, 7]),
    ]),
    _octet(sec1),
  ]);

  return SelfSignedCertificate(
    certificatePem: _pem('CERTIFICATE', certDer),
    privateKeyPem: _pem('PRIVATE KEY', pkcs8),
    fingerprintSha256: sha256.convert(certDer).toString(),
    notBefore: notBefore,
    notAfter: notAfter,
  );
}

/// DER bytes of the first certificate in a PEM string, or null.
Uint8List? certificateDerFromPem(String pem) {
  const begin = '-----BEGIN CERTIFICATE-----';
  const end = '-----END CERTIFICATE-----';
  final a = pem.indexOf(begin);
  if (a < 0) return null;
  final b = pem.indexOf(end, a);
  if (b < 0) return null;
  final body = pem.substring(a + begin.length, b).replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
  if (body.isEmpty) return null;
  try {
    return base64.decode(body);
  } on FormatException {
    return null;
  }
}

/// `notAfter` of a DER certificate produced by [generateSelfSignedCertificate]
/// (and any standard X.509), or null when it cannot be parsed.
DateTime? certificateNotAfter(Uint8List der) {
  try {
    // Cert ::= SEQ { tbs SEQ { [0] version, serial, sigAlg, issuer, validity ... } ... }
    final cert = _DerReader(der).read();
    final tbs = _DerReader(cert.value).read();
    final r = _DerReader(tbs.value);
    var el = r.read();
    if (el.tag == 0xa0) el = r.read(); // version (optional)
    // el = serial
    r.read(); // sigAlg
    r.read(); // issuer
    final validity = _DerReader(r.read().value);
    validity.read(); // notBefore
    final nb = validity.read();
    return _parseTime(nb);
  } catch (_) {
    return null;
  }
}

// ── randomness ──────────────────────────────────────────────────────────────

SecureRandom _seededRandom(Random rng) {
  final fortuna = FortunaRandom();
  fortuna.seed(KeyParameter(Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)))));
  return fortuna;
}

// ── DER encoding helpers ────────────────────────────────────────────────────

Uint8List _tlv(int tag, List<int> value) {
  final len = value.length;
  final out = BytesBuilder()..addByte(tag);
  if (len < 0x80) {
    out.addByte(len);
  } else {
    final bytes = <int>[];
    var n = len;
    while (n > 0) {
      bytes.insert(0, n & 0xff);
      n >>= 8;
    }
    out
      ..addByte(0x80 | bytes.length)
      ..add(bytes);
  }
  out.add(value);
  return out.toBytes();
}

Uint8List _concat(Iterable<List<int>> parts) {
  final b = BytesBuilder();
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

Uint8List _seq(List<List<int>> items) => _tlv(0x30, _concat(items));
Uint8List _set(List<List<int>> items) => _tlv(0x31, _concat(items));
Uint8List _octet(List<int> v) => _tlv(0x04, v);
Uint8List _utf8(String s) => _tlv(0x0c, utf8.encode(s));
Uint8List _boolTrue() => _tlv(0x01, const [0xff]);
Uint8List _bitString(List<int> v) => _tlv(0x03, [0x00, ...v]);

Uint8List _int(BigInt v) {
  var bytes = _bigIntBytes(v, 1);
  if (bytes[0] & 0x80 != 0) bytes = Uint8List.fromList([0, ...bytes]);
  return _tlv(0x02, bytes);
}

Uint8List _bigIntBytes(BigInt v, int minLen) {
  final out = <int>[];
  var n = v;
  while (n > BigInt.zero) {
    out.insert(0, (n & BigInt.from(0xff)).toInt());
    n >>= 8;
  }
  while (out.length < minLen) {
    out.insert(0, 0);
  }
  return Uint8List.fromList(out);
}

Uint8List _oid(List<int> arcs) {
  final out = <int>[arcs[0] * 40 + arcs[1]];
  for (final arc in arcs.skip(2)) {
    final chunk = <int>[arc & 0x7f];
    var n = arc >> 7;
    while (n > 0) {
      chunk.insert(0, 0x80 | (n & 0x7f));
      n >>= 7;
    }
    out.addAll(chunk);
  }
  return _tlv(0x06, out);
}

Uint8List _time(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final u = t.toUtc();
  if (u.year < 2050) {
    final yy = two(u.year % 100);
    return _tlv(0x17, ascii.encode('$yy${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z'));
  }
  return _tlv(0x18, ascii.encode('${u.year}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z'));
}

DateTime? _parseTime(_DerElement el) {
  final s = ascii.decode(el.value);
  try {
    if (el.tag == 0x17) {
      final yy = int.parse(s.substring(0, 2));
      final year = yy >= 50 ? 1900 + yy : 2000 + yy;
      return DateTime.utc(year, int.parse(s.substring(2, 4)), int.parse(s.substring(4, 6)),
          int.parse(s.substring(6, 8)), int.parse(s.substring(8, 10)), int.parse(s.substring(10, 12)));
    }
    if (el.tag == 0x18) {
      return DateTime.utc(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)),
          int.parse(s.substring(8, 10)), int.parse(s.substring(10, 12)), int.parse(s.substring(12, 14)));
    }
  } catch (_) {}
  return null;
}

Uint8List? _ipBytes(String ip) {
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(ip.trim());
  if (v4 == null) return null;
  final parts = [for (var i = 1; i <= 4; i++) int.parse(v4.group(i)!)];
  if (parts.any((p) => p > 255)) return null;
  return Uint8List.fromList(parts);
}

String _pem(String label, List<int> der) {
  final b64 = base64.encode(der);
  final lines = <String>[
    for (var i = 0; i < b64.length; i += 64) b64.substring(i, min(i + 64, b64.length)),
  ];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

// ── tiny DER reader (only what certificateNotAfter needs) ───────────────────

class _DerElement {
  _DerElement(this.tag, this.value);
  final int tag;
  final Uint8List value;
}

class _DerReader {
  _DerReader(this._bytes);
  final Uint8List _bytes;
  int _pos = 0;

  _DerElement read() {
    final tag = _bytes[_pos++];
    var len = _bytes[_pos++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | _bytes[_pos++];
      }
    }
    final value = Uint8List.sublistView(_bytes, _pos, _pos + len);
    _pos += len;
    return _DerElement(tag, value);
  }
}
