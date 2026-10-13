import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Versioned offline PIN verifier. Legacy values are recognized only for the
/// one-time migration path and are never written again.
class OfflinePinVerifier {
  static const scheme = 'pbkdf2_sha256';
  static const version = 'v1';
  static const minimumIterations = 100000;
  static const _saltLength = 16;
  static const _derivedKeyLength = 32;

  static String create(String pin) {
    final salt = List<int>.generate(
      _saltLength,
      (_) => Random.secure().nextInt(256),
    );
    final derived = _derive(pin, salt, minimumIterations);
    return [
      scheme,
      version,
      '$minimumIterations',
      _encode(salt),
      _encode(derived),
    ].join('\$');
  }

  static OfflinePinCheck verify(String pin, String? encoded) {
    if (encoded == null) return const OfflinePinCheck(false, false);
    final fields = encoded.split('\$');
    if (fields.length == 5 && fields[0] == scheme) {
      return _verifyCurrent(pin, fields);
    }
    return _verifyLegacy(pin, encoded);
  }

  static OfflinePinCheck _verifyCurrent(String pin, List<String> fields) {
    if (fields[1] != version) return const OfflinePinCheck(false, false);
    final iterations = int.tryParse(fields[2]);
    final salt = _decode(fields[3]);
    final expected = _decode(fields[4]);
    if (iterations == null ||
        iterations < minimumIterations ||
        salt == null ||
        expected == null) {
      return const OfflinePinCheck(false, false);
    }
    if (expected.length != _derivedKeyLength || salt.length < _saltLength) {
      return const OfflinePinCheck(false, false);
    }
    final actual = _derive(pin, salt, iterations);
    return OfflinePinCheck(_sameBytes(actual, expected), false);
  }

  static OfflinePinCheck _verifyLegacy(String pin, String encoded) {
    final fields = encoded.split(':');
    if (fields.length != 2 || fields[0].isEmpty || fields[1].isEmpty) {
      return const OfflinePinCheck(false, false);
    }
    final digest = _legacyHash(pin, fields[0]);
    return OfflinePinCheck(_sameText(digest, fields[1]), true);
  }

  static String _legacyHash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < 20000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64.encode(bytes);
  }

  static List<int> _derive(String pin, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    List<int> block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final derived = List<int>.of(block);
    for (var i = 1; i < iterations; i++) {
      block = hmac.convert(block).bytes;
      for (var j = 0; j < derived.length; j++) {
        derived[j] ^= block[j];
      }
    }
    return derived;
  }

  static String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int>? _decode(String encoded) {
    try {
      final padded = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');
      return base64Url.decode(padded);
    } on FormatException {
      return null;
    }
  }

  static bool _sameText(String left, String right) =>
      _sameBytes(utf8.encode(left), utf8.encode(right));

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }
}

class OfflinePinCheck {
  const OfflinePinCheck(this.matches, this.requiresUpgrade);

  final bool matches;
  final bool requiresUpgrade;
}
