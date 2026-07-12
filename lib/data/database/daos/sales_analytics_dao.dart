// ═══════════════════════════════════════════════════════════════════════════
// SALES ANALYTICS DAO — Reports and Analytics Queries
// ═══════════════════════════════════════════════════════════════════════════
//
// Extracted from SalesDao for maintainability (PIR C-03).
// Contains all sales reporting, analytics, and aggregation queries.

part of '../database.dart';

/// Extension for Sales reporting and analytics queries
extension SalesAnalyticsDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // COST CENTER UTILITIES (Shared with AccountingReportsDao)
  // ═══════════════════════════════════════════════════════════════════════

  /// Resolve a cost center ID to include itself and all descendant children.
  Future<List<int>> _resolveCostCenterIds(int? costCenterId) async {
    if (costCenterId == null) return [];
    final ids = <int>[costCenterId];
    Future<void> addChildren(int parentId) async {
      final children = await (select(costCenters)
            ..where((c) => c.parentId.equals(parentId))
            ..where((c) => c.isActive.equals(true)))
          .get();
      for (final child in children) {
        ids.add(child.id);
        await addChildren(child.id);
      }
    }
    await addChildren(costCenterId);
    return ids;
  }

  /// Build SQL cost center filter for Sales tables
  Future<({String filter, List<Variable> vars})> _buildCostCenterFilter(int? costCenterId, {String tableAlias = 'inv'}) async {
    if (costCenterId == null) return (filter: '', vars: <Variable>[]);
    final ids = await _resolveCostCenterIds(costCenterId);
    final placeholders = ids.map((_) => '?').join(', ');
    return (
      filter: 'AND $tableAlias.cost_center_id IN ($placeholders)',
      vars: ids.map((id) => Variable<int>(id)).toList(),
    );
  }

  /// Spec 149 B12-5a — auth-scope branch filter for the aggregate analytics
  /// queries below (backend-only; screens are wired separately in B12-5b, so
  /// with no caller passing `allowedBranchIds` behaviour is unchanged).
  /// Mirrors B12-1's `_buildAuthScopeFilter` contract (see
  /// AccountingReportsDao / BranchScope in
  /// lib/data/providers/branch_scope_provider.dart):
  ///   null      → no filter (full access)
  ///   {}        → `AND 1 = 0` (fail-closed)
  ///   {ids}     → `AND (<col> IN (...) OR <col> IS NULL)` — NULL-branch rows
  ///               (head-office / global data) stay visible under a scope.
  /// `tableAlias` defaults to '' since some of these queries reference an
  /// unaliased `sales_invoices` table directly (bare `branch_id`).
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

  /// م-3 (Spec 153) — the ONE return exclusion every sales aggregate shares so
  /// the sales report, the category-profit report, and the sibling KPIs all
  /// agree that a new-shape POSITIVE-total return (`sale_type = 'return'`) is
  /// not a sale. This was the actual divergence: getSalesAnalytics (and the
  /// sibling KPIs) already carried this guard, but getCategoryProfitReport did
  /// not, so positive-total returns inflated category profit only.
  ///
  /// It deliberately does NOT fold in a `status` guard. Void/cancelled invoices
  /// are already dropped by each query's `is_deleted = 0` (a committed void sets
  /// is_deleted=true). Excluding `status='returned'` ORIGINALS would be wrong —
  /// they are real gross sales that the separate returns figure already nets
  /// out; dropping them would double-remove the value AND desync
  /// getSalesAnalytics from the invoice list, the return-rate denominator, and
  /// the sibling aggregates (Spec 136 card-vs-rows invariant). getCategoryProfit
  /// keeps its own pre-existing status guard for the transient client-void
  /// window; that narrow difference is by design.
  ///
  /// `tableAlias` prefixes the column (e.g. 'inv') for JOINed queries; ''
  /// leaves it bare for single-table aggregates. Leading space so it appends
  /// directly after another predicate.
  String _saleReturnExclusion([String tableAlias = '']) {
    final p = tableAlias.isEmpty ? '' : '$tableAlias.';
    return " AND (${p}sale_type IS NULL OR ${p}sale_type != 'return')";
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AGGREGATE QUERIES
  // ═══════════════════════════════════════════════════════════════════════

  /// Get total sales for a date range
  Future<double> getTotalSales({DateTime? from, DateTime? to}) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));

    final result = await customSelect(
      'SELECT COALESCE(SUM(CASE WHEN sale_type = \'return\' THEN -total ELSE total END), 0) as total FROM sales_invoices WHERE invoice_date BETWEEN ? AND ? AND is_deleted = 0',
      variables: [dateVar(from), dateVar(to)],
      readsFrom: {salesInvoices},
    ).getSingle();

    final value = result.data['total'];
    return (value is num) ? value.toDouble() : 0.0;
  }

  /// Get sales count for a date range
  Future<int> getSalesCount({DateTime? from, DateTime? to}) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));

    final result = await customSelect(
      'SELECT COUNT(*) as count FROM sales_invoices WHERE invoice_date BETWEEN ? AND ? AND is_deleted = 0 AND sale_type != \'return\'',
      variables: [dateVar(from), dateVar(to)],
      readsFrom: {salesInvoices},
    ).getSingle();

    final value = result.data['count'];
    return (value is num) ? value.toInt() : 0;
  }

  /// Get total tax collected for a date range
  Future<double> getTotalTax({DateTime? from, DateTime? to}) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));

    final result = await customSelect(
      'SELECT COALESCE(SUM(CASE WHEN sale_type = \'return\' THEN -tax ELSE tax END), 0) as total FROM sales_invoices WHERE invoice_date BETWEEN ? AND ? AND is_deleted = 0',
      variables: [dateVar(from), dateVar(to)],
      readsFrom: {salesInvoices},
    ).getSingle();

    final value = result.data['total'];
    return (value is num) ? value.toDouble() : 0.0;
  }

  /// Get total delivery fees for a date range
  Future<double> getTotalDeliveryFees({DateTime? from, DateTime? to}) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));

    final result = await customSelect(
      'SELECT COALESCE(SUM(CASE WHEN sale_type = \'return\' THEN -delivery_fee ELSE delivery_fee END), 0) as total FROM sales_invoices WHERE invoice_date BETWEEN ? AND ? AND is_deleted = 0',
      variables: [dateVar(from), dateVar(to)],
      readsFrom: {salesInvoices},
    ).getSingle();

    final value = result.data['total'];
    return (value is num) ? value.toDouble() : 0.0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRODUCT ANALYTICS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get top selling products with optional date range
  /// P2-03: Returns typed [TopSellingProductRow] instead of Map.
  Future<List<TopSellingProductRow>> getTopSellingProducts({
    int limit = 10,
    DateTime? from,
    DateTime? to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));
    final cc = await _buildCostCenterFilter(costCenterId);
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'inv');

    String warehouseFilter = '';
    final vars = <Variable>[dateVar(from), dateVar(to)];
    vars.addAll(cc.vars);
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        warehouseFilter = 'AND 1 = 0';
      } else {
        warehouseFilter = 'AND inv.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }
    vars.addAll(az.vars);
    vars.add(Variable(limit));

    final results = await customSelect(
      '''
      SELECT p.id, p.name, SUM(si.quantity) as total_qty, SUM(si.total) as total_sales
      FROM sales_invoice_items si
      JOIN products p ON si.product_id = p.id
      JOIN sales_invoices inv ON si.invoice_id = inv.id
      WHERE inv.invoice_date BETWEEN ? AND ?
        AND inv.is_deleted = 0
        AND (inv.sale_type IS NULL OR inv.sale_type != 'return')
        ${cc.filter} $warehouseFilter${az.filter}
      GROUP BY p.id, p.name
      ORDER BY total_sales DESC
      LIMIT ?
      ''',
      variables: vars,
      readsFrom: {salesInvoiceItems, products, salesInvoices},
    ).get();

    return results
        .map(
          (row) => TopSellingProductRow(
            id: (row.data['id'] as num?)?.toInt() ?? 0,
            name: row.data['name'] as String? ?? '',
            totalQuantity: (row.data['total_qty'] as num?)?.toDouble() ?? 0.0,
            totalSales: (row.data['total_sales'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  /// Get profit report grouped by category
  /// P2-03: Returns typed [CategoryProfitRow] instead of Map.
  Future<List<CategoryProfitRow>> getCategoryProfitReport({
    DateTime? from,
    DateTime? to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'inv');

    String warehouseFilter = '';
    final vars = <Variable>[dateVar(from), dateVar(to)];
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        warehouseFilter = 'AND 1 = 0';
      } else {
        warehouseFilter = 'AND inv.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }
    vars.addAll(az.vars);

    final results = await customSelect(
      '''
      SELECT
          c.id as category_id,
          COALESCE(c.name, 'بدون تصنيف') as category_name,
          SUM(si.total) as total_sales,
          SUM(si.quantity * si.quantity_in_base * si.cost_price) as total_cost
      FROM sales_invoice_items si
      JOIN products p ON si.product_id = p.id
      LEFT JOIN categories c ON p.category_id = c.id
      JOIN sales_invoices inv ON si.invoice_id = inv.id
      WHERE inv.invoice_date BETWEEN ? AND ? AND inv.is_deleted = 0 AND inv.status NOT IN ('returned', 'cancelled', 'voided')${_saleReturnExclusion('inv')} $warehouseFilter${az.filter}
      GROUP BY c.id, c.name
      ORDER BY total_sales DESC
      ''',
      variables: vars,
      readsFrom: {salesInvoiceItems, products, categories, salesInvoices},
    ).get();

    return results.map((row) {
      final sales = (row.data['total_sales'] as num?)?.toDouble() ?? 0.0;
      final cost = (row.data['total_cost'] as num?)?.toDouble() ?? 0.0;
      return CategoryProfitRow(
        categoryId: (row.data['category_id'] as num?)?.toInt(),
        categoryName: row.data['category_name'] as String? ?? 'بدون تصنيف',
        totalSales: sales,
        totalCost: cost,
        profit: sales - cost,
        margin: sales > 0 ? ((sales - cost) / sales) * 100 : 0.0,
      );
    }).toList();
  }

  /// Get top products by volume or value
  /// P2-03: Returns typed [TopProductRow] instead of Map.
  Future<List<TopProductRow>> getTopProductsReport({
    DateTime? from,
    DateTime? to,
    int limit = 10,
    bool orderByValue = true,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    from ??= DateTime.now().subtract(const Duration(days: 30));
    to ??= DateTime.now().add(const Duration(days: 1));

    final sortColumn = orderByValue ? 'total_value' : 'total_qty';
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'inv');

    String warehouseFilter = '';
    final vars = <Variable>[dateVar(from), dateVar(to)];
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        warehouseFilter = 'AND 1 = 0';
      } else {
        warehouseFilter = 'AND inv.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }
    vars.addAll(az.vars);
    vars.add(Variable(limit));

    final results = await customSelect(
      '''
      SELECT
          p.id,
          p.name,
          SUM(si.quantity) as total_qty,
          SUM(si.total) as total_value
      FROM sales_invoice_items si
      JOIN products p ON si.product_id = p.id
      JOIN sales_invoices inv ON si.invoice_id = inv.id
      WHERE inv.invoice_date BETWEEN ? AND ? $warehouseFilter${az.filter}
      GROUP BY p.id, p.name
      ORDER BY $sortColumn DESC
      LIMIT ?
      ''',
      variables: vars,
      readsFrom: {salesInvoiceItems, products, salesInvoices},
    ).get();

    return results
        .map(
          (row) => TopProductRow(
            id: (row.data['id'] as num?)?.toInt() ?? 0,
            name: row.data['name'] as String? ?? '',
            totalQty: (row.data['total_qty'] as num?)?.toDouble() ?? 0.0,
            totalValue: (row.data['total_value'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DAILY SALES
  // ═══════════════════════════════════════════════════════════════════════

  /// Get daily sales summary for the last N days.
  /// P2-03: Returns typed [DailySalesSummaryRow] instead of Map.
  ///
  /// D-PERF-3 (A10): delegates to [getDailySalesForRange] — the single source
  /// of truth — so it inherits the is_deleted and return-invoice guards. The
  /// old hand-rolled query (and the byte-identical dead `getDailySalesSimple`)
  /// counted soft-deleted and return invoices, inflating the daily totals.
  Future<List<DailySalesSummaryRow>> getDailySalesSummary(int days) {
    final end = DateTime.now();
    return getDailySalesForRange(
        from: end.subtract(Duration(days: days)), to: end);
  }

  /// Optimized daily sales for a specific date range (PIR PER-01)
  /// P2-03: Returns typed [DailySalesSummaryRow] instead of Map.
  Future<List<DailySalesSummaryRow>> getDailySalesForRange({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    final cc = await _buildCostCenterFilter(costCenterId, tableAlias: 'sales_invoices');
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'sales_invoices');

    String whFilter = '';
    final whVars = <Variable>[];
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        whFilter = 'AND 1 = 0';
      } else {
        whFilter = 'AND sales_invoices.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        whVars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }

    final dateExpr = isPostgres
        ? "to_char(to_timestamp(invoice_date), 'YYYY-MM-DD')"
        : "date(invoice_date, 'unixepoch', 'localtime')";
    final results = await customSelect(
      '''
      SELECT $dateExpr as sale_date, SUM(total) as daily_total
      FROM sales_invoices
      WHERE invoice_date BETWEEN ? AND ?
        AND is_deleted = 0
        AND (sale_type IS NULL OR sale_type != 'return')
        ${cc.filter} $whFilter${az.filter}
      GROUP BY sale_date
      ORDER BY sale_date ASC
      ''',
      variables: [dateVar(from), dateVar(to), ...cc.vars, ...whVars, ...az.vars],
      readsFrom: {salesInvoices},
    ).get();

    return results
        .map(
          (row) => DailySalesSummaryRow(
            date: row.data['sale_date'] as String? ?? '',
            total: (row.data['daily_total'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PAYMENT & CATEGORY ANALYTICS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get payment method statistics
  /// P2-03: Returns typed [PaymentMethodStatRow] instead of Map.
  Future<List<PaymentMethodStatRow>> getPaymentMethodStats({
    DateTime? from,
    DateTime? to,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));
    final cc = await _buildCostCenterFilter(costCenterId, tableAlias: 'sales_invoices');
    final az = _buildAuthScopeFilter(allowedBranchIds);

    final results = await customSelect(
      '''
      SELECT payment_method, COUNT(*) as count, SUM(total) as total_amount
      FROM sales_invoices
      WHERE invoice_date BETWEEN ? AND ?
        AND is_deleted = 0
        AND (sale_type IS NULL OR sale_type != 'return')
        ${cc.filter}${az.filter}
      GROUP BY payment_method
      ''',
      variables: [dateVar(from), dateVar(to), ...cc.vars, ...az.vars],
      readsFrom: {salesInvoices},
    ).get();

    return results
        .map(
          (row) => PaymentMethodStatRow(
            method: row.data['payment_method'] as String? ?? '',
            count: (row.data['count'] as num?)?.toInt() ?? 0,
            total: (row.data['total_amount'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  /// Get new customers count (unique customers in period)
  Future<int> getNewCustomersCount({
    DateTime? from,
    DateTime? to,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));
    final cc = await _buildCostCenterFilter(costCenterId, tableAlias: 'sales_invoices');
    final az = _buildAuthScopeFilter(allowedBranchIds);

    final result = await customSelect(
      'SELECT COUNT(DISTINCT customer_id) as count FROM sales_invoices WHERE customer_id IS NOT NULL AND invoice_date BETWEEN ? AND ? AND is_deleted = 0 ${cc.filter}${az.filter}',
      variables: [dateVar(from), dateVar(to), ...cc.vars, ...az.vars],
      readsFrom: {salesInvoices},
    ).getSingle();

    final value = result.data['count'];
    return (value is num) ? value.toInt() : 0;
  }

  /// Get sales items grouped by product category
  /// P2-03: Returns typed [SalesByCategoryRow] instead of Map.
  Future<List<SalesByCategoryRow>> getSalesByCategory({
    DateTime? from,
    DateTime? to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'inv');

    String warehouseFilter = '';
    final vars = <Variable>[dateVar(from), dateVar(to)];
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        warehouseFilter = 'AND 1 = 0';
      } else {
        warehouseFilter = 'AND inv.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }
    vars.addAll(az.vars);

    final results = await customSelect(
      '''
      SELECT c.name as category_name, SUM(si.quantity) as total_qty, SUM(si.total) as total_amount
      FROM sales_invoice_items si
      JOIN products p ON si.product_id = p.id
      LEFT JOIN categories c ON p.category_id = c.id
      JOIN sales_invoices inv ON si.invoice_id = inv.id
      WHERE inv.invoice_date BETWEEN ? AND ? $warehouseFilter${az.filter}
      GROUP BY c.name
      ORDER BY total_amount DESC
      ''',
      variables: vars,
      readsFrom: {salesInvoiceItems, products, categories, salesInvoices},
    ).get();

    return results
        .map(
          (row) => SalesByCategoryRow(
            category: row.data['category_name'] as String? ?? 'غير مصنف',
            quantity: (row.data['total_qty'] as num?)?.toDouble() ?? 0.0,
            total: (row.data['total_amount'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  /// Get sales grouped by Sale Type (Price Level Classification)
  /// P2-03: Returns typed [SalesBySaleTypeRow] instead of Map.
  Future<List<SalesBySaleTypeRow>> getSalesBySaleType({
    DateTime? from,
    DateTime? to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));
    final az = _buildAuthScopeFilter(allowedBranchIds);

    String warehouseFilter = '';
    final vars = <Variable>[dateVar(from), dateVar(to)];
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        warehouseFilter = 'AND 1 = 0';
      } else {
        warehouseFilter = 'AND warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        vars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }
    vars.addAll(az.vars);

    final results = await customSelect(
      '''
      SELECT sale_type, COUNT(*) as count, SUM(total) as total_amount
      FROM sales_invoices
      WHERE invoice_date BETWEEN ? AND ? AND is_deleted = 0 $warehouseFilter${az.filter}
      GROUP BY sale_type
      ''',
      variables: vars,
      readsFrom: {salesInvoices},
    ).get();

    return results
        .map(
          (row) => SalesBySaleTypeRow(
            type: row.data['sale_type'] as String? ?? 'default',
            count: (row.data['count'] as num?)?.toInt() ?? 0,
            total: (row.data['total_amount'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  /// Get individual invoices filtered by a specific sale type
  /// P2-03: Returns typed [SalesInvoiceSummaryRow] instead of Map.
  Future<List<SalesInvoiceSummaryRow>> getSalesInvoicesBySaleType({
    required String saleType,
    DateTime? from,
    DateTime? to,
    Set<int>? allowedBranchIds,
  }) async {
    from ??= DateTime(2020);
    to ??= DateTime.now().add(const Duration(days: 1));
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 's');

    final results = await customSelect(
      '''
      SELECT
        s.id, s.invoice_number, s.invoice_date, s.total, s.paid,
        s.cash_paid, s.bank_paid, s.click_paid, s.payment_method,
        s.sale_type, s.discount, s.tax, s.delivery_fee,
        p.name as customer_name
      FROM sales_invoices s
      LEFT JOIN parties p ON s.customer_id = p.id
      WHERE s.sale_type = ? AND s.invoice_date BETWEEN ? AND ? AND s.is_deleted = 0${az.filter}
      ORDER BY s.invoice_date DESC
      ''',
      variables: [Variable(saleType), dateVar(from), dateVar(to), ...az.vars],
      readsFrom: {salesInvoices, parties},
    ).get();

    return results.map((row) => SalesInvoiceSummaryRow(
      id: (row.data['id'] as num?)?.toInt() ?? 0,
      invoiceNumber: row.data['invoice_number'] as String? ?? '',
      invoiceDate: row.data['invoice_date'],
      total: (row.data['total'] as num?)?.toDouble() ?? 0.0,
      paid: (row.data['paid'] as num?)?.toDouble() ?? 0.0,
      cashPaid: (row.data['cash_paid'] as num?)?.toDouble() ?? 0.0,
      bankPaid: (row.data['bank_paid'] as num?)?.toDouble() ?? 0.0,
      clickPaid: (row.data['click_paid'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: row.data['payment_method'] as String? ?? 'cash',
      saleType: row.data['sale_type'] as String? ?? 'default',
      discount: (row.data['discount'] as num?)?.toDouble() ?? 0.0,
      tax: (row.data['tax'] as num?)?.toDouble() ?? 0.0,
      deliveryFee: (row.data['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      customerName: row.data['customer_name'] as String?,
    )).toList();
  }

  /// Get daily sales for a specific date (Legacy Compatibility)
  Future<List<SalesInvoiceData>> getDailySales(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(salesInvoices)
          ..where(
            (s) => s.invoiceDate.isBetween(
              Variable(startOfDay),
              Variable(endOfDay),
            ),
          )
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .get();
  }

  /// Get daily sales with items for a simplified view
  /// P2-03: Returns typed [DailySalesSummaryRow] — alias for getDailySalesSummary.
  Future<List<DailySalesSummaryRow>> getDailySalesHistory(int days) =>
      getDailySalesSummary(days);

  // ═══════════════════════════════════════════════════════════════════════
  // SALES ANALYTICS AGGREGATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Get sales report analytics for a date range (SQL-optimized, Phase 9.2)
  Future<SalesAnalytics> getSalesAnalytics(
    DateTime start,
    DateTime end, {
    int? userId,
    int? costCenterId,
    List<int>? warehouseIds,
    String? paymentMethod,
    String? saleType,
    Set<int>? allowedBranchIds,
  }) async {
    final cc = await _buildCostCenterFilter(costCenterId);
    final ccFilter = cc.filter;
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'inv');
    final azFilter = az.filter;
    // Note: variables must be ordered carefully
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day)
        .add(const Duration(days: 1));

    // Build warehouse filter.
    // Spec 136 (field 2026-06-09): distinguish "no warehouse filter" (null →
    // all warehouses) from "a region/branch was picked but resolves to NO
    // warehouse" (non-null but empty → match nothing). Previously an empty
    // list silently skipped the filter, so the KPI cards showed company-wide
    // totals while the invoice list — which filters region warehouses
    // client-side — showed nothing. Now both agree.
    String whFilter = '';
    final whVars = <Variable>[];
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        whFilter = 'AND 1 = 0';
      } else {
        whFilter = 'AND inv.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        whVars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }

    // Spec 136 (field 2026-06-09): payment-method + sale-type filters were
    // applied ONLY to the invoice list (client-side in the screen), never to
    // these KPI aggregates — so picking "نقدي" showed cash-only rows under a
    // card that still summed EVERY payment method. Apply the SAME grouping the
    // screen uses for the list (bank_group = card/transfer/bank,
    // multiple = multiple/mixed) so the cards match the rows below them.
    String pmFilter = '';
    final pmVars = <Variable>[];
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      switch (paymentMethod) {
        case 'bank_group':
          pmFilter = "AND inv.payment_method IN ('card', 'transfer', 'bank')";
        case 'multiple':
          pmFilter = "AND inv.payment_method IN ('multiple', 'mixed')";
        default:
          pmFilter = 'AND inv.payment_method = ?';
          pmVars.add(Variable<String>(paymentMethod));
      }
    }
    String stFilter = '';
    final stVars = <Variable>[];
    if (saleType != null && saleType.isNotEmpty) {
      stFilter = 'AND inv.sale_type = ?';
      stVars.add(Variable<String>(saleType));
    }

    final variables = <Variable>[
      dateVar(normalizedStart),
      dateVar(normalizedEnd),
      if (userId != null) Variable(userId),
      ...cc.vars,
      ...whVars,
      ...pmVars,
      ...stVars,
      ...az.vars,
    ];

    final userClause = userId != null ? 'AND user_id = ?' : '';

    // Two guards — both important:
    //   • is_deleted = 0 keeps soft-deleted invoices out of analytics
    //     so the dashboard doesn't show revenue/COGS for cancelled rows
    //     that the rest of the system has already reversed.
    //   • sale_type != 'return' keeps refund invoices out of *gross*
    //     sales. New-shape returns are stored with POSITIVE totals and
    //     saleType='return', so a plain SUM(total) would inflate sales
    //     and the screen ends up subtracting the same value twice (once
    //     here, once via getSalesReturnsAnalytics). The screen now
    //     receives only the regular-sales total and subtracts returns
    //     itself, which is the standard accounting view.
    final result = await customSelect(
      '''
      SELECT
        COUNT(*) as cnt,
        COALESCE(SUM(total),    0) as total_sum,
        COALESCE(SUM(discount), 0) as discount_sum,
        COALESCE(SUM(tax),      0) as tax_sum
      FROM sales_invoices inv
      WHERE invoice_date BETWEEN ? AND ?
        AND is_deleted = 0${_saleReturnExclusion()}
        $userClause $ccFilter $whFilter $pmFilter $stFilter$azFilter
      ''',
      variables: variables,
      readsFrom: {salesInvoices},
    ).getSingle();

    final count   = (result.data['cnt']          as num?)?.toInt()    ?? 0;
    final total   = (result.data['total_sum']    as num?)?.toDouble() ?? 0.0;
    final disc    = (result.data['discount_sum'] as num?)?.toDouble() ?? 0.0;
    final tax     = (result.data['tax_sum']      as num?)?.toDouble() ?? 0.0;

    // COGS: exclude deleted invoices AND return invoices (stock and
    // COGS impact of the return is captured separately via the purchase-
    // returns / stock-movements path). Mirroring the regular-sales guard
    // keeps gross profit consistent.
    final cogsResult = await customSelect(
      '''
      SELECT COALESCE(SUM(si.quantity * si.quantity_in_base * si.cost_price), 0) as total_cogs
      FROM sales_invoice_items si
      JOIN sales_invoices inv ON si.invoice_id = inv.id
      WHERE inv.invoice_date BETWEEN ? AND ?
        AND inv.is_deleted = 0${_saleReturnExclusion('inv')}
        $userClause $ccFilter $whFilter $pmFilter $stFilter$azFilter
      ''',
      variables: variables,
      readsFrom: {salesInvoiceItems, salesInvoices},
    ).getSingle();

    final cogs = (cogsResult.data['total_cogs'] as num?)?.toDouble() ?? 0.0;
    final netRevenue  = total - disc;             // الإيراد الصافي
    final grossProfit = netRevenue - cogs;         // الربح الإجمالي الحقيقي
    final netProfit   = grossProfit - tax;          // صافي الربح
    final avg         = count > 0 ? total / count : 0.0;

    return SalesAnalytics(
      totalSales: total,
      totalGrossProfit: grossProfit,
      totalNetProfit: netProfit,
      totalProfit: netProfit,
      salesCount: count,
      invoiceCount: count,
      averageSaleValue: avg,
      averageInvoiceValue: avg,
      totalDiscount: disc,
      totalTax: tax,
      totalCOGS: cogs,
      totalNetRevenue: netRevenue,
    );
  }

  /// Alias for backward compatibility
  Future<SalesAnalytics> getSalesReportAnalytics(
    DateTime start,
    DateTime end,
  ) => getSalesAnalytics(start, end);

  // ═══════════════════════════════════════════════════════════════════════
  // RETURNS ANALYTICS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get sales returns summary for a date range
  /// P2-03: Returns typed [ReturnsAnalyticsSummary] instead of Map.
  Future<ReturnsAnalyticsSummary> getSalesReturnsAnalytics({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    final cc = costCenterId != null
        ? await _buildCostCenterFilter(costCenterId, tableAlias: 'inv')
        : (filter: '', vars: <Variable>[]);

    String whFilter = '';
    final whVars = <Variable>[];
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        whFilter = 'AND 1 = 0';
      } else {
        whFilter = 'AND inv.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        whVars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }

    // Spec 151 D-02 — branch-scope the refund total. safe_transactions has no
    // branch_id column, but its `safe_id` is NOT NULL and `safes` carries the
    // branch, so branch IS reachable via safe_transactions.safe_id →
    // safes.branch_id. When a scope is supplied, INNER JOIN safes and apply the
    // standard auth-scope filter (null = company-wide/userId=1; {} = fail-closed
    // via `AND 1 = 0`; {ids} = that branch set OR NULL-branch head-office safes).
    // Reuses _buildAuthScopeFilter so the semantics match the sales KPIs that
    // sit beside these cards on the analytics dashboard. When null, no safes
    // join is emitted → behaviour is byte-identical to before.
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 's');
    final safesJoin = allowedBranchIds != null
        ? 'JOIN safes s ON s.id = st.safe_id'
        : '';

    // Primary source: safe_transactions. This captures BOTH flows:
    //   1. POS returns → reference_type='sales_invoice', category='return'
    //   2. Returns-screen returns → reference_type='sales_return'
    // and uses the ACTUAL refund date (`created_at`) instead of the
    // original invoice's date. Multi-part refunds (cash + bank) count
    // as ONE return via DISTINCT reference_id; SUM(amount) gives the
    // correct sales value. AR-only credit returns are included via
    // `category='sales_return_balance'` memo rows.
    //
    // cc.filter / whFilter target `sales_invoices inv` so we join back
    // when those filters are active.
    final needsInvoiceJoin = cc.filter.isNotEmpty || whFilter.isNotEmpty;
    final joinSql = needsInvoiceJoin
        ? 'LEFT JOIN sales_invoices inv ON inv.id = st.reference_id'
        : '';
    final invoiceFilter = needsInvoiceJoin
        ? '${cc.filter} $whFilter'.trim()
        : '';

    final result = await customSelect(
      '''
      SELECT
        COUNT(DISTINCT st.reference_id) as return_count,
        COALESCE(SUM(st.amount), 0) as return_total
      FROM safe_transactions st
      $joinSql
      $safesJoin
      WHERE st.created_at BETWEEN ? AND ?
        AND (
          st.reference_type = 'sales_return'
          OR (st.reference_type = 'sales_invoice' AND st.category = 'return')
        )
        $invoiceFilter${az.filter}
      ''',
      variables: [
        dateVar(from),
        dateVar(to),
        if (needsInvoiceJoin) ...cc.vars,
        if (needsInvoiceJoin) ...whVars,
        ...az.vars,
      ],
      readsFrom: {
        safeTransactions,
        if (needsInvoiceJoin) salesInvoices,
        if (allowedBranchIds != null) safes,
      },
    ).getSingle();

    // Check stock_movements for returns (limited by warehouse if provided).
    // This legacy fallback only fires when the (now branch-scoped) primary
    // path above yields zero. stock_movements has no branch column, so it can't
    // be branch-scoped directly — but an EMPTY auth scope must never fall back
    // to company-wide legacy rows, so fail it closed here too (Spec 151 D-02).
    String smWhFilter = '';
    final smWhVars = <Variable>[];
    if (allowedBranchIds != null && allowedBranchIds.isEmpty) {
      smWhFilter = 'AND 1 = 0';
    } else if (allowedBranchIds != null && warehouseIds == null) {
      // D-02 nit: a branch-scoped user with NO warehouse filter can't attribute
      // legacy stock_movements (no branch column) to a branch — fail closed so
      // the fallback never leaks company-wide return rows.
      smWhFilter = 'AND 1 = 0';
    } else if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        smWhFilter = 'AND 1 = 0';
      } else {
        smWhFilter = 'AND sm.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        smWhVars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }

    final smResult = await customSelect(
      '''
      SELECT
        COUNT(DISTINCT sm.reference_id) as sm_return_count,
        COALESCE(SUM(sm.quantity * sm.unit_cost), 0) as sm_return_total
      FROM stock_movements sm
      WHERE sm.movement_type = 'return'
        AND sm.created_at BETWEEN ? AND ? $smWhFilter
      ''',
      variables: [dateVar(from), dateVar(to), ...smWhVars],
      readsFrom: {stockMovements},
    ).getSingle();

    final returnCount = (result.data['return_count'] as num?)?.toInt() ?? 0;
    final returnTotal = (result.data['return_total'] as num?)?.toDouble() ?? 0.0;
    final smReturnCount = (smResult.data['sm_return_count'] as num?)?.toInt() ?? 0;
    final smReturnTotal = (smResult.data['sm_return_total'] as num?)?.toDouble() ?? 0.0;

    return ReturnsAnalyticsSummary(
      count: returnCount > 0 ? returnCount : smReturnCount,
      total: returnTotal > 0 ? returnTotal : smReturnTotal,
    );
  }

  /// Get purchase returns summary for a date range.
  ///
  /// Primary source: `safe_transactions` with `reference_type='purchase_return'`
  /// (cash refunds + balance-adjustment memos for unpaid portions).
  /// This uses the actual refund date (`created_at`) rather than the
  /// original invoice's date, so returns processed in the current
  /// period show up even when the purchase invoice is months old.
  /// Multi-part refunds (cash + bank) are de-duplicated via
  /// `DISTINCT reference_id` and `SUM(amount)` reflects the true return
  /// value at selling-cost rather than inventory-cost.
  Future<ReturnsAnalyticsSummary> getPurchaseReturnsAnalytics({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    // Cost-center / warehouse filters target the original purchase
    // invoice (joined via reference_id) when those filters are active.
    final needsInvoiceJoin = costCenterId != null || warehouseIds != null;
    final joinSql = needsInvoiceJoin
        ? 'LEFT JOIN purchase_invoices pi ON pi.id = st.reference_id'
        : '';

    // Spec 151 D-02 — branch-scope via safe_transactions.safe_id → safes.branch_id
    // (safe_id is NOT NULL). null = company-wide/userId=1 (no join, unchanged);
    // {} = fail-closed; {ids} = that branch set OR NULL-branch head-office safes.
    final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 's');
    final safesJoin = allowedBranchIds != null
        ? 'JOIN safes s ON s.id = st.safe_id'
        : '';

    String invoiceFilter = '';
    final filterVars = <Variable>[];
    if (costCenterId != null) {
      invoiceFilter += ' AND pi.cost_center_id = ?';
      filterVars.add(Variable<int>(costCenterId));
    }
    if (warehouseIds != null) {
      if (warehouseIds.isEmpty) {
        invoiceFilter += ' AND 1 = 0';
      } else {
        invoiceFilter +=
            ' AND pi.warehouse_id IN (${warehouseIds.map((_) => '?').join(', ')})';
        filterVars.addAll(warehouseIds.map((id) => Variable<int>(id)));
      }
    }

    final result = await customSelect(
      '''
      SELECT
        COUNT(DISTINCT st.reference_id) as return_count,
        COALESCE(SUM(st.amount), 0) as return_total
      FROM safe_transactions st
      $joinSql
      $safesJoin
      WHERE st.created_at BETWEEN ? AND ?
        AND st.reference_type = 'purchase_return'
      $invoiceFilter${az.filter}
      ''',
      variables: [dateVar(from), dateVar(to), ...filterVars, ...az.vars],
      readsFrom: {
        safeTransactions,
        if (needsInvoiceJoin) purchaseInvoices,
        if (allowedBranchIds != null) safes,
      },
    ).getSingle();

    return ReturnsAnalyticsSummary(
      count: (result.data['return_count'] as num?)?.toInt() ?? 0,
      total: (result.data['return_total'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
