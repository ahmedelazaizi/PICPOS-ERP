// =======================================================================
// PURCHASE REPORTS DAO
// Extracted from purchase_dao.dart - Sprint 12 God File Splitting
// =======================================================================

part of '../database.dart';

/// Extension for Purchase Reports operations
extension PurchaseReportsDao on AppDatabase {
  /// Spec 149 B12-5a — auth-scope branch filter for the raw-SQL aggregate
  /// analytics queries below (backend-only; screens wired separately in
  /// B12-5b, so with no caller passing `allowedBranchIds` behaviour is
  /// unchanged). Mirrors B12-1's `_buildAuthScopeFilter` contract (see
  /// AccountingReportsDao / BranchScope in
  /// lib/data/providers/branch_scope_provider.dart):
  ///   null      → no filter (full access)
  ///   {}        → `AND 1 = 0` (fail-closed)
  ///   {ids}     → `AND (<col> IN (...) OR <col> IS NULL)` — NULL-branch rows
  ///               (head-office / global data) stay visible under a scope.
  ({String filter, List<Variable> vars}) _buildAuthScopeFilter(
    Set<int>? allowedBranchIds, {
    String tableAlias = '',
  }) {
    if (allowedBranchIds == null) return (filter: '', vars: <Variable>[]);
    final col = tableAlias.isEmpty ? 'branch_id' : '$tableAlias.branch_id';
    if (allowedBranchIds.isEmpty) return (filter: ' AND 1 = 0', vars: <Variable>[]);
    final ph = allowedBranchIds.map((_) => '?').join(', ');
    return (
      filter: ' AND ($col IN ($ph) OR $col IS NULL)',
      vars: allowedBranchIds.map<Variable>((id) => Variable<int>(id)).toList(),
    );
  }

