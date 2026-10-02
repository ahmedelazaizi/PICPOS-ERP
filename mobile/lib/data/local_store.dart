import 'dart:convert';

/// Entity kinds kept on the device (mirrors the cloud bootstrap/pull payload).
abstract class Kinds {
  static const customers = 'customers';
  static const products = 'products';
  static const vanStock = 'van_stock';
  static const voucherBooks = 'voucher_books';
  static const leases = 'leases';
}

enum OutboxStatus { pending, accepted, rejected }

/// A document waiting for (or done with) `POST /mobile/sync/push`.
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
}

/// Offline store contract. `SqfliteLocalStore` on device, `MemoryLocalStore`
/// in tests. Entities are stored as JSON keyed by (kind, globalId).
abstract class LocalStore {
  Future<String?> getKv(String key);
  Future<void> setKv(String key, String? value);

  Future<void> upsert(String kind, List<Map<String, Object?>> rows, {String idField = 'globalId'});
  Future<void> retainOnly(String kind, Set<String> ids);
  Future<List<Map<String, Object?>>> all(String kind);
  Future<Map<String, Object?>?> get(String kind, String id);

  Future<void> addOutbox(OutboxEntry e);
  Future<void> updateOutbox(OutboxEntry e);
  Future<List<OutboxEntry>> outbox();

  /// Wipes everything (device revoked / unpaired).
  Future<void> clear();
}

class MemoryLocalStore implements LocalStore {
  final Map<String, String?> _kv = {};
  final Map<String, Map<String, Map<String, Object?>>> _e = {};
  final List<OutboxEntry> _outbox = [];

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
  Future<void> retainOnly(String kind, Set<String> ids) async =>
      _e[kind]?.removeWhere((k, _) => !ids.contains(k));

  @override
  Future<List<Map<String, Object?>>> all(String kind) async =>
      [for (final v in (_e[kind] ?? const {}).values) Map.of(v)];

  @override
  Future<Map<String, Object?>?> get(String kind, String id) async {
    final v = _e[kind]?[id];
    return v == null ? null : Map.of(v);
  }

  @override
  Future<void> addOutbox(OutboxEntry e) async => _outbox.add(e);
  @override
  Future<void> updateOutbox(OutboxEntry e) async {}
  @override
  Future<List<OutboxEntry>> outbox() async => List.of(_outbox);

  @override
  Future<void> clear() async {
    _kv.clear();
    _e.clear();
    _outbox.clear();
  }
}
