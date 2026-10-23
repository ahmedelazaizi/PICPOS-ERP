part of 'database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATABASE MIGRATIONS — Schema upgrade path (Orchestration Layer)
// Optimized for maintainability by splitting into versioned Epochs.
// ═══════════════════════════════════════════════════════════════════════════

/// ISS-03 / P1-01: Safe migration helper — swallows known idempotent SQLite
/// errors but rethrows anything unexpected.
///
/// Accepted safe-skip patterns (each tied to a specific DDL operation):
///   • "duplicate column name" — ALTER TABLE ADD COLUMN on an already-present column
///   • "already exists" + (table|index|view) — CREATE TABLE/INDEX/VIEW for an
///     object that was added by a previous migration run
///   • "no such column" — fixDateTime-style UPDATE that references a column
///     which was never created (safe to skip; data doesn't exist)
///   • "cannot add a unique column" — SQLite رافضة `ADD COLUMN ... UNIQUE`
///     نهائياً (مفيش صيغة كده أصلاً). كانت بتوصل للـ`rethrow` فتقتل الإقلاع
///     كله بدل ما تتخطّى — شوف التعليق على [isIdempotentMigrationError].
@visibleForTesting
bool isIdempotentMigrationError(String message) {
  final msg = message.toLowerCase();
  return msg.contains('duplicate column name') ||
      (msg.contains('already exists') &&
          (msg.contains('table') ||
              msg.contains('index') ||
              msg.contains('view'))) ||
      msg.contains('no such column') ||
      // ── ليه دي هنا ────────────────────────────────────────────────────────
      // `ALTER TABLE x ADD COLUMN c TEXT UNIQUE` **مرفوضة في SQLite** (الجدول
      // ممكن يكون فيه صفوف مكرَّرة أصلاً). v132 كان بيعملها على
      // `activity_logs`، والخطأ مش في القايمة → `rethrow` → `onUpgrade` يفشل →
      // drift ما بيفتحش القاعدة → التطبيق ما بيقلعش. (MIG-002: الترقية **مش**
      // جوه ترانزاكشن — drift 2.32 بيشغّلها بلا غلاف — فكل خطوة بتتثبّت لوحدها
      // وuser_version بيفضل قديم لحد ما تخلص كلها، فالإقلاع الجاي بيعيد الخطوات
      // كلها: لازم كل خطوة تكون idempotent، وده اللي بيثبته
      // udit_b_migration_safety_test.)
      //
      // البلوكات نفسها اتصلّحت (عمود عادي + فهرس فريد جزئي)، بس ده خط دفاع
      // تاني: أي `ADD COLUMN ... UNIQUE` فاضلة في مايجريشن قديمة أو جاية
      // تتخطّى بدل ما تقفل التطبيق.
      msg.contains('cannot add a unique column');
}

Future<void> _safeMigrate(String label, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (isIdempotentMigrationError(e.toString())) {
      debugPrint('[Migration] $label (safe-skip): $e');
      // MIG-003: "no such column" may be a TYPO in a new step, not legacy data —
      // persist it so the skip is visible in the field log, not only in debugPrint.
      if (e.toString().toLowerCase().contains('no such column')) {
        await DiagnosticLogger.log('MIGRATION-SKIP', '$label: $e');
      }
    } else {
      debugPrint('[Migration] $label (ERROR - rethrowing): $e');
      // Phase 1 diagnostics: persist genuine migration failures to the
      // Documents log so a boot that dies here is traceable in the field.
      await DiagnosticLogger.logError(DiagnosticLogger.migration, label, e);
      rethrow;
    }
  }
}

/// MIG-001 — the on-disk database is newer than this build understands.
class DatabaseTooNewException implements Exception {
  const DatabaseTooNewException({required this.dbVersion, required this.appVersion});
  final int dbVersion;
  final int appVersion;
  @override
  String toString() =>
      'قاعدة البيانات أحدث من هذا الإصدار من التطبيق (قاعدة v$dbVersion، تطبيق v$appVersion). '
      'ثبّت إصدارًا أحدث أو استعد نسخة احتياطية متوافقة — لم يتم تغيير أي شيء. '
      '[DatabaseTooNewException]';
}

