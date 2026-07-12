import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/config/app_config.dart';
import '../../services/security_service.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' as pg;
import 'pg_config.dart';
import 'pg_compat_sql.dart';

/// Get database filename based on app flavor
/// This prevents data conflicts when multiple apps are installed
String getDatabaseFileName() {
  switch (AppConfig.flavor) {
    case AppFlavor.restaurant:
      return 'uralcash_restaurant.db';
    case AppFlavor.cafe:
      return 'uralcash_cafe.db';
    case AppFlavor.supermarket:
      return 'uralcash_supermarket.db';
    case AppFlavor.supermarketPro:
      return 'uralcash_supermarket_pro.db';
    case AppFlavor.supermarketPlus:
      return 'uralcash_supermarket_plus.db';
    case AppFlavor.commercial:
      return 'uralcash_commercial.db';
    case AppFlavor.unified:
      return 'uralcash_unified.db';
  }
}

QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, getDatabaseFileName()));

    // Phase 2: Securely retrieve or generate machine-unique encryption key
    final key = await SecurityService.getDatabaseEncryptionKey();

    // Defensive: SecurityService returns a SHA256 hex digest (64 chars,
    // [0-9a-f] only) — so interpolating it into the PRAGMA below is safe
    // from injection. But the audit flagged it, and rotating the key
    // derivation later (e.g. to argon2) would invalidate that assumption,
    // so we assert the shape here. If this ever throws, the key
    // derivation contract changed and someone must explicitly review
    // whether to re-key existing installs vs. switch to the `x'...'`
    // blob form (no string interpolation at all).
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      throw StateError(
        'SQLCipher key has unexpected shape '
        '(expected 64-char SHA256 hex). Key derivation contract changed?',
      );
    }

    return NativeDatabase.createInBackground(
      file,
      setup: (database) {
        // Apply the SQLCipher encryption key. Key shape asserted above
        // so the single-quote interpolation can't be abused.
        database.execute("PRAGMA key = '$key';");
        // PIR R-03: Enforce referential integrity (FK constraints)
        database.execute('PRAGMA foreign_keys = ON;');
        // WAL mode for better concurrent read/write performance
        database.execute('PRAGMA journal_mode = WAL;');
        // NORMAL sync is safe with WAL and significantly faster than FULL
        database.execute('PRAGMA synchronous = NORMAL;');
        // Multi-client fix: 60 seconds before "database is locked" error
        // (shift-close operations with JE + safe zeroing can exceed 30s under load)
        database.execute('PRAGMA busy_timeout = 60000;');
        // Increase cache to ~16MB for better read performance under load
        database.execute('PRAGMA cache_size = -16000;');
        // Keep WAL file manageable — checkpoint every 500 pages
        database.execute('PRAGMA wal_autocheckpoint = 500;');
        // Store temp tables in memory (faster sorts/indexes during heavy load)
        database.execute('PRAGMA temp_store = memory;');

      },
    );
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// POSTGRESQL CONNECTION
// ═══════════════════════════════════════════════════════════════════════════

/// Open a PostgreSQL database connection for multi-branch deployment.
///
/// Uses [PgDatabase] from drift_postgres as the Drift [QueryExecutor],
/// backed by the official Dart `postgres` package for TCP/IP connectivity.
///
/// NOTE: A PostgreSQL `strftime()` compatibility function is created in
/// AppDatabase.migration.beforeOpen to handle Drift's `currentDateAndTime`.
QueryExecutor openPostgresConnection(PostgresConfig config) {
  return PgDatabase(
    endpoint: pg.Endpoint(
      host: config.host,
      port: config.port,
      database: config.database,
      username: config.username,
      password: config.password,
    ),
    settings: pg.ConnectionSettings(
      sslMode: config.useSsl ? pg.SslMode.require : pg.SslMode.disable,
      connectTimeout: const Duration(seconds: 5),
      applicationName: 'URAL-ERP',
    ),
  ).interceptWith(_PgCompatInterceptor());
}

