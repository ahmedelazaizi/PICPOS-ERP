import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';

/// How conflicts are resolved during bi-directional sync.
///
/// In this ERP:
/// - **serverWins**: Server is authoritative (default for master data).
///   Used for: products, categories, accounts, parties, settings, roles.
/// - **clientWins**: Client version takes priority (rare — only for local drafts).
/// - **appendOnly**: No conflicts possible — each record is unique (default for transactions).
///   Used for: sales, purchases, journals, safe_transactions, stock_movements.
/// - **lastWriteWins**: Compare timestamps, most recent change wins.
///   Used for: parties (name/phone edits from multiple branches).
enum ConflictPolicy {
  serverWins,
  clientWins,
  appendOnly,
  lastWriteWins,
}

/// Result of a single table sync operation
class TableSyncResult {
  final String tableName;
  final bool success;
  final int count;
  final String? error;

  TableSyncResult({
    required this.tableName,
    required this.success,
    this.count = 0,
    this.error,
  });
}

/// Abstract base class for table-specific sync logic
abstract class SyncStrategy {
  final AppDatabase db;
  
  SyncStrategy(this.db);

  /// The table name as seen in the server API and WebSocket events
  String get tableName;

  /// The endpoint to fetch data for this table
  String get apiEndpoint;

  /// How conflicts should be resolved for this table.
  /// Override in subclasses to change the default policy.
  ConflictPolicy get conflictPolicy => ConflictPolicy.serverWins;

  /// Map JSON data from the server into database companions
  Future<void> syncFromJson(Map<String, dynamic> json);

  /// Pull only updated items since the given timestamp
  Future<int> syncIncremental(DateTime since);

  /// Helper to insert or update a record
  Future<void> upsert(Insertable record);

  /// Log a conflict to the audit trail.
  /// Called when a record is being overwritten or skipped during sync.
  Future<void> logConflict({
    required String recordId,
    required String resolution,
    required Map<String, dynamic> clientData,
    Map<String, dynamic>? serverData,
    String? reason,
  }) async {
    try {
      await db.into(db.syncConflictLog).insert(
        SyncConflictLogCompanion.insert(
          conflictTable: tableName,
          recordId: recordId,
          resolution: resolution,
          clientPayload: json.encode(clientData),
          serverPayload: Value(serverData != null ? json.encode(serverData) : null),
          reason: Value(reason),
          clientId: const Value(null),
        ),
      );
      debugPrint('[Sync] ⚠️ Conflict logged: $tableName/$recordId → $resolution');
    } catch (e) {
      debugPrint('[Sync] Failed to log conflict: $e');
    }
  }

  /// Resolve a conflict between local and server data.
  /// Returns true if server version should be applied, false if skipped.
  /// Can be overridden for custom per-table logic.
  Future<bool> resolveConflict({
    required String recordId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
  }) async {
    switch (conflictPolicy) {
      case ConflictPolicy.serverWins:
        await logConflict(
          recordId: recordId,
          resolution: 'server_wins',
          clientData: localData,
          serverData: serverData,
          reason: 'السيرفر هو المرجع الرئيسي',
        );
        return true; // Apply server version

      case ConflictPolicy.clientWins:
        await logConflict(
          recordId: recordId,
          resolution: 'client_wins',
          clientData: localData,
          serverData: serverData,
          reason: 'نسخة العميل أولوية',
        );
        return false; // Keep local version

      case ConflictPolicy.appendOnly:
        // No conflict — both versions should coexist
        return true;

      case ConflictPolicy.lastWriteWins:
        final localUpdated = DateTime.tryParse(
          localData['updatedAt'] as String? ?? localData['createdAt'] as String? ?? '',
        );
        final serverUpdated = DateTime.tryParse(
          serverData['updatedAt'] as String? ?? serverData['createdAt'] as String? ?? '',
        );
        if (localUpdated != null && serverUpdated != null && localUpdated.isAfter(serverUpdated)) {
          await logConflict(
            recordId: recordId,
            resolution: 'client_wins',
            clientData: localData,
            serverData: serverData,
            reason: 'العميل أحدث تعديل (${localUpdated.toIso8601String()} > ${serverUpdated.toIso8601String()})',
          );
          return false;
        }
        await logConflict(
          recordId: recordId,
          resolution: 'server_wins',
          clientData: localData,
          serverData: serverData,
          reason: 'السيرفر أحدث (lastWriteWins)',
        );
        return true;
    }
  }

