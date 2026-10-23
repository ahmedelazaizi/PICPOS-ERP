// E-01 المرحلة ب: إثباتُ ترحيل المفتاح على محرّك SQLCipher الحقيقيّ.
//
// ⚠️ يتخطّى نفسَه بوضوح حيث `PRAGMA cipher_version` فارغ (flutter test العاديّ
// يحمّل sqlite3 عاديّة فيُتجاهَل المفتاح بصمت). للتشغيل الحقيقيّ:
//   pwsh tool/run_sqlcipher_tests.ps1
// النتائجُ والأرقام وتعليماتُ إعادة التشغيل: docs/security/db-key-engine-validation.md
//
// كلُّ الملفات في مجلدٍ مؤقّت؛ لا يُلمس Documents ولا أيُّ *.db للمستخدم.
import 'dart:io';

import 'package:drift/drift.dart' show OpeningDetails, QueryExecutor, QueryExecutorUser;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/db_key_manager.dart';
import 'package:picpos_erp/services/db_key_migration_service.dart';
import 'package:picpos_erp/services/db_key_types.dart';
import 'package:picpos_erp/services/db_keyinfo_file.dart';
import 'package:picpos_erp/services/secret_store.dart';
import 'package:picpos_erp/services/sqlcipher_engine.dart';

import '../helpers/db_key_harness.dart' show SimulatedCrash;
import '../helpers/sqlcipher_real.dart';

const _engine = NativeSqlCipherEngine();
const _legacy = DbKey(DbKeyKind.legacyDerived,
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
final _newRaw = DbKey.raw(
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef');

DbKeyManager _manager(SecretStore store) => DbKeyManager(
      store: store,
      engine: _engine,
      legacyDerive: () async => _legacy.value,
      recoveryMemoryKb: 64,
      recoveryIterations: 1,
    );

DbKeyMigrationService _service(
  DbKeyManager m,
  Directory dir, {
  String id = 'A',
  Future<void> Function(String)? hook,
}) {
  final s = DbKeyMigrationService(
    manager: m,
    backupsDir: Directory(p.join(dir.path, 'backups')),
    processId: id,
    stepHook: hook,
  );
  m.beforeResolve = s.recoverInterrupted;
  return s;
}

Future<bool> _opensWithoutKey(File f) async {
  final e = NativeDatabase(f);
  try {
    await e.ensureOpen(_NoKeyUser());
    await e.runSelect('SELECT count(*) FROM sqlite_master;', const []);
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      await e.close();
    } catch (_) {}
  }
}

class _NoKeyUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 0;
  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails d) async {}
}

const _stdTables = {'settings': 2, 'users': 1};

