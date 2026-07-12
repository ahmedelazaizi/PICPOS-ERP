// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

/// Sync strategy for account_mappings — server is the sole authority.
/// Client receives these read-only; local edits are blocked via UI lock.
class AccountMappingSyncStrategy extends SyncStrategy {
  AccountMappingSyncStrategy(super.db);

  @override
  String get tableName => 'account_mappings';

  @override
  String get apiEndpoint => '/api/account-mappings';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final mappings = json['account_mappings'] as List;
    for (final m in mappings) {
      final accountIdVal = parseInt(m['accountId']);
      final updatedAtVal = m['updatedAt'] != null
          ? DateTime.tryParse(m['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now();
      await db.into(db.accountMappings).insertOnConflictUpdate(
        AccountMappingsCompanion(
          id: Value(parseInt(m['id'])),
          purpose: Value(m['purpose'] as String),
          accountId: Value(accountIdVal),
          costCenterId: Value(parseIntNullable(m['costCenterId'])),
          description: Value(m['description'] as String?),
          updatedAt: Value(updatedAtVal),
        ),
      );
    }
    // Force UI refresh after sync
    if (mappings.isNotEmpty) {
      db.markTablesUpdated({db.accountMappings});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.accountMappings).insertOnConflictUpdate(
      record as AccountMappingsCompanion,
    );
  }
}