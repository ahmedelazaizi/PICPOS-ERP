// ═══════════════════════════════════════════════════════════════════════════
// MutationRecordingInterceptor — test-only Drift interceptor that records
// every mutated table name during an endpoint call, for F2/FR-204 assertions.
// ═══════════════════════════════════════════════════════════════════════════
//
// Spec 129 F2 / FR-204. Backs `broadcast_wrapper_minimality_test.dart` and the
// 18 per-endpoint integration tests `ws_mirror_broadcast_*_test.dart`. Lets
// tests assert that the wrapper's declared `tables` set EQUALS the set of
// tables the endpoint body actually mutated — enforcing completeness (no
// missing broadcasts) AND minimality (no over-broadcasts).
//
// Runs ONLY in the test harness — never wired into production connections
// (see lib/data/database/connection_io.dart for the production-only
// _PgCompatInterceptor pattern this file mirrors).
//
// Usage:
//   final recorder = MutationRecordingInterceptor();
//   final db = AppDatabase(NativeDatabase.memory().interceptWith(recorder));
//   await db.someInsertOrUpdate();
//   expect(recorder.recordedTables, equals({'sales_invoices', 'inventory'}));
//
// Notes:
//   • Reset between assertions by calling [reset].
//   • The SQL parser is intentionally simple — it expects Drift-generated
//     SQL (which always wraps identifiers in backticks for SQLite or double
//     quotes for PostgreSQL) plus raw INSERT/UPDATE/DELETE inside
//     customStatement calls. Anything else (CREATE TABLE, ALTER, BEGIN,
//     COMMIT, etc.) is ignored — we don't care about DDL or transaction
//     control for broadcast-set assertions.

import 'package:drift/drift.dart';

class MutationRecordingInterceptor extends QueryInterceptor {
  final Set<String> _recorded = <String>{};

  /// Immutable view of the tables that have received INSERT / UPDATE /
  /// DELETE statements since the last [reset] (or since construction).
  Set<String> get recordedTables => Set.unmodifiable(_recorded);

  /// Clear the recorded set. Call between separate assertion blocks within
  /// one test.
  void reset() => _recorded.clear();

  void _recordFromSql(String sql) {
    // Pattern matches both SQLite (`"…"` or `` `…` ``) and PostgreSQL (`"…"`)
    // identifiers, plus bare identifiers (e.g. inside customStatement).
    // We look for the FIRST table mentioned after a top-level mutation verb.
    final match = _mutationPattern.firstMatch(sql);
    if (match == null) return;
    final table = match.group(1) ?? match.group(2) ?? match.group(3);
    if (table != null && table.isNotEmpty) {
      _recorded.add(table.toLowerCase());
    }
  }

  // ── Drift QueryInterceptor overrides ────────────────────────────────────

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _recordFromSql(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _recordFromSql(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _recordFromSql(statement);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _recordFromSql(statement);
    return super.runCustom(executor, statement, args);
  }
}

// Matches the table name in any of:
//   INSERT [OR IGNORE|OR REPLACE] INTO `<table>` (...) VALUES (...)
//   INSERT [OR IGNORE|OR REPLACE] INTO "<table>" (...) VALUES (...)
//   INSERT [OR IGNORE|OR REPLACE] INTO <table> (...) VALUES (...)
//   UPDATE [OR IGNORE|OR REPLACE] `<table>` SET ...
//   UPDATE [OR IGNORE|OR REPLACE] "<table>" SET ...
//   UPDATE [OR IGNORE|OR REPLACE] <table> SET ...
//   DELETE FROM `<table>` WHERE ...
//   DELETE FROM "<table>" WHERE ...
//   DELETE FROM <table> WHERE ...
final RegExp _mutationPattern = RegExp(
  r'^\s*(?:INSERT(?:\s+OR\s+\w+)?\s+INTO|UPDATE(?:\s+OR\s+\w+)?|DELETE\s+FROM)\s+'
  r'(?:`([^`]+)`|"([^"]+)"|(\w+))',
  caseSensitive: false,
);
