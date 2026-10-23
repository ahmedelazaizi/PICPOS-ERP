import 'dart:convert';

import '../data/database/database.dart';
import 'login_rate_limiter.dart';

/// SEC-009 (audit 2026-10-23): persists [LoginRateLimiter] lockouts in the
/// `settings` table so a restart no longer clears a brute-force lockout.
///
/// Stored as JSON `{key: expiryEpochMs}` under [settingKey]; expired entries
/// are dropped on every write/read. Idempotent per database instance.
class LoginLockoutStore {
  LoginLockoutStore._();

  static const settingKey = 'login_lockouts_v1';
  static AppDatabase? _attached;

  static Future<void> ensureAttached(AppDatabase db) async {
    if (identical(_attached, db)) return;
    _attached = db;
    LoginRateLimiter.onLockoutPersist = (key, expiry) async {
      final map = await _read(db);
      map[key] = expiry;
      await db.setSetting(settingKey, jsonEncode({
        for (final e in map.entries) e.key: e.value.millisecondsSinceEpoch,
      }));
    };
    LoginRateLimiter.onLockoutLoad = () => _read(db);
    await LoginRateLimiter.loadPersistedLockouts();
  }

  static Future<Map<String, DateTime>> _read(AppDatabase db) async {
    final raw = await db.getSettingValue(settingKey);
    final out = <String, DateTime>{};
    if (raw == null || raw.isEmpty) return out;
    try {
      final now = DateTime.now();
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
        final at = DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
        if (at.isAfter(now)) out[k] = at;
      });
    } catch (_) {}
    return out;
  }

  /// Test hook.
  static void detachForTesting() {
    _attached = null;
    LoginRateLimiter.onLockoutPersist = null;
    LoginRateLimiter.onLockoutLoad = null;
  }
}
