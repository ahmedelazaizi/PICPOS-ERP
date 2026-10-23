// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

/// مطالباتُ الموردين — v165.
///
/// ⚠️ **`lastWriteWins` لا `appendOnly`**: المطالبةُ ليست حدثاً وقع ومضى بل
/// **حالةً تتقدّم** (‏مسوّدة ← أُرسلت ← قُبلت/رُفضت ← سُوّيت). والفرعُ ينشئها
/// والإدارةُ قد تتقدّم بحالتها، فكلاهما يكتب. والأحدثُ بـ`lastModifiedAt`
/// يفوز — و`appendOnly` كانت ستُجمّد الحالةَ على أوّلِ كاتب.
///
/// ⚠️ **ولا تحرّك مالاً**: مراسلةٌ لا قيد. وإشعارُ المورد الدائنُ حين يصل
/// يُدخَل كمستندٍ مستقلٍّ في مسارِه، ولا يُشتقّ من هذا الصفّ.
class SupplierClaimSyncStrategy extends SyncStrategy {
  SupplierClaimSyncStrategy(super.db);

  @override
  String get tableName => 'supplier_claims';

  @override
  String get apiEndpoint => '/api/supplier-claims';

  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.lastWriteWins;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final rows = json['supplier_claims'] as List? ?? [];
    for (final r in rows) {
      final map = r as Map<String, dynamic>;
      await db.into(db.supplierClaims).insertOnConflictUpdate(
            SupplierClaimsCompanion(
              id: Value(parseInt(map['id'])),
              supplierId: Value(parseInt(map['supplierId'])),
              claimDate: Value(
                  DateTime.tryParse(map['claimDate'] as String? ?? '') ??
                      DateTime.now()),
              ledgerBalance: Value(parseDouble(map['ledgerBalance'])),
              settlementKind:
                  Value(map['settlementKind'] as String? ?? 'credit_note'),
              status: Value(map['status'] as String? ?? 'draft'),
              netAmount: Value(parseDouble(map['netAmount'])),
              linesJson: Value(map['linesJson'] as String?),
              lineCount: Value(parseInt(map['lineCount'])),
              replyDueAt:
                  Value(DateTime.tryParse(map['replyDueAt'] as String? ?? '')),
              notes: Value(map['notes'] as String?),
              createdBy: Value(
                  map['createdBy'] == null ? null : parseInt(map['createdBy'])),
              globalId: Value(map['globalId'] as String?),
              lastModifiedAt: Value(
                  DateTime.tryParse(map['lastModifiedAt'] as String? ?? '')),
              deletedAt:
                  Value(DateTime.tryParse(map['deletedAt'] as String? ?? '')),
              rowVersion: Value(parseInt(map['rowVersion'])),
            ),
          );
    }

    if (rows.isNotEmpty) {
      db.markTablesUpdated({db.supplierClaims});
      debugPrint('[Sync] SupplierClaims: ${rows.length} synced');
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    if (record is SupplierClaimsCompanion) {
      await db.into(db.supplierClaims).insertOnConflictUpdate(record);
    }
  }
}