/// Drift QueryInterceptor that replaces SQLite-specific `strftime('%s','now')`
/// with PostgreSQL-compatible `EXTRACT(EPOCH FROM NOW())::bigint`.
///
/// Drift's `currentDateAndTime` generates `strftime('%s', 'now')` which
/// PostgreSQL doesn't support. This interceptor transparently patches ALL
/// SQL queries before execution — fixing CREATE TABLE defaults, INSERT
/// defaults, and any other SQL using this pattern.
class _PgCompatInterceptor extends QueryInterceptor {
  String _fixSql(String sql) => PgCompatSql.fixSql(sql);
  List<Object?> _fixArgs(List<Object?> args) => PgCompatSql.fixArgs(args);


  /// Log the first failing SQL inside a transaction — the one that poisons
  /// the pg session and turns the eventual COMMIT into opaque 25P02. The
  /// failed statement is appended to Documents/server_errors.log alongside
  /// the postPurchase handler's own error log, giving us SQL + args + cause.
  Future<void> _logFailed(
      String kind, String sql, List<Object?> args, Object e, StackTrace st) async {
    // Suppress benign "Operation was cancelled" entries. These are Drift's
    // own stream-query cancellations (CancellationException) that fire when
    // a watch() is replaced by a newer one or when the widget tree is
    // rebuilt — fully expected under load and never an actual failure.
    // Without this filter, server_errors.log fills with hundreds of
    // identical traces every minute (e.g. notifications watch on each NAV
    // rebuild), drowning out real errors and making triage harder.
    final msg = e.toString();
    if (msg.contains('Operation was cancelled') ||
        msg.contains('CancellationException')) {
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, 'server_errors.log');
      final buf = StringBuffer()
        ..writeln('─── PG FAIL ───────────────────────────────────────────────')
        ..writeln('[${DateTime.now().toIso8601String()}] $kind')
        ..writeln('sql: $sql')
        ..writeln('args: $args')
        ..writeln('error: $e')
        ..writeln('stack:')
        ..writeln(st.toString());
      await File(path).writeAsString(buf.toString(),
          mode: FileMode.append, flush: true);
    } catch (_) {/* diagnostic path — never throw */}
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final sql = _fixSql(statement);
    final a = _fixArgs(args);
    try {
      return await super.runCustom(executor, sql, a);
    } catch (e, st) {
      await _logFailed('runCustom', sql, a, e, st);
      rethrow;
    }
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final sql = _fixSql(statement);
    final a = _fixArgs(args);
    try {
      return await super.runInsert(executor, sql, a);
    } catch (e, st) {
      await _logFailed('runInsert', sql, a, e, st);
      rethrow;
    }
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final sql = _fixSql(statement);
    final a = _fixArgs(args);
    try {
      return await super.runUpdate(executor, sql, a);
    } catch (e, st) {
      await _logFailed('runUpdate', sql, a, e, st);
      rethrow;
    }
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final sql = _fixSql(statement);
    final a = _fixArgs(args);
    try {
      return await super.runDelete(executor, sql, a);
    } catch (e, st) {
      await _logFailed('runDelete', sql, a, e, st);
      rethrow;
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final sql = _fixSql(statement);
    final a = _fixArgs(args);
    try {
      return await super.runSelect(executor, sql, a);
    } catch (e, st) {
      await _logFailed('runSelect', sql, a, e, st);
      rethrow;
    }
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) async {
    final fixed = BatchedStatements(
      statements.statements.map(_fixSql).toList(),
      statements.arguments,
    );
    try {
      return await super.runBatched(executor, fixed);
    } catch (e, st) {
      await _logFailed('runBatched', fixed.statements.join(' ; '),
          fixed.arguments, e, st);
      rethrow;
    }
  }
}

/// Test PostgreSQL connectivity without creating a full Drift database.
/// Returns null on success, or an error message string on failure.
Future<String?> testPostgresConnection(PostgresConfig config) async {
  try {
    final conn = await pg.Connection.open(
      pg.Endpoint(
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.username,
        password: config.password,
      ),
      settings: pg.ConnectionSettings(
        sslMode: config.useSsl ? pg.SslMode.require : pg.SslMode.disable,
        connectTimeout: const Duration(seconds: 3),
        applicationName: 'URAL-ERP-Test',
      ),
    );
    // Quick verification query
    await conn.execute('SELECT 1');
    await conn.close();
    return null; // success
  } catch (e) {
    return e.toString();
  }
}

/// Create an in-memory database for testing purposes
QueryExecutor openTestConnection() {
  return NativeDatabase.memory();
}

