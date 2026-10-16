// Financial Intelligence — pure ratio engine. No I/O, no database.
//
// Conventions
//  * A ratio whose denominator is 0 (or any input non-finite) has
//    `value == null` and status [RatioStatus.unknown]; never NaN/Infinity.
//  * Period ratios are NOT annualised: turnover = period flow / balance.
//  * Balance figures are period-end (no averaging) — documented simplification.
//  * Thresholds are rule-of-thumb defaults, stated in each ratio's formula.
import '../../core/i18n/tr.dart' show uiLocaleCode;
import 'financial_snapshot.dart';

enum RatioUnit { times, percent, days }

enum GoodDirection { higherBetter, lowerBetter }

enum RatioStatus { good, warning, bad, unknown }

enum RatioGroup { liquidity, profitability, efficiency, leverage, cashFlow, growth }

class Ratio {
  const Ratio({
    required this.key,
    required this.group,
    required this.label,
    required this.formula,
    required this.value,
    required this.unit,
    required this.direction,
    required this.status,
    required this.interpretation,
  });

  final String key;
  final RatioGroup group;
  final Bilingual label;
  final String formula;
  final double? value;
  final RatioUnit unit;
  final GoodDirection direction;
  final RatioStatus status;
  final Bilingual interpretation;

  String get labelText => label.resolve(uiLocaleCode);
  String get interpretationText => interpretation.resolve(uiLocaleCode);
}

/// Safe division: null when denominator is 0/non-finite or result non-finite.
double? safeDiv(double numerator, double denominator) {
  if (denominator == 0 || !denominator.isFinite || !numerator.isFinite) {
    return null;
  }
  final r = numerator / denominator;
  return r.isFinite ? r : null;
}

double? _pct(double n, double d) {
  final r = safeDiv(n, d);
  return r == null ? null : r * 100;
}

/// Grades [v]. higherBetter: v >= good → good, v >= warn → warning, else bad.
/// lowerBetter: v <= good → good, v <= warn → warning, else bad.
/// With [negativeIsBad] a negative value is always bad (e.g. negative equity).
RatioStatus gradeValue(
  double? v,
  GoodDirection dir,
  double good,
  double warn, {
  bool negativeIsBad = false,
}) {
  if (v == null) return RatioStatus.unknown;
  if (negativeIsBad && v < 0) return RatioStatus.bad;
  if (dir == GoodDirection.higherBetter) {
    if (v >= good) return RatioStatus.good;
    if (v >= warn) return RatioStatus.warning;
    return RatioStatus.bad;
  }
  if (v <= good) return RatioStatus.good;
  if (v <= warn) return RatioStatus.warning;
  return RatioStatus.bad;
}

const _na = Bilingual('غير متاح (المقام صفر)', 'Not available (zero denominator)');

Ratio _make(
  RatioGroup group,
  String key,
  Bilingual label,
  String formula,
  double? value,
  RatioUnit unit,
  GoodDirection dir,
  double good,
  double warn,
  Bilingual Function(RatioStatus s) interp, {
  bool negativeIsBad = false,
}) {
  final s = gradeValue(value, dir, good, warn, negativeIsBad: negativeIsBad);
  return Ratio(
    key: key,
    group: group,
    label: label,
    formula: '$formula  [good ${dir == GoodDirection.higherBetter ? '≥' : '≤'} '
        '$good, warn ${dir == GoodDirection.higherBetter ? '≥' : '≤'} $warn]',
    value: value,
    unit: unit,
    direction: dir,
    status: s,
    interpretation: s == RatioStatus.unknown ? _na : interp(s),
  );
}

Bilingual _by(RatioStatus s, Bilingual g, Bilingual w, Bilingual b) =>
    s == RatioStatus.good ? g : (s == RatioStatus.warning ? w : b);

const _hi = GoodDirection.higherBetter;
const _lo = GoodDirection.lowerBetter;

class RatioEngine {
  const RatioEngine._();

