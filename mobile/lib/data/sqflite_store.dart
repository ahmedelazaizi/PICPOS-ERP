import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'local_store.dart';

/// On-device SQLite store (app-private storage). SQLCipher encryption with a
/// Keystore-held key is an I-2 item (ARCHITECTURE-I §11).
class SqfliteLocalStore implements LocalStore {
  SqfliteLocalStore._(this._db);
  final Database _db;

  static Future<SqfliteLocalStore> open() async {
    final path = p.join(await getDatabasesPath(), 'picpos_van.db');
    final db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
      await db.execute('CREATE TABLE entities (kind TEXT NOT NULL, global_id TEXT NOT NULL, '
          'json TEXT NOT NULL, PRIMARY KEY (kind, global_id))');
      await db.execute('CREATE TABLE outbox (global_id TEXT PRIMARY KEY, kind TEXT NOT NULL, '
          'payload TEXT NOT NULL, created_at INTEGER NOT NULL, status TEXT NOT NULL, '
          'attempts INTEGER NOT NULL DEFAULT 0, error TEXT)');
    });
    return SqfliteLocalStore._(db);
  }

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
  Future<void> retainOnly(String kind, Set<String> ids) async {
    final rows = await _db.query('entities', columns: ['global_id'], where: 'kind = ?', whereArgs: [kind]);
    for (final r in rows) {
      final id = r['global_id'] as String;
      if (!ids.contains(id)) {
        await _db.delete('entities', where: 'kind = ? AND global_id = ?', whereArgs: [kind, id]);
      }
    }
  }

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
  Future<void> addOutbox(OutboxEntry e) => _db.insert('outbox', e.toRow());

  @override
  Future<void> updateOutbox(OutboxEntry e) =>
      _db.update('outbox', e.toRow(), where: 'global_id = ?', whereArgs: [e.globalId]);

  @override
  Future<List<OutboxEntry>> outbox() async =>
      [for (final r in await _db.query('outbox', orderBy: 'created_at')) OutboxEntry.fromRow(r)];

  @override
  Future<void> clear() async {
    await _db.delete('kv');
    await _db.delete('entities');
    await _db.delete('outbox');
  }
}
