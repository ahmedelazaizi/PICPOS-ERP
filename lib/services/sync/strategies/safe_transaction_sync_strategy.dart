// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class SafeTransactionSyncStrategy extends SyncStrategy {
  SafeTransactionSyncStrategy(super.db);

  @override
  String get tableName => 'safe_transactions';

  @override
  String get apiEndpoint => '/api/safe-transactions';

  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.appendOnly;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final transactions = json['transactions'] as List? ?? [];
    // Track safes that need balance recalculation
    final affectedSafeIds = <int>{};

    for (final txn in transactions) {
      final safeId = await _syncSingleTransaction(txn as Map<String, dynamic>);
      if (safeId != null) affectedSafeIds.add(safeId);
    }

    // PHASE-7 FIX: Recalculate safe balances from all transactions
    for (final safeId in affectedSafeIds) {
      await _recalculateSafeBalance(safeId);
    }
    if (affectedSafeIds.isNotEmpty) {
      debugPrint('[Sync] Recalculated balances for ${affectedSafeIds.length} safes');
    }
    // Force UI refresh after sync
    if (transactions.isNotEmpty) {
      db.markTablesUpdated({db.safeTransactions});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Full sync only for now
  }

  /// Returns the safeId if the local state changed (insert OR soft-delete
  /// replication), null otherwise. We report on soft-delete too so the
  /// caller recalculates balances — a deleted row must stop contributing.
  Future<int?> _syncSingleTransaction(Map<String, dynamic> txnMap) async {
    try {
      final serverId = parseInt(txnMap['id']);
      // Server soft-deletes set `deletedAt`. Pass it through so clients
      // can replicate admin deletions done on the server (offline-safe:
      // works on reconnect/forced-sync even if the real-time WS event was
      // missed).
      final incomingDeletedAt = DateTime.tryParse(
        txnMap['deletedAt']?.toString() ?? '',
      );

      // If already exists by server ID: update deletedAt to match server state
      final existing = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(serverId))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        if (existing.deletedAt != incomingDeletedAt) {
          await (db.update(db.safeTransactions)
                ..where((t) => t.id.equals(serverId)))
              .write(SafeTransactionsCompanion(
            deletedAt: Value(incomingDeletedAt),
          ));
          return existing.safeId; // recalc balance — state changed
        }
        return null;
      }

      // Dedup by globalId — catches locally-created transactions that the
      // server echoes back during sync (same logical transaction, different path).
      // ALSO propagate server's deletedAt to the local row, otherwise admin
      // deletes on the server never reach the client's copy.
      final incomingGlobalId = txnMap['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final byGlobalId = await (db.select(db.safeTransactions)
              ..where((t) => t.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGlobalId != null) {
          if (byGlobalId.deletedAt != incomingDeletedAt) {
            await (db.update(db.safeTransactions)
                  ..where((t) => t.globalId.equals(incomingGlobalId)))
                .write(SafeTransactionsCompanion(
              deletedAt: Value(incomingDeletedAt),
            ));
            debugPrint('[Sync] SafeTxn deletedAt updated via globalId ($incomingGlobalId) → $incomingDeletedAt');
            return byGlobalId.safeId;
          }
          debugPrint('[Sync] SafeTxn duplicate by globalId ($incomingGlobalId) — skipping');
          return null;
        }
      }

      // Dedup by (referenceType, referenceId, safeId) — fallback for
      // transactions that were created locally without a globalId but match
      // the incoming server record exactly.
      //
      // Feature 012 / Issue M-DUP-PRET: for return memos
      // (purchase_return / sales_return) the natural key is
      // (referenceType, referenceId, partyId), NOT safeId. The mirror's
      // local seed picks the global default safe at write time, while the
      // server picks per-warehouse — they often differ, so a safeId-only
      // fallback misses the dedup and the supplier statement shows the
      // return twice. Match by partyId for these categories first; fall
      // back to safeId for everything else (cash receipts/payments where
      // partyId may be null but safeId is meaningful).
      final incomingRefType = txnMap['referenceType'] as String?;
      final incomingRefId = parseIntNullable(txnMap['referenceId']);
      final incomingSafeId = parseInt(txnMap['safeId'], 1);
      final incomingPartyId = parseIntNullable(txnMap['partyId']);
      // Spec 136 (field 2026-06-14): remap server partyId → LOCAL party id, the
      // same resolution sales/purchase sync use. Without it, supplier/customer
      // payment vouchers (سند صرف/قبض) created on the server keep the server's
      // partyId on the mirror and never match the local party, so
      // getPartyStatement (filters safe_transactions by local partyId) returned
      // safeTxnRows=0 → the supplier's payments were missing from the statement.
      final resolvedPartyId =
          await resolveLocalPartyId(incomingPartyId, label: 'SafeTxn partyId');
      const returnRefTypes = {'purchase_return', 'sales_return'};
      final hasIncomingGlobalId =
          incomingGlobalId != null && incomingGlobalId.isNotEmpty;
      if (incomingRefType != null &&
          incomingRefId != null &&
          returnRefTypes.contains(incomingRefType) &&
          incomingPartyId != null) {
        // Return-memo path: reconcile the local row for this return against
        // the server's authoritative row by (refType, refId, partyId).
        //
        // Spec 136 ISS-7 — scope the match by globalId so MULTIPLE partial
        // returns on the same invoice (identical refType+refId+partyId, but a
        // distinct per-event globalId each) are NOT collapsed into one:
        //  • incoming has NO globalId (legacy): match any local row (the old
        //    Feature-012 behaviour).
        //  • incoming HAS a globalId and Tier-1 missed above: only adopt an
        //    UN-RECONCILED placeholder (globalId IS NULL). A local row that
        //    already carries a (different) globalId is a DIFFERENT return
        //    event — leave it and fall through to insert this one as a new
        //    row. Pre-fix a second device pulling two returns merged them.
        // Return types are handled here regardless of globalId so they never
        // reach the generic (refType,refId,safeId) merge below (which would
        // re-introduce the same collapse).
        final byRefAndParty = await (db.select(db.safeTransactions)
              ..where((t) {
                var cond = t.referenceType.equals(incomingRefType) &
                    t.referenceId.equals(incomingRefId) &
                    t.partyId.isIn(
                        {resolvedPartyId, incomingPartyId}.whereType<int>().toList());
                if (hasIncomingGlobalId) cond = cond & t.globalId.isNull();
                return cond;
              })
              ..limit(1))
            .getSingleOrNull();
        if (byRefAndParty != null) {
          await (db.update(db.safeTransactions)
                ..where((t) => t.id.equals(byRefAndParty.id)))
              .write(SafeTransactionsCompanion(
            voucherNumber: Value(txnMap['voucherNumber'] as String? ??
                byRefAndParty.voucherNumber),
            safeId: Value(incomingSafeId),
            globalId: Value(incomingGlobalId ?? byRefAndParty.globalId),
            description: Value(
                txnMap['description'] as String? ?? byRefAndParty.description),
            deletedAt: Value(incomingDeletedAt),
          ));
          debugPrint('[Sync] SafeTxn return-memo dedup '
              '($incomingRefType #$incomingRefId party=$incomingPartyId) — '
              'updated local row id=${byRefAndParty.id} with server identifiers');
          return byRefAndParty.safeId == incomingSafeId
              ? byRefAndParty.safeId
              : null; // recalc only the original safe; new safeId rows are added separately
        }
      } else if (incomingRefType != null && incomingRefId != null) {
        final byRef = await (db.select(db.safeTransactions)
              ..where((t) =>
                  t.referenceType.equals(incomingRefType) &
                  t.referenceId.equals(incomingRefId) &
                  t.safeId.equals(incomingSafeId))
              ..limit(1))
            .getSingleOrNull();
        if (byRef != null) {
          debugPrint('[Sync] SafeTxn duplicate by ref ($incomingRefType #$incomingRefId safe=$incomingSafeId) — skipping');
          return null;
        }
      }

      // incomingSafeId already holds parseInt(txnMap['safeId'], 1) — reuse it
      final amount = parseDouble(txnMap['amount']);
      final balanceAfter = parseDouble(txnMap['balanceAfter']);

      await db.into(db.safeTransactions).insertOnConflictUpdate(
            SafeTransactionsCompanion(
              id: Value(serverId),
              voucherNumber: Value(txnMap['voucherNumber'] as String? ?? 'SYNC-$serverId'),
              safeId: Value(incomingSafeId),
              transactionType: Value(txnMap['transactionType'] as String? ?? 'receipt'),
              category: Value(txnMap['category'] as String? ?? 'general'),
              amount: Value(amount),
              discount: Value(parseDouble(txnMap['discount'])),
              balanceAfter: Value(balanceAfter),
              referenceType: Value(txnMap['referenceType'] as String?),
              referenceId: Value(parseIntNullable(txnMap['referenceId'])),
              partyId: Value(resolvedPartyId),
              description: Value(txnMap['description'] as String? ?? txnMap['notes'] as String?),
              userId: Value(parseIntNullable(txnMap['userId'])),
              costCenterId: Value(parseIntNullable(txnMap['costCenterId'])),
               currencyId: Value(parseIntNullable(txnMap['currencyId'])),
               exchangeRate: Value(parseDoubleNullable(txnMap['exchangeRate'])),
               foreignAmount: Value(parseDoubleNullable(txnMap['foreignAmount'])),
              employeeId: Value(parseIntNullable(txnMap['employeeId'])),
              disbursementType: Value(txnMap['disbursementType'] as String?),
              globalId: Value(incomingGlobalId), // Preserve UUID from server
              deletedAt: Value(incomingDeletedAt),
              createdAt: Value(DateTime.tryParse(txnMap['createdAt']?.toString() ?? '') ?? DateTime.now()),
            ),
          );

      return incomingSafeId; // Signal that this safe needs balance recalculation
    } catch (e) {
      debugPrint('[Sync] Error in SafeTransactionSyncStrategy: $e');
      return null;
    }
  }

  /// PHASE-7 FIX: Recalculate safe balance from all its transactions
  /// Sum receipts and subtract disbursements to get the net balance
  Future<void> _recalculateSafeBalance(int safeId) async {
    try {
      final transactions = await (db.select(db.safeTransactions)
            ..where((t) => t.safeId.equals(safeId) & t.deletedAt.isNull()))
          .get();

      double balance = 0;
      for (final txn in transactions) {
        // 'closing' transactions are audit records only — they do NOT affect the balance.
        // The actual balance change is handled by 'withdrawal' (from _closeShiftSafes).
        if (txn.transactionType == 'closing') continue;

        if (txn.transactionType == 'receipt') {
          balance += txn.amount;
        } else {
          balance -= txn.amount;
        }
      }

      await (db.update(db.safes)..where((s) => s.id.equals(safeId))).write(
        SafesCompanion(balance: Value(balance)),
      );
      debugPrint('[Sync] Safe #$safeId balance recalculated: $balance');
    } catch (e) {
      debugPrint('[Sync] Error recalculating safe $safeId balance: $e');
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is SafeTransactionsCompanion) {
      await db.into(db.safeTransactions).insertOnConflictUpdate(record);
    }
  }
}