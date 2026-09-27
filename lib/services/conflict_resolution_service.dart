import 'dart:convert';
import 'package:drift/drift.dart';
import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';
import 'sync_event_bus.dart';

/// P4.2 — Conflict Resolution
///
/// When the server sends a row during delta pull that conflicts with a locally
/// modified row (client has a higher row_version), this service decides which
/// version wins and logs the outcome to [SyncConflictLog].
///
/// Default policy: [ConflictPolicy.newerWins] — whichever side has the higher
/// row_version is authoritative. Ties go to the server.
enum ConflictPolicy {
  serverWins, // server always overwrites local
  clientWins, // local is always preserved
  newerWins,  // higher row_version wins; tie → server wins
}

class ConflictResolutionService {
  ConflictResolutionService._();
  static final ConflictResolutionService instance =
      ConflictResolutionService._();

  AppDatabase? _db;

  void initialize(AppDatabase db) {
    _db = db;
  }

  /// C-04: Per-table conflict policy for the live inbound DeltaPull path.
  ///
  /// DeltaPull only runs on CLIENT/MIRROR devices, where the server is the
  /// Single Source of Truth (R4), so the default MUST be [ConflictPolicy.serverWins]
  /// — NOT this enum's `newerWins` default. The v129 `{t}_bump_version` trigger
  /// bumps `row_version` on ANY local UPDATE, so a locally-edited server-authoritative
  /// row would out-version the authoritative server row under newerWins and
  /// permanently reject the server-wins self-heal. `appendOnly` transaction tables
  /// behave like serverWins for this inbound apply-decision (the commercial_paper
  /// strategy says so explicitly), so they fold into the default too.
  ///
  /// Only the R5 `lastWriteWins` tables map to [ConflictPolicy.newerWins], whose
  /// `_resolveByRowVersion` (row_version + last_modified_at + origin tiebreak) IS
  /// the lastWriteWins semantics: `parties` and `shifts`. On THIS inbound
  /// DeltaPull path both get plain newerWins (row_version → last_modified_at)
  /// resolution — the ≈ documented lastWriteWins policy. The strategy-layer
  /// carve-outs (shift_sync_strategy's open/close windows) do NOT run here;
  /// Tier-3 strategies are skipped for client/mirror, DeltaPull is the path
  /// that actually runs. Do NOT invent new policies here (R5) — this only maps
  /// existing strategy declarations onto the 3-value service enum.
  static const Set<String> _lastWriteWinsTables = {'parties', 'shifts'};

  /// Numeric ids are shared across these seeded/master-data tables. For every
  /// other table, an id-only match is unsafe because client/server sequences
  /// are independent; a missing global_id therefore means a new row.
  static const Set<String> _sharedIdTables = {
    'branches',
    'warehouses',
    'products',
    'parties',
    'categories',
    'units',
    'payment_methods',
  };

  /// Device clocks are not authoritative. When row versions tie and timestamps
  /// are within this skew window, server wins deterministically.
  static const int _timestampSkewSeconds = 120;

  ConflictPolicy policyForTable(String table) =>
      _lastWriteWinsTables.contains(table)
          ? ConflictPolicy.newerWins
          : ConflictPolicy.serverWins;

  /// Returns `true` if the [serverRow] should be applied to local SQLite.
  /// Returns `false` if the local row is newer and should be preserved.
  ///
  /// Always logs a [SyncConflictLogItem] when the client wins.
  Future<bool> shouldApplyServerRow(
    String table,
    Map<String, dynamic> serverRow, {
    ConflictPolicy policy = ConflictPolicy.newerWins,
  }) async {
    if (_db == null) return true;

    switch (policy) {
      case ConflictPolicy.serverWins:
        return true;
      case ConflictPolicy.clientWins:
        await _logConflict(
          table: table,
          serverRow: serverRow,
          resolution: 'client_wins',
          reason: 'clientWins policy — server row rejected',
        );
        return false;
      case ConflictPolicy.newerWins:
        return _resolveByRowVersion(table, serverRow);
    }
  }