  /// Get total purchases for a date range
  ///
  /// Feature 014 / Issue 7 — was summing ALL purchase_invoices including
  /// soft-deleted rows. Mirror devices accumulated stale rows when a
  /// pull race re-inserted a soft-deleted invoice → mirror's "إجمالي
  /// المشتريات" reported a higher number than the server. The fix is
  /// the same `is_deleted = 0` clause that
  /// `SalesAnalyticsDao.getTotalSales` already uses on the sales side.
  Future<double> getTotalPurchases({
    DateTime? from,
    DateTime? to,
    List<int>? warehouseIds,
  }) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));

    String warehouseClause = '';
    if (warehouseIds != null) {
      warehouseClause = warehouseIds.isEmpty
          ? ' AND 1 = 0'
          : ' AND warehouse_id IN (${warehouseIds.join(',')})';
    }

    final result = await customSelect(
      'SELECT COALESCE(SUM(total), 0) as total '
      'FROM purchase_invoices '
      'WHERE invoice_date BETWEEN ? AND ? '
      'AND is_deleted = 0$warehouseClause',
      variables: [dateVar(from), dateVar(to)],
      readsFrom: {purchaseInvoices},
    ).getSingle();

    return result.data['total'] as double? ?? 0;
  }

  /// Get purchases by supplier
  Future<List<Map<String, dynamic>>> getPurchasesBySupplier({
    DateTime? from,
    DateTime? to,
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) async {
    from ??= DateTime.now().subtract(const Duration(days: 30));
    to ??= DateTime.now().add(const Duration(days: 1));
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'pi');

    final filters = StringBuffer();
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        filters.write(' AND 1 = 0');
      } else {
        filters.write(' AND pi.warehouse_id IN (${warehouseIds.join(',')})');
      }
    }
    if (costCenterId != null) {
      filters.write(' AND pi.cost_center_id = $costCenterId');
    }
    filters.write(az.filter);

    final results = await customSelect(
      '''
      SELECT p.id, p.name, SUM(pi.total) as total_purchases, COUNT(pi.id) as invoice_count
      FROM purchase_invoices pi
      JOIN parties p ON pi.supplier_id = p.id
      WHERE pi.invoice_date BETWEEN ? AND ?$filters
      GROUP BY p.id, p.name
      ORDER BY total_purchases DESC
      ''',
      variables: [dateVar(from), dateVar(to), ...az.vars],
      readsFrom: {purchaseInvoices, parties},
    ).get();

    return results
        .map(
          (row) => {
            'id': row.data['id'],
            'name': row.data['name'],
            'totalPurchases': row.data['total_purchases'],
            'invoiceCount': row.data['invoice_count'],
          },
        )
        .toList();
  }

  /// Get purchase invoices with supplier name for a date range
  Future<List<PurchaseInvoiceWithSupplier>> getPurchasesWithSupplierByDateRange(
    DateTime from,
    DateTime to, {
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) async {
    final query = select(purchaseInvoices).join([
      leftOuterJoin(parties, parties.id.equalsExp(purchaseInvoices.supplierId)),
    ]);
    query.where(
      purchaseInvoices.invoiceDate.isBetween(Variable(from), Variable(to)),
    );

    if (warehouseIds != null) {
      // Drift's isIn([]) already yields Constant(false) — empty list
      // correctly matches nothing instead of silently showing all rows.
      query.where(purchaseInvoices.warehouseId.isIn(warehouseIds));
    }

    // Spec 149 B12-4 (FIL-2): auth-level branch scope, mirrors B12-1's
    // _buildAuthScopeFilter contract (null = full access, {} = fail-closed,
    // {ids} = branch OR NULL-branch rows stay visible).
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where(purchaseInvoices.branchId.isIn(const <int>[]));
      } else {
        query.where(purchaseInvoices.branchId.isIn(allowedBranchIds) |
            purchaseInvoices.branchId.isNull());
      }
    }
    if (costCenterId != null) {
      query.where(purchaseInvoices.costCenterId.equals(costCenterId));
    }

    query.orderBy([OrderingTerm.desc(purchaseInvoices.createdAt)]);

    final rows = await query.get();
    return rows.map((row) {
      return PurchaseInvoiceWithSupplier(
        invoice: row.readTable(purchaseInvoices),
        supplierName: row.readTableOrNull(parties)?.name,
      );
    }).toList();
  }

  /// Get purchase report analytics for a date range (SQL-optimized, Phase 9.2)
  Future<PurchasesAnalytics> getPurchasesReportAnalytics(
    DateTime start,
    DateTime end, {
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) async {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day)
        .add(const Duration(days: 1));

    final filters = StringBuffer();
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        filters.write(' AND 1 = 0');
      } else {
        filters.write(' AND warehouse_id IN (${warehouseIds.join(',')})');
      }
    }
    if (costCenterId != null) {
      filters.write(' AND cost_center_id = $costCenterId');
    }
    // Spec 149 B12-5a: this method's existing filters are all plain string
    // interpolation (ints, injection-safe), not parameterized `?` — matching
    // that style here avoids introducing a positional-var mismatch risk.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        filters.write(' AND 1 = 0');
      } else {
        filters.write(
            ' AND (branch_id IN (${allowedBranchIds.join(',')}) OR branch_id IS NULL)');
      }
    }

    final result = await customSelect(
      '''
      SELECT
        COUNT(*)                as cnt,
        COALESCE(SUM(total), 0) as total_sum,
        COALESCE(SUM(paid),  0) as paid_sum
      FROM purchase_invoices
      WHERE invoice_date BETWEEN ? AND ?
        AND is_deleted = 0
        $filters
      ''',
      variables: [dateVar(normalizedStart), dateVar(normalizedEnd)],
      readsFrom: {purchaseInvoices},
    ).getSingle();

    final count = (result.data['cnt']       as num?)?.toInt()    ?? 0;
    final total = (result.data['total_sum'] as num?)?.toDouble() ?? 0.0;
    final paid  = (result.data['paid_sum']  as num?)?.toDouble() ?? 0.0;

    return PurchasesAnalytics(
      totalPurchases: total,
      totalOutstanding: total - paid,
      invoiceCount: count,
      averagePurchaseValue: count > 0 ? total / count : 0,
    );
  }

  /// Get purchase invoice items with product data
  Future<List<PurchaseInvoiceItemWithProduct>>
  getPurchaseInvoiceItemsWithProduct(int invoiceId) async {
    final query = select(purchaseInvoiceItems).join([
      innerJoin(
        products,
        products.id.equalsExp(purchaseInvoiceItems.productId),
      ),
    ])..where(purchaseInvoiceItems.invoiceId.equals(invoiceId));

    final rows = await query.get();
    return rows.map((row) {
      return PurchaseInvoiceItemWithProduct(
        item: row.readTable(purchaseInvoiceItems),
        product: row.readTable(products),
      );
    }).toList();
  }

}
