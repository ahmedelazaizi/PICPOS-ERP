import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart' as core_date_utils;
import 'branch_scope_provider.dart';
import 'repository_providers.dart';

/// مؤشّرٌ واحدٌ في صدر مركز التقارير: قيمةُ اليوم وقيمةُ الأمس.
///
/// الطرفان معاً لأنّ التصميم يرسم نسبةَ تغيّر — ونسبةٌ بلا طرفٍ ثانٍ رقمٌ
/// يُخترَع.
typedef ReportsKpiValue = ({double today, double yesterday});

/// مؤشّراتُ صدر مركز التقارير الأربعة.
class ReportsHubKpi {
  const ReportsHubKpi({
    required this.revenue,
    required this.netProfit,
    required this.invoices,
    required this.salesReturns,
  });

  /// صافي الإيراد من قائمة الدخل — بلا ضريبة وصافياً من المرتجعات.
  final ReportsKpiValue revenue;
  final ReportsKpiValue netProfit;
  final ReportsKpiValue invoices;
  final ReportsKpiValue salesReturns;

  /// نسبةُ التغيّر عن الأمس، أو `null` حين لا أساسَ تُقاس عليه.
  ///
  /// ⚠️ **`null` لا صفر**: يومُ أمسٍ بلا حركةٍ يجعل القسمةَ على صفر، و«٠٪»
  /// تُقرأ «لم يتغيّر» بينما الحقيقةُ «لا مقارنة». والواجهةُ تُخفي السهمَ
  /// كلَّه عند `null` بدل أن تكتب رقماً لا معنى له.
  static double? deltaPercent(ReportsKpiValue v) {
    if (v.yesterday == 0) return null;
    return ((v.today - v.yesterday) / v.yesterday.abs()) * 100;
  }
}

/// مؤشّراتُ اليوم مقابلَ الأمس، محصورةً بصلاحية فروع المستخدم.
///
/// ⚠️ **لماذا مزوّدٌ خاصٌّ لا `dashboardKpiProvider`.** ذاك محصورٌ بمرشِّح لوحة
/// التحكّم المشترك (`dashboardFilterProvider`)، فلو قرأه مركزُ التقارير لتبدّلت
/// أرقامُه كلّما بدّل المستخدمُ فترةَ اللوحة — وبطاقةٌ مكتوبٌ عليها «مبيعات
/// اليوم» تعرض الشهرَ كذبٌ صامت. وهذا المزوّدُ يثبّت اليومَ والأمسَ صراحةً.
///
/// ⚠️ **والحصرُ يدخل الاستعلامَ نفسَه** لا الترشيحَ بعده: مستخدمٌ محصورٌ
/// بفرعٍ لا يجوز أن يرى إجماليَّ الشركة في صدر الشاشة.
final reportsHubKpiProvider =
    FutureProvider.autoDispose<ReportsHubKpi>((ref) async {
  final repo = ref.watch(reportingRepositoryProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  final allowed = scope.hasFullAccess ? null : scope.allowedBranchIds;

  // نفسُ تسويةِ اليوم الكامل التي تستعملها مرشِّحاتُ التقارير — [00:00,
  // 23:59:59.999] — فلا تختلف «اليوم» هنا عن «اليوم» في شريط المرشِّحات.
  final now = DateTime.now();
  final todayFrom = core_date_utils.DateUtils.startOfDay(now);
  final todayTo = core_date_utils.DateUtils.endOfDay(now);
  final y = now.subtract(const Duration(days: 1));
  final yFrom = core_date_utils.DateUtils.startOfDay(y);
  final yTo = core_date_utils.DateUtils.endOfDay(y);

  Future<({double revenue, double profit, double returns, double invoices})>
      at(DateTime from, DateTime to) async {
    final income = await repo.getIncomeStatement(
      from,
      to,
      allowedBranchIds: allowed,
    );
    final analytics = await repo.getSalesAnalytics(
      from,
      to,
      allowedBranchIds: allowed,
    );
    return (
      revenue: (income['totalRevenue'] as num?)?.toDouble() ?? 0.0,
      profit: (income['netProfit'] as num?)?.toDouble() ?? 0.0,
      returns: (income['salesReturns'] as num?)?.toDouble() ?? 0.0,
      invoices: analytics.invoiceCount.toDouble(),
    );
  }

  final t = await at(todayFrom, todayTo);
  final p = await at(yFrom, yTo);

  return ReportsHubKpi(
    revenue: (today: t.revenue, yesterday: p.revenue),
    netProfit: (today: t.profit, yesterday: p.profit),
    invoices: (today: t.invoices, yesterday: p.invoices),
    salesReturns: (today: t.returns, yesterday: p.returns),
  );
});
