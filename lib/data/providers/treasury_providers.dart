import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart'; // For supabaseDatabaseProvider
import 'dashboard_filter_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TREASURY PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

// Feature 011 / Issue UX-SCROLL — keep `.autoDispose` (Issue UX-LOAD
// follow-up): an earlier attempt removed `.autoDispose` to address a
// scroll-position-loss symptom, but on the beta restaurant build that
// caused the treasury Cash/Bank tabs to render as forever-loading
// spinners. Empirically the stream-loading state didn't transition
// reliably without the autoDispose recreate cycle. The actual scroll
// reset was caused by the implicit ScrollController in the ListViews
// below — fixed in treasury_transactions_list.dart, treasury_cash_tab
// .dart, and treasury_bank_tab.dart by binding a State-field controller.
final allSafesProvider = StreamProvider.autoDispose<List<SafeData>>((ref) {
  if (kIsWeb) {
    // final supabase = // TODO: unused ref.watch(supabaseDatabaseProvider);
    // Supposing supabase also returns SafeData or can be mapped
    return Stream<List<SafeData>>.value([]);
  }
  final repo = ref.watch(treasuryRepositoryProvider);
  return repo.watchSafes();
});

/// Feature 005 Phase 8 — branch-scoped safes for the treasury UI.
///
/// Mirrors [scopedRecentTransactionsProvider] but for the safe list itself.
/// Pre-fix the treasury screen used [allSafesProvider] which exposes every
/// safe regardless of the current user's branch access — a security bug
/// that let "مدير فرع العقبة" see safes from الادارة / مطعم معان / سوبر
/// ماركت معان in the same list.
///
/// Behaviour:
///   - admin / financial manager (`hasFullAccess == true`) → full list.
///   - branch-restricted user → safes whose `branch_id` is in
///     `allowedBranchIds`, plus safes with `branch_id == null` (legacy
///     unscoped rows must remain visible to keep balances reconciling).
final scopedSafesProvider = StreamProvider.autoDispose<List<SafeData>>((ref) {
  if (kIsWeb) {
    return Stream<List<SafeData>>.value([]);
  }
  final scopeAsync = ref.watch(branchScopeProvider);
  final repo = ref.watch(treasuryRepositoryProvider);
  return scopeAsync.when(
    data: (scope) => repo.watchSafesForBranches(scope.allowedBranchIds),
    loading: () => const Stream<List<SafeData>>.empty(),
    // On scope-resolution error, prefer empty over leaking — branch
    // isolation is a correctness invariant we don't relax on errors.
    error: (_, _) => const Stream<List<SafeData>>.empty(),
  );
});

/// Issue 14 — recent treasury transactions scoped to the current user's
/// allowed branches. Admin / financial-manager (full-access) gets every
/// branch's vouchers as before; a branch-restricted user only sees rows
/// whose safe lives in one of their branches.
final scopedRecentTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionData>>((ref) {
  if (kIsWeb) {
    return Stream<List<TransactionData>>.value([]);
  }
  final scopeAsync = ref.watch(branchScopeProvider);
  final repo = ref.watch(treasuryRepositoryProvider);
  return scopeAsync.when(
    data: (scope) =>
        repo.watchRecentTransactionsForBranches(scope.allowedBranchIds),
    loading: () => const Stream<List<TransactionData>>.empty(),
    // On scope-resolution error, fall back to no-filter so the screen
    // still shows data instead of looking broken.
    error: (_, _) => repo.watchRecentTransactions(),
  );
});

/// Total balance across ALL safe types (cash + bank + electronic), scoped to
/// the operator's allowed branches.
///
/// Spec 136 (field 2026-06-11): folds over [scopedSafesProvider] (branch-
/// scoped) instead of [allSafesProvider]. The old version summed every
/// branch's safes regardless of the user's branch access — a branch-isolation
/// leak that made the dashboard "أرصدة جميع الصناديق" card and the treasury
/// metrics panel show other branches' balances. It is a live snapshot of
/// safes.balance (no period dimension — a running balance is "now" by nature).
final totalCashBalanceProvider = Provider.autoDispose<AsyncValue<double>>((
  ref,
) {
  final safesAsync = ref.watch(scopedSafesProvider);
  return safesAsync.whenData(
    (list) => list.whereType<SafeData>().fold(0.0, (sum, safe) => sum + safe.balance),
  );
});

/// Pure filter behind [dashboardCashBalanceProvider] — kept as a standalone
/// function so it's unit-testable without a ProviderContainer. Safes with a
/// null branchId (legacy unscoped rows) always count, mirroring
/// [scopedSafesProvider]'s own reconciliation rule above.
double sumSafeBalancesForBranch(List<SafeData> safes, int? branchId) {
  return safes
      .where((safe) =>
          branchId == null || safe.branchId == null || safe.branchId == branchId)
      .fold(0.0, (sum, safe) => sum + safe.balance);
}

/// Spec 150 (BUG-6 Fix 2, field 2026-07-09) — the HOME dashboard's "أرصدة
/// الصناديق" card, scoped down further by [dashboardFilterProvider]'s branch
/// selection. [totalCashBalanceProvider] above is left untouched — it also
/// backs the treasury metrics panel, which isn't part of this fix — this one
/// folds over the same branch-auth-scoped [scopedSafesProvider] and
/// additionally narrows to the filter's branchId when the operator picks one.
final dashboardCashBalanceProvider = Provider.autoDispose<AsyncValue<double>>((
  ref,
) {
  final branchId =
      ref.watch(dashboardFilterProvider.select((f) => f.branchId));
  final safesAsync = ref.watch(scopedSafesProvider);
  return safesAsync.whenData(
    (list) => sumSafeBalancesForBranch(list.whereType<SafeData>().toList(), branchId),
  );
});
