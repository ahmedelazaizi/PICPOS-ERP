/// Login Rate Limiter — prevents brute-force password attacks.
///
/// Tracks failed login attempts per username and enforces:
/// - Maximum 5 consecutive failed attempts
/// - 15-minute lockout after exceeding the limit
/// - Automatic reset after successful login or lockout expiry
///
/// SEC02: Hybrid approach — in-memory for speed + persistent callback
/// for surviving app restarts on critical lockouts.
class LoginRateLimiter {
  LoginRateLimiter._();

  static final _attempts = <String, _LoginAttemptRecord>{};

  /// SEC02: Optional persistence callback — set by the app to persist lockouts.
  /// Called when a user reaches max attempts. Format: `(username, lockoutExpiry)`
  static Future<void> Function(String username, DateTime lockoutExpiry)?
      onLockoutPersist;

  /// SEC02: Optional load callback — restores persisted lockouts on startup.
  /// Returns `Map<username, lockoutExpiry>` for active lockouts.
  static Future<Map<String, DateTime>> Function()? onLockoutLoad;

  /// SEC02: Load persisted lockouts into memory (call once on app startup).
  static Future<void> loadPersistedLockouts() async {
    if (onLockoutLoad == null) return;
    try {
      final persisted = await onLockoutLoad!();
      final now = DateTime.now();
      for (final entry in persisted.entries) {
        if (entry.value.isAfter(now)) {
          _attempts[entry.key.toLowerCase()] = _LoginAttemptRecord(
            failedCount: maxAttempts,
            lastAttempt: entry.value.subtract(lockoutDuration),
          );
        }
      }
    } catch (_) {
      // Persistence unavailable — continue with in-memory only
    }
  }

  /// Maximum consecutive failed attempts before lockout.
  static const int maxAttempts = 5;

  /// Duration of lockout after exceeding max attempts.
  static const Duration lockoutDuration = Duration(minutes: 15);

  /// Check if a username is currently locked out.
  /// Returns null if not locked, or the remaining lockout duration.
  static Duration? getLockoutRemaining(String username) {
    final record = _attempts[username.toLowerCase()];
    if (record == null) return null;
    if (record.failedCount < maxAttempts) return null;

    final elapsed = DateTime.now().difference(record.lastAttempt);
    if (elapsed >= lockoutDuration) {
      // Lockout expired — reset
      _attempts.remove(username.toLowerCase());
      return null;
    }

    return lockoutDuration - elapsed;
  }

  /// Returns true if the user is allowed to attempt login.
  static bool isAllowed(String username) {
    return getLockoutRemaining(username) == null;
  }

  /// Record a failed login attempt. Returns remaining attempts.
  static int recordFailure(String username) {
    final key = username.toLowerCase();
    final record = _attempts[key];

    if (record == null) {
      _attempts[key] = _LoginAttemptRecord(
        failedCount: 1,
        lastAttempt: DateTime.now(),
      );
      return maxAttempts - 1;
    }

    // If lockout expired, start fresh
    final elapsed = DateTime.now().difference(record.lastAttempt);
    if (record.failedCount >= maxAttempts && elapsed >= lockoutDuration) {
      _attempts[key] = _LoginAttemptRecord(
        failedCount: 1,
        lastAttempt: DateTime.now(),
      );
      return maxAttempts - 1;
    }

    record.failedCount++;
    record.lastAttempt = DateTime.now();

    // SEC02: Persist lockout when max attempts reached
    if (record.failedCount >= maxAttempts && onLockoutPersist != null) {
      final expiry = DateTime.now().add(lockoutDuration);
      onLockoutPersist!(key, expiry).catchError((_) {});
    }

    return maxAttempts - record.failedCount;
  }

  /// Reset attempts after successful login.
  static void recordSuccess(String username) {
    _attempts.remove(username.toLowerCase());
  }

  /// Get the number of remaining attempts for a username.
  static int remainingAttempts(String username) {
    final record = _attempts[username.toLowerCase()];
    if (record == null) return maxAttempts;
    if (record.failedCount >= maxAttempts) return 0;
    return maxAttempts - record.failedCount;
  }

  /// Clear all records (for testing purposes).
  static void reset() => _attempts.clear();
}

class _LoginAttemptRecord {
  int failedCount;
  DateTime lastAttempt;

  _LoginAttemptRecord({
    required this.failedCount,
    required this.lastAttempt,
  });
}
