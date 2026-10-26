import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import '../../core/config/data_dir.dart';

import '../../services/db_backup_sidecars.dart';
import '../../services/db_key_blocked_actions.dart';
import '../../services/db_key_boot.dart';
import '../../services/db_key_manager.dart';
import '../../services/db_key_types.dart';
import 'pending_restore.dart';

/// مسارُ الإقلاع الموحَّد لمفتاح القاعدة (E-01 المرحلة ب):
/// استعادةٌ معلَّقة ⇒ طلبُ ترحيلٍ مؤجَّل ⇒ `resolveForOpen`. كلُّه **قبل** فتح أيّ
/// مقبض. النتيجةُ تُشارَك بين بوّابة `main` و`openConnection`.
Future<DbKeyResolution> resolveDatabaseKey(File file) {
  return DbKeyBoot.memoized(file.path, () async {
    await PendingRestore.reconcileLeftover(file.path);
    final restoreApplied = await PendingRestore.apply(file.path);
    final boot = DbKeyBoot.factoryOverride?.call(file) ??
        DbKeyBoot.production(Directory(p.join(file.parent.path, 'backups')));
    final res = await boot.prepare(file);
    if (restoreApplied) {
      // الفتحُ الفعليّ أثبت النجاحَ ⇒ يُحذف `.pre-restore`؛ الفشلُ الحقيقيّ ⇒
      // يُعاد الأصل. عطلُ التخزين الآمن ليس ذنبَ الملف: يُترك للإقلاع التالي.
      final storeFault = res is DbKeyUnavailable &&
          res.reason == DbKeyUnavailableReason.storeFailure;
      if (!storeFault) {
        await PendingRestore.finalize(file.path, opens: res is DbKeyReady);
      }
    }
    return res;
  });
}

/// بوّابةُ `main`: `null` = آمنٌ للمتابعة، وإلا استثناءُ الحجب.
Future<Object?> checkDatabaseKeyGateImpl(String dbPath) async {
  final res = await resolveDatabaseKey(File(dbPath));
  return res is DbKeyUnavailable ? DbKeyBlockedException(res, dbPath) : null;
}

Future<Directory> _docs() => DataDir.documents();

/// تنفيذ شاشة الحجب الإنتاجيّ.
class ProductionDbKeyBlockedActions implements DbKeyBlockedActions {
  ProductionDbKeyBlockedActions(this.dbFile);

  final File dbFile;

  Directory get _backups => Directory(p.join(dbFile.parent.path, 'backups'));

  DbKeyBoot _boot() => DbKeyBoot.factoryOverride?.call(dbFile) ??
      DbKeyBoot.production(_backups);

  @override
  Future<DbKeyResolution> retry() {
    DbKeyBoot.resetMemo();
    return resolveDatabaseKey(dbFile);
  }

  @override
  Future<DbKeyResolution> recoverWithCode(String code) async {
    final r = await _boot().manager.recoverWithCode(dbFile, code);
    if (r is DbKeyReady) DbKeyBoot.resetMemo();
    return r;
  }

  @override
  Future<bool> hasRollbackSource() async {
    if (await File('${dbFile.path}.pre-v2').exists()) return true;
    return await PreMigrationBackups.latest(
            _backups, DbKeyManager.dbNameOf(dbFile)) !=
        null;
  }

  @override
  Future<DbKeyRollbackResult> rollbackToPreMigration() async {
    try {
      final boot = _boot();
      if (await File('${dbFile.path}.pre-v2').exists()) {
        if (await boot.service.rollbackToPreMigration(dbFile)) {
          DbKeyBoot.resetMemo();
          return DbKeyRollbackResult.done;
        }
      }
      final copy = await PreMigrationBackups.latest(
          _backups, DbKeyManager.dbNameOf(dbFile));
      if (copy != null &&
          await PendingRestore.schedule(copy.path, dbFile.path)) {
        return DbKeyRollbackResult.scheduledRestart;
      }
    } catch (e) {
      debugPrint('[DBKEY] rollback failed: ${e.runtimeType}');
    }
    return DbKeyRollbackResult.unavailable;
  }

  @override
  Future<String> exportDiagnostics(DbKeyUnavailable why) async {
    final text = await DbKeyDiagnostics.build(dbFile, why);
    final dir = Directory(p.join((await _docs()).path, 'backups'));
    await dir.create(recursive: true);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final out = File(p.join(dir.path, 'db-key-diagnostics-$stamp.txt'));
    await out.writeAsString(text, flush: true);
    return out.path;
  }

  @override
  void exitApp() => exit(0);
}
