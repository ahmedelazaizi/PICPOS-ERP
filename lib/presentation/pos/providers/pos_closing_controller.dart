// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/config/business_profile_provider.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../services/delta_pull_service.dart';
import '../../../services/network_service.dart';
import '../../../services/printing/shift_closing_print.dart';
import '../../../domain/entities/shift_closing_snapshot.dart';
import '../../shift_close_picpos/widgets/picpos_close_permissions.dart';
import '../../../data/database/sync_interceptor.dart';

/// Closing-dialog state.
///
/// Post-redesign the per-channel numbers all come from the DAO's
/// [ShiftClosingAggregates] snapshot; this class wraps that snapshot and
/// layers on the user-entered "actual" amounts, UI flags, and derived
/// variance fields used by the reconciliation dialog.
///
/// Legacy getters (`cashIncome`, `systemCard`, `cashRefunds`, ...) are
/// kept for callers that haven't yet migrated to the per-channel names
/// so a rewrite can land without cascading UI breakage.
class PosClosingState {
  final ShiftClosingAggregates aggregates;

  // User-entered actual counts for the three physical channels.
  // AR ("credit") has no drawer, so no "actual" input.
  final double actualCashAmount;
  final double actualBankAmount;
  final double actualClickAmount;

  final bool isRevealed;
  final bool isProcessing;
  final bool isLoading;
  final String? error;
  final String closingMethod;
  final double? varianceJeWarning; // GAP-24: variance JE silently failed

  /// ISS-FIN-03: Set to true when variance is CRITICAL and manager has not
  /// yet confirmed the override. The UI must display an explicit confirmation
  /// before allowing the close to proceed.
  final bool criticalVarianceBlocked;

  // Spec 135 NOTE 2 (req 4) — admin reconciliation. When a system admin opens
  // the closing dialog and MORE THAN ONE shift is open on the terminal,
  // [needsShiftSelection] is true and [selectableShifts] holds the choices so
  // the dialog can render a picker. [resolvedShiftId] is the shift actually
  // being reconciled/closed (a cashier's own shift for non-admins; the
  // admin-selected cashier shift otherwise) — the close path uses it instead
  // of re-resolving by the logged-in user (admin has no own shift).
  final int? resolvedShiftId;
  final int? resolvedShiftUserId; // owner of the shift being closed
  final List<ShiftData> selectableShifts;
  final bool needsShiftSelection;

  const PosClosingState({
    this.aggregates = const ShiftClosingAggregates(),
    this.actualCashAmount = 0.0,
    this.actualBankAmount = 0.0,
    this.actualClickAmount = 0.0,
    this.isRevealed = false,
    this.isProcessing = false,
    this.isLoading = true,
    this.error,
    this.closingMethod = 'normal',
    this.varianceJeWarning,
    this.criticalVarianceBlocked = false,
    this.resolvedShiftId,
    this.resolvedShiftUserId,
    this.selectableShifts = const [],
    this.needsShiftSelection = false,
  });

  // ── Per-channel variance ────────────────────────────────────────────
  double get cashVariance => actualCashAmount - aggregates.systemCash;
  double get bankVariance => actualBankAmount - aggregates.systemBank;
  double get clickVariance => actualClickAmount - aggregates.systemClick;
  double get totalVariance => cashVariance + bankVariance + clickVariance;

  // ── مجاميعُ القنوات الثلاث ───────────────────────────────────────────
  //
  // ⚠️ لا تجمعها في موضع النداء. ثلاثةُ سجلّاتٍ كانت تجمع
  // `actualCash + actualCard` وحدَهما (‏و`actualCardAmount` اسمٌ قديمٌ
  // مُموِّهٌ لحقل البنك)، فسجّلت ورديةً أُغلقت على ٥٥ بأنها ٤٠ — رُصد
  // ميدانياً 2026-08-12. والمالُ نفسُه كان صحيحاً، فالفرقُ يظهر عند
  // المطابقة وحدَها ويُقرأ عطباً في الحساب.
  double get systemTotal => systemCash + systemCard + systemClick;
  double get actualTotal =>
      actualCashAmount + actualBankAmount + actualClickAmount;

  // ── Convenience totals for the footer strip ─────────────────────────
  int get invoiceCount => aggregates.salesCount + aggregates.returnsCount;
  double get totalSales => aggregates.salesCash +
      aggregates.salesBank +
      aggregates.salesClick +
      aggregates.salesCredit;

