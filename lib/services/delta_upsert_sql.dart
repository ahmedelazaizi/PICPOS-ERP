/// UPSERT-by-id statement for a pulled row (R5).
///
/// `INSERT OR REPLACE` deletes then re-inserts the row, which fires
/// `ON DELETE CASCADE` on child tables (modifier groups/items, ...) and the
/// differential pull never re-sends the untouched children. `ON CONFLICT(id)
/// DO UPDATE` rewrites the payload columns in place: no delete, no cascade.
/// Columns absent from the payload keep their local value.
String deltaUpsertSql(String table, Map<String, dynamic> row) {
  final cols = row.keys.join(', ');
  final ph = List.filled(row.length, '?').join(', ');
  final set = [for (final k in row.keys) if (k != 'id') '$k = excluded.$k'];
  final action = set.isEmpty ? 'NOTHING' : 'UPDATE SET ${set.join(', ')}';
  return 'INSERT INTO $table ($cols) VALUES ($ph) '
      'ON CONFLICT(id) DO $action';
}
