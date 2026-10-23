// Spec 130 — PG Schema Parity bug reproduction test.
//
// Reproduces the field-confirmed 2026-05-25 incident where the
// `category_station_mappings` table was missing on a PostgreSQL install,
// causing every POS sale to fail with:
//
//     SELECT ks.code FROM category_station_mappings csm
//     JOIN kitchen_stations ks ON ks.id = csm.station_id
//     WHERE csm.category_id = $1
//     → Severity.error 42P01: relation "category_station_mappings"
//       does not exist
//
// Followed by a cascade `25P02 current transaction is aborted` that
// rolled back the entire invoice.
//
// Test flow:
//   1. Boot the test PG schema (Drift creates all tables).
//   2. Drop `category_station_mappings` via an admin connection (simulating
//      the field-state where the table was missing).
//   3. Re-open the AppDatabase — Phase 2d (`_ensurePostgresSchemaParity`)
//      MUST detect the missing table and re-create it before any seeder
//      or DAO runs.
//   4. Execute the exact failing query from the stack trace — it must
//      succeed (returning an empty result, NOT 42P01).
//   5. Verify a `[PG-PARITY-HEAL]` breadcrumb was emitted.
//
// **PREREQUISITE**: `PG_TEST_DSN` env var must point at a Postgres
// instance the test can DROP/CREATE on. Run via `melos test:pg` or
// `dart run scripts/run_pg_tests.dart`. Plain `flutter test` skips this
// file (the fixture throws StateError when PG_TEST_DSN is absent).

@Tags(['pg'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/connection_io.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/pg_config.dart';

import '_support/pg_fixture.dart';

PostgresConfig _readDsnFromEnv() {
  final dsn = Platform.environment['PG_TEST_DSN']!;
  final uri = Uri.parse(dsn);
  final userInfo = uri.userInfo.split(':');
  return PostgresConfig(
    host: uri.host,
    port: uri.port == 0 ? 5432 : uri.port,
    database:
        uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres',
    username: userInfo.isNotEmpty ? userInfo.first : 'postgres',
    password: userInfo.length > 1 ? userInfo[1] : '',
  );
}

Future<void> _dropTableViaAdmin(
    PostgresConfig config, String tableName) async {
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
    await conn.execute('DROP TABLE IF EXISTS "$tableName" CASCADE');
  } finally {
    await conn.close();
  }
}

void main() {
  group('Spec 130 — bug reproduction: category_station_mappings missing', () {
    late PgTestFixture fx;

    setUpAll(() async {
      DiagnosticLogger.enableTestMode();

      // Boot once to let Drift create the full schema (this exercises
      // `_createAllForPostgres()` + `_ensurePostgresSyncInfrastructure()`
      // + `_ensurePostgresSchemaParity()` in OK-state).
      fx = await bootPgTestSchema();
      // Warm up so migrations finish.
      await fx.db.customSelect('SELECT 1').get();
      // Close so we can manipulate the schema below.
      await fx.tearDown();
    });

    test('Phase 2d self-heals a dropped category_station_mappings and the '
        'original failing query succeeds', () async {
      final config = _readDsnFromEnv();

      // Simulate the field bug: drop the table from a previously-created
      // schema.
      await _dropTableViaAdmin(config, 'category_station_mappings');

      // Re-open the AppDatabase — runBeforeOpen → Phase 2d should re-create
      // the missing table BEFORE any DAO query touches it.
      DiagnosticLogger.enableTestMode(); // reset capture
      final db = AppDatabase.withExecutor(
        openPostgresConnection(config),
        isPostgres: true,
      );
      addTearDown(() async => db.close());
      // Force Drift to run beforeOpen by issuing any read.
      await db.customSelect('SELECT 1').get();

      // 1. Table re-created.
      final tableExists = await db.customSelect(
        "SELECT 1 AS x FROM information_schema.tables "
        "WHERE table_schema = 'public' "
        "AND table_name = 'category_station_mappings' LIMIT 1",
      ).get();
      expect(tableExists, isNotEmpty,
          reason: 'category_station_mappings should be re-created by '
              'the parity pass after being dropped manually.');

      // 2. The exact failing query from the field stack trace succeeds
      //    (returning no rows is fine — the point is no 42P01).
      final query = await db.customSelect(
        'SELECT ks.code FROM category_station_mappings csm '
        'JOIN kitchen_stations ks ON ks.id = csm.station_id '
        'WHERE csm.category_id = 9 LIMIT 1',
      ).get();
      expect(query, isA<List<dynamic>>(),
          reason: 'Original failing query must execute without 42P01.');

      // 3. A [PG-PARITY-HEAL] breadcrumb was emitted for the table.
      final heals = DiagnosticLogger.testLog
          .where((l) => l.contains('PG-PARITY-HEAL') &&
              l.contains('category_station_mappings'))
          .toList();
      expect(heals, isNotEmpty,
          reason: 'PG-PARITY-HEAL breadcrumb must record the table '
              'creation for ops visibility (FR-005).');
    });
  });
}
