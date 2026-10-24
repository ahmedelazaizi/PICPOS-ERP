// Password policy for passwords a USER sets for himself (plan 2026-10-24,
// B.7.1 / decision D.4): at least [kMinPasswordLength] characters, different
// from the current password and from the username. Passwords that already
// exist stay valid; the rule applies to NEW passwords only.

/// Minimum length of a newly chosen password.
const int kMinPasswordLength = 8;

/// Machine-readable rejection codes, shared by the API and the clients.
abstract final class PasswordPolicyCode {
  static const String tooShort = 'password_too_short';
  static const String sameAsCurrent = 'password_same_as_current';
  static const String sameAsUsername = 'password_same_as_username';
}

/// Returns a [PasswordPolicyCode] when [next] is unacceptable, else `null`.
/// [current] is `null` when the caller proves identity another way (card).
String? validateNewPassword(String username, String? current, String next) {
  if (next.length < kMinPasswordLength) return PasswordPolicyCode.tooShort;
  if (current != null && next == current) return PasswordPolicyCode.sameAsCurrent;
  if (next.toLowerCase() == username.trim().toLowerCase()) {
    return PasswordPolicyCode.sameAsUsername;
  }
  return null;
}
