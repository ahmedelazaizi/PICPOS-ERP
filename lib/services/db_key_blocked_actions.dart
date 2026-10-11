import 'dart:io';

import 'package:path/path.dart' as p;

import 'db_key_types.dart';
import 'db_keyinfo_file.dart';

enum DbKeyRollbackResult {
  /// رُجع إلى نسخة ما قبل الترحيل فعلًا (أعد المحاولة).
  done,

  /// جُدولت استعادةٌ تُطبَّق في الإقلاع التالي.
  scheduledRestart,

  /// لا نسخةَ متاحة أو تعذّر.
  unavailable,
}

/// ما تفعله شاشةُ الحجب. مجرّدٌ كي تُختبر الشاشةُ بلا قاعدةٍ ولا تخزين.
abstract class DbKeyBlockedActions {
  /// يعيد المحاولةَ كاملةً (يُصفَّر الحفظُ المؤقّت) ويعيد القرار الجديد.
  Future<DbKeyResolution> retry();

  /// الاسترداد برمز الاسترداد؛ رمزٌ خاطئ لا يكتب شيئًا.
  Future<DbKeyResolution> recoverWithCode(String code);

  /// «استعادة من نسخة ما قبل الترحيل» (تخسر ما كُتب بعد الترحيل).
  Future<DbKeyRollbackResult> rollbackToPreMigration();

  /// هل ثمّة نسخةُ ما قبل الترحيل (قرب القاعدة أو في `backups/key-migration`)؟
  Future<bool> hasRollbackSource();

  /// يكتب سجلًّا تشخيصيًّا (بلا مفاتيح ولا رموز) ويعيد مسارَه.
  Future<String> exportDiagnostics(DbKeyUnavailable why);

  /// إغلاقُ التطبيق ليُعاد فتحُه.
  void exitApp();
}

/// نصُّ السجلّ التشخيصيّ: حالةُ الملفات وkeyinfo غيرُ السرّيّ فقط. **لا مفتاحَ
/// ولا رمزَ استرداد ولا غلافَه** يدخل هنا.
class DbKeyDiagnostics {
  DbKeyDiagnostics._();

  static Future<String> build(
    File db,
    DbKeyUnavailable why, {
    DateTime? now,
  }) async {
    final b = StringBuffer()
      ..writeln('PicPos database key diagnostics')
      ..writeln('time: ${(now ?? DateTime.now()).toIso8601String()}')
      ..writeln('reason: ${why.reason.name}')
      ..writeln('canRecoverWithCode: ${why.canRecoverWithCode}')
      ..writeln('preMigrationCopyAvailable: ${why.preMigrationCopyAvailable}')
      ..writeln('detail: ${why.detail ?? '-'}')
      ..writeln('database: ${p.basename(db.path)}')
      ..writeln('platform: ${Platform.operatingSystem}');
    for (final s in [
      '',
      '-wal',
      '-shm',
      '.pre-v2',
      '.v2-new',
      '.v2-orphan',
      '.pre-restore',
      '.restore-pending',
      '.keyinfo.json',
      '.key-migration.request.json',
    ]) {
      final f = File('${db.path}$s');
      final exists = await f.exists();
      b.writeln(
          'file ${p.basename(db.path)}$s: ${exists ? '${await f.length()} bytes' : 'absent'}');
    }
    final info = await KeyInfoFile.read(db);
    if (info == null) {
      b.writeln('keyinfo: absent or unreadable');
    } else {
      b
        ..writeln('keyinfo.kind: ${info.kind.name}')
        ..writeln('keyinfo.fingerprint: ${info.fingerprint ?? '-'}')
        ..writeln('keyinfo.migratedFrom: ${info.migratedFrom ?? '-'}')
        ..writeln('keyinfo.hasRecoveryEnvelope: ${info.recoveryEnvelope != null}');
      final m = info.migration;
      if (m != null) {
        b
          ..writeln('migration.state: ${m.state}')
          ..writeln('migration.startedAt: ${m.startedAt}')
          ..writeln('migration.confirmedAt: ${m.confirmedAt ?? '-'}');
      }
    }
    return b.toString();
  }
}