  // ── Legacy-compatible getters (kept for callers not yet migrated) ───
  double get openingBalance => aggregates.openingBalance;
  double get cashIncome => aggregates.salesCash;
  double get cardIncome => aggregates.salesBank;
  double get clickIncome => aggregates.salesClick;
  double get creditIncome => aggregates.salesCredit;
  // Number of invoices that contributed to the credit (آجل) bucket.
  // Previously this returned `aggregates.returnsCount` whenever any credit
  // was owed — that was obviously wrong (returns count != credit-sale
  // count) and appeared in the shift-close footer as a phantom number of
  // credit sales even when the operator had only issued return receipts.
  int get creditCount => aggregates.salesCreditCount;
  double get cashRefunds => aggregates.returnsCash;
  double get bankRefunds => aggregates.returnsBank;
  double get clickRefunds => aggregates.returnsClick;
  double get totalExpenses =>
      aggregates.expensesCash +
      aggregates.expensesBank +
      aggregates.expensesClick;
  double get systemCash => aggregates.systemCash;
  double get systemCard => aggregates.systemBank;
  double get systemClick => aggregates.systemClick;
  int get counterPosCount => aggregates.counterSalesCount;
  double get counterPosTotal => aggregates.counterSalesTotal;
  int get tablePosCount => aggregates.tableSalesCount;
  double get tablePosTotal => aggregates.tableSalesTotal;
  DateTime? get shiftStartTime => aggregates.shiftStartTime;
  double get cardVariance => bankVariance; // legacy alias
  double get actualCardAmount => actualBankAmount; // legacy alias
  List<Map<String, dynamic>> get expensesList => aggregates.expensesList
      .map((e) => {
            'description': e.description,
            'amount': e.amount,
            'safeType': e.safeType,
          })
      .toList();

  PosClosingState copyWith({
    ShiftClosingAggregates? aggregates,
    double? actualCashAmount,
    double? actualBankAmount,
    double? actualClickAmount,
    bool? isRevealed,
    bool? isProcessing,
    bool? isLoading,
    String? error,
    String? closingMethod,
    double? varianceJeWarning,
    bool? criticalVarianceBlocked,
    int? resolvedShiftId,
    int? resolvedShiftUserId,
    List<ShiftData>? selectableShifts,
    bool? needsShiftSelection,
  }) {
    return PosClosingState(
      aggregates: aggregates ?? this.aggregates,
      actualCashAmount: actualCashAmount ?? this.actualCashAmount,
      actualBankAmount: actualBankAmount ?? this.actualBankAmount,
      actualClickAmount: actualClickAmount ?? this.actualClickAmount,
      isRevealed: isRevealed ?? this.isRevealed,
      isProcessing: isProcessing ?? this.isProcessing,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      closingMethod: closingMethod ?? this.closingMethod,
      varianceJeWarning: varianceJeWarning ?? this.varianceJeWarning,
      criticalVarianceBlocked: criticalVarianceBlocked ?? this.criticalVarianceBlocked,
      resolvedShiftId: resolvedShiftId ?? this.resolvedShiftId,
      resolvedShiftUserId: resolvedShiftUserId ?? this.resolvedShiftUserId,
      selectableShifts: selectableShifts ?? this.selectableShifts,
      needsShiftSelection: needsShiftSelection ?? this.needsShiftSelection,
    );
  }
}

class PosClosingController extends Notifier<PosClosingState> {
  @override
  PosClosingState build() {
    // Schedule the data fetch after the build phase
    Future.microtask(() => _loadInitialData());
    return const PosClosingState(isLoading: true);
  }

