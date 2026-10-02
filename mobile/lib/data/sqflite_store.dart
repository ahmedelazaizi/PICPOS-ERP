import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as plain;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'local_store.dart';

/// On-device store: SQLCipher-encrypted SQLite in app-private storage. The
/// passphrase comes from `DatabaseKey` (Android Keystore via
/// flutter_secure_storage), ARCHITECTURE-I §11.
class SqfliteLocalStore implements LocalStore {
  SqfliteLocalStore._(this._db);
  final Database _db;

  static const _file = 'picpos_van_enc.db';

  /// I-1 plaintext database, migrated once then deleted.
  static const _legacyFile = 'picpos_van.db';

  static Future<void> _create(Database db, int _) async {
    await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE TABLE entities (kind TEXT NOT NULL, global_id TEXT NOT NULL, '
        'json TEXT NOT NULL, PRIMARY KEY (kind, global_id))');
    await db.execute('CREATE TABLE outbox (global_id TEXT PRIMARY KEY, kind TEXT NOT NULL, '
        'payload TEXT NOT NULL, created_at INTEGER NOT NULL, status TEXT NOT NULL, '
        'attempts INTEGER NOT NULL DEFAULT 0, error TEXT)');
  }

  static Future<SqfliteLocalStore> open({required String password}) async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(p.join(dir, _file), version: 1, password: password, onCreate: _create);
    await _migrateLegacy(db, p.join(dir, _legacyFile));
    return SqfliteLocalStore._(db);
  }

  /// Copies the unencrypted I-1 database (pending outbox included) into the
  /// encrypted one, then deletes it.
  static Future<void> _migrateLegacy(Database db, String legacyPath) async {
    if (!File(legacyPath).existsSync()) return;
    final old = await plain.openDatabase(legacyPath, readOnly: true);
    try {
      await db.transaction((tx) async {
        for (final table in const ['kv', 'entities', 'outbox']) {
          for (final row in await old.query(table)) {
            await tx.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      });
    } finally {
      await old.close();
    }
    await plain.deleteDatabase(legacyPath);
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
