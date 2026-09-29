import 'package:ural_erp/core/i18n/tr.dart';
// تعريفاتُ التقارير السبعةِ التي كانت على شاشاتٍ نائبة.
//
// ═══ القاعدةُ الحاكمةُ لهذا الملفّ ═══
//
// ⚠️ **كلُّ رقمٍ هنا من استعلام.** التصميمُ يكتب أرقامَه نصّاً لأنّه صورة:
// «٢٢.٧٪» و«٣٨٤٢ عملية» و«٤٢٠ عميلاً». ونقلُها كما هي كان سيُنتج سبعَ
// شاشاتٍ تبدو حيّةً وتكذب — وذلك أسوأُ من مدخلٍ نائبٍ يقول صراحةً إنّه غيرُ
// جاهز. فما لا يسنده استعلامٌ لا يُرسَم.
//
// ⚠️ **وما اختلف عن التصميم مذكورٌ بسببه** في تعليقٍ فوقَ موضعه — لا يُترَك
// الفرقُ ليُكتشَف لاحقاً فيُظنّ سهواً.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_report_chart.dart';
import 'report_view_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// أدواتٌ مشتركة
// ═══════════════════════════════════════════════════════════════════════════

String _money(double v) =>
    '${v.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}';

String _pct(double v) => tr('{p0}٪', {'p0': v.toStringAsFixed(1)});

String _int(int v) => v.toString();

/// نطاقُ الفروع المسموحُ به. `null` = وصولٌ كامل — وهو عقدُ
/// `_buildAuthScopeFilter` نفسُه في طبقة البيانات.
Future<Set<int>?> _scope(WidgetRef ref) async {
  final scope = await ref.read(branchScopeProvider.future);
  return scope.hasFullAccess ? null : scope.allowedBranchIds;
}

/// نسبةٌ لا تُقسَم على صفر.
double _ratio(double part, double whole) => whole == 0 ? 0 : part / whole * 100;

/// أيّامٌ منذ [when] حتى نهاية المدى — حداثةُ التعامل.
int _daysSince(DateTime? when, DateTime end) =>
    when == null ? 9999 : end.difference(when).inDays.abs();

/// تسميةُ مدىً قصيرةٌ للأعمدة والرسوم.
String _dayLabel(String iso) {
  // `getDailySalesForRange` يعود بـ`date` نصّاً بصيغة `YYYY-MM-DD`.
  final parts = iso.split('-');
  return parts.length == 3 ? '${parts[2]}/${parts[1]}' : iso;
}

const _tintOk = AppColors.success;
const _tintWarn = AppColors.warning;
const _tintErr = AppColors.error;
const _tintBrand = AppColors.primary;

/// لونُ الهامش بحسب صحّته — نفسُ عتبات التصميم (‏سالبٌ · أقلُّ من ٥٪ · سليم).
Color _marginTint(double margin) =>
    margin < 0 ? _tintErr : (margin < 5 ? _tintWarn : _tintOk);

// ═══════════════════════════════════════════════════════════════════════════
// ١) هامش الربح — `profit_margin`
// ═══════════════════════════════════════════════════════════════════════════

