// E-01 المرحلة ب: DbKeyMigrationService — دورة الترحيل وكلّ سيناريو انقطاع (§2.4).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/db_key_migration_service.dart';
import 'package:picpos_erp/services/db_key_names.dart';
import 'package:picpos_erp/services/db_key_types.dart';
import 'package:picpos_erp/services/db_keyinfo_file.dart';

import '../helpers/db_key_harness.dart';

void main() {
  late DbKeyHarness h;
  const name = 'picpos_unified.db';

  setUp(() => h = DbKeyHarness());
  tearDown(() => h.dispose());

  Future<DbKey> storedKey() async =>
      DbKey.raw(h.memory.values[DbKeyNames.primary(name)]!);

  /// يشغّل ترحيلًا يموت عند [step] (يُبلَع الانقطاع المحاكى).
  Future<void> migrateAndCrashAt(String step) async {
    try {
      await h.service(
        processId: 'A',
        hook: (s) async {
          if (s == step) throw SimulatedCrash(s);
        },
      ).migrate(h.db);
      fail('expected crash at $step');
    } on SimulatedCrash {
      // المتوقَّع
    }
  }

  /// أيُّ مفتاحٍ يفتح [f] الآن: new / legacy / none.
  Future<String> whoOpens(File f) async {
    if (!f.existsSync()) return 'missing';
    final stored = h.memory.values[DbKeyNames.primary(name)];
    if (stored != null && await h.engine.canOpen(f, DbKey.raw(stored))) {
      return 'new';
    }
    if (await h.engine.canOpen(f, h.legacyKey)) return 'legacy';
    return 'none';
  }

  group('الدورة الناجحة', () {
    test('يرحّل ويحفظ user_version والجداول؛ الجديد يفتح والقديم لا', () async {
      await h.createLegacyDb(tables: {'settings': 5, 'users': 3}, userVersion: 77);

      final res = await h.service(processId: 'A').migrate(h.db);

      expect(res.status, DbKeyMigrationStatus.migrated, reason: '$res');
      final key = await storedKey();
      expect(await h.engine.canOpen(h.db, key), isTrue);
      expect(await h.engine.canOpen(h.db, h.legacyKey), isFalse);
      final insp = await h.engine.inspect(h.db, key);
      expect(insp.userVersion, 77);
      expect(insp.tableRowCounts, {'settings': 5, 'users': 3});

      // الفتحتان + إعادة القراءة + رمز الاسترداد المعلَّق.
      expect(h.memory.values[DbKeyNames.shadow(name)], key.value);
      expect(h.memory.values[DbKeyNames.recoveryPending(name)], isNotNull);

      final info = (await KeyInfoFile.read(h.db))!;
      expect(info.kind, DbKeyKind.rawV2);
      expect(info.fingerprint, key.fingerprint);
      expect(info.migratedFrom, 'legacyDerived');
      expect(info.migration!.state, 'committedPendingConfirm');
      expect(info.recoveryEnvelope, isNotNull);

      // ق-5: النسخة المسبقة في مجلد فرعيّ بمفتاحٍ قديم + أصل .pre-v2 بجانب القاعدة.
      final pre = h.backups.listSync(recursive: true).whereType<File>().where(
          (f) => f.path.contains('key-migration') && f.path.endsWith('.db'));
      expect(pre, hasLength(1));
      expect(await h.engine.canOpen(pre.single, h.legacyKey), isTrue);
      expect(h.sibling('.pre-v2').existsSync(), isTrue);
      expect(h.sibling('.v2-new').existsSync(), isFalse);
    });

    test('الالتزام في الإقلاع التالي (M8): العمليّة نفسها لا تحذف .pre-v2',
        () async {
      await h.createLegacyDb();
      await h.service(processId: 'A').migrate(h.db);

      // نفس العمليّة (نفس المعرّف): لا تأكيد.
      final same = h.service(processId: 'A');
      final r1 = await same.manager.resolveForOpen(h.db);
      expect(r1, isA<DbKeyReady>());
      expect(h.sibling('.pre-v2').existsSync(), isTrue);

      // «إقلاع جديد» بمعرّف مختلف: يقرأ المفتاح من التخزين ويفتح ⇒ يؤكّد.
      final next = h.service(processId: 'B');
      final r2 = await next.manager.resolveForOpen(h.db) as DbKeyReady;
      expect(r2.key.kind, DbKeyKind.rawV2);
      expect(h.sibling('.pre-v2').existsSync(), isFalse);
      final info = (await KeyInfoFile.read(h.db))!;
      expect(info.migration!.state, 'done');
      expect(info.migration!.confirmedAt, isNotNull);
      // النسخة المسبقة في المجلد الفرعيّ باقية (30 يومًا).
      expect(
          h.backups
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.db')),
          hasLength(1));
    });

    test('استدعاء ثانٍ على قاعدة مرحَّلة = alreadyMigrated', () async {
      await h.createLegacyDb();
      await h.service(processId: 'A').migrate(h.db);
      final again = await h.service(processId: 'B').migrate(h.db);
      expect(again.status, DbKeyMigrationStatus.alreadyMigrated);
    });

    test('ق-4: نسخة قديمة مستعادة (مفتاح مشتقّ) تُفتح ثم تُعاد تشفيرها بالجديد',
        () async {
      await h.createLegacyDb(tables: {'settings': 1, 'users': 1});
      await h.service(processId: 'A').migrate(h.db);
      await h.service(processId: 'B').manager.resolveForOpen(h.db); // M8
      final key = await storedKey();

      // «استعادة» نسخة قديمة مشفّرة بالمشتقّ فوق القاعدة.
      await FakeSqlCipherEngine.create(h.db, h.legacyKey,
          tables: {'settings': 9, 'users': 9}, userVersion: 40);
      final svc = h.service(processId: 'C');
      final r = await svc.manager.resolveForOpen(h.db) as DbKeyReady;
      expect(r.needsMigration, isTrue, reason: 'المشتقّ مرشّحُ فتحٍ فقط');

      final res = await svc.migrate(h.db);
      expect(res.status, DbKeyMigrationStatus.migrated, reason: '$res');
      expect(await h.engine.canOpen(h.db, key), isTrue,
          reason: 'نفس المفتاح الجديد المخزَّن أُعيد استعماله');
      expect((await h.engine.inspect(h.db, key)).userVersion, 40);
    });

    test('ق-5: تنظيف الـ30 يومًا يحذف القديم فقط ولا يلمس نسخ المجلد العلوي',
        () async {
      await h.createLegacyDb();
      await h.service(processId: 'A').migrate(h.db);
      final dir = Directory('${h.backups.path}${Platform.pathSeparator}key-migration');
      final f = dir.listSync().whereType<File>().firstWhere((x) => x.path.endsWith('.db'));
      // نسخة عاديّة بالمجلد العلوي لا يجوز أن تُمسّ.
      final regular = File('${h.backups.path}${Platform.pathSeparator}${name}_backup_x.db')
        ..writeAsStringSync('x');

      final svc = h.service(processId: 'B');
      expect(await svc.purgeExpiredPreMigrationBackups(h.db), 0);
      f.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 31)));
      expect(await svc.purgeExpiredPreMigrationBackups(h.db), 1);
      expect(f.existsSync(), isFalse);
      expect(regular.existsSync(), isTrue);
    });
  });

  group('فشل قبل التبديل ⇒ الأصل يبقى', () {
    Future<void> expectOriginalIntact() async {
      expect(await h.engine.canOpen(h.db, h.legacyKey), isTrue);
      expect(h.sibling('.v2-new').existsSync(), isFalse);
      expect(h.sibling('.pre-v2').existsSync(), isFalse);
      expect((await h.engine.inspect(h.db, h.legacyKey)).userVersion, 42);
    }

    for (final tamper in [
      'sameKeyAsSource',
      'dropRows',
      'wrongUserVersion',
      'corruptQuickCheck'
    ]) {
      test('فشل التحقق ($tamper) ⇒ failed والأصل سليم', () async {
        await h.createLegacyDb();
        h.engine.tamper = tamper;
        final res = await h.service(processId: 'A').migrate(h.db);
        expect(res.status, DbKeyMigrationStatus.failed, reason: '$res');
        await expectOriginalIntact();
        // ولا التزام: keyinfo لا يدّعي الترحيل.
        expect((await KeyInfoFile.read(h.db))!.kind.isLegacy, isTrue);
      });
    }

    test('فشل التصدير ⇒ failed والأصل سليم', () async {
      await h.createLegacyDb();
      h.engine.throwOnExport = true;
      final res = await h.service(processId: 'A').migrate(h.db);
      expect(res.status, DbKeyMigrationStatus.failed);
      await expectOriginalIntact();
    });

    test('ثم إعادة المحاولة بعد زوال العطل تنجح وتعيد استعمال المفتاح', () async {
      await h.createLegacyDb();
      h.engine.tamper = 'dropRows';
      await h.service(processId: 'A').migrate(h.db);
      final k1 = h.memory.values[DbKeyNames.primary(name)];
      h.engine.tamper = 'none';
      final res = await h.service(processId: 'B').migrate(h.db);
      expect(res.status, DbKeyMigrationStatus.migrated);
      expect(h.memory.values[DbKeyNames.primary(name)], k1);
    });

    test('WAL لم يُفرَّغ ⇒ skipped ولا تصدير', () async {
      await h.createLegacyDb();
      h.engine.checkpointOk = false;
      final res = await h.service(processId: 'A').migrate(h.db);
      expect(res.status, DbKeyMigrationStatus.skipped);
      expect(h.engine.exportCalls, 0);
      expect(await h.engine.canOpen(h.db, h.legacyKey), isTrue);
    });

    test('فشل مسبار التخزين الآمن ⇒ skipped ولا ملف جديد', () async {
      await h.createLegacyDb();
      h.flaky.writesThrow = true;
      final res = await h.service(processId: 'A').migrate(h.db);
      expect(res.status, DbKeyMigrationStatus.skipped);
      expect(h.engine.exportCalls, 0);
      expect(h.backups.existsSync(), isFalse);
      expect(await h.engine.canOpen(h.db, h.legacyKey), isTrue);
    });

    test('كتابة تُبلَع بصمت في التخزين ⇒ skipped (لا ترحيل بمفتاح غير محفوظ)',
        () async {
      await h.createLegacyDb();
      h.flaky.writesSilentlyDropped = true;
      final res = await h.service(processId: 'A').migrate(h.db);
      expect(res.status, DbKeyMigrationStatus.skipped);
      expect(h.engine.exportCalls, 0);
    });

    test('استعادة معلَّقة ⇒ skipped', () async {
      await h.createLegacyDb();
      h.sibling('.restore-pending').writeAsStringSync('x');
      final res = await h.service(processId: 'A').migrate(h.db);
      expect(res.status, DbKeyMigrationStatus.skipped);
    });

    test('لا مرشّح يفتح الملف ⇒ skipped', () async {
      await FakeSqlCipherEngine.create(h.db, DbKey.raw('9' * 64));
      final res = await h.service(processId: 'A').migrate(h.db);
      expect(res.status, DbKeyMigrationStatus.skipped);
    });

    test('مساحة غير كافية ⇒ skipped', () async {
      await h.createLegacyDb();
      final m = h.manager();
      final svc = DbKeyMigrationService(
        manager: m,
        backupsDir: h.backups,
        processId: 'A',
        freeSpaceBytes: (_) async => 1,
      );
      final res = await svc.migrate(h.db);
      expect(res.status, DbKeyMigrationStatus.skipped);
      expect(h.engine.exportCalls, 0);
    });

    test('قفل حصريّ: ترحيل ثانٍ متزامن ⇒ busy', () async {
      await h.createLegacyDb();
      // نمسك القفل كعمليّة أخرى.
      final raf = await File('${h.path}.key-migration.lock')
          .open(mode: FileMode.write);
      await raf.lock(FileLock.exclusive);
      try {
        final res = await h.service(processId: 'A').migrate(h.db);
        expect(res.status, DbKeyMigrationStatus.busy);
        expect(h.engine.exportCalls, 0);
      } finally {
        await raf.unlock();
        await raf.close();
      }
    });
  });

  group('جدول الانقطاع §2.4 — موت العمليّة بعد كلّ خطوة', () {
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

    for (final crashAt in steps) {
      test('انقطاع عند $crashAt: الإقلاع التالي يفتح ولا يضيع ملف، والإعادة تكتمل',
          () async {
        await h.createLegacyDb(tables: {'settings': 4, 'users': 2}, userVersion: 11);
        final crashing = h.service(
          processId: 'A',
          hook: (s) async {
            if (s == crashAt) throw SimulatedCrash(s);
          },
        );
        await expectLater(crashing.migrate(h.db), throwsA(isA<SimulatedCrash>()));

        // ── الإقلاع التالي (مدير+خدمة جديدان، معرّف عمليّة جديد) ──
        final boot = h.service(processId: 'B');
        final r = await boot.manager.resolveForOpen(h.db);

        expect(r, isA<DbKeyReady>(),
            reason: 'بعد $crashAt يجب أن تُفتح القاعدة، لا تضيع');
        final key = (r as DbKeyReady).key;
        final insp = await h.engine.inspect(h.db, key);
        expect(insp.userVersion, 11);
        expect(insp.tableRowCounts, {'settings': 4, 'users': 2});
        expect(h.sibling('.v2-new').existsSync(), isFalse,
            reason: 'لا ملف وسيط معلّق');

        // الحالات بعد التبديل تُكمل بالجديد؛ قبله تبقى بالقديم.
        final swapped = crashAt == DbKeyMigrationService.stepSwapped ||
            crashAt == DbKeyMigrationService.stepCommitted ||
            crashAt == DbKeyMigrationService.stepOldRenamed;
        expect(key.kind, swapped ? DbKeyKind.rawV2 : DbKeyKind.legacyDerived);

        // لا يوجد ملف قابل للفتح يُفقد: نسخة المجلد الفرعيّ أو pre-v2 أو db.
        // ثم إكمال الترحيل صراحةً ينتهي بقاعدة جديدة سليمة.
        final done = await boot.migrate(h.db);
        expect(done.ok, isTrue, reason: '$done');
        final k2 = await storedKey();
        expect(await h.engine.canOpen(h.db, k2), isTrue);
        expect((await h.engine.inspect(h.db, k2)).userVersion, 11);
        expect(await h.engine.canOpen(h.db, h.legacyKey), isFalse);
      });
    }

    test('صفّ «لا db، pre-v2 + v2-new»: الجديد صالح ⇒ يُكمَل التبديل', () async {
      await h.createLegacyDb();
      await migrateAndCrashAt(DbKeyMigrationService.stepOldRenamed);
      expect(h.db.existsSync(), isFalse);
      expect(h.sibling('.pre-v2').existsSync(), isTrue);
      expect(h.sibling('.v2-new').existsSync(), isTrue);

      final r = await h.service(processId: 'B').manager.resolveForOpen(h.db);
      expect((r as DbKeyReady).key.kind, DbKeyKind.rawV2);
      expect(h.sibling('.pre-v2').existsSync(), isTrue,
          reason: 'يؤكَّد في الإقلاع الذي يليه');
    });

    test('صفّ «لا db، pre-v2 + v2-new»: الجديد غير صالح ⇒ يرجع pre-v2', () async {
      await h.createLegacyDb();
      await migrateAndCrashAt(DbKeyMigrationService.stepOldRenamed);
      // تلف v2-new.
      h.sibling('.v2-new').writeAsStringSync('garbage');

      final r = await h.service(processId: 'B').manager.resolveForOpen(h.db);

      expect((r as DbKeyReady).key.kind, DbKeyKind.legacyDerived);
      expect(await whoOpens(h.db), 'legacy');
      expect(h.sibling('.v2-new').existsSync(), isFalse);
    });

    test('صفّ «لا db، pre-v2 فقط» ⇒ يرجع pre-v2', () async {
      await h.createLegacyDb();
      h.db.renameSync(h.sibling('.pre-v2').path);
      final r = await h.service(processId: 'B').manager.resolveForOpen(h.db);
      expect((r as DbKeyReady).key.kind, DbKeyKind.legacyDerived);
    });

    test('أسوأ حالة: المفتاح الجديد ضاع بعد التبديل قبل الالتزام ⇒ .v2-orphan + رجوع',
        () async {
      await h.createLegacyDb();
      await migrateAndCrashAt(DbKeyMigrationService.stepSwapped);
      expect(await whoOpens(h.db), 'new');
      final newBytes = await h.db.readAsBytes();
      h.memory.values.clear(); // التخزين الآمن لم يحفظ

      final r = await h.service(processId: 'B').manager.resolveForOpen(h.db);

      expect((r as DbKeyReady).key.kind, DbKeyKind.legacyDerived);
      expect(await whoOpens(h.db), 'legacy');
      final orphan = h.sibling('.v2-orphan');
      expect(orphan.existsSync(), isTrue, reason: 'لا يُحذف آليًّا');
      expect(await orphan.readAsBytes(), newBytes);
    });

    test('بعد الالتزام: المفتاح غاب ⇒ لا رجوع صامت؛ Unavailable مع pre-v2 سليم',
        () async {
      await h.createLegacyDb();
      await h.service(processId: 'A').migrate(h.db); // committedPendingConfirm
      final dbBytes = await h.db.readAsBytes();
      final preBytes = await h.sibling('.pre-v2').readAsBytes();
      h.memory.values.clear(); // حسابٌ آخر على نفس الجهاز: المشتقّ ما زال متاحًا

      final r = await h.service(processId: 'B').manager.resolveForOpen(h.db);

      expect(r, isA<DbKeyUnavailable>());
      final u = r as DbKeyUnavailable;
      expect(u.reason, DbKeyUnavailableReason.keyMissing);
      expect(u.preMigrationCopyAvailable, isTrue);
      expect(u.canRecoverWithCode, isTrue);
      expect(await h.db.readAsBytes(), dbBytes);
      expect(await h.sibling('.pre-v2').readAsBytes(), preBytes);
      expect(h.sibling('.v2-orphan').existsSync(), isFalse);
    });

    test('رجوع صريح rollbackToPreMigration يحفظ الجديد في .v2-orphan', () async {
      await h.createLegacyDb();
      await h.service(processId: 'A').migrate(h.db);
      h.memory.values.clear();
      final svc = h.service(processId: 'B');
      expect(await svc.rollbackToPreMigration(h.db), isTrue);
      expect(await whoOpens(h.db), 'legacy');
      expect(h.sibling('.v2-orphan').existsSync(), isTrue);
    });

    test('بعد الاسترداد بالرمز يكتمل الإقلاع بالمفتاح الجديد', () async {
      await h.createLegacyDb();
      await h.service(processId: 'A').migrate(h.db);
      final code = h.memory.values[DbKeyNames.recoveryPending(name)]!;
      h.memory.values.clear();
      final boot = h.service(processId: 'B');
      expect(await boot.manager.resolveForOpen(h.db), isA<DbKeyUnavailable>());
      final rec = await boot.manager.recoverWithCode(h.db, code);
      expect(rec, isA<DbKeyReady>());
      expect(await boot.manager.resolveForOpen(h.db), isA<DbKeyReady>());
    });

    test('db + v2-new بلا pre-v2 (قبل التبديل) ⇒ يُحذف v2-new فقط', () async {
      await h.createLegacyDb();
      await FakeSqlCipherEngine.create(h.sibling('.v2-new'), DbKey.raw('5' * 64));
      final r = await h.service(processId: 'B').manager.resolveForOpen(h.db);
      expect((r as DbKeyReady).key.kind, DbKeyKind.legacyDerived);
      expect(h.sibling('.v2-new').existsSync(), isFalse);
    });
  });
}
