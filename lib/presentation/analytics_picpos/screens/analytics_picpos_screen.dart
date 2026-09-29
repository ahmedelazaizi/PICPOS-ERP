import 'package:ural_erp/core/i18n/tr.dart';
// شاشةُ «التحليلات» بهويّة PicPos — على تصميم
// `PicPos Performance Analytics.dc.html`.
//
// ═══ المحرّكُ مبنيٌّ سلفاً — والشاشةُ إعادةُ تنسيق ═══
//
// `PerformanceAnalyticsService` يحمل الدوالَّ الأربعَ التي يصفها التصميم:
// `analyzeTrend` (‏انحدارٌ خطّيٌّ بالميل والتغيّر والاتّجاه وتنبّؤِ النقطة
// التالية) و`movingAverage` و`seasonalityIndex` و`forecast`. فلا يُعاد بناءُ
// شيءٍ منها هنا — تُستدعى كما هي.
//
// ═══ ⚠️ وفرقٌ حقيقيٌّ بين المحرّك والتصميم: طولُ السلسلة بعد التنعيم ═══
//
// تصميمُ الصفحة يحشو رأسَ المتوسّط المتحرّك بتكرار أوّلِ قيمةٍ كي تبقى
// السلسلةُ ١٢ نقطةً ومحاذيةً للشهور. و`movingAverage` في الخدمة **تُقصّر**
// السلسلةَ (‏تبدأ من النقطة `window-1`). فلو رُسمت أسماءُ الشهور الاثني عشر
// فوقَ عشرِ نقاطٍ لانزاح كلُّ عمودٍ عن شهره.
//
// والمختارُ هو **المحرّكَ لا التصميم**: الحشوُ يخترع نقطتَين لم تُقاسا. فتُقصّ
// أسماءُ الشهور مع السلسلة، ويُقال للمستخدم كم نقطةً يقرأ.
//
// ═══ ⚠️ ومحورُ الزمن مقلوبٌ في RTL ═══
//
// الزمنُ يمشي من اليمين لليسار. و`Row` داخلَ `Directionality.rtl` يرتّب
// العناصرَ كذلك تلقائيّاً، لكنّ `CustomPainter` يرسم بإحداثيّاتٍ خامٍ لا
// تعرف الاتّجاه — فخطُّ الانحدار يُعكَس صراحةً في [_RegressionPainter] وإلّا
// وقف مقلوباً فوقَ أعمدةٍ صحيحة.
//
// ═══ ⚠️ وما لم يُنقَل من التصميم ═══
//
// **حصرُ المنطقة**: التصميمُ يعطي مرشِّحَي منطقةٍ وفرع. و
// `getMonthlyPerformanceSeries` تقبل مخازنَ وفروعاً مأذونةً لا مناطق، ولا
// استعلامَ يجمع فروعَ منطقةٍ في سلسلةٍ شهريّة. فالمعروضُ حصرُ الفرع وحدَه —
// ووصلُ المنطقة دفعةُ DAO لا سطرُ عرض.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../services/performance_analytics_service.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';

final _money0 = NumberFormat('#,##0', 'en');
final _num1 = NumberFormat('#,##0.0', 'en');

const _ok = AppColors.success;
const _warn = AppColors.warning;
const _err = AppColors.error;
const _purple = AppColors.booking;

String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

List<String> get _monthsAr => [
  tr('يناير'), tr('فبراير'), tr('مارس'), tr('أبريل'), tr('مايو'), tr('يونيو'),
  tr('يوليو'), tr('أغسطس'), tr('سبتمبر'), tr('أكتوبر'), tr('نوفمبر'), tr('ديسمبر'),
];

/// كيفَ يُقرأ الرقم — المالُ يُختصر بالآلاف، والنسبةُ بعلامتها، والعدُّ صحيح.
enum _Unit { money, percent, count }

typedef _MetricDef = ({
  String id,
  String label,
  IconData icon,
  Color tint,
  _Unit unit,
  /// `true` ⇒ ارتفاعُه سيّئ (‏المصروف)، فيُلوَّن بالعكس.
  bool inverse,
});

