import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BackupService {
  static const String _backupDirName = 'UralCash_Backups';
  static const String _bucketName = 'backups';

  /// Performs a backup of the current database file and optionally uploads it to the cloud
  static Future<File?> performBackup(
    String dbPath, {
    bool uploadToCloud = false,
    SupabaseClient? supabase,
  }) async {
    try {
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        debugPrint('Backup failed: Database file not found at $dbPath');
        return null;
      }

      // 1. Get backup directory (Documents/UralCash_Backups)
      final docDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(docDir.path, _backupDirName));

      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // 2. Generate timestamped filename
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupFileName = 'uralcash_backup_$timestamp.sqlite';
      final backupPath = p.join(backupDir.path, backupFileName);

      // 3. Copy file
      final backupFile = await dbFile.copy(backupPath);
      debugPrint('Local backup successful: ${backupFile.path}');

      // 4. Cloud Upload (Optional)
      if (uploadToCloud && supabase != null) {
        await _uploadToCloud(backupFile, backupFileName, supabase);
      }

      // 5. Cleanup old backups (keep last 10)
      await _cleanupOldBackups(backupDir);

      return backupFile;
    } catch (e) {
      debugPrint('Backup error: $e');
      return null;
    }
  }

  static Future<void> _uploadToCloud(
    File file,
    String fileName,
    SupabaseClient supabase,
  ) async {
    try {
      await supabase.storage
          .from(_bucketName)
          .upload(
            fileName,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
      debugPrint('Cloud backup successful: $fileName');
    } catch (e) {
      debugPrint('Cloud upload failed: $e');
    }
  }

  static Future<void> _cleanupOldBackups(Directory backupDir) async {
    try {
      final files = await backupDir
          .list()
          .where((f) => f is File && f.path.endsWith('.sqlite'))
          .toList();
      if (files.length > 20) {
        // Keep last 20 now for safety
        // Sort by modification date
        files.sort(
          (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
        );

        // Remove oldest
        final toDelete = files.take(files.length - 20);
        for (final f in toDelete) {
          await f.delete();
        }
      }
    } catch (e) {
      debugPrint('Backup cleanup error: $e');
    }
  }
}
