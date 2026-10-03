import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'local_store.dart';

/// SQLCipher-encrypted SQLite in app-private storage (adapted from
/// mobile/lib/data/sqflite_store.dart, without the picpos_van legacy
/// migration). The passphrase comes from `DatabaseKey` (Android Keystore).
class SqlCipherLocalStore implements LocalStore {
  SqlCipherLocalStore._(this._db);
  final Database _db;

  static Future<void> _create(Database db, int _) async {
    await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE TABLE entities (kind TEXT NOT NULL, global_id TEXT NOT NULL, '
        'json TEXT NOT NULL, PRIMARY KEY (kind, global_id))');
    await db.execute('CREATE TABLE outbox (global_id TEXT PRIMARY KEY, kind TEXT NOT NULL, '
        'payload TEXT NOT NULL, created_at INTEGER NOT NULL, status TEXT NOT NULL, '
        'attempts INTEGER NOT NULL DEFAULT 0, error TEXT)');
  }

  /// Opens (or creates) `[fileName]` in the app's databases directory, e.g.
  /// `picpos_pos_enc.db` / `picpos_admin_enc.db`.
  static Future<SqlCipherLocalStore> open({required String fileName, required String password}) async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(p.join(dir, fileName), version: 1, password: password, onCreate: _create);
    return SqlCipherLocalStore._(db);
  }

  Future<void> close() => _db.close();

  @override
  Future<String?> getKv(String key) async {
    final r = await _db.query('kv', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  @override
  Future<void> setKv(String key, String? value) =>
      _db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> upsert(String kind, List<Map<String, Object?>> rows, {String idField = 'globalId'}) =>
      _db.transaction((tx) async {
        final b = tx.batch();
        for (final r in rows) {
          b.insert('entities', {'kind': kind, 'global_id': r[idField], 'json': jsonEncode(r)},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await b.commit(noResult: true);
      });

  @override
  Future<void> retainOnly(String kind, Set<String> ids) => _db.transaction((tx) async {
        final rows = await tx.query('entities', columns: ['global_id'], where: 'kind = ?', whereArgs: [kind]);
        for (final r in rows) {
          final id = r['global_id'] as String;
          if (!ids.contains(id)) {
            await tx.delete('entities', where: 'kind = ? AND global_id = ?', whereArgs: [kind, id]);
          }
        }
      });

  @override
  Future<List<Map<String, Object?>>> all(String kind) async => [
        for (final r in await _db.query('entities', where: 'kind = ?', whereArgs: [kind]))
          (jsonDecode(r['json'] as String) as Map).cast<String, Object?>(),
      ];

  @override
  Future<Map<String, Object?>?> get(String kind, String id) async {
    final r = await _db.query('entities', where: 'kind = ? AND global_id = ?', whereArgs: [kind, id]);
    return r.isEmpty ? null : (jsonDecode(r.first['json'] as String) as Map).cast<String, Object?>();
  }

  @override
  Future<bool> addOutbox(OutboxEntry e) => _db.transaction((tx) async {
        final exists = await tx.query('outbox', columns: ['global_id'], where: 'global_id = ?', whereArgs: [e.globalId]);
        if (exists.isNotEmpty) return false;
        await tx.insert('outbox', e.toRow());
        return true;
      });

  @override
  Future<void> updateOutbox(OutboxEntry e) =>
      _db.update('outbox', e.toRow(), where: 'global_id = ?', whereArgs: [e.globalId]);

  @override
  Future<OutboxEntry?> outboxEntry(String globalId) async {
    final r = await _db.query('outbox', where: 'global_id = ?', whereArgs: [globalId]);
    return r.isEmpty ? null : OutboxEntry.fromRow(r.first);
  }

  @override
  Future<List<OutboxEntry>> outbox() async =>
      [for (final r in await _db.query('outbox', orderBy: 'created_at, rowid')) OutboxEntry.fromRow(r)];

  @override
  Future<void> clear() => _db.transaction((tx) async {
        await tx.delete('kv');
        await tx.delete('entities');
        await tx.delete('outbox');
      });
}
