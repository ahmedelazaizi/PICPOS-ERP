// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

class SafeSyncStrategy extends SyncStrategy {
  SafeSyncStrategy(super.db);

  @override
  String get tableName => 'safes';

  @override
  String get apiEndpoint => '/api/safes';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final safes = json['safes'] as List;
    for (final s in safes) {
      // Three-tier dedup: globalId → name → server-id. Adding the name
      // fallback prevents locally-seeded safes (صندوق الكاشير / الحساب البنكي
      // / صندوق تحويل كليك, each with auto-generated local globalIds) from
      // duplicating against their server counterparts on the very first sync.
      // Symptom WITHOUT the fallback: the safe dropdown listed every safe
      // twice and the POS expense dialog crashed with "Bad state: Too many
      // elements" when `getDefaultSafeByType('cash').getSingleOrNull()` saw
      // two default-cash safes.
      final globalId = s['globalId'] as String?;
      final safeName = s['name'] as String;
      Safe? existing;
      if (globalId != null && globalId.isNotEmpty) {
        existing = await (db.select(db.safes)
              ..where((t) => t.globalId.equals(globalId))
              ..limit(1))
            .getSingleOrNull();
      }
      if (existing == null && safeName.isNotEmpty) {
        existing = await (db.select(db.safes)
              ..where((t) => t.name.equals(safeName))
              ..limit(1))
            .getSingleOrNull();
      }

      final companion = SafesCompanion(
        name: Value(safeName),
        safeType: Value(s['safeType'] as String? ?? 'cash'),
        bankName: Value(s['bankName'] as String?),
        accountNumber: Value(s['accountNumber'] as String?),
        balance: Value(parseDouble(s['balance'])),
        branchId: Value(parseIntNullable(s['branchId'])),
        costCenterId: Value(parseIntNullable(s['costCenterId'])),
        linkedAccountId: Value(parseIntNullable(s['linkedAccountId'])),
        isDefault: Value(parseBool(s['isDefault'], false)),
        isActive: Value(parseBool(s['isActive'], true)),
        globalId: Value(globalId),
      );

      if (existing != null) {
        // Merge: keep the local id (FKs already point at it), update fields.
        await (db.update(db.safes)
              ..where((t) => t.id.equals(existing!.id)))
            .write(companion);
      } else {
        await db.into(db.safes).insertOnConflictUpdate(
              companion.copyWith(id: Value(parseInt(s['id']))),
            );
      }
    }
    // Force UI refresh after sync
    if (safes.isNotEmpty) {
      db.markTablesUpdated({db.safes});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.safes).insertOnConflictUpdate(record as SafesCompanion);
  }
}