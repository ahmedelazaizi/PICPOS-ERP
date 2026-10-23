import 'security_service.dart';

/// SEC-004: a credential nobody knows.
///
/// A user row can reach a client without credentials (pre-login pull). The old
/// code minted the predictable `<username>123`; this mints a random secret that
/// is hashed and immediately discarded, so the account cannot be logged into
/// until the host delivers a real credential (`force_password_change` stays set).
class UnusableCredential {
  UnusableCredential._();

  static Future<({String hash, String salt})> mint() async {
    final secret = SecurityService.generateSalt();
    return (
      hash: await SecurityService.hashPasswordArgon2(secret),
      salt: SecurityService.generateSalt(),
    );
  }
}
