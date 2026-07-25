import 'package:drift/drift.dart';
import '../database/database.dart';
import '../../domain/repositories/reporting_repository.dart';

class ReportingRepositoryImpl implements IReportingRepository {
  final AppDatabase _db;

  ReportingRepositoryImpl(this._db);

  @override
  Future<List<DailySalesSummaryRow>> getDailySalesForRange({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) => _db.getDailySalesForRange(
    from: from,
    to: to,
    costCenterId: costCenterId,
    warehouseIds: warehouseIds,
    allowedBranchIds: allowedBranchIds,
  );

  @override
  Future<List<TopSellingProductRow>> getTopSellingProducts({
    required int limit,
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) => _db.getTopSellingProducts(
    limit: limit,
    from: from,
    to: to,
    costCenterId: costCenterId,
    warehouseIds: warehouseIds,
    allowedBranchIds: allowedBranchIds,
  );

  @override
  Future<List<PaymentMethodStatRow>> getPaymentMethodStats({
    int? costCenterId,
    DateTime? from,
    DateTime? to,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getPaymentMethodStats(
        costCenterId: costCenterId,
        from: from,
        to: to,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<double> getTotalSales({required DateTime from, required DateTime to}) =>
      _db.getTotalSales(from: from, to: to);

  @override
  Future<int> getSalesCount({required DateTime from, required DateTime to}) =>
      _db.getSalesCount(from: from, to: to);

  @override
  Future<int> getNewCustomersCount({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) => _db.getNewCustomersCount(
    from: from,
    to: to,
    costCenterId: costCenterId,
    allowedBranchIds: allowedBranchIds,
  );

  @override
  Future<SalesAnalytics> getSalesAnalytics(
    DateTime from,
    DateTime to, {
    int? userId,
    int? costCenterId,
    List<int>? warehouseIds,
    String? paymentMethod,
    String? saleType,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getSalesAnalytics(
        from,
        to,
        userId: userId,
        costCenterId: costCenterId,
        warehouseIds: warehouseIds,
        paymentMethod: paymentMethod,
        saleType: saleType,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<Product>> getLowStockProducts() => _db.getLowStockProducts();

  @override
  Future<List<ProductBatch>> getExpiredBatches() => _db.getExpiredBatches();

  @override
  Future<List<ProductBatch>> getExpiringBatches(int days) => _db.getExpiringBatches(days);

  @override
  Future<List<SalesInvoiceData>> getSalesByDateRange(
    DateTime start,
    DateTime end, {
    int? userId,
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getSalesByDateRange(
        start,
        end,
        userId: userId,
        warehouseIds: warehouseIds,
        costCenterId: costCenterId,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId) => 
      _db.getSalesInvoiceItems(invoiceId);

  // ── Purchase Reporting ──────────────────────────────────────────────

  @override
  Future<PurchasesAnalytics> getPurchasesReportAnalytics(
    DateTime from,
    DateTime to, {
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getPurchasesReportAnalytics(
        from, to,
        warehouseIds: warehouseIds,
        costCenterId: costCenterId,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<PurchaseInvoiceWithSupplier>> getPurchasesWithSupplierByDateRange(
    DateTime start,
    DateTime end, {
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) => _db.getPurchasesWithSupplierByDateRange(
    start, end,
    warehouseIds: warehouseIds,
    costCenterId: costCenterId,
    allowedBranchIds: allowedBranchIds,
  );

  @override
  Future<List<Map<String, dynamic>>> getPurchasesBySupplier({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) => _db.getPurchasesBySupplier(
    from: from, to: to,
    warehouseIds: warehouseIds,
    costCenterId: costCenterId,
    allowedBranchIds: allowedBranchIds,
  );

  // ── Inventory Reporting ─────────────────────────────────────────────

  @override
  Future<InventoryAnalytics> getInventoryReportAnalytics({
    List<int>? warehouseIds,
  }) =>
      _db.getInventoryReportAnalytics(warehouseIds: warehouseIds);

  // ── Treasury Reporting ──────────────────────────────────────────────

  @override
  Future<TreasuryAnalytics> getTreasuryReportAnalytics(
    DateTime start,
    DateTime end, {
    int? costCenterId,
    int? safeId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getTreasuryReportAnalytics(
        start, end,
        safeId: safeId,
        costCenterId: costCenterId,
        safeIds: safeIds,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<SafeTransactionData>> getTransactionsByDateRange(
    DateTime start,
    DateTime end, {
    int? userId,
    int? costCenterId,
    int? safeId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  }) async {
    final query = _db.select(_db.safeTransactions);
    query.where(
      (t) => t.createdAt.isBetween(
        Variable(start),
        Variable(end.add(const Duration(days: 1))),
      ),
    );
    if (userId != null) {
      query.where((t) => t.userId.equals(userId));
    }
    if (safeId != null) {
      query.where((t) => t.safeId.equals(safeId));
    }
    // Branch-level safe filtering
    if (safeIds != null && safeIds.isNotEmpty) {
      query.where((t) => t.safeId.isIn(safeIds));
    }
    if (costCenterId != null) {
      // Filter by safes linked to this cost center
      final safeIdsQuery = _db.selectOnly(_db.safes)
        ..addColumns([_db.safes.id])
        ..where(_db.safes.costCenterId.equals(costCenterId));
      query.where((t) => t.safeId.isInQuery(safeIdsQuery));
    }
    // Spec 151 D-01: authoritative branch-scope cap. This is the query the
    // treasury report screen actually reads (it does NOT delegate to the DAO
    // method), so the guard MUST live here too. Same semantics as the DAO:
    // null = no cap; {} = fail-closed; {ids} = those branches OR NULL-branch
    // shared safes. A branch-scoped user never sees another branch's voucher
    // rows even if safeIds is null on first load.
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where((t) => const Constant(false)); // no branch access → no rows
      } else {
        final scopedSafes = _db.selectOnly(_db.safes)
          ..addColumns([_db.safes.id])
          ..where(_db.safes.branchId.isIn(allowedBranchIds) |
              _db.safes.branchId.isNull());
        query.where((t) => t.safeId.isInQuery(scopedSafes));
      }
    }
    query.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  @override
  Future<List<UserTreasurySummary>> getPerUserTreasurySummary(
    DateTime from,
    DateTime to, {
    int? safeId,
    int? costCenterId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getPerUserTreasurySummary(from, to,
          safeId: safeId,
          costCenterId: costCenterId,
          safeIds: safeIds,
          allowedBranchIds: allowedBranchIds);

  // ── Sales / Delivery Reporting ──────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> getDeliveryReport({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getDeliveryReport(
        from: from,
        to: to,
        warehouseIds: warehouseIds,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<TopProductRow>> getTopProductsReport({
    required DateTime from,
    required DateTime to,
    int limit = 10,
    bool orderByValue = true,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getTopProductsReport(
        from: from,
        to: to,
        limit: limit,
        orderByValue: orderByValue,
        warehouseIds: warehouseIds,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<Map<String, dynamic>> getTaxReport(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getTaxReport(
        from,
        to,
        costCenterId: costCenterId,
        warehouseIds: warehouseIds,
        branchId: branchId,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<Map<String, dynamic>>> getSalesTaxDetailByItem(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getSalesTaxDetailByItem(
        from,
        to,
        costCenterId: costCenterId,
        warehouseIds: warehouseIds,
        branchId: branchId,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<Map<String, dynamic>>> getSalesTaxByRate(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getSalesTaxByRate(
        from,
        to,
        costCenterId: costCenterId,
        warehouseIds: warehouseIds,
        branchId: branchId,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<ShiftReportDto>> getShiftsReportPaginated({
    int limit = 50,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    int? userId,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getShiftsReportPaginated(
        limit: limit,
        offset: offset,
        startDate: startDate,
        endDate: endDate,
        userId: userId,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<CategoryProfitRow>> getCategoryProfitReport({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
    int? costCenterId,
  }) =>
      _db.getCategoryProfitReport(
        from: from,
        to: to,
        warehouseIds: warehouseIds,
        allowedBranchIds: allowedBranchIds,
        costCenterId: costCenterId,
      );

  /// Resolve a `regionId` filter to the list of active branches in that
  /// region. Returns `null` when no region filter is requested, an empty
  /// list when the region has no active branches (caller short-circuits to
  /// an empty result), or the list of branch ids otherwise.
  ///
  /// Why this exists: the previous implementation looped per-branch and
  /// merged results, but every per-branch query also includes
  /// `branch_id IS NULL` global entries (head-office depreciation, opening
  /// balances, etc.), so those rows were counted N times for an N-branch
  /// region. The DAO's `_buildBranchFilter` now accepts a list, so we just
  /// hand it the resolved ids and let SQLite do a single `IN (...)` pass.
  Future<List<int>?> _resolveRegionBranchIds(int? regionId, int? branchId) async {
    if (regionId == null || branchId != null) return null;
    final regionBranches = await _db.getBranchesByRegion(regionId);
    return regionBranches.map((b) => b.id).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getTrialBalance(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) async {
    final regionBranchIds = await _resolveRegionBranchIds(regionId, branchId);
    if (regionBranchIds != null && regionBranchIds.isEmpty) return [];
    return _db.getTrialBalance(
      from, to,
      costCenterId: costCenterId,
      branchId: branchId,
      branchIds: regionBranchIds,
      allowedBranchIds: allowedBranchIds,
    );
  }

  @override
  Future<Map<String, dynamic>> getIncomeStatement(DateTime from, DateTime to, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) async {
    final regionBranchIds = await _resolveRegionBranchIds(regionId, branchId);
    if (regionBranchIds != null && regionBranchIds.isEmpty) {
      return {
        'totalRevenue': 0.0, 'totalExpenses': 0.0, 'netProfit': 0.0,
        'totalCOGS': 0.0, 'grossProfit': 0.0, 'operatingProfit': 0.0,
        'totalDepreciation': 0.0,
        'revenueDetails': <Map<String, dynamic>>[],
        'expenseDetails': <Map<String, dynamic>>[],
        'cogsDetails': <Map<String, dynamic>>[],
        'depreciationDetails': <Map<String, dynamic>>[],
      };
    }
    return _db.getIncomeStatement(
      from, to,
      costCenterId: costCenterId,
      branchId: branchId,
      branchIds: regionBranchIds,
      allowedBranchIds: allowedBranchIds,
    );
  }

  @override
  Future<Map<String, dynamic>> getBalanceSheet(DateTime to, {int? costCenterId, int? branchId, int? regionId, Set<int>? allowedBranchIds}) async {
    final regionBranchIds = await _resolveRegionBranchIds(regionId, branchId);
    if (regionBranchIds != null && regionBranchIds.isEmpty) {
      return {
        'totalAssets': 0.0, 'totalLiabilities': 0.0, 'totalEquity': 0.0,
        'isBalanced': true,
        'assetDetails': <Map<String, dynamic>>[],
        'liabilityDetails': <Map<String, dynamic>>[],
        'equityDetails': <Map<String, dynamic>>[],
      };
    }
    return _db.getBalanceSheet(
      to,
      costCenterId: costCenterId,
      branchId: branchId,
      branchIds: regionBranchIds,
      allowedBranchIds: allowedBranchIds,
    );
  }

  @override
  Future<List<SalesByCategoryRow>> getSalesByCategory({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getSalesByCategory(
        from: from,
        to: to,
        warehouseIds: warehouseIds,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<SalesBySaleTypeRow>> getSalesBySaleType({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getSalesBySaleType(
        from: from,
        to: to,
        warehouseIds: warehouseIds,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<List<SalesInvoiceSummaryRow>> getSalesInvoicesBySaleType({
    required String saleType,
    required DateTime from,
    required DateTime to,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getSalesInvoicesBySaleType(
        saleType: saleType,
        from: from,
        to: to,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<ReturnsAnalyticsSummary> getSalesReturnsAnalytics({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) => _db.getSalesReturnsAnalytics(from: from, to: to, costCenterId: costCenterId, warehouseIds: warehouseIds, allowedBranchIds: allowedBranchIds);

  @override
  Future<ReturnsAnalyticsSummary> getPurchaseReturnsAnalytics({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) => _db.getPurchaseReturnsAnalytics(from: from, to: to, costCenterId: costCenterId, warehouseIds: warehouseIds, allowedBranchIds: allowedBranchIds);

  @override
  Stream<List<UserWithRole>> watchAllUsers() => _db.watchAllUsers();

  @override
  Future<List<CustomReportData>> getCustomReports() => _db.getCustomReports();

  @override
  Future<int> createCustomReport({
    required String name,
    required String sourceEntity,
    required String columns,
  }) => _db.createCustomReport(
        name: name,
        sourceEntity: sourceEntity,
        columns: columns,
      );

  @override
  Future<void> deleteCustomReport(int id) => _db.deleteCustomReport(id);

  @override
  Future<List<Map<String, dynamic>>> executeReport(int reportId) =>
      _db.executeReport(reportId);

  @override
  List<Map<String, String>> getAvailableFields(String entity) =>
      _db.getAvailableFields(entity);
}
