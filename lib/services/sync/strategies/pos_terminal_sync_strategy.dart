// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

/// Pulls pos_terminals master data from the server into the local DB.
///
/// Feature 009 / T012c — registers the per-device POS terminals
/// (FR-034). Without this strategy, clients/mirrors never learn which
/// terminal id maps to their `device_id`, so the per-terminal stock
/// shortage policy (FR-017) and per-terminal sales reports cannot
/// resolve. Constitution III + R5 mandate `serverWins` for master data.
///
/// FK dependencies: branches (Tier 1).
///
/// Dedup: globalId first (the server-minted UUID), then deviceId (a
/// stable client-side UUIDv7 the device generated at first launch),
/// then server id as last resort.
class PosTerminalSyncStrategy extends SyncStrategy {
  PosTerminalSyncStrategy(super.db);

  @override
  String get tableName => 'pos_terminals';

  @override
  String get apiEndpoint => '/api/pos-terminals';

  /// R5 — POS terminal registry is master data: device fingerprint +
  /// branch-binding live on the server, and the device-name / cost-center
  /// can be re-assigned by the admin from the server. `serverWins` lets
  /// those reassignments propagate to every paired client without
  /// resolving conflicts manually.
  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.serverWins;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final list = (json['pos_terminals'] as List?) ??
        (json['posTerminals'] as List?) ??
        const [];
    for (final item in list) {
      await _syncSingle(item as Map<String, dynamic>);
    }
    if (list.isNotEmpty) {
      db.markTablesUpdated({db.posTerminals});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  Future<void> _syncSingle(Map<String, dynamic> m) async {
    try {
      final serverId = parseInt(m['id']);
      final serverGlobalId = m['globalId'] as String?;
      final serverDeviceId = m['deviceId'] as String? ?? '';
      final serverName = m['name'] as String? ?? '';
      final serverBranchId = parseInt(m['branchId']);

      // Tier 1: globalId match (strongest)
      PosTerminalData? existing;
      if (serverGlobalId != null && serverGlobalId.isNotEmpty) {
        existing = await (db.select(db.posTerminals)
              ..where((t) => t.globalId.equals(serverGlobalId)))
            .getSingleOrNull();
      }
      // Tier 2: deviceId match (the device's stable UUIDv7 from secure storage)
      if (existing == null && serverDeviceId.isNotEmpty) {
        existing = await (db.select(db.posTerminals)
              ..where((t) => t.deviceId.equals(serverDeviceId)))
            .getSingleOrNull();
      }
      // Tier 3: server id (legacy fallback)
      existing ??= await (db.select(db.posTerminals)
            ..where((t) => t.id.equals(serverId)))
          .getSingleOrNull();

      // Use existing local id when matched so dependent shifts.pos_terminal_id
      // FK rows stay valid.
      final useId = existing?.id ?? serverId;
      final companion = PosTerminalsCompanion(
        id: Value(useId),
        name: Value(serverName),
        deviceId: Value(serverDeviceId),
        branchId: Value(serverBranchId),
        isActive: Value(parseBool(m['isActive'], true)),
        notes: Value(m['notes'] as String?),
        createdAt: Value(
          DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
        ),
        globalId: Value(serverGlobalId),
      );
      await db.into(db.posTerminals).insertOnConflictUpdate(companion);
    } catch (e) {
      debugPrint('[Sync] Error in PosTerminalSyncStrategy: $e');
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    await db
        .into(db.posTerminals)
        .insertOnConflictUpdate(record as PosTerminalsCompanion);
  }
}