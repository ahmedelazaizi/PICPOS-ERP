// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class AccountingPeriodSyncStrategy extends SyncStrategy {
  AccountingPeriodSyncStrategy(super.db);

  @override
  String get tableName => 'accounting_periods';

  @override
  String get apiEndpoint => '/api/accounting-periods';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final periods = json['accounting_periods'] as List? ?? [];
    for (final p in periods) {
      final map = p as Map<String, dynamic>;
      await db.into(db.accountingPeriods).insertOnConflictUpdate(
        AccountingPeriodsCompanion(
          id: Value(parseInt(map['id'])),
          fiscalYearId: Value(parseInt(map['fiscalYearId'])),
          name: Value(map['name'] as String? ?? ''),
          month: Value(parseInt(map['month'])),
          year: Value(parseInt(map['year'])),
          startDate: Value(DateTime.tryParse(map['startDate']?.toString() ?? '') ?? DateTime.now()),
          endDate: Value(DateTime.tryParse(map['endDate']?.toString() ?? '') ?? DateTime.now()),
          isClosed: Value(parseBool(map['isClosed'])),
          closedAt: Value(DateTime.tryParse(map['closedAt']?.toString() ?? '')),
          closedBy: Value(parseIntNullable(map['closedBy'])),
          notes: Value(map['notes'] as String?),
          createdAt: Value(DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now()),
          globalId: Value(map['globalId'] as String?),
        ),
      );
    }
    if (periods.isNotEmpty) {
      db.markTablesUpdated({db.accountingPeriods});
      debugPrint('[Sync] AccountingPeriods: ${periods.length} synced');
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    if (record is AccountingPeriodsCompanion) {
      await db.into(db.accountingPeriods).insertOnConflictUpdate(record);
    }
  }
}