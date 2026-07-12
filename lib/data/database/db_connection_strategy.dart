import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database.dart';
import 'pg_config.dart';
import 'connection_io.dart' show openPostgresConnection, testPostgresConnection;

/// Result of [DbConnectionStrategy.open].
///
/// Callers receive a fully-initialised [AppDatabase] together with metadata
/// about which backend is actually in use (useful for logging and health-check
/// screens).
class DbConnectionResult {
  /// The opened database instance ready for use.
  final AppDatabase db;

  /// The backend that is actually connected (may differ from the configured
  /// mode when an offline fallback has occurred).
  final DatabaseMode activeMode;

  /// True when PostgreSQL was configured but unreachable, so the app fell back
  /// to the local SQLite database.
  final bool isOfflineFallback;

  const DbConnectionResult({
    required this.db,
    required this.activeMode,
    required this.isOfflineFallback,
  });
}

/// Centralises the decision of which [QueryExecutor] to open.
///
/// ## Deployment modes
///
/// | Mode       | Condition                              | Backend  |
/// |------------|----------------------------------------|----------|
/// | **sqlite** | Default / client device                | SQLite   |
/// | **postgres** (provisioned) | Server, reachable      | PG       |
/// | **postgres** (provisioned, offline) | Server, unreachable | SQLite fallback |
/// | **postgres** (not yet provisioned) | First install       | SQLite   |
/// | **client**  | `NetworkService.isClient == true`      | SQLite   |
///
/// ## Migration path (SQLite → PostgreSQL)
///
/// 1. Deploy a PostgreSQL 14+ instance accessible from the server machine.
/// 2. Create the database and user:
///    ```sql
///    CREATE USER uralcash WITH PASSWORD 'strong_password';
///    CREATE DATABASE uralcash OWNER uralcash;
///    GRANT ALL PRIVILEGES ON DATABASE uralcash TO uralcash;
///    ```
/// 3. In the ERP settings screen, enter the PG host/port/credentials and
///    click **Test Connection → Link**.  The app:
///    a. Verifies connectivity (`testPostgresConnection`).
///    b. Runs all Drift migrations against PG (`AppDatabase.withExecutor`).
///    c. Seeds the Chart of Accounts and admin user.
///    d. Sets `pg_provisioned_ok = true` in SharedPreferences.
/// 4. Restart the app — `DbConnectionStrategy.open()` routes to PG.
///
/// ## Offline fallback
///
/// If PG becomes unreachable on a later startup, the strategy falls back
/// silently to the **local SQLite file** and sets
/// `PostgresConfig.isOfflineFallback = true`.  The `OfflineFallbackSyncService`
/// watches this flag and copies new local rows back to PG when connectivity
/// is restored.
///
/// ## Usage
///
/// ```dart
/// final result = await DbConnectionStrategy.open(isClient: isClientMode);
/// sharedDb = result.db;
/// if (result.isOfflineFallback) {
///   debugPrint('Running on local SQLite (PG unreachable)');
/// }
/// ```
class DbConnectionStrategy {
  // Private constructor — static API only.
  DbConnectionStrategy._();

  /// Open the database using the configured [DatabaseMode].
  ///
  /// [isClient] — pass `true` when the device is running in branch-client
  ///   mode (HTTP-sync to server).  Client devices always use the local SQLite
  ///   cache regardless of the stored [DatabaseMode].
  ///
  /// On non-IO platforms (e.g. Web stub) this returns a no-op stub db.
  static Future<DbConnectionResult> open({bool isClient = false}) async {
    // ── Client mode: always local SQLite ─────────────────────────────────
    if (isClient) {
      if (PostgresConfig.isOfflineFallback) {
        await PostgresConfig.setOfflineFallback(false);
        debugPrint('[DbStrategy] 📱 Client mode — cleared stale PG offline-fallback flag');
      }
      debugPrint('[DbStrategy] 📱 Client mode — using local SQLite + HTTP sync');
      return DbConnectionResult(
        db: AppDatabase(),
        activeMode: DatabaseMode.sqlite,
        isOfflineFallback: false,
      );
    }

    final dbMode = await PostgresConfig.loadMode();

    // ── SQLite mode ───────────────────────────────────────────────────────
    if (dbMode == DatabaseMode.sqlite) {
      debugPrint('[DbStrategy] 💾 SQLite mode');
      return DbConnectionResult(
        db: AppDatabase(),
        activeMode: DatabaseMode.sqlite,
        isOfflineFallback: false,
      );
    }

    // ── PostgreSQL mode ───────────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final pgProvisioned = prefs.getBool('pg_provisioned_ok') ?? false;

    if (!pgProvisioned) {
      debugPrint('[DbStrategy] 📂 PG mode saved but not yet provisioned — using SQLite. '
          'Complete the PG link flow from Settings → Network Mode.');
      return DbConnectionResult(
        db: AppDatabase(),
        activeMode: DatabaseMode.sqlite,
        isOfflineFallback: false,
      );
    }

    // PG provisioned — test reachability (short timeout)
    final pgConfig = await PostgresConfig.load();
    final error = await testPostgresConnection(pgConfig);
    if (error == null) {
      // Server reachable
      debugPrint('[DbStrategy] ✅ PostgreSQL connected: ${pgConfig.displayString}');
      await PostgresConfig.setOfflineFallback(false);
      return DbConnectionResult(
        db: AppDatabase.withExecutor(
          openPostgresConnection(pgConfig),
          isPostgres: true,
        ),
        activeMode: DatabaseMode.postgres,
        isOfflineFallback: false,
      );
    }

    // Server unreachable → offline fallback
    debugPrint('[DbStrategy] ⚠️ PostgreSQL unreachable ($error) — offline fallback to SQLite');
    await PostgresConfig.setOfflineFallback(true);
    return DbConnectionResult(
      db: AppDatabase(),
      activeMode: DatabaseMode.sqlite,
      isOfflineFallback: true,
    );
  }

  /// Mark PostgreSQL as provisioned.
  ///
  /// Call this after a successful Link-to-PG flow so that the next
  /// [open] call connects directly to PG.
  static Future<void> markProvisioned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pg_provisioned_ok', true);
  }

  /// Clear the provisioned flag.
  ///
  /// Forces the next [open] call to use SQLite, regardless of [DatabaseMode].
  /// Useful as an emergency escape hatch when PG is permanently broken.
  static Future<void> clearProvisioned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pg_provisioned_ok');
    await PostgresConfig.setOfflineFallback(false);
  }
}