  /// Resolves a server-provided party id to this device's LOCAL party id.
  ///
  /// PartySyncStrategy preserves the local autoincrement id for parties this
  /// client created (matched by globalId), so a party can live under a
  /// different id locally than on the server. Storing the raw server id in a
  /// transaction FK (customer_id / supplier_id / party_id) makes
  /// getPartyStatement — which filters by the LOCAL party id — come up empty
  /// for that party. Resolution order:
  ///   1. server id already exists locally → keep it (local id == server id);
  ///   2. else the parties remote→local FK mapping → use the local id
  ///      (emits SYNC-MAP);
  ///   3. else the party hasn't synced yet → keep the server id and emit
  ///      SYNC-WARN (its statement may be incomplete until the parties row
  ///      lands).
  ///
  /// Returns [serverPartyId] unchanged for null / 0 (no party).
  ///
  /// Spec 136: extracted verbatim from the identical blocks in the sales,
  /// purchase and safe_transaction strategies (the SYNC-MAP/SYNC-WARN lines
  /// replace the prior local debugPrint / silent fall-through). NOTE: on
  /// mirror/client the REAL inbound path is DeltaPullService._upsertRow, which
  /// carries its own equivalent remap; these Tier-3 strategies are near-dead
  /// but kept correct + observable for the fullSync path.
  Future<int?> resolveLocalPartyId(int? serverPartyId, {String label = 'party'}) async {
    if (serverPartyId == null || serverPartyId == 0) return serverPartyId;
    final direct = await (db.select(db.parties)
          ..where((p) => p.id.equals(serverPartyId))
          ..limit(1))
        .getSingleOrNull();
    if (direct != null) return serverPartyId;
    final mapping = await (db.select(db.remoteIdMappings)
          ..where((m) =>
              m.entityTable.equals('parties') & m.remoteId.equals(serverPartyId))
          ..limit(1))
        .getSingleOrNull();
    if (mapping != null) {
      unawaited(DiagnosticLogger.log('SYNC-MAP',
          '$label resolved server $serverPartyId → local ${mapping.localId}'));
      return mapping.localId;
    }
    unawaited(DiagnosticLogger.log('SYNC-WARN',
        '$label FK $serverPartyId pulled with no local party mapping — '
        'statement for this party may be incomplete until its parties row '
        'syncs (SyncStrategy fullSync path).'));
    return serverPartyId;
  }

  // ═══════════════════════════════════════════════════════════════
  // Defensive Parsing Helpers
  // ═══════════════════════════════════════════════════════════════

  /// Safely parse a boolean from dynamic JSON (handles 1/0, "true"/"false")
  bool parseBool(dynamic value, [bool defaultValue = false]) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      if (value == '1' || value.toLowerCase() == 'true') return true;
      if (value == '0' || value.toLowerCase() == 'false') return false;
    }
    return defaultValue;
  }

  /// Safely parse an integer from dynamic JSON, with fallback
  int parseInt(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    if (value is bool) return value ? 1 : 0;
    return defaultValue;
  }

  /// Safely parse a nullable integer from dynamic JSON
  int? parseIntNullable(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    if (value is bool) return value ? 1 : 0;
    return null;
  }

  /// Safely parse a double from dynamic JSON, with fallback
  double parseDouble(dynamic value, [double defaultValue = 0.0]) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Safely parse a nullable double from dynamic JSON
  double? parseDoubleNullable(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