List<_MetricDef> get _kMetrics => [
  (
    id: 'sales',
    label: tr('صافي المبيعات'),
    icon: PhosphorIconsBold.currencyCircleDollar,
    tint: AppColors.primary,
    unit: _Unit.money,
    inverse: false
  ),
  (
    id: 'margin',
    label: tr('هامش الربح الإجمالي'),
    icon: PhosphorIconsBold.percent,
    tint: _ok,
    unit: _Unit.percent,
    inverse: false
  ),
  (
    id: 'basket',
    label: tr('متوسط قيمة الفاتورة'),
    icon: PhosphorIconsBold.shoppingCart,
    tint: _purple,
    unit: _Unit.money,
    inverse: false
  ),
  (
    id: 'invoices',
    label: tr('عدد الفواتير'),
    icon: PhosphorIconsBold.receipt,
    tint: _warn,
    unit: _Unit.count,
    inverse: false
  ),
  (
    id: 'expenses',
    label: tr('المصروفات التشغيلية'),
    icon: PhosphorIconsBold.receiptX,
    tint: _err,
    unit: _Unit.money,
    inverse: true
  ),
];

String _fmt(double v, _Unit unit) {
  switch (unit) {
    case _Unit.percent:
      return tr('{p0}٪', {'p0': _num1.format(v)});
    case _Unit.count:
      return _money0.format(v);
    case _Unit.money:
      return v.abs() >= 100000
          ? tr('{p0}ك', {'p0': _money0.format(v / 1000)})
          : _money0.format(v);
  }
}

/// نافذةُ القراءة — اثنا عشر شهراً تنتهي بالشهر الجاري.
({DateTime from, DateTime to}) _window() {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month + 1, 1);
  return (from: DateTime(now.year, now.month - 11, 1), to: end);
}

/// 🔴 **النطاقُ يُمرَّر — لا يُفترَض.**
///
/// `getMonthlyPerformanceSeries` تحمل مرشِّحَ الحصر منذ Spec 149 B12‑5a، وذاك
/// البندُ يقول نصّاً إنّ توصيلَ الشاشات «‏B12‑5b» يأتي منفصلاً — ولم يأتِ لهذه
/// الشاشة. فكانت تُنادى بلا `allowedBranchIds` إطلاقاً، ومديرُ فرعٍ محصورٌ يرى
/// **أرقامَ الشركة كلِّها** على كلّ بطاقةٍ وكلّ عمودٍ في الرسم.
///
/// و`null` = وصولٌ كامل، `{}` = فشلٌ مقفول — نفسُ عقدِ `BranchScope`.
final _seriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final w = _window();
  final scope = await ref.watch(branchScopeProvider.future);
  return ref.watch(reportingRepositoryProvider).getMonthlyPerformanceSeries(
        from: w.from,
        to: w.to,
        allowedBranchIds: scope.hasFullAccess ? null : scope.allowedBranchIds,
      );
});

/// نقطةٌ شهريّةٌ بكلّ مؤشّراتها — مقيسةٌ من صفوف الاستعلام لا مكتوبة.
class _MonthPoint {
  const _MonthPoint({
    required this.date,
    required this.sales,
    required this.salesExTax,
    required this.invoices,
    required this.cogs,
    required this.expenses,
  });

  final DateTime date;

  /// الإيرادُ **شاملَ الضريبة** — بطاقةُ المبيعات، ويطابق تقريرَ المبيعات.
  final double sales;

  /// الإيرادُ **خالياً من الضريبة** — مقامُ الهامش وحدَه.
  final double salesExTax;

  final int invoices;
  final double cogs;
  final double expenses;

  /// هامشُ الربح الإجماليّ نسبةً — والقسمةُ على صفرٍ تعطي صفراً لا `NaN`.
  ///
  /// 🔴 **المقامُ خالٍ من الضريبة.** كان `sales` شاملَها بينما `cogs` تكلفةٌ
  /// خالصة، فالهامشُ يُنفَخ بنسبةِ الضريبة على كلّ صنف: تكلفةٌ ١٠٠ وبيعٌ ١٢٥
  /// وضريبةُ ١٦٪ ⇒ كان يُعرَض ٣١٪ والصحيحُ ٢٠٪. وأيُّ قرارِ تسعيرٍ اتُّخذ على
  /// تلك البطاقة يستحقّ المراجعة.
  double get margin =>
      salesExTax > 0 ? (salesExTax - cogs) / salesExTax * 100 : 0;

