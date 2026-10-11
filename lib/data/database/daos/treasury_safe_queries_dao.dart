part of '../database.dart';

/// Safe reads: watchers, defaults, totals, branch-scoped lists, user branch.
extension TreasurySafeQueriesDao on AppDatabase {
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
}
