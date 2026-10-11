part of '../database.dart';

/// Shift entry points: open / close with audit, paginated shifts report.
extension TreasuryShiftDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // SHIFT OPERATIONS (#Phase4: Blind Audit)
  // ═══════════════════════════════════════════════════════════════════════

  /// Get currently open shift for a user
  Future<Shift?> getCurrentOpenShift(int userId) {
    return (select(shifts)
          ..where((s) => s.userId.equals(userId) & s.status.equals('open'))
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Spec 135 NOTE 2 (req 4) — all OPEN shifts on a terminal/branch, regardless
  /// of which user opened them, newest first. Lets a system admin attach to a
  /// previous cashier's open shift to reconcile balances, close it, and record
  /// variances — instead of auto-opening their own shift. Pass null [branchId]
  /// to include every branch (single-terminal / full-access admin).
  Future<List<Shift>> getOpenShiftsForBranch({int? branchId}) {
    final q = select(shifts)..where((s) => s.status.equals('open'));
    if (branchId != null) {
      q.where((s) => s.branchId.equals(branchId));
    }
    q.orderBy([(s) => OrderingTerm.desc(s.startTime)]);
    return q.get();
  }

  /// Open a new shift
  /// GAP-VALIDATION: Validates required GL accounts are mapped before opening.
  ///
  /// Spec 008 / FR-003: [branchId] records the operating branch. For
  /// multi-branch users this is the branch selected via BranchScope; for
  /// single-branch users it's their only branch. Pass null for full-access
  /// users (mirror admin / system admin) — the close path uses the legacy
  /// fallback when branchId is null.
  Future<int> openShift(
    int userId,
    double openingBalance, {
    int? branchId,
    // Constitution R9: optional caller-minted globalId. The server-side
    // postOpenShift threads the client's globalId here so a subsequent
    // close-shift can resolve by globalId without needing the outbox-only
    // local→server id mapping. Falls back to a fresh UUID when null
    // (preserves legacy behaviour for direct DAO callers).
    String? globalId,
  }) async {
    // Validate the three mandatory accounts: cash, cash_shortage, cash_surplus
    const requiredPurposes = ['cash', 'cash_shortage', 'cash_surplus'];
    for (final purpose in requiredPurposes) {
      final defaultCode = AccountingDao.accountPurposes[purpose];
      if (defaultCode == null) continue;
      try {
        final mapped = await getMappedAccountCode(purpose, defaultCode);
        final acc = await getAccountByCode(mapped);
        if (acc == null) {
          throw Exception(
            'حساب "$purpose" غير مُعيَّن في الربط المحاسبي.\n'
            'يرجى الذهاب إلى الإعدادات → ربط الحسابات وتعيين الحساب المناسب قبل فتح الوردية.',
          );
        }
      } catch (e) {
        if (e.toString().contains('غير مُعيَّن')) rethrow;
        // getMappedAccountCode threw for another reason — log and continue (non-blocking)
        debugPrint('[openShift] Warning: could not validate $purpose: $e');
      }
    }
    // Feature 009 / T012h (FR-035): bind the shift to the running POS
    // terminal (resolved by PosTerminalRegistrationService from the
    // device's UUIDv7 in secure storage). NULL is intentional and
    // graceful — Constitution I (Behavior Preservation):
    //   • Standalone mode: registration service skips server lookup;
    //     no terminal id available → shift stays unbound to any terminal.
    //   • Client/mirror mode, terminal not yet registered: shift opens
    //     with null pos_terminal_id; the per-terminal stock-shortage
    //     policy tier is skipped at sale time and the per-branch /
    //     global tier still applies. Once the admin registers the
    //     terminal, subsequent shifts pick up the new id.
    //   • Existing shifts opened pre-v146 keep null pos_terminal_id.
    // Cluster 034 / Issue 1 fix — the cached terminal id can be a server
    // id that hasn't yet been mirrored into the local `pos_terminals`
    // table (or a stale value from a previous install). Inserting it
    // raw causes `FOREIGN KEY constraint failed (787)` on the shift
    // row, which the operator sees as "تعذر فتح الوردية افتحها يدوياً".
    // Verify the row exists before stamping it; fall back to null
    // (column is nullable) so the per-terminal policy tier is skipped
    // until the terminal is properly registered + synced.
    final cachedTerminalId =
        PosTerminalRegistrationService.instance.getCurrentTerminalId();
    int? posTerminalId;
    if (cachedTerminalId != null) {
      final terminalRow = await (select(posTerminals)
            ..where((t) => t.id.equals(cachedTerminalId))
            ..limit(1))
          .getSingleOrNull();
      if (terminalRow != null) {
        posTerminalId = cachedTerminalId;
      } else {
        debugPrint(
          '[openShift] cached terminal id=$cachedTerminalId not found in '
          'local pos_terminals — opening shift with null pos_terminal_id',
        );
      }
    }
    final effectiveGlobalId =
        (globalId != null && globalId.isNotEmpty) ? globalId : UuidV7.generate();
    return into(shifts).insert(
      ShiftsCompanion.insert(
        userId: userId,
        startTime: DateTime.now(),
        openingBalance: Value(openingBalance),
        status: 'open',
        // UUID-First Phase 1 Slice 3: auto-mint so shift rows carry stable
        // identity for server sync (client-open → server-close flows).
        // R9: when the caller passed a globalId (e.g. server postOpenShift
        // forwarding the client's value) reuse it for end-to-end identity.
        globalId: Value(effectiveGlobalId),
        branchId: Value(branchId),
        posTerminalId: Value(posTerminalId),
      ),
    );
  }

  /// Close shift with blind audit (variance calculation)
  /// PIR-06: Separated into 3 distinct steps:
  ///   Step 1: _settleShift — calculate expected vs actual cash, record variance
  ///   Step 2: _postVarianceJournalEntry — create JE for shortage/surplus
  ///   Step 3: _closeShiftSafes — zero out all involved safes
  Future<void> closeShiftWithAudit(
    int shiftId,
    double actualCash, {
    String? notes,
    String closingMethod = 'normal',

    /// v151 — JSON of the figures the closing report is being printed from.
    /// Stored verbatim so the report can be reproduced exactly later; the
    /// `actual*` amounts in it are cashier input and are not recomputable.
    String? closingSnapshot,

    /// GAP-24: Optional callback invoked when the variance JE fails to post.
    /// Receives the variance amount so the UI can show a warning dialog.
    /// The shift is still closed — this is non-fatal.
    void Function(double variance)? onVarianceJeFailed,
  }) async {
    // FIX: Removed outer transaction() wrapper to prevent nested transaction
    // deadlocks (SqliteException 517 "database is locked"). Each step now
    // runs independently with its own transaction where needed.

    final shift = await (select(
      shifts,
    )..where((s) => s.id.equals(shiftId))).getSingleOrNull();
    if (shift == null) throw Exception('Shift not found');
    if (shift.status == 'closed') return;

    final endTime = DateTime.now();

    // Step 1: Settlement — calculate expected cash and record variance
    // (_settleShift has its own transaction internally)
    final settlementResult = await _settleShift(
      shift: shift,
      actualCash: actualCash,
      endTime: endTime,
      notes: notes,
      closingMethod: closingMethod,
      closingSnapshot: closingSnapshot,
    );

    // Step 2: Variance JE — separate, non-fatal.
    // IMPORTANT: Cannot merge with Step 1 inside a single db.transaction() —
    // doing so caused SqliteException 517 ("database is locked") in production
    // because the write-lock from _settleShift conflicted with the second
    // nested savepoint used by createJournalEntry.  The non-fatal pattern is
    // intentional here; the variance is already persisted in the shifts table,
    // so the shift close is safe.  DB errors ARE logged to the activity trail
    // (not just debugPrint) so they are visible in the audit log for manual
    // remediation.  COA-not-configured errors are handled silently inside
    // _postVarianceJournalEntry (early return, no exception thrown).
    if (settlementResult.variance.abs() > 0.01) {
      // H2 · الطرفُ في الخزنة قبل قيد الأستاذ — اقرا
      // [_postVarianceSafeTransaction]. غيرُ قاتلٍ كنظيره في الأستاذ: الفرقُ
      // محفوظٌ في صفّ الوردية على كل حال، فلا يُمنع الإقفال.
      if (settlementResult.drawerSafeId != null) {
        try {
          await _postVarianceSafeTransaction(
            shiftId: shiftId,
            safeId: settlementResult.drawerSafeId!,
            variance: settlementResult.variance,
            endTime: endTime,
            userId: shift.userId,
          );
        } catch (e) {
          debugPrint('[ShiftClose] Variance safe txn failed: $e');
          unawaited(DiagnosticLogger.log(
            'SHIFT-VARIANCE-SAFE-FAIL',
            'shift=$shiftId safe=${settlementResult.drawerSafeId} '
            'variance=${settlementResult.variance.toStringAsFixed(2)} err=$e',
          ));
        }
      }
      try {
        await _postVarianceJournalEntry(
          shiftId: shiftId,
          variance: settlementResult.variance,
          endTime: endTime,
          // الدرجُ الذي كتبت عليه التسويةُ حركتَها — لا مفتاحُ إعدادات.
          drawerSafeId: settlementResult.drawerSafeId,
        );
      } catch (e, st) {
        debugPrint('[ShiftClose] Variance JE failed — logging to audit trail: $e\n$st');
        // Spec 136 — the close dialog's text is generic ("check surplus/deficit
        // account mapping"), but the REAL throw is whatever createJournalEntry
        // raised (e.g. posting to a 'view'/parent account, a closed period, an
        // imbalance). Surface it + the mode so the next field smoke pins the
        // actual cause instead of guessing. On client/mirror the server is the
        // GL SSoT and posts this same variance JE on the queued close (dedup by
        // the deterministic je-shiftclose-<gid>-close globalId), so the local
        // failure self-heals on the next delta-pull — it is NOT a GL loss there.
        unawaited(DiagnosticLogger.log(
          'SHIFT-VARIANCE-FAIL',
          'shift=$shiftId variance=${settlementResult.variance.toStringAsFixed(2)} '
          'isClientMode=${SyncInterceptor.isClientMode} err=$e',
        ));
        // Persist failure to activity log so it is queryable for reconciliation.
        try {
          await logActivity(
            userId: shift.userId,
            userName: 'System',
            action: 'accounting_warning',
            entityType: 'shift',
            entityId: shiftId,
            description:
                '[P1] فشل قيد فرق الوردية #$shiftId '
                '(فرق=${settlementResult.variance.toStringAsFixed(2)}): $e',
            amount: settlementResult.variance.abs(),
          );
        } catch (error, stack) {
           await DiagnosticLogger.logError(
             'SHIFT-VARIANCE-FAIL',
             'shift-close audit log failed',
             error,
             stack,
           );
         }
        // GAP-24: Notify UI so it can show a warning dialog
        onVarianceJeFailed?.call(settlementResult.variance);
        await _reopenShiftAfterFailedClose(shiftId);
        rethrow;
      }
    }

    // Step 3: Safe Closing — separate, non-fatal
    try {
      await _closeShiftSafes(
        shift: shift,
        transactions: settlementResult.transactions,
        shiftId: shiftId,
        endTime: endTime,
      );
    } catch (e) {
      debugPrint('[ShiftClose] Safe closing failed: $e');
      await _reopenShiftAfterFailedClose(shiftId);
      rethrow;
    }

    // Fiscal Lock: Lock all invoices created during this shift
    await (update(salesInvoices)..where(
          (i) =>
              i.userId.equals(shift.userId) &
              i.createdAt.isBetween(
                Variable(shift.startTime),
                Variable(endTime),
              ),
        ))
        .write(const SalesInvoicesCompanion(isLocked: Value(true)));

    await (update(shifts)..where((s) => s.id.equals(shiftId))).write(
      const ShiftsCompanion(status: Value('closed')),
    );
    await _runFinancialIntegrityChecks();
   }
   Future<void> _reopenShiftAfterFailedClose(int shiftId) async {
     await (update(shifts)..where((s) => s.id.equals(shiftId))).write(
       const ShiftsCompanion(status: Value('open'), endTime: Value(null)),
     );
   }


  /// Get shift report data paginated
  Future<List<ShiftReportDto>> getShiftsReportPaginated({
    int limit = 50,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    int? userId,
    Set<int>? allowedBranchIds,
    // فلترُ الفرع الذي يختاره المستخدم — **غيرُ** `allowedBranchIds` أعلاه.
    // ذاك حصرُ صلاحيةٍ آمر، وهذا اختيارُ عرضٍ. وكلاهما لا بدّ أن يصل SQL
    // قبل `limit`، وإلا امتلأت النافذةُ بصفوفٍ ستُرمى بعد الجلب فيظهر
    // الجدولُ فارغاً بينما للفرع صفوفٌ فعلاً.
    int? branchId,
    Set<int>? regionBranchIds,
  }) async {
    final query = select(
      shifts,
    ).join([innerJoin(users, users.id.equalsExp(shifts.userId))]);

    if (startDate != null && endDate != null) {
      query.where(shifts.startTime.isBetweenValues(startDate, endDate));
    }
    if (userId != null) {
      query.where(shifts.userId.equals(userId));
    }

    // مساواةٌ صارمة — نفسُ ما كانت تفعله الشاشةُ بعد الجلب، منقولاً كما هو
    // إلى SQL. (الشفتُ بلا فرعٍ لا يدخل اختيارَ فرعٍ بعينه.)
    if (branchId != null) {
      query.where(shifts.branchId.equals(branchId));
    } else if (regionBranchIds != null && regionBranchIds.isNotEmpty) {
      query.where(shifts.branchId.isIn(regionBranchIds));
    }

    // Spec 151 Track-3: authoritative branch-scope cap. The shifts report
    // filtered by branch on the UI only — AFTER fetching just the first
    // `limit` rows across ALL branches, so a restricted user could see at most
    // 100 recent cross-branch shifts then filter (a correctness bug on top of
    // the leak). Capping in SQL scopes the paginated page itself, fixing both.
    // Contract: null = full access, {} = fail-closed, {ids} = those branches
    // OR NULL-branch (legacy/shared) rows stay visible.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where(shifts.branchId.isIn(const <int>[]));
      } else {
        query.where(
            shifts.branchId.isIn(allowedBranchIds) | shifts.branchId.isNull());
      }
    }

    query.orderBy([OrderingTerm.desc(shifts.startTime)]);
    query.limit(limit, offset: offset);

    final result = await query.get();

    return result.map((row) {
      final s = row.readTable(shifts);
      final u = row.readTable(users);
      return ShiftReportDto(
        id: s.id,
        startTime: s.startTime,
        endTime: s.endTime,
        userName: u.displayName.isEmpty ? u.username : u.displayName,
        openingBalance: s.openingBalance,
        expectedCash: s.expectedCash,
        actualCash: s.actualCash,
        variance: s.variance,
        status: s.status,
        notes: s.notes,
        branchId: s.branchId,
        userId: s.userId,
        closingSnapshot: s.closingSnapshot,
      );
    }).toList();
  }
}
