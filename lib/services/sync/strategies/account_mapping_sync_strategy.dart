// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

/// Sync strategy for account_mappings — server is the sole authority.
/// Client receives these read-only; local edits are blocked via UI lock.
class AccountMappingSyncStrategy extends SyncStrategy {
  AccountMappingSyncStrategy(super.db);

  @override
  String get tableName => 'account_mappings';

  @override
  String get apiEndpoint => '/api/account-mappings';

  /// ٦‑٣ — يُخلي المفتاحَ الطبيعيَّ (‏الغرض، مركزُ التكلفة) قبل الإدراج.
  ///
  /// `insertOnConflictUpdate` مُفتاحٌ بـ`id` وحدَه. فجهازٌ عمل منفرداً ثمّ صار
  /// مرآةً يحمل ربطاً محلّيّاً `id=5` للغرض نفسِه الذي يرسله الخادمُ بـ`id=9`:
  /// الـ`id` لا يتصادم، فيُدرَج صفٌّ ثانٍ ويتعايشان. وهذا **عينُ** الازدواج
  /// الموثَّق في `accounting_dao_writes.dart` («mirror sync replays can leave
  /// more than one row per purpose key»).
  ///
  /// ⚠️ وبلا هذا الإخلاء، فهرسُ التفرّد الجديد
  /// ([kCreateAccountMappingsPurposeCcIndexSql]) كان سيقلب ازدواجاً صامتاً
  /// إلى **انهيارِ مزامنةٍ** صريحٍ عند أوّلِ سحب.
  ///
  /// والخادمُ هو السلطةُ الوحيدةُ لهذا الجدول (الصفُّ أعلاه)، فصفُّه هو الذي
  /// يبقى بلا مقارنةِ طوابعَ زمنيّة.
  Future<void> _clearNaturalKeyConflicts({
    required int id,
    required String purpose,
    required int? costCenterId,
  }) async {
    await (db.delete(db.accountMappings)
          ..where((m) {
            final sameSlot = costCenterId == null
                ? m.costCenterId.isNull()
                : m.costCenterId.equals(costCenterId);
            return m.purpose.equals(purpose) & sameSlot & m.id.equals(id).not();
          }))
        .go();
  }

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final mappings = json['account_mappings'] as List;
    for (final m in mappings) {
      final accountIdVal = parseInt(m['accountId']);
      final idVal = parseInt(m['id']);
      final purposeVal = m['purpose'] as String;
      final costCenterIdVal = parseIntNullable(m['costCenterId']);
      final updatedAtVal = m['updatedAt'] != null
          ? DateTime.tryParse(m['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now();
      await _clearNaturalKeyConflicts(
        id: idVal,
        purpose: purposeVal,
        costCenterId: costCenterIdVal,
      );
      await db.into(db.accountMappings).insertOnConflictUpdate(
        AccountMappingsCompanion(
          id: Value(idVal),
          purpose: Value(purposeVal),
          accountId: Value(accountIdVal),
          costCenterId: Value(costCenterIdVal),
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
    final companion = record as AccountMappingsCompanion;
    // نفسُ الإخلاء — `upsert` مدخلٌ ثانٍ لنفس الجدول من مسار المزامنة العامّ.
    // ولا يُخلى إلّا حين يحمل الصفُّ مفتاحَه كاملاً؛ وإلّا فلا مفتاحَ طبيعيَّ
    // يُقارَن به.
    if (companion.id.present && companion.purpose.present) {
      await _clearNaturalKeyConflicts(
        id: companion.id.value,
        purpose: companion.purpose.value,
        costCenterId: companion.costCenterId.present
            ? companion.costCenterId.value
            : null,
      );
    }
    await db.into(db.accountMappings).insertOnConflictUpdate(companion);
  }
}