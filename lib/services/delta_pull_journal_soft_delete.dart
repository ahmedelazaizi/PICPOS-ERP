part of 'delta_pull_service.dart';

Future<void> _applyIncomingSoftDelete(
  AppDatabase db,
  String table,
  int? localId,
  Object? deletedAtWire,
) async {
  if (table == 'journal_entries' && localId != null) {
    await _applyJournalEntrySoftDelete(db, localId, deletedAtWire);
    return;
  }
  await _applyGenericSoftDelete(db, table, localId, deletedAtWire);
}

Future<void> _applyJournalEntrySoftDelete(
  AppDatabase db,
  int entryId,
  Object? deletedAtWire,
) async {
  final affectedAccounts = await db.customSelect(
    'SELECT DISTINCT account_id FROM journal_entry_lines WHERE entry_id = ?',
    variables: [Variable.withInt(entryId)],
  ).get();
  final deletedAt = _parseJournalSoftDeleteTimestamp(deletedAtWire);
  await _markJournalEntrySoftDeleted(db, entryId, deletedAt);
  await JournalSyncStrategy(db).recalculateBalancesForAccounts(
    affectedAccounts.map((row) => row.read<int>('account_id')),
  );
  db.markTablesUpdated({db.journalEntries, db.accounts});
}

DateTime _parseJournalSoftDeleteTimestamp(Object? deletedAtWire) {
  final timestamp = deletedAtWire is DateTime
      ? deletedAtWire
      : deletedAtWire is num
          ? DateTime.fromMillisecondsSinceEpoch(deletedAtWire.toInt())
          : DateTime.tryParse(deletedAtWire?.toString() ?? '');
  if (timestamp == null) {
    throw FormatException(
      'Invalid journal_entries.deleted_at: $deletedAtWire',
    );
  }
  return timestamp;
}

Future<void> _markJournalEntrySoftDeleted(
  AppDatabase db,
  int entryId,
  DateTime deletedAt,
) async {
  // Accounting readers use isDeleted, so keep it in sync with deletedAt.
  await (db.update(db.journalEntries)
        ..where((entry) => entry.id.equals(entryId)))
      .write(JournalEntriesCompanion(
        deletedAt: Value(deletedAt),
        isDeleted: const Value(true),
      ));
}

Future<void> _applyGenericSoftDelete(
  AppDatabase db,
  String table,
  int? localId,
  Object? deletedAtWire,
) async {
  try {
    await db.customStatement(
      'UPDATE $table SET deleted_at = ? WHERE id = ?',
      [deletedAtWire, localId],
    );
  } catch (error, stack) {
    await DiagnosticLogger.logError(
      'SYNC-PULL',
      'soft-delete apply failed for $table id=$localId',
      error,
      stack,
    );
  }
}
