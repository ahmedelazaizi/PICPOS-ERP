part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FK RESOLVER DAO — P2.2 Remote ID Mapping Layer
// ═══════════════════════════════════════════════════════════════════════════
// Provides CRUD and bulk-query methods on the remote_id_mappings table.
//
// Usage pattern (OfflineSyncWorker):
//   After replaying an outbox insert and receiving the server ID:
//     await db.storeFkMapping(tableName: 'purchase_orders', localId: 5, remoteId: 1042, globalId: 'UUID-123');
//
//   Before replaying an outbox update that references a local FK:
//     final remoteId = await db.resolveRemoteId('purchase_orders', localId: 5);
//     // → 1042, or null if not yet mapped

extension FkResolverDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // WRITE
  // ─────────────────────────────────────────────────────────────────────────

  /// Upsert a local→remote mapping. If the (tableName, localId) pair already
  /// exists, the remoteId and globalId are updated in place.
  Future<void> storeFkMapping({
    required String tableName,
    required int localId,
    required int remoteId,
    String? globalId,
  }) =>
      into(remoteIdMappings).insertOnConflictUpdate(
        RemoteIdMappingsCompanion.insert(
          entityTable: tableName,
          localId: localId,
          remoteId: remoteId,
          globalId: Value(globalId),
        ),
      );

  /// Bulk-upsert mappings from a nested map
  /// `{ tableName → { localIdStr → remoteId } }`.
  /// Used during one-time migration from the legacy JSON blob in settings.
  Future<void> bulkStoreFkMappings(
    Map<String, Map<String, int>> mappings,
  ) async {
    await transaction(() async {
      for (final tableEntry in mappings.entries) {
        for (final idEntry in tableEntry.value.entries) {
          final localId = int.tryParse(idEntry.key);
          if (localId == null) continue;
          await storeFkMapping(
            tableName: tableEntry.key,
            localId: localId,
            remoteId: idEntry.value,
          );
        }
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READ
  // ─────────────────────────────────────────────────────────────────────────

  /// Resolve a local (client-side) ID → server-assigned remote ID.
  /// Returns null if no mapping exists yet (record not yet synced).
  Future<int?> resolveRemoteId(String tableName, int localId) async {
    final row = await (select(remoteIdMappings)
          ..where(
            (r) =>
                r.entityTable.equals(tableName) & r.localId.equals(localId),
          )
          ..limit(1))
        .getSingleOrNull();
    return row?.remoteId;
  }

  /// Resolve a server-assigned remote ID → local (client-side) ID.
  /// Returns null if the mapping is not present.
  Future<int?> resolveLocalId(String tableName, int remoteId) async {
    final row = await (select(remoteIdMappings)
          ..where(
            (r) =>
                r.entityTable.equals(tableName) & r.remoteId.equals(remoteId),
          )
          ..limit(1))
        .getSingleOrNull();
    return row?.localId;
  }

  /// Issue 11 (Feature 018): item-level sync strategies (sales items, purchase
  /// items, sales-order items, stock movements) referenced products by their
  /// SERVER id without consulting [remoteIdMappings]. When a client created a
  /// product offline and the server later assigned a different id during
  /// sync, every downstream item synced from the server pointed at a phantom
  /// product locally. This helper provides a single resolution path with a
  /// `SYNC-WARN` line emitted when the resolved id differs from the raw
  /// payload value, so the rate of divergence can be measured in the field.
  /// Falls back to the raw remote id when no mapping exists (preserves the
  /// previous behavior in the common case where ids match).
  Future<int> resolveItemFk(
    String tableName,
    int remoteId, {
    String? context,
  }) async {
    final mapped = await resolveLocalId(tableName, remoteId);
    if (mapped != null && mapped != remoteId) {
      DiagnosticLogger.log(
        'SYNC-WARN',
        'fk-remap table=$tableName remote=$remoteId → local=$mapped'
            '${context != null ? ' (ctx=$context)' : ''}',
      );
      return mapped;
    }
    return remoteId;
  }

  /// Resolve a globalId (UUIDv7) → server-assigned remote ID.
  /// Returns null if the mapping is not present.
  Future<int?> resolveRemoteByGlobalId(String tableName, String globalId) async {
    final row = await (select(remoteIdMappings)
          ..where(
            (r) =>
                r.entityTable.equals(tableName) & r.globalId.equals(globalId),
          )
          ..limit(1))
        .getSingleOrNull();
    return row?.remoteId;
  }

  /// Load all mappings as a nested map suitable for OfflineSyncWorker's
  /// `_applyIdMappings` method: `{ tableName → { localIdStr → remoteId } }`.
  Future<Map<String, Map<String, int>>> loadAllFkMappings() async {
    final rows = await select(remoteIdMappings).get();
    final result = <String, Map<String, int>>{};
    for (final row in rows) {
      result.putIfAbsent(row.entityTable, () => {})[row.localId.toString()] =
          row.remoteId;
    }
    return result;
  }

  /// Look up the local record by globalId for a given table and persist the
  /// mapping immediately after a successful outbox insert replay.
  ///
  /// Call this right after the server returns a remoteId for an insert
  /// operation whose payload contained a 'globalId' field.
  Future<void> recordInsertMapping({
    required String tableName,
    required String globalId,
    required int remoteId,
  }) async {
    try {
      final rows = await customSelect(
        'SELECT id FROM $tableName WHERE global_id = ? LIMIT 1',
        variables: [Variable.withString(globalId)],
      ).get();
      if (rows.isEmpty) return;
      final localId = rows.first.data['id'] as int;
      await storeFkMapping(
        tableName: tableName,
        localId: localId,
        remoteId: remoteId,
        globalId: globalId,
      );
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAINTENANCE
  // ─────────────────────────────────────────────────────────────────────────

  /// Delete all mappings for a specific table (e.g., after a full resync).
  Future<int> clearFkMappingsForTable(String tableName) =>
      (delete(remoteIdMappings)
            ..where((r) => r.entityTable.equals(tableName)))
          .go();

  /// Delete all FK mappings (use during factory reset / full resync).
  Future<int> clearAllFkMappings() => delete(remoteIdMappings).go();
}
