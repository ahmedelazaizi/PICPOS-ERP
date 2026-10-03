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

/// Signs like the desktop does. Used by tests and the desktop harness
/// (the production signer lives in the desktop app, M-1).
Future<String> signPayloadForTest(Object? payload, SimpleKeyPair keyPair) async {
  final s = await Ed25519().sign(canonicalJsonBytes(payload), keyPair: keyPair);
  return '$_prefix${base64.encode(s.bytes)}';
}