  /// All six groups. [prior] enables the growth group (empty otherwise).
  static List<Ratio> computeAll(FinancialSnapshot s, {FinancialSnapshot? prior}) =>
      [
        ...liquidity(s),
        ...profitability(s),
        ...efficiency(s),
        ...leverage(s),
        ...cashFlow(s),
        if (prior != null) ...growth(s, prior),
      ];

  static List<Ratio> liquidity(FinancialSnapshot s) => [
        _make(
          RatioGroup.liquidity, 'current_ratio',
          const Bilingual('نسبة التداول', 'Current ratio'),
          'currentAssets / currentLiabilities',
          safeDiv(s.currentAssets, s.currentLiabilities), RatioUnit.times, _hi,
          1.5, 1.0,
          (st) => _by(
            st,
            const Bilingual('السيولة كافية لسداد الالتزامات القصيرة', 'Short-term obligations are well covered'),
            const Bilingual('السيولة مقبولة لكن هامشها ضيق', 'Coverage is adequate but thin'),
            const Bilingual('الأصول المتداولة لا تغطي الالتزامات القصيرة', 'Current assets do not cover short-term obligations'),
          ),
        ),
        _make(
          RatioGroup.liquidity, 'quick_ratio',
          const Bilingual('نسبة السيولة السريعة', 'Quick ratio'),
          '(currentAssets - inventory) / currentLiabilities',
          safeDiv(s.currentAssets - s.inventory, s.currentLiabilities),
          RatioUnit.times, _hi, 1.0, 0.7,
          (st) => _by(
            st,
            const Bilingual('تغطية جيدة دون الاعتماد على المخزون', 'Good coverage without relying on stock'),
            const Bilingual('الاعتماد على بيع المخزون جزئي', 'Partly dependent on selling stock'),
            const Bilingual('الالتزامات تعتمد على بيع المخزون', 'Obligations depend on selling stock'),
          ),
        ),
        _make(
          RatioGroup.liquidity, 'cash_ratio',
          const Bilingual('نسبة النقدية', 'Cash ratio'),
          'cash / currentLiabilities',
          safeDiv(s.cash, s.currentLiabilities), RatioUnit.times, _hi,
          0.5, 0.2,
          (st) => _by(
            st,
            const Bilingual('رصيد نقدي قوي مقابل الالتزامات', 'Strong cash cushion'),
            const Bilingual('النقدية محدودة مقابل الالتزامات', 'Limited cash versus obligations'),
            const Bilingual('النقدية غير كافية للالتزامات الفورية', 'Cash is insufficient for immediate obligations'),
          ),
        ),
      ];