  /// متوسّطُ قيمة الفاتورة.
  double get basket => invoices > 0 ? sales / invoices : 0;

  double valueOf(String metricId) => switch (metricId) {
        'margin' => margin,
        'basket' => basket,
        'invoices' => invoices.toDouble(),
        'expenses' => expenses,
        _ => sales,
      };
}

List<_MonthPoint> _parse(List<Map<String, dynamic>> rows) {
  final out = <_MonthPoint>[];
  for (final r in rows) {
    final ym = r['ym'] as String?;
    if (ym == null || ym.length < 7) continue;
    final year = int.tryParse(ym.substring(0, 4));
    final month = int.tryParse(ym.substring(5, 7));
    if (year == null || month == null) continue;
    final sales = (r['net_sales'] as num?)?.toDouble() ?? 0;
    out.add(_MonthPoint(
      date: DateTime(year, month, 1),
      sales: sales,
      // السقوطُ إلى `sales` لا إلى صفر: غيابُ المفتاح يعني «لا ضريبة» —
      // والصفرُ كان سيقلب هامشاً حقيقيّاً إلى ٠٪ صامتاً.
      salesExTax: (r['net_sales_ex_tax'] as num?)?.toDouble() ?? sales,
      invoices: (r['invoice_count'] as num?)?.toInt() ?? 0,
      cogs: (r['cogs'] as num?)?.toDouble() ?? 0,
      expenses: (r['expenses'] as num?)?.toDouble() ?? 0,
    ));
  }
  return out;
}

class AnalyticsPicposScreen extends ConsumerStatefulWidget {
  const AnalyticsPicposScreen({super.key});

  @override
  ConsumerState<AnalyticsPicposScreen> createState() =>
      _AnalyticsPicposScreenState();
}

