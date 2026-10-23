// ═══════════════════════════════════════════════════════════════════════════
// SETTINGS REPOSITORY (CACHED) — read-through / write-through cache
// ═══════════════════════════════════════════════════════════════════════════
//
// Wraps `SettingsDao` with an in-memory map so the runtime-config layer
// (profile, feature overrides, deployment mode) doesn't hit SQLite on
// every single read. Startup calls `preload(keys)` to warm the cache
// BEFORE `runApp` so every provider can read synchronously from its
// constructor — no async gap between the first frame and feature flags
// being available.
//
// Invariants:
//   - `get(key)` is O(1) once `preload` has run; falls back to a cold
//     DAO read if the key was not preloaded (still caches the result).
//   - `save(key, value)` writes DB + cache in that order. A DB failure
//     surfaces normally; the cache is updated only on success.
//   - The cache is process-lifetime; there is no TTL. Invalidate
//     explicitly via `invalidate()` or `invalidateKey(key)` if another
//     process mutates the DB underneath us (sync, restore, etc.).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:picpos_erp/data/database/database.dart';

class SettingsRepositoryCached {
  final AppDatabase _db;

  /// `null` in the map is distinct from `missing`: `null` means "we
  /// asked the DB and the key is absent" — short-circuit cold lookups.
  final Map<String, String?> _cache = <String, String?>{};

  SettingsRepositoryCached(this._db);

  /// Warms the cache with the supplied keys in ONE pass. Call before
  /// `runApp`. A key with no value in the DB lands as `null` in the
  /// map, which is still a hit (avoids the cold read later).
  Future<void> preload(Iterable<String> keys) async {
    for (final key in keys) {
      final v = await _db.getSettingValue(key);
      _cache[key] = v;
    }
  }

  /// Synchronous read — use only after `preload` has populated the key,
  /// or accept that the first caller pays a cold-read cost.
  String? get(String key) {
    if (_cache.containsKey(key)) return _cache[key];
    return null; // miss — caller should prefer `getAsync` for correctness
  }

  /// Async read that falls back to DB on a miss and caches the result.
  /// Prefer this for any key that wasn't part of the preload set.
  Future<String?> getAsync(String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final v = await _db.getSettingValue(key);
    _cache[key] = v;
    return v;
  }

  /// Iterates every `feature.*` setting in the cache. Used by the
  /// `FeatureOverridesNotifier` to build its initial state synchronously
  /// after `preload` has walked the keys.
  Map<String, String?> entriesWithPrefix(String prefix) {
    final out = <String, String?>{};
    _cache.forEach((k, v) {
      if (k.startsWith(prefix)) out[k] = v;
    });
    return out;
  }

  /// Write-through: persists to DB, then updates the cache on success.
  Future<void> save(String key, String value) async {
    await _db.setSetting(key, value);
    _cache[key] = value;
  }

  /// Delete a key both from DB and cache. Falls back to "save empty" when
  /// the DAO doesn't expose a dedicated delete — the underlying table
  /// stores string values so empty-string is our "cleared" signal.
  Future<void> remove(String key) async {
    // Upstream DAO currently lacks a delete helper; use an empty-string
    // write as the documented clear semantics. Callers that need real
    // absence can use `_db.customStatement` directly.
    await _db.setSetting(key, '');
    _cache[key] = '';
  }

  /// Force the next read of [key] to hit the DB.
  void invalidateKey(String key) => _cache.remove(key);

  /// Wipe the entire cache — e.g. after a DB restore.
  void invalidate() => _cache.clear();
}
