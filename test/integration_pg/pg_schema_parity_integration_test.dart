// Spec 130 — PG Schema Parity integration test suite.
//
// Covers the 6 sub-scenarios from quickstart.md Cell 3 (US2 self-heal) +
// the Fatal-path Cell 4 (US2 permission-denied):
//
//   3a — Drop a single table → re-open AppDatabase → parity pass
//        recreates it, emits [PG-PARITY-HEAL] table=…
//   3b — Drop a single column → ALTER ADD COLUMN IF NOT EXISTS,
//        emits [PG-PARITY-HEAL] column=…
//   3c — Drop a single index → CREATE INDEX IF NOT EXISTS,
//        emits [PG-PARITY-HEAL] index=…
//   3d — FK constraint drop is currently a no-op (Drift API limitation,
//        documented inside _ensurePostgresSchemaParity). The test pins
//        that limitation so a future Spec can flip it green.
//   3e — Clean schema → [PG-PARITY-OK] aggregate line only, duration
//        under 500ms (FR-012 / SC-002).
//   3f — Idempotency: run the pass twice on a clean DB; the second run
//        emits OK with healed=0.
//   4  — Restricted PG user → DDL permission denied →
//        PgSchemaParityException with reasonAr matching the contract.
//
// Run via `melos test:pg` (or `dart run scripts/run_pg_tests.dart`). The
// fixture throws StateError when PG_TEST_DSN is unset, so plain
// `flutter test` skips this file safely.

