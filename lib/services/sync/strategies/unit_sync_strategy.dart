// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

class UnitSyncStrategy extends SyncStrategy {
  UnitSyncStrategy(super.db);

  @override
  String get tableName => 'units';

  @override
  String get apiEndpoint => '/api/units';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final units = json['units'] as List;
    for (final u in units) {
      final serverId = parseInt(u['id']);
      final serverGlobalId = u['globalId'] as String?;
      final serverName = u['name'] as String;
      final serverSymbol = u['symbol'] as String? ?? serverName;

      // FIX 2026-04-28: Three-tier dedup to prevent duplicates after first
      // DeltaPull. Locally-seeded units (قطعة, كيلو, ...) have local globalIds
      // that differ from the server's, so naive insertOnConflictUpdate would
      // create twin rows.
      Unit? existing;
      if (serverGlobalId != null && serverGlobalId.isNotEmpty) {
        existing = await (db.select(db.units)
              ..where((t) => t.globalId.equals(serverGlobalId)))
            .getSingleOrNull();
      }
      existing ??= await (db.select(db.units)
              ..where((t) => t.name.equals(serverName)))
            .getSingleOrNull();
      existing ??= await (db.select(db.units)
            ..where((t) => t.id.equals(serverId)))
          .getSingleOrNull();

      final useId = existing?.id ?? serverId;
      await db.into(db.units).insertOnConflictUpdate(
        UnitsCompanion(
          id: Value(useId),
          name: Value(serverName),
          symbol: Value(serverSymbol),
          globalId: Value(serverGlobalId),
        ),
      );
    }
    // Force UI refresh after sync
    if (units.isNotEmpty) {
      db.markTablesUpdated({db.units});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.units).insertOnConflictUpdate(record as UnitsCompanion);
  }
}