import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/database/database.dart';

/// Server-side brute-force lockout for the embedded-server credential
/// endpoints (Spec 151 P1-8b).
///
/// The existing [LoginRateLimiter] runs on the CLIENT/UI side
/// (`auth_repository_impl`, `login_screen`, `pos_credential_handler`). The
/// HQ/server process ALSO renders that local login UI in the same isolate, so
/// reusing `LoginRateLimiter`'s static map here would let a remote caller
/// hammering `/api/auth/*` lock out the operator's OWN local UI login for that
/// username — a cross-surface denial of service. This is a deliberately
/// SEPARATE tracker so the two surfaces never contaminate each other.
///
/// FLEET-6: the counters used to live only in process memory, so restarting
/// the main cleared a brute-force lockout. They are now written behind to the
/// host's `settings` table under [settingKey] (a host-local key, listed in
/// `kDeviceLocalSettingKeys`: it never syncs and is never served by
/// `GET /api/settings`) and reloaded by [configure] at start. No schema change.
/// The stored map is bounded ([maxEntries]) and entries older than
/// [lockoutDuration] are dropped on every write. Reads stay synchronous.
///
/// Keyed by an opaque caller-supplied string (the handler derives
/// `u:<username>` for password logins and `c:<hash>` for card-code logins so
/// raw card codes never enter the map). Thresholds mirror [LoginRateLimiter]:
/// 5 failures → 15-minute lockout.
class ServerLoginThrottle {
  ServerLoginThrottle._();

  /// Maximum consecutive failed attempts before lockout.
  static const int maxAttempts = 5;

  /// Duration of lockout after exceeding [maxAttempts].
  static const Duration lockoutDuration = Duration(minutes: 15);

  /// Host-local settings key holding `{key: [failedCount, lastAttemptMs]}`.
  static const String settingKey = 'server_login_throttle_v1';

  /// Hard cap on persisted/in-memory entries (newest win).
  static const int maxEntries = 500;

  static final Map<String, _Attempt> _attempts = <String, _Attempt>{};
  static AppDatabase? _db;
  static Future<void> _chain = Future<void>.value();

  /// Bind the durable store and reload what a previous run persisted.
  /// Idempotent per database instance; the load is serialized before any
  /// write so a partial in-memory map never overwrites the stored one.
  static void configure(AppDatabase db) {
    if (identical(_db, db)) return;
    _db = db;
    _chain = _chain.then((_) => _load(db)).catchError(_swallow);
  }

  /// Completes when every pending load/write has finished (tests, shutdown).
  static Future<void> flush() => _chain;

  /// True when [key] is currently locked out. Auto-clears an expired lockout.
  static bool isLockedOut(String key) {
    final record = _attempts[key];
    if (record == null) return false;
    if (record.failedCount < maxAttempts) return false;

    final elapsed = DateTime.now().difference(record.lastAttempt);
    if (elapsed >= lockoutDuration) {
      // Lockout window elapsed — reset so the caller gets a fresh start.
      _attempts.remove(key);
      _schedulePersist();
      return false;
    }
    return true;
  }

  /// Record a failed credential attempt for [key].
  static void recordFailure(String key) {
    final record = _attempts[key];
    if (record == null) {
      _attempts[key] = _Attempt(failedCount: 1, lastAttempt: DateTime.now());
    } else {
      // If a previous lockout has fully elapsed, start a fresh count.
      final elapsed = DateTime.now().difference(record.lastAttempt);
      if (record.failedCount >= maxAttempts && elapsed >= lockoutDuration) {
        _attempts[key] = _Attempt(failedCount: 1, lastAttempt: DateTime.now());
      } else {
        record.failedCount++;
        record.lastAttempt = DateTime.now();
      }
    }
    _schedulePersist();
  }

  /// Clear the counter for [key] after a successful authentication.
  static void recordSuccess(String key) {
    if (_attempts.remove(key) != null) _schedulePersist();
  }

  /// Clear all state, memory AND the stored map (test hook only).
  static void reset() {
    _attempts.clear();
    _schedulePersist();
  }

  /// Simulates a process restart (test hook only): waits for pending writes,
  /// forgets the memory and the database binding. Call [configure] again to
  /// "start" the new process on the same database.
  static Future<void> restartForTesting() async {
    await _chain;
    _attempts.clear();
    _db = null;
  }

  // ── persistence ───────────────────────────────────────────────────────

  static void _schedulePersist() {
    final db = _db;
    if (db == null) return;
    _chain = _chain.then((_) => _write(db)).catchError(_swallow);
  }

  static void _prune() {
    final now = DateTime.now();
    _attempts.removeWhere(
        (_, a) => now.difference(a.lastAttempt) >= lockoutDuration);
    if (_attempts.length > maxEntries) {
      final newest = _attempts.entries.toList()
        ..sort((a, b) => b.value.lastAttempt.compareTo(a.value.lastAttempt));
      _attempts
        ..clear()
        ..addEntries(newest.take(maxEntries));
    }
  }

  static Future<void> _write(AppDatabase db) async {
    if (!identical(_db, db)) return;
    _prune();
    await db.setSetting(
      settingKey,
      jsonEncode({
        for (final e in _attempts.entries)
          e.key: [e.value.failedCount, e.value.lastAttempt.millisecondsSinceEpoch],
      }),
    );
  }

  static Future<void> _load(AppDatabase db) async {
    final raw = await db.getSettingValue(settingKey);
    if (raw == null || raw.isEmpty || !identical(_db, db)) return;
    final now = DateTime.now();
    try {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
        final list = v as List;
        final count = (list[0] as num).toInt();
        final at = DateTime.fromMillisecondsSinceEpoch((list[1] as num).toInt());
        if (count <= 0 || now.difference(at) >= lockoutDuration) return;
        final mem = _attempts[k];
        if (mem == null || mem.lastAttempt.isBefore(at)) {
          _attempts[k] = _Attempt(failedCount: count, lastAttempt: at);
        }
      });
    } catch (e) {
      debugPrint('[ServerLoginThrottle] ignoring unreadable stored state: $e');
    }
    _prune();
  }

  static void _swallow(Object e, StackTrace st) =>
      debugPrint('[ServerLoginThrottle] persistence skipped: $e');
}

class _Attempt {
  int failedCount;
  DateTime lastAttempt;

  _Attempt({required this.failedCount, required this.lastAttempt});
}
