// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

class AccountSyncStrategy extends SyncStrategy {
  AccountSyncStrategy(super.db);

  @override
  String get tableName => 'accounts';

  @override
  String get apiEndpoint => '/api/accounts';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final accounts = json['accounts'] as List;
    for (final a in accounts) {
      final serverId = parseInt(a['id']);
      final serverGlobalId = a['globalId'] as String?;
      final serverCode = a['code'] as String;

      // FIX 2026-04-28: Three-tier dedup to prevent the locally-seeded chart
      // of accounts (170+ rows) from doubling against the server's chart on
      // first DeltaPull. The `code` column is the unique business key for
      // accounting (e.g. "1010" for cash on hand), so it's the strongest
      // dedup after globalId.
      Account? existing;
      if (serverGlobalId != null && serverGlobalId.isNotEmpty) {
        existing = await (db.select(db.accounts)
              ..where((t) => t.globalId.equals(serverGlobalId)))
            .getSingleOrNull();
      }
      if (existing == null && serverCode.isNotEmpty) {
        existing = await (db.select(db.accounts)
              ..where((t) => t.code.equals(serverCode)))
            .getSingleOrNull();
      }
      existing ??= await (db.select(db.accounts)
            ..where((t) => t.id.equals(serverId)))
          .getSingleOrNull();

      final useId = existing?.id ?? serverId;
      await db.into(db.accounts).insertOnConflictUpdate(
        AccountsCompanion(
          id: Value(useId),
          code: Value(serverCode),
          name: Value(a['name'] as String),
          globalId: Value(serverGlobalId),
          accountType: Value(a['accountType'] as String),
          accountNature: Value(a['accountNature'] as String? ?? 'detail'),
          normalBalance: Value(a['normalBalance'] as String? ?? 'debit'),
          level: Value(parseInt(a['level'], 1)),
          parentId: Value(parseIntNullable(a['parentId'])),
          balance: Value(parseDouble(a['balance'])),
          isSystem: Value(parseBool(a['isSystem'], false)),
          isActive: Value(parseBool(a['isActive'], true)),
          isHiddenFromEntries:
              Value(parseBool(a['isHiddenFromEntries'], false)),
        ),
      );
    }
    // Force UI refresh after sync
    if (accounts.isNotEmpty) {
      db.markTablesUpdated({db.accounts});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db
        .into(db.accounts)
        .insertOnConflictUpdate(record as AccountsCompanion);
  }
}