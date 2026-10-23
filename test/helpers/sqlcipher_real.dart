// عُدّة اختبارات المحرّك الحقيقيّ (E-01): تعمل فقط حين يكون المحرّكُ المحمَّل
// SQLCipher فعلًا. `flutter test` العاديّ يحمّل sqlite3 عاديّة فتتخطّى كلُّ
// الاختبارات بوضوح (لا فشل). لتشغيلها على SQLCipher الحقيقيّ:
//   tool/run_sqlcipher_tests.ps1   (انظر docs/security/db-key-engine-validation.md)
// و`PICPOS_REQUIRE_SQLCIPHER=1` يحوّل التخطّي إلى فشل كي لا ينجح التشغيلُ
// «الحقيقيّ» وهو في الواقع متخطٍّ.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/db_key_types.dart';

class _User extends QueryExecutorUser {
  _User([this.version = 0]);
  int version;
  @override
  int get schemaVersion => version;
  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails d) async {}
}

bool? _available;

/// هل المحرّك المحمَّل SQLCipher (`PRAGMA cipher_version` غير فارغ)؟
Future<bool> sqlCipherAvailable() async {
  if (_available != null) return _available!;
  var version = '';
  final e = NativeDatabase.memory(setup: (raw) {
    final r = raw.select('PRAGMA cipher_version;');
    version = r.isEmpty ? '' : (r.first.values.first?.toString() ?? '');
  });
  try {
    await e.ensureOpen(_User(0));
  } finally {
    await e.close();
  }
  return _available = version.trim().isNotEmpty;
}

/// يُستدعى أوّلَ كلّ اختبار؛ `false` ⇒ تخطَّ (أو فشل إن طُلب الإلزام).
Future<bool> requireSqlCipher() async {
  if (await sqlCipherAvailable()) return true;
  const msg = 'المحرّك المحمَّل ليس SQLCipher — شغّل tool/run_sqlcipher_tests.ps1';
  if (Platform.environment['PICPOS_REQUIRE_SQLCIPHER'] == '1') {
    fail('PICPOS_REQUIRE_SQLCIPHER=1 لكن $msg');
  }
  markTestSkipped(msg);
  return false;
}

/// يفتح [f] بالمفتاح مباشرةً (بدون أيّ منطق المشروع) ويُبقي المقبضَ مفتوحًا.
/// schemaVersion الذي يرجعه المستخدمُ = user_version المخزَّن (وإلا كتب drift
/// فوقه — انظر _NoopUser في sqlcipher_engine.dart).
Future<NativeDatabase> openRaw(
  File f,
  DbKey key, {
  bool wal = false,
  int autoCheckpoint = 1000,
}) async {
  final user = _User();
  final e = NativeDatabase(f, setup: (raw) {
    raw.execute('PRAGMA key = ${key.pragmaLiteral};');
    if (wal) raw.execute('PRAGMA journal_mode = WAL;');
    raw.execute('PRAGMA wal_autocheckpoint = $autoCheckpoint;');
    user.version =
        (raw.select('PRAGMA user_version;').first.values.first as num).toInt();
  });
  await e.ensureOpen(user);
  return e;
}

/// قاعدةٌ بجدولَين و[userVersion] (يُكتب بـPRAGMA صريح، كما يفعل drift).
Future<void> createDb(
  File f,
  DbKey key, {
  int userVersion = 7,
  bool wal = true,
  int settingsRows = 2,
}) async {
  final e = await openRaw(f, key, wal: wal);
  try {
    await e.runCustom('CREATE TABLE settings(k TEXT, v TEXT);', const []);
    await e.runCustom('CREATE TABLE users(id INTEGER, name TEXT);', const []);
    for (var i = 0; i < settingsRows; i++) {
      await e.runCustom("INSERT INTO settings VALUES('k$i','v$i');", const []);
    }
    await e.runCustom("INSERT INTO users VALUES(1,'مستخدم');", const []);
    await e.runCustom('PRAGMA user_version = $userVersion;', const []);
  } finally {
    await e.close();
  }
}

List<int> head16(File f) {
  final raf = f.openSync();
  try {
    return raf.readSync(16);
  } finally {
    raf.closeSync();
  }
}

bool looksPlain(File f) =>
    String.fromCharCodes(head16(f)).startsWith('SQLite format 3');

Future<int> scalarInt(QueryExecutor e, String sql) async =>
    ((await e.runSelect(sql, const [])).first.values.first as num).toInt();

String sizeMb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
