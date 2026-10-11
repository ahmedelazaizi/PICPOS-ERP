import 'dart:io';

import 'package:path/path.dart' as p;

import 'db_keyinfo_file.dart';

/// `keyinfo` مجاورٌ لكلّ نسخةٍ احتياطيّة: `<backup>.db.keyinfo.json` (T11).
/// أفضلُ جهدٍ دائمًا: فشلُه لا يُفشل نسخةً.
class BackupSidecars {
  BackupSidecars._();

  /// يكتب keyinfo النسخةِ من keyinfo القاعدة الحيّة (النوعُ والبصمةُ والغلاف؛
  /// بلا علمِ تقدّمِ الترحيل). لا شيء إن لم يوجد keyinfo للقاعدة.
  static Future<void> writeFor(File db, File backup, {DateTime? now}) async {
    try {
      final info = await KeyInfoFile.read(db);
      if (info == null) return;
      await KeyInfoFile.write(
        backup,
        KeyInfo(
          kind: info.kind,
          fingerprint: info.fingerprint,
          createdAt: (now ?? DateTime.now()).toIso8601String(),
          migratedFrom: info.migratedFrom,
          recoveryEnvelope: info.recoveryEnvelope,
        ),
      );
    } catch (_) {}
  }

  /// يحذف المجاورَ مع النسخة.
  static Future<void> deleteFor(File backup) async {
    try {
      final side = KeyInfoFile.of(backup);
      if (await side.exists()) await side.delete();
    } catch (_) {}
  }

  /// ينسخ المجاورَ إلى جانب النسخة المصدَّرة [exportedBackup].
  static Future<void> copyFor(File backup, File exportedBackup) async {
    try {
      final side = KeyInfoFile.of(backup);
      if (await side.exists()) await side.copy(KeyInfoFile.of(exportedBackup).path);
    } catch (_) {}
  }
}

/// نسخُ ما قبل الترحيل في `backups/key-migration/` (تُحفَظ 30 يومًا).
class PreMigrationBackups {
  PreMigrationBackups._();

  static const Duration retention = Duration(days: 30);

  /// أحدثُ نسخةٍ ما زالت ضمن المدّة، أو `null`.
  static Future<File?> latest(
    Directory backupsDir,
    String dbName, {
    DateTime? now,
  }) async {
    try {
      final dir = Directory(p.join(backupsDir.path, 'key-migration'));
      if (!await dir.exists()) return null;
      final prefix = '$dbName.pre-v2-';
      final cutoff = (now ?? DateTime.now()).subtract(retention);
      File? best;
      DateTime? bestAt;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final n = p.basename(e.path);
        if (!n.startsWith(prefix) || !n.endsWith('.db')) continue;
        final at = await e.lastModified();
        if (at.isBefore(cutoff)) continue;
        if (bestAt == null || at.isAfter(bestAt)) {
          best = e;
          bestAt = at;
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  /// آخرُ يومٍ تتوفّر فيه النسخة (تاريخُ التعديل + 30 يومًا).
  static Future<DateTime?> availableUntil(
    Directory backupsDir,
    String dbName, {
    DateTime? now,
  }) async {
    final f = await latest(backupsDir, dbName, now: now);
    if (f == null) return null;
    return (await f.lastModified()).add(retention);
  }
}
