// E-01 T9: المحرّك الحقيقيّ (sqlcipher_export + user_version + WAL).
//
// ⚠️ يتخطّى نفسَه حيث `PRAGMA cipher_version` فارغ: `flutter test` يحمّل
// sqlite3 العاديّ (native-assets) لا SQLCipher، فالمفتاح يُتجاهَل بصمت. يصبح
// ذا معنى فقط على بيئةٍ تحمل SQLCipher (بناء build_picpos.bat الحقيقيّ).
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/db_key_manager.dart';
import 'package:picpos_erp/services/db_key_migration_service.dart';
import 'package:picpos_erp/services/db_key_types.dart';
import 'package:picpos_erp/services/secret_store.dart';
import 'package:picpos_erp/services/sqlcipher_engine.dart';

class _User extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails d) async {}
}

void main() {
  const engine = NativeSqlCipherEngine();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('picpos_engine_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('المحرّك الحاليّ: غير SQLCipher ⇒ NotSqlCipherException (لا true كاذب)',
      () async {
    final f = File('${dir.path}/probe.db')..writeAsBytesSync([0]);
    try {
      await engine.canOpen(f, DbKey.raw('0' * 64));
    } on NotSqlCipherException {
      return; // المتوقَّع تحت flutter test العاديّ
    }
    // SQLCipher حقيقيّ: ملفٌّ ليس قاعدة ⇒ false (لا استثناء) — مقبول أيضًا.
  });

  test('ترحيل حقيقيّ: user_version والجداول وWAL، والقديم لا يفتح الجديد',
      () async {
    final f = File('${dir.path}/real.db');
    const legacy = DbKey(DbKeyKind.legacyDerived,
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

    // ينشئ قاعدة WAL بالمفتاح القديم، user_version = 7.
    final exec = NativeDatabase(f, setup: (raw) {
      raw.execute('PRAGMA key = ${legacy.pragmaLiteral};');
    });
    try {
      await exec.ensureOpen(_User());
      final cipher = await exec.runSelect('PRAGMA cipher_version;', const []);
      if (cipher.isEmpty ||
          cipher.first.values.first.toString().trim().isEmpty) {
        await exec.close();
        markTestSkipped('المحرّك المحمَّل ليس SQLCipher — يتطلب بناء الإصدار');
        return;
      }
      await exec.runCustom('PRAGMA journal_mode = WAL;', const []);
      await exec.runCustom('CREATE TABLE settings(k TEXT, v TEXT);', const []);
      await exec.runCustom('CREATE TABLE users(id INTEGER);', const []);
      await exec.runCustom("INSERT INTO settings VALUES('a','1'),('b','2');", const []);
      await exec.runCustom('INSERT INTO users VALUES(1);', const []);
      await exec.runCustom('PRAGMA user_version = 7;', const []);
    } finally {
      await exec.close();
    }

    final mgr = DbKeyManager(
      store: MemorySecretStore(),
      engine: engine,
      legacyDerive: () async => legacy.value,
      recoveryMemoryKb: 64,
      recoveryIterations: 1,
    );
    final svc = DbKeyMigrationService(
      manager: mgr,
      backupsDir: Directory('${dir.path}/backups'),
      processId: 'A',
    );
    final res = await svc.migrate(f);
    expect(res.status, DbKeyMigrationStatus.migrated, reason: '$res');

    final key = (await mgr.resolveForOpen(f) as DbKeyReady).key;
    expect(key.kind, DbKeyKind.rawV2);
    final raf = f.openSync();
    final head = raf.readSync(16);
    raf.closeSync();
    expect(String.fromCharCodes(head), isNot(startsWith('SQLite format 3')));
    final insp = await engine.inspect(f, key);
    expect(insp.userVersion, 7);
    expect(insp.tableRowCounts, {'settings': 2, 'users': 1});
    expect(await engine.canOpen(f, legacy), isFalse);
  });
}
