// Spec 150 — BUG 6 Fix 2: the HOME dashboard's "أرصدة الصناديق" card ignored
// the shared dashboard filter's branch selection and always summed every
// safe the operator was allowed to see (see dashboard_screen.dart's
// cashBalance / dashboardCashBalanceProvider in treasury_providers.dart).
//
// The fix scopes the sum down to sumSafeBalancesForBranch(safes, branchId) —
// a plain function over SafeData, extracted so it's unit-testable without a
// ProviderContainer (dashboardCashBalanceProvider itself is just this
// function folded over scopedSafesProvider + dashboardFilterProvider.branchId).

import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/providers/treasury_providers.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';

SafeData _safe({required int id, required double balance, int? branchId}) {
  return SafeData(
    id: id,
    name: 'safe-$id',
    safeType: 'cash',
    balance: balance,
    isDefault: false,
    isActive: true,
    branchId: branchId,
  );
}

void main() {
  group('Spec 150 BUG-6 Fix 2 — dashboard cash balance branch scope', () {
    final safes = [
      _safe(id: 1, balance: 100, branchId: 1),
      _safe(id: 2, balance: 250, branchId: 2),
      _safe(id: 3, balance: 50, branchId: null), // legacy unscoped
    ];

    test('no branch selected (branchId == null) sums every safe', () {
      expect(sumSafeBalancesForBranch(safes, null), 400.0);
    });

    test('a specific branch sums only that branch + unscoped legacy safes',
        () {
      expect(sumSafeBalancesForBranch(safes, 1), 150.0); // 100 + 50
      expect(sumSafeBalancesForBranch(safes, 2), 300.0); // 250 + 50
    });

    test('a branch with no safes of its own still counts unscoped legacy ones',
        () {
      expect(sumSafeBalancesForBranch(safes, 99), 50.0);
    });
  });
}
