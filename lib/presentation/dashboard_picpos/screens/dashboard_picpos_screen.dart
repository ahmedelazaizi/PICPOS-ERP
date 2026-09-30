import 'package:ural_erp/core/i18n/tr.dart';
// منطق منسوخ من dashboard_screen.dart (lib/presentation/screens/,
// ١٠٩٦ سطر) — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ
// §٥.٨). الشاشة دي الاستثناء الوحيد في دفعة إعادة التصميم اللي عندها
// تخطيط PicPos مخصّص فعلاً (مش reskin) — لكن كل منطق الأعمال والـ providers
// نفسها بالظبط:
//   - `_DashboardFilterBar` (فلتر الفترة/الفرع) منسوخة حرفياً — تقرأ/تكتب
//     `dashboardFilterProvider` زي الأصل بالظبط.
//   - `_QuickActionCard` منسوخة حرفياً — نفس الشبكة (٨ إجراءات) بنفس
//     `onNavigate(index)` لكل واحد.
//   - كروت الـ KPI (`dashboardKpiProvider`) وكارت رصيد الصناديق
//     (`dashboardCashBalanceProvider`) بنفس أغلفة `PermissionGuard`
//     (`treasuryBalanceView` / `dashboardProfit`) — القيم بس بتتعرض بشكل
//     PicPos بدل `_HoverableStatCard` الأصلية.
//   - بانر تنبيه المخزون (`lowStockProductsProvider`) و`GettingStartedChecklist`
//     زي ما هم بالظبط.
//   - **اتحذف** قسم «آخر المبيعات» (`todaySalesProvider`) بالكامل — مش جزء
//     من هالة الميزات المطلوبة لهذه النسخة (يُحذف صراحة بالتاسك).
//
// طبقة PicPos المضافة (جديدة، عرض فقط، ما بتتنقلش لـ UralCash):
// `PicPosGauge`/`PicPosDonut` (lib/presentation/dashboard_picpos/widgets/) —
// كل واحد منهم يستقبل رقم جاهز من provider حقيقي ويرسمه، بلا أي حساب أعمال
// جديد. توثيق مصدر كل مؤشر (إلزامي حسب التاسك):
//
// ┌─────────────────────────────┬───────────────────────────────────────────┐
// │ المؤشر                      │ المصدر / سبب التأجيل                        │
// ├─────────────────────────────┼───────────────────────────────────────────┤
// │ قوس «هامش الربح»            │ حقيقي. `dashboardKpiProvider` →            │
// │ (PicPosGauge)                │ `kpi.netProfit / kpi.revenue`، مع حراسة    │
// │                              │ `revenue == 0` وقصّ (clamp) للعرض ٠..١.     │
// │                              │ نفس الحقلين المستخدمين أصلاً في كارت       │
// │                              │ «صافي الربح» و«صافي الإيراد» بالشاشة الأم.  │
// ├─────────────────────────────┼───────────────────────────────────────────┤
// │ دونات «تركيبة الإيراد»       │ حقيقي. نفس `dashboardKpiProvider` —        │
// │ (PicPosDonut)                │ شريحتين: `kpi.revenue` (صافي الإيراد بدون  │
// │                              │ ضريبة) و`kpi.outputVatNet` (ضريبة المخرجات │
// │                              │ الصافية). نفس التفكيك المعروض أصلاً في     │
// │                              │ tooltip كارت «صافي الإيراد» بالشاشة الأم    │
// │                              │ (مجموعهما = `kpi.netRevenueInclVat`) —      │
// │                              │ بلا أي معادلة جديدة.                       │
// ├─────────────────────────────┼───────────────────────────────────────────┤
// │ «نسبة التحصيل»               │ **مؤجَّل**. لا يوجد provider يعطي نسبة      │
// │                              │ تحصيل جاهزة. `arAgingReportProvider`       │
// │                              │ موجود لكنه يرجّع صفوف تقادم لكل عميل تحتاج  │
// │                              │ تجميعاً/معادلة جديدة لاشتقاق نسبة واحدة —   │
// │                              │ ده تحديدًا نوع «الاختراع» الممنوع بالتاسك.  │
// ├─────────────────────────────┼───────────────────────────────────────────┤
// │ «توزيع طرق الدفع»            │ **مؤجَّل**. لا `DashboardKpi` ولا           │
// │                              │ `SalesAnalytics` فيهم تقسيم نقدي/شبكة/آجل — │
// │                              │ مفيش provider حالي يوفر توزيع طرق الدفع.    │
// ├─────────────────────────────┼───────────────────────────────────────────┤
// │ «تحقيق الهدف الشهري»         │ **مؤجَّل**. لا يوجد provider/إعداد لهدف      │
// │                              │ مبيعات في المشروع حالياً.                   │
// └─────────────────────────────┴───────────────────────────────────────────┘
//
// المؤجّلات معروضة كبطاقة واحدة صريحة «غير متاحة حالياً» بدل اختراع أرقام —
// ولا يُضاف أي provider/محرك جديد في هذا التاسك (لو احتاج لاحقاً، يكون
// كوميت محرك منفصل + patch، زي أي إصلاح منطقي آخر).

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/config/business_profile_provider.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/providers.dart';
import '../../../data/providers/dashboard_filter_provider.dart';
import '../../widgets/permission_guard.dart';
import '../../widgets/getting_started_checklist.dart';
import '../../picpos_shell/picpos_page_header.dart';
import '../widgets/picpos_gauge.dart';
import '../widgets/picpos_donut.dart';

