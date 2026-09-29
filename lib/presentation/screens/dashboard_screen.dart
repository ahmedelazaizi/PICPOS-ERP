import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/branch_chip.dart';
import '../../core/config/business_profile_provider.dart';
import '../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../../data/providers/dashboard_filter_provider.dart';
import '../widgets/permission_guard.dart';
import '../widgets/enhanced_components.dart';
import '../../core/constants/app_constants.dart';
import '../widgets/getting_started_checklist.dart';

/// Main dashboard with statistics and quick actions
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, this.onNavigate});

  final void Function(int)? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Spec 136 (field 2026-06-11): the sales / count / profit cards follow the
    // shared dashboard filter (branch + cost-center + period) the analytics
    // screen sets, and source revenue/profit from the GL income statement.
    final kpi = ref.watch(dashboardKpiProvider);
    // Spec 136 (review 2026-06-14): the KPI cards follow the shared analytics
    // filter, which persists across the session — so after the user picks a
    // month/year in analytics the cards show THAT period. Surface the active
    // period above the cards so the figure isn't misread as "today".
    final dashFilter = ref.watch(dashboardFilterProvider);
    // Recent-sales list below still streams today's invoices (it's a live feed,
    // not a filtered KPI).
    final todaySales = ref.watch(todaySalesProvider);
    // Fix 2 (spec 150, BUG-6): branch-scoped by the filter (unlike
    // totalCashBalanceProvider, which sums every allowed-branch safe).
    final cashBalance = ref.watch(dashboardCashBalanceProvider);
    // Fix 2 label: don't claim "جميع الصناديق" once the filter has narrowed
    // the card down to one branch.
    final cashCardTitle = dashFilter.branchId == null
        ? tr('أرصدة جميع الصناديق')
        : tr('أرصدة صناديق الفرع');
    // Phase C2: subscribe to runtime feature flags so the dashboard
    // KPIs / quick-action cards re-render the moment a developer
    // toggles a feature or changes the profile — no logout / restart.
    final features = ref.watch(featureFlagsProvider);

    // #Phase3: Log screen access + run notification triggers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      if (user != null) {
        ref
            .read(activityLoggerProvider)
            .logNavigation(
              user.id,
              user.displayName,
              tr('لوحة التحكم (Dashboard)'),
            );
        // B3: Auto-check notification triggers
        ref.read(notificationTriggersServiceProvider).runAllChecks(userId: user.id);
      }
    });

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Enhanced Header
              SectionHeader(
                title: tr('لوحة التحكم'),
                icon: PhosphorIconsBold.squaresFour,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Feature 004 — branch-scope indicator. Tells the operator
                    // at a glance whether the dashboard is showing all
                    // branches (HQ admin) or a single branch (everyone else).
                    _DashboardScopeIndicator(),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            PhosphorIconsBold.calendar,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat(
                              tr('EEEE، d MMMM yyyy'),
                              'ar',
                            ).format(DateTime.now()),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Fix 1 (spec 150, BUG-6): filter bar that WRITES to the shared
              // dashboardFilterProvider — mirrors analytics_dashboard_screen
              // .dart's _syncGlobalFilter(). Before this, HOME only ever READ
              // the filter, so the KPI cards below were stuck on whatever
              // analytics last set (or "today, all branches" if analytics was
              // never opened this session) with no way to change it here.
              const _DashboardFilterBar(),
              const SizedBox(height: 8),

              // Active-period indicator for the KPI cards (they follow the
              // shared analytics filter, not necessarily today).
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.calendarBlank,
                        size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      _dashboardPeriodLabel(dashFilter.from, dashFilter.to),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),

              // ─── Compact KPI Summary Row ───────────────────────────
              SizedBox(
                height: 90,
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        // البند 1 — المعادلة كاملة بالأرقام بدل وصف نصّي. سبب
                        // عدم تطابق الرقم مع حساب العميل اليدوي أنه بدون
                        // ضريبة بينما هو يجمع مقبوضات شاملة الضريبة؛ الفارق
                        // هو ضريبة المخرجات المعروضة هنا صراحةً.
                        richMessage: kpi.maybeWhen(
                          data: (k) {
                            final f = NumberFormat('#,##0.00', 'ar');
                            return TextSpan(
                              text: 'صافي إيراد دفتر الأستاذ — عن الفترة '
                                  'والفرع المحددين أعلى الشاشة\n\n'
                                  'صافي الإيراد (بدون ضريبة)   ${f.format(k.revenue)}\n'
                                  '+ ضريبة المخرجات (صافية)    ${f.format(k.outputVatNet)}\n'
                                  '= صافي الإيراد شامل الضريبة ${f.format(k.netRevenueInclVat)}\n\n'
                                  'المردودات المخصومة أصلاً    ${f.format(k.salesReturns)}\n\n'
                                  'ملاحظة: الإيرادات غير البيعية (فائض الخزنة، '
                                  'خصم المشتريات) لا تدخل هذا الرقم.',
                            );
                          },
                          orElse: () => const TextSpan(
                            text: 'صافي إيراد دفتر الأستاذ — غير شامل الضريبة '
                                'وبعد خصم المردودات',
                          ),
                        ),
                        // dashboard_sales_today — نفس شكل كارتَي الخزنة
                        // والربح المجاورين: البديل بيموّه الرقم، وموافقة
                        // المدير بتكشفه.
                        child: PermissionGuard(
                          permission: PermissionCodes.dashboardSalesToday,
                          allowManagerOverride: true,
                          actionName: tr('عرض صافي الإيراد'),
                          fallback: _HoverableStatCard(
                            title: tr('صافي الإيراد'),
                            value: '---',
                            suffix: AppConstants.currencySymbolEn,
                            icon: PhosphorIconsBold.chartLineUp,
                            color: AppColors.success,
                          ),
                          child: _HoverableStatCard(
                            // Fix 4 (spec 150 / REP-5): kpi.revenue is the GL net
                            // revenue (ex-VAT, after returns) — "المبيعات" alone
                            // reads as gross sales, so relabel + tooltip like
                            // analytics_dashboard_screen.dart's matching card.
                            title: tr('صافي الإيراد'),
                            value: kpi.when(
                              data: (k) =>
                                  NumberFormat('#,##0.00', 'ar').format(k.revenue),
                              loading: () => '...',
                              error: (e, s) => '0.00',
                            ),
                            suffix: AppConstants.currencySymbolEn,
                            icon: PhosphorIconsBold.chartLineUp,
                            color: AppColors.success,
                            trendLabel:
                                _trendBadgeLabel(dashFilter.from, dashFilter.to),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HoverableStatCard(
                        title: tr('عدد الفواتير'),
                        value: kpi.when(
                          data: (k) => k.invoiceCount.toString(),
                          loading: () => '...',
                          error: (e, s) => '0',
                        ),
                        suffix: tr('فاتورة'),
                        icon: PhosphorIconsBold.receipt,
                        color: AppColors.primary,
                        trendLabel:
                            _trendBadgeLabel(dashFilter.from, dashFilter.to),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Treasury Balance
                    Expanded(
                      child: PermissionGuard(
                        permission: PermissionCodes.treasuryBalanceView,
                        allowManagerOverride: true,
                        actionName: tr('عرض أرصدة جميع الصناديق'),
                        fallback: _HoverableStatCard(
                          title: cashCardTitle,
                          value: '---',
                          suffix: AppConstants.currencySymbolEn,
                          icon: PhosphorIconsBold.wallet,
                          color: AppColors.info,
                        ),
                        child: _HoverableStatCard(
                          title: cashCardTitle,
                          value: cashBalance.when(
                            data: (balance) =>
                                NumberFormat('#,##0.00', 'ar').format(balance),
                            loading: () => '...',
                            error: (e, s) => '0.00',
                          ),
                          suffix: AppConstants.currencySymbolEn,
                          icon: PhosphorIconsBold.wallet,
                          color: AppColors.info,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Daily Profit
                    Expanded(
                      child: PermissionGuard(
                        permission: PermissionCodes.dashboardProfit,
                        allowManagerOverride: true,
                        actionName: tr('عرض صافي الأرباح'),
                        fallback: _HoverableStatCard(
                          title: tr('صافي الربح'),
                          value: '---',
                          suffix: AppConstants.currencySymbolEn,
                          icon: PhosphorIconsBold.money,
                          color: AppColors.secondary,
                        ),
                        child: _HoverableStatCard(
                          title: tr('صافي الربح'),
                          value: kpi.when(
                                data: (k) =>
                                    NumberFormat('#,##0.00', 'ar').format(k.netProfit),
                                loading: () => '...',
                                error: (e, s) => '0.00',
                              ),
                          suffix: AppConstants.currencySymbolEn,
                          icon: PhosphorIconsBold.money,
                          color: AppColors.secondary,
                          trendLabel:
                              _trendBadgeLabel(dashFilter.from, dashFilter.to),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ─── Low Stock Alert ─────────────────────────────────────
              // dashboard_alerts — بانر تنبيه نقص المخزون. عرض بحت:
              // `fallback` بلا تجاوز مدير — ديالوج كلمة سر عشان يظهر بانر
              // تنبيه غلط (نفس قرار `pos_low_stock_alert` في دفعة ٧، وهو
              // حرفياً نفس التنبيه في البيع السريع).
              PermissionGuard(
                permission: PermissionCodes.dashboardAlerts,
                fallback: const SizedBox.shrink(),
                child: Consumer(
                  builder: (context, ref, _) {
                    final lowStock = ref.watch(lowStockProductsProvider);
                    return lowStock.when(
                    data: (products) => products.isEmpty
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(PhosphorIconsBold.warning, color: AppColors.warning, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tr('تنبيه: {p0} صنف وصل للحد الأدنى من المخزون', {'p0': products.length}),
                                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    if (onNavigate != null) onNavigate!(8);
                                  },
                                  child:  Text(tr('عرض المخزون'), style: const TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                    );
                  },
                ),
              ),

              // ─── Getting Started Checklist ─────────────────────────
              GettingStartedChecklist(onNavigate: onNavigate),

              // ─── Quick Actions Grid ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 4),
                child: Text(
                  tr('إجراءات سريعة'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              // Row 1: Sales / Products / Purchases / Reports
              SizedBox(
                height: 80,
                child: Row(
                  children: [
                    _QuickActionCard(
                      title: features.invoiceModeEnabled ? tr('فاتورة مبيعات') : tr('نقطة بيع'),
                      icon: features.invoiceModeEnabled
                          ? PhosphorIconsBold.fileText
                          : PhosphorIconsBold.shoppingCart,
                      color: const Color(0xFF10B981),
                      onTap: () {
                        if (onNavigate != null) {
                          onNavigate!(features.invoiceModeEnabled ? 17 : 1);
                        }
                      },
                    ),
                    const SizedBox(width: 10),
                    _QuickActionCard(
                      title: tr('إضافة صنف'),
                      icon: PhosphorIconsBold.plusCircle,
                      color: const Color(0xFF6366F1),
                      onTap: () {
                        if (onNavigate != null) onNavigate!(4);
                      },
                    ),
                    const SizedBox(width: 10),
                    _QuickActionCard(
                      title: tr('فاتورة مشتريات'),
                      icon: PhosphorIconsBold.shoppingBag,
                      color: const Color(0xFFF59E0B),
                      onTap: () {
                        if (onNavigate != null) onNavigate!(9);
                      },
                    ),
                    const SizedBox(width: 10),
                    _QuickActionCard(
                      title: tr('التقارير'),
                      icon: PhosphorIconsBold.chartBar,
                      color: const Color(0xFF3B82F6),
                      onTap: () {
                        if (onNavigate != null) onNavigate!(11);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Row 2: Sales Return / Purchase Return / Inventory / Manufacturing
              SizedBox(
                height: 80,
                child: Row(
                  children: [
                    _QuickActionCard(
                      title: tr('مرتجع مبيعات'),
                      icon: PhosphorIconsBold.arrowUDownLeft,
                      color: const Color(0xFFEF4444),
                      onTap: () {
                        if (onNavigate != null) onNavigate!(44); // salesReturns
                      },
                    ),
                    const SizedBox(width: 10),
                    _QuickActionCard(
                      title: tr('مرتجع مشتريات'),
                      icon: PhosphorIconsBold.arrowUDownRight,
                      color: const Color(0xFFEC4899),
                      onTap: () {
                        if (onNavigate != null) onNavigate!(45); // purchaseReturns
                      },
                    ),
                    const SizedBox(width: 10),
                    _QuickActionCard(
                      title: tr('المخزون'),
                      icon: PhosphorIconsBold.warehouse,
                      color: const Color(0xFF8B5CF6),
                      onTap: () {
                        if (onNavigate != null) onNavigate!(8); // inventory
                      },
                    ),
                    const SizedBox(width: 10),
                    _QuickActionCard(
                      title: tr('التصنيع'),
                      icon: PhosphorIconsBold.factory,
                      color: const Color(0xFF14B8A6),
                      onTap: () {
                        if (onNavigate != null) onNavigate!(25); // manufacturing
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Recent Sales
              Expanded(
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Row(
                          children: [
                            const Icon(
                              PhosphorIconsBold.clockCounterClockwise,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              tr('آخر المبيعات'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: todaySales.when(
                            data: (sales) {
                              if (sales.isEmpty) {
                                return  Center(
                                  child: Text(
                                    tr('لا توجد مبيعات اليوم'),
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                );
                              }
                              return ListView.separated(
                                itemCount: sales.length > 10
                                    ? 10
                                    : sales.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(),
                                itemBuilder: (context, index) {
                                  final sale = sales[index];
                                  return ListTile(
                                    leading: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.success.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        PhosphorIconsBold.receipt,
                                        color: AppColors.success,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      tr('فاتورة #{p0}', {'p0': sale.invoiceNumber}),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      DateFormat(
                                        'hh:mm a',
                                        'ar',
                                      ).format(sale.invoiceDate),
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: Text(
                                      '${NumberFormat('#,##0.00', 'ar').format(sale.total)} ${AppConstants.currencySymbolEn}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



/// Compact StatCard — fits 90px height with horizontal icon + value layout
/// Short Arabic label for the dashboard KPI period (the cards follow the shared
/// analytics filter). Shows "اليوم" when the window is the current calendar day,
/// otherwise the from–to range — so a month/year figure isn't misread as today.
String _dashboardPeriodLabel(DateTime from, DateTime to) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final f = DateFormat('yyyy/MM/dd', 'ar');
  if (!from.isBefore(todayStart) && !to.isAfter(todayEnd)) {
    return 'اليوم • ${f.format(from)}';
  }
  return 'الفترة: ${f.format(from)} — ${f.format(to)}';
}

/// Fix 3 (spec 150, BUG-6) — short label for the KPI cards' trend badge.
/// Unlike [_dashboardPeriodLabel] (full date range, for the line above the
/// cards), this stays chip-sized: "اليوم" only when the filter window IS
/// today, otherwise a generic "الفترة المحددة" so a month/year figure isn't
/// mislabeled as today's.
String _trendBadgeLabel(DateTime from, DateTime to) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
  if (!from.isBefore(todayStart) && !to.isAfter(todayEnd)) return tr('اليوم');
  return tr('الفترة المحددة');
}

/// Fix 1 (spec 150, BUG-6) — the HOME dashboard's own filter bar. Writes to
/// [dashboardFilterProvider] the same way analytics_dashboard_screen.dart's
/// `_syncGlobalFilter` does (branch + resolved warehouseIds + period), so the
/// KPI cards above — which already `ref.watch` the provider — re-scope with
/// no further change. Deliberately lighter than analytics' filter (no
/// region/cost-center/warehouse drill-down): this bar only needs to cover the
/// fields `DashboardFilter` actually carries for the HOME cards.
class _DashboardFilterBar extends ConsumerStatefulWidget {
  const _DashboardFilterBar();

  @override
  ConsumerState<_DashboardFilterBar> createState() =>
      _DashboardFilterBarState();
}

class _DashboardFilterBarState extends ConsumerState<_DashboardFilterBar> {
  late String _selectedPeriod;
  late DateTime _fromDate;
  late DateTime _toDate;
  int? _selectedBranchId;
  List<int>? _branchWarehouseIds;

  @override
  void initState() {
    super.initState();
    // Seed from whatever is already in the shared filter (e.g. set earlier
    // from analytics) instead of silently resetting it to "today, all
    // branches" the moment the operator opens HOME.
    final current = ref.read(dashboardFilterProvider);
    _fromDate = current.from;
    _toDate = current.to;
    _selectedBranchId = current.branchId;
    _branchWarehouseIds = current.warehouseIds;
    _selectedPeriod = _periodOf(current.from, current.to);
  }

  String _periodOf(DateTime from, DateTime to) {
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    if (!from.isBefore(DateTime(now.year, now.month, now.day)) &&
        !to.isAfter(todayEnd)) {
      return 'today';
    }
    if (from == DateTime(now.year, now.month, 1) && !to.isAfter(todayEnd)) {
      return 'month';
    }
    if (from == DateTime(now.year, 1, 1) && !to.isAfter(todayEnd)) {
      return 'year';
    }
    return 'custom';
  }

  void _onPeriodChanged(String period) {
    final now = DateTime.now();
    setState(() {
      _selectedPeriod = period;
      switch (period) {
        case 'yesterday':
          _fromDate = DateTime(now.year, now.month, now.day - 1);
          _toDate = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
          break;
        case 'month':
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'year':
          _fromDate = DateTime(now.year, 1, 1);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'today':
        default:
          _fromDate = DateTime(now.year, now.month, now.day);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
    });
    _apply();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      locale: const Locale('ar'),
    );
    if (picked == null) return;
    setState(() {
      _selectedPeriod = 'custom';
      _fromDate = picked.start;
      _toDate = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
    });
    _apply();
  }

  Future<void> _onBranchChanged(int? branchId) async {
    setState(() {
      _selectedBranchId = branchId;
      _branchWarehouseIds = null; // reset until resolved below
    });
    if (branchId == null) {
      _apply();
      return;
    }
    final warehouseIds =
        await ref.read(branchWarehouseIdsProvider(branchId).future);
    if (!mounted) return;
    setState(() => _branchWarehouseIds = warehouseIds);
    _apply();
  }

  void _apply() {
    ref.read(dashboardFilterProvider.notifier).update(
          branchId: _selectedBranchId,
          warehouseIds: _branchWarehouseIds,
          // Not exposed on this bar — carry forward whatever cost-center
          // scope (if any) is already set elsewhere rather than clobbering it.
          costCenterId: ref.read(dashboardFilterProvider).costCenterId,
          from: _fromDate,
          to: _toDate,
        );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsBold.calendarBlank,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${dateFormat.format(_fromDate)} - ${dateFormat.format(_toDate)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _periodChip('today', tr('اليوم')),
          const SizedBox(width: 6),
          _periodChip('yesterday', tr('أمس')),
          const SizedBox(width: 6),
          _periodChip('month', tr('الشهر')),
          const SizedBox(width: 6),
          _periodChip('year', tr('السنة')),
          const Spacer(),
          SizedBox(
            width: 170,
            child: FutureBuilder<List<Branche>>(
              future: ref.read(branchRepositoryProvider).getBranches(),
              builder: (ctx, snap) {
                final branches = snap.data ?? [];
                if (branches.isEmpty) return const SizedBox.shrink();
                final effectiveBranch =
                    branches.any((b) => b.id == _selectedBranchId)
                        ? _selectedBranchId
                        : null;
                return DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: effectiveBranch,
                    isExpanded: true,
                    hint:  Text(tr('الفرع'), style: const TextStyle(fontSize: 12)),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textPrimary),
                    items: [
                       DropdownMenuItem<int?>(
                          value: null, child: Text(tr('كل الفروع'))),
                      ...branches.map((b) => DropdownMenuItem<int?>(
                            value: b.id,
                            child: Text(b.name, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: _onBranchChanged,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String period, String label) {
    final isSelected = _selectedPeriod == period;
    return InkWell(
      onTap: () => _onPeriodChanged(period),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _HoverableStatCard extends StatefulWidget {
  final String title;
  final String value;
  final String suffix;
  final IconData icon;
  final Color color;
  // Fix 3 (spec 150): defaults to "اليوم" for cards that are a live "now"
  // snapshot (e.g. safe balances); period-scoped cards pass the filter-driven
  // label from _trendBadgeLabel instead of always showing "اليوم".
  final String trendLabel;

  const _HoverableStatCard({
    required this.title,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
    this.trendLabel = 'اليوم',
  });

  @override
  State<_HoverableStatCard> createState() => _HoverableStatCardState();
}

class _HoverableStatCardState extends State<_HoverableStatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
          border: Border.all(
            color: _isHovered
                ? widget.color.withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? widget.color.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: _isHovered ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon, color: widget.color, size: 20),
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          widget.value,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: widget.color,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.suffix,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Trend badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsBold.trendUp, size: 10, color: AppColors.success),
                  const SizedBox(width: 2),
                  Text(
                    widget.trendLabel,
                    style: const TextStyle(fontSize: 9, color: AppColors.success, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact Quick Action Card — fits 80px height, centered icon + label
class _QuickActionCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _isHovered ? widget.color.withValues(alpha: 0.06) : Colors.white,
              border: Border.all(
                color: _isHovered
                    ? widget.color.withValues(alpha: 0.35)
                    : Colors.grey.withValues(alpha: 0.12),
                width: _isHovered ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? widget.color.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: _isHovered ? 12 : 4,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: _isHovered ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.color,
                      size: _isHovered ? 22 : 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: _isHovered ? FontWeight.w700 : FontWeight.w600,
                      color: _isHovered ? widget.color : AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Feature 004 — small chip on the dashboard header that tells the operator
/// what they're looking at:
///   • "كل الفروع" pill (orange) when the user has unrestricted scope
///   • A [BranchChip] for the user's primary branch when they're branch-bound
/// Hidden while the scope is loading or the user isn't authenticated yet.
class _DashboardScopeIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) return const SizedBox.shrink();

    final scopeAsync = ref.watch(branchScopeProvider);
    final scope = scopeAsync.value;
    if (scope == null) return const SizedBox.shrink();

    if (scope.hasFullAccess) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF57C00).withValues(alpha: 0.3)),
        ),
        child:  Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsBold.buildings, size: 12, color: Color(0xFFE65100)),
            const SizedBox(width: 4),
            Text(
              tr('كل الفروع'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE65100),
              ),
            ),
          ],
        ),
      );
    }

    final primaryId = scope.primaryBranchId;
    if (primaryId == null) return const SizedBox.shrink();
    return BranchChip(branchId: primaryId);
  }
}
