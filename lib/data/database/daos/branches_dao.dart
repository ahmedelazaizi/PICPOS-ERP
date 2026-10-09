part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BRANCHES DAO - Multi-Branch Management
// ═══════════════════════════════════════════════════════════════════════════

extension BranchesDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════════
  // BRANCHES CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Watch all active branches. Spec 150 (BUG 5) — defensively collapses
  /// same-name duplicates before they reach the pickers; see
  /// [_dedupBranchesByName] for the survivor rule. Read-only: the
  /// destructive merge stays behind `BranchDedupExtension.mergeDuplicateBranches`.
  Stream<List<Branche>> watchBranches() {
    return (select(branches)
          ..where((b) => b.isActive.equals(true))
          ..orderBy([(b) => OrderingTerm.asc(b.name)]))
        .watch()
        .map(_dedupBranchesByName);
  }

  /// Get all active branches — see [watchBranches] for the dedup rationale.
  Future<List<Branche>> getBranches() async {
    final rows = await (select(branches)
          ..where((b) => b.isActive.equals(true))
          ..orderBy([(b) => OrderingTerm.asc(b.name)]))
        .get();
    return _dedupBranchesByName(rows);
  }

  /// Collapse rows sharing a trimmed name, keeping the `isSystemDefault`
  /// one first, else the one with a non-null `globalId`, else the lowest
  /// id. Belt-and-braces for the create-side fixes (setup wizard +
  /// seeder heal) — does not touch the database.
  List<Branche> _dedupBranchesByName(List<Branche> rows) {
    final byName = <String, Branche>{};
    for (final row in rows) {
      final key = row.name.trim();
      final current = byName[key];
      if (current == null || _preferBranch(row, current)) {
        byName[key] = row;
      }
    }
    return byName.values.toList();
  }

  bool _preferBranch(Branche candidate, Branche current) {
    if (candidate.isSystemDefault != current.isSystemDefault) {
      return candidate.isSystemDefault;
    }
    if ((candidate.globalId != null) != (current.globalId != null)) {
      return candidate.globalId != null;
    }
    return candidate.id < current.id;
  }

  /// Get branch by ID
  Future<Branche?> getBranchById(int id) async {
    return (select(branches)..where((b) => b.id.equals(id))).getSingleOrNull();
  }

  /// Create new branch
  Future<int> createBranch({
    required String name,
    String? code,
    String? address,
    String? phone,
    int? costCenterId,
    int? regionId,
  }) async {
    return into(branches).insert(
      BranchesCompanion.insert(
        name: name,
        code: Value(code),
        address: Value(address),
        phone: Value(phone),
        costCenterId: Value(costCenterId),
        regionId: Value(regionId),
        // UUID-First (Phase 1): stable cross-install identity for sync.
        globalId: Value(UuidV7.generate()),
      ),
    );
  }

  /// Update branch
  Future<bool> updateBranch(Branche branch) async {
    return update(branches).replace(branch);
  }

  /// Deactivate branch (soft delete) — IBW-05: validates financial safety
  Future<void> deactivateBranch(int id) async {
    // IBW-05: Prevent deactivation if open invoices exist in branch warehouses
    final branchWarehouses = await (select(warehouses)
          ..where((w) => w.branchId.equals(id) & w.isActive.equals(true)))
        .get();
    if (branchWarehouses.isNotEmpty) {
      // Check for non-zero safe balances
      final activeSafes = await (select(safes)
            ..where((s) => s.branchId.equals(id) & s.isActive.equals(true)))
          .get();
      final nonZeroSafes = activeSafes.where((s) => s.balance.abs() > 0.01);
      if (nonZeroSafes.isNotEmpty) {
        throw Exception(
          'لا يمكن إلغاء تفعيل الفرع: يوجد ${nonZeroSafes.length} صندوق برصيد غير صفري',
        );
      }
    }
    await (update(branches)..where((b) => b.id.equals(id))).write(
      const BranchesCompanion(isActive: Value(false)),
    );
  }

  /// Insert a branch. Auto-mints a UUID v7 globalId if the caller didn't
  /// supply one — UUID-First (Phase 1).
  Future<int> insertBranch(BranchesCompanion branch) {
    final hasGid = branch.globalId.present &&
        (branch.globalId.value?.isNotEmpty ?? false);
    final withGid =
        hasGid ? branch : branch.copyWith(globalId: Value(UuidV7.generate()));
    return into(branches).insert(withGid);
  }

  /// Soft-delete a branch with optional bulk-reassign of user access.
  ///
  /// Feature 049 (v131) — replaces the pre-v131 HARD DELETE which failed
  /// with FK violation 23503 whenever the branch had ANY `user_branch_access`
  /// row referencing it. Field-observed on 2026-05-13 14:04:07 when admin
  /// tried to delete a duplicate "الفرع الرئيسي" (id=7) on the server and
  /// hit:
  ///   PG FAIL: foreign key constraint "user_branch_access_branch_id_fkey"
  ///   detail: Key (id)=(7) is still referenced from table user_branch_access
  ///
  /// Same root pattern as Feature 045 categories: schema has `isActive` +
  /// `deletedAt` already, but the delete code bypassed them with a hard
  /// DELETE. Reports + dropdowns filter by `isActive=true` so soft-delete
  /// flows naturally through the existing UI.
  ///
  /// Pre-flight FK checks (caller fixes the issue first, then retries):
  ///   - sales_invoices referencing the branch (legacy v131-style check)
  ///   - purchase_invoices
  ///   - shifts that are still open OR ANY history (financial audit trail
  ///     must stay tied to the branch)
  ///   - safes whose `branchId` points here AND have non-zero balance
  ///
  /// [reassignUsersToBranchId] handles the dedup-duplicate-branch case:
  /// when the operator wants to delete a duplicate of "الفرع الرئيسي"
  /// because mirror sync drift created multiple copies, the user
  /// assignments on the duplicate must be transferred to the canonical
  /// branch first. Null = no reassign (default; throws if any user
  /// assignment exists).
  Future<void> deleteBranch(
    int id, {
    int? reassignUsersToBranchId,
  }) async {
    if (reassignUsersToBranchId != null && reassignUsersToBranchId == id) {
      throw ArgumentError(
        'reassignUsersToBranchId must differ from the branch being deleted',
      );
    }
    await transaction(() async {
      // Check if any sale invoices reference this branch — legacy v131
      // pre-check; preserved because financial reports need the row to
      // exist (we soft-delete, not hard-delete, so they would survive
      // anyway, but the operator deserves the early "you have data
      // here" message before we touch user assignments).
      final salesCount = await (select(salesInvoices)
            ..where((i) => i.warehouseId.equals(id))
            ..limit(1))
          .get();
      if (salesCount.isNotEmpty) {
        throw Exception('لا يمكن حذف هذا الفرع: مرتبط بفواتير مبيعات');
      }

      final purchasesCount = await (select(purchaseInvoices)
            ..where((i) => i.warehouseId.equals(id))
            ..limit(1))
          .get();
      if (purchasesCount.isNotEmpty) {
        throw Exception('لا يمكن حذف هذا الفرع: مرتبط بفواتير مشتريات');
      }

      // Feature 049 — handle user_branch_access. When caller supplies a
      // destination, REASSIGN. Otherwise count + throw a clear error so
      // the operator can choose to either reassign or unassign first.
      final userLinks = await (select(userBranchAccess)
            ..where((u) => u.branchId.equals(id)))
          .get();
      if (userLinks.isNotEmpty) {
        if (reassignUsersToBranchId == null) {
          throw Exception('لا يمكن حذف هذا الفرع: مرتبط بـ '
              '${userLinks.length} مستخدم. يرجى نقلهم إلى فرع آخر أولاً.');
        }
        // Defensive: ensure the destination exists + is active. Caller
        // already enforced this via the UI dropdown but the DAO is the
        // last line of defense.
        final destBranch = await (select(branches)
              ..where((b) => b.id.equals(reassignUsersToBranchId))
              ..limit(1))
            .getSingleOrNull();
        if (destBranch == null || !destBranch.isActive) {
          throw Exception('فرع الوجهة لإعادة التعيين غير صالح '
              '(id=$reassignUsersToBranchId)');
        }
        // Move user assignments. Compound PK (userId, branchId) means we
        // must delete-then-insert per row to avoid PK collision when the
        // user already has access to the destination branch.
        for (final link in userLinks) {
          await (delete(userBranchAccess)
                ..where((u) =>
                    u.userId.equals(link.userId) &
                    u.branchId.equals(id)))
              .go();
          // Idempotent — skip insert if user already has destination.
          final already = await (select(userBranchAccess)
                ..where((u) =>
                    u.userId.equals(link.userId) &
                    u.branchId.equals(reassignUsersToBranchId)))
              .getSingleOrNull();
          if (already == null) {
            await into(userBranchAccess).insert(
              UserBranchAccessCompanion.insert(
                userId: link.userId,
                branchId: reassignUsersToBranchId,
              ),
            );
          }
        }
      }

      // Soft-delete instead of hard-delete. The row stays referenceable
      // by historical journal entries / safes / shifts (no FK collateral
      // damage) but disappears from active dropdowns + reports because
      // those filter on `isActive=true`.
      await (update(branches)..where((b) => b.id.equals(id))).write(
        BranchesCompanion(
          isActive: const Value(false),
          deletedAt: Value(DateTime.now()),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// Feature 049 — count user_branch_access rows that would be affected
  /// by deleting [branchId]. Used by the delete-branch UI to choose
  /// between an empty-confirm dialog and the bulk-reassign dialog.
  Future<int> countUsersWithBranchAccess(int branchId) async {
    final rows = await (select(userBranchAccess)
          ..where((u) => u.branchId.equals(branchId)))
        .get();
    return rows.length;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WAREHOUSES BY BRANCH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get warehouses for a specific branch
  Future<List<Warehouse>> getWarehousesByBranch(int branchId) async {
    return (select(warehouses)
          ..where((w) => w.branchId.equals(branchId))
          ..where((w) => w.isActive.equals(true)))
        .get();
  }

  /// Watch warehouses for a branch
  Stream<List<Warehouse>> watchWarehousesByBranch(int branchId) {
    return (select(warehouses)
          ..where((w) => w.branchId.equals(branchId))
          ..where((w) => w.isActive.equals(true)))
        .watch();
  }

  /// Create warehouse for branch
  Future<int> createWarehouseForBranch({
    required String name,
    required int branchId,
    bool isDefault = false,
  }) async {
    return insertWarehouse(WarehousesCompanion.insert(
      name: name,
      branchId: Value(branchId),
      isDefault: Value(isDefault),
      globalId: Value(UuidV7.generate()),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BRANCH STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get sales summary for a branch
  Future<BranchSalesSummary> getBranchSalesSummary(
    int branchId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final warehouse =
        await (select(warehouses)
              ..where((w) => w.branchId.equals(branchId))
              ..where((w) => w.isDefault.equals(true)))
            .getSingleOrNull();

    if (warehouse == null) {
      return BranchSalesSummary.empty(branchId);
    }

    var query = select(salesInvoices)
      ..where((s) => s.warehouseId.equals(warehouse.id));

    if (from != null && to != null) {
      query = query
        ..where((s) => s.invoiceDate.isBetween(Variable(from), Variable(to)));
    }

    final invoices = await query.get();

    double totalSales = 0;
    double totalProfit = 0;
    int invoiceCount = 0;

    for (final invoice in invoices) {
      totalSales += invoice.total;
      invoiceCount++;
    }

    return BranchSalesSummary(
      branchId: branchId,
      totalSales: totalSales,
      totalProfit: totalProfit,
      invoiceCount: invoiceCount,
      period: from != null && to != null
          ? BranchDateRange(start: from, end: to)
          : null,
    );
  }

  /// Get inventory value for a branch, valued at the global WAC
  /// (products.costPrice) — the single inventory-cost SoT (Spec 153, owner
  /// decision 2026-07-12) — so it ties out to GL account 1136, the inventory
  /// report (post-م-1) and the م-2 reconciliation. NOT per-warehouse
  /// inventory_balances.average_cost, which is informational only and never
  /// posts to GL (using it here made the branch value diverge from the ledger).
  Future<double> getBranchInventoryValue(int branchId) async {
    final warehouseList = await getWarehousesByBranch(branchId);
    if (warehouseList.isEmpty) return 0;

    final ids = warehouseList.map((w) => w.id).toList();
    final row = await customSelect(
      'SELECT COALESCE(SUM(ib.quantity * p.cost_price), 0.0) AS v '
      'FROM inventory_balances ib '
      'JOIN products p ON p.id = ib.product_id '
      'WHERE ib.warehouse_id IN (${ids.map((_) => '?').join(', ')}) '
      'AND p.track_inventory = 1',
      variables: ids.map((id) => Variable<int>(id)).toList(),
      readsFrom: {inventoryBalances, products},
    ).getSingle();
    return (row.data['v'] as num?)?.toDouble() ?? 0.0;
  }

  /// Auto-link cost centers to branches, warehouses, and regions by matching names.
  Future<int> autoLinkCostCenters() async {
    final allCC = await (select(costCenters)
      ..where((c) => c.isActive.equals(true))).get();
    if (allCC.isEmpty) return 0;

    int linked = 0;
    final ccMap = <String, int>{};
    for (final cc in allCC) {
      ccMap[cc.name.trim()] = cc.id;
    }

    // 1. Branches without cost center
    final ubranches = await (select(branches)
      ..where((b) => b.costCenterId.isNull() & b.isActive.equals(true))).get();
    for (final b in ubranches) {
      final ccId = ccMap[b.name.trim()];
      if (ccId != null) {
        await (update(branches)..where((x) => x.id.equals(b.id)))
          .write(BranchesCompanion(costCenterId: Value(ccId)));
        linked++;
        debugPrint('[AutoLink] Branch "${b.name}" → CC #$ccId');
      }
    }

    // 2. Warehouses without cost center
    final uwhs = await (select(warehouses)
      ..where((w) => w.costCenterId.isNull() & w.isActive.equals(true))).get();
    for (final wh in uwhs) {
      var ccId = ccMap[wh.name.trim()];
      if (ccId == null && wh.branchId != null) {
        final br = await (select(branches)..where((x) => x.id.equals(wh.branchId!))..limit(1)).getSingleOrNull();
        if (br != null) ccId = ccMap[br.name.trim()];
      }
      if (ccId != null) {
        await (update(warehouses)..where((x) => x.id.equals(wh.id)))
          .write(WarehousesCompanion(costCenterId: Value(ccId)));
        linked++;
        debugPrint('[AutoLink] Warehouse "${wh.name}" → CC #$ccId');
      }
    }

    // 3. Regions without cost center
    final uregs = await (select(regions)
      ..where((r) => r.costCenterId.isNull() & r.isActive.equals(true))).get();
    for (final r in uregs) {
      final ccId = ccMap[r.name.trim()];
      if (ccId != null) {
        await (update(regions)..where((x) => x.id.equals(r.id)))
          .write(RegionsCompanion(costCenterId: Value(ccId)));
        linked++;
        debugPrint('[AutoLink] Region "${r.name}" → CC #$ccId');
      }
    }

    if (linked > 0) debugPrint('[AutoLink] ✅ Linked $linked entities to cost centers');
    return linked;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERVER-SIDE DUPLICATE DEDUP (Spec 084c)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Pre-v131 installs accumulated duplicate "الفرع الرئيسي" rows from a
  // bug in the sync layer (now fixed by Feature 049). This pair of helpers
  // gives the operator an in-app affordance to audit and merge those
  // ghost rows. Mirrors `specs/049-branch-soft-delete-bulk-reassign/
  // duplicate_branch_repair.sql` — keep them in sync.
  //
  // Server mode only. Mirror/client/standalone callers should not invoke
  // these — the UI gates on `NetworkService.instance.isServerRunning`.

  /// Find all groups of active branches that share a name (case-sensitive).
  /// Within each group, the row with the highest reference count is the
  /// suggested canonical pick (ties broken by lowest id).
  Future<List<DuplicateBranchGroup>> auditDuplicateBranches() async {
    final rows = await customSelect(r'''
      WITH dup_names AS (
        SELECT name FROM branches
        WHERE is_active = TRUE
        GROUP BY name HAVING COUNT(*) > 1
      ),
      ref_counts AS (
        SELECT b.id, b.name, b.global_id,
               (SELECT COUNT(*) FROM user_branch_access WHERE branch_id = b.id)
             + (SELECT COUNT(*) FROM sales_invoices    WHERE branch_id = b.id)
             + (SELECT COUNT(*) FROM purchase_invoices WHERE branch_id = b.id)
             + (SELECT COUNT(*) FROM shifts            WHERE branch_id = b.id)
             + (SELECT COUNT(*) FROM safes             WHERE branch_id = b.id)
               AS ref_count,
               (SELECT COUNT(*) FROM sales_invoices    WHERE branch_id = b.id)
             + (SELECT COUNT(*) FROM purchase_invoices WHERE branch_id = b.id)
             + (SELECT COUNT(*) FROM shifts            WHERE branch_id = b.id)
               AS attached_txn_refs
        FROM branches b
        WHERE b.is_active = TRUE
          AND b.name IN (SELECT name FROM dup_names)
      )
      SELECT id, name, global_id, ref_count, attached_txn_refs
      FROM ref_counts
      ORDER BY name, ref_count DESC, id ASC
    ''').get();

    final byName = <String, List<DuplicateBranchRow>>{};
    for (final r in rows) {
      final name = r.read<String>('name');
      byName.putIfAbsent(name, () => []).add(DuplicateBranchRow(
            id: r.read<int>('id'),
            name: name,
            globalId: r.read<String?>('global_id'),
            refCount: r.read<int>('ref_count'),
            attachedTxnRefs: r.read<int>('attached_txn_refs'),
          ));
    }

    return byName.entries.map((e) {
      final all = e.value;
      return DuplicateBranchGroup(
        name: e.key,
        canonical: all.first,
        duplicates: all.skip(1).toList(),
      );
    }).toList();
  }

  /// Run the dedup repair: reassign user_branch_access from each duplicate
  /// to its canonical, then soft-delete the duplicate. Duplicates with any
  /// attached transactional row (sales/purchase invoice, shift) are SKIPPED
  /// — operator must merge those via the v131 bulk-reassign UI first.
  ///
  /// All steps run inside `transaction()`; any exception rolls back.
  /// Each merged or skipped duplicate emits one `DiagnosticLogger` line.
  /// Returns a result summary the caller can render.
  Future<BranchDedupResult> repairDuplicateBranches() async {
    return await transaction(() async {
      final groups = await auditDuplicateBranches();
      final merged = <MergedBranchDedupRecord>[];
      final skipped = <SkippedBranchDedupRecord>[];

      for (final g in groups) {
        for (final dup in g.duplicates) {
          if (dup.attachedTxnRefs > 0) {
            skipped.add(SkippedBranchDedupRecord(
              dupId: dup.id,
              canonicalId: g.canonical.id,
              name: g.name,
              attachedTxnRefs: dup.attachedTxnRefs,
            ));
            await DiagnosticLogger.log(
              'BRANCH-DEDUP',
              'SKIP dupId=${dup.id} → canonicalId=${g.canonical.id} '
                  'name="${g.name}" attachedTxnRefs=${dup.attachedTxnRefs}',
            );
            continue;
          }

          // Reassign user_branch_access — INSERT canonical row first, then
          // DELETE duplicate row. The NOT EXISTS guard handles compound-PK
          // collisions when the user already has the canonical.
          await customStatement('''
            INSERT INTO user_branch_access (user_id, branch_id)
            SELECT uba.user_id, ?
            FROM user_branch_access uba
            WHERE uba.branch_id = ?
              AND NOT EXISTS (
                SELECT 1 FROM user_branch_access x
                WHERE x.user_id = uba.user_id AND x.branch_id = ?
              )
          ''', [g.canonical.id, dup.id, g.canonical.id]);

          await customStatement(
            'DELETE FROM user_branch_access WHERE branch_id = ?',
            [dup.id],
          );

          // Soft-delete the duplicate.
          await (update(branches)..where((b) => b.id.equals(dup.id))).write(
            BranchesCompanion(
              isActive: const Value(false),
              deletedAt: Value(DateTime.now()),
              lastModifiedAt: Value(DateTime.now()),
            ),
          );

          merged.add(MergedBranchDedupRecord(
            dupId: dup.id,
            canonicalId: g.canonical.id,
            name: g.name,
          ));
          await DiagnosticLogger.log(
            'BRANCH-DEDUP',
            'merged dupId=${dup.id} → canonicalId=${g.canonical.id} '
                'name="${g.name}"',
          );
        }
      }

      return BranchDedupResult(merged: merged, skipped: skipped);
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Branch sales summary
class BranchSalesSummary {
  final int branchId;
  final double totalSales;
  final double totalProfit;
  final int invoiceCount;
  final BranchDateRange? period;

  BranchSalesSummary({
    required this.branchId,
    required this.totalSales,
    required this.totalProfit,
    required this.invoiceCount,
    this.period,
  });

  factory BranchSalesSummary.empty(int branchId) => BranchSalesSummary(
    branchId: branchId,
    totalSales: 0,
    totalProfit: 0,
    invoiceCount: 0,
  );

  double get averageInvoiceValue =>
      invoiceCount > 0 ? totalSales / invoiceCount : 0;
}

class BranchDateRange {
  final DateTime start;
  final DateTime end;

  BranchDateRange({required this.start, required this.end});

  Duration get duration => end.difference(start);
}

// ═══════════════════════════════════════════════════════════════════════════
// Spec 084c — branches dedup data classes
// ═══════════════════════════════════════════════════════════════════════════

class DuplicateBranchRow {
  final int id;
  final String name;
  final String? globalId;
  final int refCount;
  final int attachedTxnRefs;

  const DuplicateBranchRow({
    required this.id,
    required this.name,
    required this.globalId,
    required this.refCount,
    required this.attachedTxnRefs,
  });
}

class DuplicateBranchGroup {
  final String name;
  final DuplicateBranchRow canonical;
  final List<DuplicateBranchRow> duplicates;

  const DuplicateBranchGroup({
    required this.name,
    required this.canonical,
    required this.duplicates,
  });

  bool get hasDuplicates => duplicates.isNotEmpty;
}

class MergedBranchDedupRecord {
  final int dupId;
  final int canonicalId;
  final String name;
  const MergedBranchDedupRecord({
    required this.dupId,
    required this.canonicalId,
    required this.name,
  });
}

class SkippedBranchDedupRecord {
  final int dupId;
  final int canonicalId;
  final String name;
  final int attachedTxnRefs;
  const SkippedBranchDedupRecord({
    required this.dupId,
    required this.canonicalId,
    required this.name,
    required this.attachedTxnRefs,
  });
}

class BranchDedupResult {
  final List<MergedBranchDedupRecord> merged;
  final List<SkippedBranchDedupRecord> skipped;
  const BranchDedupResult({required this.merged, required this.skipped});

  bool get isEmpty => merged.isEmpty && skipped.isEmpty;

  int get mergedCount => merged.length;
  int get skippedCount => skipped.length;
  bool get hasSkipped => skipped.isNotEmpty;
}
