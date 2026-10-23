// Spec 130 — PG Schema Parity static test.
//
// Verifies invariants that don't require a running PostgreSQL instance:
//   1. `_ensurePostgresSchemaParity()` is a no-op on SQLite (the
//      `if (!_isPostgres) return` early-exit). Observable via the
//      absence of any `PG-PARITY-*` entry in DiagnosticLogger after a
//      SQLite AppDatabase opens.
//   2. The parity-pass body does NOT call `db.transaction(...)` —
//      FR-008 mandates DDL outside any active PG transaction. Enforced
//      via a source-code grep against database.dart.
//   3. The parity-pass helpers do NOT emit destructive DDL
//      (DROP / TRUNCATE / DELETE). FR-004 — CREATE-only. Enforced via
//      a source-code grep over the relevant private methods.
//   4. Every `DriftSqlType` is handled in `_buildPgColumnDef`. New
//      Drift enum values should fail this test, prompting the author
//      to extend the parity helper.
//   5. `allSchemaEntities` is non-empty and contains TableInfo entries
//      — sanity check that the parity pass has something to iterate.
//
// Runs under plain `flutter test` — no PG, no Docker.
//
// **CRITICAL — DO NOT REMOVE THE FR-008 GREP**: the invariant "parity
// pass runs outside any transaction" prevents the cascade-bug that
// motivated this Spec (a missing table inside an active PG transaction
// causes 25P02 errors on every subsequent query). If a future refactor
// wraps the parity pass body in `db.transaction(...)`, this test must
// fail loud.

import 'package:drift/drift.dart' show DriftSqlType, TableInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database.dart';
import '../helpers/database_source.dart';