/// المصدر: `REPORTS.profit` في التصميم — تبويبتا «التصنيفات» و«هامش الربح».
///
/// ⚠️ **الرسمُ هامشٌ لكلّ تصنيفٍ لا هامشٌ شهريّ.** التصميمُ يرسم ستّةَ أشهر،
/// وحسابُ الهامش الشهريِّ يقتضي استعلامَ تكلفةٍ لكلّ شهرٍ على حدة — ستّةَ
/// استعلاماتٍ إضافيّةً لرسمٍ واحد. والبيانةُ المتاحةُ من نفس الاستعلام
/// (‏الهامشُ لكلّ تصنيف) تجيب السؤالَ نفسَه: أينَ يضيع الربح.
///
/// وتبويبةُ «هامش الربح» **أصنافٌ لا تصنيفات** كما في التصميم (أمرُ المالك
/// 2026-08-26). وكان الظنُّ أنّ تكلفةَ سطرِ البيع غيرُ متاحة، والمقيسُ أنّها
/// موجودةٌ في `sales_invoice_items.cost_price` — لقطةُ التكلفة **وقتَ البيع**
/// — فلم تكن فجوةَ بيانات بل تجميعاً على `product_id` بدل `category_id`.
///
/// ⚠️ **والتكلفةُ لقطةُ وقتِ البيع لا تكلفةُ اليوم**: صنفٌ ارتفعت تكلفتُه
/// اليومَ لم يكن يبيع بخسارةٍ الشهرَ الماضي، وتقييمُه بتكلفة اليوم يتّهمه.
PicPosReportDefinition profitMarginReport() => PicPosReportDefinition(
      id: 'profit_margin',
      title: tr('هامش الربح'),
      subtitle: tr('تكلفةُ المبيعات وصافي الربح — تصنيفاً وصنفاً'),
      icon: PhosphorIconsBold.percent,
      tabs: [
        PicPosReportTabDef(
          id: 'cats',
          label: tr('التصنيفات'),
          icon: PhosphorIconsBold.chartPieSlice,
          note: tr('الربحُ = المبيعات − تكلفة البضاعة المباعة، لكلّ تصنيف.'),
          load: (ref, range) async {
            final rows = await _categoryRows(ref, range);
            if (rows.isEmpty) return const PicPosReportTabContent();
            final sales = rows.fold<double>(0, (a, r) => a + r.totalSales);
            final cost = rows.fold<double>(0, (a, r) => a + r.totalCost);
            final profit = rows.fold<double>(0, (a, r) => a + r.profit);
            return PicPosReportTabContent(
              badge: _int(rows.length),
              kpis: [
                PicPosHubKpi(
                  icon: PhosphorIconsBold.receipt,
                  label: tr('إجمالي المبيعات'),
                  value: _money(sales),
                  tint: _tintBrand,
                  vs: tr('في المدى المختار'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.package,
                  label: tr('تكلفة البضاعة المباعة'),
                  value: _money(cost),
                  tint: _tintWarn,
                  vs: tr('من دفتر التكلفة'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.trendUp,
                  label: tr('صافي الربح'),
                  value: _money(profit),
                  tint: profit >= 0 ? _tintOk : _tintErr,
                  vs: tr('المبيعات ناقص التكلفة'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.percent,
                  label: tr('الهامش الإجمالي'),
                  value: _pct(_ratio(profit, sales)),
                  tint: _marginTint(_ratio(profit, sales)),
                  vs: tr('الربح من المبيعات'),
                ),
              ],
              chart: PicPosReportChart(
                title: tr('المبيعات والتكلفة لكلّ تصنيف'),
                subtitle: tr('{p0} تصنيفاً في المدى', {'p0': rows.length}),
                series:  [
                  PicPosChartSeries(label: tr('المبيعات'), color: _tintBrand),
                  PicPosChartSeries(label: tr('التكلفة'), color: _tintWarn),
                ],
                bars: [
                  for (final r in rows.take(8))
                    PicPosChartBar(
                      label: r.categoryName,
                      value: r.totalSales,
                      display: r.totalSales.toStringAsFixed(0),
                      secondValue: r.totalCost,
                    ),
                ],
              ),
              table: PicPosDataTable(
                title: tr('الربحُ لكلّ تصنيف'),
                subtitle: tr('مرتَّبةً بالمبيعات تنازليّاً'),
                columns:  [
                  PicPosTableColumn(tr('التصنيف'), flex: 2.2),
                  PicPosTableColumn(tr('المبيعات'),
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('التكلفة'),
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('الربح'),
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('الهامش'), flex: 1.4),
                ],
                rows: [
                  for (final r in rows)
                    PicPosTableRow(cells: [
                      PicPosTextCell(r.categoryName,
                          icon: PhosphorIconsBold.tag),
                      PicPosTextCell(_money(r.totalSales)),
                      PicPosTextCell(_money(r.totalCost)),
                      PicPosTextCell(_money(r.profit)),
                      PicPosBarCell(
                        _pct(r.margin),
                        (r.margin / 100).clamp(0.0, 1.0),
                        _marginTint(r.margin),
                      ),
                    ]),
                ],
                totals: [
                  tr('{p0} تصنيفاً', {'p0': rows.length}),
                  _money(sales),
                  _money(cost),
                  _money(profit),
                  _pct(_ratio(profit, sales)),
                ],
              ),
            );
          },
        ),
        PicPosReportTabDef(
          id: 'margin',
          label: tr('هامش الربح'),
          icon: PhosphorIconsBold.percent,
          note: 'الأصنافُ التي هامشُها سالبٌ أو أقلُّ من ٥٪ — تحتاج مراجعةَ سعر. '
              'والتكلفةُ لقطةُ **وقتِ البيع** لا تكلفةُ اليوم.',
          load: (ref, range) async {
            final repo = ref.read(reportingRepositoryProvider);
            final all = await repo.getProductProfitReport(
              from: range.start,
              to: range.end,
              allowedBranchIds: await _scope(ref),
            );
            if (all.isEmpty) return const PicPosReportTabContent();
            final weak = all.where((r) => r.margin < 5).toList()
              ..sort((a, b) => a.margin.compareTo(b.margin));
            final negative = all.where((r) => r.margin < 0).length;
            final best = all.reduce((a, b) => a.margin >= b.margin ? a : b);
            final worst = all.reduce((a, b) => a.margin <= b.margin ? a : b);
            final sales = all.fold<double>(0, (a, r) => a + r.totalSales);
            final profit = all.fold<double>(0, (a, r) => a + r.profit);
            return PicPosReportTabContent(
              badge: weak.isEmpty ? null : _int(weak.length),
              kpis: [
                PicPosHubKpi(
                  icon: PhosphorIconsBold.percent,
                  label: tr('الهامش الإجمالي'),
                  value: _pct(_ratio(profit, sales)),
                  tint: _marginTint(_ratio(profit, sales)),
                  vs: tr('على {p0} صنفاً بيع', {'p0': all.length}),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.arrowUp,
                  label: tr('أعلى هامش'),
                  value: _pct(best.margin),
                  tint: _tintOk,
                  vs: best.productName,
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.arrowDown,
                  label: tr('أدنى هامش'),
                  value: _pct(worst.margin),
                  tint: _tintErr,
                  vs: worst.productName,
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.warning,
                  label: tr('أصنافٌ بهامشٍ سالب'),
                  value: _int(negative),
                  tint: negative > 0 ? _tintErr : _tintOk,
                  vs: tr('تبيع بخسارة'),
                ),
              ],
              chart: PicPosReportChart(
                title: tr('أضعفُ الأصناف هامشاً'),
                subtitle: tr('النسبةُ المئويّةُ من المبيعات'),
                series:  [
                  PicPosChartSeries(label: tr('الهامش'), color: _tintBrand),
                ],
                bars: [
                  // الأضعفُ أوّلاً — الرسمُ يجيب «أين تضيع النقود»، فصدارةُ
                  // الأصناف الرابحةِ فيه تدفع المطلوبَ خارجَ الصورة.
                  for (final r in (weak.isEmpty ? all : weak).take(8))
                    PicPosChartBar(
                      label: r.productName,
                      // السالبُ يُرسَم بقيمته المطلقة ونصُّه يحمل الإشارة،
                      // فالعمودُ لا ينزل تحت المحور وتبقى الإشارةُ مقروءة.
                      value: r.margin,
                      display: _pct(r.margin),
                    ),
                ],
              ),
              table: PicPosDataTable(
                title: tr('أصنافٌ تحتاج مراجعةَ سعر'),
                subtitle: tr('هامشٌ أقلُّ من ٥٪ أو سالب'),
                emptyLabel: tr('لا صنفَ هامشُه دون ٥٪ — كلُّها سليمة'),
                columns:  [
                  PicPosTableColumn(tr('الصنف'), flex: 2.4),
                  PicPosTableColumn(tr('متوسّطُ التكلفة'),
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('متوسّطُ البيع'),
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('الهامش'), flex: 1.4),
                  PicPosTableColumn(tr('المتاح'),
                      flex: 1.0, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('الحالة'), flex: 1.2),
                ],
                rows: [
                  for (final r in weak)
                    PicPosTableRow(cells: [
                      PicPosTextCell(r.productName,
                          sub: r.categoryName,
                          icon: PhosphorIconsBold.package,
                          tint: _marginTint(r.margin)),
                      PicPosTextCell(_money(r.averageCost)),
                      PicPosTextCell(_money(r.averagePrice)),
                      PicPosBarCell(
                        _pct(r.margin),
                        (r.margin / 100).clamp(0.0, 1.0),
                        _marginTint(r.margin),
                      ),
                      PicPosTextCell(r.currentStock.toStringAsFixed(0)),
                      PicPosPillCell(
                        r.margin < 0 ? tr('يبيع بخسارة') : tr('هامشٌ ضعيف'),
                        _marginTint(r.margin),
                      ),
                    ]),
                ],
                totals: [
                  tr('{p0} صنفاً', {'p0': weak.length}),
                  '',
                  '',
                  '',
                  weak
                      .fold<double>(0, (a, r) => a + r.currentStock)
                      .toStringAsFixed(0),
                  '',
                ],
              ),
            );
          },
        ),
      ],
    );

Future<List<CategoryProfitRow>> _categoryRows(WidgetRef ref, DateTimeRange range) async {
  final repo = ref.read(reportingRepositoryProvider);
  final rows = await repo.getCategoryProfitReport(
    from: range.start,
    to: range.end,
    allowedBranchIds: await _scope(ref),
  );
  return rows.toList()
    ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
}

// ═══════════════════════════════════════════════════════════════════════════
// ٢) تحليل سلوك العملاء — `cust_behavior`   و   ٣) الموردين — `sup_behavior`
// ═══════════════════════════════════════════════════════════════════════════

/// التقريران بنيةً واحدةً على جدولَين — فتعريفٌ واحدٌ بمعاملٍ يفرّقهما.
/// نسخُهما لكان نسختَين تنحرفان بأوّل تعديلِ عمود.
PicPosReportDefinition partyBehaviorReport({required bool suppliers}) {
  final who = suppliers ? tr('المورّد') : tr('العميل');
  final whoPlural = suppliers ? tr('الموردين') : tr('العملاء');
  final valueLabel = suppliers ? tr('المشتريات') : tr('المبيعات');
  return PicPosReportDefinition(
    id: suppliers ? 'sup_behavior' : 'cust_behavior',
    title: tr('تحليل سلوك {whoPlural}', {'whoPlural': whoPlural}),
    subtitle: tr('التكرارُ والقيمةُ وآخرُ تعاملٍ لكلّ {who}', {'who': who}),
    icon: suppliers ? PhosphorIconsBold.truck : PhosphorIconsBold.users,
    tabs: [
      PicPosReportTabDef(
        id: 'list',
        label: whoPlural,
        icon: PhosphorIconsBold.users,
        note:
            tr('الفواتيرُ المحذوفةُ والمرتجعاتُ مستبعَدة، والتعاملُ بلا {who} مسجَّلٍ لا يُحتسَب.', {'who': who}),
        load: (ref, range) async {
          final rows = await _partyRows(ref, range, suppliers: suppliers);
          if (rows.isEmpty) return const PicPosReportTabContent();
          final total = rows.fold<double>(0, (a, r) => a + r.totalValue);
          final unpaid = rows.fold<double>(0, (a, r) => a + r.unpaidValue);
          final invoices = rows.fold<int>(0, (a, r) => a + r.invoiceCount);
          return PicPosReportTabContent(
            badge: _int(rows.length),
            kpis: [
              PicPosHubKpi(
                icon: PhosphorIconsBold.users,
                label: tr('{whoPlural} المتعاملون', {'whoPlural': whoPlural}),
                value: _int(rows.length),
                tint: _tintBrand,
                vs: tr('لهم فاتورةٌ في المدى'),
              ),
              PicPosHubKpi(
                icon: PhosphorIconsBold.receipt,
                label: tr('إجمالي {valueLabel}', {'valueLabel': valueLabel}),
                value: _money(total),
                tint: _tintOk,
                vs: tr('{invoices} فاتورة', {'invoices': invoices}),
              ),
              PicPosHubKpi(
                icon: PhosphorIconsBold.calculator,
                label: tr('متوسّطُ الفاتورة'),
                value: _money(invoices == 0 ? 0 : total / invoices),
                tint: _tintBrand,
                vs: tr('على كلّ الفواتير'),
              ),
              PicPosHubKpi(
                icon: PhosphorIconsBold.warning,
                label: tr('غيرُ المسدَّد'),
                value: _money(unpaid),
                tint: unpaid > 0 ? _tintWarn : _tintOk,
                // ⚠️ المتبقّي **في هذا المدى** لا رصيدُ الطرف الكلّيّ —
                // فالرصيدُ يحمل فواتيرَ أقدمَ ومقبوضاتٍ لاحقة.
                vs: tr('من فواتير المدى وحدَها'),
              ),
            ],
            chart: PicPosReportChart(
              title: tr('أعلى {whoPlural} قيمةً', {'whoPlural': whoPlural}),
              subtitle: tr('أعلى ثمانيةٍ في المدى'),
              series: [
                PicPosChartSeries(label: valueLabel, color: _tintBrand),
              ],
              bars: [
                for (final r in rows.take(8))
                  PicPosChartBar(
                    label: r.partyName,
                    value: r.totalValue,
                    display: r.totalValue.toStringAsFixed(0),
                  ),
              ],
            ),
            table: PicPosDataTable(
              title: tr('سلوكُ {whoPlural}', {'whoPlural': whoPlural}),
              subtitle: tr('مرتَّبةً بالقيمة تنازليّاً'),
              columns: [
                PicPosTableColumn(who, flex: 2.2),
                 PicPosTableColumn(tr('الفواتير'),
                    flex: 1.0, align: PicPosCellAlign.end),
                PicPosTableColumn(valueLabel,
                    flex: 1.4, align: PicPosCellAlign.end),
                 PicPosTableColumn(tr('متوسّطُ الفاتورة'),
                    flex: 1.3, align: PicPosCellAlign.end),
                 PicPosTableColumn(tr('غيرُ المسدَّد'),
                    flex: 1.3, align: PicPosCellAlign.end),
                 PicPosTableColumn(tr('آخرُ تعامل'), flex: 1.2),
              ],
              rows: [
                for (final r in rows)
                  PicPosTableRow(cells: [
                    PicPosTextCell(r.partyName,
                        icon: suppliers
                            ? PhosphorIconsBold.truck
                            : PhosphorIconsBold.user),
                    PicPosTextCell(_int(r.invoiceCount)),
                    PicPosTextCell(_money(r.totalValue)),
                    PicPosTextCell(_money(r.averageValue)),
                    PicPosTextCell(_money(r.unpaidValue)),
                    PicPosTextCell(_shortDate(r.lastInvoiceDate)),
                  ]),
              ],
              totals: [
                '${rows.length} $who',
                _int(invoices),
                _money(total),
                _money(invoices == 0 ? 0 : total / invoices),
                _money(unpaid),
                '',
              ],
            ),
          );
        },
      ),
    ],
  );
}

String _shortDate(DateTime? d) => d == null
    ? '—'
    : '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

Future<List<PartyPeriodAggregateRow>> _partyRows(
  WidgetRef ref,
  DateTimeRange range, {
  required bool suppliers,
}) async {
  final repo = ref.read(reportingRepositoryProvider);
  final scope = await _scope(ref);
  return suppliers
      ? repo.getSupplierPeriodAggregates(
          from: range.start, to: range.end, allowedBranchIds: scope)
      : repo.getCustomerPeriodAggregates(
          from: range.start, to: range.end, allowedBranchIds: scope);
}

// ═══════════════════════════════════════════════════════════════════════════
// ٤) تقسيم العملاء (RFM) — `an_customers`
// ═══════════════════════════════════════════════════════════════════════════

/// شريحةُ RFM — تسميةٌ وحدُّها ولونُها.
typedef _Segment = ({String label, Color tint});

/// ⚠️ **الحدودُ تُحسَب من بيانات المدى نفسِه لا تُكتَب.**
///
/// تقسيمُ RFM القياسيُّ يعطي كلَّ بُعدٍ درجةً ١..٣ بحسب موقعِه من **أثلاثِ
/// التوزيع الفعليّ**. ولو كُتبت الحدودُ ثوابتَ («أكثرُ من ٥ فواتير = وفيّ»)
/// لصار التقريرُ يقول شيئاً عن الثوابت لا عن العملاء: متجرٌ يبيع عشرَ
/// فواتيرَ في الشهر يظهر كلُّ عملائه «نائمين»، وآخرُ يبيع ألفاً يظهر كلُّهم
/// «أوفياء».
///
/// والدرجةُ تُقلَب في الحداثة: أيّامٌ أقلُّ = درجةٌ أعلى.
int _score(double value, List<double> sortedAsc, {required bool inverted}) {
  if (sortedAsc.isEmpty) return 2;
  double at(double q) {
    final i = ((sortedAsc.length - 1) * q).round();
    return sortedAsc[i];
  }

  final low = at(1 / 3), high = at(2 / 3);
  final raw = value <= low ? 1 : (value <= high ? 2 : 3);
  return inverted ? 4 - raw : raw;
}

_Segment _segmentOf(int r, int f, int m) {
  // القاعدةُ مذكورةٌ بنصّها في سطر ملاحظة التبويبة كي يقرأها المشغّل.
  if (r >= 3 && f + m >= 5) return (label: tr('الأوفياء'), tint: _tintOk);
  if (r >= 3) return (label: tr('نشِطون'), tint: AppColors.info);
  if (r == 2 && f + m >= 4) return (label: tr('معرَّضون للفقد'), tint: _tintWarn);
  if (r <= 1 && f + m >= 4) return (label: tr('ثمينون نائمون'), tint: _tintErr);
  return (label: tr('نائمون'), tint: AppColors.textPrimary);
}

PicPosReportDefinition customerSegmentsReport() => PicPosReportDefinition(
      id: 'an_customers',
      title: tr('تقسيم العملاء (RFM)'),
      subtitle: tr('الحداثةُ والتكرارُ والقيمةُ — ثلاثُ درجاتٍ لكلّ عميل'),
      icon: PhosphorIconsBold.chartDonut,
      tabs: [
        PicPosReportTabDef(
          id: 'seg',
          label: tr('التقسيم'),
          icon: PhosphorIconsBold.chartDonut,
          note:
              'الدرجاتُ ١..٣ من أثلاثِ توزيع المدى نفسِه — لا من حدودٍ ثابتة. '
              'حداثةٌ أقلُّ يوماً = درجةٌ أعلى.',
          load: (ref, range) async {
            final rows = await _partyRows(ref, range, suppliers: false);
            if (rows.isEmpty) return const PicPosReportTabContent();

            final recency = [
              for (final r in rows)
                _daysSince(r.lastInvoiceDate, range.end).toDouble()
            ]..sort();
            final freq = [for (final r in rows) r.invoiceCount.toDouble()]
              ..sort();
            final money = [for (final r in rows) r.totalValue]..sort();

            final scored = [
              for (final r in rows)
                (
                  row: r,
                  days: _daysSince(r.lastInvoiceDate, range.end),
                  r: _score(
                      _daysSince(r.lastInvoiceDate, range.end).toDouble(),
                      recency,
                      inverted: true),
                  f: _score(r.invoiceCount.toDouble(), freq, inverted: false),
                  m: _score(r.totalValue, money, inverted: false),
                )
            ];

            final buckets = <String, ({int count, double value, Color tint})>{};
            for (final s in scored) {
              final seg = _segmentOf(s.r, s.f, s.m);
              final prev = buckets[seg.label];
              buckets[seg.label] = (
                count: (prev?.count ?? 0) + 1,
                value: (prev?.value ?? 0) + s.row.totalValue,
                tint: seg.tint,
              );
            }
            final ordered = buckets.entries.toList()
              ..sort((a, b) => b.value.value.compareTo(a.value.value));

            final loyal = buckets[tr('الأوفياء')]?.count ?? 0;
            final atRisk = (buckets[tr('معرَّضون للفقد')]?.count ?? 0) +
                (buckets[tr('ثمينون نائمون')]?.count ?? 0);
            final total = rows.fold<double>(0, (a, r) => a + r.totalValue);

            return PicPosReportTabContent(
              badge: _int(rows.length),
              kpis: [
                PicPosHubKpi(
                  icon: PhosphorIconsBold.users,
                  label: tr('عملاءُ المدى'),
                  value: _int(rows.length),
                  tint: _tintBrand,
                  vs: tr('لهم فاتورةٌ واحدةٌ فأكثر'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.star,
                  label: tr('الأوفياء'),
                  value: _int(loyal),
                  tint: _tintOk,
                  vs: _pct(_ratio(loyal.toDouble(), rows.length.toDouble())),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.warning,
                  label: tr('معرَّضون للفقد'),
                  value: _int(atRisk),
                  tint: atRisk > 0 ? _tintWarn : _tintOk,
                  vs: tr('حداثةٌ ضعيفةٌ وقيمةٌ عالية'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.receipt,
                  label: tr('قيمةُ المدى'),
                  value: _money(total),
                  tint: _tintBrand,
                  vs: tr('مجموعُ فواتير العملاء'),
                ),
              ],
              chart: PicPosReportChart(
                title: tr('العملاءُ حسب الشريحة'),
                subtitle: tr('العددُ في كلّ شريحة'),
                series:  [
                  PicPosChartSeries(label: tr('عملاء'), color: _tintBrand),
                ],
                bars: [
                  for (final e in ordered)
                    PicPosChartBar(
                      label: e.key,
                      value: e.value.count.toDouble(),
                      display: _int(e.value.count),
                    ),
                ],
              ),
              table: PicPosDataTable(
                title: tr('درجاتُ العملاء'),
                subtitle: tr('مرتَّبةً بالقيمة تنازليّاً'),
                columns:  [
                  PicPosTableColumn(tr('العميل'), flex: 2.2),
                  PicPosTableColumn(tr('آخرُ تعامل'),
                      flex: 1.2, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('الفواتير'),
                      flex: 1.0, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('القيمة'),
                      flex: 1.4, align: PicPosCellAlign.end),
                  const PicPosTableColumn('R·F·M', flex: 1.0),
                  PicPosTableColumn(tr('الشريحة'), flex: 1.5),
                ],
                rows: [
                  for (final s in scored)
                    PicPosTableRow(cells: [
                      PicPosTextCell(s.row.partyName,
                          icon: PhosphorIconsBold.user),
                      PicPosTextCell(
                          s.days >= 9999 ? '—' : tr('منذ {p0} يوماً', {'p0': s.days})),
                      PicPosTextCell(_int(s.row.invoiceCount)),
                      PicPosTextCell(_money(s.row.totalValue)),
                      PicPosTextCell('${s.r}·${s.f}·${s.m}'),
                      PicPosPillCell(
                        _segmentOf(s.r, s.f, s.m).label,
                        _segmentOf(s.r, s.f, s.m).tint,
                      ),
                    ]),
                ],
                totals: [
                  tr('{p0} عميلاً', {'p0': rows.length}),
                  '',
                  _int(rows.fold<int>(0, (a, r) => a + r.invoiceCount)),
                  _money(total),
                  '',
                  '',
                ],
              ),
            );
          },
        ),
      ],
    );

// ═══════════════════════════════════════════════════════════════════════════
// ٥) اتجاهات المبيعات — `an_sales`
// ═══════════════════════════════════════════════════════════════════════════

/// ⚠️ **الرسمُ يعرض آخرَ ١٤ يوماً من المدى** — أربعةٌ وثلاثون عموداً على
/// عرضٍ واحدٍ تصير خطوطاً بلا تسميات. والعددُ **مذكورٌ في وصف الرسم** ولا
/// يُقتَطع صامتاً؛ والجدولُ تحتَه يحمل المدى كاملاً.
PicPosReportDefinition salesTrendReport() => PicPosReportDefinition(
      id: 'an_sales',
      title: tr('تحليل المبيعات'),
      subtitle: tr('اتّجاهاتُ المبيعات وأنماطُها على الزمن'),
      icon: PhosphorIconsBold.chartLine,
      tabs: [
        PicPosReportTabDef(
          id: 'trend',
          label: tr('الاتجاه'),
          icon: PhosphorIconsBold.chartLine,
          note: tr('المبيعاتُ اليوميّةُ في المدى — المرتجعاتُ والمحذوفُ مستبعَدان.'),
          load: (ref, range) async {
            final repo = ref.read(reportingRepositoryProvider);
            final scope = await _scope(ref);
            final daily = await repo.getDailySalesForRange(
                from: range.start, to: range.end, allowedBranchIds: scope);
            final analytics = await repo.getSalesAnalytics(
                range.start, range.end,
                allowedBranchIds: scope);
            if (daily.isEmpty && analytics.invoiceCount == 0) {
              return const PicPosReportTabContent();
            }
            final best = daily.isEmpty
                ? null
                : daily.reduce((a, b) => a.total >= b.total ? a : b);
            const chartDays = 14;
            final shown = daily.length <= chartDays
                ? daily
                : daily.sublist(daily.length - chartDays);
            return PicPosReportTabContent(
              badge: _int(daily.length),
              kpis: [
                PicPosHubKpi(
                  icon: PhosphorIconsBold.receipt,
                  label: tr('صافي الإيراد'),
                  value: _money(analytics.totalNetRevenue),
                  tint: _tintBrand,
                  vs: tr('المبيعات ناقص الخصومات'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.fileText,
                  label: tr('عددُ الفواتير'),
                  value: _int(analytics.invoiceCount),
                  tint: _tintOk,
                  vs: tr('في المدى المختار'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.calculator,
                  label: tr('متوسّطُ الفاتورة'),
                  value: _money(analytics.averageInvoiceValue),
                  tint: _tintBrand,
                  vs: tr('الإجمالي على العدد'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.trendUp,
                  label: tr('أعلى يوم'),
                  value: best == null ? '—' : _money(best.total),
                  tint: _tintOk,
                  vs: best == null ? tr('لا مبيعات') : _dayLabel(best.date),
                ),
              ],
              chart: PicPosReportChart(
                title: tr('المبيعاتُ اليوميّة'),
                subtitle: shown.length == daily.length
                    ? tr('{p0} يوماً في المدى', {'p0': daily.length})
                    : tr('آخرُ {p0} يوماً من {p1}', {'p0': shown.length, 'p1': daily.length}),
                series:  [
                  PicPosChartSeries(label: tr('المبيعات'), color: _tintBrand),
                ],
                bars: [
                  for (final d in shown)
                    PicPosChartBar(
                      label: _dayLabel(d.date),
                      value: d.total,
                      display: d.total.toStringAsFixed(0),
                    ),
                ],
              ),
              table: PicPosDataTable(
                title: tr('المبيعاتُ يوماً بيوم'),
                subtitle: tr('المدى كاملاً'),
                columns:  [
                  PicPosTableColumn(tr('اليوم'), flex: 1.6),
                  PicPosTableColumn(tr('المبيعات'),
                      flex: 1.6, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('من أعلى يوم'), flex: 2.0),
                ],
                rows: [
                  for (final d in daily)
                    PicPosTableRow(cells: [
                      PicPosTextCell(d.date,
                          icon: PhosphorIconsBold.calendarBlank),
                      PicPosTextCell(_money(d.total)),
                      PicPosBarCell(
                        best == null || best.total == 0
                            ? '—'
                            : _pct(_ratio(d.total, best.total)),
                        best == null || best.total == 0
                            ? 0
                            : (d.total / best.total).clamp(0.0, 1.0),
                        _tintBrand,
                      ),
                    ]),
                ],
                totals: [
                  tr('{p0} يوماً', {'p0': daily.length}),
                  _money(daily.fold<double>(0, (a, d) => a + d.total)),
                  '',
                ],
              ),
            );
          },
        ),
      ],
    );

// ═══════════════════════════════════════════════════════════════════════════
// ٦) دوران المخزون — `an_inventory`
// ═══════════════════════════════════════════════════════════════════════════

/// **الدورانُ على متوسّط المدى** — `COGS ÷ ((قيمةُ أوّلِ المدى + قيمةُ آخرِه) ÷ ٢)`.
///
/// كان يقسم على قيمة المخزون **الآن** لأنّه لا استعلامَ للقيمة في الماضي،
/// فبُني `getInventoryCostValueAt` (أمرُ المالك 2026-08-26): الرصيدُ اليومَ
/// ناقصَ صافي حركات المخزون بعد التاريخ.
///
/// ⚠️ **والمتغيّرُ تاريخيّاً هو الكمّيّةُ لا التكلفة.** التقييمُ يقع على
/// `products.cost_price` — المتوسّطُ المرجّحُ العامُّ — في الطرفَين، وهو
/// قرارُ المالك 2026-07-12 المكتوبُ في `getInventoryReportAnalytics`: عليه
/// تُقيَّم صفوفُ تقرير المخزون وتُقيَّد تكلفةُ المبيعات في الأستاذ. وتقييمُ
/// الطرفِ الماضي بأساسٍ آخرَ كان ينتج بسطاً ومقاماً على مسطرتين — وهو أسوأُ
/// من حدٍّ معلَن. فالحدُّ الباقي مكتوبٌ في سطر ملاحظة التبويبة.
PicPosReportDefinition inventoryTurnoverReport() => PicPosReportDefinition(
      id: 'an_inventory',
      title: tr('دوران وكفاءة المخزون'),
      subtitle: tr('قيمةُ المخزون مقابلَ تكلفة ما بيع'),
      icon: PhosphorIconsBold.package,
      tabs: [
        PicPosReportTabDef(
          id: 'turnover',
          label: tr('الدوران'),
          icon: PhosphorIconsBold.arrowsClockwise,
          note:
              'الدورانُ = تكلفةُ المبيعات ÷ متوسّطِ المخزون بين طرفَي المدى. '
              'والكمّيّةُ تاريخيّةٌ والتكلفةُ متوسّطٌ مرجّحٌ حاليّ.',
          load: (ref, range) async {
            final repo = ref.read(reportingRepositoryProvider);
            final scope = await _scope(ref);
            final inv = await repo.getInventoryReportAnalytics();
            final sales = await repo.getSalesAnalytics(range.start, range.end,
                allowedBranchIds: scope);
            final low = await repo.getLowStockProducts();
            // قيمةُ **أوّل** المدى — الطرفُ الذي كان مفقوداً.
            final openingValue =
                await repo.getInventoryCostValueAt(range.start);
            final averageValue = (openingValue + inv.totalCostValue) / 2;
            final turnover =
                averageValue == 0 ? 0.0 : sales.totalCOGS / averageValue;
            final top = await repo.getTopProductsReport(
                from: range.start,
                to: range.end,
                limit: 8,
                allowedBranchIds: scope);
            return PicPosReportTabContent(
              badge: low.isEmpty ? null : _int(low.length),
              kpis: [
                PicPosHubKpi(
                  icon: PhosphorIconsBold.package,
                  label: tr('قيمةُ المخزون بالتكلفة'),
                  value: _money(inv.totalCostValue),
                  tint: _tintBrand,
                  vs: tr('{p0} صنفاً', {'p0': inv.uniqueProducts}),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.arrowsClockwise,
                  label: tr('معدّلُ الدوران'),
                  value: turnover.toStringAsFixed(2),
                  tint: turnover >= 1 ? _tintOk : _tintWarn,
                  vs: tr('مرّةً على متوسّطِ {p0}', {'p0': _money(averageValue)}),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.receipt,
                  label: tr('تكلفةُ المبيعات'),
                  value: _money(sales.totalCOGS),
                  tint: _tintWarn,
                  vs: tr('في المدى المختار'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.warning,
                  label: tr('أصنافٌ تحت الحدّ'),
                  value: _int(low.length),
                  tint: low.isEmpty ? _tintOk : _tintErr,
                  vs: tr('{p0} منها منتهٍ', {'p0': inv.outOfStockCount}),
                ),
              ],
              chart: PicPosReportChart(
                title: tr('أكثرُ الأصناف حركةً'),
                subtitle: tr('بقيمة المبيعات في المدى'),
                series:  [
                  PicPosChartSeries(label: tr('المبيعات'), color: _tintBrand),
                ],
                bars: [
                  for (final p in top)
                    PicPosChartBar(
                      label: p.name,
                      value: p.totalValue,
                      display: p.totalValue.toStringAsFixed(0),
                    ),
                ],
              ),
              table: PicPosDataTable(
                title: tr('أصنافٌ تحت حدّ الطلب'),
                subtitle: tr('الرصيدُ الحاليُّ دون الحدّ الأدنى'),
                emptyLabel: tr('لا صنفَ تحت الحدّ'),
                columns:  [
                  PicPosTableColumn(tr('الصنف'), flex: 2.6),
                  PicPosTableColumn(tr('الرصيد'),
                      flex: 1.1, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('الحدُّ الأدنى'),
                      flex: 1.1, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('التكلفة'),
                      flex: 1.2, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('الحالة'), flex: 1.2),
                ],
                rows: [
                  for (final p in low)
                    PicPosTableRow(cells: [
                      PicPosTextCell(p.name, icon: PhosphorIconsBold.package),
                      PicPosTextCell(p.currentStock.toStringAsFixed(0)),
                      PicPosTextCell(p.minStock.toStringAsFixed(0)),
                      PicPosTextCell(_money(p.costPrice)),
                      PicPosPillCell(
                        p.currentStock <= 0 ? tr('منتهٍ') : tr('تحت الحدّ'),
                        p.currentStock <= 0 ? _tintErr : _tintWarn,
                      ),
                    ]),
                ],
                totals: [
                  tr('{p0} صنفاً', {'p0': low.length}),
                  '',
                  '',
                  '',
                  '',
                ],
              ),
            );
          },
        ),
      ],
    );

// ═══════════════════════════════════════════════════════════════════════════
// ٧) نشاط المستخدمين — `u_activity`
// ═══════════════════════════════════════════════════════════════════════════

/// ⚠️ **استعلامٌ لكلّ مستخدم.** `getActivityCount` يعدّ لمستخدمٍ واحد، ولا
/// يوجد تجميعٌ بـ`GROUP BY user_id`. وعددُ المستخدمين في منشأةٍ واحدةٍ
/// عشراتٌ لا آلاف، فالحلقةُ مقبولة — ولو صار العددُ كبيراً فمكانُ الإصلاح
/// استعلامٌ مجمَّعٌ في الـDAO لا صفحةٌ في الشاشة.
PicPosReportDefinition userActivityReport() => PicPosReportDefinition(
      id: 'u_activity',
      title: tr('نشاط المستخدمين'),
      subtitle: tr('عددُ العمليات لكلّ مستخدمٍ في المدى'),
      icon: PhosphorIconsBold.userGear,
      tabs: [
        PicPosReportTabDef(
          id: 'list',
          label: tr('المستخدمون'),
          icon: PhosphorIconsBold.users,
          note: tr('العددُ من سجلّ النشاط — والسجلُّ لا يُحذَف.'),
          load: (ref, range) async {
            // ⚠️ **لا `allUsersProvider.future` ولا `watchAllUsers().first`.**
            // الأوّلُ `StreamProvider.autoDispose` و`ref.read` لا يترك
            // مستمعاً، فقد يُرمى قبل أن يبثّ. والثاني مجرى drift لا يستقرّ
            // في المنطقة الوهميّة لاختبارات الودجت فتعلّق الشاشةُ على
            // دوّارةٍ لا تنتهي — وقع ذلك فعلاً وأمسكه اختبارُ التركيب.
            // والتقريرُ يريد لقطةً لا بثّاً.
            final repo = ref.read(reportingRepositoryProvider);
            final users = await repo.getAllUsersWithRoles();
            final logs = ref.read(activityLogRepositoryProvider);
            final counts = <({String name, String role, int ops})>[];
            for (final u in users) {
              final n = await logs.getActivityCount(
                fromDate: range.start,
                toDate: range.end,
                userId: u.user.id,
              );
              counts.add((
                name: u.user.displayName,
                role: u.role?.name ?? '—',
                ops: n,
              ));
            }
            counts.sort((a, b) => b.ops.compareTo(a.ops));
            if (counts.isEmpty) return const PicPosReportTabContent();
            final total = counts.fold<int>(0, (a, c) => a + c.ops);
            final active = counts.where((c) => c.ops > 0).length;
            final busiest = counts.first;
            return PicPosReportTabContent(
              badge: _int(counts.length),
              kpis: [
                PicPosHubKpi(
                  icon: PhosphorIconsBold.users,
                  label: tr('مستخدمون نشِطون'),
                  value: _int(active),
                  tint: _tintBrand,
                  vs: tr('من {p0} مسجَّلاً', {'p0': counts.length}),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.listChecks,
                  label: tr('إجمالي العمليات'),
                  value: _int(total),
                  tint: _tintOk,
                  vs: tr('في المدى المختار'),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.trendUp,
                  label: tr('الأكثرُ نشاطاً'),
                  value: _int(busiest.ops),
                  tint: _tintBrand,
                  vs: busiest.ops == 0 ? tr('لا نشاط') : busiest.name,
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.userMinus,
                  label: tr('بلا نشاط'),
                  value: _int(counts.length - active),
                  tint: counts.length - active > 0 ? _tintWarn : _tintOk,
                  vs: tr('لم يسجّلوا عمليّةً'),
                ),
              ],
              chart: PicPosReportChart(
                title: tr('العملياتُ لكلّ مستخدم'),
                subtitle: tr('أعلى ثمانيةٍ في المدى'),
                series:  [
                  PicPosChartSeries(label: tr('عمليات'), color: _tintBrand),
                ],
                bars: [
                  for (final c in counts.take(8))
                    PicPosChartBar(
                      label: c.name,
                      value: c.ops.toDouble(),
                      display: _int(c.ops),
                    ),
                ],
              ),
              table: PicPosDataTable(
                title: tr('نشاطُ المستخدمين'),
                subtitle: tr('مرتَّبةً بعدد العمليات تنازليّاً'),
                columns:  [
                  PicPosTableColumn(tr('المستخدم'), flex: 2.2),
                  PicPosTableColumn(tr('الدور'), flex: 1.6),
                  PicPosTableColumn(tr('العمليات'),
                      flex: 1.2, align: PicPosCellAlign.end),
                  PicPosTableColumn(tr('من الإجمالي'), flex: 2.0),
                ],
                rows: [
                  for (final c in counts)
                    PicPosTableRow(cells: [
                      PicPosTextCell(c.name, icon: PhosphorIconsBold.user),
                      PicPosTextCell(c.role),
                      PicPosTextCell(_int(c.ops)),
                      PicPosBarCell(
                        total == 0 ? '—' : _pct(_ratio(c.ops.toDouble(), total.toDouble())),
                        total == 0 ? 0 : (c.ops / total).clamp(0.0, 1.0),
                        c.ops == 0 ? _tintWarn : _tintBrand,
                      ),
                    ]),
                ],
                totals: [
                  tr('{p0} مستخدماً', {'p0': counts.length}),
                  '',
                  _int(total),
                  '',
                ],
              ),
            );
          },
        ),
      ],
    );
