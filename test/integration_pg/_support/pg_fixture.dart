// Spec 029 / US1 — Postgres test fixture.
//
// Boots an `AppDatabase` over a real PostgreSQL connection (pointed at the
// DSN exposed by the runner script via env `PG_TEST_DSN`). Drift's own
// migration machinery creates the schema on first open. Between test files
// the public schema is dropped + recreated so each `*_pg_test.dart` starts
// from a clean slate.
//
// Lifecycle (per test file):
//   final fx = await bootPgTestSchema();
//   addTearDown(fx.tearDown);
//   // ... use fx.db ...
//
// If `PG_TEST_DSN` is unset, the helper throws with a hint pointing at
// `melos test:pg`. This makes accidental in-process invocation by the
// default `flutter test` runner loud rather than silent.

import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:picpos_erp/data/database/connection_io.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/pg_config.dart';

/// Opaque handle returned by [bootPgTestSchema]. Owns the [AppDatabase]
/// the test will use plus the teardown closure that closes the connection
/// and wipes the schema for the next file.
class PgTestFixture {
  PgTestFixture._({
    required this.db,
    required Future<void> Function() teardown,
  }) : _teardown = teardown;

  final AppDatabase db;
  final Future<void> Function() _teardown;

  Future<void> tearDown() => _teardown();
}

/// Read [PG_TEST_DSN] from the environment and parse it into a
/// [PostgresConfig]. Throws an actionable error when the variable is
/// missing — that means the developer ran the file with plain
/// `flutter test` instead of the dedicated `melos test:pg` orchestrator.
PostgresConfig _readDsnFromEnv() {
  final dsn = Platform.environment['PG_TEST_DSN'];
  if (dsn == null || dsn.isEmpty) {
    throw StateError(
      'PG_TEST_DSN is not set. Run integration_pg tests via '
      '`melos test:pg` (or `dart run scripts/run_pg_tests.dart`). '
      'Plain `flutter test` does NOT spawn Postgres and skips this suite.',
    );
  }
  final uri = Uri.parse(dsn);
  // Format: postgres://user:pass@host:port/dbname
  if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
    throw FormatException(
      'PG_TEST_DSN must use a postgres:// URI; got: $dsn',
    );
  }
  final userInfo = uri.userInfo.split(':');
  return PostgresConfig(
    host: uri.host,
    port: uri.port == 0 ? 5432 : uri.port,
    database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres',
    username: userInfo.isNotEmpty ? userInfo.first : 'postgres',
    password: userInfo.length > 1 ? userInfo[1] : '',
  );
}

/// Drop and recreate the `public` schema on the target database. This wipes
/// every Drift-managed table so the next [AppDatabase] open starts fresh.
/// Uses an admin connection separate from the AppDatabase pool — admin work
/// must not run inside Drift's connection lifecycle.
Future<void> _resetPublicSchema(PostgresConfig config) async {
  final endpoint = pg.Endpoint(
    host: config.host,
    port: config.port,
    database: config.database,
    username: config.username,
    password: config.password,
  );
  final conn = await pg.Connection.open(
    endpoint,
    settings: const pg.ConnectionSettings(
      sslMode: pg.SslMode.disable,
      connectTimeout: Duration(seconds: 10),
    ),
  );
  try {
    // CASCADE so dependent objects (sequences, constraints) drop cleanly.
    await conn.execute('DROP SCHEMA IF EXISTS public CASCADE');
    await conn.execute('CREATE SCHEMA public');
    // Restore the default grants that PostgreSQL expects on `public`.
    await conn.execute('GRANT ALL ON SCHEMA public TO public');
    await conn.execute(
      'GRANT ALL ON SCHEMA public TO ${config.username}',
    );
  } finally {
    await conn.close();
  }
}

/// A SECOND, independent connection to the schema [bootPgTestSchema] created
/// (no schema reset): lets a test run two real concurrent transactions.
AppDatabase openExtraPgConnection() => AppDatabase.withExecutor(
      openPostgresConnection(_readDsnFromEnv()),
      isPostgres: true,
    );

/// Open an [AppDatabase] connected to the test Postgres. Drift's migration
/// runs on the first `db.<table>` access — for explicit warm-up the caller
/// can `await db.customSelect('SELECT 1').get();`.
///
/// The returned [PgTestFixture]'s [PgTestFixture.tearDown] MUST be
/// registered with `addTearDown` (or called manually) so the connection
/// pool is drained between files.
Future<PgTestFixture> bootPgTestSchema() async {
  final config = _readDsnFromEnv();
  await _resetPublicSchema(config);

  final db = AppDatabase.withExecutor(
    openPostgresConnection(config),
    isPostgres: true,
  );

  // Drift's migration runs lazily on first DAO access. Tests should issue
  // a trivial DAO query at the top of `setUpAll` if they want migration
  // errors surfaced before the first real assertion.

  return PgTestFixture._(
    db: db,
    teardown: () async {
      await db.close();
    },
  );
}
