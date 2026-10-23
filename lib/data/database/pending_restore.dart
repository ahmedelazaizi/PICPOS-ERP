import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;

import '../../services/db_key_manager.dart';
import '../../services/sqlcipher_engine.dart' show DbInspection;
import 'schema_version_limit.dart';

/// هل [file] نسخةٌ قابلةٌ للفتح بأحد المفاتيح المعروفة وسليمةٌ؟
typedef BackupOpener = Future<bool> Function(File file);

/// تطبيقُ الاستعادة المعلَّقة بأمان (E-01 §4.3).
///
/// الاستعادةُ كانت `pending.copy(dbPath)` فوق القاعدة الحيّة بلا أيّ فحص —
/// ونسخةٌ لا يُعرف مفتاحُها كانت تمحو القاعدةَ الحيّة. الآن:
///  1. تُفحص النسخةُ المعلَّقة (تُفتح بمرشّحٍ + `quick_check`) **قبل** لمس
///     القاعدة؛ المرفوضةُ تُنقل إلى `.restore-rejected` والحيّةُ لا تُمسّ.
///  2. القاعدةُ الحيّةُ تُنقل إلى `.pre-restore` (لا تُكتب فوقها).
///  3. بعد أن يُثبت الفتحُ الفعليّ نجاحَه يُحذف `.pre-restore`، وإلا يُعاد.
class PendingRestore {
  PendingRestore._();

  static const String pendingSuffix = '.restore-pending';
  static const String preRestoreSuffix = '.pre-restore';
  static const String rejectedSuffix = '.restore-rejected';

  /// للاختبار فقط: يستبدل الفحصَ الإنتاجيّ (SQLCipher + مرشّحو المفاتيح).
  @visibleForTesting
  static BackupOpener? openerOverride;

  /// الفحصُ الإنتاجيّ: يفتح بأيّ مرشّح (v2 المخزَّن، المشتقّ، الاحتياطيّ
  /// القديم) ويشغّل `quick_check`. كلُّ استثناءٍ ⇒ `false` (فشلٌ مغلق).
  static Future<bool> canOpen(File file, {required String dbName}) async {
    final o = openerOverride;
    if (o != null) return o(file);
    try {
      final m = DbKeyManager.production();
      final key = await m.findOpeningKey(file, dbName: dbName);
      if (key == null) return false;
      return acceptInspection(await m.engine.inspect(file, key));
    } catch (e) {
      debugPrint('[RESTORE] verification failed: ${e.runtimeType}');
      return false;
    }
  }

  /// BKP-002: a backup is restorable only if it passes quick_check AND was
  /// written by this build or an older one — a newer schema would be opened by
  /// a build that cannot understand it (see MIG-001).
  static bool acceptInspection(DbInspection i,
          {int maxSchemaVersion = kMaxSupportedSchemaVersion}) =>
      i.quickCheckOk && i.userVersion <= maxSchemaVersion;

  static Future<void> _deleteSidecars(String path) async {
    for (final s in ['$path-wal', '$path-shm']) {
      final f = File(s);
      if (await f.exists()) await f.delete();
    }
  }

  /// يجدول استعادةً من [backupPath] **بعد التحقّق**. `false` إن غاب الملفُّ أو
  /// لم يفتحه أيُّ مفتاحٍ معروف (لا شيء يُجدوَل).
  static Future<bool> schedule(String backupPath, String dbPath) async {
    final src = File(backupPath);
    if (!await src.exists()) return false;
    final pendingPath = '$dbPath$pendingSuffix';
    final tmp = File('$pendingPath.tmp');
    try {
      await src.copy(tmp.path);
      if (!await canOpen(tmp, dbName: p.basename(dbPath))) {
        debugPrint('[RESTORE] backup rejected: no known key opens it');
        await tmp.delete();
        await _deleteSidecars(tmp.path);
        return false;
      }
      await _deleteSidecars(tmp.path);
      await tmp.rename(pendingPath);
      return true;
    } catch (e) {
      debugPrint('[RESTORE] schedule failed: $e');
      if (await tmp.exists()) await tmp.delete();
      return false;
    }
  }

