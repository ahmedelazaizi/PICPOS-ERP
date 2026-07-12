/// Server-side brute-force lockout for the embedded-server credential
/// endpoints (Spec 151 P1-8b).
///
/// The existing [LoginRateLimiter] runs on the CLIENT/UI side
/// (`auth_repository_impl`, `login_screen`, `pos_credential_handler`). The
/// HQ/server process ALSO renders that local login UI in the same isolate, so
/// reusing `LoginRateLimiter`'s static map here would let a remote caller
/// hammering `/api/auth/*` lock out the operator's OWN local UI login for that
/// username — a cross-surface denial of service. This is a deliberately
/// SEPARATE in-memory tracker so the two surfaces never contaminate each other.
///
/// Purely in-memory (no schema, no persistence). Keyed by an opaque caller-
/// supplied string (the handler derives `u:<username>` for password logins and
/// `c:<hash>` for card-code logins so raw card codes never enter the map).
/// Thresholds mirror [LoginRateLimiter]: 5 failures → 15-minute lockout.
class ServerLoginThrottle {
  ServerLoginThrottle._();

  /// Maximum consecutive failed attempts before lockout.
  static const int maxAttempts = 5;

  /// Duration of lockout after exceeding [maxAttempts].
  static const Duration lockoutDuration = Duration(minutes: 15);

  static final Map<String, _Attempt> _attempts = <String, _Attempt>{};

  /// True when [key] is currently locked out. Auto-clears an expired lockout.
  static bool isLockedOut(String key) {
    final record = _attempts[key];
    if (record == null) return false;
    if (record.failedCount < maxAttempts) return false;

    final elapsed = DateTime.now().difference(record.lastAttempt);
    if (elapsed >= lockoutDuration) {
      // Lockout window elapsed — reset so the caller gets a fresh start.
      _attempts.remove(key);
      return false;
    }
    return true;
  }

  /// Record a failed credential attempt for [key].
  static void recordFailure(String key) {
    final record = _attempts[key];
    if (record == null) {
      _attempts[key] = _Attempt(failedCount: 1, lastAttempt: DateTime.now());
      return;
    }
    // If a previous lockout has fully elapsed, start a fresh count.
    final elapsed = DateTime.now().difference(record.lastAttempt);
    if (record.failedCount >= maxAttempts && elapsed >= lockoutDuration) {
      _attempts[key] = _Attempt(failedCount: 1, lastAttempt: DateTime.now());
      return;
    }
    record.failedCount++;
    record.lastAttempt = DateTime.now();
  }

  /// Clear the counter for [key] after a successful authentication.
  static void recordSuccess(String key) {
    _attempts.remove(key);
  }

  /// Clear all state (test hook only).
  static void reset() => _attempts.clear();
}

class _Attempt {
  int failedCount;
  DateTime lastAttempt;

  _Attempt({required this.failedCount, required this.lastAttempt});
}
