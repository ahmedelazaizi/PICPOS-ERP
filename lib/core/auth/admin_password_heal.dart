import '../../services/security_service.dart';

/// Returns whether the stored admin credential is structurally unusable.
/// A valid hash is preserved even when the default password no longer works.
bool adminPasswordNeedsHeal({required String salt, required String hash}) {
  if (hash.isEmpty) return true;
  if (SecurityService.isArgon2Hash(hash)) {
    return hash.split(r'$').length < 6;
  }
  return salt.isEmpty || hash.length < 32;
}