  static List<Ratio> profitability(FinancialSnapshot s) => [
        _make(
          RatioGroup.profitability, 'gross_margin',
          const Bilingual('هامش مجمل الربح', 'Gross margin'),
          'grossProfit / revenue x 100',
          _pct(s.grossProfit, s.revenue), RatioUnit.percent, _hi, 30, 15,
          (st) => _by(
            st,
            const Bilingual('هامش مجمل قوي', 'Healthy gross margin'),
            const Bilingual('هامش مجمل متوسط', 'Moderate gross margin'),
            const Bilingual('هامش مجمل ضعيف: راجع التسعير والتكلفة', 'Thin gross margin: review pricing and cost'),
          ),
        ),
        _make(
          RatioGroup.profitability, 'net_margin',
          const Bilingual('هامش صافي الربح', 'Net margin'),
          'netIncome / revenue x 100',
          _pct(s.netIncome, s.revenue), RatioUnit.percent, _hi, 10, 3,
          (st) => _by(
            st,
            const Bilingual('ربحية صافية جيدة', 'Good bottom-line profitability'),
            const Bilingual('ربحية صافية منخفضة', 'Low net profitability'),
            const Bilingual('الشركة تحقق خسارة أو ربحاً ضئيلاً', 'Loss-making or near break-even'),
          ),
        ),
        _make(
          RatioGroup.profitability, 'roa',
          const Bilingual('العائد على الأصول', 'Return on assets'),
          'netIncome / totalAssets x 100 (period, not annualised)',
          _pct(s.netIncome, s.totalAssets), RatioUnit.percent, _hi, 5, 1,
          (st) => _by(
            st,
            const Bilingual('الأصول مستغلة بكفاءة في توليد الربح', 'Assets generate profit efficiently'),
            const Bilingual('عائد الأصول متواضع', 'Modest return on assets'),
            const Bilingual('عائد الأصول ضعيف أو سالب', 'Weak or negative return on assets'),
          ),
        ),
        _make(
          RatioGroup.profitability, 'roe',
          const Bilingual('العائد على حقوق الملكية', 'Return on equity'),
          'netIncome / equity x 100 (period, not annualised)',
          _pct(s.netIncome, s.equity), RatioUnit.percent, _hi, 12, 5,
          (st) => _by(
            st,
            const Bilingual('عائد جيد للملاك', 'Good return for owners'),
            const Bilingual('عائد مقبول للملاك', 'Acceptable return for owners'),
            const Bilingual('عائد ضعيف للملاك', 'Poor return for owners'),
          ),
        ),
        _make(
          RatioGroup.profitability, 'ebitda_margin',
          const Bilingual('هامش EBITDA', 'EBITDA margin'),
          '(netIncome + interest + tax + depreciation) / revenue x 100',
          _pct(s.ebitda, s.revenue), RatioUnit.percent, _hi, 15, 5,
          (st) => _by(
            st,
            const Bilingual('ربحية تشغيلية قوية قبل الفوائد والضرائب والإهلاك', 'Strong operating profitability'),
            const Bilingual('ربحية تشغيلية متوسطة', 'Moderate operating profitability'),
            const Bilingual('ربحية تشغيلية ضعيفة', 'Weak operating profitability'),
          ),
        ),
      ];

  static List<Ratio> efficiency(FinancialSnapshot s) {
    final days = s.periodDays.toDouble();
    final dio = _mulDays(safeDiv(s.inventory, s.cogs), days);
    final dso = _mulDays(safeDiv(s.receivables, s.revenue), days);
    final dpo = _mulDays(safeDiv(s.payables, s.cogs), days);
    final ccc = (dio == null || dso == null || dpo == null)
        ? null
        : dio + dso - dpo;
    return [
      _make(
        RatioGroup.efficiency, 'inventory_turnover',
        const Bilingual('معدل دوران المخزون', 'Inventory turnover'),
        'cogs / inventory (period, not annualised)',
        safeDiv(s.cogs, s.inventory), RatioUnit.times, _hi, 4, 2,
        (st) => _by(
          st,
          const Bilingual('المخزون يدور بسرعة جيدة', 'Stock turns over quickly'),
          const Bilingual('دوران المخزون متوسط', 'Average stock turnover'),
          const Bilingual('دوران بطيء: خطر ركود المخزون', 'Slow turnover: risk of dead stock'),
        ),
      ),
      _make(
        RatioGroup.efficiency, 'dso',
        const Bilingual('أيام التحصيل (DSO)', 'Days sales outstanding'),
        'receivables / revenue x periodDays',
        dso, RatioUnit.days, _lo, 30, 60,
        (st) => _by(
          st,
          const Bilingual('تحصيل سريع من العملاء', 'Customers pay quickly'),
          const Bilingual('تحصيل متأخر نسبياً', 'Collection is somewhat slow'),
          const Bilingual('تحصيل بطيء: راجع الائتمان والمتابعة', 'Slow collection: review credit and follow-up'),
        ),
      ),
      _make(
        RatioGroup.efficiency, 'dpo',
        const Bilingual('أيام السداد (DPO)', 'Days payable outstanding'),
        'payables / cogs x periodDays',
        dpo, RatioUnit.days, _hi, 30, 15,
        (st) => _by(
          st,
          const Bilingual('استفادة جيدة من ائتمان الموردين', 'Good use of supplier credit'),
          const Bilingual('ائتمان الموردين مستغل جزئياً', 'Supplier credit partly used'),
          const Bilingual('السداد سريع جداً مقارنة بالتحصيل', 'Paying suppliers very quickly'),
        ),
      ),
      _make(
        RatioGroup.efficiency, 'asset_turnover',
        const Bilingual('معدل دوران الأصول', 'Asset turnover'),
        'revenue / totalAssets (period, not annualised)',
        safeDiv(s.revenue, s.totalAssets), RatioUnit.times, _hi, 1.0, 0.5,
        (st) => _by(
          st,
          const Bilingual('الأصول تولد مبيعات بكفاءة', 'Assets generate sales efficiently'),
          const Bilingual('كفاءة استخدام الأصول متوسطة', 'Average asset efficiency'),
          const Bilingual('الأصول غير مستغلة بالكامل', 'Assets are under-utilised'),
        ),
      ),
      _make(
        RatioGroup.efficiency, 'cash_conversion_cycle',
        const Bilingual('دورة تحويل النقد', 'Cash conversion cycle'),
        'DIO + DSO - DPO, DIO = inventory / cogs x periodDays',
        ccc, RatioUnit.days, _lo, 45, 90,
        (st) => _by(
          st,
          const Bilingual('النقد يعود سريعاً من التشغيل', 'Cash returns quickly from operations'),
          const Bilingual('دورة النقد متوسطة الطول', 'Moderately long cash cycle'),
          const Bilingual('النقد محجوز طويلاً في التشغيل', 'Cash is tied up for long'),
        ),
      ),
    ];
  }

