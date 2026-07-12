part of '../database.dart';

/// Table to store pending synchronization tasks for Supabase
@DataClassName('SyncOutboxItem')
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The target table name in Supabase
  TextColumn get targetTable =>
      text().named('table_name').withLength(max: 100)();

  /// Remote ID if known, otherwise NULL for inserts
  TextColumn get remoteId => text().nullable()();

  /// The local record ID (can be int or UUID string)
  TextColumn get recordId => text()();

  /// UUIDv7 Idempotency key to prevent double inserts during retries
  TextColumn get idempotencyKey => text().nullable()();

  /// The operation type: 'insert', 'update', 'delete', 'upsert'
  TextColumn get operation => text().withLength(max: 20)();

  /// JSON payload to be sent to Supabase
  TextColumn get payload => text()();

  /// Current status: 'pending', 'synced', 'failed'
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Number of sync attempts
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Last error message if failed
  TextColumn get lastError => text().nullable()();

  /// When this sync task was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When this task was last attempted
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
}

/// Conflict log for audit trail of sync conflicts.
/// When a client pushes data that conflicts with server state,
/// both versions are logged here for traceability.
@DataClassName('SyncConflictLogItem')
class SyncConflictLog extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The table where the conflict occurred
  TextColumn get conflictTable => text().named('table_name').withLength(max: 100)();

  /// The record ID that conflicted
  TextColumn get recordId => text()();

  /// How the conflict was resolved: 'server_wins', 'client_wins', 'merged', 'skipped'
  TextColumn get resolution => text().withLength(max: 20)();

  /// JSON snapshot of what the client tried to push
  TextColumn get clientPayload => text()();

  /// JSON snapshot of the server's current version (if available)
  TextColumn get serverPayload => text().nullable()();

  /// Human-readable reason for the resolution
  TextColumn get reason => text().nullable()();

  /// Which client caused the conflict
  TextColumn get clientId => text().nullable()();

  /// When the conflict was detected
  DateTimeColumn get detectedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Persistent FK remap table — maps client-local (SQLite auto-increment) IDs to
/// server-assigned IDs captured during outbox drain.
///
/// Replaces the fragile JSON blob in the settings table ('_sync_id_mappings').
/// Indexed for efficient lookup by (tableName + localId), (tableName + remoteId),
/// and (tableName + globalId) so the OfflineSyncWorker can resolve FKs in any direction.
@DataClassName('RemoteIdMappingData')
@TableIndex(name: 'idx_remote_id_local', columns: {#entityTable, #localId}, unique: true)
@TableIndex(name: 'idx_remote_id_remote', columns: {#entityTable, #remoteId})
@TableIndex(name: 'idx_remote_id_global', columns: {#entityTable, #globalId})
class RemoteIdMappings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityTable => text().named('table_name')(); // SQL table name, e.g. 'purchase_orders'
  IntColumn get localId => integer()();   // local SQLite auto-increment ID
  IntColumn get remoteId => integer()();  // server-assigned ID (returned after successful sync)
  TextColumn get globalId => text().nullable()(); // UUIDv7 stable identity (may be null for legacy rows)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Stores idempotency keys to ensure exactly-once processing for incoming API requests.
/// Required by PIR-03 and PIR-04.
@DataClassName('ProcessedMessageItem')
class ProcessedMessages extends Table {
  /// The global idempotency key (UUID or generated signature).
  TextColumn get idempotencyKey => text()();

  /// The JSON response payload returned originally.
  TextColumn get responsePayload => text()();

  /// Endpoint or operation name for debugging.
  TextColumn get actionType => text().nullable()();

  /// Timestamp when created. Automatically pruned after expiration (e.g. 7 days).
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {idempotencyKey};
}
