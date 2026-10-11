import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'db_key_types.dart';

/// لقطةٌ للمقارنة بين الأصل والمُصدَّر.
class DbInspection {
  const DbInspection({
    required this.quickCheckOk,
    required this.userVersion,
    required this.tableRowCounts,
  });

  final bool quickCheckOk;
  final int userVersion;
  final Map<String, int> tableRowCounts;

  bool matches(DbInspection other) {
    if (userVersion != other.userVersion) return false;
    if (tableRowCounts.length != other.tableRowCounts.length) return false;
    for (final e in tableRowCounts.entries) {
      if (other.tableRowCounts[e.key] != e.value) return false;
    }
    return true;
  }
}

/// المحرّكُ المحمَّلُ ليس SQLCipher (`PRAGMA cipher_version` فارغ) — كلُّ
/// فحصٍ/تصديرٍ عليه بلا معنى، فيُرفَض بدل أن يُعطي `true` لأيّ مفتاح.
class NotSqlCipherException implements Exception {
  const NotSqlCipherException();
  @override
  String toString() => 'NotSqlCipherException: the loaded SQLite engine is '
      'not SQLCipher (PRAGMA cipher_version is empty).';
}

/// واجهةٌ مجرّدةٌ لكلّ ما يلمس محرّكَ SQLCipher، كي يُختبَر المنطقُ بمحاكٍ
/// (`flutter test` يحمّل sqlite3 العاديّ لا SQLCipher).
abstract class SqlCipherEngine {
  /// هل يفتح [key] الملفَّ [db]؟ `false` للمفتاح الخطأ/الملف الفاسد.
  /// يرمي [NotSqlCipherException] إن لم يكن المحرّك SQLCipher.
  Future<bool> canOpen(File db, DbKey key);

  /// فتحٌ بالمفتاح + `quick_check` + `user_version` + عدّادات الجداول.
  /// يرمي إن تعذّر الفتح.
  Future<DbInspection> inspect(File db, DbKey key);

  /// `PRAGMA wal_checkpoint(TRUNCATE)`؛ `true` إن `busy = 0`.
  Future<bool> checkpointTruncate(File db, DbKey key);

  /// `ATTACH … KEY` ثم `sqlcipher_export` ثم نسخُ `user_version` صراحةً
  /// (التصديرُ لا ينسخه). الأصلُ للقراءة فقط عمليًّا ولا يُلمَس.
  Future<void> exportTo(File src, DbKey srcKey, File dst, DbKey dstKey);
}

class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  // لا ترحيلَ ولا كتابةَ لـ user_version: NativeDatabase يستعمل
  // OnOpenVersionDelegate فلا يُضبط الإصدارُ هنا أصلًا.
  @override
  Future<void> beforeOpen(
      QueryExecutor executor, OpeningDetails details) async {}
}

/// التنفيذُ الإنتاجيّ عبر `NativeDatabase(setup:)` من `drift/native.dart`
/// (بلا اعتمادٍ مباشرٍ على `sqlite3`، ممنوع بتعليق pubspec).
class NativeSqlCipherEngine implements SqlCipherEngine {
  const NativeSqlCipherEngine();

  Future<NativeDatabase> _open(File f, DbKey key) async {
    final exec = NativeDatabase(
      f,
      setup: (raw) {
        raw.execute('PRAGMA key = ${key.pragmaLiteral};');
        final cipher = raw.select('PRAGMA cipher_version;');
        final v = cipher.isEmpty
            ? ''
            : (cipher.first.values.first?.toString().trim() ?? '');
        if (v.isEmpty) throw const NotSqlCipherException();
      },
    );
    try {
      await exec.ensureOpen(_NoopUser());
      // يفشل هنا بـ«file is not a database» عند المفتاح الخطأ.
      await exec.runSelect('SELECT count(*) FROM sqlite_master;', const []);
      return exec;
    } catch (_) {
      await _closeQuietly(exec);
      rethrow;
    }
  }

  Future<void> _closeQuietly(QueryExecutor e) async {
    try {
      await e.close();
    } catch (_) {}
  }

  @override
  Future<bool> canOpen(File db, DbKey key) async {
    if (!await db.exists()) return false;
    try {
      final e = await _open(db, key);
      await _closeQuietly(e);
      return true;
    } on NotSqlCipherException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  static String _q(String ident) => '"${ident.replaceAll('"', '""')}"';

  @override
  Future<DbInspection> inspect(File db, DbKey key) async {
    final e = await _open(db, key);
    try {
      final qc = await e.runSelect('PRAGMA quick_check;', const []);
      final ok = qc.length == 1 &&
          qc.first.values.first.toString().toLowerCase() == 'ok';
      final uv = await e.runSelect('PRAGMA user_version;', const []);
      final version = (uv.first.values.first as num).toInt();
      final tables = await e.runSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' "
        "AND sql NOT LIKE 'CREATE VIRTUAL TABLE%' ORDER BY name;",
        const [],
      );
      final counts = <String, int>{};
      for (final t in tables) {
        final name = t['name'] as String;
        final r = await e.runSelect('SELECT count(*) AS c FROM ${_q(name)};',
            const []);
        counts[name] = (r.first['c'] as num).toInt();
      }
      return DbInspection(
        quickCheckOk: ok,
        userVersion: version,
        tableRowCounts: counts,
      );
    } finally {
      await _closeQuietly(e);
    }
  }

  @override
  Future<bool> checkpointTruncate(File db, DbKey key) async {
    final e = await _open(db, key);
    try {
      final r = await e.runSelect('PRAGMA wal_checkpoint(TRUNCATE);', const []);
      if (r.isEmpty) return false;
      return (r.first.values.first as num).toInt() == 0;
    } finally {
      await _closeQuietly(e);
    }
  }

  @override
  Future<void> exportTo(
      File src, DbKey srcKey, File dst, DbKey dstKey) async {
    if (await dst.exists()) await dst.delete();
    final e = await _open(src, srcKey);
    try {
      final uv = await e.runSelect('PRAGMA user_version;', const []);
      final version = (uv.first.values.first as num).toInt();
      final path = dst.path.replaceAll("'", "''");
      await e.runCustom(
          "ATTACH DATABASE '$path' AS v2 KEY ${dstKey.pragmaLiteral};",
          const []);
      await e.runSelect("SELECT sqlcipher_export('v2');", const []);
      // sqlcipher_export لا ينسخ user_version، وdrift يعتمد عليه للسكيما.
      await e.runCustom('PRAGMA v2.user_version = $version;', const []);
      await e.runCustom('DETACH DATABASE v2;', const []);
    } finally {
      await _closeQuietly(e);
    }
  }
}
