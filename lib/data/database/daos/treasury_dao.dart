// ═══════════════════════════════════════════════════════════════════════════
// TREASURY DAO - Safes, Transactions, and Financial Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all treasury-related database operations.
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// اسم الصندوق الرئيسي (الإدارة المركزية) — وجهة نقدية إقفال الورديات.
const String kCentralSafeName = 'الصندوق الرئيسي';

/// مفتاح البذرة الثابت للـ`globalId` — مستقل عن الاسم المعروض عشان إعادة
/// التسمية ما تخلقش خزينة تانية على الأجهزة التانية (نفس نمط Spec 136 ISS-2).
const String kCentralSafeSeedKey = 'central';

/// كود الحساب الافتراضي لكل نوع خزينة — **مطابق لمسار البيع الحي**.
///
/// `_resolveBranchSafeAccount` في `accounting_autopost_dao.dart:58` بيقع على
/// حساب الغرض بحسب نوع الخزينة (`cash`/`bank`/`click`). أي خريطة مختلفة هنا
/// معناها إن سند القبض النقدي بيتقيّد على حساب غير اللي البيع النقدي بيتقيّد
/// عليه — تناقض في نفس الدفتر أسوأ من الباج الأصلي.
const Map<String, String> kSafeTypeAccountCode = {
  'cash': '1111', // الصندوق الرئيسي — نفس ما بيعمله مسار البيع
  'bank': '1113', // البنك الأهلي - حساب جاري
  'click': '1116', // حساب Click
};

/// ختمُ الرقعة المرّة-الواحدة لربط الخزائن بحساباتها الفرعية.
///
/// قرارُ المالك 2026-08-11: الربطُ التلقائيُّ يصلح **تنصيباً جديداً** ثم تصير
/// شاشةُ إدارة الصناديق صاحبةَ القرار. ومنتقي «الحساب المرتبط» فيها اختياريٌّ
/// ويسمح بـ«بدون» (‏`safe_management_dialog.dart` — `showClearButton: true`)،
/// فإصلاحٌ يعمل كلَّ إقلاعٍ كان سيدوس ذلك الاختيار ويخلّف حساباً يتيماً في
/// الدليل مع كلّ مسح.
///
/// ويُكتب هنا لا في `DeploymentSettingsKeys`: تلك محروسةٌ بـ
/// `test/static/no_direct_network_mode_writes_test.dart` الذي يمنع أيَّ
/// `setSetting` على مفاتيحها خارج مُلزِم النشر — نفسُ سبب بقاء مفاتيح رقعة
/// Spec 138 في ملفّ خدمتها.
const String kSafeSubAccountsBackfillV1Applied =
    'safe_sub_accounts_backfill_v1_applied';

/// One expense line item surfaced by [getShiftClosingAggregates] for the
/// dialog's "detailed expenses" drop-down.
class ShiftClosingExpenseItem {
  final String description;
  final double amount;
  final String safeType; // 'cash' | 'bank' | 'click'
  const ShiftClosingExpenseItem({
    required this.description,
    required this.amount,
    required this.safeType,
  });
}

/// Per-channel aggregation of everything that touched the cashier's drawer
/// during a shift. Produced by [getShiftClosingAggregates] and consumed by
/// the shift-close reconciliation dialog so the accountant can match each
/// channel (cash drawer / bank POS tape / e-wallet / AR) against what the
/// system recorded.
///
/// Channels used everywhere:
///   - `cash`   — physical money in the cash drawer.
///   - `bank`   — any card / transfer / POS-machine channel.
///   - `click`  — mobile-wallet (Click Pay) channel.
///   - `credit` — not a drawer; tracks AR movement only (no "actual" count).
///
/// Every `cash/bank/click` field corresponds to a matching
/// `sales_invoices.payment_method` bucket or a `safes.safe_type` bucket for
/// vouchers. `credit` applies to invoices only — a voucher is always paid
/// through a physical safe, not an AR ledger.
class ShiftClosingAggregates {
  // ── Sales (customer-paid us) ──────────────────────────────────────────
  final double salesCash;
  final double salesBank;
  final double salesClick;
  final double salesCredit; // sum of `total` for paymentMethod=='credit'
  final int salesCreditCount; // number of credit/partial-credit sales
  final int salesCount; // non-return invoices
  final int counterSalesCount;
  final int tableSalesCount;
  final double counterSalesTotal;
  final double tableSalesTotal;

  // ── Returns (we paid back customer) ───────────────────────────────────
  final double returnsCash;
  final double returnsBank;
  final double returnsClick;
  final double returnsCredit; // AR-only refunds (paymentMethod=='credit')
  final int returnsCount;

  // ── Receipt vouchers (money IN, non-sales) ────────────────────────────
  // Typical cause: a customer paying off an older credit invoice.
  final double receiptCash;
  final double receiptBank;
  final double receiptClick;
  final int receiptCount;

  // ── Payment vouchers (money OUT to suppliers / other) ─────────────────
  // Excludes expenses (tracked separately) — these are `payment` rows with
  // non-expense categories (e.g. supplier settlements).
  final double paymentCash;
  final double paymentBank;
  final double paymentClick;
  final int paymentCount;

  // ── Expenses (money OUT for salaries / rent / utilities / etc.) ───────
  final double expensesCash;
  final double expensesBank;
  final double expensesClick;
  final int expensesCount;
  final List<ShiftClosingExpenseItem> expensesList;

  // ── Opening balance + shift metadata ──────────────────────────────────
  final double openingBalance; // cash only — bank/click start at 0 each shift
  final DateTime? shiftStartTime;

  const ShiftClosingAggregates({
    this.salesCash = 0,
    this.salesBank = 0,
    this.salesClick = 0,
    this.salesCredit = 0,
    this.salesCreditCount = 0,
    this.salesCount = 0,
    this.counterSalesCount = 0,
    this.tableSalesCount = 0,
    this.counterSalesTotal = 0,
    this.tableSalesTotal = 0,
    this.returnsCash = 0,
    this.returnsBank = 0,
    this.returnsClick = 0,
    this.returnsCredit = 0,
    this.returnsCount = 0,
    this.receiptCash = 0,
    this.receiptBank = 0,
    this.receiptClick = 0,
    this.receiptCount = 0,
    this.paymentCash = 0,
    this.paymentBank = 0,
    this.paymentClick = 0,
    this.paymentCount = 0,
    this.expensesCash = 0,
    this.expensesBank = 0,
    this.expensesClick = 0,
    this.expensesCount = 0,
    this.expensesList = const [],
    this.openingBalance = 0,
    this.shiftStartTime,
  });

  // ── Derived helpers (the "system expected" math) ──────────────────────
  double get systemCash =>
      openingBalance +
      salesCash +
      receiptCash -
      returnsCash -
      expensesCash -
      paymentCash;

  double get systemBank =>
      salesBank + receiptBank - returnsBank - expensesBank - paymentBank;

  double get systemClick =>
      salesClick + receiptClick - returnsClick - expensesClick - paymentClick;

  /// AR-only movement. Positive = customers owe more to us (net credit
  /// sales). Negative = credit returns outweighed credit sales.
  double get systemCreditNet => salesCredit - returnsCredit;

  double get totalIncomeCash => salesCash + receiptCash;
  double get totalIncomeBank => salesBank + receiptBank;
  double get totalIncomeClick => salesClick + receiptClick;

  double get totalOutflowCash => returnsCash + expensesCash + paymentCash;
  double get totalOutflowBank => returnsBank + expensesBank + paymentBank;
  double get totalOutflowClick => returnsClick + expensesClick + paymentClick;
}

class ShiftReportDto {
  final int id;
  final DateTime startTime;
  final DateTime? endTime;
  final String userName;
  final double openingBalance;
  final double? expectedCash;
  final double? actualCash;
  final double? variance;
  final String status;
  final String? notes;
  // Feature 017 — exposed so the shifts report screen can filter
  // client-side by branch / region without changing the DAO query.
  final int? branchId;

  /// Owner of the shift. Needed to recompute a closed shift's aggregates,
  /// which are scoped per user.
  final int userId;

  /// v151 — raw JSON of the figures the closing report was printed from,
  /// or null for shifts closed before the column existed (those are
  /// recomputed and labelled as such).
  final String? closingSnapshot;

  ShiftReportDto({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.userName,
    required this.openingBalance,
    this.expectedCash,
    this.actualCash,
    this.variance,
    required this.status,
    this.notes,
    this.branchId,
    this.userId = 0,
    this.closingSnapshot,
  });
}

/// PIR-06: Internal result DTO for shift settlement step
class _ShiftSettlementResult {
  final double variance;
  final List<SafeTransactionData> transactions;

  /// الدرجُ الذي حُسب عليه [variance] — يُكتب عليه صفُّ التسوية كي لا يبقى
  /// الفرقُ في الأستاذ بلا طرفٍ في الخزنة. `null` حين لا درجَ نقديّاً أصلاً.
  final int? drawerSafeId;

  const _ShiftSettlementResult({
    required this.variance,
    required this.transactions,
    this.drawerSafeId,
  });
}

