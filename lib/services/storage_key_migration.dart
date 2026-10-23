import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secret_store.dart';

/// Adapts a [FlutterSecureStorage] instance to [SecretStore] without changing
/// the options of that instance (callers keep their own platform options).
class FlutterSecureSecretStore implements SecretStore {
  const FlutterSecureSecretStore(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Renames a secure-storage key without ever losing the value
/// (`docs/security/internal-identifier-migration.md`, rule (a)).
///
///  * the NEW key is the primary: reads look at it first, writes go to it;
///  * if the new key is absent, the OLD key is read; a valid value is copied to
///    the new key, read back and compared, and only then is the old key deleted
///    (copy → verify → delete), so an interruption at any point leaves the value
///    readable under at least one name;
///  * if both exist with the SAME value (an earlier run died between copy and
///    delete) the old one is removed; if they differ the new one wins and the
///    old one is left untouched (never destroy a value we did not copy).
///
/// Idempotent. Read failures of the new key propagate to the caller (the caller
/// already decides what a failing store means); a failing copy/delete never
/// loses data and never throws — the old value is returned.
class StorageKeyMigration {
  StorageKeyMigration._();

  /// Value of [newKey], else of [oldKey] (migrated), else `null`.
  /// [isValid] decides whether an OLD value is worth migrating; an invalid old
  /// value is returned as is and left where it is.
  static Future<String?> read(
    SecretStore store, {
    required String newKey,
    required String oldKey,
    bool Function(String value)? isValid,
  }) async {
    final current = await store.read(newKey);
    if (oldKey == newKey) return current; // nothing was renamed
    if (current != null && current.isNotEmpty) {
      await _cleanupIfCopied(store, oldKey, current);
      return current;
    }
    final old = await store.read(oldKey);
    if (old == null || old.isEmpty) return current;
    if (isValid != null && !isValid(old)) return old;
    try {
      await store.write(newKey, old);
      final back = await store.read(newKey);
      if (back == old) {
        await store.delete(oldKey);
      }
    } catch (_) {
      // Copy or delete failed: the value is still readable (old key and/or
      // new key); the next read retries.
    }
    return old;
  }

  /// Writes [value] to [newKey] and drops the superseded [oldKey] (only after
  /// the new value reads back identically). Write failures propagate.
  static Future<void> write(
    SecretStore store, {
    required String newKey,
    required String oldKey,
    required String value,
  }) async {
    await store.write(newKey, value);
    if (oldKey == newKey) return;
    await _cleanupIfCopied(store, oldKey, value, expectNew: newKey);
  }

  /// Deletes both names (old first, so a failure of the second delete cannot
  /// resurrect a stale old value through the read fallback).
  static Future<void> delete(
    SecretStore store, {
    required String newKey,
    required String oldKey,
  }) async {
    if (oldKey != newKey) await store.delete(oldKey);
    await store.delete(newKey);
  }

  static Future<void> _cleanupIfCopied(
    SecretStore store,
    String oldKey,
    String expected, {
    String? expectNew,
  }) async {
    try {
      if (expectNew != null && await store.read(expectNew) != expected) return;
      final old = await store.read(oldKey);
      if (old == null) return;
      // On a write the old value is superseded by definition; on a read it is
      // only removed when it equals the primary (finishing an interrupted run).
      if (expectNew != null || old == expected) await store.delete(oldKey);
    } catch (_) {
      // best effort; retried on the next call
    }
  }
}