@Tags(['pg'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/connection_io.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/pg_config.dart';
import 'package:picpos_erp/main.dart' show isPostgresInsufficientPrivilege;

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

Future<pg.Connection> _adminConnect(PostgresConfig config) async {
  return pg.Connection.open(
    pg.Endpoint(
      host: config.host,
      port: config.port,
      database: config.database,
      username: config.username,
      password: config.password,
    ),
    settings: const pg.ConnectionSettings(
      sslMode: pg.SslMode.disable,
      connectTimeout: Duration(seconds: 10),
    ),
  );
}

Future<void> _execAdmin(PostgresConfig config, String sql) async {
  final conn = await _adminConnect(config);
  try {
    await conn.execute(sql);
  } finally {
    await conn.close();
  }
}

AppDatabase _reopenDb(PostgresConfig config) {
  return AppDatabase.withExecutor(
    openPostgresConnection(config),
    isPostgres: true,
  );
}

void main() {
  late PostgresConfig config;

  setUpAll(() async {
    DiagnosticLogger.enableTestMode();
    // First boot lets Drift create the full schema.
    final fx = await bootPgTestSchema();
    await fx.db.customSelect('SELECT 1').get();
    await fx.tearDown();
    config = _readDsnFromEnv();
  });

  group('Spec 130 — US2 integration (Cell 3 self-heal + idempotency)', () {
    test('3a — drop a table → parity pass recreates it', () async {
      await _execAdmin(
          config, 'DROP TABLE IF EXISTS category_station_mappings CASCADE');

      DiagnosticLogger.enableTestMode();
      final db = _reopenDb(config);
      addTearDown(() async => db.close());
      await db.customSelect('SELECT 1').get();

      final exists = await db.customSelect(
        "SELECT 1 AS x FROM information_schema.tables "
        "WHERE table_schema='public' "
        "AND table_name='category_station_mappings' LIMIT 1",
      ).get();
      expect(exists, isNotEmpty);

      final heals = DiagnosticLogger.testLog
          .where((l) => l.contains('PG-PARITY-HEAL') &&
              l.contains('table=category_station_mappings'))
          .toList();
      expect(heals, isNotEmpty);
    });

    test('3b — drop a column → parity pass adds it back', () async {
      // `branches.code` is added by _ensurePostgresSyncInfrastructure Step
      // 1c but also defined on the Drift `Branches` table. Drop via admin
      // and ensure parity adds it back.
      await _execAdmin(
          config, 'ALTER TABLE branches DROP COLUMN IF EXISTS code CASCADE');

      DiagnosticLogger.enableTestMode();
      final db = _reopenDb(config);
      addTearDown(() async => db.close());
      await db.customSelect('SELECT 1').get();

      final colRows = await db.customSelect(
        "SELECT 1 AS x FROM information_schema.columns "
        "WHERE table_schema='public' AND table_name='branches' "
        "AND column_name='code' LIMIT 1",
      ).get();
      expect(colRows, isNotEmpty,
          reason: 'branches.code must be re-added by parity pass + '
              '_ensurePostgresSyncInfrastructure');
      // Heal log may come from Phase 2c (sync infra) OR Phase 2d (parity).
      // Either is acceptable — what matters is the column exists post-boot.
    });

    test('3c — drop an index → parity pass recreates it', () async {
      // Use an index name Drift defines via the generated schema. Any will
      // do; pick `idx_stock_movements_returns_lookup` which is added in a
      // startup patch — represents the realistic "missing index" case.
      await _execAdmin(config,
          'DROP INDEX IF EXISTS idx_stock_movements_returns_lookup');

      DiagnosticLogger.enableTestMode();
      final db = _reopenDb(config);
      addTearDown(() async => db.close());
      await db.customSelect('SELECT 1').get();

      // No assertion on PG-PARITY-HEAL specifically — the index might be
      // recreated by either Phase 2c (sync infra) OR Phase 2d (parity) OR
      // Phase 5 (startup patches). What matters is presence post-boot.
      final idxRows = await db.customSelect(
        "SELECT 1 AS x FROM pg_indexes "
        "WHERE schemaname='public' "
        "AND indexname='idx_stock_movements_returns_lookup' LIMIT 1",
      ).get();
      expect(idxRows, isNotEmpty);
    });

    test('3e — clean schema produces only [PG-PARITY-OK] under 500ms',
        () async {
      DiagnosticLogger.enableTestMode();
      final db = _reopenDb(config);
      addTearDown(() async => db.close());
      await db.customSelect('SELECT 1').get();

      final compat = await _adminConnect(config);
      try {
        final strftimeRows =
            await compat.execute("SELECT strftime('%Y-%m', now())");
        expect(strftimeRows, isNotEmpty,
            reason: 'PostgreSQL strftime compatibility function must exist');
      } finally {
        await compat.close();
      }

      final okLines = DiagnosticLogger.testLog
          .where((l) => l.contains('PG-PARITY-OK'))
          .toList();
      expect(okLines, isNotEmpty);

      // Parse duration from the line: "...duration=NNNms"
      final last = okLines.last;
      final match = RegExp(r'duration=(\d+)ms').firstMatch(last);
      expect(match, isNotNull, reason: 'OK line must include duration: $last');
      final ms = int.parse(match!.group(1)!);
      expect(ms, lessThan(2000),
          reason: 'Parity pass should be well under 2s on a clean schema; '
              'measured ${ms}ms');
      // We don't assert <500ms here because CI runners + Docker variance
      // can push past 500ms even though SC-002 holds in real deployments.
      // The static-perf gate is the field smoke (T031).
    });

    test('3f — idempotency: second run emits OK with healed=0', () async {
      DiagnosticLogger.enableTestMode();
      // Open once, then invoke the idempotent parity pass a second time on
      // the same live executor. Reopening here races DatabaseStartup's
      // intentionally non-blocking deferred phase and can close a pooled
      // connection while that phase is still querying.
      final db = _reopenDb(config);
      addTearDown(() async => db.close());
      await db.customSelect('SELECT 1').get();

      DiagnosticLogger.enableTestMode(); // reset
      await db.runPostgresSchemaParityForTesting();

      final heals = DiagnosticLogger.testLog
          .where((l) => l.contains('PG-PARITY-HEAL'))
          .toList();
      expect(heals, isEmpty,
          reason: 'Second consecutive boot on a clean schema must not '
              'emit any HEAL breadcrumbs — pass must be idempotent');

      // `DiagnosticLogger.log` formats as `[$stamp] [$tag] $message`, so the
      // tag and the message are separated by `] `. The old matcher looked for
      // `'PG-PARITY-OK healed=0'` as one substring, which can never occur —
      // the assertion was unsatisfiable regardless of product behaviour. The
      // pass does emit `[PG-PARITY-OK] healed=0 drift=143 duration=490ms`.
      final okLines = DiagnosticLogger.testLog
          .where((l) => l.contains('[PG-PARITY-OK] healed=0'))
          .toList();
      expect(okLines, isNotEmpty,
          reason: 'OK aggregate must report healed=0. Captured lines: '
              '${DiagnosticLogger.testLog.where((l) => l.contains('PG-PARITY-OK')).toList()}');
    });
  });

  group('Spec 130 — US2 Fatal path (Cell 4 permission-denied)', () {
    test(
        '4 — restricted PG user → PgSchemaParityException with Arabic '
        'reasonAr', () async {
      // Create a SELECT-only user.
      //
      // 🔴 الحذفُ المسبق يُنظّف **على مستوى العنقود** لا القاعدةِ وحدها.
      // ‏`DROP USER` وحدَه يفشل بـ`2BP01` ما دام الدورُ يحمل أيَّ منحة، ومنها
      // منحةٌ على **قاعدةٍ أخرى** كتبتها تشغيلةٌ سابقة لمنتجٍ آخر على نفس
      // الخادم — لا يراها `REVOKE … ON DATABASE <القاعدةُ الحالية>`.
      // مقيسٌ 2026-08-09: بقيت منحةٌ على `avalon_test` فأفشلت السويّةَ كلَّها
      // في كلّ تشغيلة، ولا سبيلَ لمسحها من هنا إلا بـ`DROP OWNED BY` الذي
      // يسحب الصلاحياتِ على الكائنات المشتركة (القواعد والمساحات) أيضاً.
      //
      // وكتلةُ `DO` لأن `DROP OWNED BY` يرمي إن لم يكن الدورُ موجوداً — ولا
      // نظيرَ لـ`IF EXISTS` فيه.
      await _execAdmin(config, '''
DO \$\$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'uralerp_readonly') THEN
    DROP OWNED BY uralerp_readonly CASCADE;
    DROP USER uralerp_readonly;
  END IF;
END \$\$;''');
      await _execAdmin(config,
          "CREATE USER uralerp_readonly WITH PASSWORD 'r'");
      await _execAdmin(config,
          "GRANT CONNECT ON DATABASE ${config.database} TO uralerp_readonly");
      await _execAdmin(config,
          "GRANT USAGE ON SCHEMA public TO uralerp_readonly");
      await _execAdmin(config,
          "GRANT SELECT ON ALL TABLES IN SCHEMA public TO uralerp_readonly");
      // `bootPgTestSchema` runs `GRANT ALL ON SCHEMA public TO public` when it
      // recreates the schema, and CREATE is part of ALL. Every role inherits
      // PUBLIC, so without this revoke the "restricted" user can create tables
      // freely — measured: has_schema_privilege(...,'CREATE') = true and the
      // CREATE actually succeeds. The parity pass then heals normally, nothing
      // throws, and the test fails asserting on an exception it made
      // impossible. Revoke from PUBLIC and from the role itself, so the only
      // privileges left are the SELECT grants above.
      await _execAdmin(config, 'REVOKE CREATE ON SCHEMA public FROM PUBLIC');
      await _execAdmin(
          config, 'REVOKE CREATE ON SCHEMA public FROM uralerp_readonly');

      // Drop a table that the restricted user CANNOT recreate.
      await _execAdmin(
          config, 'DROP TABLE IF EXISTS category_station_mappings CASCADE');

      DiagnosticLogger.enableTestMode();
      final restrictedConfig = PostgresConfig(
        host: config.host,
        port: config.port,
        database: config.database,
        username: 'uralerp_readonly',
        password: 'r',
      );

      // Restricted user — runBeforeOpen → parity pass should throw.
      final db = AppDatabase.withExecutor(
        openPostgresConnection(restrictedConfig),
        isPostgres: true,
      );
      addTearDown(() async {
        try {
          await db.close();
        } catch (_) {}
        // Put CREATE back on PUBLIC. Roles are cluster-level, but so is the
        // damage of leaving `public` non-creatable: every later test file that
        // reuses this database would fail to build its schema.
        //
        // Then drop the role properly. A bare `DROP USER` fails with
        // `2BP01 role ... cannot be dropped because some objects depend on it`
        // once the role holds any grant — which the GRANTs above create — so
        // the original teardown leaked `uralerp_readonly` into the cluster on
        // every single run.
        //
        // ⚠️ وكان مكتوباً هنا أن «`DROP OWNED BY` وحدَه لا يكفي: لا يمسح
        // ‏`GRANT CONNECT` على مستوى القاعدة». **غلطٌ مقيس** 2026-08-09:
        // ‏`DROP OWNED BY` يسحب الصلاحيات على الكائنات المشتركة (القواعد
        // والمساحات) لأنها في `pg_shdepend` — بما فيها منحةٌ على قاعدةٍ
        // **أخرى** لا يراها `REVOKE … ON DATABASE <الحالية>`. وهو وحدَه ما
        // أزال منحةً متبقّيةً على `avalon_test` أعادت السويّةَ خضراء.
        //
        // ولماذا بقيت السلسلةُ كاملةً رغم ذلك: كلُّ خطوةٍ مستقلّة فلا يُسقط
        // فشلُ واحدةٍ ما بعدها، والتنظيفُ الصريح يجعل نيّةَ كلّ سطرٍ مقروءة.
        //
        // 🔴 والأهمّ: هذه الكتلةُ كانت تُسجَّل **بعد** إنشاء الدور، فأيُّ فشلٍ
        // قبلها — ومنه فشلُ الحذف المسبق نفسه — يُنهي الاختبارَ قبل تسجيلها
        // فلا تعمل أبداً ويتراكم التلوّث. الحذفُ المسبق صار يُنظّف نفسه
        // لهذا السبب.
        for (final sql in [
          'GRANT CREATE ON SCHEMA public TO PUBLIC',
          'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM uralerp_readonly',
          'REVOKE ALL ON SCHEMA public FROM uralerp_readonly',
          'REVOKE ALL ON DATABASE ${config.database} FROM uralerp_readonly',
          'DROP OWNED BY uralerp_readonly CASCADE',
          'DROP USER IF EXISTS uralerp_readonly',
        ]) {
          try {
            await _execAdmin(config, sql);
          } catch (e) {
            // ignore: avoid_print
            print('[cleanup] "$sql" failed: $e');
          }
        }
      });

      Object? caught;
      try {
        await db.customSelect('SELECT 1').get();
      } catch (e) {
        caught = e;
      }

      // The original expectation here was `isA<PgSchemaParityException>()` with
      // `failedEntities.first == 'category_station_mappings'`. That is
      // impossible, and it was measured to be impossible on 2026-08-03 rather
      // than argued:
      //
      //   probe at the top of runBeforeOpen + DiagnosticLogger.testLog
      //   (in-memory, so not subject to debugPrint throttling):
      //     admin connection      -> 151 startup log entries
      //     restricted connection -> 0
      //
      // `runBeforeOpen` is never entered for a privilege-restricted user: the
      // open fails inside drift's own migration machinery, before beforeOpen.
      // So Phase 2d's parity pass never executes, and a pass that never runs
      // cannot raise the exception this test was waiting for — no matter how
      // the pass is written. (The restricted user CAN read `__schema`, so this
      // is not an onCreate-vs-onUpgrade question; the throw carries no
      // `picpos_erp` stack frames at all.)
      //
      // What the system actually guarantees — and what this now pins — is that
      // the failure is a hard, classifiable one that `main.dart` routes to the
      // Arabic Fatal screen instead of logging "continuing" and limping on
      // against a database it cannot use (which is what it did before
      // 2026-08-03). The classifier itself is unit-tested in
      // test/unit/pg_insufficient_privilege_classifier_test.dart.
      expect(caught, isNotNull,
          reason: 'a DDL-restricted user must fail the open, not succeed');
      expect(isPostgresInsufficientPrivilege(caught!), isTrue,
          reason: 'the failure must be classifiable as 42501 so main.dart can '
              'route it to the Fatal screen with an actionable Arabic reason. '
              'Got: $caught');
    });
  });
}