class _AnalyticsPicposScreenState
    extends ConsumerState<AnalyticsPicposScreen> {
  String _focus = 'sales';
  int _range = 12;
  bool _smooth = false;

  @override
  Widget build(BuildContext context) {
    final series = ref.watch(_seriesProvider);

    return PicPosScreenScaffold(
      title: tr('التحليلات'),
      subtitle:
          tr('اتجاه ومقارنة فترات وتنبؤ بالانحدار الخطي — كل رقم محتسب من السلسلة الزمنية لا مُدخَل'),
      icon: PhosphorIconsBold.chartLineUp,
      headerActions: [
        _rangeToggle(),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _smooth = !_smooth),
          icon: const Icon(PhosphorIconsBold.waves, size: 15),
          label: Text(_smooth ? tr('تنعيم ٣ أشهر') : tr('القيم الخام')),
          style: _smooth
              ? OutlinedButton.styleFrom(
                  foregroundColor: context.picposBrandInk,
                  side: BorderSide(color: context.picposBrandInk, width: 1.5),
                )
              : null,
        ),
      ],
      body: series.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // العارضُ يبتلع رمْيَ SQL في بطاقة — فالإخفاقُ يُقال صراحةً بدل أن
        // تبدو الشاشةُ عاملةً على سلسلةٍ فارغة.
        error: (e, _) => PicPosEmptyState(
          icon: PhosphorIconsBold.warningOctagon,
          title: tr('تعذّر حسابُ السلسلة الزمنيّة'),
          hint: '$e',
        ),
        data: (rows) {
          final all = _parse(rows);
          if (all.length < 2) {
            return  PicPosEmptyState(
              icon: PhosphorIconsBold.chartLineUp,
              title: tr('لا تكفي البياناتُ لرسم اتجاه'),
              hint: 'الانحدارُ الخطّيُّ يحتاج شهرَين على الأقلّ فيهما حركة. '
                  'سجِّلْ مبيعاتٍ ثمّ عُدْ.',
            );
          }
          return _body(all);
        },
      ),
    );
  }

  Widget _rangeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: context.picposHairline, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final n in [6, 9, 12])
            InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => setState(() => _range = n),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _range == n ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  n == 12 ? tr('١٢ شهراً') : tr('{p0} أشهر', {'p0': _ar(n)}),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _range == n ? Colors.white : context.picposMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════

  /// السلسلةُ المعروضةُ لمؤشّرٍ بعد قصِّ النافذة وتنعيمها.
  ///
  /// ⚠️ التنعيمُ يُقصّر السلسلة (‏راجع شرحَ الرأس)، فتُعاد أسماءُ الشهور مع
  /// النقاط دائماً كزوجٍ واحد — فلا يمكن أن ينزاح عمودٌ عن شهره.
  ({List<TimeSeriesPoint> points, List<String> labels}) _seriesFor(
    List<_MonthPoint> all,
    String metricId,
  ) {
    final window = all.length <= _range
        ? all
        : all.sublist(all.length - _range);
    var points = [
      for (final p in window)
        TimeSeriesPoint(date: p.date, value: p.valueOf(metricId))
    ];
    if (_smooth) {
      points = PerformanceAnalyticsService.movingAverage(points, 3);
    }
    return (
      points: points,
      labels: [for (final p in points) _monthsAr[p.date.month - 1]],
    );
  }

  Widget _body(List<_MonthPoint> all) {
    final focus = _kMetrics.firstWhere((m) => m.id == _focus);
    final f = _seriesFor(all, _focus);
    final trend = PerformanceAnalyticsService.analyzeTrend(f.points);
    final forecast = f.points.isEmpty
        ? const <TimeSeriesPoint>[]
        : PerformanceAnalyticsService.forecast(f.points, 3);

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 20),
      children: [
        _metricCards(all),
        const SizedBox(height: 12),
        _chartCard(focus, f, trend, forecast),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final trendTable = _trendTable(all);
          final seasons = _seasonalityCard(all, focus);
          if (box.maxWidth < 1100) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [trendTable, const SizedBox(height: 12), seasons],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 155, child: trendTable),
              const SizedBox(width: 12),
              Expanded(flex: 100, child: seasons),
            ],
          );
        }),
        const SizedBox(height: 12),
        _readingCard(all),
      ],
    );
  }

  // ── بطاقاتُ المؤشّرات ───────────────────────────────────────────────────

  Widget _metricCards(List<_MonthPoint> all) {
    return LayoutBuilder(builder: (context, box) {
      final perRow = box.maxWidth < 900 ? 2 : 5;
      final w = (box.maxWidth - (perRow - 1) * 12) / perRow;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final m in _kMetrics)
            SizedBox(width: w, child: _metricCard(m, all)),
        ],
      );
    });
  }

  Widget _metricCard(_MetricDef m, List<_MonthPoint> all) {
    final s = _seriesFor(all, m.id);
    if (s.points.isEmpty) return const SizedBox.shrink();

    final last = s.points.last.value;
    final prev =
        s.points.length >= 2 ? s.points[s.points.length - 2].value : last;
    final delta = prev != 0 ? (last - prev) / prev * 100 : 0.0;
    // ارتفاعُ المصروف سيّئ، وارتفاعُ الباقي جيّد — فاللونُ يتبع المعنى لا
    // الإشارة.
    final good = m.inverse ? delta <= 0 : delta >= 0;
    final on = m.id == _focus;

    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => setState(() => _focus = m.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border.all(
              color: on ? context.picposBrandInk : context.picposHairline,
              width: 1.5),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(m.icon, size: 15, color: m.tint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(m.label,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: context.picposMuted),
                      overflow: TextOverflow.ellipsis),
                ),
                if (on)
                  Icon(PhosphorIconsBold.crosshairSimple,
                      size: 13, color: context.picposBrandInk),
              ],
            ),
            const SizedBox(height: 8),
            Text(_fmt(last, m.unit),
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, height: 1.1),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                    delta >= 0
                        ? PhosphorIconsBold.trendUp
                        : PhosphorIconsBold.trendDown,
                    size: 12,
                    color: good ? _ok : _err),
                const SizedBox(width: 6),
                Text(tr('{p0}{p1}٪', {'p0': delta >= 0 ? '+' : '', 'p1': _num1.format(delta)}),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: good ? _ok : _err)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(tr('عن {p0}', {'p0': _fmt(prev, m.unit)}),
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: context.picposMuted),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: LayoutBuilder(
                builder: (context, box) => TrendSparkline(
                  data: [for (final p in s.points) p.value],
                  width: box.maxWidth,
                  height: 34,
                  color: m.tint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── الرسمُ الرئيس ──────────────────────────────────────────────────────

  Widget _chartCard(
    _MetricDef focus,
    ({List<TimeSeriesPoint> points, List<String> labels}) f,
    TrendAnalysis trend,
    List<TimeSeriesPoint> forecast,
  ) {
    final actual = [for (final p in f.points) p.value];
    final projected = [for (final p in forecast) p.value];
    final top = [...actual, ...projected]
            .fold<double>(0, (a, b) => math.max(a, b)) *
        1.12;

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PicPosSectionHeader(
            title: tr('{p0} — الاتجاه والتنبؤ', {'p0': focus.label}),
            subtitle: '${_ar(f.points.length)} نقطة'
                '${_smooth ? ' · مُنعَّمة بمتوسط متحرك ٣ أشهر' : ' · قيم خام'}'
                ' · تنبؤ ٣ أشهر قادمة بالانحدار الخطي',
            icon: focus.icon,
          ),
          _ChartLegend(tint: focus.tint),
          const SizedBox(height: 12),
          SizedBox(
            height: 280,
            child: _TrendChart(
              actual: actual,
              projected: projected,
              labels: f.labels,
              top: top <= 0 ? 1 : top,
              tint: focus.tint,
              slope: trend.slope,
              // الانحدارُ يبدأ من قيمةٍ تُشتقّ من الميل والنهاية، فالخطُّ
              // يمرّ بالسلسلة نفسِها لا بمحورٍ مستقلّ.
              intercept: trend.endValue - trend.slope * (actual.length - 1),
              unit: focus.unit,
              grid: context.picposHairline,
              muted: context.picposMuted,
            ),
          ),
        ],
      ),
    );
  }

  // ── جدولُ الاتجاه ──────────────────────────────────────────────────────

  Widget _trendTable(List<_MonthPoint> all) {
    return PicPosDataTable(
      title: tr('تحليل الاتجاه لكل مؤشر'),
      subtitle:
          tr('الميل من الانحدار الخطي — والتنبؤ هو النقطة التالية على الخط'),
      minWidth: 820,
      columns:  [
        PicPosTableColumn(tr('المؤشر'), flex: 1.7),
        PicPosTableColumn(tr('البداية'), flex: 1.1, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('النهاية'), flex: 1.1, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('الميل / شهر'),
            flex: 1.2, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('التغير'), flex: 1.1, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('تنبؤ الشهر القادم'),
            flex: 1.4, align: PicPosCellAlign.end),
      ],
      rows: [
        for (final m in _kMetrics)
          () {
            final s = _seriesFor(all, m.id);
            final t = PerformanceAnalyticsService.analyzeTrend(s.points);
            final good = m.inverse ? t.changePercent <= 0 : t.changePercent >= 0;
            return PicPosTableRow(
              onTap: () => setState(() => _focus = m.id),
              cells: [
                PicPosTextCell(m.label,
                    sub: switch (t.direction) {
                      TrendDirection.up => tr('صاعد'),
                      TrendDirection.down => tr('هابط'),
                      TrendDirection.flat => tr('مستقر'),
                    },
                    icon: m.icon,
                    tint: m.tint),
                PicPosTextCell(_fmt(t.startValue, m.unit)),
                PicPosTextCell(_fmt(t.endValue, m.unit), bold: true),
                PicPosTextCell(
                  '${t.slope >= 0 ? '+' : '-'}${_fmt(t.slope.abs(), m.unit)}',
                  tint: (t.slope >= 0) == m.inverse ? _err : _ok,
                ),
                PicPosTextCell(
                  '${t.changePercent >= 0 ? '+' : ''}'
                  '${_num1.format(t.changePercent)}٪',
                  tint: good ? _ok : _err,
                ),
                PicPosTextCell(_fmt(t.forecastNext ?? t.endValue, m.unit),
                    bold: true),
              ],
            );
          }(),
      ],
    );
  }

  // ── الموسميّة ──────────────────────────────────────────────────────────

  Widget _seasonalityCard(List<_MonthPoint> all, _MetricDef focus) {
    final s = _seriesFor(all, focus.id);
    final months = {for (final p in s.points) p.date.month}.toList()..sort();

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
           PicPosSectionHeader(
            title: tr('مُعامل الموسمية'),
            subtitle: tr('متوسط الشهر ÷ متوسط السلسلة — فوق ١.٠ يعني موسماً مرتفعاً'),
            icon: PhosphorIconsBold.calendarHeart,
          ),
          if (months.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(tr('لا نقاطَ تكفي لحساب موسميّة'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.picposMuted)),
            )
          else
            for (final month in months)
              () {
                final idx = PerformanceAnalyticsService.seasonalityIndex(
                    s.points, month);
                if (idx == null) return const SizedBox.shrink();
                return _SeasonBar(
                  label: _monthsAr[month - 1],
                  index: idx,
                  track: context.picposField,
                  muted: context.picposMuted,
                );
              }(),
        ],
      ),
    );
  }

  // ── القراءةُ النصّيّة ───────────────────────────────────────────────────

  Widget _readingCard(List<_MonthPoint> all) {
    final sales = PerformanceAnalyticsService.analyzeTrend(
        _seriesFor(all, 'sales').points);
    final exp = PerformanceAnalyticsService.analyzeTrend(
        _seriesFor(all, 'expenses').points);

    // الميلُ نسبةً من نقطة البداية — فيقارَن مؤشّران مختلفا المقياس.
    final salesGrowth =
        sales.startValue != 0 ? sales.slope / sales.startValue * 100 : 0.0;
    final expGrowth =
        exp.startValue != 0 ? exp.slope / exp.startValue * 100 : 0.0;
    final healthy = salesGrowth > expGrowth;

    return PicPosContentCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: (healthy ? _ok : _err).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
                healthy
                    ? PhosphorIconsBold.checkCircle
                    : PhosphorIconsBold.warning,
                size: 22,
                color: healthy ? _ok : _err),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  healthy
                      ? tr('النمو يسبق المصروف — الاتجاه سليم')
                      : tr('المصروف ينمو أسرع من المبيعات'),
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'ميل المبيعات ${_num1.format(salesGrowth)}٪ شهرياً مقابل '
                  '${_num1.format(expGrowth)}٪ للمصروفات التشغيلية — '
                  'كلاهما محسوبٌ بالانحدار الخطي على '
                  '${_ar(_seriesFor(all, 'sales').points.length)} نقطة.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      fontWeight: FontWeight.w600,
                      color: context.picposMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// الرسم