/// Extension for Treasury-related database operations
extension TreasuryDao on AppDatabase {
  /// الصندوق الرئيسي (الإدارة المركزية) — أو `null` لو مش مزروع.
  ///
  /// البحث بالـ`globalId` المشتق مش بالاسم: الاسم قابل للتعديل من المستخدم،
  /// والبحث بيه كان هيخلق خزينة تانية على أول إعادة تسمية. الاسم احتياطي
  /// للتركيبات اللي اتعملت قبل ما البذرة الثابتة تدخل.
  Future<Safe?> getCentralSafe() async {
    final gid = UuidV7.deriveSeedGlobalId(
        table: 'safes', seedKey: kCentralSafeSeedKey);
    final byGid = await (select(safes)
          ..where((s) => s.globalId.equals(gid))
          ..limit(1))
        .getSingleOrNull();
    if (byGid != null) return byGid;
    return (select(safes)
          ..where((s) => s.name.equals(kCentralSafeName))
          ..limit(1))
        .getSingleOrNull();
  }


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
        } catch (_) {} // logActivity failure must NEVER block shift close
        // GAP-24: Notify UI so it can show a warning dialog
        onVarianceJeFailed?.call(settlementResult.variance);
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
      debugPrint('[ShiftClose] Safe closing failed (non-fatal): $e');
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
  }

  /// PIR-06 Step 1: Calculate expected cash and record shift settlement
  /// FIX: Own transaction wrapper to keep settlement atomic without nesting.
  Future<_ShiftSettlementResult> _settleShift({
    required Shift shift,
    required double actualCash,
    required DateTime endTime,
    String? notes,
    String closingMethod = 'normal',
    String? closingSnapshot,
  }) async {
    return transaction(() async {
      // ⚠️ نطاقان مختلفان عن قصد، وخلطُهما كان أصلَ عطبٍ ماليّ:
      //
      // [txs] — مفلترةٌ بـ`shift.userId` — تخصّ **التصريف** وحدَه
      //   (`_closeShiftSafes`, Spec 136 ISS-8): الإقفال يرحّل صافيَ ما حرّكته
      //   هذه الوردية فقط، ويترك فلوسَ الورديات الأخرى في الدرج.
      //
      // [drawerTxs] — بلا فلترِ مستخدم — تخصّ **التوقّع**: `expectedCash`
      //   يوصف ما ينبغي أن يكون في الدرج **فعلاً**، والدرجُ واحدٌ يشترك فيه
      //   كلُّ من مسّه. والكاشير يعدّه كلَّه.
      //
      // قبل الفصل كان الاثنان نطاقاً واحداً، فأيُّ إيصالٍ على نفس الدرج
      // بمستخدمٍ آخر يسقط من التوقّع بينما فلوسُه في الدرج:
      //   * بيعةُ مديرٍ بلا وردية (الفورك يتخطّى `_ensureShiftOpen` له)
      //     ⇒ **فائضٌ** بحجمها بالضبط، فيُقيَّد «فائض نقدية» مدين نقدية /
      //     دائن إيراد — والمبلغُ نفسُه كان قد قُيِّد بقيد البيعة. النتيجة:
      //     النقديةُ في الأستاذ مرّتين وإيرادٌ وهميّ. مقيس: فرقُ +٢٠٠.
      //   * سندُ صرفٍ يوقّعه مشرفٌ على درج الكاشير ⇒ **عجزٌ وهميّ** بحجمه.
      final txs =
          await (select(safeTransactions)..where(
                (t) =>
                    t.userId.equals(shift.userId) &
                    t.createdAt.isBetween(
                      Variable(shift.startTime),
                      Variable(endTime),
                    ),
              ))
              .get();

      // Only count transactions that belong to cash-type safes.
      // Bank/visa and click collections are settled electronically — including
      // them in expectedCash inflates it relative to actualCash (physical drawer)
      // and produces a phantom deficit equal to the non-cash collections.
      final cashSafes = await (select(safes)
              ..where((s) => s.safeType.equals('cash')))
          .get();
      final cashSafeIds = {for (final s in cashSafes) s.id};

      // الدرجُ (أو الأدراج) التي تخصّ هذه الوردية: ما لمسَته فعلاً. وإن لم
      // تلمس شيئاً فأدراجُ فرعِها النقدية — وإلا بقيت وردية «بلا حركةٍ خاصة»
      // عمياءَ عن بيعةٍ حصلت على درجها.
      var drawerSafeIds = txs
          .map((t) => t.safeId)
          .where(cashSafeIds.contains)
          .toSet();
      if (drawerSafeIds.isEmpty) {
        drawerSafeIds = {
          for (final s in cashSafes)
            if (shift.branchId == null || s.branchId == shift.branchId) s.id,
        };
      }

      final drawerTxs = drawerSafeIds.isEmpty
          ? <SafeTransactionData>[]
          : await (select(safeTransactions)..where(
                (t) =>
                    t.safeId.isIn(drawerSafeIds) &
                    t.createdAt.isBetween(
                      Variable(shift.startTime),
                      Variable(endTime),
                    ),
              ))
              .get();

      double totalReceipts = 0;
      double totalPayments = 0;

      for (final t in drawerTxs) {
        // صفُّ تسوية الفرق (‏[_postVarianceSafeTransaction]) **تصحيحٌ لعدٍّ
        // سابق** لا حركةَ درجٍ حقيقية، فلا يدخل توقّعَ أيّ وردية. وبدون
        // استثنائه يتسرّب إلى الوردية التالية حين يتلامس وقتُ الإقفال مع وقت
        // الفتح (‏`isBetween` شاملُ الطرفين) فيتضاعف الفرقُ المقيس: مقيس
        // ٢٠ بدل ١٠ في `atomicity_variance_test`.
        if (t.category == 'shift_variance') continue;
        if (t.transactionType == 'receipt') {
          totalReceipts += t.amount;
        } else if (t.transactionType == 'payment') {
          totalPayments += t.amount;
        }
      }

      final expectedCash = shift.openingBalance + totalReceipts - totalPayments;
      final variance = actualCash - expectedCash;

      await (update(shifts)..where((s) => s.id.equals(shift.id))).write(
        ShiftsCompanion(
          endTime: Value(endTime),
          expectedCash: Value(expectedCash),
          actualCash: Value(actualCash),
          variance: Value(variance),
          status: const Value('closed'),
          notes: Value(notes),
          closingMethod: Value(closingMethod),
          // Absent(), not Value(null): a close path that doesn't supply a
          // snapshot must leave any existing one alone rather than erase it.
          closingSnapshot: closingSnapshot == null
              ? const Value.absent()
              : Value(closingSnapshot),
        ),
      );

      // الدرجُ الذي تحرّك أكثر — وإن لم يتحرّك شيءٌ فأوّلُ أدراج النطاق.
      int? primaryDrawer;
      if (drawerSafeIds.isNotEmpty) {
        final moved = <int, double>{};
        for (final t in drawerTxs) {
          moved[t.safeId] = (moved[t.safeId] ?? 0) + t.amount.abs();
        }
        primaryDrawer = moved.isEmpty
            ? drawerSafeIds.first
            : moved.entries
                .reduce((a, b) => a.value >= b.value ? a : b)
                .key;
      }

      return _ShiftSettlementResult(
        variance: variance,
        transactions: txs,
        drawerSafeId: primaryDrawer,
      );
    });
  }

  /// H2 · الطرفُ الغائب: فرقُ الوردية كان يُقيَّد في الأستاذ وحدَه (‏دائن
  /// نقدية للعجز) بينما `safes.balance` يبقى كما هو ⇒ حسابُ النقدية والخزنةُ
  /// ينفصلان بمقدار الفرق، **وتتراكم الفجوةُ كلَّ وردية**، ولا أثرَ للفرق في
  /// كشف حركة الخزنة يراه مراجع.
  ///
  /// مقيس: عجزُ ٥٠ ⇒ الأستاذ ينزل ٥٠ والخزنةُ لا تنزل شيئاً.
  ///
  /// يُنادى **خارج** `_settleShift` عمداً: `createSafeTransaction` يفتح
  /// معاملتَه، ودمجُها في معاملةِ التسوية هو نفسُ نمط التعشيش الذي سبّب
  /// SqliteException 517 مع `createJournalEntry` (اقرا الخطوة ٢ في
  /// [closeShiftWithAudit]).
  Future<void> _postVarianceSafeTransaction({
    required int shiftId,
    required int safeId,
    required double variance,
    required DateTime endTime,
    required int userId,
  }) async {
    final safe =
        await (select(safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
    if (safe == null) return;

    final isShortage = variance < 0;
    final amount = variance.abs();
    await createSafeTransaction(SafeTransactionsCompanion.insert(
      voucherNumber: 'SHV-$shiftId-${safe.id}',
      safeId: safe.id,
      transactionType: isShortage ? 'payment' : 'receipt',
      category: 'shift_variance',
      amount: amount,
      balanceAfter: safe.balance + (isShortage ? -amount : amount),
      referenceType: const Value('shift_close'),
      referenceId: Value(shiftId),
      description: Value(isShortage
          ? 'تسوية عجز إقفال وردية #$shiftId'
          : 'تسوية فائض إقفال وردية #$shiftId'),
      userId: Value(userId),
      createdAt: Value(endTime),
    ));
  }

  /// PIR-06 Step 2: Generate journal entry for cash variance (shortage/surplus)
  ///
  /// PHASE-2 FIX: Exceptions here propagate to the parent closeShift transaction.
  /// A failed GL entry must roll back the entire shift-close to prevent
  /// "shift closed but variance unrecorded" silent data corruption.
  ///
  /// EXCEPTION: Accounts that are not yet configured in the Chart of Accounts
  /// produce a safe warning only — the shift close still completes, which is
  /// the correct business behaviour when no variance accounts are mapped.
  Future<void> _postVarianceJournalEntry({
    required int shiftId,
    required double variance,
    required DateTime endTime,
  }) async {
    // Resolve branchId for the JE (from the primary cash safe).
    // Use getSetting() which tolerates duplicate rows (legacy sync artifact).
    final primarySafeSetting = await getSetting('pos_cash_safe_id');
    final primarySafeId = int.tryParse(primarySafeSetting?.value ?? '1') ?? 1;
    final primarySafe = await (select(safes)..where((s) => s.id.equals(primarySafeId))).getSingleOrNull();
    final resolvedBranchId = primarySafe?.branchId;

    final cashAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('cash', AccountingDao.accountPurposes['cash']!),
    );
    if (cashAccount == null) {
      // COA not configured — skip JE but log clearly. This is not a DB error.
      debugPrint('[FINANCIAL_WARNING] Shift #$shiftId: cash account not configured - variance JE skipped.');
      return;
    }

    // Spec 083 — thread the safe name into JE descriptions so multi-safe
    // installs can tell at a glance WHICH till had the shortage/surplus.
    // Pre-spec, every variance JE read "تعديل نقدية — عجز" with no
    // attribution; in branches with several safes the operator couldn't
    // tell which till the entry belonged to without cross-referencing
    // the shift. `primarySafe` may legitimately be null on legacy installs
    // (settings never seeded) — fall back to the unattributed format.
    final safeName = primarySafe?.name;
    final safeSuffix = safeName != null ? ' — $safeName' : '';

    final lines = <JournalLine>[];
    if (variance < 0) {
      // Shortage: Dr Cash Shortage Expense, Cr Cash
      final shortageAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('cash_shortage', AccountingDao.accountPurposes['cash_shortage']!),
      );
      if (shortageAccount == null) {
        debugPrint('[FINANCIAL_WARNING] Shift #$shiftId: cash_shortage account not configured - shortage JE skipped.');
        return;
      }
      lines.add(JournalLine(
        accountId: shortageAccount.id,
        debit: variance.abs(),
        description: 'عجز صندوق — إقفال وردية #$shiftId$safeSuffix',
      ));
      lines.add(JournalLine(
        accountId: cashAccount.id,
        credit: variance.abs(),
        description: 'تعديل نقدية — عجز$safeSuffix',
      ));
    } else {
      // Surplus: Dr Cash, Cr Cash Surplus Revenue
      final surplusAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('cash_surplus', AccountingDao.accountPurposes['cash_surplus']!),
      );
      if (surplusAccount == null) {
        debugPrint('[FINANCIAL_WARNING] Shift #$shiftId: cash_surplus account not configured - surplus JE skipped.');
        return;
      }
      lines.add(JournalLine(
        accountId: cashAccount.id,
        debit: variance,
        description: 'فائض نقدية — إقفال وردية #$shiftId$safeSuffix',
      ));
      lines.add(JournalLine(
        accountId: surplusAccount.id,
        credit: variance,
        description: 'فائض صندوق — إقفال وردية$safeSuffix',
      ));
    }

    if (lines.isNotEmpty) {
      // Phase 5A.8 (Issue 2) — derive a deterministic globalId for the
      // variance JE from the shift's own globalId. Both client and server
      // run this same DAO during shift close (server when reconstructing
      // the missing shift, client when closing locally). Without a stable
      // globalId, each side wrote a JE with a random UUID, and the sync
      // pull duplicated the variance entry in the General Ledger. With
      // the deterministic globalId, JournalSyncStrategy's Tier 1 dedup
      // recognises the match and updates instead of inserting.
      //
      // Older shifts (created before openShift started auto-minting a
      // globalId in commit 7900XXX) may not have one. In that legacy
      // case we fall back to null and accept random globalId — those
      // shifts predate the multi-device era and won't dedupe, but won't
      // duplicate within a single device either.
      final shiftRow = await (select(shifts)
            ..where((s) => s.id.equals(shiftId))
            ..limit(1))
          .getSingleOrNull();
      // Spec 129 F5 — canonical schema `je-shiftclose-<shiftGid>-close`.
      // The legacy `je-shift-variance-<shiftGid>` format from Phase 5A.8
      // (Issue 2) served the same dedup goal but didn't follow the F5
      // formula. Existing legacy rows stay in the DB; new posts use the
      // canonical helper. Shifts without a globalId (very old rows) fall
      // back to null and accept random UUID (same behaviour as before).
      final detGlobalId = (shiftRow?.globalId != null && shiftRow!.globalId!.isNotEmpty)
          ? JournalEntryGid.compute(
              sourceType: JournalEntryGid.sourceShiftClose,
              sourceGid: shiftRow.globalId!,
              verb: 'close',
            )
          : null;
      if (detGlobalId != null) {
        unawaited(DiagnosticLogger.log(
          DiagnosticLogger.gidAutopost,
          'sourceType=shiftclose sourceGid=${shiftRow!.globalId!.substring(0, 8)} '
          'verb=close shiftId=$shiftId',
        ));
      }
      // Throws on DB failure → propagates to parent transaction → rollback
      await accountingDao.createJournalEntry(
        description: 'قيد فرق إقفال وردية #$shiftId$safeSuffix',
        date: endTime,
        lines: lines,
        referenceType: 'shift_close',
        referenceId: shiftId,
        isAutoPosted: true,
        branchId: resolvedBranchId,
        globalId: detGlobalId,
      );
    }
  }

  /// PIR-06 Step 3: Zero out all safes used during the shift
  /// FIX: Removed duplicate zeroing (previously safes were zeroed BOTH inline AND via closeSafe)
  Future<void> _closeShiftSafes({
    required Shift shift,
    required List<SafeTransactionData> transactions,
    required int shiftId,
    required DateTime endTime,
  }) async {
    // Spec 136 ISS-8 — PER-SHIFT drain (supersedes Spec 107 "Full Drain").
    //
    // Field report: closing one user's shift drained the ENTIRE cumulative
    // safe balance — including cash earned by OTHER users' still-open shifts
    // and residuals from previously-unclosed shifts (the old code swept every
    // active branch safe and zeroed each one). The operator wants the close to
    // settle ONLY the closing user's current shift and leave every other
    // shift's money in the till.
    //
    // `transactions` is already scoped to (userId == shift.userId, createdAt
    // in [shift.startTime, endTime]) by _settleShift, so the NET movement this
    // shift made into each safe is exactly:
    //     sum(receipts) - sum(payments | withdrawals)   per safeId.
    // We transfer only that net to HQ and leave the remaining balance (the
    // opening float — openShift never posts it as a safe txn — plus any other
    // shift's contributions) untouched. Only safes THIS shift actually moved
    // cash in/out of are processed; sister/other-branch safes and untouched
    // tills are never swept.
    final netBySafe = <int, double>{};
    for (final t in transactions) {
      final type = t.transactionType;
      final double delta;
      if (type == 'receipt') {
        delta = t.amount;
      } else if (type == 'payment' || type == 'withdrawal') {
        delta = -t.amount;
      } else {
        // memo / transfer / other — no physical till movement to drain.
        continue;
      }
      netBySafe[t.safeId] = (netBySafe[t.safeId] ?? 0) + delta;
    }

    for (final sId in netBySafe.keys) {
      final safe = await (select(safes)..where((s) => s.id.equals(sId))).getSingleOrNull();
      if (safe == null) continue;

      // Feature 011 / Issue NEG-BAL — idempotency on (safe, shift).
      //
      // Real-world incident from a beta restaurant: every shift close was
      // producing TWO `shift_closing` rows per safe — a `ZRO…` from this
      // method and a `PMT-X` from postSafeTransaction (the client also
      // submits each safe transaction individually via
      // /api/safes/transaction). When `/api/shifts/close` reached the
      // server BEFORE the matching `/api/safes/transaction`, the order
      // on the server was:
      //   1. _closeShiftSafes inserted ZRO and absolute-set balance to 0
      //   2. postSafeTransaction then read balance=0, applied -amount,
      //      and stored the new row with balanceAfter = -amount
      // → safe balances on the server's "إدارة الخزينة" screen showed
      // NEGATIVE amounts even though no real disbursement happened
      // (e.g. صندوق فيزا الإدارة: -12.500, صندوق فيزا مطعم معان: -33.000).
      //
      // Fix: skip this safe entirely if a `shift_closing` transaction
      // for THIS exact (shiftId, safeId) pair already exists. Robust
      // regardless of which API call arrives first; standalone mode is
      // unaffected (no prior row → no skip).
      final alreadyClosed = await (select(safeTransactions)
            ..where((t) =>
                t.safeId.equals(sId) &
                t.referenceType.equals('shift_closing') &
                t.referenceId.equals(shiftId))
            ..limit(1))
          .getSingleOrNull();
      if (alreadyClosed != null) {
        debugPrint('[TreasuryDao] _closeShiftSafes: safe #$sId already has '
            'a shift_closing transaction for shift #$shiftId — skipping '
            '(prevents duplicate ZRO + PMT pair driving balance negative).');
        continue;
      }

      // Spec 107 — Model A (Full Drain): transfer the full safe balance to
      // HQ at every shift close. Branch safes are daily operational tills,
      // NOT inter-shift carry containers; their natural end-of-shift state
      // is zero. Any value sitting in the safe — whether it came from this
      // shift's sales, a manual receipt voucher posted earlier, or leftover
      // from a previously-broken close — belongs in HQ (cash → main safe,
      // bank → checking account, click → click clearing).
      //
      // Variance attribution to the cashier is handled SEPARATELY by
      // `_settleShift` (Spec 104) which scopes its expectation calc to the
      // shift period in cash safes only. So a manual receipt of 50 added
      // before the shift does NOT inflate `expectedCash` (Spec 104 fix)
      // but IS drained at close (this Spec 107 rule) — the two concerns
      // are intentionally decoupled.
      //
      // Supersedes Spec 106 US1 (Model B / shift-delta-only) after model
      // discussion 2026-05-20.
      // Spec 136 ISS-8 — drain only THIS shift's net contribution to the
      // safe, not the full cumulative balance. A net <= 0 (more cash paid out
      // than taken in during the shift, rare for a till) drains nothing — the
      // variance JE handles any discrepancy; we never push another shift's
      // balance out.
      final balanceToZero = netBySafe[sId] ?? 0;
      if (balanceToZero > 0.001) {
        // Spec 136 item 7 — clamp the drain to what's physically in the till
        // so a shift whose tracked net exceeds the actual balance (untracked
        // cash-out / shortage) never pushes the safe negative. The undrained
        // remainder is a shortage the variance settlement (_settleShift,
        // Spec 104) already attributes against expected-vs-actual cash, so we
        // do NOT post a second variance JE here (double-count); we cap the
        // physical transfer and surface the gap via SHIFT-DRAIN-CLAMP.
        // Normal case (net <= balance): actualDrain == balanceToZero →
        // byte-identical behaviour.
        final actualDrain = balanceToZero > safe.balance
            ? (safe.balance > 0 ? safe.balance : 0.0)
            : balanceToZero;
        final drainShortfall = balanceToZero - actualDrain;
        if (drainShortfall > 0.001) {
          unawaited(DiagnosticLogger.log(
              'SHIFT-DRAIN-CLAMP',
              'shift #$shiftId safe #$sId: tracked net '
              '${balanceToZero.toStringAsFixed(3)} exceeds till balance '
              '${safe.balance.toStringAsFixed(3)} — drained '
              '${actualDrain.toStringAsFixed(3)}, shortfall '
              '${drainShortfall.toStringAsFixed(3)} left for variance '
              'settlement (safe not pushed negative).'));
        }
        final voucherNo = 'ZRO${DateTime.now().millisecondsSinceEpoch}$sId';

        // Feature 041 / Route B.1 — deterministic UUIDv5 for the shift_closing
        // row's globalId, keyed on (shift.globalId, safe.globalId). Both the
        // CLIENT's _closeShiftSafes and the SERVER's _closeShiftSafes (now
        // reliably invoked end-to-end after Feature 035) derive THE SAME
        // value without any coordination, so the cross-side race that drove
        // v122 NEG-BAL is resolved at the data layer:
        //   - safe_transactions.globalId is UNIQUE → second cross-instance
        //     insert can never collide via DeltaPull.
        //   - The layered pre-check below catches the duplicate locally so
        //     the safe's balance is not zeroed a second time (which would
        //     otherwise post a withdrawal of -|balance| → negative drift).
        //
        // Legacy shift rows pre-v119 may have null globalId. In that case
        // mint a fresh UuidV7 (current behavior preserved). Same for safes
        // whose globalId was never populated by an earlier migration —
        // both are extremely rare in practice (master-data sync seeds them
        // at first paired connect) but the fallback keeps the close path
        // alive instead of crashing on `!`.
        final shiftGid = shift.globalId;
        // Spec 136 (field 2026-06-14): the per-safe close dedup key MUST be
        // identical on mirror and server. safe.globalId is NOT — safes are
        // created independently per device (the mirror's first sync pulls
        // safes=0 and seeds its own), so each side derived a different
        // zeroOutGlobalId → the globalId dedup below missed → duplicate
        // "إقفال وردية" JEs (field-observed on the supermarket cash safe; the
        // restaurant safe happened to match). Derive the key from the safe's
        // LINKED ACCOUNT CODE (shared, synced chart of accounts) + the safe
        // name — both are cross-device-stable business identifiers. Fall back
        // to safe.globalId only when the safe has no linked account.
        String? safeStableKey;
        if (safe.linkedAccountId != null) {
          final linkedAcc =
              await accountingDao.getAccountById(safe.linkedAccountId!);
          if (linkedAcc != null && linkedAcc.code.isNotEmpty) {
            safeStableKey = 'acct:${linkedAcc.code}:${safe.name}';
          }
        }
        safeStableKey ??= safe.globalId;
        final String zeroOutGlobalId;
        if (shiftGid != null &&
            shiftGid.isNotEmpty &&
            safeStableKey != null &&
            safeStableKey.isNotEmpty) {
          zeroOutGlobalId = UuidV7.deriveShiftClosingGlobalId(
            shiftGlobalId: shiftGid,
            safeGlobalId: safeStableKey,
          );

          // Defense in depth — alongside the (safeId, refType, refId) check
          // above, also dedup by deterministic globalId. This catches the
          // exact field race that v122 surfaced: the "other side" already
          // wrote the row with a different referenceId (its own local
          // shift id), bypassing the legacy check, but the globalId is
          // identical so we skip cleanly without driving balance negative.
          final existingByGlobalId = await (select(safeTransactions)
                ..where((t) => t.globalId.equals(zeroOutGlobalId))
                ..limit(1))
              .getSingleOrNull();
          if (existingByGlobalId != null) {
            debugPrint('[TreasuryDao] _closeShiftSafes: shift_closing '
                'globalId=$zeroOutGlobalId already present for safe #$sId '
                '(refId=${existingByGlobalId.referenceId}); skipping insert '
                'to prevent NEG-BAL drift (Feature 041 layered dedup).');
            // Important — the safe balance has already been zeroed by the
            // "other side"'s parallel run, so do NOT also rewrite it to 0
            // (that would no-op anyway) and do NOT post another JE.
            continue;
          }
        } else {
          // Spec 007 / FR-011 / T019.B legacy path: mint UuidV7 fresh when
          // either side's master globalId is missing. Mirror DeltaPull dedup
          // still falls back to (refType, refId, partyId) tier matching.
          unawaited(DiagnosticLogger.log(
              'SHIFT-CLOSE-WARN',
              'وردية=$shiftId صندوق=$sId مفتاح إقفال غير ثابت '
              '(shiftGid=$shiftGid, safeKey=$safeStableKey) — استُخدم globalId '
              'عشوائي؛ إزالة التكرار عبر الأجهزة قد تفشل (راقب تكرار قيد إقفال '
              'الوردية). اربط هذا الصندوق بحساب في دليل الحسابات لمنع ذلك.'));
          zeroOutGlobalId = UuidV7.generate();
        }

        // ── الطرفُ المستقبِل يُحسم **قبل** السحب ──────────────────────────
        //
        // §٥-١ (بلاغٌ ميدانيّ 2026-08-11): كان السحبُ غيرَ مشروطٍ والاستلامُ
        // بعده «أفضلَ جهد» داخل `try` يكتفي بالتسجيل حين لا يجد مستقبِلاً.
        // فأيُّ حالةٍ بلا مستقبِلٍ تحوّل **التحويلَ** إلى **اختفاء**:
        // `[SHIFT-CLOSE-NO-CENTRAL] safeId=1 amount=140.0` — ٤٦٠ خرجت من ثلاث
        // خزائن ولم تستقبلها خزينة. والحارسُ كان يسجّل ولا يمنع.
        //
        // وثلاثةُ طرقٍ مقيسةٍ تبلغ تلك الحالة، كلُّها بنفس النتيجة:
        //   ١. قاعدةٌ أُنشئت قبل دخول الصندوق المركزي في البذرة —
        //      `seedInitialData` لا تعمل إلا على قاعدةٍ جديدة أو بلا
        //      مستخدمين، ولا إصلاحَ إقلاعٍ يزرعه.
        //   ٢. حذفُه من شاشة إدارة الصناديق على تنصيبٍ **جديد**: حارسُ
        //      `deleteSafeById` يشترط `isDefault == false`، والمركزيُّ
        //      `isDefault: false` قصداً؛ وحارسُ القيود لا يعترض لأن تحويلات
        //      الإقفال لا تُنشئ قيداً، فحسابُه يبقى بلا بنود.
        //   ٣. أن تعمل الورديةُ على المركزيّ نفسِه: سطرُ الاستلام ممنوعٌ عن
        //      النفس (‏صواب) والسحبُ فوقه لم يكن مشروطاً (‏خطأ).
        //
        // فالقاعدةُ الآن واحدة: **تحويلٌ بلا طرفٍ مقابلٍ ليس تحويلاً**. لا
        // يُكتب سطرُ سحبٍ ولا يُخصم رصيدٌ ولا يُرحَّل قيدٌ ما لم يوجد مستقبِلٌ
        // مغايرٌ للمصدر. والمالُ يبقى في الدرج — وهو الصدق: لم يستلمه أحد.
        final central = await getCentralSafe();
        if (central == null) {
          unawaited(DiagnosticLogger.log(
            'SHIFT-CLOSE-NO-CENTRAL',
            'safeId=$sId amount=$actualDrain — الصندوق الرئيسي مش موجود، '
                'التسليم اتوقف والفلوس فضلت في الدرج. اعمل خزينة اسمها '
                '"$kCentralSafeName" من شاشة إدارة الصناديق.',
          ));
          continue;
        }
        if (central.id == sId) {
          // الورديةُ على المركزيّ نفسِه: طرفا التحويل واحدٌ فحركتُه صفر.
          continue;
        }

        // Spec 136 ISS-8 (supersedes Spec 107 Model A): balanceAfter is the
        // safe's REMAINING balance after draining only this shift's net — NOT
        // zero, because other shifts' contributions and the opening float stay
        // in the till.
        final balanceAfterDrain = safe.balance - actualDrain;
        final shiftClosingTxnId = await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNo,
            safeId: sId,
            transactionType: 'withdrawal',
            category: 'shift_closing',
            amount: actualDrain,
            balanceAfter: balanceAfterDrain,
            description: Value(
                'إقفال وردية #$shiftId — تحويل حصة الوردية من ${safe.name} إلى الإدارة'),
            createdAt: Value(endTime),
            userId: Value(shift.userId),
            referenceType: const Value('shift_closing'),
            referenceId: Value(shiftId),
            globalId: Value(zeroOutGlobalId),
          ),
        );

        // Spec 107 (Model A): drain the full balance atomically. Uses the
        // Spec 069 atomic helper to avoid the read-then-write race that an
        // absolute `SET balance = 0` would expose if another transaction
        // touched this safe between our read and our write.
        await adjustSafeBalance(sId, -actualDrain);

        // ── الطرف المستقبِل: الصندوق الرئيسي (الإدارة المركزية) ────────────
        //
        // السحب فوق كان بيتم **بلا خزينة مستقبِلة**، فمجموع أرصدة الخزائن
        // بيقلّ كل وردية وينحرف عن حساب النقدية في الأستاذ — واللي بيفضل صح
        // لأن النقدية اتقيّدت على ١١١١ من ساعة البيع. وصف سطر السحب نفسه
        // بيقول «تحويل حصة الوردية إلى الإدارة»: النية كانت موجودة والطرف
        // ده هو اللي كان ناقص.
        //
        // مفيش قيد يومية هنا **عن قصد**: الخزنتين بيقعوا على نفس حساب
        // النقدية، فالحركة داخل نفس الحساب ومفيش حاجة تتحرك في الأستاذ. قيد
        // بصفر كان بيدّي إحساس كاذب إن فيه ترحيل حصل.
        // المستقبِلُ محسومٌ فوق (‏موجودٌ ومغايرٌ للمصدر)، فهذا السطرُ ليس
        // «أفضلَ جهد»: فشلُه يعني سحباً بلا استلام — وهو عينُ العطب. فيُترك
        // بلا `try` كي تُسقط أيُّ إخفاقةٍ معاملةَ الإقفال كلَّها بدل أن
        // تُخلّف مالاً مسحوباً لا يملكه أحد.
        await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNo,
            safeId: central.id,
            transactionType: 'receipt',
            category: 'shift_closing',
            amount: actualDrain,
            balanceAfter: central.balance + actualDrain,
            description:
                Value('إقفال وردية #$shiftId — استلام حصة ${safe.name}'),
            createdAt: Value(endTime),
            userId: Value(shift.userId),
            referenceType: const Value('shift_closing'),
            referenceId: Value(shiftId),
            globalId: Value('$zeroOutGlobalId-central'),
          ),
        );
        await adjustSafeBalance(central.id, actualDrain);

        // Post a GL journal entry for this safe's shift-close transfer.
        // Credit: the safe's own linked GL account.
        // Debit:  same-type purpose account (cash safe → cash, bank safe → bank).
        try {
          Account? sourceAccount;
          if (safe.linkedAccountId != null) {
            sourceAccount = await accountingDao.getAccountById(safe.linkedAccountId!);
          }
          sourceAccount ??= safe.safeType == 'bank'
              ? await accountingDao.getAccountByPurpose('bank')
              : await accountingDao.getAccountByPurpose('cash');

          final destAccount = safe.safeType == 'bank'
              ? await accountingDao.getAccountByPurpose('bank')
              : await accountingDao.getAccountByPurpose('cash');

          if (sourceAccount != null && destAccount != null) {
            // Spec 135 BUG-F — deterministic globalId for the shift-close
            // transfer JE. Previously this createJournalEntry omitted
            // globalId, so it fell back to a random UuidV7 (see
            // accounting_dao_writes.dart:30), and `referenceId` was the
            // LOCAL autoincrement `shiftClosingTxnId` (different on client
            // vs server). Neither the globalId UNIQUE constraint nor the
            // (referenceType, referenceId) dedup could match across
            // instances → the client JE AND the server JE both survived
            // DeltaPull → duplicate "تحويل رصيد صندوق" entries on the
            // server (field-observed JE-2026-00284/285/286).
            //
            // Fix mirrors the variance JE (this file, ~line 567): derive
            // a canonical `je-shiftclose-<sourceGid>-transfer` from the
            // already-deterministic `zeroOutGlobalId` (itself keyed on the
            // shift+safe globalIds via deriveShiftClosingGlobalId). One
            // transfer JE per (shift, safe); client and server converge on
            // the same id; the UNIQUE constraint catches the duplicate at
            // INSERT. Legacy rows whose shift/safe globalId was missing
            // already fell back to a random zeroOutGlobalId above, so this
            // derives a (still-unique-per-side) value for them — same
            // degraded-dedup behaviour as before for those rare rows.
            final transferJeGid = JournalEntryGid.compute(
              sourceType: JournalEntryGid.sourceShiftClose,
              sourceGid: zeroOutGlobalId,
              verb: 'transfer',
            );
            unawaited(DiagnosticLogger.log(
              DiagnosticLogger.gidAutopost,
              'sourceType=shiftclose sourceGid=${zeroOutGlobalId.length >= 8 ? zeroOutGlobalId.substring(0, 8) : zeroOutGlobalId} '
              'verb=transfer shiftId=$shiftId safeId=$sId',
            ));
            await accountingDao.createJournalEntry(
              description: 'إقفال وردية #$shiftId — ${safe.name} ($voucherNo)',
              date: endTime,
              lines: [
                JournalLine(
                  accountId: destAccount.id,
                  debit: actualDrain,
                  description: 'إقفال وردية — تحويل رصيد ${safe.name}',
                ),
                JournalLine(
                  accountId: sourceAccount.id,
                  credit: actualDrain,
                  description: 'إقفال وردية — ${safe.name}',
                ),
              ],
              referenceType: 'shift_closing',
              referenceId: shiftClosingTxnId, // unique per safe per shift
              isAutoPosted: true,
              branchId: safe.branchId,
              globalId: transferJeGid,
            );
          }
        } catch (e) {
          debugPrint('[TreasuryDao] Shift-close JE failed for safe #$sId: $e');
        }

        // 2026-05-12 NEG-BAL hotfix (Feature 035 v123) — DO NOT mirror this
        // shift_closing safe_txn from CLIENT. The server-side `_closeShiftSafes`
        // (now invoked reliably by the v119 globalId fix at /api/shifts/close)
        // already creates the SAME row server-side with `referenceId =
        // SERVER's shift id`. The client mirror used `referenceId = CLIENT's
        // local shift id`, which bypassed the
        // `(safeId, referenceType, referenceId)` idempotency check at
        // line 622, producing TWO `shift_closing` rows per (safe, shift) on
        // the server → safes.balance drifted negative → next shift's close JE
        // emitted negative debit/credit values (field-observed JE-2026-00063).
        //
        // Tactical fix: skip the mirror when running in CLIENT/MIRROR mode.
        // The /api/shifts/close handler is the single source of truth for the
        // server-side shift_closing row (Constitution R4). Standalone-mode
        // calls fall through (SyncInterceptor.isClientMode is false but
        // .instance is null too, so the call no-ops naturally).
        //
        // Permanent fix tracked in `specs/041-shift-closing-globalid-dedup/`
        // (Route B.1 — deterministic UUIDv5 keyed on shift+safe globalIds —
        // makes both paths converge on the same safe-txn globalId so the
        // existing globalId UNIQUE constraint catches the duplicate). Until
        // 041 ships, this skip is the bleeding-edge stop.
        if (!SyncInterceptor.isClientMode) {
          try {
            await SyncInterceptor.instance?.submitSafeTransaction(
              safeId: sId,
              transactionType: 'withdrawal',
              amount: actualDrain,
              category: 'shift_closing',
              description: 'تصفير رصيد الخزينة عند إغلاق الوردية #$shiftId',
              userId: shift.userId,
              referenceType: 'shift_closing',
              referenceId: shiftId,
              // Spec 007 / FR-011 / T019.B: thread the zero-out's locally-minted
              // globalId so server stores the row under the same UUID as the
              // local insert above. Prevents mirror duplicate after DeltaPull.
              globalId: zeroOutGlobalId,
            );
          } catch (e) {
            debugPrint('[TreasuryDao] Failed to sync zero-out: $e');
          }
        } else {
          debugPrint('[TreasuryDao] _closeShiftSafes: skipping client mirror '
              'of shift_closing safe_txn for safe #$sId — server\'s '
              '/api/shifts/close handler is the single source of truth '
              '(NEG-BAL hotfix v123, see specs/041).');
        }
      } else {
        // Spec 136 item 6 — breadcrumb so a no-op shift-close drain is
        // visible instead of silently skipped: this safe carried no net
        // balance from this shift (opening float + other shifts'
        // contributions intentionally stay in the till — Spec 136 ISS-8).
        unawaited(DiagnosticLogger.log(
            'SHIFT-DRAIN-SKIP',
            'shift #$shiftId safe #$sId: net shift balance '
            '${balanceToZero.toStringAsFixed(3)} ≤ 0.001 — no shift-close '
            'drain posted (nothing to transfer to admin).'));
      }
    }
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

  // ═══════════════════════════════════════════════════════════════════════
  // SAFE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all active safes
  Stream<List<Safe>> watchAllSafes() {
    return (select(safes)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .watch();
  }

  /// Feature 005 Phase 8 — branch-scoped variant of [watchAllSafes].
  ///
  /// Returns the active safes whose `branch_id` is in [branchIds] (or NULL,
  /// which we keep visible so legacy safes that never got a branch link
  /// still show up). Pass `null` for full access (admin / financial manager)
  /// — the call then degrades to [watchAllSafes].
  ///
  /// Bug fix: the treasury screen used to call [watchAllSafes] regardless of
  /// the user's role, so a branch-scoped manager (e.g. "مدير فرع العقبة")
  /// saw safes from every other branch in the list. This is the corrective
  /// query — pair it with `branchScopeProvider.allowedBranchIds` in the
  /// Riverpod layer.
  Stream<List<Safe>> watchSafesForBranches(Set<int>? branchIds) {
    if (branchIds == null) return watchAllSafes();
    return (select(safes)
          ..where((s) =>
              s.isActive.equals(true) &
              (s.branchId.isIn(branchIds) | s.branchId.isNull()))
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .watch();
  }

  /// Get default safe
  Future<Safe?> getDefaultSafe() {
    return (select(safes)
          ..where((s) => s.isDefault.equals(true) & s.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Get safe by ID
  Future<Safe?> getSafeById(int id) {
    return (select(safes)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  /// Get default safe by type (cash/bank)
  Future<Safe?> getDefaultSafeByType(String type) {
    return (select(safes)
          ..where(
            (s) =>
                s.safeType.equals(type) &
                s.isDefault.equals(true) &
                s.isActive.equals(true),
          )
          ..limit(1))
        .getSingleOrNull()
        .then((safe) async {
          if (safe != null) return safe;
          // Fallback to any safe of that type if no default is marked
          return (select(safes)
                ..where(
                  (s) => s.safeType.equals(type) & s.isActive.equals(true),
                )
                ..limit(1))
              .getSingleOrNull();
        });
  }

  /// الورديّةُ التي تحكم **درجَ** [userId] الآن، أو `null` إن لم توجد.
  ///
  /// المصدرُ الوحيد لسؤال «هل يجوز أن يخرج نقدٌ الآن؟» (‏ح‑١، مواصفة
  /// 2026-08-18) — يستعمله حارسُ `processSalesReturn` وحارسُ المرتجع السريع
  /// في `sales_transaction_orchestrator`.
  ///
  /// ⚠️ السؤالُ عن **الدرج** لا عن المستخدم، ولذلك يقبل ورديّةَ غيرِه على
  /// فرعه: `_settleShift` يحسب `expectedCash` من `drawerTxs` **بلا فلترِ
  /// مستخدم** عن قصدٍ منصوصٍ عليه («الدرجُ واحدٌ يشترك فيه كلُّ من مسّه»)،
  /// فحركةُ مديرٍ على درج الكاشير تدخل توقّعَ ورديّة الكاشير ولا تُنتج عجزاً.
  /// ومديرُ النظام لا يفتح ورديّةً لنفسه أصلاً بل يلتحق بورديّة الكاشير
  /// (Spec 135 NOTE 2)، فحصرُ السؤال في ورديّته كان رفضاً باطلاً.
  Future<Shift?> resolveOpenShiftForDrawer(int userId) async {
    final own = await getCurrentOpenShift(userId);
    if (own != null) return own;
    final branchId = await getUserBranchId(userId);
    final onBranch = await getOpenShiftsForBranch(branchId: branchId);
    return onBranch.isEmpty ? null : onBranch.first;
  }

  /// سُلَّمُ اختيارِ الخزنةِ لأيّ حركةِ مالٍ — المصدرُ الوحيد.
  ///
  /// استُخرج من `_recordSalesReceipt` (مسارُ البيع) ليستعمله مسارُ المرتجع
  /// أيضاً: كان المرتجعُ ينادي `getDefaultSafeByType` مباشرةً، فيخصم من
  /// **الخزنةِ الافتراضيّةِ العامّة** أيّاً كان فرعُ من يُجري المرتجع — نقدٌ
  /// يخرج من درجِ فرعٍ ورقٌ يُسلَّم في فرعٍ آخر.
  ///
  /// الأولويّات:
  ///   * P1 — [specificSafeId] صريحٌ ونشط.
  ///   * P2‑أ — [preferredBranchId]: فرعٌ يعرفه النداءُ يقيناً (فرعُ الورديّة
  ///     المفتوحة في مسار المرتجع = الفرعُ القائمُ بالعمليّة فعلاً).
  ///   * P2‑ب — الفرعُ المشتقُّ من [warehouseId] (سلوكُ مسار البيع القائم).
  ///   * P3 — الافتراضيّةُ العامّة.
  ///
  /// ولا تُرجِع `null` أبداً: تعذُّرُ الخزنةِ **يرمي**. وهذا مقصودٌ بنيويّاً —
  /// نداءٌ يُرجَع له `null` يُغري بـ`if (safe != null)` بلا `else`، فتمضي
  /// العمليّةُ ويُرحَّل قيدٌ يقول «تحرّك نقد» والدرجُ ساكن. وهو ما كان يفعله
  /// مسارُ المرتجع بالضبط. (‏ح‑٣ في مواصفة 2026-08-18.)
  ///
  /// [operationLabel] و[noSafeMessage] للتشخيص ولرسالةِ المستخدم — تختلف
  /// بين بيعةٍ («الفاتورة لم تُحفظ») ومرتجعٍ («المرتجع لم يُحفظ»).
  Future<Safe> resolveSafeForOperation({
    required String safeType,
    required String operationLabel,
    required String noSafeMessage,
    int? specificSafeId,
    int? preferredBranchId,
    int? warehouseId,
  }) async {
    Safe? targetSafe;
    var reason = 'unknown';

    // ── P1: تجاوزٌ صريح ──
    if (specificSafeId != null) {
      targetSafe = await (select(safes)
            ..where((s) => s.id.equals(specificSafeId) & s.isActive.equals(true)))
          .getSingleOrNull();
      if (targetSafe != null) {
        reason = 'P1-explicit(id=$specificSafeId)';
      } else {
        debugPrint('[SafeRoute] ⚠ P1: explicit safeId=$specificSafeId '
            'not found/inactive, falling through');
      }
    }

    // ── P2‑أ: فرعٌ يعرفه النداءُ يقيناً ──
    if (targetSafe == null && preferredBranchId != null) {
      targetSafe = await _safeForBranch(preferredBranchId, safeType);
      if (targetSafe != null) {
        reason = 'P2a-preferredBranch(branchId=$preferredBranchId,type=$safeType)';
      } else {
        debugPrint('[SafeRoute] ⚠ P2a: no $safeType safe for '
            'preferredBranchId=$preferredBranchId — trying warehouse branch');
      }
    }

    // ── P2‑ب: الفرعُ المشتقُّ من المخزن ──
    if (targetSafe == null && warehouseId != null) {
      final warehouse = await (select(warehouses)
            ..where((w) => w.id.equals(warehouseId)))
          .getSingleOrNull();
      final whBranchId = warehouse?.branchId;
      if (whBranchId != null) {
        targetSafe = await _safeForBranch(whBranchId, safeType);
        if (targetSafe != null) {
          reason = 'P2-branch(branchId=$whBranchId,type=$safeType)';
        } else {
          debugPrint('[SafeRoute] ⚠ P2: no $safeType safe for '
              'branchId=$whBranchId (warehouseId=$warehouseId) — '
              'falling to system default');
        }
      } else {
        debugPrint('[SafeRoute] ⚠ P2: warehouseId=$warehouseId has no branchId '
            '— skipping branch-aware lookup');
      }
    }

    // ── P3: الافتراضيّةُ العامّة — آخرُ ملاذ ──
    if (targetSafe == null) {
      targetSafe = await getDefaultSafeByType(safeType);
      if (targetSafe != null) {
        reason = 'P3-systemDefault(type=$safeType,id=${targetSafe.id})';
        debugPrint('[SafeRoute] ⚠ P3 used for $operationLabel → '
            'safe "${targetSafe.name}" (${targetSafe.id})');
      }
    }

    if (targetSafe == null) {
      // H1 · كان `return` صامتاً في مسار البيع: الفاتورةُ تُحفظ وقيدُها
      // يُقيَّد (مدين نقدية) **والدرجُ لا يتحرّك إطلاقاً** ⇒ عجزٌ عند الإقفال
      // بحجم البيعة، وحسابُ النقدية في الأستاذ ينفصل عن الخزائن. ولا رسالةَ
      // للكاشير ولا صفَّ فشلٍ يُراجَع — البيعةُ تبدو ناجحة.
      //
      // والرميُ يرجّع المعاملةَ كلَّها (النداءاتُ كلُّها من داخل معاملة)، فلا
      // يبقى نصفُ عملية: إما عمليّةٌ كاملةٌ بنقديةٍ مقيَّدة، أو لا شيء.
      debugPrint('[SafeRoute] ✗ No safe found for $operationLabel '
          'safeType=$safeType warehouseId=$warehouseId '
          'preferredBranchId=$preferredBranchId');
      throw Exception(noSafeMessage);
    }

    debugPrint('[SafeRoute] ✓ $operationLabel → safe "${targetSafe.name}" '
        '(id=${targetSafe.id}, type=${targetSafe.safeType}, '
        'branch=${targetSafe.branchId}) [$reason]');
    return targetSafe;
  }

  /// أنشطُ خزائنِ [branchId] من [safeType]، والمعلَّمةُ افتراضيّةً أوّلاً.
  Future<Safe?> _safeForBranch(int branchId, String safeType) {
    return (select(safes)
          ..where((s) =>
              s.branchId.equals(branchId) &
              s.safeType.equals(safeType) &
              s.isActive.equals(true))
          ..orderBy([
            (s) => OrderingTerm(expression: s.isDefault, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Get total cash balance across all safes (legacy, merges all types)
  Future<double> getTotalCashBalance() async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(balance), 0) as total FROM safes WHERE is_active = 1',
      readsFrom: {safes},
    ).getSingle();
    return result.data['total'] as double? ?? 0;
  }

  /// Get aggregated safe balances grouped by safeType (e.g., 'cash', 'bank')
  Future<Map<String, double>> getSafesBalancesByType({
    Set<int>? allowedBranchIds,
  }) async {
    // Spec 151 D-01: branch-scope the summary balance cards too. Without this,
    // a branch-scoped treasury report showed company-wide cash/bank totals
    // beside its (now scoped) voucher list. Same semantics as the voucher cap:
    // null = company-wide; {} = fail-closed; {ids} = those branches OR
    // NULL-branch (shared / head-office) safes. Inlined (not via the shared
    // helper) because this DAO extension can't see TreasuryReportsDao's copy.
    final vars = <Variable>[];
    var scope = '';
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        scope = ' AND 1 = 0';
      } else {
        final ph = allowedBranchIds.map((_) => '?').join(', ');
        scope = ' AND (branch_id IN ($ph) OR branch_id IS NULL)';
        vars.addAll(allowedBranchIds.map((e) => Variable<int>(e)));
      }
    }
    final results = await customSelect(
      'SELECT safe_type, SUM(balance) as total FROM safes '
      'WHERE is_active = 1$scope GROUP BY safe_type',
      variables: vars,
      readsFrom: {safes},
    ).get();

    return {
      for (final row in results)
        row.data['safe_type'] as String: row.data['total'] as double? ?? 0.0,
    };
  }

  /// Set safe balance to an ABSOLUTE value.
  ///
  /// **Use sparingly** — most call sites should use [adjustSafeBalance]
  /// (delta-based) instead. This setter is appropriate ONLY for:
  ///  - Reconciliation flows that authoritatively re-set the balance to a
  ///    computed total (e.g. `reconciliation_service.dart`).
  ///  - One-off corrections by the accountant via the safes settings UI.
  ///
  /// For ANY routine "balance went up/down by N" path (sale, return,
  /// receipt voucher, payment voucher, transfer), use [adjustSafeBalance]
  /// — it is immune to the read-then-write lost-update race that bites
  /// under PostgreSQL's default Read-Committed isolation. (Spec 069 / D5-003.)
  Future<void> updateSafeBalance(int safeId, double newBalance) async {
    // T-01: SECURITY — Audit trail: log old vs new balance
    // NOTE: Activity log insert REMOVED from inside transactions to prevent
    // PostgreSQL transaction abort (25P02). On PG, any error in a try-catch
    // still aborts the entire transaction unlike SQLite.
    // The audit log can be added AFTER the transaction completes.

    await (update(safes)..where((s) => s.id.equals(safeId))).write(
      SafesCompanion(balance: Value(newBalance)),
    );
    // الكتابةُ المطلقة مشروعةٌ في مواضعَ معدودة (مصالحة · تصحيحُ محاسب ·
    // فرعُ `else` في `createSafeTransaction`). ظهورُها في التشغيلة اليدوية
    // بجوار حركةِ بيعٍ يعني أن مساراً روتينياً عاد إليها.
    unawaited(DiagnosticLogger.log(DiagnosticLogger.safeMove,
        'safe=$safeId abs=$newBalance via=absolute'));
  }

  /// 069 (D5-003) — Atomically adjust a safe's balance by [delta].
  ///
  /// Issues `UPDATE safes SET balance = balance + ? WHERE id = ?`. The
  /// arithmetic happens at the SQL layer, so two concurrent +100 calls
  /// against the same safe land as +200 (not +100 with one lost) regardless
  /// of isolation level. Required for PostgreSQL Read-Committed safety;
  /// no-cost on SQLite.
  ///
  /// Pass a NEGATIVE delta to decrease the balance (e.g. payment voucher
  /// of 100 → `adjustSafeBalance(safeId, -100)`).
  Future<void> adjustSafeBalance(int safeId, double delta) async {
    await customStatement(
      'UPDATE safes SET balance = balance + ? WHERE id = ?',
      [delta, safeId],
    );
    // أثرُ التشغيلة اليدوية — سطرٌ لكلّ حركة. سطران متطابقان لنفس الخزنة =
    // تطبيقٌ مزدوج. `unawaited` كي لا يدخل زمنُ الملفّ في زمن المعاملة.
    unawaited(DiagnosticLogger.log(
        DiagnosticLogger.safeMove, 'safe=$safeId delta=$delta via=adjust'));
  }

  /// Low-level safe transaction with full accounting treatment (Moved from database.dart)
  /// HARDENED: Safe balance now recalculated inside transaction to prevent Lost Update
  Future<int> createSafeTransaction(SafeTransactionsCompanion trans) async {
    return transaction(() async {
      // 0. Soft/Hard Period Closing Gating
      final dateToValidate = trans.createdAt.present ? trans.createdAt.value : DateTime.now();
      await accountingDao.validateFinancialPeriod(dateToValidate, operation: 'حركة خزينة');

      // Insert the transaction record
      final transactionId = await into(safeTransactions).insert(trans);

      // CRITICAL: Atomic balance update to prevent Lost Update race condition.
      // Uses SQL-level arithmetic (balance + amount) instead of read-then-write.
      final safeId = trans.safeId.value;
      final amount = trans.amount.value;
      final transType = trans.transactionType.value;

      // الحركةُ نفسُها قبل أثرِها على الرصيد — تربط سطرَ `SAFE-MOVE` التالي
      // بسببه، فيُقرأ السجلُّ قصّةً لا أرقاماً متناثرة.
      unawaited(DiagnosticLogger.log(
          DiagnosticLogger.safeMove,
          'txn safe=$safeId type=$transType amount=$amount '
          'category=${trans.category.value} ref=${trans.referenceType.present ? trans.referenceType.value : '-'}'));

      if (transType == 'deposit' || transType == 'receipt') {
        // Atomic increment: SET balance = balance + amount
        await customStatement(
          'UPDATE safes SET balance = balance + ? WHERE id = ?',
          [amount, safeId],
        );
      } else if (transType == 'withdrawal' || transType == 'payment') {
        // Atomic decrement: SET balance = balance - amount
        await customStatement(
          'UPDATE safes SET balance = balance - ? WHERE id = ?',
          [amount, safeId],
        );
      } else if (transType == 'closing') {
        // 'closing' is a daily/shift close that empties the safe.
        await customStatement(
          'UPDATE safes SET balance = 0 WHERE id = ?',
          [safeId],
        );
      } else {
        // transfer, adjustment, memo — use the provided balanceAfter
        await updateSafeBalance(safeId, trans.balanceAfter.value);
      }

      // Update party balance if this is a party-related transaction
      if (trans.partyId.present && trans.partyId.value != null) {
        final partyId = trans.partyId.value!;

        // Receipt from customer: reduce their outstanding balance (they owed us, now paying)
        // Payment to supplier: reduce our outstanding balance to them
        if (transType == 'receipt') {
          await adjustPartyBalance(partyId, -amount); // Reduce customer's debt
        } else if (transType == 'payment') {
          await adjustPartyBalance(
            partyId,
            -amount,
          ); // Reduce our debt to supplier
        }
      }

      return transactionId;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TRANSACTION OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch transactions for a date range
  Stream<List<SafeTransactionData>> watchTransactions({
    DateTime? from,
    DateTime? to,
  }) {
    from ??= DateTime.now().subtract(const Duration(days: 30));
    to ??= DateTime.now().add(const Duration(days: 1));

    return (select(safeTransactions)
          ..where((t) => t.createdAt.isBetween(Variable(from!), Variable(to!)))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Watch recent transactions (limited to 50)
  Stream<List<SafeTransactionData>> watchRecentTransactions() {
    return (select(safeTransactions)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(50))
        .watch();
  }

  /// Issue 14 — branch-scoped variant of [watchRecentTransactions].
  ///
  /// `branchIds` is the set returned by `branchScopeProvider`:
  ///   • `null` → full access (admin / financial manager) — same behaviour
  ///     as [watchRecentTransactions], no branch filter.
  ///   • non-null → restrict rows to safe_transactions whose `safeId`
  ///     belongs to a safe linked to one of those branches. Safes with a
  ///     null `branchId` are intentionally included so legacy unscoped
  ///     vouchers (e.g. seed data, pre-v133 rows) don't disappear from
  ///     restricted users' lists.
  ///
  /// Implementation note: a JOIN-based stream keeps the watcher tied to
  /// both tables so the list updates when either a transaction or a
  /// safe's branch changes (e.g. admin moves a safe between branches).
  Stream<List<SafeTransactionData>> watchRecentTransactionsForBranches(
    Set<int>? branchIds,
  ) {
    if (branchIds == null) return watchRecentTransactions();

    final query = select(safeTransactions).join([
      innerJoin(safes, safes.id.equalsExp(safeTransactions.safeId)),
    ])
      ..where(safeTransactions.deletedAt.isNull() &
          (safes.branchId.isIn(branchIds) | safes.branchId.isNull()))
      ..orderBy([OrderingTerm.desc(safeTransactions.createdAt)])
      ..limit(50);
    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(safeTransactions)).toList());
  }

  /// Create a receipt voucher (سند قبض)
  ///
  /// TODO(accounting-integrity): No `deleteReceiptVoucher` / admin-delete flow
  /// exists yet for receipts. When one is added, it MUST route through
  /// `reverseAutoPostedJournalEntriesFor(referenceType: 'receipt_voucher',
  /// voidReferenceType: 'receipt_voucher_void', ...)` inside the same
  /// transaction that soft-deletes the safe_transactions row, mirroring
  /// what `deleteExpenseTransaction` does for payment vouchers. Otherwise
  /// deleting a receipt will leave its auto-posted JE on the books and
  /// break trial balance / GL.
  Future<int> createReceiptVoucher({
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? costCenterId,
    int? linkedAccountId, // GAP-03: Custom GL account from COA
    /// Optional pre-generated UUID. When the voucher is being created as
    /// part of a client→server sync and the SAME logical voucher is being
    /// written on both ends (Issue 12), pass the same globalId to both
    /// calls so SafeTransactionSyncStrategy dedupes by UUID instead of
    /// inserting a phantom second row. When null, a fresh UUID is minted.
    String? globalId,
    // Spec 133 — symmetric with createPaymentVoucher (Spec 081). When the
    // receipt voucher represents a cheque (not cash), the commercial-papers
    // autopost owns BOTH the customer-credit JE (Dr: Notes Receivable, Cr:
    // Customer) AND the parties.balance adjustment via
    // _cpApplyBalanceSideEffects. Running the cash-leg JE + safe transaction
    // + party-balance adjust here too produced a double customer credit
    // (one row from the voucher path, one from the autopost). When
    // skipJournalEntry == true the cash-leg JE is suppressed; when
    // skipSafeTransaction == true the entire safe lookup + insert +
    // balance update + party adjust + fire-and-forget sync is suppressed.
    // For cheque receipts the caller passes BOTH true (no cash arrived,
    // no JE belongs here).
    bool skipJournalEntry = false,
    bool skipSafeTransaction = false,
    // Spec 135 BUG-C — the branch the OPERATOR is working in, threaded from
    // the voucher dialog (activeBranchIdProvider) and, on the server, from the
    // client's branchId. The voucher JE was attributed to targetSafe.branchId,
    // so a receipt taken in branch B into a safe that belongs to branch A
    // landed on A's books. Prefer the operating branch; fall back to the
    // safe's branch when the caller didn't supply one (legacy/standalone).
    // NOT an R9-gate issue (the push predicate is correct) — purely JE branch
    // attribution. Mirrors the manual-JE fix in drift_accounting_repository.
    int? operatingBranchId,
  }) async {
    return transaction(() async {
      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(DateTime.now(), operation: 'سند قبض');

      int transactionId = 0;

      if (!skipSafeTransaction) {
        // Phase 5B.5 (Issue 7) — on client mode, an absent safeId is a
        // dialog/UX bug, not an "use the default" prompt. Falling back to
        // getDefaultSafe() silently posted to whichever safe happened to
        // be flagged default for the device — frequently the WRONG one
        // when the user explicitly picked a branch-specific safe in the
        // dialog (the dialog had a stale state). Reject loudly so the
        // failure surfaces in the UI instead of corrupting the GL.
        // Server mode and standalone mode keep the default-safe fallback
        // — those flows never expose a safe picker to the user, so there
        // IS no "explicit selection" to honour.
        if (safeId == null && SyncInterceptor.isClientMode) {
          throw StateError(
              'safeId required on client mode — no default-safe fallback. '
              'The receipt-voucher dialog must enforce a safe selection '
              'before submit (see Phase 5B.6).');
        }

        Safe? targetSafe;
        if (safeId != null) {
          targetSafe = await (select(
            safes,
          )..where((s) => s.id.equals(safeId))).getSingleOrNull();
        } else {
          targetSafe = await getDefaultSafe();
        }

        if (targetSafe == null) throw Exception('No target safe found');

        // ── مركزُ تكلفة الخزنة يُورَّث حين لا يحدّده المنادي ──────────────
        //
        // شاشةُ إدارة الصناديق تربط كلَّ خزنةٍ بمركز تكلفة، وكان الربطُ
        // **لا يقرؤه أحد**: هذا المسارُ يكتب مركزَ المنادي وحدَه، فسندٌ من
        // حوارٍ لا يسأل عن مركزٍ يقع بلا مركزٍ مهما كانت خزنتُه مربوطة —
        // والمشغّلُ يفتح تقريرَ مراكز التكلفة فلا يجد حركةَ الخزنة فيه.
        // (‏نفسُ فئة §٣-ب: سطحُ إعدادٍ يكتب قيمةً لا يقرؤها أحد.)
        //
        // والفرعُ كان يصل سلفاً (`operatingBranchId ?? targetSafe.branchId`
        // تحت) — فهذا يُكمل الطرفَ الناقص لا يُنشئ نمطاً جديداً.
        //
        // ⚠️ سدُّ فراغٍ لا تجاوزٌ على اختيار: مركزُ المنادي الصريحُ أولى
        // دائماً، وخزنةٌ بلا مركزٍ تُبقي الحركةَ بلا مركزٍ ولا تخترع واحداً.
        final effectiveCostCenterId = costCenterId ?? targetSafe.costCenterId;

        final newBalance = targetSafe.balance + amount;
        final voucherNumber = await generateInvoiceNumber('RV');

        // Phase 5B.1 (Issues 1 + 7) — capture the effective globalId BEFORE
        // the safe-transaction insert so the journal entry can derive its
        // own deterministic globalId from it. Both client and server run
        // this DAO (server inside postReceipt). Without a stable JE globalId
        // each side wrote a JE with a random UUID, and the next pull
        // duplicated the entry in the General Ledger. With deterministic
        // identity, JournalSyncStrategy's Tier 1 match dedups cleanly.
        final effectiveGlobalId = globalId ?? UuidV7.generate();

        transactionId = await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNumber,
            safeId: targetSafe.id,
            transactionType: 'receipt',
            category: category,
            amount: amount,
            discount: Value(discount),
            balanceAfter: newBalance,
            partyId: Value(partyId),
            description: Value(description),
            userId: Value(userId),
            costCenterId: Value(effectiveCostCenterId),
            globalId: Value(effectiveGlobalId),
          ),
        );

        // H15 — سندُ قبضٍ: زيادةٌ ذرّية. سندان متزامنان على نفس الخزنة كانا
        // يقرآن نفسَ الرصيد فيضيع أحدُ المبلغين. `newBalance` لقطةٌ لا أمر.
        await adjustSafeBalance(targetSafe.id, amount);

        // Spec 133 — party balance adjustment belongs INSIDE the
        // skipSafeTransaction guard. For cheque receipts the commercial
        // papers pipeline owns the AR side-effect via
        // `_cpApplyBalanceSideEffects` (commercial_papers_dao.dart); running
        // it here too caused parties.balance to decrement twice (mirrors
        // the Spec 081 fix on the payment side).
        if (partyId != null) {
          await adjustPartyBalance(partyId, -(amount + discount));
        }

        if (!skipJournalEntry) {
          // Create journal entry for financial reporting
          await _createVoucherJournalEntry(
            voucherNumber: voucherNumber,
            amount: amount,
            discount: discount,
            category: category,
            description: description ?? 'سند قبض',
            isReceipt: true,
            transactionId: transactionId,
            costCenterId: effectiveCostCenterId,
            branchId: operatingBranchId ?? targetSafe.branchId, // Spec 135 BUG-C
            linkedAccountId: linkedAccountId, // GAP-03
            safeId: targetSafe.id, // Use safe's linked account for cash side
            partyId: partyId, // Issue 4 (Feature 022): party AR sub-account
            safeTransactionGlobalId: effectiveGlobalId,
          );
        }

        // ── Client → Server sync (fire-and-forget) ──
        // Spec 087 (F2) — look up the party's globalId so the server
        // resolves to ITS partyId (different autoincrement on mirror)
        // and the safe-transaction row lands with the right party link
        // → voucher appears in the customer/supplier statement.
        String? receiptPartyGid;
        if (partyId != null) {
          final partyRow = await (select(parties)
                ..where((p) => p.id.equals(partyId))
                ..limit(1))
              .getSingleOrNull();
          receiptPartyGid = partyRow?.globalId;
        }
        try {
          await SyncInterceptor.instance?.submitSafeTransaction(
            safeId: targetSafe.id,
            transactionType: 'receipt',
            amount: amount,
            category: category,
            description: description,
            userId: userId,
            referenceType: 'receipt_voucher',
            referenceId: transactionId,
            // Phase 5B.4 (Issue 7) — surface the safe's globalId + the
            // dialog-selected cost center so the server resolves to ITS
            // safe.id (different autoincrement) and stamps the JE with
            // the right cost center instead of a default fallback.
            globalId: effectiveGlobalId,
            safeGlobalId: targetSafe.globalId,
            costCenterId: effectiveCostCenterId,
            partyId: partyId,
            partyGlobalId: receiptPartyGid,
          );
        } catch (e) {
          debugPrint('[TREASURY-SYNC] Receipt voucher sync failed: $e');
        }
      }

      return transactionId;
    });
  }

  /// Create a payment voucher (سند صرف)
  Future<int> createPaymentVoucher({
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? costCenterId,
    /// Optional pre-generated UUID. When the voucher is being created as
    /// part of a client→server sync and the SAME logical voucher is being
    /// written on both ends, pass the same globalId to both calls so that
    /// pull-sync (SafeTransactionSyncStrategy) dedupes by UUID instead of
    /// creating a phantom second row. When null, a fresh UUID is minted.
    String? globalId,
    // When true, skips the cash/bank journal entry because the commercial
    // papers system already creates the correct accounting entry (Dr: Payables,
    // Cr: Notes Payable) upon check issuance.  Avoids duplicate JEs.
    bool skipJournalEntry = false,
    // When true, skips safe lookup / safe transaction / balance update entirely.
    // Used for check payments where no physical cash leaves the safe.
    bool skipSafeTransaction = false,
    // Spec 135 BUG-C — operator's working branch (see createReceiptVoucher).
    // Prefer it for the JE branch; fall back to targetSafe.branchId.
    int? operatingBranchId,
  }) async {
    return transaction(() async {
      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(DateTime.now(), operation: 'سند صرف');

      int transactionId = 0;

      if (!skipSafeTransaction) {
        // Phase 5B.5 (Issue 7) — same rationale as createReceiptVoucher.
        // On client mode the safe MUST be explicit. The voucher dialog is
        // responsible for enforcing this (5B.6); reaching the DAO with a
        // null safeId means the caller bypassed the dialog, in which case
        // posting to whichever safe is flagged default would silently land
        // the entry on the wrong branch's books.
        if (safeId == null && SyncInterceptor.isClientMode) {
          throw StateError(
              'safeId required on client mode — no default-safe fallback. '
              'The payment-voucher dialog must enforce a safe selection '
              'before submit (see Phase 5B.6).');
        }

        Safe? targetSafe;
        if (safeId != null) {
          targetSafe = await (select(
            safes,
          )..where((s) => s.id.equals(safeId))).getSingleOrNull();
        } else {
          targetSafe = await getDefaultSafe();
        }

        if (targetSafe == null) throw Exception('No target safe found');

        // Note: Balance check removed - expenses allowed even with zero/negative balance
        // Will be settled at daily closing (الإقفال اليومي)

        // مركزُ تكلفة الخزنة يُورَّث حين لا يحدّده المنادي — انظر
        // `createReceiptVoucher` أعلاه للتعليل الكامل. والمسارانِ متناظرانِ
        // قصداً: صرفٌ يقع بلا مركزٍ وقبضٌ يقع به يجعل تقريرَ المركز نصفَ
        // صورةٍ — إيراداتٌ بلا مصروفاتها.
        final effectiveCostCenterId = costCenterId ?? targetSafe.costCenterId;

        final newBalance = targetSafe.balance - amount;
        final voucherNumber = await generateInvoiceNumber('PV');

        // Phase 5B.1 (Issues 1 + 7) — capture the effective globalId early
        // so the JE can derive its own deterministic identity from it.
        // See createReceiptVoucher above for the full rationale.
        final effectiveGlobalId = globalId ?? UuidV7.generate();

        transactionId = await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNumber,
            safeId: targetSafe.id,
            transactionType: 'payment',
            category: category,
            amount: amount,
            discount: Value(discount),
            balanceAfter: newBalance,
            partyId: Value(partyId),
            description: Value(description),
            userId: Value(userId),
            costCenterId: Value(effectiveCostCenterId),
            globalId: Value(effectiveGlobalId),
          ),
        );

        // H15 — سندُ صرف: خصمٌ ذرّيّ (نفسُ علّة سند القبض أعلاه).
        await adjustSafeBalance(targetSafe.id, -amount);

        // Create journal entry for financial reporting.
        // Skipped for check payments: the commercial papers system creates the
        // correct entry (Dr: Payables / Cr: Notes Payable) on check issuance.
        if (!skipJournalEntry) {
          await _createVoucherJournalEntry(
            voucherNumber: voucherNumber,
            amount: amount,
            discount: discount,
            category: category,
            description: description ?? 'سند صرف',
            isReceipt: false,
            transactionId: transactionId,
            costCenterId: effectiveCostCenterId,
            branchId: operatingBranchId ?? targetSafe.branchId, // Spec 135 BUG-C
            safeId: targetSafe.id,
            partyId: partyId, // Issue 4 (Feature 022): party AP sub-account
            safeTransactionGlobalId: effectiveGlobalId,
          );
        }

        // ── Client → Server sync (fire-and-forget) ──
        // Spec 087 (F2) — thread partyId + partyGlobalId so the
        // server's voucher row lands on the right supplier and
        // appears in their statement.
        String? paymentPartyGid;
        if (partyId != null) {
          final partyRow = await (select(parties)
                ..where((p) => p.id.equals(partyId))
                ..limit(1))
              .getSingleOrNull();
          paymentPartyGid = partyRow?.globalId;
        }
        try {
          await SyncInterceptor.instance?.submitSafeTransaction(
            safeId: targetSafe.id,
            transactionType: 'payment',
            amount: amount,
            category: category,
            description: description,
            userId: userId,
            referenceType: 'payment_voucher',
            referenceId: transactionId,
            // Phase 5B.4 (Issue 7) — see createReceiptVoucher above for
            // the rationale; same divergence-mitigation here for payment
            // vouchers.
            globalId: effectiveGlobalId,
            safeGlobalId: targetSafe.globalId,
            costCenterId: effectiveCostCenterId,
            partyId: partyId,
            partyGlobalId: paymentPartyGid,
          );
        } catch (e) {
          debugPrint('[TREASURY-SYNC] Payment voucher sync failed: $e');
        }

        // Spec 081 — party balance adjustment belongs INSIDE the
        // skipSafeTransaction guard. For cheque payments the commercial
        // papers pipeline owns the AP side-effect via
        // `_cpApplyBalanceSideEffects` (commercial_papers_dao.dart:565);
        // running it here too caused parties.balance to decrement twice.
        if (partyId != null) {
          await adjustPartyBalance(
            partyId,
            -(amount + discount),
          ); // NEGATIVE: reduces outstanding balance
        }
      }

      return transactionId;
    });
  }

  /// Helper to create journal entry for vouchers
  /// This ensures treasury transactions appear in financial statements
  Future<void> _createVoucherJournalEntry({
    required String voucherNumber,
    required double amount,
    required double discount,
    required String category,
    required String description,
    required bool isReceipt,
    required int transactionId,
    int? costCenterId,
    int? branchId,
    int? linkedAccountId, // GAP-03: Custom GL account from COA
    int? safeId, // Safe ID to resolve linked account for cash side
    // Issue 4 (Feature 022): the voucher's party. When non-null AND the
    // operator hasn't picked an explicit CoA override, the JE's "other"
    // leg (debit on payment, credit on receipt) lands on the party's
    // AP/AR sub-account instead of the category-default expense/income
    // account. Without this, payment vouchers to suppliers were debiting
    // "مصروفات متنوعة" (5299) and the GL supplier statement diverged
    // from the CRM/parties statement.
    int? partyId,
    /// Phase 5B.1 (Issues 1 + 7) — when the parent voucher's globalId is
    /// known, the JE derives a deterministic globalId from it
    /// (`je-rcpt-<g>` / `je-pmt-<g>`). Both client and server end up
    /// computing the same JE globalId for the same logical voucher, so
    /// JournalSyncStrategy's Tier 1 dedup recognises the match instead
    /// of inserting a phantom duplicate row in the General Ledger.
    /// Optional for backward compatibility with legacy callers; absent
    /// callers keep the previous random-globalId behaviour (no
    /// cross-device dedup, but no within-device duplicate either).
    String? safeTransactionGlobalId,
  }) async {
    // GAP-03: If a linked account is specified, use it directly
    Account? categoryAccount;
    if (linkedAccountId != null) {
      categoryAccount = await accountingDao.getAccountById(linkedAccountId);
    }
    // Issue 4 (Feature 022): party-aware fallback BEFORE the generic
    // category-code fallback. Order: explicit CoA pick → party AP/AR
    // sub-account → category default. This is the fix for the bug where
    // payment vouchers to suppliers debited "مصروفات متنوعة" instead of
    // the supplier's payables sub-account.
    if (categoryAccount == null && partyId != null) {
      categoryAccount = await _resolveVoucherPartyAccount(
        partyId: partyId,
        isReceipt: isReceipt,
      );
    }
    // Fallback to category-based mapping
    if (categoryAccount == null) {
      final accountCode = _getCategoryAccountCode(category, isReceipt);
      categoryAccount = await accountingDao.getAccountByCode(accountCode);

      // If account doesn't exist, create it
      if (categoryAccount == null) {
        final accountName = _getCategoryAccountName(category, isReceipt);
        final accountType = isReceipt ? 'revenue' : 'expense';
        await into(accounts).insert(
          AccountsCompanion.insert(
            code: accountCode,
            name: accountName,
            accountType: accountType,
            isSystem: const Value(false),
            // UUID-First (Phase 1): stable cross-install identity for sync.
            globalId: Value(UuidV7.generate()),
          ),
        );
        categoryAccount = await accountingDao.getAccountByCode(accountCode);
      }
    }

    // Resolve the cash/treasury account:
    // 1. If safe has a linkedAccountId, use that account
    // 2. Otherwise fall back to default cash account '1111' (الصندوق الرئيسي)
    // Cluster 023 / Issue 3 — leaf-safe lookups so a safe whose
    // `linkedAccountId` happens to point at a parent (or a `cash` purpose
    // mapped to a parent) doesn't fail the JE post.
    Account? cashAccount;
    if (safeId != null) {
      final safe = await (select(safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
      if (safe?.linkedAccountId != null) {
        cashAccount = await accountingDao.getLeafAccountById(safe!.linkedAccountId!);
      }
      // خزينة مش مربوطة: الرجوع على '1111' مباشرة كان بيرحّل سند قبض على
      // «الحساب البنكي» أو «كليك» على **الصندوق الرئيسي** — النقدية في
      // الأستاذ بتزيد والبنك بينقص والخزينة بتقول العكس. الـdropdown في
      // `receipt_voucher_dialog.dart` بيعرض كل الخزائن مش الكاش بس،
      // فالمسار قابل للوصول عادي.
      //
      // نفس نمط مسار المبيعات الصح (`_resolveSaleLegAccount` →
      // `_resolveBranchSafeAccount`): الرجوع بحسب **نوع الخزينة**.
      if (cashAccount == null && safe != null) {
        final byType = kSafeTypeAccountCode[safe.safeType];
        if (byType != null) {
          cashAccount = await accountingDao.getLeafAccountById(
            (await accountingDao.getAccountByCode(byType))?.id ?? -1,
          );
        }
      }
    }
    cashAccount ??= await accountingDao.getAccountByCode('1111');
    if (cashAccount == null) {
      await accountingDao.syncDefaultAccounts();
      cashAccount = await accountingDao.getAccountByCode('1111');
    }
    // Last-resort: leaf-safe purpose lookup. Catches installs whose seed
    // doesn't have code '1111' anymore (e.g. CoA was customised) — without
    // this we silently dropped the JE at the null-guard below.
    cashAccount ??= await accountingDao.getLeafAccountByPurpose('cash');

    // Get or create discount account
    final discountCode = isReceipt ? '5205' : '4202';
    final discountName = isReceipt ? 'خصم مسموح به (Settlement)' : 'خصم مكتسب (Settlement)';
    var discountAccount = await accountingDao.getAccountByCode(discountCode);
    if (discountAccount == null && discount > 0) {
      await into(accounts).insert(AccountsCompanion.insert(
        code: discountCode,
        name: discountName,
        accountType: isReceipt ? 'expense' : 'revenue',
        isSystem: const Value(false),
        // UUID-First (Phase 1): stable cross-install identity for sync.
        globalId: Value(UuidV7.generate()),
      ));
      discountAccount = await accountingDao.getAccountByCode(discountCode);
    }

    // Cluster 023 / Issue 1 — silently returning here was the silent bug:
    // safe transaction got persisted but the JE was skipped, so the GL
    // balance drifted from the safe's actual balance. Throw loudly instead
    // — the outer transaction rolls back and the operator sees a clear
    // error pointing at the misconfigured account, instead of an invisible
    // ledger drift discovered weeks later.
    if (categoryAccount == null) {
      throw Exception(
        'تعذّر تحديد حساب التصنيف لسند ${isReceipt ? 'القبض' : 'الصرف'} '
        '(category="$category"). تأكّد من ربط الحساب فى إعدادات > دليل الحسابات > ربط الحسابات.',
      );
    }
    if (cashAccount == null) {
      throw Exception(
        'تعذّر تحديد حساب الخزينة/البنك لسند ${isReceipt ? 'القبض' : 'الصرف'}. '
        'تأكّد من ربط حساب الصندوق الرئيسي (1111) أو حساب الخزينة المختارة فى دليل الحسابات.',
      );
    }

    // Total impact on party/revenue
    final totalAmount = amount + discount;

    // Create journal entry
    // RV: DB Cash (amount), DB Discount Allowed (discount), CR Party/Revenue (total)
    // PV: DB Party/Expense (total), CR Cash (amount), CR Discount Received (discount)
    final List<JournalLine> lines = [];

    if (isReceipt) {
      // Receipt: Debit Cash, Debit Discount, Credit Revenue/Party
      lines.add(JournalLine(accountId: cashAccount.id, debit: amount, credit: 0, description: description));
      if (discount > 0 && discountAccount != null) {
        lines.add(JournalLine(accountId: discountAccount.id, debit: discount, credit: 0, description: 'خصم معجل دفع مسموح به'));
      }
      lines.add(JournalLine(accountId: categoryAccount.id, debit: 0, credit: totalAmount, description: description));
    } else {
      // Payment: Debit Expense/Party, Credit Cash, Credit Discount
      lines.add(JournalLine(accountId: categoryAccount.id, debit: totalAmount, credit: 0, description: description));
      lines.add(JournalLine(accountId: cashAccount.id, debit: 0, credit: amount, description: description));
      if (discount > 0 && discountAccount != null) {
        lines.add(JournalLine(accountId: discountAccount.id, debit: 0, credit: discount, description: 'خصم معجل دفع مكتسب'));
      }
    }

    // Phase 5B.1 (Issues 1 + 7) — derive deterministic JE globalId from
    // the parent voucher's globalId so client + server converge on the
    // same JE row after sync. See _createVoucherJournalEntry's parameter
    // docs for the full rationale. Falls back to null (random globalId)
    // when the caller didn't supply one (legacy callers / direct DAO use).
    final detGlobalId = (safeTransactionGlobalId != null && safeTransactionGlobalId.isNotEmpty)
        ? '${isReceipt ? 'je-rcpt' : 'je-pmt'}-$safeTransactionGlobalId'
        : null;

    await accountingDao.createJournalEntry(
      description: description,
      date: DateTime.now(),
      lines: lines,
      referenceType: isReceipt ? 'receipt_voucher' : 'payment_voucher',
      referenceId: transactionId,
      costCenterId: costCenterId,
      branchId: branchId,
      globalId: detGlobalId,
    );
  }

  /// Map category to account code using centralized purposes
  String _getCategoryAccountCode(String category, bool isReceipt) {
    final Map<String, String> categoryToPurpose = {
      'sales': 'sales',
      'purchase': 'cogs',
      'salary': 'salary_expense',
      'salaries': 'salary_expense',
      'rent': 'rent_expense',
      'income': 'other_income',
      'other_income': 'other_income',
      'expense': 'misc_expense',
      'other_expense': 'misc_expense',
    };

    final purpose = categoryToPurpose[category.toLowerCase()];
    if (purpose != null) {
      final code = AccountingDao.accountPurposes[purpose];
      if (code != null) return code;
    }

    // Fallback for custom or daily closing categories
    final prefix = isReceipt ? '4' : '5';
    if (category.toLowerCase() == 'daily_closing') return '${prefix}999';
    return isReceipt ? '4299' : '5299';
  }

  /// Map category to account name
  String _getCategoryAccountName(String category, bool isReceipt) {
    switch (category.toLowerCase()) {
      case 'sales':
        return 'إيرادات المبيعات';
      case 'purchase':
        return 'تكلفة البضاعة المباعة';
      case 'salary':
      case 'salaries':
        return 'مصروفات الرواتب';
      case 'rent':
        return 'مصروفات الإيجار';
      case 'utilities':
        return 'مصروفات المرافق';
      case 'supplies':
        return 'مصروفات المستلزمات';
      case 'other_income':
        return 'إيرادات أخرى';
      case 'other_expense':
        return 'مصروفات أخرى';
      case 'daily_closing':
        return 'إقفال يومي';
      default:
        return isReceipt ? 'إيرادات متنوعة' : 'مصروفات متنوعة';
    }
  }

  /// Issue 4 (Feature 022): resolve a voucher's "other-leg" account when the
  /// voucher targets a specific party. Prefers the party's AP/AR sub-account
  /// (so the GL party statement shows every voucher under the right ledger
  /// row); falls back to the configured `payables` / `receivables` control
  /// account when the party has no linked sub-account (legacy data, system
  /// parties).
  ///
  /// Returns null only if the control-account lookup itself fails — caller
  /// then falls through to the existing category-based path so the JE still
  /// posts somewhere rather than silently dropping.
  Future<Account?> _resolveVoucherPartyAccount({
    required int partyId,
    required bool isReceipt,
  }) async {
    final party = await (select(parties)
          ..where((p) => p.id.equals(partyId))
          ..limit(1))
        .getSingleOrNull();
    if (party?.accountId != null) {
      // Cluster 023 / Issue 3 — leaf-safe lookup so a party whose
      // `accountId` happens to point at a parent (legacy data drift) doesn't
      // cause the JE validator to reject the post on a "view" account.
      final sub = await accountingDao.getLeafAccountById(party!.accountId!);
      if (sub != null) return sub;
    }
    // Fallback to the control account, leaf-safe so a misconfigured
    // `receivables` / `payables` mapping (e.g. pointing at code "22") is
    // walked down to a postable child instead of failing the post.
    final purpose = isReceipt ? 'receivables' : 'payables';
    return accountingDao.getLeafAccountByPurpose(purpose);
  }

  /// Close safe daily (اقفال يومي)
  /// Zeroes out the balance by creating a 'daily_closing' transaction
  /// T-02 HARDENED: now posts a journal entry for the closing transfer
  Future<void> closeSafe(int safeId, {int? userId, double? cashAmount, double? bankAmount, String? notes, String? closeEventGid}) async {
    await transaction(() async {
      final safe = await (select(
        safes,
      )..where((s) => s.id.equals(safeId))).getSingleOrNull();
      if (safe == null) throw Exception('Safe not found');

      // Spec 135 — close-safe idempotency guard. The close is a dual-write
      // (local DAO + server postCloseSafe) and can be re-delivered (outbox
      // retry). When the caller minted a closeEventGid, skip if a closing
      // safe_transaction already carries it — this one logical close has
      // already been processed on this instance. (The currentBalance<=0
      // early-return below is the same-instance safety net; this guard also
      // covers the rare case where new activity pushed the balance back up
      // between a partial delivery and its retry.)
      if (closeEventGid != null && closeEventGid.isNotEmpty) {
        final already = await (select(safeTransactions)
              ..where((t) => t.globalId.equals(closeEventGid))
              ..limit(1))
            .getSingleOrNull();
        if (already != null) {
          debugPrint('[CLOSE-SAFE] event $closeEventGid already processed '
              '(txn #${already.id}) — skipping duplicate close for safe #$safeId');
          return;
        }
      }

      final currentBalance = safe.balance;
      if (currentBalance <= 0) return; // Already zeroed

      // ── الطرفُ المستقبِل ومرجعُ الحساب: يُحسمان **قبل** أيّ تعديل ──────────
      //
      // كان الإقفالُ اليوميّ يصفّي الدرجَ بلا خزينةٍ مستقبِلة، تماماً كالعطب
      // الذي أُصلح في `_closeShiftSafes` (اقرأ التعليق عند `:923`) — والإصلاح
      // لم يُنقَل إلى هنا. النتيجةُ مقيسة: قبل الإقفال Σالخزائن=١٠٠ والأستاذ
      // ١٠٠، وبعده Σالخزائن=**صفر** والأستاذ ١٠٠ ⇒ فجوةٌ دائمةٌ تتراكم كلَّ يوم.
      //
      // وكان `if (sourceAccount == null …) return;` أسفلَه **داخل** الـ`try`
      // وبعد التصفير، فيخرج من ردّ النداء كلِّه ويثبّت التصفيرَ **بلا أيّ قيد**.
      // لذلك يُحسم كلُّ شيءٍ هنا قبل أن يُمَسّ رصيد.
      final central = await getCentralSafe();
      if (central == null) {
        throw StateError(
            'الإقفال اليومي متوقّف: الصندوق الرئيسي غيرُ موجود، فلا خزينةَ '
            'تستقبل رصيدَ «${safe.name}». صفَّرَ الإقفالُ الدرجَ قبل هذا '
            'الإصلاح بلا طرفٍ مقابل، فتختفي النقديةُ من الخزائن ويبقى الأستاذُ '
            'كما هو. اِزرع الصندوقَ الرئيسي ثم أعِد الإقفال.');
      }
      if (central.id == safeId) {
        throw StateError(
            'الإقفال اليومي متوقّف: «${safe.name}» هو الصندوقُ الرئيسي نفسُه، '
            'والتحويلُ إلى الذات سطرُ استلامٍ وهميٌّ ورصيدٌ لا يتصفّى.');
      }

      Account? sourceAccount;
      if (safe.linkedAccountId != null) {
        sourceAccount = await accountingDao.getAccountById(safe.linkedAccountId!);
      }
      sourceAccount ??= safe.safeType == 'bank'
          ? await accountingDao.getAccountByPurpose('bank')
          : await accountingDao.getAccountByPurpose('cash');
      if (sourceAccount == null) {
        throw StateError(
            'الإقفال اليومي متوقّف: لا حسابَ دفتريّاً لـ«${safe.name}» ولا '
            'حسابَ غرضٍ (${safe.safeType == 'bank' ? 'bank' : 'cash'}). '
            'الإقفالُ بلا قيدٍ يترك النقديةَ خارجَ الأستاذ.');
      }

      final voucherNumber = await generateInvoiceNumber('CLO');
      final description = 'إقفال يومي — كاش: ${cashAmount ?? 0} | بنك: ${bankAmount ?? 0} | ملاحظات: ${notes ?? ''}';

      // Create a 'withdrawal' type transaction to zero out the balance.
      // Spec 135: stamp the caller-minted event gid so a re-delivered close
      // is caught by the idempotency guard above, and so the closing txn has
      // a stable cross-instance identity.
      final closingTxnId = await into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: voucherNumber,
          safeId: safeId,
          transactionType: 'withdrawal',
          category: 'closing',
          amount: currentBalance,
          balanceAfter: 0,
          description: Value(description),
          userId: Value(userId),
          createdAt: Value(DateTime.now()),
          globalId: Value(closeEventGid),
        ),
      );

      // تصفيرٌ **نسبيّ** لا مطلق: `updateSafeBalance(safeId, 0)` كتابةٌ مطلقة
      // تمحو أيَّ حركةٍ دخلت بين قراءتنا وكتابتنا (سباقُ read-then-write الذي
      // يوثّقه هذا الملفُّ نفسُه عند `:1277`).
      await adjustSafeBalance(safeId, -currentBalance);

      // ── الطرفُ المستقبِل — الصندوقُ الرئيسي ────────────────────────────────
      // بلا هذا السطر تنقص Σ أرصدة الخزائن بمقدار الإقفال كلَّ يوم بينما يبقى
      // حسابُ النقدية في الأستاذ صحيحاً. مطابقٌ لـ`_closeShiftSafes:944-961`.
      await into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: voucherNumber,
          safeId: central.id,
          transactionType: 'receipt',
          category: 'closing',
          amount: currentBalance,
          balanceAfter: central.balance + currentBalance,
          description: Value('إقفال يومي — استلام رصيد ${safe.name}'),
          userId: Value(userId),
          createdAt: Value(DateTime.now()),
          referenceType: const Value('daily_closing'),
          referenceId: Value(closingTxnId),
          globalId: Value(
              (closeEventGid != null && closeEventGid.isNotEmpty)
                  ? '$closeEventGid-central'
                  : null),
        ),
      );
      await adjustSafeBalance(central.id, currentBalance);

      final branchId = safe.branchId; // Standardized branch resolution

      // Post accounting JE for the closing transfer.
      // Credit: the safe's own linked GL account (safe.linkedAccountId).
      //         Fallback to purpose-based account by safe type.
      // Debit:  split between cash and bank destinations based on
      //         the amounts entered by the user; if neither provided,
      //         route to the generic opposite-type purpose account.
      // ⚠️ **بلا `try/catch` هنا عن قصد.** كان القيدُ كلُّه ملفوفاً في
      // `catch (e) { debugPrint(...) }`، فأيُّ فشلٍ في الترحيل يُبتلَع **بعد**
      // أن صُفِّي الدرجُ فعلاً ⇒ نقديةٌ خرجت من الخزائن بلا أثرٍ في الأستاذ ولا
      // رسالةٍ لأحد. ونحن داخلَ `transaction()`، فتركُ الاستثناء يصعد يُرجِع
      // التصفيرَ والاستلامَ معاً — وهو التصرّفُ الصحيح: إقفالٌ بلا قيدٍ لا
      // يُحفَظ أصلاً. (‏نفسُ نمطِ `operational_expenses_dao.dart:395`.)
      {
        // ── Destination accounts (Debit side): where the money goes ──
        final effectiveCash = (cashAmount ?? 0).clamp(0, currentBalance).toDouble();
        final effectiveBank = (bankAmount ?? 0).clamp(0, currentBalance).toDouble();
        // If both are 0 (no amounts specified), route everything to the
        // same-type account (cash safe → cash, bank safe → bank).
        final useSplit = effectiveCash + effectiveBank > 0.001;

        final lines = <JournalLine>[];

        if (useSplit) {
          if (effectiveBank > 0.001) {
            final bankAccount = await accountingDao.getAccountByPurpose('bank');
            if (bankAccount != null) {
              lines.add(JournalLine(
                accountId: bankAccount.id,
                debit: effectiveBank,
                description: 'إقفال — تحويل إلى البنك',
              ));
            }
          }
          if (effectiveCash > 0.001) {
            final cashAccount = await accountingDao.getAccountByPurpose('cash');
            if (cashAccount != null) {
              lines.add(JournalLine(
                accountId: cashAccount.id,
                debit: effectiveCash,
                description: 'إقفال — تحويل نقدي',
              ));
            }
          }
          // If split amounts don't add up exactly to balance, absorb remainder
          // in the larger destination to keep the JE balanced.
          final splitTotal = effectiveCash + effectiveBank;
          if ((splitTotal - currentBalance).abs() > 0.001 && lines.isNotEmpty) {
            final diff = currentBalance - splitTotal;
            lines[0] = JournalLine(
              accountId: lines[0].accountId,
              debit: lines[0].debit + diff,
              description: lines[0].description,
            );
          }
        } else {
          // No split: use the same-type GL account
          final destAccount = safe.safeType == 'bank'
              ? await accountingDao.getAccountByPurpose('bank')
              : await accountingDao.getAccountByPurpose('cash');
          if (destAccount != null) {
            lines.add(JournalLine(
              accountId: destAccount.id,
              debit: currentBalance,
              description: safe.safeType == 'bank'
                  ? 'إقفال بنك — ترحيل إلى البنك'
                  : 'إقفال صندوق — ترحيل إلى الصندوق الرئيسي',
            ));
          }
        }

        // Credit: this safe's GL account
        lines.add(JournalLine(
          accountId: sourceAccount.id,
          credit: currentBalance,
          description: 'إقفال يومي — ${safe.name}',
        ));

        // ── قيدٌ يلغي نفسَه = لا قيد ────────────────────────────────────────
        // الخزنتان تقعان على نفس حساب النقدية حين لا يكون للخزنة حسابٌ مرتبط،
        // فيخرج القيدُ `١١١١ مدين ١٠٠ / ١١١١ دائن ١٠٠` — صافيه صفرٌ على نفس
        // الحساب. مقيسٌ في الإقفال اليومي. وهو ليس عبثاً فحسب: يقرأه المدقّقُ
        // ترحيلاً حدث ولم يحدث. والحركةُ الحقيقيةُ هنا بين خزنتين لا بين
        // حسابين — سطرا الخزائن أعلاه هما الأثرُ الصحيح.
        final netByAccount = <int, double>{};
        for (final l in lines) {
          netByAccount.update(l.accountId, (v) => v + l.debit - l.credit,
              ifAbsent: () => l.debit - l.credit);
        }
        final isSelfCancelling =
            netByAccount.values.every((v) => v.abs() < 0.001);

        if (lines.length >= 2 && !isSelfCancelling) {
          // Spec 135 — deterministic JE globalId for the daily-closing JE.
          // referenceId is closingTxnId, a LOCAL autoincrement that differs
          // client vs server, so the (referenceType, referenceId) dedup never
          // matched across instances → the client-posted closing JE and the
          // server-posted one both survived DeltaPull as duplicates. Keyed on
          // the shared closeEventGid both sides converge; the
          // journal_entries.globalId UNIQUE index dedups on next pull. Null
          // (legacy random gid) when the caller didn't mint one.
          final closeJeGid = (closeEventGid != null && closeEventGid.isNotEmpty)
              ? JournalEntryGid.compute(
                  sourceType: JournalEntryGid.sourceSafeClose,
                  sourceGid: closeEventGid,
                  verb: 'close',
                )
              : null;
          if (closeJeGid != null) {
            final gidShort = closeEventGid!.length >= 8
                ? closeEventGid.substring(0, 8)
                : closeEventGid;
            unawaited(DiagnosticLogger.log(
              DiagnosticLogger.gidAutopost,
              'sourceType=safeclose sourceGid=$gidShort verb=close safe=$safeId',
            ));
          }
          await accountingDao.createJournalEntry(
            description: 'إقفال يومي — ${safe.name} ($voucherNumber)',
            date: DateTime.now(),
            lines: lines,
            referenceType: 'daily_closing',
            referenceId: closingTxnId, // unique per closing event (safe txn ID)
            isAutoPosted: true,
            branchId: branchId,
            globalId: closeJeGid,
          );
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TREASURY REPORTS — See treasury_reports_dao.dart
  // ═══════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════
  // BRANCH-SCOPED BANK SAFES
  // ═══════════════════════════════════════════════════════════════════════

  /// Get active bank safes for a specific branch.
  /// If [branchId] is null, returns ALL active bank safes (single-branch fallback).
  Future<List<Safe>> getBankSafesForBranch(int? branchId) {
    final query = select(safes)
      ..where((s) => s.safeType.equals('bank') & s.isActive.equals(true));
    if (branchId != null) {
      query.where((s) => s.branchId.equals(branchId));
    }
    query.orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.get();
  }

  /// Get active cash safes for a specific branch.
  /// If [branchId] is null, returns ALL active cash safes (single-branch fallback).
  Future<List<Safe>> getCashSafesForBranch(int? branchId) {
    final query = select(safes)
      ..where((s) => s.safeType.equals('cash') & s.isActive.equals(true));
    if (branchId != null) {
      query.where((s) => s.branchId.equals(branchId));
    }
    query.orderBy([(s) => OrderingTerm.asc(s.name)]);
    return query.get();
  }

  /// Resolve the "primary" branch ID for a given user from UserBranchAccess.
  ///
  /// Feature 011 / Issue INV-PREFIX — DETERMINISM. The legacy `.limit(1)`
  /// without an ORDER BY made the result database-dependent for any
  /// multi-branch user (admins, financial managers). Two consecutive calls
  /// could return different branchIds, which then propagated through:
  ///   • activeBranchIdProvider → activeWarehouseIdProvider →
  ///     warehouseId on every new sale
  ///   • shift.branchId on shift open (when the open path falls back to
  ///     this resolver)
  ///   • _closeShiftSafes ownerBranchId fallback
  /// The visible symptom on a beta restaurant: the same user's invoices
  /// flipped between branch-code prefixes (e.g. AQ-POS-1, MS-POS-2,
  /// AQ-POS-3, ...) because each invoice's branchId resolved to a
  /// different `user_branch_access` row.
  ///
  /// Fix: order by `branchId ASC` so the smallest-id row wins consistently.
  /// `.limit(1)` is preserved — callers expect a single Id, and
  /// multi-branch users still see ALL their branches via the dedicated
  /// `getUserAccessibleBranchIds` resolver used by `branchScopeProvider`.
  Future<int?> getUserBranchId(int userId) async {
    final result = await (select(userBranchAccess)
          ..where((u) => u.userId.equals(userId))
          ..orderBy([(u) => OrderingTerm.asc(u.branchId)])
          ..limit(1))
        .getSingleOrNull();
    return result?.branchId;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SAFE CRUD OPERATIONS (ISS-09: migrated from database.dart)
  // ═══════════════════════════════════════════════════════════════════════

  /// Update safe name, bank info. PostgreSQL-compatible: Drift API
  Future<void> updateSafeInfo({
    required int safeId,
    required String name,
    String? bankName,
    String? accountNumber,
  }) async {
    await (update(safes)..where((s) => s.id.equals(safeId))).write(
      SafesCompanion(
        name: Value(name),
        bankName: Value(bankName),
        accountNumber: Value(accountNumber),
      ),
    );
  }

  /// Set a safe as the default (clears others first). PostgreSQL-compatible.
  Future<void> markSafeAsDefault(int safeId) async {
    // Use raw SQL with sqlBool() for PG boolean compatibility
    final falseVal = sqlBool(false);
    final trueVal = sqlBool(true);
    await customStatement(
      'UPDATE safes SET is_default = $falseVal',
    );
    await customStatement(
      'UPDATE safes SET is_default = $trueVal, is_active = $trueVal WHERE id = ?',
      [safeId],
    );
  }

  /// Toggle safe active/inactive. PostgreSQL-compatible.
  Future<void> setSafeActiveStatus(int safeId, bool isActive) async {
    final boolVal = sqlBool(isActive);
    await customStatement(
      'UPDATE safes SET is_active = $boolVal WHERE id = ?',
      [safeId],
    );
  }

  /// Delete a non-default safe. PostgreSQL-compatible.
  Future<void> removeSafe(int safeId) async {
    await (delete(safes)..where((s) => s.id.equals(safeId) & s.isDefault.equals(false))).go();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SHIFT-CLOSE RECONCILIATION AGGREGATION
  //
  // Returns a single ShiftClosingAggregates snapshot that the shift-close
  // dialog uses to render a per-channel reconciliation table. Replaces the
  // ad-hoc aggregation loop that used to live inside `pos_closing_controller`
  // so the math is in one place and unit-testable.
  //
  // Rules:
  //   * Non-system-admin users see ONLY their own transactions. System
  //     admins see everyone's. (Matches the legacy controller semantics.)
  //   * Time window is `[shiftStart, shiftEnd ?? now]` when `shiftStart` is
  //     known; otherwise falls back to start-of-today (safe floor so we never
  //     bleed into yesterday's closed shift). `shiftEnd` is only passed when
  //     RECOMPUTING a closed shift — leaving it null there would extend the
  //     window to the present and swallow everything sold since.
  //   * `paymentMethod='mixed'` invoices are split across cash/bank/click
  //     using the per-field `cashPaid`, `bankPaid`, `clickPaid` columns.
  //   * `paymentMethod='credit'` invoices count towards AR only — they
  //     never touch the cash/bank/click buckets.
  //   * Voucher safe routing is read from `safes.safe_type` (cash / bank /
  //     click; anything else degrades to cash).
  //   * A `transaction_type='payment'` row is an **expense** when its
  //     `category` is in the well-known expense list; otherwise it's a
  //     **payment voucher** (supplier settlement, transfer out, ...).
  //   * Time-zone note: `shift_start` is stored as local DateTime; this
  //     method compares with local DateTime — no conversion needed.
  // ═══════════════════════════════════════════════════════════════════════

  /// Well-known categories that represent an *expense* rather than a
  /// payment voucher. Kept at DAO scope so UI-only code doesn't have to
  /// hard-code the list.
  static const Set<String> _expenseCategories = {
    'salary',
    'rent',
    'utilities',
    'supplies',
    'other_expense',
    'expense',
  };

  static String _normalizeSafeType(String? raw) {
    final t = (raw ?? 'cash').toLowerCase();
    if (t == 'bank') return 'bank';
    if (t == 'click') return 'click';
    return 'cash';
  }

  Future<ShiftClosingAggregates> getShiftClosingAggregates({
    required int userId,
    required bool includeAllUsers,
    DateTime? shiftStart,
    double openingBalance = 0,
    /// Issue 16 — when set, restricts the aggregate to invoices stamped
    /// with this branch and to safe_transactions whose safe lives in this
    /// branch. `null` keeps the legacy "all branches" behaviour for the
    /// admin closing path. Rows with NULL `branch_id` are intentionally
    /// included so legacy/seed data isn't silently excluded from the
    /// cashier's drawer count.
    int? branchId,

    /// Upper bound of the aggregation window. Defaults to "now", which is
    /// what closing a live shift wants.
    ///
    /// Required for RECOMPUTING an already-closed shift: without it the
    /// window runs to the present moment, so a shift closed this morning
    /// would swallow every sale made since. Only pass it for a closed
    /// shift, using that shift's `endTime`.
    DateTime? shiftEnd,
  }) async {
    final now = DateTime.now();
    final effectiveFrom = shiftStart ??
        DateTime(now.year, now.month, now.day);
    final effectiveTo = shiftEnd ?? now;

    // ── Sales invoices — SQL GROUP BY aggregation ─────────────────────
    // Previous approach loaded ALL invoice rows into Dart (potentially
    // hundreds per shift) and aggregated in a Dart loop. Replacing with
    // a single GROUP BY query reduces the result set to ≤20 rows while
    // computing the same sums inside the DB engine (where it belongs).
    //
    // Groups by (payment_method, sale_type, no_customer) so the credit-
    // routing logic below (which depends on whether a customer is attached)
    // can work on aggregate data without needing individual rows.
    final userWhere = !includeAllUsers ? 'AND user_id = ?' : '';
    // Issue 16 — branch filter on sales_invoices. NULL branch_id passes
    // through so legacy rows (pre-v133 backfill) keep being counted in
    // the cashier's drawer.
    final branchWhere = branchId != null
        ? 'AND (branch_id = ? OR branch_id IS NULL)'
        : '';
    final invoiceRows = await customSelect(
      '''
      SELECT
        payment_method,
        sale_type,
        CAST(customer_id IS NULL AS INTEGER)          AS no_customer,
        COUNT(*)                                       AS cnt,
        SUM(ABS(paid))                                AS total_paid,
        SUM(total)                                    AS total_amount,
        SUM(ABS(COALESCE(cash_paid,  0)))             AS total_cash,
        SUM(ABS(COALESCE(bank_paid,  0)))             AS total_bank,
        SUM(ABS(COALESCE(click_paid, 0)))             AS total_click,
        SUM(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NOT NULL
                    AND total - paid > 0.01
               THEN total - paid ELSE 0 END
        )                                             AS credit_unpaid,
        COUNT(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NOT NULL
                    AND total - paid > 0.01
               THEN 1 END
        )                                             AS credit_cnt,
        SUM(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NOT NULL
                    AND total - paid > 0.01 AND paid > 0
               THEN paid ELSE 0 END
        )                                             AS partial_credit_cash,
        SUM(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NULL
               THEN CASE WHEN paid > 0 THEN paid ELSE total END
               ELSE 0 END
        )                                             AS no_cust_credit_cash,
        SUM(
          CASE WHEN payment_method = 'credit'
                    AND customer_id IS NOT NULL
                    AND total - paid <= 0.01
               THEN paid ELSE 0 END
        )                                             AS full_credit_cash,
        SUM(
          CASE WHEN payment_method IN ('mixed','multiple')
                    AND total - COALESCE(cash_paid,0)
                              - COALESCE(bank_paid,0)
                              - COALESCE(click_paid,0) > 0.0001
               THEN total - COALESCE(cash_paid,0)
                          - COALESCE(bank_paid,0)
                          - COALESCE(click_paid,0)
               ELSE 0 END
        )                                             AS mixed_credit
      FROM sales_invoices
      WHERE invoice_date >= ? AND invoice_date <= ?
        AND is_deleted = 0
        $userWhere
        $branchWhere
      GROUP BY payment_method,
               sale_type,
               CAST(customer_id IS NULL AS INTEGER)
      ''',
      variables: [
        Variable<DateTime>(effectiveFrom),
        Variable<DateTime>(effectiveTo),
        if (!includeAllUsers) Variable<int>(userId),
        if (branchId != null) Variable<int>(branchId),
      ],
    ).get();

    double salesCash = 0, salesBank = 0, salesClick = 0, salesCredit = 0;
    double returnsCash = 0, returnsBank = 0, returnsClick = 0, returnsCredit = 0;
    int salesCount = 0, returnsCount = 0;
    int salesCreditCount = 0;
    int counterSalesCount = 0, tableSalesCount = 0;
    double counterSalesTotal = 0, tableSalesTotal = 0;

    for (final row in invoiceRows) {
      final method = (row.read<String?>('payment_method') ?? '').toLowerCase();
      final saleType = row.read<String?>('sale_type') ?? '';
      final cnt = row.read<int>('cnt');
      final totalPaid = row.read<double?>('total_paid') ?? 0.0;
      final totalAmount = row.read<double?>('total_amount') ?? 0.0;
      final totalCash = row.read<double?>('total_cash') ?? 0.0;
      final totalBank = row.read<double?>('total_bank') ?? 0.0;
      final totalClick = row.read<double?>('total_click') ?? 0.0;

      final isPosReturn = saleType == 'return';

      if (isPosReturn) {
        // Returns: amounts were already ABS'd in SQL → subtract from drawer.
        returnsCount += cnt;
        switch (method) {
          case 'cash':
            returnsCash += totalPaid;
          case 'click':
            returnsClick += totalPaid;
          case 'card':
          case 'transfer':
          case 'bank':
            returnsBank += totalPaid;
          case 'credit':
            // No money moved — AR credited back. Use total for AR movement.
            returnsCredit += totalAmount.abs();
          case 'mixed':
          case 'multiple':
            returnsCash += totalCash;
            returnsBank += totalBank;
            returnsClick += totalClick;
          default:
            returnsCash += totalPaid; // unknown → treat as cash
        }
      } else {
        salesCount += cnt;
        if (saleType == 'table') {
          tableSalesCount += cnt;
          tableSalesTotal += totalAmount;
        } else {
          counterSalesCount += cnt;
          counterSalesTotal += totalAmount;
        }
        switch (method) {
          case 'cash':
            salesCash += totalPaid;
          case 'click':
            salesClick += totalPaid;
          case 'card':
          case 'transfer':
          case 'bank':
            salesBank += totalPaid;
          case 'credit':
            // Aggregate credit columns computed in SQL handle all sub-cases:
            //   • no-customer credit → salesCash
            //   • partially-paid credit with customer → salesCredit + salesCash
            //   • fully-paid credit → salesCash
            salesCredit += row.read<double?>('credit_unpaid') ?? 0.0;
            salesCreditCount += row.read<int?>('credit_cnt') ?? 0;
            salesCash += (row.read<double?>('partial_credit_cash') ?? 0.0) +
                (row.read<double?>('no_cust_credit_cash') ?? 0.0) +
                (row.read<double?>('full_credit_cash') ?? 0.0);
          case 'mixed':
          case 'multiple':
            salesCash += totalCash;
            salesBank += totalBank;
            salesClick += totalClick;
            salesCredit += row.read<double?>('mixed_credit') ?? 0.0;
          default:
            salesCash += totalPaid;
        }
      }
    }

    // ── Safe transactions (vouchers + expenses) ───────────────────────
    // Join with safes to read safe_type for channel routing. Auto-generated
    // sales/purchase shadow rows are excluded at the SQL level so Dart never
    // sees them — this halves the result set on a typical busy-shift query.
    final txQuery = select(safeTransactions).join([
      innerJoin(safes, safes.id.equalsExp(safeTransactions.safeId)),
    ])
      ..where(safeTransactions.createdAt.isBiggerOrEqualValue(effectiveFrom))
      ..where(safeTransactions.createdAt.isSmallerOrEqualValue(effectiveTo))
      ..where(
        safeTransactions.referenceType.isNull() |
        safeTransactions.referenceType.isNotIn(
          ['sales_invoice', 'purchase_invoice'],
        ),
      )
      // Issue 16 — exclude soft-deleted vouchers from the cashier's
      // drawer count. The flag was already used by the treasury list
      // and reports; the closing aggregate inherited a stale row count
      // for any voucher admin had reversed during the shift.
      ..where(safeTransactions.deletedAt.isNull());
    if (!includeAllUsers) {
      txQuery.where(safeTransactions.userId.equals(userId));
    }
    if (branchId != null) {
      // Issue 16 — restrict to safes belonging to this branch (or NULL
      // branch for legacy seed safes that never got a branch link).
      txQuery.where(safes.branchId.equals(branchId) | safes.branchId.isNull());
    }
    final txRows = await txQuery.get();

    double receiptCash = 0, receiptBank = 0, receiptClick = 0;
    double paymentCash = 0, paymentBank = 0, paymentClick = 0;
    double expensesCash = 0, expensesBank = 0, expensesClick = 0;
    int receiptCount = 0, paymentCount = 0, expensesCount = 0;
    final List<ShiftClosingExpenseItem> expenseItems = [];

    // `sales_invoice` and `purchase_invoice` auto-ref rows are already
    // excluded by the SQL query above, so no Dart-level skip is needed.
    // `sales_return` rows come from the "returns screen" dialog and must
    // be counted here (the underlying invoice is outside the shift window).
    const returnsScreenRefs = {
      'sales_return',
    };

    for (final row in txRows) {
      final t = row.readTable(safeTransactions);
      final s = row.readTable(safes);
      final channel = _normalizeSafeType(s.safeType);
      final amt = t.amount.abs();

      // Returns-screen refunds: the invoice was saved in an earlier
      // shift (or this shift) and the status-change flow only recorded
      // a safe_transaction for the cash/bank/click refund. Categorise
      // those into the returns buckets so the reconciliation subtracts
      // the refund from the drawer the same way a POS return does.
      if (t.referenceType != null &&
          returnsScreenRefs.contains(t.referenceType)) {
        final cat = t.category.toLowerCase();
        // Memo entries for AR-only refunds (`category` ends with
        // `_balance`) reflect a credit customer's balance reduction.
        // No cash moved — route them to the credit returns bucket so
        // the AR column on the dialog shows the movement but the cash
        // columns stay untouched.
        if (cat.endsWith('_balance')) {
          returnsCount++;
          returnsCredit += amt;
          continue;
        }
        returnsCount++;
        switch (channel) {
          case 'bank':
            returnsBank += amt;
            break;
          case 'click':
            returnsClick += amt;
            break;
          default:
            returnsCash += amt;
        }
        continue;
      }

      // Purchase returns flow in the opposite direction (supplier gives
      // us money back — a cash INFLOW). They bucket under "receipts"
      // with the rest of the cash inflows. The balance-adjustment memo
      // (`category` ends with `_balance`) is a pure AP reduction —
      // no cash moved — so we skip those entirely, otherwise we would
      // inflate the expected cash count.
      if (t.referenceType == 'purchase_return') {
        final cat = t.category.toLowerCase();
        if (cat.endsWith('_balance')) {
          // Supplier's AP was reduced, no cash hit the drawer.
          continue;
        }
        receiptCount++;
        switch (channel) {
          case 'bank':
            receiptBank += amt;
            break;
          case 'click':
            receiptClick += amt;
            break;
          default:
            receiptCash += amt;
        }
        continue;
      }

      if (t.transactionType == 'receipt') {
        receiptCount++;
        switch (channel) {
          case 'bank':
            receiptBank += amt;
            break;
          case 'click':
            receiptClick += amt;
            break;
          default:
            receiptCash += amt;
        }
      } else if (t.transactionType == 'payment') {
        final cat = (t.category).toLowerCase();
        final isExpense = _expenseCategories.contains(cat);
        if (isExpense) {
          expensesCount++;
          switch (channel) {
            case 'bank':
              expensesBank += amt;
              break;
            case 'click':
              expensesClick += amt;
              break;
            default:
              expensesCash += amt;
          }
          final desc = (t.description != null && t.description!.isNotEmpty)
              ? t.description!
              : (cat.isNotEmpty ? cat : 'مصروف');
          expenseItems.add(ShiftClosingExpenseItem(
            description: desc,
            amount: amt,
            safeType: channel,
          ));
        } else {
          paymentCount++;
          switch (channel) {
            case 'bank':
              paymentBank += amt;
              break;
            case 'click':
              paymentClick += amt;
              break;
            default:
              paymentCash += amt;
          }
        }
      }
      // 'transfer' / 'closing' / 'adjustment' are ignored here — they are
      // internal to treasury (move between safes, zero out at close, etc.)
      // and must not affect the cashier's per-channel reconciliation.
    }

    return ShiftClosingAggregates(
      salesCash: salesCash,
      salesBank: salesBank,
      salesClick: salesClick,
      salesCredit: salesCredit,
      salesCreditCount: salesCreditCount,
      salesCount: salesCount,
      counterSalesCount: counterSalesCount,
      tableSalesCount: tableSalesCount,
      counterSalesTotal: counterSalesTotal,
      tableSalesTotal: tableSalesTotal,
      returnsCash: returnsCash,
      returnsBank: returnsBank,
      returnsClick: returnsClick,
      returnsCredit: returnsCredit,
      returnsCount: returnsCount,
      receiptCash: receiptCash,
      receiptBank: receiptBank,
      receiptClick: receiptClick,
      receiptCount: receiptCount,
      paymentCash: paymentCash,
      paymentBank: paymentBank,
      paymentClick: paymentClick,
      paymentCount: paymentCount,
      expensesCash: expensesCash,
      expensesBank: expensesBank,
      expensesClick: expensesClick,
      expensesCount: expensesCount,
      expensesList: expenseItems,
      openingBalance: openingBalance,
      shiftStartTime: shiftStart,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Feature 004 (Multi-Branch Governance, US1) — Atomic Safe + CoA linkage
  // ═══════════════════════════════════════════════════════════════════════

  /// Returns the next zero-padded 5-digit suffix to compose a deterministic
  /// sub-account code under [parentId]. Mirrors the convention used by the
  /// `party_dao.insertParty` path: e.g., parent code `1110` plus the
  /// returned `42` becomes `'1110-00042'`. Transaction-safe — call this
  /// inside an open `transaction(() async { ... })`.
  ///
  /// Suffix uniqueness is local-only at create-time. After sync, `serverWins`
  /// resolves any divergence between client and server codes; FK linkage is
  /// always carried by `globalId`, so divergent codes never break referential
  /// integrity.
  ///
  /// **Portability (2026-05-03)** — the previous implementation used a
  /// `customSelect` with `INSTR()` and `SUBSTR()` to extract the suffix in
  /// SQL. `INSTR` is SQLite-only; PostgreSQL rejects it with
  /// `function instr(text, unknown) does not exist`, breaking safe creation
  /// on any deployment that runs the engine against Postgres (server mode
  /// + Supabase). The portable fix is to read the candidate codes through
  /// Drift's typed query API and parse the suffix in Dart — no
  /// dialect-specific functions, identical behaviour on SQLite and Postgres.
  Future<int> _nextAccountSuffix(int parentId) async {
    final children = await (select(accounts)
          ..where((a) => a.parentId.equals(parentId)))
        .get();
    var maxSuffix = 0;
    for (final account in children) {
      final dashIdx = account.code.indexOf('-');
      if (dashIdx <= 0) continue; // not a suffixed sub-account
      final suffixStr = account.code.substring(dashIdx + 1);
      final suffix = int.tryParse(suffixStr);
      if (suffix != null && suffix > maxSuffix) {
        maxSuffix = suffix;
      }
    }
    return maxSuffix + 1;
  }

  /// الأبُ الذي تُعلَّق تحته حساباتُ الخزائن الفرعية.
  ///
  /// Compatibility (2026-05-03) — `'1110'` أولاً (استيرادُ دليلٍ مخصَّصٍ قد
  /// يحمله) ثم `'111'` وهو ما يبذره `database_seeder_accounts.dart` فعلاً
  /// («النقدية وما فى حكمها»)، فلا يُجبَر المشغّلُ على إنشاء `1110` يدوياً.
  ///
  /// مستخرَجٌ كي يشترك فيه مسارُ الإنشاء ومسارُ الإصلاح: لو افترق النصّان
  /// لأمكن أن يُنشئ أحدُهما تحت `1110` والآخرُ تحت `111` في نفس التنصيب،
  /// فتتشتّت حساباتُ الخزائن على أبوين ولا يجمعها تقرير.
  Future<Account?> _resolveSafesParentAccount() async {
    for (final code in const ['1110', '111']) {
      final found =
          await (select(accounts)..where((a) => a.code.equals(code)))
              .getSingleOrNull();
      if (found != null) return found;
    }
    return null;
  }

  /// يمنح كلَّ خزنةٍ بلا `linkedAccountId` حسابَها الفرعيَّ تحت أب الخزائن،
  /// ويعيد عددَ ما رُبط.
  ///
  /// ── فئةُ العطب ────────────────────────────────────────────────────────
  /// خزنةٌ بلا ربطٍ تسقط بحسب **نوعها** على حسابٍ مشترك
  /// ([kSafeTypeAccountCode]: cash→1111 · bank→1113 · click→1116)، فكلُّ
  /// الخزائن النقدية تترحّل على `1111` ولا تُميَّز في الأستاذ: درجُ الكاشير
  /// والصندوقُ المركزيُّ رقمٌ واحدٌ لا ينفصل، ولا سبيلَ لمطابقة رصيد خزنةٍ
  /// بعينها مع الدفاتر.
  ///
  /// و[createSafeWithLinkedAccount] تفعل الصوابَ منذ v142، لكنّ **البذرة**
  /// لا تمرّ بها: `database_seeder.dart` يُدرج «صندوق الكاشير» و«الحساب
  /// البنكي» و«صندوق تحويل كليك» و«الصندوق الرئيسي» بإدراجٍ عارٍ بلا ربط —
  /// فكلُّ تنصيبٍ جديدٍ يولد بالعطب كاملاً. هذا الإصلاحُ هو الطرفُ المكمّل.
  ///
  /// **متعادلٌ** ويعمل كلَّ إقلاع: لا يمسّ إلا `linkedAccountId IS NULL`،
  /// فاختيارُ المستخدم الصريحُ لا يُداس أبداً. والمحذوفةُ ناعماً مستثناةٌ —
  /// لا معنى لحسابٍ جديدٍ لخزنةٍ أُزيلت.
  ///
  /// كلُّ خزنةٍ في معاملةٍ مستقلّة: لاحقةُ الكود متسلسلةٌ لكلّ أب، فمعاملةٌ
  /// واحدةٌ جامعةٌ كانت ستُسقط الجميعَ لتصادمٍ في واحدة.
  Future<int> linkUnlinkedSafesToSubAccounts() async {
    final parent = await _resolveSafesParentAccount();
    // دليلٌ بلا أبٍ للخزائن: لا نُنشئ شجرةً من عندنا — الإنشاءُ اليدويّ
    // يصرّح بذلك للمستخدم، والإصلاحُ الصامتُ يكتفي بالانصراف.
    if (parent == null) return 0;

    final unlinked = await (select(safes)
          ..where((s) => s.linkedAccountId.isNull() & s.deletedAt.isNull()))
        .get();
    if (unlinked.isEmpty) return 0;

    var linked = 0;
    for (final safe in unlinked) {
      final ok = await transaction(() async {
        final suffix = await _nextAccountSuffix(parent.id);
        final code = '${parent.code}-${suffix.toString().padLeft(5, '0')}';

        // تصادمٌ نظريّ (صفٌّ قديمٌ من هجرةٍ جزئية) — نتخطّى هذه الخزنةَ
        // وتُلتقط في الإقلاع التالي بدل إسقاط الدفعة كلّها.
        final dup = await (select(accounts)..where((a) => a.code.equals(code)))
            .getSingleOrNull();
        if (dup != null) return false;

        final accountId = await into(accounts).insert(
          AccountsCompanion.insert(
            code: code,
            name: safe.name,
            accountType: 'asset',
            parentId: Value(parent.id),
            isSystem: const Value(false),
            globalId: Value(UuidV7.generate()),
          ),
        );
        await (update(safes)..where((s) => s.id.equals(safe.id)))
            .write(SafesCompanion(linkedAccountId: Value(accountId)));
        return true;
      });
      if (ok) linked++;
    }
    return linked;
  }

  /// يشغّل [linkUnlinkedSafesToSubAccounts] **مرّةً واحدةً لكلّ تنصيب** — وهو
  /// ما يناديه الإقلاع.
  ///
  /// ── لماذا البوّابةُ هنا لا داخلَ الإصلاح ──────────────────────────────────
  /// شاشةُ إدارة الصناديق فيها منتقي «الحساب المرتبط» من دليل الحسابات، وهو
  /// **اختياريٌّ** في الإنشاء والتعديل معاً (‏`hint: 'بدون'` مع
  /// `showClearButton: true` في `safe_management_dialog.dart`). فـ«بدون»
  /// اختيارٌ صريحٌ للمستخدم لا فراغٌ ينتظر الملء.
  ///
  /// ولأن الإصلاح متعادلٌ على `linkedAccountId IS NULL` فهو لا يدوس ربطاً
  /// قائماً — لكنه كان يدوس **الفكّ**: يمسح المستخدمُ الربطَ فيعيده الإقلاعُ
  /// التالي بحسابٍ **جديدٍ يُنشئه**، وكلُّ مسحٍ يخلّف حساباً يتيماً في الدليل
  /// (‏`111-00005` ثم `111-00006` …) لا يستعمله أحد ولا يحذفه أحد.
  ///
  /// فالبوّابةُ على الغلاف: [linkUnlinkedSafesToSubAccounts] يبقى بلا بوّابةٍ
  /// وقابلاً للنداء المباشر (‏زرٌّ إداريٌّ لاحقاً · اختبار)، والغلافُ وحدَه هو
  /// ما يمرّ به الإقلاع.
  ///
  /// ⚠️ والختمُ **بعد** النجاح لا قبله: الإصلاحُ ينصرف صامتاً حين لا يجد أبَ
  /// الخزائن، فختمُ الرقعة عندها كان يحرق التنصيبَ الجديد — لا يعمل على أوّل
  /// إقلاعٍ ولا على ما بعده. لذلك يُفحص وجودُ الأب قبل الختم.
  Future<int> linkUnlinkedSafesToSubAccountsOnce() async {
    if (await getSettingValue(kSafeSubAccountsBackfillV1Applied) == 'true') {
      return 0;
    }
    // بلا أبٍ لم يعمل الإصلاحُ شيئاً — فلا يُختم، ويُعاد في الإقلاع التالي.
    if (await _resolveSafesParentAccount() == null) return 0;

    final linked = await linkUnlinkedSafesToSubAccounts();
    await setSetting(kSafeSubAccountsBackfillV1Applied, 'true');
    return linked;
  }

  /// Atomically create a Safe and its linked Chart-of-Accounts sub-account.
  ///
  /// This is the canonical entry point for safe creation since v142 (Feature
  /// 004). Both rows (the safe and its sub-account under parent code `1110`
  /// "النقدية فى الصناديق") are inserted inside a single `db.transaction()`,
  /// linked via `safes.linked_account_id`, and both carry a UUIDv7 `globalId`
  /// so cross-device sync resolves them deterministically.
  ///
  /// The sub-account code is computed as `'1110-{NNNNN}'` where NNNNN is the
  /// next sequential suffix produced by [_nextAccountSuffix]. The account's
  /// `name` mirrors the safe's `name` so the user sees the linkage visually.
  ///
  /// Throws [MissingParentAccountException] (rolling back the transaction)
  /// when the `'1110'` parent account is absent from the deployed Chart of
  /// Accounts. The dialog layer surfaces the message verbatim to the user.
  Future<int> createSafeWithLinkedAccount({
    required String name,
    required String safeType,
    String? bankName,
    String? accountNumber,
    int? costCenterId,
    int? branchId,
  }) {
    // Feature 004 (US3, FR-023b) — fail fast before opening the transaction
    // when the elevated-admin session has lost the server connection. The
    // alternative (enqueue or silently no-op) would mislead the user about
    // whether the safe was created.
    final guard = MutationGuard.current;
    if (!guard.canMutate) {
      throw MutationDeniedException(guard.reason);
    }
    return transaction(() async {
      final parent = await _resolveSafesParentAccount();
      final parentCode = parent?.code;
      if (parent == null || parentCode == null) {
        throw const MissingParentAccountException(
          '1110 / 111',
          'لم يتم العثور على حساب أب للصناديق (الكود 1110 أو 111). '
          'يرجى إنشاء الحساب من شاشة دليل الحسابات قبل إعادة المحاولة.',
        );
      }

      // ── Compute the deterministic sub-account code ───────────────────
      final suffix = await _nextAccountSuffix(parent.id);
      final accountCode = '$parentCode-${suffix.toString().padLeft(5, '0')}';

      // Defensive uniqueness check — collisions shouldn't occur because the
      // suffix is monotonic per parent inside this transaction, but a stale
      // PG row from a partial migration could theoretically clash.
      final dup = await (select(accounts)
            ..where((a) => a.code.equals(accountCode)))
          .getSingleOrNull();
      if (dup != null) {
        throw Exception(
          'كود الحساب الفرعى "$accountCode" مستخدم بالفعل — '
          'تحقق من دليل الحسابات.',
        );
      }

      // ── INSERT account ──────────────────────────────────────────────
      final accountId = await into(accounts).insert(
        AccountsCompanion.insert(
          code: accountCode,
          name: name,
          accountType: 'asset',
          parentId: Value(parent.id),
          isSystem: const Value(false),
          globalId: Value(UuidV7.generate()),
        ),
      );

      // ── INSERT safe with linked_account_id ──────────────────────────
      final safeId = await into(safes).insert(
        SafesCompanion.insert(
          name: name,
          safeType: Value(safeType),
          bankName: Value(bankName),
          accountNumber: Value(accountNumber),
          costCenterId: Value(costCenterId),
          branchId: Value(branchId),
          linkedAccountId: Value(accountId),
          globalId: Value(UuidV7.generate()),
        ),
      );

      return safeId;
    });
  }
}
