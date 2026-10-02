part of 'database.dart';

/// v187 — `cloud_sync_documents` (I-3, desktop ↔ cloud sync).
///
/// One row per cloud field document (mobile sales invoice, return,
/// collection, visit) the desktop has handled, keyed by the cloud
/// `global_id`:
/// • `status = 'posted'` — posted through the desktop paths; `desktop_ref` /
///   `desktop_number` identify the desktop document. A document already
///   posted is never posted again (re-pull is idempotent); it is only
///   acknowledged to the cloud again.
/// • `status = 'conflict'` — desktop validation refused it; `reason` is shown
///   in Settings › Integrations › cloud link with a retry action. It is never
///   dropped: it stays pending on the cloud until posted.
///
/// Raw SQL outside Drift's table model (no codegen run), following
/// [ensureChequeDrawerSchema]. Local to this device: not in the LAN delta pull.
extension CloudSyncSchema on AppDatabase {
  Future<void> ensureCloudSyncSchema() async {
    await customStatement(_isPostgres
        ? '''CREATE TABLE IF NOT EXISTS cloud_sync_documents (
               id SERIAL PRIMARY KEY,
               global_id TEXT NOT NULL UNIQUE,
               kind TEXT NOT NULL,
               cloud_number TEXT,
               status TEXT NOT NULL,
               desktop_ref TEXT,
               desktop_number TEXT,
               reason TEXT,
               attempts INTEGER NOT NULL DEFAULT 0,
               retry_requested INTEGER NOT NULL DEFAULT 0,
               payload TEXT,
               created_at BIGINT NOT NULL,
               updated_at BIGINT NOT NULL
             )'''
        : '''CREATE TABLE IF NOT EXISTS cloud_sync_documents (
               id INTEGER PRIMARY KEY AUTOINCREMENT,
               global_id TEXT NOT NULL UNIQUE,
               kind TEXT NOT NULL,
               cloud_number TEXT,
               status TEXT NOT NULL,
               desktop_ref TEXT,
               desktop_number TEXT,
               reason TEXT,
               attempts INTEGER NOT NULL DEFAULT 0,
               retry_requested INTEGER NOT NULL DEFAULT 0,
               payload TEXT,
               created_at INTEGER NOT NULL,
               updated_at INTEGER NOT NULL
             )''');
    await customStatement('CREATE INDEX IF NOT EXISTS '
        'idx_cloud_sync_documents_status ON cloud_sync_documents(status)');
  }

  Future<CloudSyncDocument?> cloudSyncDocument(String globalId) async {
    final row = await customSelect(
      'SELECT * FROM cloud_sync_documents WHERE global_id = ?',
      variables: [Variable<String>(globalId)],
    ).getSingleOrNull();
    return row == null ? null : CloudSyncDocument._fromRow(row.data);
  }

  /// Marks [globalId] posted (clears any previous conflict).
  Future<void> recordCloudSyncPosted({
    required String globalId,
    required String kind,
    String? cloudNumber,
    required String desktopRef,
    String? desktopNumber,
  }) =>
      _cloudSyncUpsert(globalId, kind, cloudNumber, 'posted',
          desktopRef: desktopRef, desktopNumber: desktopNumber);

  /// Records (or refreshes) a conflict for [globalId] with its [reason].
  Future<void> recordCloudSyncConflict({
    required String globalId,
    required String kind,
    String? cloudNumber,
    required String reason,
    String? payload,
  }) =>
      _cloudSyncUpsert(globalId, kind, cloudNumber, 'conflict',
          reason: reason, payload: payload);

  Future<void> _cloudSyncUpsert(
    String globalId,
    String kind,
    String? cloudNumber,
    String status, {
    String? desktopRef,
    String? desktopNumber,
    String? reason,
    String? payload,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await cloudSyncDocument(globalId);
    if (existing == null) {
      await customInsert(
        'INSERT INTO cloud_sync_documents (global_id, kind, cloud_number, '
        'status, desktop_ref, desktop_number, reason, attempts, payload, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)',
        variables: [
          Variable<String>(globalId),
          Variable<String>(kind),
          Variable<String>(cloudNumber),
          Variable<String>(status),
          Variable<String>(desktopRef),
          Variable<String>(desktopNumber),
          Variable<String>(reason),
          Variable<String>(payload),
          Variable<int>(now),
          Variable<int>(now),
        ],
      );
      return;
    }
    await customUpdate(
      'UPDATE cloud_sync_documents SET status = ?, desktop_ref = ?, '
      'desktop_number = ?, reason = ?, payload = COALESCE(?, payload), '
      'attempts = attempts + 1, retry_requested = 0, updated_at = ? '
      'WHERE global_id = ?',
      variables: [
        Variable<String>(status),
        Variable<String>(desktopRef),
        Variable<String>(desktopNumber),
        Variable<String>(reason),
        Variable<String>(payload),
        Variable<int>(now),
        Variable<String>(globalId),
      ],
    );
  }

  /// Open conflicts, newest first.
  Future<List<CloudSyncDocument>> listCloudSyncConflicts() async {
    final rows = await customSelect(
      "SELECT * FROM cloud_sync_documents WHERE status = 'conflict' "
      'ORDER BY updated_at DESC, id DESC',
    ).get();
    return [for (final r in rows) CloudSyncDocument._fromRow(r.data)];
  }

  /// Asks the next sync run to post [globalId] again.
  Future<void> requestCloudSyncRetry(String globalId) => customUpdate(
        'UPDATE cloud_sync_documents SET retry_requested = 1 '
        "WHERE global_id = ? AND status = 'conflict'",
        variables: [Variable<String>(globalId)],
      );

  Future<({int posted, int conflicts})> cloudSyncCounts() async {
    final rows = await customSelect(
      'SELECT status, COUNT(*) AS n FROM cloud_sync_documents GROUP BY status',
    ).get();
    var posted = 0, conflicts = 0;
    for (final r in rows) {
      final n = (r.data['n'] as num).toInt();
      if (r.data['status'] == 'posted') posted = n;
      if (r.data['status'] == 'conflict') conflicts = n;
    }
    return (posted: posted, conflicts: conflicts);
  }
}

/// A cloud field document as handled by this desktop.
class CloudSyncDocument {
  const CloudSyncDocument({
    required this.globalId,
    required this.kind,
    required this.status,
    this.cloudNumber,
    this.desktopRef,
    this.desktopNumber,
    this.reason,
    this.attempts = 0,
    this.retryRequested = false,
    this.updatedAt,
  });

  factory CloudSyncDocument._fromRow(Map<String, dynamic> d) =>
      CloudSyncDocument(
        globalId: d['global_id'] as String,
        kind: d['kind'] as String,
        status: d['status'] as String,
        cloudNumber: d['cloud_number'] as String?,
        desktopRef: d['desktop_ref'] as String?,
        desktopNumber: d['desktop_number'] as String?,
        reason: d['reason'] as String?,
        attempts: (d['attempts'] as num?)?.toInt() ?? 0,
        retryRequested: (d['retry_requested'] as num?)?.toInt() == 1,
        updatedAt: d['updated_at'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (d['updated_at'] as num).toInt())
            : null,
      );

  final String globalId;
  final String kind;
  final String status;
  final String? cloudNumber;
  final String? desktopRef;
  final String? desktopNumber;
  final String? reason;
  final int attempts;
  final bool retryRequested;
  final DateTime? updatedAt;

  bool get isPosted => status == 'posted';
  bool get isConflict => status == 'conflict';
}
