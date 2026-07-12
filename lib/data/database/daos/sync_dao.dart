part of '../database.dart';

extension SyncDao on AppDatabase {
  /// Adds a new item to the sync outbox
  /// Should be called within a database transaction alongside the local data operation.
  Future<int> addToSyncOutbox({
    required String tableName,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    String? remoteId,
    String? idempotencyKey,
  }) {
    // We use toString() for simple storage, but the worker will parse this.
    // Ideally, the payload should be JSON encoded.
    return into(syncOutbox).insert(
      SyncOutboxCompanion.insert(
        targetTable: tableName,
        recordId: recordId,
        operation: operation,
        payload: jsonEncode(payload),
        remoteId: Value(remoteId),
        idempotencyKey: Value(idempotencyKey),
        status: const Value('pending'),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  /// Get pending items from the outbox for the background worker
  Future<List<SyncOutboxItem>> getPendingSyncItems({int limit = 50}) {
    return (select(syncOutbox)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Mark an item as successfully synced to Supabase
  Future<void> markAsSyncSuccess(int id, {String? remoteId}) {
    return (update(syncOutbox)..where((t) => t.id.equals(id))).write(
      SyncOutboxCompanion(
        status: const Value('synced'),
        remoteId: Value(remoteId),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark an item as failed with an error message and increment attempt counter
  Future<void> markAsSyncFailed(int id, String error) async {
    // Read current attempts first, then increment
    final item = await (select(
      syncOutbox,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    final currentAttempts = item?.attempts ?? 0;
    await (update(syncOutbox)..where((t) => t.id.equals(id))).write(
      SyncOutboxCompanion(
        status: const Value('pending'), // Keep as pending to retry later
        lastError: Value(error),
        attempts: Value(currentAttempts + 1),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark an item as permanently failed (non-retryable error)
  Future<void> markAsSyncError(int id, String error) {
    return (update(syncOutbox)..where((t) => t.id.equals(id))).write(
      SyncOutboxCompanion(
        status: const Value('failed'),
        lastError: Value(error),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// PHASE-8: Mark an item as dead_letter — permanently excluded from retry.
  /// Unlike 'failed', dead_letter items are NEVER reset by resetFailedSyncItems.
  Future<void> markAsSyncDeadLetter(int id, String error) {
    return (update(syncOutbox)..where((t) => t.id.equals(id))).write(
      SyncOutboxCompanion(
        status: const Value('dead_letter'),
        lastError: Value('DEAD_LETTER: $error'),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// L4 (2026-04-28): Bulk-reset every dead_letter item back to pending so the
  /// next outbox drain re-attempts them all. Used by the "إعادة محاولة الكل"
  /// button in the sync management dialog after the admin has fixed the
  /// underlying issue (e.g. corrected a warehouse-branch mapping).
  Future<int> retryAllDeadLetterItems() async {
    return (update(syncOutbox)
          ..where((t) => t.status.equals('dead_letter')))
        .write(
      const SyncOutboxCompanion(
        status: Value('pending'),
        attempts: Value(0),
        lastError: Value(null),
      ),
    );
  }

  /// Watch pending count for UI indicators
  Stream<int> watchSyncPendingCount() {
    final count = syncOutbox.id.count();
    return (selectOnly(syncOutbox)
          ..addColumns([count])
          ..where(syncOutbox.status.equals('pending')))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  /// Watch pending sync count scoped to a single source table (e.g. `sales`,
  /// `purchase_invoices`, `sales_returns`, `purchase_returns`). Used by the
  /// per-screen "X invoices waiting to sync" banner so the operator sees the
  /// count for the list they're looking at, not the global outbox total.
  Stream<int> watchSyncPendingCountForTable(String tableName) {
    final count = syncOutbox.id.count();
    return (selectOnly(syncOutbox)
          ..addColumns([count])
          ..where(syncOutbox.status.equals('pending') &
              syncOutbox.targetTable.equals(tableName)))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  /// Snapshot version of the same query for one-shot reads.
  Future<int> getSyncPendingCountForTable(String tableName) async {
    final count = syncOutbox.id.count();
    final row = await (selectOnly(syncOutbox)
          ..addColumns([count])
          ..where(syncOutbox.status.equals('pending') &
              syncOutbox.targetTable.equals(tableName)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  /// Reset all permanently failed items back to 'pending' so they can be retried.
  /// Called when server connectivity is confirmed (e.g. before drainOutbox).
  /// PHASE-8: Does NOT reset 'dead_letter' items — those are permanently excluded.
  Future<int> resetFailedSyncItems() async {
    final failedItems = await (select(syncOutbox)
          ..where((t) => t.status.equals('failed')))
        .get();
    if (failedItems.isEmpty) return 0;

    for (final item in failedItems) {
      await (update(syncOutbox)..where((t) => t.id.equals(item.id))).write(
        const SyncOutboxCompanion(
          status: Value('pending'),
          attempts: Value(0),
        ),
      );
    }
    return failedItems.length;
  }

  /// PHASE-8: Get dead letter items count for diagnostics/UI
  Future<int> getDeadLetterCount() async {
    final count = syncOutbox.id.count();
    final row = await (selectOnly(syncOutbox)
          ..addColumns([count])
          ..where(syncOutbox.status.equals('dead_letter')))
        .getSingle();
    return row.read(count) ?? 0;
  }

  /// Watch dead-letter count in real-time for the red alert badge in the UI.
  Stream<int> watchSyncDeadLetterCount() {
    final count = syncOutbox.id.count();
    return (selectOnly(syncOutbox)
          ..addColumns([count])
          ..where(syncOutbox.status.equals('dead_letter')))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  /// Get all outbox items (for diagnostic purposes)
  Future<List<SyncOutboxItem>> getAllSyncItems() {
    return (select(syncOutbox)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Operator-escape: bulk-mark every non-synced outbox row as synced.
  ///
  /// Used when the operator has VERIFIED the data already exists on the
  /// server (e.g. via pgAdmin or the server's own UI) but stale rows in
  /// the local outbox keep the pending-count badge lit. Hitting drain
  /// doesn't help in that case because the server returns 409 (which
  /// IS already handled) — but if any earlier drain attempt finished
  /// with a network-level error before the response was parsed, the
  /// row can be stuck in `pending`/`failed`/`dead_letter` while the
  /// server already has the write.
  ///
  /// Returns the number of rows marked synced.
  Future<int> markAllAsSyncedReconciled() async {
    final affected = await (update(syncOutbox)
          ..where((t) =>
              t.status.isIn(const ['pending', 'failed', 'dead_letter'])))
        .write(
      SyncOutboxCompanion(
        status: const Value('synced'),
        lastError: const Value('reconciled_by_operator'),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
    return affected;
  }
}
