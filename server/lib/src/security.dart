import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final Random _rng = Random.secure();

/// Same alphabet rule as desktop LAN pairing: no look-alike characters.
const String kPairingAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String randomPairingCode([int length = 8]) => List.generate(
      length,
      (_) => kPairingAlphabet[_rng.nextInt(kPairingAlphabet.length)],
    ).join();

String randomToken([int bytes = 32]) => base64Url
    .encode(List<int>.generate(bytes, (_) => _rng.nextInt(256)))
    .replaceAll('=', '');

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// PBKDF2-HMAC-SHA256, stored as `pbkdf2$iter$saltB64$hashB64`.
String hashPin(String pin, {int iterations = 120000, List<int>? salt}) {
  final s = salt ?? List<int>.generate(16, (_) => _rng.nextInt(256));
  final dk = _pbkdf2(utf8.encode(pin), s, iterations, 32);
  return 'pbkdf2\$$iterations\$${base64.encode(s)}\$${base64.encode(dk)}';
}

bool verifyPin(String pin, String stored) {
  final parts = stored.split('\$');
  if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
  final iter = int.tryParse(parts[1]);
  if (iter == null) return false;
  final salt = base64.decode(parts[2]);
  final dk = _pbkdf2(utf8.encode(pin), salt, iter, 32);
  return constantTimeEquals(base64.encode(dk), parts[3]);
}

Uint8List _pbkdf2(List<int> password, List<int> salt, int iter, int len) {
  final hmac = Hmac(sha256, password);
  final out = BytesBuilder();
  var block = 1;
  while (out.length < len) {
    final b = Uint8List(4)..buffer.asByteData().setUint32(0, block);
    var u = hmac.convert([...salt, ...b]).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iter; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
    block++;
  }
  return Uint8List.fromList(out.toBytes().sublist(0, len));
}

/// Session token: base64url(json{uid,did,cid,exp}).hmac — same idea as the
/// desktop `api_session_token.dart` (HMAC of {uid, exp}), plus device/company.
class SessionTokens {
  SessionTokens(this.secret, {this.ttl = const Duration(hours: 12)});
  final String secret;
  final Duration ttl;

  String issue({required int employeeId, required int devicePk, required int companyId}) {
    final body = base64Url.encode(utf8.encode(jsonEncode({
      'uid': employeeId,
      'did': devicePk,
      'cid': companyId,
      'exp': DateTime.now().add(ttl).millisecondsSinceEpoch,
    })));
    return '$body.${_sig(body)}';
  }

  /// Returns the claims or null when invalid/expired.
  Map<String, dynamic>? verify(String token) {
    final i = token.lastIndexOf('.');
    if (i <= 0) return null;
    final body = token.substring(0, i);
    if (!constantTimeEquals(_sig(body), token.substring(i + 1))) return null;
    try {
      final m = jsonDecode(utf8.decode(base64Url.decode(body))) as Map<String, dynamic>;
      if ((m['exp'] as int) < DateTime.now().millisecondsSinceEpoch) return null;
      return m;
    } catch (_) {
      return null;
    }
  }

  String _sig(String body) =>
      Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(body)).toString();
}
