/// Ed25519 verification of desktop-signed payloads (ARCHITECTURE-M ADR-M2).
///
/// The desktop generates the key pair at link time; the phone pins the
/// public key from the pairing QR (never from the cloud). Signatures travel
/// as `ed25519:<base64 of 64 bytes>` over [canonicalJsonBytes] of the payload.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'canonical_json.dart';

const _prefix = 'ed25519:';

/// Human-comparable fingerprint of a signing public key (M-5): SHA-256 of the
/// raw 32 key bytes, first 16 bytes as 8 groups of 4 upper-case hex digits
/// (`A1B2 C3D4 ...`). Shown at pairing so the user can compare it with the one
/// on the office computer before trusting a key delivered by the cloud.
/// Throws [FormatException] when [publicKeyBase64] is not a 32-byte key.
Future<String> signingKeyFingerprint(String publicKeyBase64) async {
  final bytes = base64.decode(publicKeyBase64.trim());
  if (bytes.length != 32) throw const FormatException('Ed25519 public key must be 32 bytes');
  final digest = (await Sha256().hash(bytes)).bytes.take(16);
  final hex = [for (final b in digest) b.toRadixString(16).padLeft(2, '0')].join().toUpperCase();
  return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)].join(' ');
}

/// Verifies payloads against the pinned desktop signing key.
class PayloadVerifier {
  PayloadVerifier._(this._key);

  /// [publicKeyBase64] is the raw 32-byte Ed25519 public key in base64.
  /// Throws [FormatException] when it is not a valid key encoding.
  factory PayloadVerifier.fromBase64(String publicKeyBase64) {
    final bytes = base64.decode(publicKeyBase64.trim());
    if (bytes.length != 32) throw const FormatException('Ed25519 public key must be 32 bytes');
    return PayloadVerifier._(SimplePublicKey(bytes, type: KeyPairType.ed25519));
  }

  final SimplePublicKey _key;
  static final _algorithm = Ed25519();

  /// True only when [signature] is a well-formed `ed25519:` signature of the
  /// canonical form of [payload] by the pinned key. Never throws: anything
  /// malformed (bad prefix, bad base64, wrong length, non-canonical payload
  /// such as a double) is simply "not verified".
  Future<bool> verify(Object? payload, String? signature) async {
    if (signature == null || !signature.startsWith(_prefix)) return false;
    final List<int> sig;
    final List<int> message;
    try {
      sig = base64.decode(signature.substring(_prefix.length));
      message = canonicalJsonBytes(payload);
    } on FormatException {
      return false;
    } on CanonicalJsonException {
      return false;
    }
    if (sig.length != 64) return false;
    return _algorithm.verify(message, signature: Signature(sig, publicKey: _key));
  }
}

/// Signs like the desktop does. Used by tests and the desktop harness.
Future<String> signPayloadForTest(Object? payload, SimpleKeyPair keyPair) async {
  final s = await Ed25519().sign(canonicalJsonBytes(payload), keyPair: keyPair);
  return '$_prefix${base64.encode(s.bytes)}';
}

/// The desktop's signer (M-1): an Ed25519 key pair restored from its 32-byte
/// seed (kept in the desktop's secure storage; only the public key leaves).
class PayloadSigner {
  PayloadSigner._(this._keyPair);

  /// Restores the key pair from a 32-byte private seed.
  static Future<PayloadSigner> fromSeed(List<int> seed) async {
    if (seed.length != 32) throw const FormatException('Ed25519 seed must be 32 bytes');
    return PayloadSigner._(await Ed25519().newKeyPairFromSeed(seed));
  }

  /// A fresh random 32-byte seed (store it, never send it anywhere).
  static List<int> newSeed() => SecretKeyData.random(length: 32).bytes;

  final SimpleKeyPair _keyPair;

  /// Raw 32-byte public key, base64 (what the cloud and the phone pin).
  Future<String> publicKeyBase64() async => base64.encode((await _keyPair.extractPublicKey()).bytes);

  /// `ed25519:<base64>` over [canonicalJsonBytes] of [payload].
  Future<String> sign(Object? payload) => signPayloadForTest(payload, _keyPair);
}
