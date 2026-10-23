// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

/// متابعاتُ التحصيل — v165.
///
/// ⚠️ **`appendOnly` لا `serverWins`**: كلُّ صفٍّ **حدثٌ وقع** — مكالمةٌ جرت
/// في وقتٍ بعينه. ولا يُعاد كتابتُه من الخادم لأنّ الخادمَ لم يشهدها. وما
/// يتغيّر لاحقاً (حذفٌ ناعم) يعبر بعمود `deletedAt` لا بإبدال الصفّ.
///
/// ⚠️ **ولا يحرّك مالاً**: لا خزنةَ ولا ذمّةَ ولا قيد. فلا شيءَ يُعاد حسابُه
/// بعد المزامنة — بخلاف `PaymentAllocationSyncStrategy` التي تُحدّث `paid`.
class PartyFollowUpSyncStrategy extends SyncStrategy {
  PartyFollowUpSyncStrategy(super.db);

  @override
  String get tableName => 'party_follow_ups';

  @override
  String get apiEndpoint => '/api/party-follow-ups';

  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.appendOnly;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final rows = json['party_follow_ups'] as List? ?? [];
    for (final r in rows) {
      final map = r as Map<String, dynamic>;
      await db.into(db.partyFollowUps).insertOnConflictUpdate(
            PartyFollowUpsCompanion(
              id: Value(parseInt(map['id'])),
              partyId: Value(parseInt(map['partyId'])),
              invoiceId: Value(map['invoiceId'] == null
                  ? null
                  : parseInt(map['invoiceId'])),
              invoiceNumber: Value(map['invoiceNumber'] as String?),
              amountDue: Value(parseDouble(map['amountDue'])),
              contactedAt: Value(
                  DateTime.tryParse(map['contactedAt'] as String? ?? '') ??
                      DateTime.now()),
              outcome: Value(map['outcome'] as String? ?? 'no_answer'),
              promisedDate:
                  Value(DateTime.tryParse(map['promisedDate'] as String? ?? '')),
              promisedAmount: Value(map['promisedAmount'] == null
                  ? null
                  : parseDouble(map['promisedAmount'])),
              contactPerson: Value(map['contactPerson'] as String?),
              nextActionAt:
                  Value(DateTime.tryParse(map['nextActionAt'] as String? ?? '')),
              notes: Value(map['notes'] as String?),
              createdBy: Value(
                  map['createdBy'] == null ? null : parseInt(map['createdBy'])),
              globalId: Value(map['globalId'] as String?),
              deletedAt:
                  Value(DateTime.tryParse(map['deletedAt'] as String? ?? '')),
              rowVersion: Value(parseInt(map['rowVersion'])),
            ),
          );
    }

    if (rows.isNotEmpty) {
      db.markTablesUpdated({db.partyFollowUps});
      debugPrint('[Sync] PartyFollowUps: ${rows.length} synced');
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    if (record is PartyFollowUpsCompanion) {
      await db.into(db.partyFollowUps).insertOnConflictUpdate(record);
    }
  }
}