  // Spec 135 NOTE 2 (req 4) — when a system admin must pick which open shift
  // to reconcile (more than one open on the terminal), the dialog calls this
  // with the chosen shift id; we re-run the load against it.
  int? _targetShiftId;
  Future<void> selectTargetShift(int shiftId) async {
    _targetShiftId = shiftId;
    state = state.copyWith(isLoading: true, needsShiftSelection: false);
    await _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final authState = ref.read(authProvider);
      final loggedInUserId = authState.user?.id ?? 1;

      final treasuryRepo = ref.read(treasuryRepositoryProvider);

      // Spec 135 NOTE 2 (req 4) — resolve WHICH shift to reconcile/close.
      // Cashiers close their OWN open shift. A system admin no longer
      // auto-opens a shift; instead they attach to a previous cashier's OPEN
      // shift on this terminal's branch: exactly one open → use it; more than
      // one → surface a picker (needsShiftSelection); none → fall through to
      // the legacy admin "today's full picture" path below.
      ShiftData? shift;
      if (authState.isOriginallyAdmin) {
        int? terminalBranchId;
        try {
          terminalBranchId =
              (await ref.read(branchRepositoryProvider).getActiveBranch())?.id;
        } catch (_) {}
        var openShifts =
            await treasuryRepo.getOpenShiftsForBranch(branchId: terminalBranchId);
        // Spec 136: if the terminal's branch resolved to one with no open
        // shift but shifts ARE open elsewhere, fall back to all open shifts so
        // a mis-resolved terminal branch never blocks a legitimate close
        // (single → adopt it; many → picker). Without this, the new
        // "refuse when no shift resolved" guard could wrongly block the owner.
        if (openShifts.isEmpty && terminalBranchId != null) {
          openShifts = await treasuryRepo.getOpenShiftsForBranch(branchId: null);
        }
        if (_targetShiftId != null) {
          for (final s in openShifts) {
            if (s.id == _targetShiftId) {
              shift = s;
              break;
            }
          }
        } else if (openShifts.length == 1) {
          shift = openShifts.first;
        } else if (openShifts.length > 1) {
          // Multiple cashiers' shifts open — let the admin choose.
          state = state.copyWith(
            isLoading: false,
            needsShiftSelection: true,
            selectableShifts: openShifts,
          );
          return;
        }
      } else {
        shift = await treasuryRepo.getCurrentOpenShift(loggedInUserId);
      }

      // Spec 136 (field 2026-06-10): a shift CLOSE must always reconcile exactly
      // ONE resolved shift — never "all users, whole day". The old path set
      // includeAllUsers=true whenever no specific shift was resolved (admin with
      // no own shift, or a temporarily-elevated admin), which made the closing
      // census — most visibly the آجل/credit total — sum EVERY cashier's
      // invoices for the whole day instead of just the shift being closed.
      // The shift resolution above already yields the right shift (single open →
      // it; many → picker; none → refused by the guard below), so the close is
      // always scoped to shift.userId + the shift window + its branch. The admin
      // "today's full picture" is an audit view that belongs in reports, not in
      // the close dialog.
      final int userId = shift?.userId ?? loggedInUserId;
      const bool includeAllUsers = false;

      // Issue 16 — scope the closing aggregate to the cashier's active
      // branch so the dialog doesn't pile up other branches' invoices
      // and vouchers on top of the cashier's drawer. Admin / financial-
      // manager keep the full picture (branchId left null) by leaning
      // on `includeAllUsers` instead.
      //
      // Feature 011 / Issue CLOSE-SCOPE — for non-admin users the dialog
      // was previously calling `branchRepo.getActiveBranch()`, which on
      // standalone/server mode (and on mirror — where isClient is false)
      // returns the FIRST active branch ordered by id (typically branch 1
      // = الإدارة). A branch manager closing a shift on فرع العقبة saw
      // aggregates from الإدارة + every other branch, not just their own.
      // The OPEN SHIFT itself carries the authoritative branchId (Spec
      // 008 / FR-005 — recorded at open time), so prefer that. The domain
      // ShiftData class does not expose branchId yet, so read it directly
      // from the underlying shift row via the DAO. Fall back to
      // getActiveBranch() and primary-branch lookups only when the shift
      // is missing or has a null branchId (legacy rows pre-v145).
      int? scopedBranchId;
      if (!includeAllUsers) {
        final activeShift = shift; // capture for closure promotion (non-final local)
        if (activeShift != null) {
          try {
            final db = ref.read(databaseProvider);
            final raw = await (db.select(db.shifts)
                  ..where((s) => s.id.equals(activeShift.id))
                  ..limit(1))
                .getSingleOrNull();
            scopedBranchId = raw?.branchId;
          } catch (e) {
            debugPrint('[ShiftClose] shift.branchId lookup failed: $e');
          }
        }
        if (scopedBranchId == null) {
          try {
            final branchRepo = ref.read(branchRepositoryProvider);
            final activeBranch = await branchRepo.getActiveBranch();
            scopedBranchId = activeBranch?.id;
          } catch (e) {
            debugPrint('[ShiftClose] active-branch lookup failed: $e');
          }
        }
        if (scopedBranchId == null) {
          // Last resort — resolve the user's primary branch directly. Now
          // deterministic after Issue INV-PREFIX (orderBy branchId ASC).
          try {
            final db = ref.read(databaseProvider);
            scopedBranchId = await db.getUserBranchId(userId);
          } catch (e) {
            debugPrint('[ShiftClose] getUserBranchId fallback failed: $e');
          }
        }
      }

      // Spec 029 corrective patch (2026-05-10) — operator-reported bug:
      // when a cashier closes a shift then opens the close dialog again
      // (or returns later without re-opening a shift), the dialog showed
      // PHANTOM aggregate values from already-closed shifts. Root cause:
      // when `shift == null`, we passed `shiftStart: null` to the DAO,
      // which then fell back to `today_midnight` and summed every
      // invoice posted today regardless of which shift produced it.
      //
      // Defensive guard: refuse to compute close aggregates when there
      // is no open shift. The dialog renders an explicit "no open
      // shift" error + a hint to open a new shift first. This also
      // prevents `handleClosing` from running its `print + logActivity
      // + logout` chain against a non-existent shift (the previous
      // closeShiftWithAudit call was already silently skipped, leaving
      // a confusing "successful close" UI).
      //
      // Spec 136 — with the whole-day admin path removed, a close that could
      // not resolve a specific open shift is always refused here (a close must
      // target exactly one shift). The admin who wants a cross-cashier overview
      // uses the treasury/reports screens instead.
      if (shift == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'no_open_shift',
        );
        return;
      }

