import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/logging/diagnostic_logger.dart';
import '../../services/inventory_service.dart';
import 'providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTY PROVIDERS (Customers, Suppliers, Couriers)
//
// All three list providers (customers, suppliers, all-parties) now flow
// through `branchScopeProvider` so a branch-restricted user only sees
// parties tagged for one of their branches (or `is_global = true`).
// Admin / financial-manager users hit `BranchScope.fullAccess` and the
// repo short-circuits to its existing global query — same SQL as before
// the scoping was added, so admin behaviour is unchanged.
//
// While the scope future is still resolving (first frame after login,
// before branchScopeProvider has returned) the providers emit an empty
// list rather than the unscoped admin-equivalent — otherwise a
// restricted cashier would briefly see other branches' rows during
// the ~tens-of-ms scope lookup. The StreamProvider re-evaluates as
// soon as the scope future completes (`ref.watch` on the AsyncValue),
// so this is a single-frame placeholder, not a permanent empty state.
// ═══════════════════════════════════════════════════════════════════════════

Stream<List<Party>> _emptyParties() => Stream<List<Party>>.value(const []);

// Spec 115 diagnostic — counters لـ provider re-evaluations. كل مرة الـ
// builder يُنفَّذ يعني stream pipeline جديد. لو هذا العدد يساوي تقريباً
// عدد [PARTIES-BUILD] في الـ widget، إذن الـ provider يُعاد بناءه على كل
// rebuild — الـ distinct/debounce لا تنجو عبر re-evaluations.
int _allPartiesEvals = 0;
int _allCustomersEvals = 0;
int _allSuppliersEvals = 0;

void _logEval(String tag, int count) {
  if (count <= 5 || count % 10 == 0) {
    unawaited(DiagnosticLogger.log(
      'PARTIES-PROVIDER-EVAL',
      '$tag re-eval #$count',
    ));
  }
}

// Feature 011 / Issue UX-LOAD — keep `.autoDispose`. An earlier attempt
// removed it (UX-SCROLL fix) on the theory that transient re-watches were
// disposing the provider, but field testing showed the loading state
// didn't transition reliably without autoDispose's recreate cycle. The
// actual scroll-position fix is the State-field ScrollController in the
// consuming widgets — see treasury_transactions_list.dart etc.
// Spec 115 (L3 + L4) — منع flicker AsyncLoading + منع re-evaluation الزائد.
//
// L3 — `.value` بدل `.asData?.value`: `.asData` يُرجع null أثناء AsyncLoading
// حتى مع previousData. `.value` يحفظها (Riverpod 3.2.1 async_value.dart:540-551).
//
// L4 — `select((s) => s.value)`: يُشغّل re-evaluation فقط إذا `.value`
// تغيّر فعلاً. `ref.watch(provider)` العادي يُشغّل re-eval على كل تغيير
// AsyncValue type (Loading↔Data) حتى لو `.value` ثابت. هذا يحفظ الـ Drift
// stream pipeline (distinct + debounce) من إعادة الإنشاء في كل auth tick.
// مرجع: specs/115-parties-rebuild-loop/research.md.
final allCustomersProvider = StreamProvider.autoDispose<List<Party>>((ref) {
  _allCustomersEvals++;
  _logEval('allCustomersProvider', _allCustomersEvals);
  if (kIsWeb) {
    final supabase = ref.watch(supabaseDatabaseProvider);
    return supabase?.watchCustomers() ?? Stream<List<Party>>.value([]);
  }
  final repo = ref.watch(partiesRepositoryProvider);
  final scope = ref.watch(branchScopeProvider.select((s) => s.value));
  if (scope == null) return _emptyParties();
  return repo.watchCustomersForBranches(scope.allowedBranchIds);
});

final allSuppliersProvider = StreamProvider.autoDispose<List<Party>>((ref) {
  _allSuppliersEvals++;
  _logEval('allSuppliersProvider', _allSuppliersEvals);
  if (kIsWeb) {
    final supabase = ref.watch(supabaseDatabaseProvider);
    return supabase?.watchSuppliers() ?? Stream<List<Party>>.value([]);
  }
  final repo = ref.watch(partiesRepositoryProvider);
  final scope = ref.watch(branchScopeProvider.select((s) => s.value));
  if (scope == null) return _emptyParties();
  return repo.watchSuppliersForBranches(scope.allowedBranchIds);
});

/// All parties provider (both customers and suppliers) — branch-scoped.
final allPartiesProvider = StreamProvider.autoDispose<List<Party>>((ref) {
  _allPartiesEvals++;
  _logEval('allPartiesProvider', _allPartiesEvals);
  final repo = ref.watch(partiesRepositoryProvider);
  final scope = ref.watch(branchScopeProvider.select((s) => s.value));
  if (scope == null) return _emptyParties();
  return repo.watchAllPartiesForBranches(scope.allowedBranchIds);
});

final allDeliveryCompaniesProvider =
    StreamProvider.autoDispose<List<DeliveryCompany>>((ref) {
      final repo = ref.watch(deliveryRepositoryProvider);
      return repo.watchDeliveryCompanies();
    });

/// Phase 2: Parties acting as Delivery Companies
final allDeliveryPartiesProvider = StreamProvider.autoDispose<List<Party>>((
  ref,
) {
  final repo = ref.watch(partiesRepositoryProvider);
  return repo.watchDeliveryParties();
});

final allCouriersProvider = StreamProvider.autoDispose<List<Courier>>((ref) {
  final repo = ref.watch(deliveryRepositoryProvider);
  return repo.watchCouriers();
});

/// Phase 2: Inventory Bonds Service
final inventoryServiceProvider = Provider<InventoryService>((ref) {
  final db = ref.watch(databaseProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  return InventoryService(db, settings);
});
