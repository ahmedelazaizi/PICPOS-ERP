// ignore_for_file: avoid_dynamic_calls
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/core/utils/financial_utils.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class JournalSyncStrategy extends SyncStrategy {
  JournalSyncStrategy(super.db);

  @override
  String get tableName => 'journals';

  @override
  String get apiEndpoint => '/api/journals';

  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.appendOnly;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final journals = json['journals'] as List? ?? [];
    final affectedAccountIds = <int>{};

    for (final entry in journals) {
      final ids = await _syncSingleEntry(entry as Map<String, dynamic>);
      affectedAccountIds.addAll(ids);
    }

    // PHASE-7 FIX: Batch-recalculate account balances for all affected accounts
    for (final accountId in affectedAccountIds) {
      await _recalculateAccountBalance(accountId);
    }
    if (affectedAccountIds.isNotEmpty) {
      debugPrint('[Sync] Recalculated balances for ${affectedAccountIds.length} accounts');
    }
    // Force UI refresh after sync
    if (journals.isNotEmpty) {
      db.markTablesUpdated({db.journalEntries, db.journalEntryLines});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Full sync only for now
  }

  /// Returns the set of affected account IDs for balance recalculation
  Future<Set<int>> _syncSingleEntry(Map<String, dynamic> entryMap) async {
    final affectedIds = <int>{};
    try {
      final serverId = parseInt(entryMap['id']);

      // Phase 5B.2 — Tier 0: globalId match. The voucher fix in 5B.1
      // makes both client and server compute the SAME deterministic JE
      // globalId for the same logical voucher (`je-rcpt-<g>` /
      // `je-pmt-<g>`), so the inbound JE here has a globalId we already
      // wrote locally. Without this tier, the strategy fell through to
      // Tier 1 (server id, never matches) and then Tier 2
      // (referenceType+referenceId — also doesn't match because each
      // side keeps its own safe_transactions autoincrement), inserting
      // a phantom duplicate JE in the General Ledger.
      final entryGlobalId = entryMap['globalId'] as String?;
      if (entryGlobalId != null && entryGlobalId.isNotEmpty) {
        final byGlobal = await (db.select(db.journalEntries)
              ..where((e) => e.globalId.equals(entryGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGlobal != null) {
          debugPrint('[Sync] JE globalId match — skip duplicate insert '
              '(local id=${byGlobal.id}, server id=$serverId, globalId=$entryGlobalId)');
          return affectedIds;
        }
      }

      // Skip if already exists (by server ID)
      final existing = await (db.select(db.journalEntries)
            ..where((e) => e.id.equals(serverId))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) return affectedIds;

      // Also skip if a local JE for the same reference already exists
      // (prevents duplicates when client creates JE locally then syncs server copy)
      final refType = entryMap['referenceType'] as String?;
      final refId = parseIntNullable(entryMap['referenceId']);
      if (refType != null && refId != null) {
        // Check both reference type variants (e.g., 'purchase' and 'purchase_invoice')
        final refTypes = <String>[refType];
        if (refType == 'purchase') refTypes.add('purchase_invoice');
        if (refType == 'purchase_invoice') refTypes.add('purchase');
        if (refType == 'sale') refTypes.add('sales_invoice');
        if (refType == 'sales_invoice') refTypes.add('sale');

        for (final rt in refTypes) {
          final byRef = await (db.select(db.journalEntries)
                ..where((e) =>
                    e.referenceType.equals(rt) &
                    e.referenceId.equals(refId) &
                    e.isAutoPosted.equals(true))
                ..limit(1))
              .getSingleOrNull();
          if (byRef != null) {
            debugPrint('[Sync] Skipping journal #$serverId — $rt ref=$refId already exists locally as id=${byRef.id}');
            return affectedIds;
          }
        }
      }

      // PHASE-8: Validate double-entry balance before inserting
      final lines = entryMap['lines'] as List? ?? [];
      double totalDebit = 0;
      double totalCredit = 0;
      for (final line in lines) {
        final lineMap = line as Map<String, dynamic>;
        totalDebit += parseDouble(lineMap['debit']);
        totalCredit += parseDouble(lineMap['credit']);
      }
      // Spec 139 (L1) — reference the single balance-tolerance source of truth
      // instead of a hardcoded 0.01, so inbound-JE validation tracks the cap.
      if ((totalDebit - totalCredit).abs() > FinancialUtils.balanceTolerance) {
        final diff = (totalDebit - totalCredit).abs();
        // PHASE-8+: Clear alert for review — both console and conflict log
        print('╔══════════════════════════════════════════════════════════════╗');
        print('║  ⚠️  تنبيه: قيد محاسبي غير متوازن وارد من السيرفر!            ║');
        print('║  رقم القيد: $serverId                                        ║');
        print('║  المدين: $totalDebit | الدائن: $totalCredit | الفرق: $diff    ║');
        print('║  ← تم رفض القيد وتسجيله — يرجى مراجعته على السيرفر          ║');
        print('╚══════════════════════════════════════════════════════════════╝');
        debugPrint('[Sync] ⚠️ REJECTED unbalanced journal #$serverId: debit=$totalDebit, credit=$totalCredit, diff=$diff');
        try {
          await db.into(db.syncConflictLog).insert(
            SyncConflictLogCompanion.insert(
              conflictTable: 'journals',
              recordId: serverId.toString(),
              resolution: 'skipped',
              clientPayload: entryMap.toString(),
              reason: Value('⚠️ قيد غير متوازن يحتاج مراجعة: مدين=$totalDebit, دائن=$totalCredit, الفرق=$diff'),
            ),
          );
        } catch (_) {}
        return affectedIds;
      }

      // Cluster 028 / Bug 2: remap the server's costCenterId to the local
      // cost-center id so the JE shows up under the right cost center on
      // the mirror. Same pattern as `_resolveLocalAccountId` (Issue 11)
      // — without it, the server's id is inserted verbatim and the
      // mirror's display picks a DIFFERENT cost center because the local
      // ids drifted from the server's.
      final headerLocalCcId = await _resolveLocalCostCenterId(
        serverCostCenterId: parseIntNullable(entryMap['costCenterId']),
        costCenterGlobalId: entryMap['costCenterGlobalId'] as String?,
        costCenterCode: entryMap['costCenterCode'] as String?,
      );

      // PHASE-7 FIX: Server entries are already approved/posted — set isPosted = true
      // Phase 5B.2 — also persist the JE's globalId so subsequent pulls
      // can dedup via Tier 0 above instead of falling through.
      await db.into(db.journalEntries).insertOnConflictUpdate(
            JournalEntriesCompanion(
              id: Value(serverId),
              entryNumber: Value(entryMap['entryNumber'] as String? ?? 'SYNC-$serverId'),
              description: Value(entryMap['description'] as String?),
              entryDate: Value(DateTime.tryParse(entryMap['entryDate']?.toString() ?? '') ?? DateTime.now()),
              referenceType: Value(entryMap['referenceType'] as String?),
              referenceId: Value(parseIntNullable(entryMap['referenceId'])),
              isAutoPosted: Value(parseBool(entryMap['isAutoPosted'], true)),
              isPosted: const Value(true), // PHASE-7: Always posted from server
              needsApproval: const Value(false), // PHASE-7: Already approved on server
              costCenterId: Value(headerLocalCcId),
              branchId: Value(parseIntNullable(entryMap['branchId'])),
              createdAt: Value(DateTime.tryParse(entryMap['createdAt']?.toString() ?? '') ?? DateTime.now()),
              globalId: entryGlobalId != null && entryGlobalId.isNotEmpty
                  ? Value(entryGlobalId)
                  : const Value.absent(),
            ),
          );

      // Insert the journal entry lines (using lines already parsed above).
      //
      // Issue 11 — remap server accountId → local accountId. The chart of
      // accounts is seeded independently on each side, so the same business
      // account (e.g. code "1010") commonly has different numeric ids on
      // server vs. client. AccountSyncStrategy uses the local id when an
      // account already exists by code/globalId; if we trust the server's
      // numeric accountId blindly here, the line either points to a wrong
      // account or to nothing (broken FK), which is why the journal-entries
      // screen showed empty debit/credit columns on the client.
      for (final line in lines) {
        final lineMap = line as Map<String, dynamic>;
        final serverAccountId = parseInt(lineMap['accountId']);
        final localAccountId = await _resolveLocalAccountId(
          serverAccountId: serverAccountId,
          accountGlobalId: lineMap['accountGlobalId'] as String?,
          accountCode: lineMap['accountCode'] as String?,
        );
        // Cluster 028 / Bug 2: same cost-center remap on each line.
        final lineLocalCcId = await _resolveLocalCostCenterId(
          serverCostCenterId: parseIntNullable(lineMap['costCenterId']),
          costCenterGlobalId: lineMap['costCenterGlobalId'] as String?,
          costCenterCode: lineMap['costCenterCode'] as String?,
        );
        await db.into(db.journalEntryLines).insertOnConflictUpdate(
              JournalEntryLinesCompanion(
                id: Value(parseInt(lineMap['id'])),
                entryId: Value(serverId),
                accountId: Value(localAccountId),
                debit: Value(parseDouble(lineMap['debit'])),
                credit: Value(parseDouble(lineMap['credit'])),
                description: Value(lineMap['description'] as String?),
                costCenterId: Value(lineLocalCcId),
              ),
            );
        affectedIds.add(localAccountId);
      }
    } catch (e) {
      debugPrint('[Sync] Error in JournalSyncStrategy: $e');
    }
    return affectedIds;
  }

  /// Resolve a server-side account id to the corresponding local account id,
  /// preferring globalId match, then code match, and finally falling back to
  /// the raw server id. Returns the server id unchanged when no local row
  /// matches — that keeps the row insertable but lets a later accounts pull
  /// reconcile it. See Issue 11 for the failure mode this prevents.
  ///
  /// Phase 5B.3 — when no local match is found AND we have an account
  /// globalId or code to identify with, log a `[SYNC-WARN]` (visible to
  /// the operator via DiagnosticLogger callers) so the field can spot
  /// silent account-mapping drift. The orphan-JE diagnostic in 5B.7
  /// surfaces the resulting unresolved lines on demand.
  Future<int> _resolveLocalAccountId({
    required int serverAccountId,
    String? accountGlobalId,
    String? accountCode,
  }) async {
    if (accountGlobalId != null && accountGlobalId.isNotEmpty) {
      final byGlobal = await (db.select(db.accounts)
            ..where((a) => a.globalId.equals(accountGlobalId))
            ..limit(1))
          .getSingleOrNull();
      if (byGlobal != null) return byGlobal.id;
    }
    if (accountCode != null && accountCode.isNotEmpty) {
      final byCode = await (db.select(db.accounts)
            ..where((a) => a.code.equals(accountCode))
            ..limit(1))
          .getSingleOrNull();
      if (byCode != null) return byCode.id;
    }

    // Spec 117 (Bug A) — defensive placeholder upsert.
    // قبل ترك الـ JE line orphaned بـ serverId غير صالح، أنشئ account
    // placeholder بالـ info المُرسَلة من السيرفر. الـ next accounts pull
    // سيستبدل name/type بالقيم الحقيقية، والـ JE line ستظل تشير لنفس الـ
    // local id (الـ globalId/code يبقيان ثابتَين).
    //
    // هذا يُصلح "السند لا يظهر في دفتر الأستاذ" — السبب: orphan FK
    // إلى account.id لا يوجد محلياً → التقارير لا تجمع الـ line.
    if (accountCode != null && accountCode.isNotEmpty) {
      try {
        await db.into(db.accounts).insertOnConflictUpdate(
          AccountsCompanion(
            id: Value(serverAccountId),
            code: Value(accountCode),
            name: Value('حساب $accountCode'),
            accountType: const Value('asset'),
            globalId: accountGlobalId != null && accountGlobalId.isNotEmpty
                ? Value(accountGlobalId)
                : const Value.absent(),
          ),
        );
        unawaited(DiagnosticLogger.log('SYNC-WARN',
            'Spec 117 Bug A — created placeholder account '
            'id=$serverAccountId code=$accountCode globalId=$accountGlobalId — '
            'real data will arrive on next accounts pull.'));
        return serverAccountId;
      } catch (e) {
        unawaited(DiagnosticLogger.log('SYNC-WARN',
            'Spec 117 Bug A — placeholder account insert failed for '
            'serverAccountId=$serverAccountId code=$accountCode: $e — falling back'));
      }
    }

    // 073 (D2-007): use DiagnosticLogger so the warn survives release builds.
    unawaited(DiagnosticLogger.log('SYNC-WARN',
        '_resolveLocalAccountId: no local match for '
        'serverAccountId=$serverAccountId code=$accountCode '
        'globalId=$accountGlobalId — line will reference server id '
        '(may appear orphaned in GL until accounts pull catches up)'));
    return serverAccountId;
  }

  /// Cluster 028 / Bug 2: resolve a server-side cost-center id to the
  /// local cost-center id. Mirrors `_resolveLocalAccountId`. Tries
  /// globalId first (strongest), then code, and falls back to the raw
  /// server id when neither is provided. Returns `null` when the input
  /// is null. The fallback path emits a `[SYNC-WARN]` diagnostic so
  /// silent drift is visible in field logs.
  Future<int?> _resolveLocalCostCenterId({
    required int? serverCostCenterId,
    String? costCenterGlobalId,
    String? costCenterCode,
  }) async {
    if (serverCostCenterId == null) return null;
    if (costCenterGlobalId != null && costCenterGlobalId.isNotEmpty) {
      final byGlobal = await (db.select(db.costCenters)
            ..where((c) => c.globalId.equals(costCenterGlobalId))
            ..limit(1))
          .getSingleOrNull();
      if (byGlobal != null) return byGlobal.id;
    }
    if (costCenterCode != null && costCenterCode.isNotEmpty) {
      final byCode = await (db.select(db.costCenters)
            ..where((c) => c.code.equals(costCenterCode))
            ..limit(1))
          .getSingleOrNull();
      if (byCode != null) return byCode.id;
    }
    // 073 (D2-007): use DiagnosticLogger so the warn survives release builds.
    unawaited(DiagnosticLogger.log('SYNC-WARN',
        '_resolveLocalCostCenterId: no local match for '
        'serverCostCenterId=$serverCostCenterId code=$costCenterCode '
        'globalId=$costCenterGlobalId — JE will reference server id '
        '(may show up under a different cost center until cost-centers pull catches up)'));
    return serverCostCenterId;
  }

  /// Recalculate account balance from all posted journal entries (IAS 1 compliant)
  /// Mirrors the logic in AccountingWritesMixin._updateAccountBalance
  Future<void> _recalculateAccountBalance(int accountId) async {
    try {
      final debitCol = db.journalEntryLines.debit.sum();
      final creditCol = db.journalEntryLines.credit.sum();
      final query = db.selectOnly(db.journalEntryLines).join([
        innerJoin(db.journalEntries, db.journalEntries.id.equalsExp(db.journalEntryLines.entryId)),
      ]);
      query.addColumns([debitCol, creditCol]);
      query.where(
        db.journalEntryLines.accountId.equals(accountId) &
        db.journalEntries.isPosted.equals(true),
      );
      final row = await query.getSingleOrNull();
      final totalDebit = row?.read(debitCol) ?? 0.0;
      final totalCredit = row?.read(creditCol) ?? 0.0;
      final computedBalance = totalDebit - totalCredit;
      await (db.update(db.accounts)..where((a) => a.id.equals(accountId))).write(
        AccountsCompanion(balance: Value(computedBalance)),
      );
    } catch (e) {
      debugPrint('[Sync] Error recalculating balance for account $accountId: $e');
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is JournalEntriesCompanion) {
      await db.into(db.journalEntries).insertOnConflictUpdate(record);
    }
  }
}