  static double? _mulDays(double? ratio, double days) =>
      (ratio == null || days <= 0) ? null : ratio * days;

  static List<Ratio> leverage(FinancialSnapshot s) => [
        _make(
          RatioGroup.leverage, 'debt_to_equity',
          const Bilingual('الدين إلى حقوق الملكية', 'Debt to equity'),
          'debt / equity (negative equity = bad)',
          safeDiv(s.debt, s.equity), RatioUnit.times, _lo, 1.0, 2.0,
          (st) => _by(
            st,
            const Bilingual('اعتماد منخفض على الاقتراض', 'Low reliance on borrowing'),
            const Bilingual('اعتماد متوسط على الاقتراض', 'Moderate reliance on borrowing'),
            const Bilingual('مديونية مرتفعة أو حقوق ملكية سالبة', 'High leverage or negative equity'),
          ),
          negativeIsBad: true,
        ),
        _make(
          RatioGroup.leverage, 'debt_to_assets',
          const Bilingual('الدين إلى الأصول', 'Debt to assets'),
          'debt / totalAssets',
          safeDiv(s.debt, s.totalAssets), RatioUnit.times, _lo, 0.4, 0.6,
          (st) => _by(
            st,
            const Bilingual('نسبة تمويل الأصول بالدين منخفضة', 'Few assets are debt-financed'),
            const Bilingual('جزء معتبر من الأصول ممول بالدين', 'A notable share is debt-financed'),
            const Bilingual('معظم الأصول ممولة بالدين', 'Most assets are debt-financed'),
          ),
          negativeIsBad: true,
        ),
        _make(
          RatioGroup.leverage, 'interest_coverage',
          const Bilingual('تغطية الفوائد', 'Interest coverage'),
          '(netIncome + interest + tax) / interest',
          safeDiv(s.ebit, s.interest), RatioUnit.times, _hi, 3.0, 1.5,
          (st) => _by(
            st,
            const Bilingual('الأرباح تغطي الفوائد بسهولة', 'Earnings cover interest comfortably'),
            const Bilingual('تغطية الفوائد ضيقة', 'Interest coverage is tight'),
            const Bilingual('الأرباح لا تكفي لسداد الفوائد', 'Earnings barely or do not cover interest'),
          ),
        ),
      ];