void main() {
  late Directory dir;
  late File db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('picpos_real_engine_');
    db = File(p.join(dir.path, 'picpos_unified.db'));
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('(ب)(ج) صيغة المفتاح والتشفير الفعليّ', () {
    test('x\'<64hex> يفتح، وعبارة الأحرف نفسها لا تفتح، وبلا مفتاح لا يفتح',
        () async {
      if (!await requireSqlCipher()) return;
      final f = File(p.join(dir.path, 'raw.db'));
      await createDb(f, _newRaw, wal: false);
      expect(await _engine.canOpen(f, _newRaw), isTrue);
      expect(await _engine.canOpen(f, DbKey(DbKeyKind.legacyDerived, _newRaw.value)),
          isFalse,
          reason: 'x\'hex\' ≠ عبارة نصّية بالأحرف نفسها');
      expect(await _opensWithoutKey(f), isFalse);
      expect(looksPlain(f), isFalse);
    });

    test('ATTACH … KEY بالصيغة الخام: الناتج مشفّر ولا يفتحه القديم ولا الفارغ',
        () async {
      if (!await requireSqlCipher()) return;
      final src = File(p.join(dir.path, 'src.db'));
      final dst = File(p.join(dir.path, 'dst.db'));
      await createDb(src, _legacy, wal: false);
      await _engine.exportTo(src, _legacy, dst, _newRaw);
      expect(looksPlain(dst), isFalse);
      expect(await _engine.canOpen(dst, _newRaw), isTrue);
      expect(await _engine.canOpen(dst, _legacy), isFalse);
      expect(await _opensWithoutKey(dst), isFalse);
      // الأصل: ما زال مشفّرًا ويفتح بالقديم (لم يُلمس).
      expect(looksPlain(src), isFalse);
      expect(await _engine.canOpen(src, _legacy), isTrue);
    });
  });

  group('(أ) user_version', () {
    test('sqlcipher_export الخام لا ينسخ user_version (يوثّق السبب)', () async {
      if (!await requireSqlCipher()) return;
      final src = File(p.join(dir.path, 'src.db'));
      final dst = File(p.join(dir.path, 'dst.db'));
      await createDb(src, _legacy, userVersion: 195, wal: false);
      final e = await openRaw(src, _legacy);
      try {
        await e.runCustom(
            "ATTACH DATABASE '${dst.path}' AS v2 KEY ${_newRaw.pragmaLiteral};",
            const []);
        await e.runSelect("SELECT sqlcipher_export('v2');", const []);
        await e.runCustom('DETACH DATABASE v2;', const []);
      } finally {
        await e.close();
      }
      final d = await openRaw(dst, _newRaw);
      try {
        expect(await scalarInt(d, 'PRAGMA user_version;'), 0,
            reason: 'التصدير الخام يترك user_version = 0');
        expect(await scalarInt(d, 'SELECT count(*) FROM settings;'), 2);
      } finally {
        await d.close();
      }
    });

    test('exportTo ينسخ user_version صراحةً (195)', () async {
      if (!await requireSqlCipher()) return;
      final src = File(p.join(dir.path, 'src.db'));
      final dst = File(p.join(dir.path, 'dst.db'));
      await createDb(src, _legacy, userVersion: 195);
      await _engine.exportTo(src, _legacy, dst, _newRaw);
      final insp = await _engine.inspect(dst, _newRaw);
      expect(insp.userVersion, 195);
      expect(insp.tableRowCounts, _stdTables);
      expect(insp.quickCheckOk, isTrue);
    });

    test('انحدار: canOpen/inspect/checkpoint/exportTo لا تكتب user_version '
        'فوق المخزَّن (كان drift يكتب 1)', () async {
      if (!await requireSqlCipher()) return;
      final f = File(p.join(dir.path, 'uv.db'));
      await createDb(f, _legacy, userVersion: 195);
      await _engine.canOpen(f, _legacy);
      await _engine.inspect(f, _legacy);
      await _engine.checkpointTruncate(f, _legacy);
      await _engine.exportTo(f, _legacy, File(p.join(dir.path, 'o.db')), _newRaw);
      final e = await openRaw(f, _legacy);
      try {
        expect(await scalarInt(e, 'PRAGMA user_version;'), 195);
      } finally {
        await e.close();
      }
    });

    test('user_version = 0 يبقى 0', () async {
      if (!await requireSqlCipher()) return;
      final f = File(p.join(dir.path, 'uv0.db'));
      await createDb(f, _legacy, userVersion: 0);
      final insp = await _engine.inspect(f, _legacy);
      expect(insp.userVersion, 0);
    });
  });

  group('(د) WAL', () {
    test('ملفات -wal/-shm نشطة (انهيار): المعاملات في WAL تدخل التصدير، '
        'والنسخةُ الاحتياطيّة كاملة، ولا -wal/-shm قديمة بعد التبديل', () async {
      if (!await requireSqlCipher()) return;
      final live = File(p.join(dir.path, 'live', 'picpos_unified.db'));
      live.parent.createSync();
      await createDb(live, _legacy, userVersion: 9);
      // يُبقي WAL كبيرًا: لا تفريغ تلقائيّ، والمقبضُ مفتوح.
      final holder = await openRaw(live, _legacy, autoCheckpoint: 0);
      final crashDir = Directory(p.join(dir.path, 'crash'))..createSync();
      final crash = File(p.join(crashDir.path, 'picpos_unified.db'));
      try {
        for (var i = 0; i < 50; i++) {
          await holder.runCustom(
              "INSERT INTO settings VALUES('w$i','x');", const []);
        }
        final wal = File('${live.path}-wal');
        expect(wal.existsSync() && wal.lengthSync() > 0, isTrue,
            reason: 'يجب أن يوجد -wal نشط');
        // صورة «انهيار»: نسخ db+wal+shm والمقبض مفتوح.
        for (final s in ['', '-wal', '-shm']) {
          final x = File('${live.path}$s');
          if (x.existsSync()) x.copySync('${crash.path}$s');
        }
        // دليلٌ سلبيّ: نسخُ الملف الرئيس وحده يفقد صفوف WAL.
        final mainOnly = File(p.join(dir.path, 'mainOnly.db'));
        live.copySync(mainOnly.path);
        final lost = await _engine.inspect(mainOnly, _legacy);
        expect(lost.tableRowCounts['settings'], lessThan(52),
            reason: 'بلا checkpoint النسخةُ ناقصة');
      } finally {
        await holder.close();
      }
      expect(File('${crash.path}-wal').existsSync(), isTrue);

      final store = MemorySecretStore();
      final mgr = _manager(store);
      final svc = _service(mgr, crashDir);
      final res = await svc.migrate(crash);
      expect(res.status, DbKeyMigrationStatus.migrated, reason: '$res');

      final newKey = DbKey.raw((await mgr.readStored('picpos_unified.db')).primary!);
      final insp = await _engine.inspect(crash, newKey);
      expect(insp.tableRowCounts, {'settings': 52, 'users': 1});
      expect(insp.userVersion, 9);
      expect(File('${crash.path}-wal').existsSync(), isFalse,
          reason: '-wal قديم بعد التبديل');
      expect(File('${crash.path}-shm').existsSync(), isFalse,
          reason: '-shm قديم بعد التبديل');

      // النسخة الاحتياطية (db.copy بلا wal) كاملة لأن checkpoint(TRUNCATE) سبقها.
      final backups = Directory(p.join(crashDir.path, 'backups', 'key-migration'))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();
      expect(backups, hasLength(1));
      final b = await _engine.inspect(backups.single, _legacy);
      expect(b.tableRowCounts['settings'], 52);
      expect(b.userVersion, 9);
    });

    test('قاعدةٌ بعد ترحيلها تعمل بـWAL كالإنتاج (journal_mode=WAL ثم كتابة/قراءة)',
        () async {
      if (!await requireSqlCipher()) return;
      await createDb(db, _legacy);
      final store = MemorySecretStore();
      final mgr = _manager(store);
      expect((await _service(mgr, dir).migrate(db)).ok, isTrue);
      final key = DbKey.raw((await mgr.readStored('picpos_unified.db')).primary!);
      final e = await openRaw(db, key, wal: true);
      try {
        final mode = await e.runSelect('PRAGMA journal_mode;', const []);
        expect(mode.first.values.first.toString().toLowerCase(), 'wal');
        await e.runCustom("INSERT INTO settings VALUES('n','1');", const []);
        expect(await scalarInt(e, 'SELECT count(*) FROM settings;'), 3);
      } finally {
        await e.close();
      }
    });
  });

  group('(هـ) دورة migrate() كاملة', () {
    test('قاعدة بيانات بسيطة: المفتاح الجديد يفتح، القديم لا، الصفوف وuser_version',
        () async {
      if (!await requireSqlCipher()) return;
      await createDb(db, _legacy, userVersion: 195);
      final store = MemorySecretStore();
      final mgr = _manager(store);
      final svc = _service(mgr, dir);
      final res = await svc.migrate(db);
      expect(res.status, DbKeyMigrationStatus.migrated, reason: '$res');
      final ready = await _manager(store).resolveForOpen(db) as DbKeyReady;
      expect(ready.key.kind, DbKeyKind.rawV2);
      expect(looksPlain(db), isFalse);
      final insp = await _engine.inspect(db, ready.key);
      expect(insp.userVersion, 195);
      expect(insp.tableRowCounts, _stdTables);
      expect(await _engine.canOpen(db, _legacy), isFalse);
      final info = await KeyInfoFile.read(db);
      expect(info?.kind, DbKeyKind.rawV2);
      // استدعاءٌ ثانٍ: لا شيء يُفعل.
      expect((await svc.migrate(db)).status, DbKeyMigrationStatus.alreadyMigrated);
    });

    test('AppDatabase الحقيقيّ (schema الإنتاج) ثم ترحيل ثم فتحه بالمفتاح الجديد',
        () async {
      if (!await requireSqlCipher()) return;
      // إنشاءٌ حقيقيّ: onCreate + بذرة على قاعدةٍ في الذاكرة، ثم تصديرها بالمفتاح
      // القديم إلى الملف (AppDatabase يترك مقبضًا مفتوحًا على ملفّه بعد close()
      // بسبب مهامّ الإقلاع، فلا نفتحه على الملف قبل الترحيل).
      NativeDatabase exec(DbKey k) => NativeDatabase(db, setup: (raw) {
            raw.execute('PRAGMA key = ${k.pragmaLiteral};');
            raw.execute('PRAGMA journal_mode = WAL;');
            raw.execute('PRAGMA foreign_keys = ON;');
          });
      final app1 = AppDatabase.withExecutor(
          NativeDatabase.memory(setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;')));
      final schemaV = app1.schemaVersion;
      int usersBefore;
      try {
        usersBefore = (await app1.customSelect('SELECT count(*) AS c FROM users')
                .getSingle())
            .read<int>('c');
        await app1.customStatement(
            "ATTACH DATABASE '${db.path}' AS v1 KEY ${_legacy.pragmaLiteral};");
        await app1.customSelect("SELECT sqlcipher_export('v1') AS x").get();
        await app1.customStatement('PRAGMA v1.user_version = $schemaV;');
        await app1.customStatement('DETACH DATABASE v1;');
      } finally {
        await app1.close();
      }      final before = await _engine.inspect(db, _legacy);
      expect(before.userVersion, schemaV);
      expect(before.tableRowCounts.length, greaterThan(50));

      final store = MemorySecretStore();
      final mgr = _manager(store);
      final res = await _service(mgr, dir).migrate(db);
      expect(res.status, DbKeyMigrationStatus.migrated, reason: '$res');

      final key = DbKey.raw((await mgr.readStored('picpos_unified.db')).primary!);
      final after = await _engine.inspect(db, key);
      expect(after.userVersion, schemaV);
      expect(after.tableRowCounts, before.tableRowCounts);
      expect(after.quickCheckOk, isTrue);
      expect(looksPlain(db), isFalse);

      // drift يفتحها بلا ترحيل (user_version = schemaVersion) ويقرأ البيانات.
      final app2 = AppDatabase.withExecutor(exec(key));
      try {
        final c = (await app2.customSelect('SELECT count(*) AS c FROM users')
                .getSingle())
            .read<int>('c');
        expect(c, usersBefore);
        final uv = (await app2.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version');
        expect(uv, schemaV);
      } finally {
        await app2.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('(و) انقطاعٌ في منتصف الترحيل', () {
    const steps = [
      DbKeyMigrationService.stepKeyStored,
      DbKeyMigrationService.stepCheckpointed,
      DbKeyMigrationService.stepBackedUp,
      DbKeyMigrationService.stepExported,
      DbKeyMigrationService.stepVerified,
      DbKeyMigrationService.stepOldRenamed,
      DbKeyMigrationService.stepSwapped,
      DbKeyMigrationService.stepCommitted,
    ];
    for (final step in steps) {
      test('موت العمليّة بعد $step ⇒ recoverInterrupted ⇒ قاعدةٌ سليمة تفتح '
          'وإعادةُ migrate تكتمل', () async {
        if (!await requireSqlCipher()) return;
        await createDb(db, _legacy, userVersion: 33);
        final store = MemorySecretStore();
        final crashing = _service(_manager(store), dir, hook: (s) async {
          if (s == step) throw SimulatedCrash(s);
        });
        await expectLater(crashing.migrate(db), throwsA(isA<SimulatedCrash>()));

        // «إقلاعٌ جديد»: مديرٌ وخدمةٌ جديدان على نفس التخزين والملفات.
        final mgr = _manager(store);
        final svc = _service(mgr, dir, id: 'B');
        await svc.recoverInterrupted(db);

        final opening = await mgr.findOpening(db, dbName: 'picpos_unified.db');
        expect(opening, isNotNull, reason: 'لا مفتاحَ يفتح القاعدة بعد $step');
        final insp = await _engine.inspect(db, opening!.key);
        expect(insp.userVersion, 33);
        expect(insp.tableRowCounts, _stdTables);
        expect(insp.quickCheckOk, isTrue);
        expect(File('${db.path}.v2-new').existsSync(), isFalse);

        final again = await svc.migrate(db);
        expect(again.ok, isTrue, reason: '$step ⇒ $again');
        final key = (await _manager(store).resolveForOpen(db) as DbKeyReady).key;
        expect(key.kind, DbKeyKind.rawV2);
        final fin = await _engine.inspect(db, key);
        expect(fin.userVersion, 33);
        expect(fin.tableRowCounts, _stdTables);
        expect(await _engine.canOpen(db, _legacy), isFalse);
      });
    }
  });

  group('(ح) ويندوز: القفل والتنظيف والمقابض المفتوحة', () {
    test('القفل الحصريّ: مقبضٌ آخر يحمله ⇒ busy فورًا (لا تعليق)، وبعد تحريره ينجح',
        () async {
      if (!await requireSqlCipher()) return;
      await createDb(db, _legacy);
      final lockFile = File('${db.path}.key-migration.lock');
      final other = lockFile.openSync(mode: FileMode.write);
      other.lockSync(FileLock.exclusive);
      final store = MemorySecretStore();
      final svc = _service(_manager(store), dir);
      try {
        final r = await svc.migrate(db).timeout(const Duration(seconds: 20));
        expect(r.status, DbKeyMigrationStatus.busy, reason: '$r');
        // لا شيءَ من الترحيل بدأ.
        expect(await _engine.canOpen(db, _legacy), isTrue);
        expect(File('${db.path}.v2-new').existsSync(), isFalse);
      } finally {
        other.unlockSync();
        other.closeSync();
      }
      expect((await svc.migrate(db)).status, DbKeyMigrationStatus.migrated);
    });

    test('مقبضٌ مفتوح على القاعدة أثناء التبديل (ويندوز لا يسمح بإعادة التسمية) ⇒ '
        'failed، الأصلُ سليمٌ، والتعافي ينظّف .v2-new', () async {
      if (!await requireSqlCipher()) return;
      await createDb(db, _legacy, userVersion: 5);
      final holder = await openRaw(db, _legacy, wal: true);
      final store = MemorySecretStore();
      final svc = _service(_manager(store), dir);
      DbKeyMigrationResult res;
      try {
        res = await svc.migrate(db);
      } finally {
        await holder.close();
      }
      // على ويندوز: rename فوق ملفٍّ مفتوح يفشل. على غيره قد ينجح ⇒ نقبل الاثنين
      // لكن لا نقبل أبدًا فقدان البيانات.
      final mgr = _manager(store);
      await _service(mgr, dir, id: 'B').recoverInterrupted(db);
      final opening = await mgr.findOpening(db, dbName: 'picpos_unified.db');
      expect(opening, isNotNull, reason: '$res');
      final insp = await _engine.inspect(db, opening!.key);
      expect(insp.tableRowCounts, _stdTables);
      expect(insp.userVersion, 5);
      if (Platform.isWindows) {
        expect(res.status, DbKeyMigrationStatus.failed, reason: '$res');
        expect(opening.key.kind, isNot(DbKeyKind.rawV2));
        expect(File('${db.path}.v2-new').existsSync(), isFalse);
      }
    });

    test('M8 + تنظيف النسخ: عمليّةٌ جديدة تحذف .pre-v2، والنسخةُ المنتهية '
        '(>30 يومًا) تُحذف مع keyinfo الجانبيّ، والحديثةُ تبقى', () async {
      if (!await requireSqlCipher()) return;
      await createDb(db, _legacy);
      final store = MemorySecretStore();
      final svc = _service(_manager(store), dir);
      expect((await svc.migrate(db)).status, DbKeyMigrationStatus.migrated);
      expect(File('${db.path}.pre-v2').existsSync(), isTrue);

      final bdir = Directory(p.join(dir.path, 'backups', 'key-migration'));
      final backup = bdir.listSync().whereType<File>().singleWhere(
          (f) => f.path.endsWith('.db'));
      expect(KeyInfoFile.of(backup).existsSync(), isTrue);

      // إقلاعٌ جديد: resolveForOpen ⇒ recoverInterrupted ⇒ M8.
      final mgr = _manager(store);
      final svcB = _service(mgr, dir, id: 'B');
      final ready = await mgr.resolveForOpen(db);
      expect(ready, isA<DbKeyReady>());
      expect(File('${db.path}.pre-v2').existsSync(), isFalse,
          reason: 'M8 يحذف .pre-v2 على ويندوز');
      expect((await KeyInfoFile.read(db))?.migration?.state, 'done');

      // النسخةُ الحديثة تبقى.
      expect(await svcB.purgeExpiredPreMigrationBackups(db), 0);
      expect(backup.existsSync(), isTrue);
      // تعتيق النسخة 40 يومًا ⇒ تُحذف مع الجانبيّ.
      backup.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 40)));
      expect(await svcB.purgeExpiredPreMigrationBackups(db), 1);
      expect(backup.existsSync(), isFalse);
      expect(KeyInfoFile.of(backup).existsSync(), isFalse);
    });
  });

  group('(ز) الزمن على قاعدةٍ كبيرة', () {
    final mb = int.tryParse(Platform.environment['PICPOS_BIG_DB_MB'] ?? '');
    test('ترحيل ${mb ?? "(PICPOS_BIG_DB_MB غير مضبوط)"} MB',
        skip: mb == null ? 'اضبط PICPOS_BIG_DB_MB=200 لتشغيله' : false,
        timeout: const Timeout(Duration(minutes: 40)), () async {
      if (!await requireSqlCipher()) return;
      final sw = Stopwatch()..start();
      final rows = (mb! * 1024 * 1024) ~/ 1040;
      final e = await openRaw(db, _legacy, wal: true);
      try {
        await e.runCustom(
            'CREATE TABLE big(id INTEGER PRIMARY KEY, a BLOB, b TEXT);', const []);
        await e.runCustom('CREATE INDEX big_b ON big(b);', const []);
        await e.runCustom(
            'WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c '
            'WHERE x < $rows) INSERT INTO big SELECT x, randomblob(1000), '
            "hex(randomblob(8)) FROM c;",
            const []);
        await e.runCustom('PRAGMA user_version = 195;', const []);
      } finally {
        await e.close();
      }
      // ignore: avoid_print
      print('[BIG] created ${sizeMb(db.lengthSync())} MB, $rows rows in '
          '${sw.elapsed.inSeconds}s (not part of migration time)');

      final laps = <String, int>{};
      var last = 0;
      final run = Stopwatch();
      final store = MemorySecretStore();
      final svc = _service(_manager(store), dir, hook: (s) async {
        laps[s] = run.elapsedMilliseconds - last;
        last = run.elapsedMilliseconds;
      });
      run.start();
      final res = await svc.migrate(db);
      run.stop();
      expect(res.status, DbKeyMigrationStatus.migrated, reason: '$res');
      // ignore: avoid_print
      print('[BIG] migrate total ${run.elapsedMilliseconds} ms; steps(ms): $laps');
      // ignore: avoid_print
      print('[BIG] db now ${sizeMb(db.lengthSync())} MB; '
          'pre-v2 ${sizeMb(File("${db.path}.pre-v2").lengthSync())} MB');

      final key = DbKey.raw(
          (await _manager(store).readStored('picpos_unified.db')).primary!);
      final insp = await _engine.inspect(db, key);
      expect(insp.tableRowCounts['big'], rows);
      expect(insp.userVersion, 195);
      expect(insp.quickCheckOk, isTrue);
    });
  });
}
