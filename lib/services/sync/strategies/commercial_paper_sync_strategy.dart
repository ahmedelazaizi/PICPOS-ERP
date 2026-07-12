// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

/// Pulls commercial papers (cheques, promissory notes, bills of exchange)
/// from the server into the local DB.
class CommercialPaperSyncStrategy extends SyncStrategy {
  CommercialPaperSyncStrategy(super.db);

  @override
  String get tableName => 'commercial_papers';

  @override
  String get apiEndpoint => '/api/commercial-papers';

  /// R5 / SYNC_ARCHITECTURE §3.2: commercial papers are transactional
  /// records (cheques / promissory notes once issued never change identity).
  /// `appendOnly` reflects the IDENTITY contract — each globalId is a
  /// one-time write, so the sync pass does insertOnConflictUpdate without
  /// firing a spurious `sync_conflict_log` entry on every refresh.
  ///
  /// 073 (D2-009): the paper STATUS (pending → collected / endorsed /
  /// cancelled) DOES change server-side. That mutation is propagated by
  /// custom code in `_syncSingle` (lines 50-62 below) which detects
  /// `existing.status != serverStatus` and explicitly issues an UPDATE.
  /// So the visible behavior is identical to `serverWins` for the status
  /// field, just routed through hand-written code rather than the
  /// strategy policy. Do not "fix" the policy to serverWins — the
  /// custom code intentionally limits the overwrite to status +
  /// endorsedToPartyId + notes, leaving immutable identity fields
  /// (paperNumber, type, partyId, amount, dueDate) protected.
  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.appendOnly;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final list = json['commercial_papers'] as List? ?? [];
    for (final item in list) {
      await _syncSingle(item as Map<String, dynamic>);
    }
    // Force UI refresh after sync
    if (list.isNotEmpty) {
      db.markTablesUpdated({db.commercialPapers});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Server-side incremental not yet implemented
  }

  Future<void> _syncSingle(Map<String, dynamic> m) async {
    try {
      final serverId = parseInt(m['id']);

      // Skip if already exists
      final existing = await (db.select(db.commercialPapers)
            ..where((c) => c.id.equals(serverId)))
          .getSingleOrNull();
      if (existing != null) {
        // Update status if it changed (papers often change status)
        final serverStatus = m['status'] as String? ?? 'pending';
        if (existing.status != serverStatus) {
          await (db.update(db.commercialPapers)
                ..where((c) => c.id.equals(serverId)))
              .write(CommercialPapersCompanion(
            status: Value(serverStatus),
            endorsedToPartyId: Value(parseIntNullable(m['endorsedToPartyId'])),
            notes: Value(m['notes'] as String?),
          ));
        }
        return;
      }

      await db.into(db.commercialPapers).insertOnConflictUpdate(
        CommercialPapersCompanion(
          id: Value(serverId),
          paperNumber: Value(m['paperNumber'] as String? ?? ''),
          type: Value(m['type'] as String? ?? 'cheque'),
          direction: Value(m['direction'] as String? ?? 'received'),
          partyId: Value(parseInt(m['partyId'])),
          amount: Value(parseDouble(m['amount'])),
          issueDate: Value(
            DateTime.tryParse(m['issueDate'] as String? ?? '') ?? DateTime.now(),
          ),
          dueDate: Value(
            DateTime.tryParse(m['dueDate'] as String? ?? '') ?? DateTime.now(),
          ),
          bankName: Value(m['bankName'] as String?),
          bankBranch: Value(m['bankBranch'] as String?),
          accountNumber: Value(m['accountNumber'] as String?),
          status: Value(m['status'] as String? ?? 'pending'),
          endorsedToPartyId: Value(parseIntNullable(m['endorsedToPartyId'])),
          notes: Value(m['notes'] as String?),
          safeId: Value(parseIntNullable(m['safeId'])),
          createdAt: Value(
            DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
          ),
        ),
      );

      // Sync status history if present
      final history = m['statusHistory'] as List? ?? [];
      for (final h in history) {
        final hm = h as Map<String, dynamic>;
        await db.into(db.paperStatusHistory).insertOnConflictUpdate(
          PaperStatusHistoryCompanion(
            id: Value(parseInt(hm['id'])),
            paperId: Value(serverId),
            fromStatus: Value(hm['fromStatus'] as String? ?? ''),
            toStatus: Value(hm['toStatus'] as String? ?? ''),
            changedAt: Value(
              DateTime.tryParse(hm['changedAt'] as String? ?? '') ?? DateTime.now(),
            ),
            changedBy: Value(parseInt(hm['changedBy'], 1)),
            notes: Value(hm['notes'] as String?),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Sync] Error in CommercialPaperSyncStrategy: $e');
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is CommercialPapersCompanion) {
      await db.into(db.commercialPapers).insertOnConflictUpdate(record);
    }
  }
}