      // M1 fix: pull latest transactions from server before calculating
      // aggregates so that invoices created on OTHER devices during this
      // shift are included in the closing report.
      //
      // R9 (2026-05-12): gate on the broadened SyncInterceptor.isClientMode
      // so MIRROR mode also pre-pulls. The legacy NetworkService.isClient
      // is false in mirror, which meant an HQ admin closing a shift on a
      // mirror device was computing aggregates against stale local data
      // (other branches' invoices missed for the same shift).
      if (SyncInterceptor.isClientMode) {
        try {
          await DeltaPullService.instance.pullMultiple([
            'sales_invoices',
            'safe_transactions',
            'payment_allocations',
          ]);
        } catch (e) {
          // Non-fatal — proceed with locally-cached data if pull fails.
          debugPrint('[ShiftClose] Pre-close delta pull failed: $e');
        }
      }

      // Delegate ALL aggregation to the DAO so the math lives in one
      // unit-testable place and per-channel routing (cash / bank / click
      // / credit) is consistent across UI and printed report.
      final db = ref.read(databaseProvider);
      final aggregates = await db.getShiftClosingAggregates(
        userId: userId,
        includeAllUsers: includeAllUsers,
        shiftStart: shift.startTime,
        openingBalance: shift.openingBalance,
        branchId: scopedBranchId,
      );

