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
Future<void> _safeMigrate(String label, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    final msg = e.toString().toLowerCase();
    final isIdempotentError =
        msg.contains('duplicate column name') ||
        (msg.contains('already exists') &&
            (msg.contains('table') ||
                msg.contains('index') ||
                msg.contains('view'))) ||
        msg.contains('no such column');
    if (isIdempotentError) {
      debugPrint('[Migration] $label (safe-skip): $e');
    } else {
      debugPrint('[Migration] $label (ERROR - rethrowing): $e');
      // Phase 1 diagnostics: persist genuine migration failures to the
      // Documents log so a boot that dies here is traceable in the field.
      await DiagnosticLogger.logError(DiagnosticLogger.migration, label, e);
      rethrow;
    }
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
    // R-29: Pre-migration backup — safety snapshot before schema changes
    try {
      final backupPath = await createDatabaseBackup();
      debugPrint('[Migration] Pre-migration backup created: $backupPath (v$from → v$to)');
    } catch (e) {
      debugPrint('[Migration] Pre-migration backup failed (non-blocking): $e');
    }

    // Epoch 1: v1 → v59
    if (from < 60) await _migrateEpoch1(m, from);
    // Epoch 2: v60 → v80
    if (from < 81) await _migrateEpoch2(m, from);
    // Epoch 3: v81 → v111+
    await _migrateEpoch3(m, from);
  }
}