// ═══════════════════════════════════════════════════════════════════════════

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.tint});

  final Color tint;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, Widget swatch) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch,
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.picposMuted)),
          ],
        );

    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        item(tr('القيمة الفعلية'),
            Container(width: 14, height: 14, color: tint)),
        item(
            tr('خط الانحدار'),
            Container(
                width: 14,
                height: 2.5,
                color: _err)),
        item(
            tr('التنبؤ'),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(color: tint, width: 1.5),
              ),
            )),
      ],
    );
  }
}

/// أعمدةُ السلسلة الفعليّة والمتنبَّأِ بها، وفوقَها خطُّ الانحدار.
class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.actual,
    required this.projected,
    required this.labels,
    required this.top,
    required this.tint,
    required this.slope,
    required this.intercept,
    required this.unit,
    required this.grid,
    required this.muted,
  });

  final List<double> actual;
  final List<double> projected;
  final List<String> labels;
  final double top;
  final Color tint;
  final double slope;
  final double intercept;
  final _Unit unit;
  final Color grid;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final cols = actual.length + projected.length;
    final yTicks = [for (var i = 4; i >= 0; i--) _fmt(top * i / 4, unit)];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 66,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 26),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final t in yTicks)
                  Text(t,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: muted)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Stack(
            children: [
              // شبكةُ الخطوط الأفقيّة.
              Positioned.fill(
                bottom: 26,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Container(height: 1, color: grid),
                  ],
                ),
              ),
              // خطُّ الانحدار — يُرسَم فوقَ الشبكة وتحتَ الأعمدة.
              Positioned.fill(
                bottom: 26,
                child: CustomPaint(
                  painter: _RegressionPainter(
                    cols: cols,
                    top: top,
                    slope: slope,
                    intercept: intercept,
                  ),
                ),
              ),
              // الأعمدة. في RTL يرتّبها `Row` من اليمين، فالزمنُ يمشي كما
              // في التصميم بلا عكسٍ يدويّ.
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < cols; i++)
                    Expanded(
                      child: _bar(
                        context,
                        value: i < actual.length
                            ? actual[i]
                            : projected[i - actual.length],
                        label: i < labels.length
                            ? labels[i]
                            : '+${_ar(i - actual.length + 1)}',
                        forecast: i >= actual.length,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context,
      {required double value,
      required String label,
      required bool forecast}) {
    final fraction = (value / top).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(_fmt(value, unit),
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: forecast ? tint : muted),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              return Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: math.max(3, box.maxHeight * fraction),
                  decoration: BoxDecoration(
                    color: forecast ? Colors.transparent : tint,
                    border: forecast
                        ? Border.all(color: tint, width: 1.5)
                        : null,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(7)),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 16,
            child: Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: forecast ? tint : muted),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// خطُّ الانحدار الأحمرُ المتقطّع.
///
/// ⚠️ **يُعكَس المحورُ صراحةً.** `Row` في RTL يضع العمودَ صفراً على اليمين،
/// أمّا `CustomPainter` فيرسم بإحداثيّاتٍ خامٍ لا تعرف الاتّجاه. فلولا هذا
/// العكسُ لوقف الخطُّ مقلوباً فوقَ أعمدةٍ صحيحة — وهو أسوأُ من غيابه لأنّه
/// يبدو صحيحاً.
class _RegressionPainter extends CustomPainter {
  const _RegressionPainter({
    required this.cols,
    required this.top,
    required this.slope,
    required this.intercept,
  });

  final int cols;
  final double top;
  final double slope;
  final double intercept;

  @override
  void paint(Canvas canvas, Size size) {
    if (cols < 2 || top <= 0) return;

    final paint = Paint()
      ..color = _err
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    Offset at(int i) {
      final y = size.height - (intercept + slope * i) / top * size.height;
      final x = (cols - 1 - i + 0.5) / cols * size.width; // ← العكس
      return Offset(x, y.clamp(0.0, size.height));
    }

    // شرطاتٌ بطول ٧ وفجوةٌ ٥ — كما في التصميم.
    const dash = 7.0, gap = 5.0;
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < cols; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_RegressionPainter old) =>
      old.cols != cols ||
      old.top != top ||
      old.slope != slope ||
      old.intercept != intercept;
}

/// شريطُ موسميّةٍ ثنائيُّ الاتّجاه حول مركزٍ يمثّل ١٫٠٠.
class _SeasonBar extends StatelessWidget {
  const _SeasonBar({
    required this.label,
    required this.index,
    required this.track,
    required this.muted,
  });

  final String label;
  final double index;
  final Color track;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final dev = (index - 1) * 100; // انحرافٌ مئويٌّ عن المتوسّط
    final half = math.min(dev.abs() * 2.6, 49.0);
    final fill = dev >= 1 ? _ok : (dev <= -1 ? _err : muted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.picposText),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: SizedBox(
              height: 16,
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: track,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // خطُّ المركز — ١٫٠٠.
                    Positioned(
                      left: w / 2 - 0.75,
                      top: 0,
                      bottom: 0,
                      child: Container(
                          width: 1.5,
                          color: muted.withValues(alpha: 0.5)),
                    ),
                    Positioned(
                      left: dev >= 0 ? w / 2 : w / 2 - w * half / 100,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: math.max(w * half / 100, 2),
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            child: Text(index.toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: fill)),
          ),
        ],
      ),
    );
  }
}