/// MIG-004 — the mandatory safety snapshot could not be taken; nothing was changed.
class PreMigrationBackupFailedException implements Exception {
  const PreMigrationBackupFailedException({required this.from, required this.to, this.cause});
  final int from;
  final int to;
  final Object? cause;
  @override
  String toString() =>
      'تعذّر أخذ النسخة الاحتياطية الإلزامية قبل ترقية قاعدة البيانات (v$from → v$to)؛ '
      'أُوقفت الترقية ولم يتغيّر شيء. تحقق من المساحة الحرة وصلاحيات مجلد المستندات. '
      '[PreMigrationBackupFailedException${cause == null ? '' : ': $cause'}]';
}

/// Test seams (MIG-004). Production leaves both null.
@visibleForTesting
Future<String?> Function()? preMigrationBackupOverride;
@visibleForTesting
Future<bool> Function()? liveDatabaseFileExistsOverride;

Future<bool> _liveDatabaseFileExists() async {
  try {
    return await File(await getDatabasePath()).exists();
  } catch (_) {
    return false; // no platform path (unit tests / web): nothing to protect
  }
}
extension DatabaseMigrations on AppDatabase {
  /// Runs all schema migrations from version [from] to version [to].
  /// Called by [AppDatabase.migration] onUpgrade handler.
  ///
  /// PIR P2.6: Split into 3 epoch methods for maintainability:
  /// - [_migrateEpoch1]: v1 → v59 (core schema, basic features)
  /// - [_migrateEpoch2]: v60 → v80 (PIR Phase 0, performance, new modules)
  /// - [_migrateEpoch3]: v81 → v132 (enterprise, advanced features, multi-client sync)
  Future<void> runOnUpgrade(Migrator m, int from, int to) async {
    // MIG-001: a database NEWER than this build (rollback to an older app, or a
    // restored backup from a newer one) must not be "upgraded": every epoch step
    // is gated `from < N` (no-ops), drift would then stamp user_version back to
    // the older number and the next real upgrade would replay v197+ over data
    // already migrated. Refuse before touching anything (and before the stamp).
    if (from > to) throw DatabaseTooNewException(dbVersion: from, appVersion: to);

    // R-29 / MIG-004: pre-migration backup is MANDATORY when a live database
    // file exists: no backup => the upgrade is aborted before any change, and
    // the app refuses to open instead of migrating without a way back.
    //
    // من غير `checkpoint` عن قصد: إحنا **جوّه** `onUpgrade` والاتصال في نص فتحه
    // والـ migrator ماسكه، و`PRAGMA wal_checkpoint` ممكن يتعارض مع القفل. النسخة
    // ممكن تنقص آخر معاملات قبل الإقفال، وده مقبول لأنها لقطة أمان قبل تغيير
    // سكيما مش طريق رجوع من حذف.
    String? backupPath;
    Object? backupError;
    try {
      backupPath = await (preMigrationBackupOverride ?? createDatabaseBackup)();
    } catch (e) {
      backupError = e;
    }
    if (backupPath != null) {
      debugPrint('[Migration] Pre-migration backup created: $backupPath (v$from → v$to)');
    } else if (await (liveDatabaseFileExistsOverride ?? _liveDatabaseFileExists)()) {
      throw PreMigrationBackupFailedException(
        from: from,
        to: to,
        cause: backupError,
      );
    } else {
      debugPrint('[Migration] no live database file — pre-migration backup skipped (v$from → v$to)');
    }
    // Epoch 1: v1 → v59
    if (from < 60) await _migrateEpoch1(m, from);
    // Epoch 2: v60 → v80
    if (from < 81) await _migrateEpoch2(m, from);
    // Epoch 3: v81 → v111+
    await _migrateEpoch3(m, from);
  }
}