      state = state.copyWith(
        aggregates: aggregates,
        isLoading: false,
        // Spec 135 NOTE 2 (req 4) — remember the exact shift being closed so
        // handleClosing closes IT (by id + owner) instead of re-resolving by
        // the logged-in user (an admin has no own shift to find).
        resolvedShiftId: shift.id,
        resolvedShiftUserId: shift.userId,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void updateActualCash(double amount) {
    state = state.copyWith(actualCashAmount: amount);
  }

  void updateActualCard(double amount) {
    // Legacy alias kept for the existing dialog bindings; writes to the
    // new bank bucket.
    state = state.copyWith(actualBankAmount: amount);
  }

  void updateActualBank(double amount) {
    state = state.copyWith(actualBankAmount: amount);
  }

  void updateActualClick(double amount) {
    state = state.copyWith(actualClickAmount: amount);
  }

  void revealResults() {
    state = state.copyWith(isRevealed: true);
  }

  void setClosingMethod(String method) {
    state = state.copyWith(closingMethod: method);
  }

  Future<bool> handleClosing({
    String password = '',
    String cardCode = '',
    bool overrideVariance = false,
  }) async {
    state = state.copyWith(isProcessing: true);

    try {
      final authState = ref.read(authProvider);
      // مدير النظام بس هو اللي بيتجاوز كلمة سر الإقفال. قبل كده كانت
      // `isAdmin || isManager`، وهي بتتحدد بمطابقة اسم الدور — فـ«مدير فرع»
      // كان بيعدّي بلا كلمة سر.
      final isAdmin = authState.hasSystemAdminBypass;
      final userId = authState.user?.id ?? 1;
      final closingMethod = state.closingMethod;

      // Feature 048 (v130) — DB-backed close-attempt audit. Field reports
      // showed cases where the cashier clicked إقفال الوردية but no
      // SHIFT-CLOSE / SHIFT-MIRROR diagnostic lines appeared in the log
      // file (possibly because the per-session log got rotated, or the
      // unawaited DiagnosticLogger writes never flushed before the user
      // logged out + the app shut down). An activity_logs row is a
      // synchronous DB write that CANNOT be lost in a buffer — so we
      // can always reconstruct "the cashier did attempt to close" from
      // the audit trail even if the diagnostic file is incomplete.
      try {
        final db = ref.read(databaseProvider);
        await db.logActivity(
          userId: userId,
          userName: authState.user?.displayName ?? authState.user?.username ?? 'unknown',
          action: 'shift_close_attempt',
          entityType: 'shift',
          description: 'بدء إغلاق الوردية: method=$closingMethod '
              'actualCash=${state.actualCashAmount.toStringAsFixed(3)} '
              'actualBank=${state.actualBankAmount.toStringAsFixed(3)} '
              'actualClick=${state.actualClickAmount.toStringAsFixed(3)} '
              '(Feature 048 close-attempt audit)',
        );
      } catch (e) {
        debugPrint('[ShiftClose] activity_logs audit write failed (non-fatal): $e');
      }

      if (!isAdmin) {
        bool authenticated = false;

        switch (closingMethod) {
          case 'quick':
            // Quick close: no authentication needed, admin reviews later
            authenticated = true;
            // Set actual amounts = system amounts (variance = 0 temporarily)
            state = state.copyWith(
              actualCashAmount: state.systemCash,
              actualBankAmount: state.systemCard,
              actualClickAmount: state.systemClick,
            );
            break;

          case 'msr_card':
            // MSR card: authenticate via card code
            if (cardCode.trim().isEmpty) {
              state = state.copyWith(isProcessing: false);
              throw Exception('يرجى تمرير بطاقة MSR');
            }
            final authRepo = ref.read(authRepositoryProvider);
            final user = await authRepo.authenticateByPasswordOrCard(cardCode.trim());
            if (user != null) {
              authenticated = true;
            }
            if (!authenticated) {
              state = state.copyWith(isProcessing: false);
              throw Exception('بطاقة MSR غير صالحة أو غير مسجلة');
            }
            // Set actual amounts = system amounts (variance = 0 temporarily)
            state = state.copyWith(
              actualCashAmount: state.systemCash,
              actualBankAmount: state.systemCard,
              actualClickAmount: state.systemClick,
            );
            break;

          case 'admin_password':
            // Admin password only: verify admin, skip variance entry
            final cleanPassword = password.trim();
            if (cleanPassword.isEmpty) {
              state = state.copyWith(isProcessing: false);
              throw Exception('أدخل كلمة سر المدير');
            }
            if (ref.read(adminPasswordServiceProvider).verify(cleanPassword)) {
              authenticated = true;
            } else {
              final authRepo = ref.read(authRepositoryProvider);
              final user = await authRepo.authenticateByPasswordOrCard(cleanPassword);
              if (user != null && (user.role?.isSystemRole == true || (user.role?.name.toLowerCase().contains('admin') ?? false))) {
                authenticated = true;
              }
            }
            if (!authenticated) {
              state = state.copyWith(isProcessing: false);
              throw Exception('كلمة المرور غير صحيحة');
            }
            // Set actual amounts = system amounts (variance = 0 temporarily)
            state = state.copyWith(
              actualCashAmount: state.systemCash,
              actualBankAmount: state.systemCard,
              actualClickAmount: state.systemClick,
            );
            break;

          // ── مدخلٌ واحدٌ للبطاقة وكلمة المرور (طلبُ المالك 2026-08-14) ────
          //
          // إضافةٌ لا استبدال: `msr_card` و`admin_password` باقيان كما هما
          // لأن `shifts.closingMethod` يحمل القيمةَ تاريخياً، وحوارُ
          // UralCash ما زال يعرضهما. حوارُ PicPos وحدَه يستعمل هذه.
          //
          // ⚠️ والفحصُ **بالصلاحية** لا بوجود المستخدم: مسارُ `msr_card`
          // فوقُ يقبل أيَّ مستخدمٍ مسجَّل بلا فحصِ دورٍ إطلاقاً، فبطاقةُ أيّ
          // كاشيرٍ كانت تُغلق الورديةَ بفرقٍ صفر. وهذا يناقض طلبَ المالك
          // نفسَه («المديرُ هو من يجرد»).
          case 'card_or_password':
            final input = cardCode.trim().isNotEmpty
                ? cardCode.trim()
                : password.trim();
            if (input.isEmpty) {
              state = state.copyWith(isProcessing: false);
              throw Exception('مرّر البطاقة أو أدخل كلمة المرور');
            }

            // كلمةُ مرور الإعدادات تبقى مقبولةً — هي مفتاحُ المالك حين لا
            // يكون له حسابُ مستخدمٍ على الطرفيّة.
            if (ref.read(adminPasswordServiceProvider).verify(input)) {
              authenticated = true;
            } else {
              final authRepo = ref.read(authRepositoryProvider);
              final user = await authRepo.authenticateByPasswordOrCard(input);
              if (user == null) {
                state = state.copyWith(isProcessing: false);
                throw Exception('البطاقة أو كلمة المرور غير صالحة');
              }
              final codes =
                  await authRepo.getUserPermissionCodes(user.user.id);
              if (!canCloseShiftCodes(codes)) {
                state = state.copyWith(isProcessing: false);
                throw Exception(
                    'هذا المستخدم لا يملك صلاحية إغلاق الوردية');
              }
              authenticated = true;
            }

            state = state.copyWith(
              actualCashAmount: state.systemCash,
              actualBankAmount: state.systemCard,
              actualClickAmount: state.systemClick,
            );
            break;

          default:
            // 'normal' method: current behavior (enter amounts + admin password)
            final cleanPassword = password.trim();
            bool normalAuth = false;
            if (ref.read(adminPasswordServiceProvider).verify(cleanPassword)) {
              normalAuth = true;
            } else {
              final authRepo = ref.read(authRepositoryProvider);
              final user = await authRepo.authenticateByPasswordOrCard(cleanPassword);
              if (user != null && (user.role?.isSystemRole == true || (user.role?.name.toLowerCase().contains('admin') ?? false))) {
                normalAuth = true;
              }
            }

            if (!normalAuth) {
              state = state.copyWith(isProcessing: false);
              throw Exception('كلمة المرور غير صحيحة');
            }
            authenticated = true;
        }

        if (!authenticated) {
          state = state.copyWith(isProcessing: false);
          throw Exception('فشل التحقق');
        }
      }

      // ISS-FIN-03: Block on CRITICAL cash variance unless manager explicitly overrides.
      if (!overrideVariance) {
        final accountingService = ref.read(accountingServiceProvider);
        final varianceCheck = accountingService.validateShiftClose(
          expectedCash: state.systemCash,
          actualCash: state.actualCashAmount,
        );
        if (varianceCheck.isCritical) {
          state = state.copyWith(
            isProcessing: false,
            criticalVarianceBlocked: true,
          );
          return false;
        }
      }

      final treasuryRepo = ref.read(treasuryRepositoryProvider);

      // v122 visibility — log the close-shift entry point so we can correlate
      // the operator-clicked close with the SHIFT-MIRROR / DEAD-LETTER
      // outcome lines that follow.
      unawaited(DiagnosticLogger.log('SHIFT-CLOSE',
          'pos_closing_controller.closeShift CALLED userId=$userId '
          'actualCash=${state.actualCashAmount} '
          'actualBank=${state.actualBankAmount} '
          'actualClick=${state.actualClickAmount} '
          'actualTotal=${state.actualTotal} '
          'closingMethod=$closingMethod'));

      // Spec 135 NOTE 2 (req 4) — close the shift RESOLVED at load (the
      // cashier's own shift, or the cashier shift an admin attached to), not a
      // shift looked up by the logged-in user. An admin has no own open shift,
      // so the server close must target the resolved shift's OWNER.
      final closeOwnerUserId = state.resolvedShiftUserId ?? userId;

      // In client mode: route the close to the server (or queue if offline).
      // In standalone mode: this is a no-op (returns false immediately).
      await ClientWriteInterceptor.closeShift(
        userId: closeOwnerUserId,
        actualCash: state.actualCashAmount,
        actualCard: state.actualCardAmount,
      );

      // Always close the local shift record as well.
      // • Standalone mode  : the only close that matters.
      // • Client mode      : keeps the local DB consistent immediately so the
      //   cashier can open a new shift without waiting for server sync to arrive.
      //   The server-side close is handled above (or queued for when back online).
      //
      // Spec 029 corrective patch — fail FAST when there is no open
      // shift. The previous `if (currentShift != null)` silently
      // skipped the close DAO call but still ran the print + logout
      // chain → the operator saw "successful close" without anything
      // actually closing. Now we raise a clear Arabic error so the
      // upstream dialog can route to the open-shift dialog instead.
      // Spec 135 NOTE 2 (req 4) — close the shift resolved at load. Prefer the
      // resolvedShiftId (set for both cashier-own and admin-attached shifts);
      // fall back to the logged-in user's open shift for any legacy path that
      // reached here without a resolved id.
      int? closeShiftId = state.resolvedShiftId;
      if (closeShiftId == null) {
        final currentShift = await treasuryRepo.getCurrentOpenShift(userId);
        closeShiftId = currentShift?.id;
      }
      if (closeShiftId == null) {
        state = state.copyWith(isProcessing: false);
        throw Exception('لا توجد وردية مفتوحة لإغلاقها');
      }
      // Built BEFORE the close so the exact same figures are both persisted
      // and printed. Deriving the printout separately would let the stored
      // snapshot and the paper drift apart, which defeats the whole point of
      // keeping one.
      final settingsRepo2 = ref.read(settingsRepositoryProvider);
      final companyName = await settingsRepo2.getSetting('company_name');
      final fontScaleStr =
          await settingsRepo2.getSetting('closing_report_font_scale');
      final fontScale = double.tryParse(fontScaleStr ?? '') ?? 1.0;

      final snapshot = ShiftClosingSnapshot(
        invoiceCount: state.invoiceCount,
        totalSales: state.totalSales,
        systemCash: state.systemCash,
        systemCard: state.systemCard,
        systemClick: state.systemClick,
        actualCash: state.actualCashAmount,
        actualCard: state.actualCardAmount,
        actualClick: state.actualClickAmount,
        cashVariance: state.cashVariance,
        cardVariance: state.cardVariance,
        clickVariance: state.clickVariance,
        totalVariance: state.totalVariance,
        totalExpenses: state.totalExpenses,
        cashRefunds: state.cashRefunds,
        cashIncome: state.cashIncome,
        creditSales: state.creditIncome,
        creditSalesCount: state.creditCount,
        openingBalance: state.openingBalance,
        employeeName: authState.user?.displayName,
        companyName: companyName,
        closedAt: DateTime.now(),
      );

      await treasuryRepo.closeShiftWithAudit(
        closeShiftId,
        state.actualCashAmount,
        // القنواتُ غيرُ النقدية في الملاحظة: النقديُّ نفسُه هو المبلغُ
        // المُمرَّر فوق. وكليك كانت غائبةً فسجّل التدقيقُ ورديةً ناقصةً قناة.
        notes: [
          'إغلاق وردية POS',
          if (state.actualBankAmount > 0)
            'بنك: ${state.actualBankAmount.toStringAsFixed(AppConstants.decimalPlaces)}',
          if (state.actualClickAmount > 0)
            'كليك: ${state.actualClickAmount.toStringAsFixed(AppConstants.decimalPlaces)}',
        ].join(' - '),
        closingMethod: closingMethod,
        closingSnapshot: snapshot.encode(),
        onVarianceJeFailed: (variance) {
          // GAP-24: non-fatal — shift closes but UI warns the operator
          state = state.copyWith(varianceJeWarning: variance);
        },
      );

      // REMOVED: _recordLegacyClosingTransactions() was creating phantom
      // 'daily_closing' safe-transactions with `balanceAfter: systemCash`.
      // createSafeTransaction()'s else-branch used that value to SET the
      // safe balance → restored it to systemCash after _closeShiftSafes()
      // had already zeroed it, causing duplicate entries and wrong totals
      // in the treasury report.  The shift_closing records from
      // _closeShiftSafes() are sufficient; the treasury daily-closing
      // dialog creates its own daily_closing records separately.

      // NOTE: Shift closing JE REMOVED — individual sales/expense JEs already
      // handle all accounting entries (Debit Cash/Bank → Credit Sales).
      // A summary closing JE would DOUBLE-COUNT all amounts.
      // Variance entries (actual vs expected) are handled separately
      // in treasury_dao.dart → _postVarianceJournalEntry().

      await printShiftClosingSnapshot(
        snapshot: snapshot,
        fontScale: fontScale,
        printersRepo: ref.read(printersRepositoryProvider),
        // يتيح الطباعةَ بقالب `shift_closing` الذي صمّمه المستخدم؛ وبلا
        // قالبٍ افتراضيّ يبقى المولّدُ الثابت.
        db: ref.read(databaseProvider),
      );

      final logger = ref.read(activityLoggerProvider);
      await logger.logShiftClose(
        authState.user?.id ?? 0,
        authState.user?.displayName ?? 'الكاشير',
        expectedAmount: state.systemTotal,
        actualAmount: state.actualTotal,
      );

      // Feature 006 #1: refresh treasury views so the operator immediately
      // sees the just-zeroed branch safes and any open-shift indicator.
      // The DAO's safes-table writes already nudge the watch streams, but
      // FutureProviders (current-shift, balances) need an explicit refresh.
      ref.invalidate(scopedSafesProvider);
      ref.invalidate(allSafesProvider);

      // Spec 135 (final-review note) — reset the processing flag on the SUCCESS
      // path too, mirroring the catch branch. The dialog normally pops right
      // after a successful close, but if a caller keeps it mounted (or logout
      // is deferred) the button must not stay stuck disabled.
      state = state.copyWith(isProcessing: false);
      return true;
    } catch (e) {
      state = state.copyWith(isProcessing: false);
      rethrow;
    }
  }

  Future<void> _recordLegacyClosingTransactions(
    dynamic authState,
    double systemCash,
    double systemCard,
    double actualCash,
    double actualCard,
  ) async {
    final now = DateTime.now();
    final dateTimeStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final currentUserName = authState.user?.displayName ?? authState.user?.username ?? 'الكاشير';
    final currentUserId = authState.user?.id ?? 1;

    final treasuryRepo = ref.read(treasuryRepositoryProvider);
    final cashSafe = await treasuryRepo.getDefaultSafeByType('cash');
    final bankSafe = await treasuryRepo.getDefaultSafeByType('bank');

    if (cashSafe != null) {
      await treasuryRepo.createSafeTransaction(
        voucherNumber: 'CLO-CASH-$dateTimeStr',
        safeId: cashSafe.id,
        transactionType: 'closing',
        category: 'daily_closing',
        amount: systemCash,
        balanceAfter: systemCash,
        referenceType: 'daily_closing',
        description: 'الموظف: $currentUserName | إغلاق نقدي | النظام: ${systemCash.toStringAsFixed(AppConstants.decimalPlaces)} | الفعلي: ${actualCash.toStringAsFixed(AppConstants.decimalPlaces)}',
        userId: currentUserId,
      );
    }

    if (bankSafe != null) {
      await treasuryRepo.createSafeTransaction(
        voucherNumber: 'CLO-BANK-$dateTimeStr',
        safeId: bankSafe.id,
        transactionType: 'closing',
        category: 'daily_closing',
        amount: systemCard,
        balanceAfter: systemCard,
        referenceType: 'daily_closing',
        description: 'الموظف: $currentUserName | إغلاق بنكي | النظام: ${systemCard.toStringAsFixed(AppConstants.decimalPlaces)} | الفعلي: ${actualCard.toStringAsFixed(AppConstants.decimalPlaces)}',
        userId: currentUserId,
      );
    }
  }
}

final posClosingControllerProvider = NotifierProvider.autoDispose<PosClosingController, PosClosingState>(
  PosClosingController.new,
);
