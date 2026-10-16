// حالةُ الشاشة: مزوِّدُ النتيجة بنطاق الفرع، وبناءُ بطاقات المؤشّرات، وكشفُ
// «لا بياناتٍ مرحَّلة». لا منطقَ ماليّ هنا — كلُّه من المحرّك.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/financial_analytics_provider.dart';
import '../../data/providers/providers.dart';
import '../../domain/analytics/financial_snapshot.dart';
import '../../domain/analytics/kpi_comparison.dart';
import '../../domain/analytics/ratio_engine.dart';

/// فترةٌ وفرعٌ اختياريّ (`null` ⇒ كلُّ ما يسمح به نطاقُ المستخدم).
typedef FinIndicatorsParams = ({DateTime from, DateTime to, int? branchId});

/// نفسُ `financialAnalyticsProvider` لكن بمرشّح فرعٍ من الشاشة.
///
/// النطاقُ الموثَّقُ للمستخدم يُطبَّق دائماً: فرعٌ خارجَه يعطي نطاقاً فارغاً
/// (لا بيانات) لا بياناتِ فرعٍ غيرِ مصرَّح. واختيارُ فرعٍ بعينه يجعل العرضَ
/// «مقيَّداً» فيعلن المحرّك أنّ الموازنةَ غيرُ متاحة (موازناتُ الشركة كلُّها).
final finIndicatorsProvider = FutureProvider.autoDispose
    .family<FinancialAnalyticsResult, FinIndicatorsParams>((ref, p) async {
  final db = ref.watch(databaseProvider);
  final scope = await ref.watch(branchScopeProvider.future);
  final Set<int>? allowed;
  final picked = p.branchId;
  if (picked == null) {
    allowed = scope.allowedBranchIds;
  } else if (scope.isAllowed(picked)) {
    allowed = {picked};
  } else {
    allowed = <int>{};
  }
  return computeFinancialAnalytics(
    db,
    (from: p.from, to: p.to),
    allowedBranchIds: allowed,
  );
});

/// بطاقاتُ المؤشّرات الأربع بمفاتيحها.
///
/// الإيرادُ وصافي الدخل من `result.comparisons` (فيها الموازنة). ومجملُ الربح
/// والتدفّقُ التشغيليّ لا يحملان في المحرّك هدفَ موازنة، فيُقارَنان بالفترة
/// السابقة فقط وموازنتُهما `null` ⇒ «غير متاح».
List<KpiComparison> buildFinKpis(FinancialAnalyticsResult r) {
  KpiComparison fromEngine(String key, double actual, double prior) {
    for (final c in r.comparisons) {
      if (c.key == key) return c;
    }
    return KpiComparison(
      key: key,
      actual: actual,
      direction: GoodDirection.higherBetter,
      prior: prior,
    );
  }

  return [
    fromEngine('revenue', r.current.revenue, r.prior.revenue),
    KpiComparison(
      key: 'gross_profit',
      actual: r.current.grossProfit,
      direction: GoodDirection.higherBetter,
      prior: r.prior.grossProfit,
    ),
    fromEngine('net_income', r.current.netIncome, r.prior.netIncome),
    KpiComparison(
      key: 'operating_cash_flow',
      actual: r.current.operatingCashFlow,
      direction: GoodDirection.higherBetter,
      prior: r.prior.operatingCashFlow,
    ),
  ];
}

/// نسبُ الفترة السابقة بمفتاح النسبة. (مجموعةُ النموّ تحتاج فترةً قبلها،
/// فتغيب هنا و«—» تُعرض.)
Map<String, Ratio> finPriorRatios(FinancialAnalyticsResult r) => {
      for (final x in RatioEngine.computeAll(r.prior)) x.key: x,
    };

/// هل لا يوجد أيُّ رقمٍ مرحَّلٍ في الفترتين؟ (كلُّ البنود المعروضة صفر.)
bool finSnapshotsEmpty(FinancialSnapshot a, FinancialSnapshot b) =>
    _isBlank(a) && _isBlank(b);

bool _isBlank(FinancialSnapshot s) =>
    s.revenue == 0 &&
    s.cogs == 0 &&
    s.opex == 0 &&
    s.netIncome == 0 &&
    s.totalAssets == 0 &&
    s.totalLiabilities == 0 &&
    s.equity == 0 &&
    s.cash == 0 &&
    s.inventory == 0 &&
    s.receivables == 0 &&
    s.payables == 0 &&
    s.operatingCashFlow == 0 &&
    s.investingCashFlow == 0 &&
    s.financingCashFlow == 0;
