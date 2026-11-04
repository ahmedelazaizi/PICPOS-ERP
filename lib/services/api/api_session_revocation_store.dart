import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/database/database.dart';
import 'api_session_token.dart';

/// INT-13 — session revocations survive a host restart.
///
/// [ApiSessionToken] keeps its revocation lists in process memory (reads stay
/// synchronous on every request). Before this store, restarting the main
/// emptied them, so a web session logged out — or every session of a user
/// whose password changed / who was disabled (`revokeUser`) — verified again
/// until its `exp` (up to 12 h; 30 days for pre-`iat` device tokens).
///
/// Same pattern as `ServerLoginThrottle` (FLEET-6): written behind to the
/// host's `settings` table under [settingKey] — a host-local key listed in
/// `kDeviceLocalSettingKeys`, so it never syncs and is never served by
/// `GET /api/settings` — and merged back in by [configure] at server start.
/// No schema change, no new table. Entries are pruned to what can still
/// match a valid token ([ApiSessionToken.revocationSnapshot]).
class ApiSessionRevocationStore {
  ApiSessionRevocationStore._();

  /// Host-local settings key: `{"sids": {sid: expMs}, "users": {uid: atMs}}`.
  static const String settingKey = 'api_session_revocations_v1';

  static AppDatabase? _db;
  static Future<void> _chain = Future<void>.value();

  /// Binds the durable store and merges what a previous run persisted.
  /// Called by `ApiHandler` (server start). Every call re-merges — the merge
  /// is idempotent (later instant wins) — so a re-created handler on the same
  /// database also picks the stored lists up.
  static void configure(AppDatabase db) {
    _db = db;
    ApiSessionToken.onRevocationsChanged = _schedulePersist;
    _chain = _chain.then((_) => _load(db)).catchError(_swallow);
  }

  /// Completes when every pending load/write has finished (tests, shutdown).
  static Future<void> flush() => _chain;

  /// The snapshot is taken when the queued write RUNS, i.e. after the
  /// start-up load ahead of it in [_chain] has merged the stored lists — so a
  /// revocation made while the load is still pending never overwrites the
  /// stored entries with a partial state.
  static void _schedulePersist() {
    final db = _db;
    if (db == null) return;
    _chain = _chain.then((_) => _write(db)).catchError(_swallow);
  }

  static Future<void> _write(AppDatabase db) async {
    if (!identical(_db, db)) return;
    await db.setSetting(
      settingKey,
      jsonEncode(ApiSessionToken.revocationSnapshot()),
    );
  }

  static Future<void> _load(AppDatabase db) async {
    final raw = await db.getSettingValue(settingKey);
    if (raw == null || raw.isEmpty || !identical(_db, db)) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final sids = <String, int>{
        for (final e in ((map['sids'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toInt(),
      };
      final users = <int, int>{};
      for (final e in ((map['users'] as Map?) ?? const {}).entries) {
        final uid = int.tryParse(e.key as String);
        if (uid != null) users[uid] = (e.value as num).toInt();
      }
      ApiSessionToken.restoreRevocations(sids, users);
    } catch (e) {
      debugPrint('[ApiSessionRevocationStore] ignoring unreadable state: $e');
    }
  }

  static void _swallow(Object e, StackTrace st) =>
      debugPrint('[ApiSessionRevocationStore] persistence skipped: $e');
}
