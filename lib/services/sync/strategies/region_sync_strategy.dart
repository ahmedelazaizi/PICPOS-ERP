// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

class RegionSyncStrategy extends SyncStrategy {
  RegionSyncStrategy(super.db);

  @override
  String get tableName => 'regions';

  @override
  String get apiEndpoint => '/api/regions';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final regionsList = json['regions'] as List;
    for (final r in regionsList) {
      await db.into(db.regions).insertOnConflictUpdate(
        RegionsCompanion(
          id: Value(parseInt(r['id'])),
          name: Value(r['name'] as String),
          address: Value(r['address'] as String?),
          phone: Value(r['phone'] as String?),
          isActive: Value(parseBool(r['isActive'], true)),
          costCenterId: Value(parseIntNullable(r['costCenterId'])),
          globalId: Value(r['globalId'] as String?),
        ),
      );
    }
    // Force UI refresh after sync
    if (regionsList.isNotEmpty) {
      db.markTablesUpdated({db.regions});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.regions).insertOnConflictUpdate(record as RegionsCompanion);
  }
}