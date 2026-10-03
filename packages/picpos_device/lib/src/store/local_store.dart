/// Offline store contract (adapted from mobile/lib/data/local_store.dart):
/// a key/value table, JSON entities keyed by `(kind, globalId)`, and the
/// outbox of documents waiting for the server.
library;

import 'dart:convert';

enum OutboxStatus {
  pending,

  /// Accepted (or reported `duplicate`: the server already had it).
  accepted,

  /// Rejected by the server: «تحتاج مراجعة» (needs attention); never dropped.
  rejected,
}

/// A document waiting for (or done with) its push. [globalId] is the
/// client UUID and the `X-Idempotency-Key` of every attempt.
class OutboxEntry {
  OutboxEntry({
    required this.globalId,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.error,
  });

  final String globalId;
  final String kind;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  OutboxStatus status;
  int attempts;
  String? error;

  Map<String, Object?> toRow() => {
        'global_id': globalId,
        'kind': kind,
        'payload': jsonEncode(payload),
        'created_at': createdAt.millisecondsSinceEpoch,
        'status': status.name,
        'attempts': attempts,
        'error': error,
      };

  static OutboxEntry fromRow(Map<String, Object?> r) => OutboxEntry(
        globalId: r['global_id'] as String,
        kind: r['kind'] as String,
        payload: (jsonDecode(r['payload'] as String) as Map).cast<String, Object?>(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        status: OutboxStatus.values.byName(r['status'] as String),
        attempts: r['attempts'] as int,
        error: r['error'] as String?,
      );

  OutboxEntry copy() => fromRow(toRow());
}

abstract class LocalStore {
  Future<String?> getKv(String key);
  Future<void> setKv(String key, String? value);

  Future<void> upsert(String kind, List<Map<String, Object?>> rows, {String idField = 'globalId'});
  Future<void> retainOnly(String kind, Set<String> ids);
  Future<List<Map<String, Object?>>> all(String kind);
  Future<Map<String, Object?>?> get(String kind, String id);

  /// Inserts [e] unless an entry with the same `globalId` exists. Returns
  /// `false` for such a duplicate (idempotent enqueue).
  Future<bool> addOutbox(OutboxEntry e);
  Future<void> updateOutbox(OutboxEntry e);
  Future<OutboxEntry?> outboxEntry(String globalId);

  /// All entries in creation order.
  Future<List<OutboxEntry>> outbox();

  /// Wipes everything (device revoked / unpaired).
  Future<void> clear();
}

/// In-memory store for tests and previews. Entries are copied in and out, so
/// a caller only changes the store through [updateOutbox] (as on SQLite).
class MemoryLocalStore implements LocalStore {
  final Map<String, String?> _kv = {};
  final Map<String, Map<String, Map<String, Object?>>> _e = {};
  final Map<String, OutboxEntry> _outbox = {};

  @override
  Future<String?> getKv(String key) async => _kv[key];
  @override
  Future<void> setKv(String key, String? value) async => _kv[key] = value;

  @override
  Future<void> upsert(String kind, List<Map<String, Object?>> rows, {String idField = 'globalId'}) async {
    final m = _e.putIfAbsent(kind, () => {});
    for (final r in rows) {
      m[r[idField] as String] = Map.of(r);
    }
  }

  @override
  Future<void> retainOnly(String kind, Set<String> ids) async => _e[kind]?.removeWhere((k, _) => !ids.contains(k));

  @override
  Future<List<Map<String, Object?>>> all(String kind) async => [for (final v in (_e[kind] ?? const {}).values) Map.of(v)];

  @override
  Future<Map<String, Object?>?> get(String kind, String id) async {
    final v = _e[kind]?[id];
    return v == null ? null : Map.of(v);
  }

  @override
  Future<bool> addOutbox(OutboxEntry e) async {
    if (_outbox.containsKey(e.globalId)) return false;
    _outbox[e.globalId] = e.copy();
    return true;
  }

  @override
  Future<void> updateOutbox(OutboxEntry e) async {
    if (_outbox.containsKey(e.globalId)) _outbox[e.globalId] = e.copy();
  }

  @override
  Future<OutboxEntry?> outboxEntry(String globalId) async => _outbox[globalId]?.copy();

  /// Insertion order (= creation order: entries are enqueued as they are made).
  @override
  Future<List<OutboxEntry>> outbox() async => [for (final e in _outbox.values) e.copy()];

  @override
  Future<void> clear() async {
    _kv.clear();
    _e.clear();
    _outbox.clear();
  }
}
