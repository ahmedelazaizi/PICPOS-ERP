/// The «PicPos إدارة» mobile password hash (ADR-M3): PBKDF2-HMAC-SHA256,
/// 32-byte key, 16-byte salt, stored as `pbkdf2$<iter>$<saltB64>$<hashB64>` —
/// byte-compatible with the cloud's `hashPin`/`verifyPin`
/// (server/lib/src/security.dart). Computed on the desktop (and later by the
/// phone for `user.change_mobile_password`); the plaintext never travels.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

const kMobilePasswordIterations = 120000;
const kMobilePasswordMinLength = 8;

/// Matches digits entered on Arabic/Persian keyboards to ASCII credentials.
String normalizeCredential(String credential) => String.fromCharCodes([
      for (final digit in credential.trim().codeUnits)
        if (digit >= 0x0660 && digit <= 0x0669)
          digit - 0x0660 + 0x30
        else if (digit >= 0x06f0 && digit <= 0x06f9)
          digit - 0x06f0 + 0x30
        else
          digit,
    ]);

Future<String> hashMobilePassword(String password,
    {int iterations = kMobilePasswordIterations, List<int>? salt}) async {
  final s = salt ?? List<int>.generate(16, (_) => Random.secure().nextInt(256));
  final dk = await _derive(password, s, iterations);
  return 'pbkdf2\$$iterations\$${base64.encode(s)}\$${base64.encode(dk)}';
}

Future<bool> verifyMobilePassword(String password, String stored) async {
  final p = stored.split('\$');
  if (p.length != 4 || p[0] != 'pbkdf2') return false;
  final it = int.tryParse(p[1]);
  if (it == null || it < 1) return false;
  try {
    final dk = await _derive(password, base64.decode(p[2]), it);
    final want = base64.decode(p[3]);
    if (want.length != dk.length) return false;
    var diff = 0;
    for (var i = 0; i < dk.length; i++) {
      diff |= dk[i] ^ want[i];
    }
    return diff == 0;
  } on FormatException {
    return false;
  }
}

Future<List<int>> _derive(String password, List<int> salt, int iterations) async {
  final k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
      .deriveKeyFromPassword(password: password, nonce: salt);
  return k.extractBytes();
}
