// E-01 §4.3: الاستعادة المعلَّقة — تُفحص قبل الجدولة، والحيّة تُنقل لـ.pre-restore.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/pending_restore.dart';

void main() {
  late Directory dir;
  late String dbPath;
  File f(String suffix) => File('$dbPath$suffix');

  /// «صالحٌ» = أوّل سطر `OK`. يحاكي نتيجة فتح النسخة بمرشّحٍ + quick_check.
  Future<bool> opener(File file) async {
    if (!file.existsSync()) return false;
    return file.readAsStringSync().startsWith('OK');
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('picpos_restore_');
    dbPath = '${dir.path}${Platform.pathSeparator}picpos_unified.db';
    PendingRestore.openerOverride = opener;
  });
  tearDown(() {
    PendingRestore.openerOverride = null;
    dir.deleteSync(recursive: true);
  });

  File backup(String content) =>
      File('${dir.path}${Platform.pathSeparator}b.db')..writeAsStringSync(content);

  group('schedule (الجدولة بعد التحقق)', () {
    test('نسخة صالحة تُجدوَل ولا تُمسّ الحيّة', () async {
      File(dbPath).writeAsStringSync('OK live');
      expect(await PendingRestore.schedule(backup('OK restored').path, dbPath),
          isTrue);
      expect(f('.restore-pending').readAsStringSync(), 'OK restored');
      expect(File(dbPath).readAsStringSync(), 'OK live');
      expect(f('.restore-pending.tmp').existsSync(), isFalse);
    });

    test('نسخة لا يفتحها أي مفتاح تُرفض ولا يبقى معلَّق', () async {
      File(dbPath).writeAsStringSync('OK live');
      expect(await PendingRestore.schedule(backup('garbage').path, dbPath),
          isFalse);
      expect(f('.restore-pending').existsSync(), isFalse);
      expect(f('.restore-pending.tmp').existsSync(), isFalse);
      expect(File(dbPath).readAsStringSync(), 'OK live');
    });

    test('نسخة غير موجودة ⇒ false', () async {
      expect(await PendingRestore.schedule('${dir.path}/nope.db', dbPath),
          isFalse);
    });
  });

  group('apply', () {
    test('تنقل الحيّة إلى .pre-restore ثم تضع المستعادة وتحذف المعلَّق',
        () async {
      File(dbPath).writeAsStringSync('OK live');
      f('-wal').writeAsStringSync('stale wal');
      f('.restore-pending').writeAsStringSync('OK restored');

      expect(await PendingRestore.apply(dbPath), isTrue);

      expect(File(dbPath).readAsStringSync(), 'OK restored');
      expect(f('.pre-restore').readAsStringSync(), 'OK live');
      expect(f('.restore-pending').existsSync(), isFalse);
      expect(f('-wal').existsSync(), isFalse, reason: 'WAL القديم يُزال');
      expect(f('.restoring').existsSync(), isFalse);
    });

    test('معلَّق لا يُفتح ⇒ يُرفض (.restore-rejected) والحيّة لا تُمسّ',
        () async {
      File(dbPath).writeAsStringSync('OK live');
      f('.restore-pending').writeAsStringSync('bad bytes');

      expect(await PendingRestore.apply(dbPath), isFalse);

      expect(File(dbPath).readAsStringSync(), 'OK live');
      expect(f('.pre-restore').existsSync(), isFalse);
      expect(f('.restore-pending').existsSync(), isFalse);
      expect(f('.restore-rejected').readAsStringSync(), 'bad bytes');
    });

    test('بلا معلَّق ⇒ false ولا أثر', () async {
      File(dbPath).writeAsStringSync('OK live');
      expect(await PendingRestore.apply(dbPath), isFalse);
      expect(File(dbPath).readAsStringSync(), 'OK live');
    });

    test('بلا قاعدة حيّة (تثبيت فارغ) ⇒ يضع المستعادة بلا .pre-restore',
        () async {
      f('.restore-pending').writeAsStringSync('OK restored');
      expect(await PendingRestore.apply(dbPath), isTrue);
      expect(File(dbPath).readAsStringSync(), 'OK restored');
      expect(f('.pre-restore').existsSync(), isFalse);
    });

    test('استئناف بعد انقطاع بين النقلين: لا يضيع الأصل', () async {
      // الحالة: الحيّة نُقلت إلى .pre-restore ثم انقطع قبل وضع المستعادة.
      f('.pre-restore').writeAsStringSync('OK original');
      f('.restore-pending').writeAsStringSync('OK restored');

      expect(await PendingRestore.apply(dbPath), isTrue);

      expect(File(dbPath).readAsStringSync(), 'OK restored');
      expect(f('.pre-restore').readAsStringSync(), 'OK original');
    });

    test('استئناف بعد انقطاع قبل حذف المعلَّق: لا يُكتب الأصل فوق .pre-restore',
        () async {
      // الحالة: المستعادة وُضعت لكنّ المعلَّق باقٍ و.pre-restore = الأصل الحقيقيّ.
      File(dbPath).writeAsStringSync('OK restored');
      f('.pre-restore').writeAsStringSync('OK original');
      f('.restore-pending').writeAsStringSync('OK restored');

      expect(await PendingRestore.apply(dbPath), isTrue);

      expect(f('.pre-restore').readAsStringSync(), 'OK original',
          reason: 'الأصل الحقيقيّ لا يُستبدَل بالمستعادة');
      expect(File(dbPath).readAsStringSync(), 'OK restored');
    });
  });

  group('finalize / rollback / reconcileLeftover', () {
    test('finalize(opens: true) يحذف .pre-restore', () async {
      File(dbPath).writeAsStringSync('OK restored');
      f('.pre-restore').writeAsStringSync('OK live');
      await PendingRestore.finalize(dbPath, opens: true);
      expect(f('.pre-restore').existsSync(), isFalse);
      expect(File(dbPath).readAsStringSync(), 'OK restored');
    });

    test('finalize(opens: false) تعيد القاعدة السابقة وتحفظ المستعادة مرفوضة',
        () async {
      File(dbPath).writeAsStringSync('restored but unopenable');
      f('.pre-restore').writeAsStringSync('OK live');
      await PendingRestore.finalize(dbPath, opens: false);
      expect(File(dbPath).readAsStringSync(), 'OK live');
      expect(f('.restore-rejected').readAsStringSync(),
          'restored but unopenable');
      expect(f('.pre-restore').existsSync(), isFalse);
    });

    test('reconcileLeftover: الحالية تفتح ⇒ يحذف .pre-restore', () async {
      File(dbPath).writeAsStringSync('OK restored');
      f('.pre-restore').writeAsStringSync('OK live');
      await PendingRestore.reconcileLeftover(dbPath);
      expect(f('.pre-restore').existsSync(), isFalse);
    });

    test('reconcileLeftover: الحالية لا تفتح ⇒ يعيد .pre-restore', () async {
      File(dbPath).writeAsStringSync('junk');
      f('.pre-restore').writeAsStringSync('OK live');
      await PendingRestore.reconcileLeftover(dbPath);
      expect(File(dbPath).readAsStringSync(), 'OK live');
    });

    test('reconcileLeftover مع معلَّق قائم لا يفعل شيئًا (apply يستأنف)',
        () async {
      f('.pre-restore').writeAsStringSync('OK original');
      f('.restore-pending').writeAsStringSync('OK restored');
      await PendingRestore.reconcileLeftover(dbPath);
      expect(f('.pre-restore').existsSync(), isTrue);
    });
  });
}
