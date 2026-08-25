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

String _pct(double v) => '${v.toStringAsFixed(1)}٪';

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
/// ⚠️ **والجدولُ تصنيفاتٌ لا أصناف.** التصميمُ يسرد الأصنافَ التي تحتاج
/// مراجعةَ سعر، و`getCategoryProfitReport` يجمع على مستوى التصنيف. وجدولُ
/// أصنافٍ بهامشٍ حقيقيٍّ يحتاج تكلفةً لكلّ سطرِ بيع — استعلامٌ لا يوجد.
PicPosReportDefinition profitMarginReport() => PicPosReportDefinition(
      id: 'profit_margin',
      title: 'هامش الربح',
      subtitle: 'تكلفةُ المبيعات وصافي الربح لكلّ تصنيف',
      icon: PhosphorIconsBold.percent,
      tabs: [
        PicPosReportTabDef(
          id: 'cats',
          label: 'التصنيفات',
          icon: PhosphorIconsBold.chartPieSlice,
          note: 'الربحُ = المبيعات − تكلفة البضاعة المباعة، لكلّ تصنيف.',
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
                  label: 'إجمالي المبيعات',
                  value: _money(sales),
                  tint: _tintBrand,
                  vs: 'في المدى المختار',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.package,
                  label: 'تكلفة البضاعة المباعة',
                  value: _money(cost),
                  tint: _tintWarn,
                  vs: 'من دفتر التكلفة',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.trendUp,
                  label: 'صافي الربح',
                  value: _money(profit),
                  tint: profit >= 0 ? _tintOk : _tintErr,
                  vs: 'المبيعات ناقص التكلفة',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.percent,
                  label: 'الهامش الإجمالي',
                  value: _pct(_ratio(profit, sales)),
                  tint: _marginTint(_ratio(profit, sales)),
                  vs: 'الربح من المبيعات',
                ),
              ],
              chart: PicPosReportChart(
                title: 'المبيعات والتكلفة لكلّ تصنيف',
                subtitle: '${rows.length} تصنيفاً في المدى',
                series: const [
                  PicPosChartSeries(label: 'المبيعات', color: _tintBrand),
                  PicPosChartSeries(label: 'التكلفة', color: _tintWarn),
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
                title: 'الربحُ لكلّ تصنيف',
                subtitle: 'مرتَّبةً بالمبيعات تنازليّاً',
                columns: const [
                  PicPosTableColumn('التصنيف', flex: 2.2),
                  PicPosTableColumn('المبيعات',
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn('التكلفة',
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn('الربح',
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn('الهامش', flex: 1.4),
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
                  '${rows.length} تصنيفاً',
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
          label: 'هامش الربح',
          icon: PhosphorIconsBold.percent,
          note: 'التصنيفاتُ التي هامشُها سالبٌ أو أقلُّ من ٥٪ — تحتاج مراجعةَ سعر.',
          load: (ref, range) async {
            final all = await _categoryRows(ref, range);
            final weak = all.where((r) => r.margin < 5).toList()
              ..sort((a, b) => a.margin.compareTo(b.margin));
            if (all.isEmpty) return const PicPosReportTabContent();
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
                  label: 'الهامش الإجمالي',
                  value: _pct(_ratio(profit, sales)),
                  tint: _marginTint(_ratio(profit, sales)),
                  vs: 'على كلّ التصنيفات',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.arrowUp,
                  label: 'أعلى هامش',
                  value: _pct(best.margin),
                  tint: _tintOk,
                  vs: best.categoryName,
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.arrowDown,
                  label: 'أدنى هامش',
                  value: _pct(worst.margin),
                  tint: _tintErr,
                  vs: worst.categoryName,
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.warning,
                  label: 'تصنيفاتٌ بهامشٍ سالب',
                  value: _int(negative),
                  tint: negative > 0 ? _tintErr : _tintOk,
                  vs: 'تبيع بخسارة',
                ),
              ],
              chart: PicPosReportChart(
                title: 'الهامشُ لكلّ تصنيف',
                subtitle: 'النسبةُ المئويّةُ من المبيعات',
                series: const [
                  PicPosChartSeries(label: 'الهامش', color: _tintBrand),
                ],
                bars: [
                  for (final r in all.take(8))
                    PicPosChartBar(
                      label: r.categoryName,
                      // السالبُ يُرسَم بقيمته المطلقة ونصُّه يحمل الإشارة،
                      // فالعمودُ لا ينزل تحت المحور وتبقى الإشارةُ مقروءة.
                      value: r.margin,
                      display: _pct(r.margin),
                    ),
                ],
              ),
              table: PicPosDataTable(
                title: 'تحتاج مراجعةَ سعر',
                subtitle: 'هامشٌ أقلُّ من ٥٪ أو سالب',
                emptyLabel: 'لا تصنيفَ هامشُه دون ٥٪ — كلُّها سليمة',
                columns: const [
                  PicPosTableColumn('التصنيف', flex: 2.4),
                  PicPosTableColumn('المبيعات',
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn('التكلفة',
                      flex: 1.3, align: PicPosCellAlign.end),
                  PicPosTableColumn('الهامش', flex: 1.4),
                  PicPosTableColumn('الحالة', flex: 1.2),
                ],
                rows: [
                  for (final r in weak)
                    PicPosTableRow(cells: [
                      PicPosTextCell(r.categoryName,
                          icon: PhosphorIconsBold.tag,
                          tint: _marginTint(r.margin)),
                      PicPosTextCell(_money(r.totalSales)),
                      PicPosTextCell(_money(r.totalCost)),
                      PicPosBarCell(
                        _pct(r.margin),
                        (r.margin / 100).clamp(0.0, 1.0),
                        _marginTint(r.margin),
                      ),
                      PicPosPillCell(
                        r.margin < 0 ? 'يبيع بخسارة' : 'هامشٌ ضعيف',
                        _marginTint(r.margin),
                      ),
                    ]),
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
  final who = suppliers ? 'المورّد' : 'العميل';
  final whoPlural = suppliers ? 'الموردين' : 'العملاء';
  final valueLabel = suppliers ? 'المشتريات' : 'المبيعات';
  return PicPosReportDefinition(
    id: suppliers ? 'sup_behavior' : 'cust_behavior',
    title: 'تحليل سلوك $whoPlural',
    subtitle: 'التكرارُ والقيمةُ وآخرُ تعاملٍ لكلّ $who',
    icon: suppliers ? PhosphorIconsBold.truck : PhosphorIconsBold.users,
    tabs: [
      PicPosReportTabDef(
        id: 'list',
        label: whoPlural,
        icon: PhosphorIconsBold.users,
        note:
            'الفواتيرُ المحذوفةُ والمرتجعاتُ مستبعَدة، والتعاملُ بلا $who مسجَّلٍ لا يُحتسَب.',
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
                label: '$whoPlural المتعاملون',
                value: _int(rows.length),
                tint: _tintBrand,
                vs: 'لهم فاتورةٌ في المدى',
              ),
              PicPosHubKpi(
                icon: PhosphorIconsBold.receipt,
                label: 'إجمالي $valueLabel',
                value: _money(total),
                tint: _tintOk,
                vs: '$invoices فاتورة',
              ),
              PicPosHubKpi(
                icon: PhosphorIconsBold.calculator,
                label: 'متوسّطُ الفاتورة',
                value: _money(invoices == 0 ? 0 : total / invoices),
                tint: _tintBrand,
                vs: 'على كلّ الفواتير',
              ),
              PicPosHubKpi(
                icon: PhosphorIconsBold.warning,
                label: 'غيرُ المسدَّد',
                value: _money(unpaid),
                tint: unpaid > 0 ? _tintWarn : _tintOk,
                // ⚠️ المتبقّي **في هذا المدى** لا رصيدُ الطرف الكلّيّ —
                // فالرصيدُ يحمل فواتيرَ أقدمَ ومقبوضاتٍ لاحقة.
                vs: 'من فواتير المدى وحدَها',
              ),
            ],
            chart: PicPosReportChart(
              title: 'أعلى $whoPlural قيمةً',
              subtitle: 'أعلى ثمانيةٍ في المدى',
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
              title: 'سلوكُ $whoPlural',
              subtitle: 'مرتَّبةً بالقيمة تنازليّاً',
              columns: [
                PicPosTableColumn(who, flex: 2.2),
                const PicPosTableColumn('الفواتير',
                    flex: 1.0, align: PicPosCellAlign.end),
                PicPosTableColumn(valueLabel,
                    flex: 1.4, align: PicPosCellAlign.end),
                const PicPosTableColumn('متوسّطُ الفاتورة',
                    flex: 1.3, align: PicPosCellAlign.end),
                const PicPosTableColumn('غيرُ المسدَّد',
                    flex: 1.3, align: PicPosCellAlign.end),
                const PicPosTableColumn('آخرُ تعامل', flex: 1.2),
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
  if (r >= 3 && f + m >= 5) return (label: 'الأوفياء', tint: _tintOk);
  if (r >= 3) return (label: 'نشِطون', tint: AppColors.info);
  if (r == 2 && f + m >= 4) return (label: 'معرَّضون للفقد', tint: _tintWarn);
  if (r <= 1 && f + m >= 4) return (label: 'ثمينون نائمون', tint: _tintErr);
  return (label: 'نائمون', tint: AppColors.textPrimary);
}

PicPosReportDefinition customerSegmentsReport() => PicPosReportDefinition(
      id: 'an_customers',
      title: 'تقسيم العملاء (RFM)',
      subtitle: 'الحداثةُ والتكرارُ والقيمةُ — ثلاثُ درجاتٍ لكلّ عميل',
      icon: PhosphorIconsBold.chartDonut,
      tabs: [
        PicPosReportTabDef(
          id: 'seg',
          label: 'التقسيم',
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

            final loyal = buckets['الأوفياء']?.count ?? 0;
            final atRisk = (buckets['معرَّضون للفقد']?.count ?? 0) +
                (buckets['ثمينون نائمون']?.count ?? 0);
            final total = rows.fold<double>(0, (a, r) => a + r.totalValue);

            return PicPosReportTabContent(
              badge: _int(rows.length),
              kpis: [
                PicPosHubKpi(
                  icon: PhosphorIconsBold.users,
                  label: 'عملاءُ المدى',
                  value: _int(rows.length),
                  tint: _tintBrand,
                  vs: 'لهم فاتورةٌ واحدةٌ فأكثر',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.star,
                  label: 'الأوفياء',
                  value: _int(loyal),
                  tint: _tintOk,
                  vs: _pct(_ratio(loyal.toDouble(), rows.length.toDouble())),
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.warning,
                  label: 'معرَّضون للفقد',
                  value: _int(atRisk),
                  tint: atRisk > 0 ? _tintWarn : _tintOk,
                  vs: 'حداثةٌ ضعيفةٌ وقيمةٌ عالية',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.receipt,
                  label: 'قيمةُ المدى',
                  value: _money(total),
                  tint: _tintBrand,
                  vs: 'مجموعُ فواتير العملاء',
                ),
              ],
              chart: PicPosReportChart(
                title: 'العملاءُ حسب الشريحة',
                subtitle: 'العددُ في كلّ شريحة',
                series: const [
                  PicPosChartSeries(label: 'عملاء', color: _tintBrand),
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
                title: 'درجاتُ العملاء',
                subtitle: 'مرتَّبةً بالقيمة تنازليّاً',
                columns: const [
                  PicPosTableColumn('العميل', flex: 2.2),
                  PicPosTableColumn('آخرُ تعامل',
                      flex: 1.2, align: PicPosCellAlign.end),
                  PicPosTableColumn('الفواتير',
                      flex: 1.0, align: PicPosCellAlign.end),
                  PicPosTableColumn('القيمة',
                      flex: 1.4, align: PicPosCellAlign.end),
                  PicPosTableColumn('R·F·M', flex: 1.0),
                  PicPosTableColumn('الشريحة', flex: 1.5),
                ],
                rows: [
                  for (final s in scored)
                    PicPosTableRow(cells: [
                      PicPosTextCell(s.row.partyName,
                          icon: PhosphorIconsBold.user),
                      PicPosTextCell(
                          s.days >= 9999 ? '—' : 'منذ ${s.days} يوماً'),
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
                  '${rows.length} عميلاً',
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
      title: 'تحليل المبيعات',
      subtitle: 'اتّجاهاتُ المبيعات وأنماطُها على الزمن',
      icon: PhosphorIconsBold.chartLine,
      tabs: [
        PicPosReportTabDef(
          id: 'trend',
          label: 'الاتجاه',
          icon: PhosphorIconsBold.chartLine,
          note: 'المبيعاتُ اليوميّةُ في المدى — المرتجعاتُ والمحذوفُ مستبعَدان.',
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
                  label: 'صافي الإيراد',
                  value: _money(analytics.totalNetRevenue),
                  tint: _tintBrand,
                  vs: 'المبيعات ناقص الخصومات',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.fileText,
                  label: 'عددُ الفواتير',
                  value: _int(analytics.invoiceCount),
                  tint: _tintOk,
                  vs: 'في المدى المختار',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.calculator,
                  label: 'متوسّطُ الفاتورة',
                  value: _money(analytics.averageInvoiceValue),
                  tint: _tintBrand,
                  vs: 'الإجمالي على العدد',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.trendUp,
                  label: 'أعلى يوم',
                  value: best == null ? '—' : _money(best.total),
                  tint: _tintOk,
                  vs: best == null ? 'لا مبيعات' : _dayLabel(best.date),
                ),
              ],
              chart: PicPosReportChart(
                title: 'المبيعاتُ اليوميّة',
                subtitle: shown.length == daily.length
                    ? '${daily.length} يوماً في المدى'
                    : 'آخرُ ${shown.length} يوماً من ${daily.length}',
                series: const [
                  PicPosChartSeries(label: 'المبيعات', color: _tintBrand),
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
                title: 'المبيعاتُ يوماً بيوم',
                subtitle: 'المدى كاملاً',
                columns: const [
                  PicPosTableColumn('اليوم', flex: 1.6),
                  PicPosTableColumn('المبيعات',
                      flex: 1.6, align: PicPosCellAlign.end),
                  PicPosTableColumn('من أعلى يوم', flex: 2.0),
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
                  '${daily.length} يوماً',
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

/// ⚠️ **معدّلُ الدوران تقريبٌ معلَنٌ لا رقمٌ محاسبيّ.** الصيغةُ الدقيقةُ
/// `COGS ÷ متوسّطِ المخزون` بين أوّلِ المدى وآخرِه، ولا يوجد استعلامُ
/// «قيمةِ المخزون بتاريخٍ ماضٍ». فالمقسومُ عليه هو قيمةُ المخزون **الآن**،
/// وهذا مكتوبٌ في سطر ملاحظة التبويبة كي لا يُقرأ الرقمُ على أنّه أدقُّ
/// ممّا هو. رقمٌ يكذب أسوأُ من لا رقم — ورقمٌ يقول حدَّه ليس كاذباً.
PicPosReportDefinition inventoryTurnoverReport() => PicPosReportDefinition(
      id: 'an_inventory',
      title: 'دوران وكفاءة المخزون',
      subtitle: 'قيمةُ المخزون مقابلَ تكلفة ما بيع',
      icon: PhosphorIconsBold.package,
      tabs: [
        PicPosReportTabDef(
          id: 'turnover',
          label: 'الدوران',
          icon: PhosphorIconsBold.arrowsClockwise,
          note:
              'الدورانُ = تكلفةُ المبيعات ÷ قيمةِ المخزون **الحاليّة** — تقريبٌ، '
              'إذ لا تُقرأ قيمةُ المخزون بتاريخٍ ماضٍ.',
          load: (ref, range) async {
            final repo = ref.read(reportingRepositoryProvider);
            final scope = await _scope(ref);
            final inv = await repo.getInventoryReportAnalytics();
            final sales = await repo.getSalesAnalytics(range.start, range.end,
                allowedBranchIds: scope);
            final low = await repo.getLowStockProducts();
            final turnover =
                inv.totalCostValue == 0 ? 0.0 : sales.totalCOGS / inv.totalCostValue;
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
                  label: 'قيمةُ المخزون بالتكلفة',
                  value: _money(inv.totalCostValue),
                  tint: _tintBrand,
                  vs: '${inv.uniqueProducts} صنفاً',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.arrowsClockwise,
                  label: 'معدّلُ الدوران',
                  value: turnover.toStringAsFixed(2),
                  tint: turnover >= 1 ? _tintOk : _tintWarn,
                  vs: 'مرّةً في المدى — تقريبيّ',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.receipt,
                  label: 'تكلفةُ المبيعات',
                  value: _money(sales.totalCOGS),
                  tint: _tintWarn,
                  vs: 'في المدى المختار',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.warning,
                  label: 'أصنافٌ تحت الحدّ',
                  value: _int(low.length),
                  tint: low.isEmpty ? _tintOk : _tintErr,
                  vs: '${inv.outOfStockCount} منها منتهٍ',
                ),
              ],
              chart: PicPosReportChart(
                title: 'أكثرُ الأصناف حركةً',
                subtitle: 'بقيمة المبيعات في المدى',
                series: const [
                  PicPosChartSeries(label: 'المبيعات', color: _tintBrand),
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
                title: 'أصنافٌ تحت حدّ الطلب',
                subtitle: 'الرصيدُ الحاليُّ دون الحدّ الأدنى',
                emptyLabel: 'لا صنفَ تحت الحدّ',
                columns: const [
                  PicPosTableColumn('الصنف', flex: 2.6),
                  PicPosTableColumn('الرصيد',
                      flex: 1.1, align: PicPosCellAlign.end),
                  PicPosTableColumn('الحدُّ الأدنى',
                      flex: 1.1, align: PicPosCellAlign.end),
                  PicPosTableColumn('التكلفة',
                      flex: 1.2, align: PicPosCellAlign.end),
                  PicPosTableColumn('الحالة', flex: 1.2),
                ],
                rows: [
                  for (final p in low)
                    PicPosTableRow(cells: [
                      PicPosTextCell(p.name, icon: PhosphorIconsBold.package),
                      PicPosTextCell(p.currentStock.toStringAsFixed(0)),
                      PicPosTextCell(p.minStock.toStringAsFixed(0)),
                      PicPosTextCell(_money(p.costPrice)),
                      PicPosPillCell(
                        p.currentStock <= 0 ? 'منتهٍ' : 'تحت الحدّ',
                        p.currentStock <= 0 ? _tintErr : _tintWarn,
                      ),
                    ]),
                ],
                totals: [
                  '${low.length} صنفاً',
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
      title: 'نشاط المستخدمين',
      subtitle: 'عددُ العمليات لكلّ مستخدمٍ في المدى',
      icon: PhosphorIconsBold.userGear,
      tabs: [
        PicPosReportTabDef(
          id: 'list',
          label: 'المستخدمون',
          icon: PhosphorIconsBold.users,
          note: 'العددُ من سجلّ النشاط — والسجلُّ لا يُحذَف.',
          load: (ref, range) async {
            final users = await ref.read(allUsersProvider.future);
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
                  label: 'مستخدمون نشِطون',
                  value: _int(active),
                  tint: _tintBrand,
                  vs: 'من ${counts.length} مسجَّلاً',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.listChecks,
                  label: 'إجمالي العمليات',
                  value: _int(total),
                  tint: _tintOk,
                  vs: 'في المدى المختار',
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.trendUp,
                  label: 'الأكثرُ نشاطاً',
                  value: _int(busiest.ops),
                  tint: _tintBrand,
                  vs: busiest.ops == 0 ? 'لا نشاط' : busiest.name,
                ),
                PicPosHubKpi(
                  icon: PhosphorIconsBold.userMinus,
                  label: 'بلا نشاط',
                  value: _int(counts.length - active),
                  tint: counts.length - active > 0 ? _tintWarn : _tintOk,
                  vs: 'لم يسجّلوا عمليّةً',
                ),
              ],
              chart: PicPosReportChart(
                title: 'العملياتُ لكلّ مستخدم',
                subtitle: 'أعلى ثمانيةٍ في المدى',
                series: const [
                  PicPosChartSeries(label: 'عمليات', color: _tintBrand),
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
                title: 'نشاطُ المستخدمين',
                subtitle: 'مرتَّبةً بعدد العمليات تنازليّاً',
                columns: const [
                  PicPosTableColumn('المستخدم', flex: 2.2),
                  PicPosTableColumn('الدور', flex: 1.6),
                  PicPosTableColumn('العمليات',
                      flex: 1.2, align: PicPosCellAlign.end),
                  PicPosTableColumn('من الإجمالي', flex: 2.0),
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
                  '${counts.length} مستخدماً',
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
