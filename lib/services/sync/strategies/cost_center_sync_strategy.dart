// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

class CostCenterSyncStrategy extends SyncStrategy {
  CostCenterSyncStrategy(super.db);

  @override
  String get tableName => 'cost_centers';

  @override
  String get apiEndpoint => '/api/cost_centers';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final centers = json['cost_centers'] as List;
    for (final c in centers) {
      await db.into(db.costCenters).insertOnConflictUpdate(
        CostCentersCompanion(
          id: Value(parseInt(c['id'])),
          code: Value(c['code'] as String),
          name: Value(c['name'] as String),
          parentId: Value(parseIntNullable(c['parentId'])),
          isActive: Value(parseBool(c['isActive'], true)),
          createdAt: Value(
            c['createdAt'] != null
                ? DateTime.parse(c['createdAt'] as String)
                : DateTime.now(),
          ),
        ),
      );
    }
    // Force UI refresh after sync
    if (centers.isNotEmpty) {
      db.markTablesUpdated({db.costCenters});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db
        .into(db.costCenters)
        .insertOnConflictUpdate(record as CostCentersCompanion);
  }
}