/// شاشة لوحة القيادة بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام `dashboardKpiProvider` و
/// `dashboardCashBalanceProvider` و`lowStockProductsProvider` و
/// `dashboardFilterProvider` كما هم — فقط طبقة العرض تبدّلت لتخطيط PicPos
/// مخصّص + قوس/دونات PicPos-only فوق نفس البيانات (راجع رأس الملف للتوثيق
/// الكامل لمصدر كل مؤشر).
class DashboardPicposScreen extends ConsumerWidget {
  const DashboardPicposScreen({super.key, this.onNavigate});

  final void Function(int)? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpi = ref.watch(dashboardKpiProvider);
    final dashFilter = ref.watch(dashboardFilterProvider);
    final cashBalance = ref.watch(dashboardCashBalanceProvider);
    final cashCardTitle =
        dashFilter.branchId == null ? tr('كل الصناديق') : tr('صناديق الفرع');
    final features = ref.watch(featureFlagsProvider);
    final numberFmt = NumberFormat('#,##0.00', 'ar');

    return PicPosScreenScaffoldDashboard(
      onNavigate: onNavigate,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DashboardFilterBar(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
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

            // ─── بانر تنبيه المخزون (lowStockProductsProvider) ─────────
            // dashboard_alerts — نفس حارس فورك UralCash: عرض بحت بـ`fallback`
            // بلا تجاوز مدير.
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppColors.warning.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(PhosphorIconsBold.warning,
                                  color: AppColors.warning, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  tr('تنبيه: {p0} صنف وصل للحد الأدنى من المخزون', {'p0': products.length}),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (onNavigate != null) onNavigate!(8);
                                },
                                child:  Text(tr('عرض المخزون'),
                                    style: const TextStyle(fontSize: 12)),
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

            // ─── صف الإبراز: كروت KPI + قوس هامش الربح + دونات التركيبة ─
            LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;
              final kpiGrid = _PicPosKpiGrid(
                kpi: kpi,
                cashBalance: cashBalance,
                cashCardTitle: cashCardTitle,
                numberFmt: numberFmt,
              );
              // dashboard_chart — «عرض الرسوم البيانية». الرسمين دول موجودين
              // في فورك PicPos بس؛ لوحة UralCash مالهاش رسوم أصلاً (اللي
              // فيها أيقونات اسمها chartLineUp/chartBar وخلاص). عرض بحت →
              // `fallback: SizedBox.shrink()` بلا تجاوز مدير.
              final profitGauge = PermissionGuard(
                permission: PermissionCodes.dashboardChart,
                fallback: const SizedBox.shrink(),
                child: _ProfitMarginGaugeCard(kpi: kpi),
              );
              final revenueDonut = PermissionGuard(
                permission: PermissionCodes.dashboardChart,
                fallback: const SizedBox.shrink(),
                child: _RevenueCompositionDonutCard(kpi: kpi),
              );

              // ملاحظة: بلا `CrossAxisAlignment.stretch` ولا `IntrinsicHeight`
              // عن قصد — الصف هنا جوّه `SingleChildScrollView` فبيستقبل ارتفاع
              // غير محدود؛ الاتنين بيفترضوا ارتفاع محدود ليمدّوا الأبناء له
              // ويرموا استثناء وقت التشغيل (BoxConstraints forces an
              // infinite height) لو الأب مديله ارتفاع لا نهائي. كل كارت هنا
              // بيحدد ارتفاعه من محتواه (Container عادي)، فمفيش داعي للتمدد.
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    kpiGrid,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: profitGauge),
                        const SizedBox(width: 12),
                        Expanded(child: revenueDonut),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: kpiGrid),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: profitGauge),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: revenueDonut),
                ],
              );
            }),
            const SizedBox(height: 12),

            // ─── مؤشرات مؤجَّلة (توثيق مرئي — بلا أرقام مخترعة) ─────────
            const _DeferredMetricsNotice(),
            const SizedBox(height: 8),

            // ─── دليل البدء ─────────────────────────────────────────────
            GettingStartedChecklist(onNavigate: onNavigate),

            // ─── شبكة الإجراءات السريعة ─────────────────────────────────
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
            SizedBox(
              height: 80,
              child: Row(
                children: [
                  _QuickActionCard(
                    title: features.invoiceModeEnabled
                        ? tr('فاتورة مبيعات')
                        : tr('نقطة بيع'),
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
                      if (onNavigate != null) {
                        onNavigate!(45); // purchaseReturns
                      }
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
                      if (onNavigate != null) {
                        onNavigate!(25); // manufacturing
                      }
                    },
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

/// Short Arabic label for the dashboard KPI period — منسوخة حرفياً من
/// dashboard_screen.dart (الأصل).
String _dashboardPeriodLabel(DateTime from, DateTime to) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final f = DateFormat('yyyy/MM/dd', uiLocaleCode);
  if (!from.isBefore(todayStart) && !to.isAfter(todayEnd)) {
    return tr('اليوم • {p0}', {'p0': f.format(from)});
  }
  return tr('الفترة: {p0} — {p1}', {
    'p0': f.format(from),
    'p1': f.format(to),
  });
}

// ═══════════════════════════════════════════════════════════════════════
// إطار PicPos لهذه الشاشة تحديداً — هيدر + محتوى، بدون Scaffold مزدوج
// ═══════════════════════════════════════════════════════════════════════
class PicPosScreenScaffoldDashboard extends StatelessWidget {
  final void Function(int)? onNavigate;
  final Widget child;

  const PicPosScreenScaffoldDashboard({
    super.key,
    required this.onNavigate,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             PicPosPageHeader(
              title: tr('لوحة القيادة'),
              subtitle: tr('نظرة سريعة على المبيعات والمخزون والصناديق'),
              icon: PhosphorIconsBold.gauge,
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// شبكة كروت KPI — نفس بيانات dashboard_screen.dart (kpi + cashBalance)،
// بعرض PicPos بدل _HoverableStatCard الأصلية.
// ═══════════════════════════════════════════════════════════════════════
class _PicPosKpiGrid extends StatelessWidget {
  final AsyncValue<DashboardKpi> kpi;
  final AsyncValue<double> cashBalance;
  final String cashCardTitle;
  final NumberFormat numberFmt;

  const _PicPosKpiGrid({
    required this.kpi,
    required this.cashBalance,
    required this.cashCardTitle,
    required this.numberFmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // dashboard_sales_today — نفس حارس فورك UralCash وبنفس شكل
              // كارتَي الخزنة والربح تحت في نفس الملف.
              Expanded(
                child: PermissionGuard(
                  permission: PermissionCodes.dashboardSalesToday,
                  allowManagerOverride: true,
                  actionName: tr('عرض صافي الإيراد'),
                  fallback: _PicPosKpiTile(
                    title: tr('صافي الإيراد'),
                    value: '---',
                    suffix: AppConstants.currencySymbolEn,
                    icon: PhosphorIconsBold.chartLineUp,
                    color: AppColors.success,
                  ),
                  child: _PicPosKpiTile(
                    title: tr('صافي الإيراد'),
                    value: kpi.when(
                      data: (k) => numberFmt.format(k.revenue),
                      loading: () => '...',
                      error: (e, s) => '0.00',
                    ),
                    suffix: AppConstants.currencySymbolEn,
                    icon: PhosphorIconsBold.chartLineUp,
                    color: AppColors.success,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PicPosKpiTile(
                  title: tr('عدد الفواتير'),
                  value: kpi.when(
                    data: (k) => k.invoiceCount.toString(),
                    loading: () => '...',
                    error: (e, s) => '0',
                  ),
                  suffix: tr('فاتورة'),
                  icon: PhosphorIconsBold.receipt,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PermissionGuard(
                  permission: PermissionCodes.treasuryBalanceView,
                  allowManagerOverride: true,
                  actionName: tr('عرض أرصدة جميع الصناديق'),
                  fallback: _PicPosKpiTile(
                    title: cashCardTitle,
                    value: '---',
                    suffix: AppConstants.currencySymbolEn,
                    icon: PhosphorIconsBold.wallet,
                    color: AppColors.info,
                  ),
                  child: _PicPosKpiTile(
                    title: cashCardTitle,
                    value: cashBalance.when(
                      data: (balance) => numberFmt.format(balance),
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
              Expanded(
                child: PermissionGuard(
                  permission: PermissionCodes.dashboardProfit,
                  allowManagerOverride: true,
                  actionName: tr('عرض صافي الأرباح'),
                  fallback: _PicPosKpiTile(
                    title: tr('صافي الربح'),
                    value: '---',
                    suffix: AppConstants.currencySymbolEn,
                    icon: PhosphorIconsBold.money,
                    color: AppColors.secondary,
                  ),
                  child: _PicPosKpiTile(
                    title: tr('صافي الربح'),
                    value: kpi.when(
                      data: (k) => numberFmt.format(k.netProfit),
                      loading: () => '...',
                      error: (e, s) => '0.00',
                    ),
                    suffix: AppConstants.currencySymbolEn,
                    icon: PhosphorIconsBold.money,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PicPosKpiTile extends StatelessWidget {
  final String title;
  final String value;
  final String suffix;
  final IconData icon;
  final Color color;

  const _PicPosKpiTile({
    required this.title,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      suffix,
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// قوس «هامش الربح» — المؤشر الحقيقي الوحيد المضمون (راجع التوثيق برأس
// الملف). المصدر: dashboardKpiProvider → kpi.netProfit / kpi.revenue.
// ═══════════════════════════════════════════════════════════════════════
class _ProfitMarginGaugeCard extends StatelessWidget {
  final AsyncValue<DashboardKpi> kpi;

  const _ProfitMarginGaugeCard({required this.kpi});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: kpi.when(
        data: (k) {
          // حراسة القسمة على صفر — لا إيراد يعني هامش غير معرَّف، نعرض ٠٪.
          final rawMargin = k.revenue == 0 ? 0.0 : k.netProfit / k.revenue;
          final clamped = rawMargin < 0 ? 0.0 : (rawMargin > 1 ? 1.0 : rawMargin);
          return Center(
            child: PicPosGauge(
              value: clamped,
              label: tr('هامش الربح'),
              valueLabel: '${(rawMargin * 100).toStringAsFixed(1)}%',
              color: rawMargin < 0 ? AppColors.error : AppColors.success,
              size: 128,
            ),
          );
        },
        loading: () => const Center(
          child: SizedBox(
            width: 128,
            height: 128,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
        error: (e, s) =>  Center(
          child: PicPosGauge(
            value: 0,
            label: tr('هامش الربح'),
            valueLabel: '—',
            color: AppColors.textMuted,
            size: 128,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// دونات «تركيبة الإيراد» — نفس حقلي dashboardKpiProvider المعروضين أصلاً
// في tooltip كارت «صافي الإيراد» بالشاشة الأم (kpi.revenue + kpi.outputVatNet
// = kpi.netRevenueInclVat). بلا أي معادلة جديدة.
// ═══════════════════════════════════════════════════════════════════════
class _RevenueCompositionDonutCard extends StatelessWidget {
  final AsyncValue<DashboardKpi> kpi;

  const _RevenueCompositionDonutCard({required this.kpi});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: kpi.when(
        data: (k) {
          final segments = [
            PicPosDonutSegment(
              label: tr('صافي الإيراد'),
              value: k.revenue < 0 ? 0 : k.revenue,
              color: AppColors.success,
            ),
            PicPosDonutSegment(
              label: tr('ضريبة المخرجات'),
              value: k.outputVatNet < 0 ? 0 : k.outputVatNet,
              color: AppColors.info,
            ),
          ];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PicPosDonut(
                segments: segments,
                size: 118,
                centerLabel: tr('شامل الضريبة'),
                centerValue:
                    NumberFormat('#,##0', 'ar').format(k.netRevenueInclVat),
              ),
              const SizedBox(height: 8),
              _DonutLegend(segments: segments),
            ],
          );
        },
        loading: () => const SizedBox(
          height: 118,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, s) =>  SizedBox(
          height: 118,
          child: Center(
            child: Text(tr('تعذّر تحميل تركيبة الإيراد'),
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
        ),
      ),
    );
  }
}

class _DonutLegend extends StatelessWidget {
  final List<PicPosDonutSegment> segments;

  const _DonutLegend({required this.segments});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: segments
          .map((s) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(s.label,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textMuted)),
                ],
              ))
          .toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// إشعار المؤشرات المؤجَّلة — توثيق مرئي صريح، بلا أي رقم مخترع (راجع
// التوثيق برأس الملف لسبب كل تأجيل).
// ═══════════════════════════════════════════════════════════════════════
class _DeferredMetricsNotice extends StatelessWidget {
  const _DeferredMetricsNotice();

  @override
  Widget build(BuildContext context) {
    final deferred = [
      tr('نسبة التحصيل'),
      tr('توزيع طرق الدفع'),
      tr('تحقيق الهدف الشهري'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.info, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('مؤشرات إضافية غير متاحة حالياً ({p0}) — بانتظار مصدر بيانات مخصّص.', {'p0': deferred.join(tr('، '))}),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _DashboardFilterBar — منسوخة حرفياً من dashboard_screen.dart (الأصل).
// تكتب لـ dashboardFilterProvider بنفس الحقول (branch + warehouseIds +
// period)؛ أي إصلاح منطقي هنا يتصلّح بالمصدر أولاً ثم يُنقل بـ patch.
// ═══════════════════════════════════════════════════════════════════════
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
          costCenterId: ref.read(dashboardFilterProvider).costCenterId,
          from: _fromDate,
          to: _toDate,
        );
  }

  @override
  Widget build(BuildContext context) {
      final dateFormat = DateFormat('yyyy/MM/dd', uiLocaleCode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          _periodChip('today', tr('اليوم')),
          _periodChip('yesterday', tr('أمس')),
          _periodChip('month', tr('الشهر')),
          _periodChip('year', tr('السنة')),
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
                            child:
                                Text(b.name, overflow: TextOverflow.ellipsis),
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

// ═══════════════════════════════════════════════════════════════════════
// _QuickActionCard — منسوخة حرفياً من dashboard_screen.dart (الأصل).
// ═══════════════════════════════════════════════════════════════════════
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
              color: _isHovered
                  ? widget.color.withValues(alpha: 0.06)
                  : Colors.white,
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
                      color: widget.color
                          .withValues(alpha: _isHovered ? 0.15 : 0.08),
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
                      fontWeight:
                          _isHovered ? FontWeight.w700 : FontWeight.w600,
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
