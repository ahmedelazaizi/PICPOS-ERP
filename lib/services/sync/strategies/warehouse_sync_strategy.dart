// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/warehouse_dedup_extension.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

class WarehouseSyncStrategy extends SyncStrategy {
  WarehouseSyncStrategy(super.db);

  @override
  String get tableName => 'warehouses';

  @override
  String get apiEndpoint => '/api/warehouses';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final warehouses = json['warehouses'] as List;
    final seenServerGlobalIds = <String>{};
    // Wrap the per-row upsert loop in a transaction (mirrors
    // BranchSyncStrategy.syncFromJson) so a mid-loop failure doesn't leave
    // the table half-updated.
    await db.transaction(() async {
      for (final w in warehouses) {
        // Three-tier dedup: globalId → name → server-id, mirroring the pattern
        // used in BranchSyncStrategy. Without the name fallback, the locally-
        // seeded "المخزن الرئيسي" (auto-generated globalId) would never match
        // the server's "المخزن الرئيسي" (server globalId) and the first sync
        // would create a duplicate row.
        final globalId = w['globalId'] as String?;
        final whName = w['name'] as String;
        Warehouse? existing;

        // Tier 1: globalId match
        if (globalId != null && globalId.isNotEmpty) {
          existing = await (db.select(db.warehouses)
                ..where((t) => t.globalId.equals(globalId))
                ..limit(1))
              .getSingleOrNull();
        }
        // Tier 2: name match (catches the locally-seeded default warehouse)
        if (existing == null && whName.isNotEmpty) {
          existing = await (db.select(db.warehouses)
                ..where((t) => t.name.equals(whName))
                ..limit(1))
              .getSingleOrNull();
        }

        final companion = WarehousesCompanion(
          name: Value(whName),
          branchId: Value(parseIntNullable(w['branchId'])),
          isDefault: Value(parseBool(w['isDefault'], false)),
          isActive: Value(parseBool(w['isActive'], true)),
          costCenterId: Value(parseIntNullable(w['costCenterId'])),
          regionId: Value(parseIntNullable(w['regionId'])),
          globalId: Value(globalId),
        );

        if (existing != null) {
          await (db.update(db.warehouses)
                ..where((t) => t.id.equals(existing!.id)))
              .write(companion);
        } else {
          await db.into(db.warehouses).insertOnConflictUpdate(
                companion.copyWith(id: Value(parseInt(w['id']))),
              );
        }
        if (globalId != null && globalId.isNotEmpty) {
          seenServerGlobalIds.add(globalId);
        }
      }
    });

    if (warehouses.isNotEmpty) {
      // Spec 150 / BUG 5b — one-shot straggler-cleanup pass for sites that
      // already accumulated duplicate "المخزن الرئيسي"-style rows from
      // earlier name-fallback matches, before the Tier 2 match above (and
      // DeltaPullService's natural-key fallback) existed to stop new ones
      // forming. Mirrors BranchSyncStrategy's byName dedup pass: among
      // rows sharing a (trimmed) name, keep the one whose globalId matches
      // this response (or, failing that, the lowest id), repoint its FKs
      // via remapWarehouseFks, then deactivate the rest. Deactivate, not
      // hard-delete — this runs unsupervised on every sync, so it uses the
      // same soft-cleanup discipline as BranchSyncStrategy instead of
      // WarehouseDedupExtension's caller-gated destructive merge.
      final allActive = await (db.select(db.warehouses)
            ..where((t) => t.isActive.equals(true)))
          .get();
      final byName = <String, List<Warehouse>>{};
      for (final wh in allActive) {
        byName.putIfAbsent(wh.name.trim(), () => []).add(wh);
      }
      await db.transaction(() async {
        for (final entry in byName.entries) {
          if (entry.value.length < 2) continue;
          final group = entry.value;
          Warehouse keeper = group.first;
          for (final wh in group) {
            final isAuthoritative = wh.globalId != null &&
                wh.globalId!.isNotEmpty &&
                seenServerGlobalIds.contains(wh.globalId);
            if (isAuthoritative) {
              keeper = wh;
              break;
            }
            if (wh.id < keeper.id) keeper = wh;
          }
          for (final wh in group) {
            if (wh.id == keeper.id) continue;
            // mergePrices: false — the loser is only deactivated, not
            // deleted, and warehouse_prices has no server→client re-sync,
            // so let its price rows follow the deactivated warehouse
            // instead of discarding them unsupervised.
            await db.remapWarehouseFks(wh.id, keeper.id, mergePrices: false);
            await (db.update(db.warehouses)..where((t) => t.id.equals(wh.id)))
                .write(const WarehousesCompanion(isActive: Value(false)));
            await DiagnosticLogger.log(
              'SYNC-WARN',
              'warehouses deduped — deactivated duplicate "${wh.name}" '
              '(localId=${wh.id} kept localId=${keeper.id}, FKs remapped).',
            );
          }
        }
      });
    }

    // Force UI refresh after sync
    if (warehouses.isNotEmpty) {
      db.markTablesUpdated({db.warehouses});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.warehouses).insertOnConflictUpdate(record as WarehousesCompanion);
  }
}