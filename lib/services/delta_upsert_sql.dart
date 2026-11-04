/// UPSERT-by-id statement for a pulled row (R5).
///
/// `INSERT OR REPLACE` deletes then re-inserts the row, which fires
/// `ON DELETE CASCADE` on child tables (modifier groups/items, ...) and the
/// differential pull never re-sends the untouched children. `ON CONFLICT(id)
/// DO UPDATE` rewrites the payload columns in place: no delete, no cascade.
/// Columns absent from the payload keep their local value.
///
/// INT-05 / INT-03 (round 2): the `DO UPDATE` only runs when some payload
/// column actually differs. The inclusive watermark (`>= since`, and on
/// PostgreSQL the open-transaction floor) re-delivers boundary rows by design,
/// and a byte-identical re-apply is not a no-op: it fires the
/// `{t}_bump_version` trigger (row_version unchanged ⇒ bump), so the reader's
/// copy drifted to server+1 with a local stamp on every duplicate — and for
/// the newerWins tables (parties, shifts) a later genuine server row could
/// then lose to it. `IS DISTINCT FROM` is NULL-safe and valid on SQLite
/// (3.39+) and PostgreSQL; a row that differs in any column updates exactly
/// as before.
String deltaUpsertSql(String table, Map<String, dynamic> row) {
  final cols = row.keys.join(', ');
  final ph = List.filled(row.length, '?').join(', ');
  final updatable = [for (final k in row.keys) if (k != 'id') k];
  final insert = 'INSERT INTO $table ($cols) VALUES ($ph) ON CONFLICT(id) DO';
  if (updatable.isEmpty) return '$insert NOTHING';
  final set = updatable.map((k) => '$k = excluded.$k').join(', ');
  final changed = updatable
      .map((k) => '$table.$k IS DISTINCT FROM excluded.$k')
      .join(' OR ');
  return '$insert UPDATE SET $set WHERE $changed';
}