  Future<bool> _resolveByRowVersion(
    String table,
    Map<String, dynamic> serverRow,
  ) async {
    final id = serverRow['id'];
    final globalId = serverRow['global_id'] is String
        ? serverRow['global_id'] as String
        : null;

    try {
      // Prefer global_id lookup so client-originated rows (where local id
      // differs from server id) are compared against their true counterpart.
      QueryRow? local;
      if (globalId != null && globalId.isNotEmpty) {
        try {
          local = await _db!
              .customSelect(
                'SELECT row_version, last_modified_at, origin_client_id, global_id '
                'FROM $table WHERE global_id = ? LIMIT 1',
                variables: [Variable.withString(globalId)],
              )
              .getSingleOrNull();
        } catch (error, stack) {
          // Some legacy tables lack global_id; only their documented shared ids
          // may use the guarded numeric-id fallback below.
          await DiagnosticLogger.logError(
            'SYNC-CONFLICT',
            'global_id lookup failed for $table',
            error,
            stack,
          );
        }
      }
      if (local == null && id is int && _sharedIdTables.contains(table)) {
        try {
          final candidate = await _db!
              .customSelect(
                'SELECT row_version, last_modified_at, origin_client_id, global_id '
                'FROM $table WHERE id = ? LIMIT 1',
                variables: [Variable.withInt(id)],
              )
              .getSingleOrNull();
          // Never let a numeric collision bind unrelated records. A fallback
          // is valid only when the local candidate also has no global_id.
          if (candidate == null || candidate.data['global_id'] == null) {
            local = candidate;
          }
        } catch (error, stack) {
          await DiagnosticLogger.logError(
            'SYNC-CONFLICT',
            'shared-id lookup failed for $table',
            error,
            stack,
          );
        }
      }

      if (local == null) return true; // no local row → apply server

      final localVersion = local.data['row_version'] as int? ?? 0;
      final serverVersion = serverRow['row_version'] as int? ?? 0;

      if (serverVersion > localVersion) return true;
      if (serverVersion < localVersion) {
        await _logConflict(
          table: table,
          serverRow: serverRow,
          resolution: 'client_wins',
          reason:
              'local row_version=$localVersion > server row_version=$serverVersion',
        );
        SyncEventBus.instance.emit(
          SyncConflictDetected(table, id, 'client_wins'),
        );
        return false;
      }

      // Tie on row_version — fall back to last_modified_at, then
      // origin_client_id lexical order for a deterministic winner.
      final localTs = local.data['last_modified_at'] as int? ?? 0;
      final serverTs = serverRow['last_modified_at'] as int? ?? 0;
      final timestampDelta = (serverTs - localTs).abs();
      // Within clock skew, timestamps cannot establish causality. Prefer the
      // server so every client resolves the tie identically.
      if (timestampDelta < _timestampSkewSeconds) return true;
      if (serverTs > localTs) return true;
      if (serverTs < localTs) {
        await _logConflict(
          table: table,
          serverRow: serverRow,
          resolution: 'client_wins',
          reason:
              'tie on row_version=$localVersion; local last_modified_at=$localTs > server=$serverTs outside skew window',
        );
        SyncEventBus.instance.emit(
          SyncConflictDetected(table, id, 'client_wins'),
        );
        return false;
      }

      final localOrigin = (local.data['origin_client_id'] as String?) ?? '';
      final serverOrigin = (serverRow['origin_client_id'] as String?) ?? '';
      // Deterministic tie-break: the origin with the lexically smaller id wins.
      // Equal strings → both sides produced the same update, server-wins is a
      // safe no-op.
      if (serverOrigin.compareTo(localOrigin) <= 0) return true;
      await _logConflict(
        table: table,
        serverRow: serverRow,
        resolution: 'client_wins',
        reason:
            'full tie on row_version/last_modified_at; origin=$localOrigin beats $serverOrigin',
      );
      SyncEventBus.instance.emit(
        SyncConflictDetected(table, id, 'client_wins'),
      );
      return false;
    } catch (error, stack) {
      // Resolver failures must be observable; server-wins remains the safe
      // availability default, but the diagnostic trail prevents silent drift.
      await DiagnosticLogger.logError(
        'SYNC-CONFLICT',
        'conflict resolution failed for $table',
        error,
        stack,
      );
      return true;
    }
  }

  Future<void> _logConflict({
    required String table,
    required Map<String, dynamic> serverRow,
    required String resolution,
    required String reason,
  }) async {
    try {
      await _db!.into(_db!.syncConflictLog).insert(
        SyncConflictLogCompanion.insert(
          conflictTable: table,
          recordId: serverRow['id']?.toString() ?? '',
          resolution: resolution,
          clientPayload: '{}',
          serverPayload: Value(jsonEncode(serverRow)),
          reason: Value(reason),
        ),
      );
    } catch (error, stack) {
      await DiagnosticLogger.logError(
        'SYNC-CONFLICT',
        'conflict log insert failed for $table',
        error,
        stack,
      );
    }
  }
}
