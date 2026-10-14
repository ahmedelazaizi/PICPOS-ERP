// E-01 المرحلة ب (الجزء 2): ربط الإقلاع — الترحيلُ المؤجَّل، الحجبُ بلا إنشاء
// قاعدة، الاسترداد، فحصُ المساحة، keyinfo للنسخ. بمحاكي محرّكٍ + تخزينٍ
// وهميّ + مجلدٍ مؤقّت (لا SQLCipher ولا Documents ولا أيّ *.db للمستخدم).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ural_erp/data/database/db_key_startup.dart';
import 'package:ural_erp/services/db_backup_sidecars.dart';
import 'package:ural_erp/services/db_key_blocked_actions.dart';
import 'package:ural_erp/services/db_key_boot.dart';
import 'package:ural_erp/services/db_key_manager.dart';
import 'package:ural_erp/services/db_key_names.dart';
import 'package:ural_erp/services/db_key_types.dart';
import 'package:ural_erp/services/db_keyinfo_file.dart';

import '../helpers/db_key_harness.dart';

Future<int?> _plenty(Directory _) async => 1 << 40;
Future<int?> _scarce(Directory _) async => 10;
Future<int?> _unknown(Directory _) async => null;

void main() {
  late DbKeyHarness h;

  setUp(() {
    h = DbKeyHarness();
    DbKeyBoot.resetMemo();
    DbKeyBoot.lastOutcome = null;
    DbKeyBoot.factoryOverride = null;
  });
  tearDown(() {
    DbKeyBoot.factoryOverride = null;
    DbKeyBoot.resetMemo();
    h.dispose();
  });

  DbKeyBoot boot(String pid, {Future<int?> Function(Directory)? space}) {
    final s = h.service(processId: pid);
    return DbKeyBoot(
      manager: s.manager,
      service: s,
      freeSpace: space ?? _plenty,
      migrationDisabled: () => false,
    );
  }

  Future<void> request({bool confirmed = false}) => DbKeyMigrationRequest(
        requestedAt: DateTime(2026, 10, 1),
        spaceConfirmedByAdmin: confirmed,
      ).write(h.db);

  group('الترحيل المؤجَّل', () {
    test('بلا طلب لا يُرحَّل شيء (لا ترحيل تلقائيّ أبدًا)', () async {
      await h.createLegacyDb();
      final r = await boot('p1').prepare(h.db);
      expect(r, isA<DbKeyReady>());
      expect((r as DbKeyReady).needsMigration, isTrue);
      expect(h.engine.exportCalls, 0);
      expect(DbKeyBoot.lastOutcome, isNull);
    });

    test('الطلب يُنفَّذ عند الإقلاع التالي ويلتزم، ويُؤكَّد في الإقلاع الثاني',
        () async {
      await h.createLegacyDb();
      await request();

      // الإقلاع 1: ترحيل + التزام (pending confirm).
      final r1 = await boot('boot1').prepare(h.db);
      expect(r1, isA<DbKeyReady>());
      expect((r1 as DbKeyReady).key.kind, DbKeyKind.rawV2);
      expect(DbKeyBoot.lastOutcome!.kind, DbKeyBootOutcomeKind.migrated);
      expect(await DbKeyMigrationRequest.read(h.db), isNull,
          reason: 'الطلب لمرّة واحدة');
      var info = await KeyInfoFile.read(h.db);
      expect(info!.migration!.state, 'committedPendingConfirm');
      expect(await h.sibling('.pre-v2').exists(), isTrue);

      // الإقلاع 2 (عمليّة جديدة): تأكيد M8 وحذفُ .pre-v2.
      DbKeyBoot.resetMemo();
      final r2 = await boot('boot2').prepare(h.db);
      expect((r2 as DbKeyReady).key, r1.key);
      info = await KeyInfoFile.read(h.db);
      expect(info!.migration!.state, 'done');
      expect(await h.sibling('.pre-v2').exists(), isFalse);
      // نسخة ما قبل الترحيل المستقلة باقية (30 يومًا).
      final kept = Directory(p.join(h.backups.path, 'key-migration'));
      expect(kept.listSync().whereType<File>().any((f) => f.path.endsWith('.db')),
          isTrue);
    });

    test('مساحةٌ غير كافية ⇒ يُتخطّى والقاعدة كما هي', () async {
      await h.createLegacyDb();
      await request();
      final r = await boot('p', space: _scarce).prepare(h.db);
      expect((r as DbKeyReady).key.kind, DbKeyKind.legacyDerived);
      expect(DbKeyBoot.lastOutcome!.kind, DbKeyBootOutcomeKind.skipped);
      expect(h.engine.exportCalls, 0);
      expect(await DbKeyMigrationRequest.read(h.db), isNull);
    });

    test('مساحةٌ غير معروفة: بلا تأكيد المدير يُتخطّى، ومعه يُنفَّذ', () async {
      await h.createLegacyDb();
      await request(confirmed: false);
      var r = await boot('p1', space: _unknown).prepare(h.db);
      expect((r as DbKeyReady).key.kind, DbKeyKind.legacyDerived);
      expect(DbKeyBoot.lastOutcome!.kind, DbKeyBootOutcomeKind.skipped);

      DbKeyBoot.resetMemo();
      await request(confirmed: true);
      r = await boot('p2', space: _unknown).prepare(h.db);
      expect((r as DbKeyReady).key.kind, DbKeyKind.rawV2);
      expect(DbKeyBoot.lastOutcome!.kind, DbKeyBootOutcomeKind.migrated);
    });

    test('فشل التصدير ⇒ تُفتح القاعدة بالقديم ولا يُحجب الإقلاع', () async {
      await h.createLegacyDb();
      h.engine.throwOnExport = true;
      await request();
      final r = await boot('p').prepare(h.db);
      expect((r as DbKeyReady).key.kind, DbKeyKind.legacyDerived);
      expect(DbKeyBoot.lastOutcome!.kind, DbKeyBootOutcomeKind.failed);
      expect(await h.sibling('.v2-new').exists(), isFalse);
    });

    test('علمُ --no-db-key-migration يتخطّى الطلب', () async {
      await h.createLegacyDb();
      await request();
      final s = h.service(processId: 'p');
      final b = DbKeyBoot(
          manager: s.manager,
          service: s,
          freeSpace: _plenty,
          migrationDisabled: () => true);
      final r = await b.prepare(h.db);
      expect((r as DbKeyReady).key.kind, DbKeyKind.legacyDerived);
      expect(DbKeyBoot.lastOutcome!.kind, DbKeyBootOutcomeKind.skipped);
    });

    test('keyinfo يدّعي «مرحَّلة» وفتحها مفتاحٌ قديم ⇒ يُصحَّح السجلّ', () async {
      await h.createLegacyDb();
      await KeyInfoFile.write(
        h.db,
        const KeyInfo(
            kind: DbKeyKind.rawV2,
            fingerprint: 'deadbeefdeadbeef',
            createdAt: '2026-10-01'),
      );
      final r = await boot('p').prepare(h.db);
      expect((r as DbKeyReady).key.kind, DbKeyKind.legacyDerived);
      expect((await KeyInfoFile.read(h.db))!.kind, DbKeyKind.legacyDerived);
    });
  });

  group('الحجب: لا تُنشأ قاعدةٌ فارغة أبدًا', () {
    Future<String> migrateAndLoseKey() async {
      await h.createLegacyDb();
      await request();
      await boot('b1').prepare(h.db);
      DbKeyBoot.resetMemo();
      await boot('b2').prepare(h.db); // تأكيد M8
      final name = DbKeyManager.dbNameOf(h.db);
      final code = await h.manager().pendingRecoveryCode(name);
      expect(code, isNotNull);
      // حساب ويندوز آخر: التخزين الآمن لا يحوي المفتاح.
      h.memory.values.remove(DbKeyNames.primary(name));
      h.memory.values.remove(DbKeyNames.shadow(name));
      return code!;
    }

    List<String> listing() => h.dir
        .listSync(recursive: true)
        .map((e) => p.relative(e.path, from: h.dir.path))
        .toList()
      ..sort();

    test('مفتاحٌ مفقودٌ لقاعدةٍ مرحَّلة ⇒ DbKeyUnavailable بلا أيّ كتابة', () async {
      await migrateAndLoseKey();
      final before = listing();
      final bytes = await h.db.readAsBytes();
      final r = await boot('b3').prepare(h.db);
      expect(r, isA<DbKeyUnavailable>());
      expect((r as DbKeyUnavailable).reason, DbKeyUnavailableReason.keyMissing);
      expect(r.canRecoverWithCode, isTrue);
      expect(listing(), before, reason: 'لا ملفّ جديد ولا حذف');
      expect(await h.db.readAsBytes(), bytes);
      // ولم يُولَّد مفتاحٌ جديد.
      final name = DbKeyManager.dbNameOf(h.db);
      expect(h.memory.values.containsKey(DbKeyNames.primary(name)), isFalse);
    });

    test('بوّابة main: تُرجع استثناء الحجب ولا تنشئ قاعدة', () async {
      await migrateAndLoseKey();
      DbKeyBoot.resetMemo();
      DbKeyBoot.factoryOverride = (f) => boot('g1');
      final before = listing();
      final blocked = await checkDatabaseKeyGateImpl(h.db.path);
      expect(blocked, isA<DbKeyBlockedException>());
      expect((blocked as DbKeyBlockedException).dbPath, h.db.path);
      expect(listing(), before);
    });

    test('بوّابة main على تثبيتٍ جديد: لا حجب ويُنشأ المفتاح لا القاعدة',
        () async {
      DbKeyBoot.factoryOverride = (f) => boot('g1');
      expect(await checkDatabaseKeyGateImpl(h.db.path), isNull);
      expect(await h.db.exists(), isFalse,
          reason: 'القاعدة تُنشأ عند فتح drift لا عند البوّابة');
    });

    test('recoverWithCode يعيد الوصول ويكتب الفتحتين', () async {
      final code = await migrateAndLoseKey();
      final m = h.manager();
      final bad = await m.recoverWithCode(h.db, 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF');
      expect(bad, isA<DbKeyUnavailable>());
      final name = DbKeyManager.dbNameOf(h.db);
      expect(h.memory.values.containsKey(DbKeyNames.primary(name)), isFalse,
          reason: 'رمز خاطئ لا يكتب شيئًا');

      final ok = await m.recoverWithCode(h.db, code);
      expect(ok, isA<DbKeyReady>());
      DbKeyBoot.resetMemo();
      final again = await boot('b4').prepare(h.db);
      expect(again, isA<DbKeyReady>());
      expect((again as DbKeyReady).key.kind, DbKeyKind.rawV2);
    });

    test('تشخيصٌ نصّيّ بلا أيّ مفتاح أو رمز', () async {
      final code = await migrateAndLoseKey();
      final r = await boot('b5').prepare(h.db) as DbKeyUnavailable;
      final text = await DbKeyDiagnostics.build(h.db, r);
      expect(text, contains('keyMissing'));
      expect(text, contains('keyinfo.kind: rawV2'));
      expect(text, isNot(contains(code)));
      expect(text, isNot(contains(kLegacyHex)));
      final name = DbKeyManager.dbNameOf(h.db);
      expect(text.contains(name), isTrue);
    });
  });

  group('أدوات مساعدة', () {
    test('فحص المساحة 3× (قاعدة + WAL)', () async {
      await h.db.writeAsBytes(List.filled(1000, 1));
      await h.sibling('-wal').writeAsBytes(List.filled(500, 1));
      var c = await MigrationSpaceCheck.measure(h.db, freeBytes: (_) async => 4499);
      expect(c.requiredBytes, 4500);
      expect(c.ok, isFalse);
      c = await MigrationSpaceCheck.measure(h.db, freeBytes: (_) async => 4500);
      expect(c.ok, isTrue);
      c = await MigrationSpaceCheck.measure(h.db, freeBytes: _unknown);
      expect(c.known, isFalse);
      expect(c.ok, isFalse);
    });

    test('DiskSpace: ويندوز عبر PowerShell و df مع حقن المشغّل', () async {
      List<String>? seen;
      final w = await DiskSpace.freeBytes(
        Directory(r'D:\Data\x'),
        isWindows: true,
        runner: (e, a) async {
          seen = a;
          return ProcessResult(1, 0, '123456\r\n', '');
        },
      );
      expect(w, 123456);
      expect(seen!.last, contains("DriveInfo('D')"));
      final bad = await DiskSpace.freeBytes(Directory(r'\\srv\share'),
          isWindows: true, runner: (e, a) async => ProcessResult(1, 0, '1', ''));
      expect(bad, isNull, reason: 'UNC ⇒ غير معروف لا تخمين');
      final fail = await DiskSpace.freeBytes(Directory(r'C:\x'),
          isWindows: true, runner: (e, a) async => ProcessResult(1, 1, '', 'e'));
      expect(fail, isNull);
      final thrown = await DiskSpace.freeBytes(Directory(r'C:\x'),
          isWindows: true, runner: (e, a) async => throw Exception('no pwsh'));
      expect(thrown, isNull);
      final df = await DiskSpace.freeBytes(Directory('/data'),
          isWindows: false,
          runner: (e, a) async => ProcessResult(1, 0,
              'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/x 100 40 60 40% /\n',
              ''));
      expect(df, 60 * 1024);
    });

    test('طلب الترحيل: كتابة/قراءة/مسح، والتالفُ يُعامَل كغائب', () async {
      expect(await DbKeyMigrationRequest.read(h.db), isNull);
      await request(confirmed: true);
      final r = await DbKeyMigrationRequest.read(h.db);
      expect(r!.spaceConfirmedByAdmin, isTrue);
      await DbKeyMigrationRequest.fileOf(h.db).writeAsString('{not json');
      expect(await DbKeyMigrationRequest.read(h.db), isNull);
      await DbKeyMigrationRequest.clear(h.db);
      expect(await DbKeyMigrationRequest.fileOf(h.db).exists(), isFalse);
    });

    test('keyinfo مجاور للنسخة: كتابة ونسخ وحذف', () async {
      await h.createLegacyDb();
      await KeyInfoFile.write(
        h.db,
        const KeyInfo(
          kind: DbKeyKind.rawV2,
          fingerprint: 'aabbccddeeff0011',
          createdAt: '2026-10-01',
          recoveryEnvelope: {'ct': 'x'},
          migration: KeyMigrationProgress(
              state: 'done', newFingerprint: 'f', oldKind: 'legacyDerived', startedAt: 's'),
        ),
      );
      final backup = File(p.join(h.dir.path, 'b.db'))..writeAsStringSync('x');
      await BackupSidecars.writeFor(h.db, backup);
      final side = await KeyInfoFile.read(backup);
      expect(side!.fingerprint, 'aabbccddeeff0011');
      expect(side.recoveryEnvelope, isNotNull);
      expect(side.migration, isNull, reason: 'بلا علم تقدّم');

      final out = File(p.join(h.dir.path, 'out.db'))..writeAsStringSync('x');
      await BackupSidecars.copyFor(backup, out);
      expect(await KeyInfoFile.of(out).exists(), isTrue);
      await BackupSidecars.deleteFor(backup);
      expect(await KeyInfoFile.of(backup).exists(), isFalse);
    });

    test('أحدثُ نسخة ما قبل الترحيل ضمن 30 يومًا', () async {
      final dir = Directory(p.join(h.backups.path, 'key-migration'))
        ..createSync(recursive: true);
      final name = DbKeyManager.dbNameOf(h.db);
      final old = File(p.join(dir.path, '$name.pre-v2-a.db'))..writeAsStringSync('o');
      final fresh = File(p.join(dir.path, '$name.pre-v2-b.db'))..writeAsStringSync('n');
      final now = DateTime.now();
      old.setLastModifiedSync(now.subtract(const Duration(days: 40)));
      fresh.setLastModifiedSync(now.subtract(const Duration(days: 2)));
      final f = await PreMigrationBackups.latest(h.backups, name);
      expect(f!.path, fresh.path);
      final until = await PreMigrationBackups.availableUntil(h.backups, name);
      expect(until!.isAfter(now.add(const Duration(days: 27))), isTrue);
      fresh.setLastModifiedSync(now.subtract(const Duration(days: 31)));
      expect(await PreMigrationBackups.latest(h.backups, name), isNull);
    });
  });
}
