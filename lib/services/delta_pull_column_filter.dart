import 'dart:async';
import 'package:drift/drift.dart'
    show GeneratedDatabase, SqlDialect, Variable;
import 'package:flutter/foundation.dart';
import '../core/logging/diagnostic_logger.dart';

/// D-1 — makes the delta-pull upsert tolerant of a host on a newer schema.
///
/// The host sends `SELECT *` rows; a client on an older schema has no column
/// for the extra keys, and `INSERT OR REPLACE INTO t (<keys>)` fails with
/// "no such column", dropping the whole row. This filters a row down to the
/// table's actual local columns (`PRAGMA table_info`, cached per session) and
/// logs one SYNC-WARN line per table per session when keys are dropped.
/// Column discovery: `PRAGMA table_info` on SQLite, `information_schema.columns`
/// on PostgreSQL.
class DeltaPullColumnFilter {
  final Map<String, Set<String>> _columns = {};
  final Set<String> _warned = {};

  /// Start a new session (new database ⇒ new schema).
  void reset() {
    _columns.clear();
    _warned.clear();
  }

  Future<Set<String>> _localColumns(GeneratedDatabase db, String table) async {
    final cached = _columns[table];
    if (cached != null) return cached;
    final Set<String> cols;
    if (db.executor.dialect == SqlDialect.postgres) {
      // PRAGMA is a 42601 syntax error on PG and would poison the open
      // transaction; information_schema is the portable equivalent.
      final rows = await db.customSelect(
        'SELECT column_name FROM information_schema.columns '
        'WHERE table_schema = current_schema() AND table_name = ?',
        variables: [Variable<String>(table)],
      ).get();
      cols = {for (final r in rows) r.read<String>('column_name')};
    } else {
      final rows = await db.customSelect('PRAGMA table_info("$table")').get();
      cols = {for (final r in rows) r.read<String>('name')};
    }
    // Empty ⇒ unknown table: don't cache, don't filter.
    if (cols.isNotEmpty) _columns[table] = cols;
    return cols;
  }

  /// [row] without keys that are not local columns of [table]. Never throws
  /// (falls back to the raw row).
  Future<Map<String, dynamic>> apply(
    GeneratedDatabase db,
    String table,
    Map<String, dynamic> row,
  ) async {
    try {
      final cols = await _localColumns(db, table);
      if (cols.isEmpty) return row;
      final unknown = row.keys.where((k) => !cols.contains(k)).toList();
      if (unknown.isEmpty) return row;
      if (_warned.add(table)) {
        unawaited(DiagnosticLogger.log(
          'SYNC-WARN',
          'DeltaPull $table: ignoring columns unknown to this client schema '
          '(host is newer?): ${unknown.join(', ')}',
        ));
      }
      return {
        for (final e in row.entries)
          if (cols.contains(e.key)) e.key: e.value,
      };
    } catch (e) {
      debugPrint('[DeltaPull] column filter $table failed (applying raw): $e');
      return row;
    }
  }
}