  static List<Ratio> cashFlow(FinancialSnapshot s) => [
        _make(
          RatioGroup.cashFlow, 'ocf_margin',
          const Bilingual('هامش التدفق التشغيلي', 'Operating cash flow margin'),
          'operatingCashFlow / revenue x 100',
          _pct(s.operatingCashFlow, s.revenue), RatioUnit.percent, _hi, 10, 0,
          (st) => _by(
            st,
            const Bilingual('المبيعات تتحول إلى نقد بشكل جيد', 'Sales convert into cash well'),
            const Bilingual('تدفق تشغيلي ضعيف', 'Weak operating cash generation'),
            const Bilingual('التشغيل يستهلك النقد', 'Operations are burning cash'),
          ),
        ),
        _make(
          RatioGroup.cashFlow, 'ocf_to_current_liabilities',
          const Bilingual('التدفق التشغيلي إلى الالتزامات المتداولة', 'Operating cash flow to current liabilities'),
          'operatingCashFlow / currentLiabilities',
          safeDiv(s.operatingCashFlow, s.currentLiabilities), RatioUnit.times,
          _hi, 0.4, 0.1,
          (st) => _by(
            st,
            const Bilingual('التشغيل يغطي الالتزامات القصيرة', 'Operations cover short-term liabilities'),
            const Bilingual('تغطية تشغيلية جزئية', 'Partial operating coverage'),
            const Bilingual('التدفق التشغيلي لا يغطي الالتزامات', 'Operating cash does not cover liabilities'),
          ),
        ),
        _make(
          RatioGroup.cashFlow, 'cash_flow_to_net_income',
          const Bilingual('جودة الأرباح (تدفق/ربح)', 'Earnings quality (OCF / net income)'),
          'operatingCashFlow / netIncome',
          safeDiv(s.operatingCashFlow, s.netIncome), RatioUnit.times, _hi,
          1.0, 0.5,
          (st) => _by(
            st,
            const Bilingual('الأرباح مدعومة بنقد فعلي', 'Profit is backed by real cash'),
            const Bilingual('جزء من الأرباح لم يتحول لنقد', 'Part of profit is not yet cash'),
            const Bilingual('الأرباح لا تقابلها سيولة', 'Profit is not backed by cash'),
          ),
        ),
        _make(
          RatioGroup.cashFlow, 'free_cash_flow_margin',
          const Bilingual('هامش التدفق الحر', 'Free cash flow margin'),
          '(operatingCashFlow + investingCashFlow) / revenue x 100',
          _pct(s.operatingCashFlow + s.investingCashFlow, s.revenue),
          RatioUnit.percent, _hi, 5, 0,
          (st) => _by(
            st,
            const Bilingual('نقد حر بعد الاستثمار', 'Free cash left after investment'),
            const Bilingual('نقد حر محدود', 'Limited free cash'),
            const Bilingual('الاستثمار يفوق التدفق التشغيلي', 'Investment exceeds operating cash'),
          ),
        ),
      ];

  /// Growth vs [prior] period: (current - prior) / |prior| x 100.
  static List<Ratio> growth(FinancialSnapshot s, FinancialSnapshot prior) {
    Ratio g(String key, Bilingual label, double cur, double prev) => _make(
          RatioGroup.growth, key, label,
          '(current - prior) / |prior| x 100',
          _pct(cur - prev, prev.abs()), RatioUnit.percent, _hi, 5, 0,
          (st) => _by(
            st,
            const Bilingual('نمو إيجابي عن الفترة السابقة', 'Growing versus prior period'),
            const Bilingual('ثبات أو تراجع طفيف', 'Flat or slightly down'),
            const Bilingual('تراجع عن الفترة السابقة', 'Declined versus prior period'),
          ),
        );
    return [
      g('revenue_growth', const Bilingual('نمو الإيرادات', 'Revenue growth'),
          s.revenue, prior.revenue),
      g('gross_profit_growth', const Bilingual('نمو مجمل الربح', 'Gross profit growth'),
          s.grossProfit, prior.grossProfit),
      g('net_income_growth', const Bilingual('نمو صافي الربح', 'Net income growth'),
          s.netIncome, prior.netIncome),
      g('asset_growth', const Bilingual('نمو الأصول', 'Asset growth'),
          s.totalAssets, prior.totalAssets),
    ];
  }
}
