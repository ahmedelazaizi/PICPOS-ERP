// ═══════════════════════════════════════════════════════════════════════════
// COST CENTER RESOLVER — ISS-17
// ═══════════════════════════════════════════════════════════════════════════
//
// Ensures every financial transaction has a cost center assigned.
// Resolution order:
//   1. Explicit cost center ID from the transaction
//   2. Default cost center from the branch
//   3. Global default (first active cost center)
//   4. null (only if no cost centers exist at all)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import '../data/database/database.dart';

/// Resolves a cost center ID using a fallback chain.
///
/// ISS-17: Ensures no financial transaction is saved without a cost center.
class CostCenterResolver {
  final AppDatabase _db;

  CostCenterResolver(this._db);

  /// Resolve non-null cost center ID with fallback chain:
  /// explicit → branch default → global default → null
  Future<int?> resolve({
    int? explicitCostCenterId,
    int? branchId,
  }) async {
    // 1. If explicitly provided, use it
    if (explicitCostCenterId != null) return explicitCostCenterId;

    // 2. Try to get default from branch
    if (branchId != null) {
      try {
        final branch = await (_db.select(_db.branches)
              ..where((b) => b.id.equals(branchId)))
            .getSingleOrNull();
        if (branch?.costCenterId != null) {
          debugPrint(
            '[CostCenterResolver] Resolved from branch $branchId → CC ${branch!.costCenterId}',
          );
          return branch.costCenterId;
        }
      } catch (e) {
        debugPrint('[CostCenterResolver] Branch lookup failed: $e');
      }
    }

    // 3. Try global default (first active cost center)
    try {
      final firstCC = await (_db.select(_db.costCenters)
            ..where((cc) => cc.isActive.equals(true))
            ..limit(1))
          .getSingleOrNull();
      if (firstCC != null) {
        debugPrint(
          '[CostCenterResolver] Using global default CC: ${firstCC.id} (${firstCC.name})',
        );
        return firstCC.id;
      }
    } catch (e) {
      debugPrint('[CostCenterResolver] Global CC lookup failed: $e');
    }

    // 4. No cost centers exist
    debugPrint('[CostCenterResolver] No cost center found — returning null');
    return null;
  }
}