  /// يطبّق الاستعادةَ المعلَّقة إن وُجدت. يعيد `true` إن طُبِّقت (وبقي
  /// `.pre-restore` بانتظار [finalize]).
  static Future<bool> apply(String dbPath) async {
    try {
      final pending = File('$dbPath$pendingSuffix');
      if (!await pending.exists()) return false;
      final db = File(dbPath);
      final pre = File('$dbPath$preRestoreSuffix');
      final name = p.basename(dbPath);

      if (!await canOpen(pending, dbName: name)) {
        final rejected = File('$dbPath$rejectedSuffix');
        if (await rejected.exists()) await rejected.delete();
        await pending.rename(rejected.path);
        debugPrint('[RESTORE] pending restore rejected; live database kept');
        return false;
      }

      // نسخةٌ مؤقّتة بجانب القاعدة ثم نقلان؛ المعلَّق لا يُحذف إلا في النهاية،
      // فانقطاعٌ في أيّ نقطةٍ يُستأنف في الإقلاع التالي.
      final staged = File('$dbPath.restoring');
      await pending.copy(staged.path);

      // `.pre-restore` الموجود يعني انقطاعًا سابقًا بعد نقل الأصل: لا يُكتب
      // فوقه (هو الأصلُ الحقيقيّ)، وما في `db` حينها نسخةٌ مستعادةٌ جزئيًّا.
      if (await db.exists()) {
        if (await pre.exists()) {
          await db.delete();
        } else {
          await db.rename(pre.path);
        }
      }
      // ملفاتُ WAL/SHM لقاعدةٍ أخرى على ملفٍّ ليس لها = فسادٌ أو رجوعُ بياناتٍ
      // قديمة؛ تُزال مع الاستبدال.
      await _deleteSidecars(dbPath);
      await staged.rename(dbPath);
      await pending.delete();
      debugPrint('[RESTORE] pending restore applied (pre-restore kept)');
      return true;
    } catch (e) {
      debugPrint('[RESTORE] failed to apply pending restore: $e');
      return false;
    }
  }

  /// بعد أن يُثبت الفتحُ الفعليّ [opens]: `true` ⇒ يُحذف `.pre-restore`؛
  /// `false` ⇒ يُعاد مكانَ القاعدة (والمستعادةُ تُنقل إلى `.restore-rejected`).
  static Future<void> finalize(String dbPath, {required bool opens}) async {
    try {
      final pre = File('$dbPath$preRestoreSuffix');
      if (!await pre.exists()) return;
      if (opens) {
        await pre.delete();
        return;
      }
      await rollback(dbPath);
    } catch (e) {
      debugPrint('[RESTORE] finalize failed: $e');
    }
  }

  /// يعيد `.pre-restore` مكانَ القاعدة. المستعادةُ تُحفظ في `.restore-rejected`.
  static Future<void> rollback(String dbPath) async {
    final pre = File('$dbPath$preRestoreSuffix');
    if (!await pre.exists()) return;
    final db = File(dbPath);
    if (await db.exists()) {
      final rejected = File('$dbPath$rejectedSuffix');
      if (await rejected.exists()) await rejected.delete();
      await db.rename(rejected.path);
    }
    await _deleteSidecars(dbPath);
    await pre.rename(dbPath);
    debugPrint('[RESTORE] rolled back to the pre-restore database');
  }

  /// انقطاعٌ بعد [apply] وقبل [finalize]: `.pre-restore` باقٍ بلا معلَّق.
  /// إن فتحت القاعدةُ الحاليّةُ بمرشّحٍ حُذف، وإلا أُعيد.
  static Future<void> reconcileLeftover(String dbPath) async {
    try {
      final pre = File('$dbPath$preRestoreSuffix');
      if (!await pre.exists()) return;
      if (await File('$dbPath$pendingSuffix').exists()) return; // apply يستأنف
      final db = File(dbPath);
      final ok = await db.exists() &&
          await canOpen(db, dbName: p.basename(dbPath));
      await finalize(dbPath, opens: ok);
    } catch (e) {
      debugPrint('[RESTORE] reconcile failed: $e');
    }
  }
}