/// Get the current database file path
Future<String> getDatabasePath() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return p.join(dbFolder.path, getDatabaseFileName());
}

/// Create a backup of the database
/// Returns the backup file path on success, null on failure
Future<String?> createDatabaseBackup() async {
  try {
    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) return null;

    final dbFolder = await getApplicationDocumentsDirectory();
    final backupFolder = Directory(p.join(dbFolder.path, 'backups'));

    if (!await backupFolder.exists()) {
      await backupFolder.create(recursive: true);
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final backupFileName = '${getDatabaseFileName()}_backup_$timestamp.db';
    final backupPath = p.join(backupFolder.path, backupFileName);

    await dbFile.copy(backupPath);

    // Keep only last 7 backups
    await _cleanOldBackups(backupFolder.path);

    return backupPath;
  } catch (e) {
    return null;
  }
}

/// Restore database from a backup file
Future<bool> restoreDatabaseBackup(String backupPath) async {
  try {
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) return false;

    final dbPath = await getDatabasePath();
    await backupFile.copy(dbPath);
    return true;
  } catch (e) {
    return false;
  }
}

/// List available backup files
Future<List<FileSystemEntity>> listBackups() async {
  try {
    final dbFolder = await getApplicationDocumentsDirectory();
    final backupFolder = Directory(p.join(dbFolder.path, 'backups'));

    if (!await backupFolder.exists()) return [];

    final files = await backupFolder
        .list()
        .where((f) => f.path.endsWith('.db'))
        .toList();

    // Sort by modification time (newest first)
    files.sort((a, b) {
      final aStat = FileStat.statSync(a.path);
      final bStat = FileStat.statSync(b.path);
      return bStat.modified.compareTo(aStat.modified);
    });

    return files;
  } catch (e) {
    return [];
  }
}

/// Clean old backups, keeping only the last 7
Future<void> _cleanOldBackups(String backupFolderPath) async {
  try {
    final backupFolder = Directory(backupFolderPath);
    final files = await backupFolder
        .list()
        .where((f) => f.path.endsWith('.db'))
        .toList();

    if (files.length <= 7) return;

    // Sort by modification time (oldest first)
    files.sort((a, b) {
      final aStat = FileStat.statSync(a.path);
      final bStat = FileStat.statSync(b.path);
      return aStat.modified.compareTo(bStat.modified);
    });

    // Delete oldest backups
    for (var i = 0; i < files.length - 7; i++) {
      await files[i].delete();
    }
  } catch (e) {
    // Silently fail
  }
}

/// Auto-backup on startup — creates a backup if the last one is older than 24 hours
/// Returns the backup path if created, null if skipped or failed
Future<String?> autoBackupOnStartup() async {
  try {
    final backups = await listBackups();

    if (backups.isNotEmpty) {
      final latestStat = FileStat.statSync(backups.first.path);
      final hoursSince = DateTime.now().difference(latestStat.modified).inHours;
      if (hoursSince < 24) return null; // Skip — recent backup exists
    }

    return await createDatabaseBackup();
  } catch (e) {
    return null;
  }
}

/// Export the latest backup to an external folder (e.g., USB drive)
/// Returns true on success
Future<bool> exportBackupToPath(String destinationFolder) async {
  try {
    final backups = await listBackups();
    if (backups.isEmpty) return false;

    final latestBackup = File(backups.first.path);
    final fileName = latestBackup.path.split(Platform.pathSeparator).last;
    final destFile = File(p.join(destinationFolder, fileName));

    await latestBackup.copy(destFile.path);
    return true;
  } catch (e) {
    return false;
  }
}

/// Get backup statistics (count, total size in bytes, last backup time)
Future<Map<String, dynamic>> getBackupStats() async {
  try {
    final backups = await listBackups();
    if (backups.isEmpty) {
      return {'count': 0, 'totalSize': 0, 'lastBackup': null};
    }

    int totalSize = 0;
    for (final backup in backups) {
      final stat = FileStat.statSync(backup.path);
      totalSize += stat.size;
    }

    final latestStat = FileStat.statSync(backups.first.path);

    return {
      'count': backups.length,
      'totalSize': totalSize,
      'lastBackup': latestStat.modified,
    };
  } catch (e) {
    return {'count': 0, 'totalSize': 0, 'lastBackup': null};
  }
}
