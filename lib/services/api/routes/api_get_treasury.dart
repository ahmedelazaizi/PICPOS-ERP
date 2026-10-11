// ApiHandler - safes, shifts, journals, commercial papers, payments, account mappings (GET).
part of '../api_handler.dart';

/// safes, shifts, journals, commercial papers, payments, account mappings (GET) (see [ApiHandler]).
extension ApiHandlerTreasuryGets on ApiHandler {
  // ═══════════════════════════════════════════════════════════════
  // Safes (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSafes(Request request) async {
    try {
      final branchId = await _extractBranchId(request);
      final query = _db.select(_db.safes);
      if (branchId != null) {
        query.where((s) => s.branchId.equals(branchId) | s.branchId.isNull());
      }
      final safes = await query.get();

      // ── هويّةُ الحساب المرتبط تُرسَل معه ────────────────────────────────
      //
      // 🔴 كانت الحمولةُ تحمل `linkedAccountId` **رقماً خامّاً من الخادم**
      // وحدَه. ودليلُ الحسابات يُزرع على كلِّ طرفٍ مستقلّاً، فنفسُ الحساب
      // يحمل مُعرِّفاً رقميّاً مختلفاً على الخادم وعلى العميل — ولهذا
      // `JournalSyncStrategy` تترجم **كلَّ** سطرِ قيدٍ بـglobalId/code.
      // وجدولُ الخزائن كان الوحيدَ المشيرَ إلى الحسابات بلا ترجمة.
      //
      // والأثرُ كان شكليّاً ما دام لا قيدَ يمرّ عبر هذا الحقل. ومع توجيه
      // رِجْلِ كلِّ قيدِ خزنةٍ إليه يصير خطأُ الترجمة **ترحيلاً خاطئاً
      // منهجيّاً على كلِّ جهاز** — وهو أصعبُ كشفاً من العطب الذي نُصلحه.
      //
      // فتُرسَل الهويّةُ المستقرّةُ معه. وعميلٌ قديمٌ يتجاهل الحقلَين،
      // وخادمٌ قديمٌ لا يرسلهما فيسقط العميلُ إلى السلوك السابق — أي أنّ
      // الإضافةَ متوافقةٌ في الاتّجاهَين.
      final linkedIds =
          safes.map((s) => s.linkedAccountId).whereType<int>().toSet();
      final linkedAccounts = <int, Account>{};
      if (linkedIds.isNotEmpty) {
        for (final acc in await (_db.select(_db.accounts)
              ..where((a) => a.id.isIn(linkedIds.toList())))
            .get()) {
          linkedAccounts[acc.id] = acc;
        }
      }

      final jsonList = safes
          .map(
            (s) => <String, dynamic>{
              'id': s.id,
              'name': s.name,
              'safeType': s.safeType,
              'bankName': s.bankName,
              'accountNumber': s.accountNumber,
              'balance': s.balance,
              'branchId': s.branchId,
              'costCenterId': s.costCenterId,
              'linkedAccountId': s.linkedAccountId,
              'linkedAccountGlobalId':
                  linkedAccounts[s.linkedAccountId]?.globalId,
              'linkedAccountCode': linkedAccounts[s.linkedAccountId]?.code,
              'isDefault': s.isDefault,
              'isActive': s.isActive,
            },
          )
          .toList();
      return _json({'safes': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch safes');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Shifts (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getShifts(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final query = _db.select(_db.shifts);
      
      if (branchId != null) {
        final scopedUserIds = await _resolveScopedUserIds(branchId);
        if (scopedUserIds.isNotEmpty) {
          query.where((s) => s.userId.isIn(scopedUserIds));
        } else {
          query.where((s) => s.userId.equals(-1)); // Return nothing if no users accessible
        }
      }
      
      final shifts = await query.get();
      final jsonList = shifts
          .map(
            (s) => <String, dynamic>{
              'id': s.id,
              'startTime': s.startTime.toIso8601String(),
              'endTime': s.endTime?.toIso8601String(),
              'userId': s.userId,
              'openingBalance': s.openingBalance,
              'expectedCash': s.expectedCash,
              'actualCash': s.actualCash,
              'variance': s.variance,
              'status': s.status,
              'notes': s.notes,
              // v151 — the closing report's stored figures, so a pulling
              // client can reprint a shift closed on another terminal.
              'closingSnapshot': s.closingSnapshot,
              'createdAt': s.createdAt.toIso8601String(),
              // Spec 008 / FR-001: surface the recorded operating branch so
              // pulling clients see it via shift_sync_strategy.
              'branchId': s.branchId,
              // Spec 029 / US3 Bug B: surface globalId + lastModifiedAt so
              // ShiftSyncStrategy can dedup by globalId (Tier 1) and apply
              // the lastWriteWins comparison + open-shift carve-out without
              // having to invent a synthetic timestamp from startTime.
              'globalId': s.globalId,
              'lastModifiedAt': s.lastModifiedAt?.toIso8601String(),
            },
          )
          .toList();
      return _json({'shifts': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch shifts');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Safe Transactions (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSafeTransactions(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final safeIds = branchId != null ? await _resolveBranchSafeIds(branchId) : null;
      final query = _db.select(_db.safeTransactions)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
      if (safeIds != null && safeIds.isNotEmpty) {
        query.where((t) => t.safeId.isIn(safeIds));
      }
      final txns = await query.get();

      final jsonList = txns
          .map(
            (t) => <String, dynamic>{
              'id': t.id,
              'voucherNumber': t.voucherNumber,
              'safeId': t.safeId,
              'transactionType': t.transactionType,
              'category': t.category,
              'amount': t.amount,
              'discount': t.discount,
              'balanceAfter': t.balanceAfter,
              'referenceType': t.referenceType,
              'referenceId': t.referenceId,
              'partyId': t.partyId,
              'description': t.description,
              'userId': t.userId,
              'costCenterId': t.costCenterId,
              'employeeId': t.employeeId,
              'disbursementType': t.disbursementType,
               'currencyId': t.currencyId,
               'exchangeRate': t.exchangeRate,
               'foreignAmount': t.foreignAmount,
              // Carry globalId so clients can dedupe/match by UUID across
              // installs, and deletedAt so client-side pull can replicate
              // admin soft-deletes done on the server.
              'globalId': t.globalId,
              'deletedAt': t.deletedAt?.toIso8601String(),
              'createdAt': t.createdAt.toIso8601String(),
            },
          )
          .toList();

      return _json({'transactions': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getSafeTransactions error: $e');
      return ApiErrors.fail(e, 'Failed to fetch safe transactions');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Journal Entries (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getJournalEntries(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final query = _db.select(_db.journalEntries);
      if (branchId != null) {
        query.where((e) => e.branchId.equals(branchId));
      }
      final entries = await query.get();
      final jsonList = <Map<String, dynamic>>[];

      // Cluster 028 / Bug 2: pre-load cost-center identity so each JE
      // line can carry `costCenterCode` + `costCenterGlobalId` alongside
      // the raw `costCenterId`. Without these the mirror's sync strategy
      // could only insert the server's numeric id as-is, and any local
      // cost-center id drift (cost centers seeded independently on each
      // side, same code → different ids) made the JE show up under the
      // WRONG cost center on the mirror after the next DeltaPull.
      final allCostCenters = await _db.select(_db.costCenters).get();
      final costCenterById = {for (final c in allCostCenters) c.id: c};

      for (final entry in entries) {
        // JOIN with accounts so each line carries the account's `code` and
        // `globalId`. The client uses these to remap to its local account id
        // (server and client account ids diverge: the chart of accounts is
        // seeded independently on each side, then deduped by code). Without
        // the code, the client's INNER-JOIN against accounts on display
        // filters out every line — Issue 11 (empty journals on client).
        final linesQuery = _db.select(_db.journalEntryLines).join([
          leftOuterJoin(_db.accounts,
              _db.accounts.id.equalsExp(_db.journalEntryLines.accountId)),
        ])
          ..where(_db.journalEntryLines.entryId.equals(entry.id))
          ..orderBy([OrderingTerm.asc(_db.journalEntryLines.id)]);
        final lineRows = await linesQuery.get();
        final headerCc =
            entry.costCenterId != null ? costCenterById[entry.costCenterId] : null;

        jsonList.add({
          'id': entry.id,
          // Phase 5B.2 — ship the JE's globalId so the client's
          // JournalSyncStrategy can dedup deterministically by Tier 0
          // globalId before falling back to the legacy server-id /
          // referenceType-referenceId tiers. Critical for the Phase 5B.1
          // voucher fix to actually dedup across sides.
          'globalId': entry.globalId,
          'entryNumber': entry.entryNumber,
          'description': entry.description,
          'entryDate': entry.entryDate.toIso8601String(),
          'referenceType': entry.referenceType,
          'referenceId': entry.referenceId,
          'isAutoPosted': entry.isAutoPosted,
          'costCenterId': entry.costCenterId,
          'costCenterCode': headerCc?.code,
          'costCenterGlobalId': headerCc?.globalId,
          'branchId': entry.branchId,
          'createdAt': entry.createdAt.toIso8601String(),
          'lines': lineRows.map((row) {
            final l = row.readTable(_db.journalEntryLines);
            final acc = row.readTableOrNull(_db.accounts);
            final lineCc =
                l.costCenterId != null ? costCenterById[l.costCenterId] : null;
            return {
              'id': l.id,
              'accountId': l.accountId,
              'accountCode': acc?.code,
              'accountGlobalId': acc?.globalId,
              'debit': l.debit,
              'credit': l.credit,
              'description': l.description,
              'costCenterId': l.costCenterId,
              'costCenterCode': lineCc?.code,
              'costCenterGlobalId': lineCc?.globalId,
            };
          }).toList(),
        });
      }

      return _json({'journals': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getJournalEntries error: $e');
      return ApiErrors.fail(e, 'Failed to fetch journal entries');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Commercial Papers (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getCommercialPapers(Request request) async {
    try {
      // Spec 151 residual #1 — the only branch linkage is safeId, which is
      // NULLABLE (pending/undeposited papers have no safe). So:
      //   • no identity / mis-provisioned (sentinel) → fully closed, zero rows
      //     (an early return, NOT `IN(-1) OR IS NULL`, so the NULL-safe papers
      //     do NOT leak to a tokenless caller — omission closed);
      //   • real branch → its safes' papers + NULL-safe (head-office /
      //     undeposited) papers stay visible (the documented convention);
      //   • full-access (admin) → no filter → all.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      if (branchId == _kNoBranchAccess) {
        return _json({'commercial_papers': const [], 'count': 0});
      }
      final safeIds =
          branchId != null ? await _resolveBranchSafeIds(branchId) : null;
      final query = _db.select(_db.commercialPapers);
      if (safeIds != null) {
        query.where((p) => p.safeId.isIn(safeIds) | p.safeId.isNull());
      }
      final papers = await query.get();
      final jsonList = <Map<String, dynamic>>[];
      final drawers = await _db.commercialPaperDrawers(); // v186

      for (final p in papers) {
        final history = await (_db.select(_db.paperStatusHistory)
              ..where((h) => h.paperId.equals(p.id)))
            .get();

        jsonList.add({
          'id': p.id,
          'paperNumber': p.paperNumber,
          'type': p.type,
          'direction': p.direction,
          'partyId': p.partyId,
          'amount': p.amount,
          'issueDate': p.issueDate.toIso8601String(),
          'dueDate': p.dueDate.toIso8601String(),
          'bankName': p.bankName,
          'bankBranch': p.bankBranch,
          'accountNumber': p.accountNumber,
          'status': p.status,
          'endorsedToPartyId': p.endorsedToPartyId,
          'notes': p.notes,
          'safeId': p.safeId,
          'drawerAccountId': drawers[p.id]?.accountId,
          'drawerName': drawers[p.id]?.name,
          'createdAt': p.createdAt.toIso8601String(),
          'statusHistory': history.map((h) => {
            'id': h.id,
            'fromStatus': h.fromStatus,
            'toStatus': h.toStatus,
            'changedAt': h.changedAt.toIso8601String(),
            'changedBy': h.changedBy,
            'notes': h.notes,
          }).toList(),
        });
      }

      return _json({'commercial_papers': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getCommercialPapers error: $e');
      return ApiErrors.fail(e, 'Failed to fetch commercial papers');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Payments
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getPayments(Request request) async {
    try {
      // Spec 151 residual #1 — scope by safe→branch (payments.safeId is NOT
      // NULL). No identity → sentinel → safeId IN (-1) → zero rows (omission
      // closed); full-access (admin) → no filter → all.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      final safeIds =
          branchId != null ? await _resolveBranchSafeIds(branchId) : null;
      final query = _db.select(_db.payments);
      if (safeIds != null && safeIds.isNotEmpty) {
        query.where((p) => p.safeId.isIn(safeIds));
      }
      final rows = await query.get();
      final jsonList = rows.map((p) => <String, dynamic>{
        'id': p.id,
        'paymentNumber': p.paymentNumber,
        'paymentDate': p.paymentDate.toIso8601String(),
        'amount': p.amount,
        'paymentMethod': p.paymentMethod,
        'safeId': p.safeId,
        'partyId': p.partyId,
        'paymentType': p.paymentType,
        'notes': p.notes,
        'userId': p.userId,
        'safeTransactionId': p.safeTransactionId,
        'globalId': p.globalId,
        'idempotencyKey': p.idempotencyKey,
        'isDeleted': p.isDeleted,
        'deletedAt': p.deletedAt?.toIso8601String(),
        'deletedBy': p.deletedBy,
        'updatedAt': p.updatedAt.toIso8601String(),
        'createdAt': p.createdAt.toIso8601String(),
      }).toList();
      return _json({'payments': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch payments');
    }
  }

  Future<Response> _getPaymentAllocations(Request request) async {
    try {
      // Spec 151 residual #1 — allocations have no branch column; scope via
      // parent payment→safe→branch. Resolve the caller's in-scope payment ids,
      // then filter allocations by them. No identity / mis-provisioned →
      // sentinel safe → no scoped payments → sentinel id → zero rows.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      List<int>? paymentIds;
      if (branchId != null) {
        final safeIds = await _resolveBranchSafeIds(branchId);
        final scoped = await (_db.select(_db.payments)
              ..where((p) => p.safeId.isIn(safeIds)))
            .get();
        paymentIds = scoped.map((p) => p.id).toList();
        // Empty (branch has no in-scope payments) must fail CLOSED, not drop
        // the filter — `paymentId IN (-1)` matches nothing.
        if (paymentIds.isEmpty) paymentIds = const [_kNoBranchAccess];
      }
      final query = _db.select(_db.paymentAllocations);
      if (paymentIds != null) {
        query.where((a) => a.paymentId.isIn(paymentIds!));
      }
      final rows = await query.get();
      final jsonList = rows.map((a) => <String, dynamic>{
        'id': a.id,
        'paymentId': a.paymentId,
        'invoiceType': a.invoiceType,
        'invoiceId': a.invoiceId,
        'allocatedAmount': a.allocatedAmount,
      }).toList();
      return _json({'payment_allocations': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch payment allocations');
    }
  }


  /// Account Mappings — read-only for client sync
  Future<Response> _getAccountMappings(Request request) async {
    try {
      final mappings = await _db.select(_db.accountMappings).get();
      final jsonList = mappings.map((m) => <String, dynamic>{
        'id': m.id,
        'purpose': m.purpose,
        'accountId': m.accountId,
        'costCenterId': m.costCenterId,
        'description': m.description,
        'updatedAt': m.updatedAt.toIso8601String(),
      }).toList();
      return _json({'account_mappings': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch account mappings');
    }
  }
}
