import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'db_key_types.dart';

class RecoveryCodeException implements Exception {
  const RecoveryCodeException(this.message);
  final String message;
  @override
  String toString() => 'RecoveryCodeException: $message';
}

/// رمزُ استرداد 160-بت (20 بايت) بصيغة Base32 (32 حرفًا) في مجموعات
/// `XXXX-XXXX-…`. يُعرَض للمدير مرّةً واحدة.
class RecoveryCode {
  RecoveryCode._();

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static const int _bytes = 20;

  static String generate({List<int> Function(int n)? randomBytes}) {
    final bytes = (randomBytes ?? _secureBytes)(_bytes);
    if (bytes.length != _bytes) {
      throw ArgumentError('recovery code needs $_bytes bytes');
    }
    final raw = _base32(bytes);
    return [
      for (var i = 0; i < raw.length; i += 4) raw.substring(i, i + 4),
    ].join('-');
  }

  /// يُسقط الفواصلَ والمسافات ويحوّل للأحرف الكبيرة؛ يرمي [FormatException]
  /// إن لم يكن 32 حرفًا من الأبجديّة.
  static String normalize(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (s.length != 32 || !RegExp(r'^[A-Z2-7]{32}$').hasMatch(s)) {
      throw const FormatException('invalid recovery code format');
    }
    return s;
  }

  static List<int> _secureBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static String _base32(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }
}

/// غلافُ استرداد: `AES-256-GCM(KEK, dbKey)` حيث
/// `KEK = Argon2id(code, salt)`. الرمزُ عاليُ الإنتروبيا (160-بت) فتكفي
/// معاملاتٌ معتدلة (نفسُ معاملات `SecurityService`: 4MB/3/1).
class RecoveryEnvelope {
  RecoveryEnvelope._();

  static const String _aad = 'picpos-dbkey-recovery-v1';
  static const int defaultMemoryKb = 4096;
  static const int defaultIterations = 3;

  static Argon2id _kdf(int m, int t, int p) => Argon2id(
        parallelism: p,
        memory: m,
        iterations: t,
        hashLength: 32,
      );

  /// يغلّف مفتاحًا خامًّا (hex 64) بـ[code]. [memoryKb]/[iterations] للاختبار.
  static Future<Map<String, dynamic>> wrap(
    String keyHex,
    String code, {
    int memoryKb = defaultMemoryKb,
    int iterations = defaultIterations,
    List<int> Function(int n)? randomBytes,
  }) async {
    if (!isValidRawKeyHex(keyHex)) {
      throw ArgumentError('keyHex must be 64 lowercase hex chars');
    }
    final norm = RecoveryCode.normalize(code);
    final rnd = randomBytes ?? _secure;
    final salt = rnd(16);
    final nonce = rnd(12);
    final kek = await _kdf(memoryKb, iterations, 1)
        .deriveKey(secretKey: SecretKey(utf8.encode(norm)), nonce: salt);
    final box = await AesGcm.with256bits().encrypt(
      hexToBytes(keyHex),
      secretKey: kek,
      nonce: nonce,
      aad: utf8.encode(_aad),
    );
    return {
      'v': 1,
      'kdf': 'argon2id',
      'm': memoryKb,
      't': iterations,
      'p': 1,
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'ct': base64.encode(box.cipherText),
      'mac': base64.encode(box.mac.bytes),
    };
  }

  /// يفكّ الغلافَ ويعيد المفتاحَ hex. رمزٌ خاطئ أو غلافٌ تالف ⇒
  /// [RecoveryCodeException] دون أيّ أثرٍ جانبيّ.
  static Future<String> unwrap(Map<String, dynamic> env, String code) async {
    final String norm;
    try {
      norm = RecoveryCode.normalize(code);
    } on FormatException {
      throw const RecoveryCodeException('رمز الاسترداد بصيغة غير صحيحة');
    }
    try {
      if (env['v'] != 1 || env['kdf'] != 'argon2id') {
        throw const RecoveryCodeException('unsupported envelope');
      }
      final m = (env['m'] as num).toInt();
      final t = (env['t'] as num).toInt();
      final p = (env['p'] as num).toInt();
      final kek = await _kdf(m, t, p).deriveKey(
        secretKey: SecretKey(utf8.encode(norm)),
        nonce: base64.decode(env['salt'] as String),
      );
      final plain = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64.decode(env['ct'] as String),
          nonce: base64.decode(env['nonce'] as String),
          mac: Mac(base64.decode(env['mac'] as String)),
        ),
        secretKey: kek,
        aad: utf8.encode(_aad),
      );
      final hex = bytesToHex(plain);
      if (!isValidRawKeyHex(hex)) {
        throw const RecoveryCodeException('corrupt envelope payload');
      }
      return hex;
    } on RecoveryCodeException {
      rethrow;
    } catch (_) {
      throw const RecoveryCodeException('رمز الاسترداد خاطئ أو الغلاف تالف');
    }
  }

  static List<int> _secure(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }
}
