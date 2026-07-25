import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'branch_scope_provider.dart';
import 'repository_providers.dart';

/// Spec 136 (field 2026-06-11) — shared dashboard/analytics filter.
///
/// Per owner decision, the main dashboard ("لوحة التحكم") KPI cards follow the
/// SAME filter the analytics screen uses. The analytics screen writes its
/// branch / cost-center / period selection here; the dashboard cards read it.
/// `warehouseIds` is the branch resolved to its warehouses (the analytics
/// screen computes it via BranchWarehouseFilterBar, which needs a WidgetRef, so
/// it is threaded through here rather than re-resolved inside a provider).
class DashboardFilter {
  final int? branchId;
  final List<int>? warehouseIds;
  final int? costCenterId;
  final DateTime from;
  final DateTime to;

  const DashboardFilter({
    this.branchId,
    this.warehouseIds,
    this.costCenterId,
    required this.from,
    required this.to,
  });
}

class DashboardFilterNotifier extends Notifier<DashboardFilter> {
  @override
  DashboardFilter build() {
    // Default scope: today (calendar day), all branches the operator can see.
    // The analytics screen seeds the active branch on first open and pushes it
    // here, so a branch-restricted user's dashboard narrows as soon as they
    // visit analytics.
    final now = DateTime.now();
    return DashboardFilter(
      from: DateTime(now.year, now.month, now.day),
      to: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  void update({
    int? branchId,
    List<int>? warehouseIds,
    int? costCenterId,
    required DateTime from,
    required DateTime to,
  }) {
    state = DashboardFilter(
      branchId: branchId,
      warehouseIds: warehouseIds,
      costCenterId: costCenterId,
      from: from,
      to: to,
    );
  }
}

final dashboardFilterProvider =
    NotifierProvider<DashboardFilterNotifier, DashboardFilter>(
  DashboardFilterNotifier.new,
);

/// KPI bundle for the main dashboard, sourced from the GL income statement
/// (single source of truth) + sales analytics, scoped by [dashboardFilterProvider].
class DashboardKpi {
  final double revenue; // GL net revenue (ex-VAT, net of returns)
  final double netProfit; // GL net profit
  final int invoiceCount;

  /// البند 1 (متطلبات العميل 2026-07-25) — مكوّنات «صافي الإيراد» حتى يستطيع
  /// العميل تدقيق الرقم يدوياً.
  ///
  /// The complaint was that the figure could not be reconciled by hand. The
  /// premise that returns weren't deducted was wrong — they were. The real
  /// cause: the card shows an EX-VAT figure while the operator adds up
  /// tax-inclusive receipts, so the gap is exactly the net output VAT. Rather
  /// than change a correct number, expose its parts.
  final double salesReturns; // المردودات المخصومة أصلاً (بدون ضريبة)
  final double outputVatNet; // ضريبة المخرجات صافية من عكوسات المردودات
  final double netRevenueInclVat; // = revenue + outputVatNet

  const DashboardKpi({
    required this.revenue,
    required this.netProfit,
    required this.invoiceCount,
    this.salesReturns = 0,
    this.outputVatNet = 0,
    this.netRevenueInclVat = 0,
  });
}

final dashboardKpiProvider = FutureProvider.autoDispose<DashboardKpi>((ref) async {
  final f = ref.watch(dashboardFilterProvider);
  final repo = ref.watch(reportingRepositoryProvider);

  // Spec 149 B12-5b (FIL-2): the logged-in user's branch authorization scope.
  // null = full access (admin/financial-manager/mirror) → no restriction.
  // This is a SEPARATE, additional restriction on top of `f.branchId` above
  // (the user-facing dashboard filter) — enforced at the DAO so a branch-
  // restricted user can never see all-branch KPI totals regardless of what
  // they pick in the filter.
  final scope = await ref.watch(branchScopeProvider.future);
  final allowed = scope.hasFullAccess ? null : scope.allowedBranchIds;

  // Revenue + profit from the GL income statement — VAT handled correctly,
  // scoped by branch + cost-center + period.
  final income = await repo.getIncomeStatement(
    f.from,
    f.to,
    costCenterId: f.costCenterId,
    branchId: f.branchId,
    allowedBranchIds: allowed,
  );
  final revenue = (income['totalRevenue'] as num?)?.toDouble() ?? 0.0;
  final netProfit = (income['netProfit'] as num?)?.toDouble() ?? 0.0;

  // Invoice count from sales analytics (income statement has no count). Uses the
  // branch's warehouseIds threaded in from the analytics screen.
  final analytics = await repo.getSalesAnalytics(
    f.from,
    f.to,
    costCenterId: f.costCenterId,
    warehouseIds: f.warehouseIds,
    allowedBranchIds: allowed,
  );

  return DashboardKpi(
    revenue: revenue,
    netProfit: netProfit,
    invoiceCount: analytics.invoiceCount,
    salesReturns: (income['salesReturns'] as num?)?.toDouble() ?? 0.0,
    outputVatNet: (income['outputVatNet'] as num?)?.toDouble() ?? 0.0,
    netRevenueInclVat:
        (income['netRevenueInclVat'] as num?)?.toDouble() ?? 0.0,
  );
});