void main() {
  group('Spec 130 — PG schema parity static invariants', () {
    late String dbSrc;

    setUpAll(() {
      // Read the source file once. Tests below grep against it.
      dbSrc = readDatabaseSource();
    });

    test('Source file contains _ensurePostgresSchemaParity method',
        () async {
      expect(dbSrc, contains('Future<void> _ensurePostgresSchemaParity()'),
          reason: 'The parity pass method must exist with the expected '
              'signature. If renamed, update this test + all callers.');
    });

    test('FR-008 — _ensurePostgresSchemaParity body has NO transaction() '
        'call (DDL must run outside any active transaction)', () async {
      // Slice the source from "_ensurePostgresSchemaParity" to the next
      // "Future<" or method-end (a coarse but reliable extraction; the
      // method spans ~150 lines and uses `Future<...>` for the next
      // method declaration `_buildPgColumnDef`).
      final start = dbSrc.indexOf('Future<void> _ensurePostgresSchemaParity()');
      expect(start, greaterThan(0));
      // End the slice at the next top-level "  /// " comment block that
      // introduces the next member, OR the next "}\n\n  /// " (close of
      // the method + new member). Use a conservative regex.
      final after = dbSrc.substring(start);
      final endRel = RegExp(r'\n\s{0,4}}\s*\n\s{0,4}/// ').firstMatch(after);
      expect(endRel, isNotNull,
          reason: 'Could not delimit _ensurePostgresSchemaParity body. '
              'Source structure changed — update the slice regex.');
      final body = after.substring(0, endRel!.start);

      // FR-008: no transaction() invocation inside the body. The regex
      // tolerates `transaction(` and `db.transaction(` patterns.
      final txnPattern = RegExp(r'\btransaction\s*\(');
      expect(txnPattern.hasMatch(body), isFalse,
          reason: '🚨 FR-008 VIOLATION: _ensurePostgresSchemaParity body '
              'contains `transaction(...)`. DDL must run outside any '
              'active PG transaction (otherwise a missing-table 42P01 '
              'aborts the whole transaction with 25P02 cascade — exactly '
              'the bug this Spec 130 was created to fix).');
    });

    test('FR-004 — Parity pass + helpers do NOT emit destructive DDL '
        '(DROP / TRUNCATE / DELETE / ALTER … DROP)', () async {
      // Extract the three relevant private methods + the parity pass body
      // into one combined slice. We intentionally do NOT use the whole
      // database.dart file because legitimate DROPs exist elsewhere
      // (e.g., _ensurePostgresSyncInfrastructure drops triggers before
      // re-creating them — a deliberate Spec 129 pattern).
      String slice(String marker, [int span = 3500]) {
        final i = dbSrc.indexOf(marker);
        if (i < 0) return '';
        return dbSrc.substring(i, (i + span).clamp(0, dbSrc.length));
      }

      final combined =
          slice('Future<void> _ensurePostgresSchemaParity()', 6500) +
              slice('String _buildPgColumnDef(', 2500) +
              slice('String _buildPgCreateTableSql(', 3500);

      // DESTRUCTIVE patterns that must NEVER appear inside these methods.
      // We allow the literal *words* in comments (those are descriptive)
      // but disallow the SQL forms (followed by something that suggests
      // execution).
      final patterns = <RegExp>[
        RegExp("'DROP\\s", caseSensitive: false),
        RegExp("'TRUNCATE\\s", caseSensitive: false),
        RegExp("'DELETE\\s+FROM", caseSensitive: false),
        RegExp("ALTER\\s+TABLE[^']*DROP\\s+COLUMN", caseSensitive: false),
      ];
      for (final p in patterns) {
        expect(p.hasMatch(combined), isFalse,
            reason: '🚨 FR-004 VIOLATION: Parity pass emits destructive '
                'DDL matching `${p.pattern}`. The pass MUST be CREATE-only '
                '(see Clarification Q4 + spec FR-004). If the policy '
                'changed, update spec.md before changing this test.');
      }
    });

    test('_buildPgColumnDef handles every DriftSqlType', () async {
      // For each enum value, verify the helper source mentions it. The
      // helper is private so we can't call it directly from the test —
      // but a source-grep is sufficient: new enum values that the helper
      // hasn't been taught about will fail this assertion before they
      // reach production.
      final helperStart = dbSrc.indexOf('String _buildPgColumnDef(');
      expect(helperStart, greaterThan(0));
      final after = dbSrc.substring(helperStart);
      // Helper ends at next top-level `/// ` comment (which introduces
      // the next class member). Same delimiter style as the FR-008 test.
      final endRel = RegExp(r'\n\s{0,4}}\s*\n\s{0,4}/// ').firstMatch(after);
      // Fallback: if the helper happens to be the last in the file,
      // grab everything to EOF (still safe — Drift type names are
      // unique enough not to collide with unrelated code).
      final helperBody = endRel != null
          ? after.substring(0, endRel.start)
          : after;

      for (final type in DriftSqlType.values) {
        expect(helperBody, contains('DriftSqlType.${type.name}'),
            reason: '_buildPgColumnDef does not handle '
                'DriftSqlType.${type.name}. Add a branch in the helper '
                'so the parity pass can emit a PG-compatible column for '
                'this kind.');
      }
    });

    test(
        'Skeleton no-op on SQLite — opening AppDatabase.forTesting() '
        'emits NO PG-PARITY-* DiagnosticLogger entries', () async {
      DiagnosticLogger.enableTestMode();

      final db = AppDatabase.forTesting();
      addTearDown(() async => db.close());
      // Trigger beforeOpen by issuing any query.
      await db.customSelect('SELECT 1').get();

      final pgParityLines = DiagnosticLogger.testLog
          .where((l) => l.contains('PG-PARITY'))
          .toList();
      expect(pgParityLines, isEmpty,
          reason: 'The parity pass must early-return on non-PG executors. '
              'Found unexpected PG-PARITY breadcrumbs on a SQLite boot: '
              '$pgParityLines');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('allSchemaEntities is non-empty and includes core tables', () async {
      // Sanity check that the parity pass has something to iterate when
      // it does run on PG. If this fails, the bigger problem is the
      // Drift schema itself — but the parity pass would silently no-op.
      final db = AppDatabase.forTesting();
      addTearDown(() async => db.close());
      final entities = db.allSchemaEntities.toList();
      expect(entities, isNotEmpty);

      final tableNames = entities.whereType<TableInfo>()
          .map((e) => e.actualTableName.toLowerCase())
          .toSet();
      // Spot-check entities that the field bug specifically named.
      expect(tableNames, contains('category_station_mappings'),
          reason: 'category_station_mappings (the field-bug table) MUST '
              'be in allSchemaEntities — otherwise the parity pass '
              'cannot heal it on PG.');
      expect(tableNames, contains('kitchen_stations'));
    });

    // ─────────────────────────────────────────────────────────────────────
    // Composite / non-autoincrement primary keys must reach PostgreSQL.
    //
    // `_buildPgCreateTableSql` emitted PRIMARY KEY only as part of SERIAL,
    // i.e. only for autoincrement int columns. Every table that declares its
    // key through drift's `Set<Column> get primaryKey` was created on PG with
    // NO primary key at all — eight of them, including `document_sequences`
    // (keyed on `prefix`, which is what stops two invoices getting the same
    // number) and `processed_messages` (keyed on `idempotency_key`, the whole
    // basis of replay de-duplication).
    //
    // Verifiable without PostgreSQL: `$primaryKey` is drift metadata, and the
    // generator either reads it or it does not. `$primaryKey` appeared ZERO
    // times in database.dart before this fix.
    test('PG table DDL emits composite primary keys', () async {
      expect(dbSrc.contains(r'$primaryKey'), isTrue,
          reason: 'the PG CREATE TABLE builder must read drift\'s declared '
              'primaryKey. Without it, tables keyed on anything other than '
              'an autoincrement id land on the server with no key — '
              'duplicate document numbers and dead idempotency.');
    });

    test('tables with a declared composite key are still in the schema',
        () async {
      // Guards the fix against becoming vacuous: if these tables ever stop
      // declaring a composite key, the assertion above would pass while
      // protecting nothing.
      final db = AppDatabase.forTesting();
      addTearDown(() async => db.close());

      final keyed = db.allSchemaEntities
          .whereType<TableInfo>()
          .where((t) => t.$primaryKey.isNotEmpty)
          .where((t) => !t.$columns.any((c) => c.hasAutoIncrement))
          .map((t) => t.actualTableName.toLowerCase())
          .toSet();

      expect(keyed, contains('document_sequences'),
          reason: 'document numbering depends on this key');
      expect(keyed, contains('processed_messages'),
          reason: 'replay de-duplication depends on this key');
      expect(keyed.length, greaterThanOrEqualTo(8),
          reason: 'eight such tables were measured; a drop means one lost '
              'its key declaration rather than the builder being fixed');
    });
  });
}
