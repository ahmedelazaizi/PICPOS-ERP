import 'package:ural_erp/core/i18n/tr.dart';
// «المناطق ومسارات التوزيع» — نسخةُ PicPos على وحدة `regions` من التصميم.
//
// ═══ ⚠️ تصحيحُ خريطةٍ خاطئةٍ في تسليمٍ سابق ═══
//
// سُندت «المناطق» في تسليمٍ سابقٍ إلى `screens/region_management_screen.dart`
// — وهو **خطأ**. ذاك يعرض جدولَ `Regions` (‏مناطقُ جغرافيّةٌ لها فروع)،
// وتبويباتُ التصميم الأربعُ مساراتُ توزيعٍ وزياراتٌ وأهدافٌ وشركاتُ توصيل:
// أي `screens/distribution_screen.dart` وله **نفسُ الأربع** تقريباً.
//
// ═══ نسخةٌ لا قشرة — والسببُ مقيس ═══
//
// تبويباتُ شاشة التوزيع المشتركةِ أصنافٌ **خاصّةٌ** (`_RoutesTab` …) داخلَ
// ملفّات `part`، فلا تُستورَد من هنا. وكشفُها يعني تعديلَ شاشة UralCash،
// وأمرُ المالك: «انسخ إلى PicPos بشكلٍ منفصل». فالمنطقُ هنا يقرأ من
// `distributionControllerProvider` نفسِه ولا يلمس تلك الملفّات.
//
// ═══ ما لم يُنقَل، بقياس ═══
//
// ⚠️ **لوحةُ الزيارات تعرض مساراً واحداً لا كلَّ المسارات.** التصميمُ يرسم
// لوحةً تجمع زياراتِ الأسبوع كلَّها، و`watchRouteVisits` تأخذ **معرِّفَ
// مسارٍ** واحداً — ولا واجهةَ تقرأ زياراتِ كلِّ المسارات معاً. فبناءُ واحدةٍ
// تغييرٌ في طبقة البيانات، والمعروضُ هنا مسارٌ يختاره المشغّلُ بشريحة.
// بندٌ في التسليم.
//
// ⚠️ **ومؤشّراتُ التصميم بلا مصدرٍ لم تُخترَع**: «قيمة الطلبات» من الزيارات
// المنفَّذة مشتقّةٌ من `orderAmount` (‏موجود)، أمّا «تحصيلات المناديب» فتُقرأ
// من `watchAllCollections` وهي مدىً زمنيٌّ لا رقمٌ جاهز — فتُحسَب من الشهر
// الجاري لا تُكتَب.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_entity_card.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_status_board.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../screens/providers/distribution_controller.dart';

/// ملاحظاتُ التبويبات — نصوصُ `TABS.regions[].note` حرفيّاً.
List<String> get _tabNotes => [
  tr('كل مسار له مندوب مسؤول ومنطقة جغرافية'),
  tr('الزيارة قد تنتج فاتورة بيع أو تُتخطّى بسبب'),
  tr('الهدف شهري بالقيمة وبعدد الزيارات معاً'),
  tr('المندوب يتبع شركة أو يكون داخلياً'),
];

final _routesProvider = StreamProvider.autoDispose<List<SalesRoute>>(
  (ref) => ref.watch(distributionControllerProvider).watchSalesRoutes(),
);

/// موظّفو النطاق — لأسماء المناديب. **محصورةٌ بفروع المستخدم** لأنّ
/// `getAllEmployees` في المتحكّم تحلّ النطاقَ بنفسها (‏H6).
final _repsProvider = FutureProvider.autoDispose<List<Employee>>(
  (ref) => ref.watch(distributionControllerProvider).getAllEmployees(),
);

/// زياراتُ مسارٍ بعينه في الشهر الجاري.
final _visitsProvider =
    StreamProvider.autoDispose.family<List<RouteVisit>, int>((ref, routeId) {
  final now = DateTime.now();
  return ref.watch(distributionControllerProvider).watchRouteVisits(
        routeId,
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 0, 23, 59, 59),
      );
});

/// أهدافُ الشهر الجاري.
final _targetsProvider = StreamProvider.autoDispose<List<SalesRepTarget>>(
  (ref) {
    final now = DateTime.now();
    return ref
        .watch(distributionControllerProvider)
        .watchMonthlyTargets(now.year, now.month);
  },
);

class DistributionPicposScreen extends ConsumerStatefulWidget {
  const DistributionPicposScreen({super.key});

  @override
  ConsumerState<DistributionPicposScreen> createState() =>
      _DistributionPicposScreenState();
}

class _DistributionPicposScreenState
    extends ConsumerState<DistributionPicposScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// المسارُ المختارُ في تبويبة الزيارات — `null` = أوّلُ مسارٍ متاح.
  int? _visitRouteId;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _hit(String? s) =>
      _query.isEmpty || (s ?? '').toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final List<SalesRoute> routes =
        ref.watch(_routesProvider).value ?? const [];
    final List<Employee> reps = ref.watch(_repsProvider).value ?? const [];
    final List<SalesRepTarget> targets =
        ref.watch(_targetsProvider).value ?? const [];
    final List<DeliveryCompany> companies =
        ref.watch(allDeliveryCompaniesProvider).value ?? const [];

    return PicPosScreenScaffold(
      title: tr('المناطق ومسارات التوزيع'),
      subtitle: tr('المسارات الجغرافية وزيارات المندوبين والأهداف والتحصيل'),
      icon: PhosphorIconsBold.mapTrifold,
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('ابحث عن مسار أو مندوب...'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 14),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
        ),
      ),
      subHeader: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosReportTabs(
            controller: _tabs,
            tabs: [
              (
                label: tr('المسارات'),
                icon: PhosphorIconsBold.path,
                badge: '${routes.length}'
              ),
              (
                label: tr('الزيارات'),
                icon: PhosphorIconsBold.mapPinLine,
                badge: null
              ),
              (
                label: tr('الأهداف والتحصيل'),
                icon: PhosphorIconsBold.target,
                badge: '${targets.length}'
              ),
              (
                label: tr('شركات التوصيل'),
                icon: PhosphorIconsBold.moped,
                badge: '${companies.length}'
              ),
            ],
          ),
          PicPosTabNote(note: _tabNotes[_tabs.index]),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: TabBarView(
        controller: _tabs,
        children: [
          _scroll(_routesTab(context, routes, reps)),
          _scroll(_visitsTab(context, routes, reps)),
          _scroll(_targetsTab(context, targets, reps)),
          _scroll(_companiesTab(context, companies)),
        ],
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 26),
        child: child,
      );

  String _repName(List<Employee> reps, int? id) {
    if (id == null) return tr('بلا مندوب ثابت');
    return reps.where((e) => e.id == id).firstOrNull?.name ?? tr('مندوب #{id}', {'id': id});
  }

  // ── المسارات ───────────────────────────────────────────────────────────

  Widget _routesTab(
    BuildContext context,
    List<SalesRoute> routes,
    List<Employee> reps,
  ) {
    final shown =
        routes.where((r) => _hit(r.name) || _hit(r.area)).toList();
    final active = routes.where((r) => r.isActive).length;
    final assigned = routes.where((r) => r.salesRepId != null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.path,
              label: tr('المسارات النشطة'),
              value: '$active',
              tint: AppColors.primary,
              vs: tr('من {p0} مسجّل', {'p0': routes.length}),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.user,
              label: tr('مسارٌ له مندوب'),
              value: '$assigned',
              tint: AppColors.success,
              vs: tr('{p0} بلا مندوبٍ ثابت', {'p0': routes.length - assigned}),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.usersThree,
              label: tr('المناديب في نطاقك'),
              value: '${reps.length}',
              tint: const Color(0xFF8B5CF6),
              vs: tr('محصورون بفروعك'),
            ),
          ],
        ),
        const SizedBox(height: 16),
         PicPosBlockHeader(title: tr('مسارات التوزيع')),
        if (shown.isEmpty)
          _empty(context, tr('لا مساراتٍ مطابقة'))
        else
          PicPosEntityCardGrid(
            children: [
              for (final r in shown)
                PicPosEntityCard(
                  title: r.name,
                  subtitle: r.area ?? r.description,
                  tint: r.isActive ? AppColors.success : AppColors.textMuted,
                  icon: PhosphorIconsBold.path,
                  status: r.isActive ? tr('نشط') : tr('موقوف'),
                  statusTint:
                      r.isActive ? AppColors.success : AppColors.textMuted,
                  stats: [
                    PicPosEntityStat(
                      tr('المندوب'),
                      _repName(reps, r.salesRepId),
                      tint: r.salesRepId == null ? AppColors.warning : null,
                    ),
                    PicPosEntityStat(tr('المنطقة'), r.area ?? '—'),
                  ],
                  chips: [
                    if ((r.description ?? '').isNotEmpty)
                      PicPosEntityChip(
                          PhosphorIconsBold.textAlignRight, r.description!),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  // ── الزيارات ───────────────────────────────────────────────────────────

  Widget _visitsTab(
    BuildContext context,
    List<SalesRoute> routes,
    List<Employee> reps,
  ) {
    if (routes.isEmpty) {
      return _empty(context, tr('لا مساراتٍ بعد — أنشئ مساراً لتظهر زياراته'));
    }
    final routeId = _visitRouteId ?? routes.first.id;
    final visits = ref.watch(_visitsProvider(routeId)).value ?? const [];

    List<RouteVisit> of(String status) =>
        visits.where((v) => v.status == status).toList();

    // ⚠️ **حالاتُ العمود من العمود نفسِه**: `RouteVisits.status` يوثّق أربعاً
    //    (planned · completed · cancelled · skipped)، فلا تُخترَع خامسةٌ ولا
    //    تُسقَط واحدةٌ فتختفي زياراتُها من اللوحة بلا أثر.
    final statuses = [
      ('planned', tr('مخططة'), PhosphorIconsBold.calendarBlank, AppColors.primary),
      ('completed', tr('منفَّذة'), PhosphorIconsBold.checkCircle,
          AppColors.success),
      ('skipped', tr('متخطّاة'), PhosphorIconsBold.skipForward, AppColors.warning),
      ('cancelled', tr('ملغاة'), PhosphorIconsBold.xCircle, AppColors.error),
    ];

    final done = of('completed');
    final orders = done.fold<double>(0, (s, v) => s + v.orderAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.mapPinLine,
              label: tr('زياراتُ الشهر'),
              value: '${visits.length}',
              tint: AppColors.primary,
              vs: tr('على المسار المختار'),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.checkCircle,
              label: tr('منفَّذة'),
              value: '${done.length}',
              tint: AppColors.success,
              vs: visits.isEmpty
                  ? ''
                  : tr('{p0}٪ إتمام', {'p0': (done.length * 100 / visits.length).round()}),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.skipForward,
              label: tr('متخطّاة'),
              value: '${of('skipped').length}',
              tint: AppColors.warning,
              vs: tr('بسببٍ مسجَّل'),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.currencyCircleDollar,
              label: tr('قيمة الطلبات'),
              value: orders.toStringAsFixed(0),
              tint: AppColors.success,
              vs: tr('من الزيارات المنفَّذة'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // ⚠️ شريحةُ المسار **ليست زينة**: `watchRouteVisits` تقرأ مساراً واحداً،
        //    فلا لوحةَ تجمع كلَّ المسارات كما في التصميم. والمشغّلُ يختار.
        PicPosBlockHeader(
          title: tr('لوحة زيارات الشهر'),
          subtitle: 'المسارُ المعروض: ${routes.where((r) => r.id == routeId)
              .firstOrNull?.name ?? '—'}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in routes)
              ChoiceChip(
                label: Text(r.name),
                selected: r.id == routeId,
                onSelected: (_) => setState(() => _visitRouteId = r.id),
              ),
          ],
        ),
        const SizedBox(height: 14),
        PicPosStatusBoard(
          emptyLabel: tr('لا زيارات'),
          columns: [
            for (final s in statuses)
              PicPosBoardColumn(
                label: s.$2,
                icon: s.$3,
                tint: s.$4,
                total: of(s.$1).length,
                cards: [
                  for (final v in of(s.$1).take(4))
                    PicPosBoardCard(
                      title: tr('عميل #{p0}', {'p0': v.customerId}),
                      subtitle:
                          '${v.visitDate.year}-${v.visitDate.month.toString().padLeft(2, '0')}-${v.visitDate.day.toString().padLeft(2, '0')}',
                      value: v.orderAmount > 0
                          ? v.orderAmount.toStringAsFixed(0)
                          : '—',
                      meta: v.saleId != null
                          ? tr('أنتجت فاتورة')
                          : _repName(reps, v.salesRepId),
                      metaIcon: v.saleId != null
                          ? PhosphorIconsBold.receipt
                          : PhosphorIconsBold.user,
                      metaTint:
                          v.saleId != null ? AppColors.success : null,
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // ── الأهداف والتحصيل ───────────────────────────────────────────────────

  Widget _targetsTab(
    BuildContext context,
    List<SalesRepTarget> targets,
    List<Employee> reps,
  ) {
    final shown = targets
        .where((t) => _hit(_repName(reps, t.salesRepId)))
        .toList();
    final totalTarget = targets.fold<double>(0, (s, t) => s + t.targetAmount);
    final totalDone = targets.fold<double>(0, (s, t) => s + t.achievedAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.target,
              label: tr('هدفُ الشهر'),
              value: totalTarget.toStringAsFixed(0),
              tint: AppColors.primary,
              vs: tr('{p0} مندوباً', {'p0': targets.length}),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.currencyCircleDollar,
              label: tr('المحقَّق'),
              value: totalDone.toStringAsFixed(0),
              tint: AppColors.success,
              vs: totalTarget == 0
                  ? tr('لا هدفَ مضبوط')
                  : tr('{p0}٪ من الهدف', {'p0': (totalDone * 100 / totalTarget).round()}),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: tr('أهداف المناديب'),
          subtitle: tr('الهدف شهري بالقيمة وبعدد الزيارات معاً'),
          emptyLabel: tr('لا أهدافَ لهذا الشهر'),
          columns:  [
            PicPosTableColumn(tr('المندوب'), flex: 1.8),
            PicPosTableColumn(tr('هدف القيمة'), flex: 1.2,
                align: PicPosCellAlign.end),
            PicPosTableColumn(tr('المحقَّق'), flex: 1.2,
                align: PicPosCellAlign.end),
            PicPosTableColumn(tr('نسبة الإنجاز'), flex: 1.6),
            PicPosTableColumn(tr('الزيارات'), flex: 1.2,
                align: PicPosCellAlign.end),
          ],
          rows: [
            for (final t in shown)
              PicPosTableRow(
                cells: [
                  PicPosTextCell(
                    _repName(reps, t.salesRepId),
                    icon: PhosphorIconsBold.user,
                    tint: AppColors.primary,
                  ),
                  PicPosTextCell(t.targetAmount.toStringAsFixed(0)),
                  PicPosTextCell(t.achievedAmount.toStringAsFixed(0)),
                  PicPosBarCell(
                    t.targetAmount == 0
                        ? '—'
                        : tr('{p0}٪', {'p0': (t.achievedAmount * 100 / t.targetAmount).round()}),
                    t.targetAmount == 0
                        ? 0
                        : t.achievedAmount / t.targetAmount,
                    t.targetAmount != 0 &&
                            t.achievedAmount >= t.targetAmount
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  PicPosTextCell('${t.achievedVisits}/${t.targetVisits}'),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // ── شركات التوصيل ──────────────────────────────────────────────────────

  Widget _companiesTab(BuildContext context, List<DeliveryCompany> companies) {
    final shown = companies.where((c) => _hit(c.name)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.moped,
              label: tr('شركاتُ التوصيل'),
              value: '${companies.length}',
              tint: AppColors.primary,
              vs: '${companies.where((c) => c.isActive).length} نشطة',
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: tr('شركات التوصيل'),
          subtitle: tr('المندوب يتبع شركة أو يكون داخلياً'),
          emptyLabel: tr('لا شركاتِ توصيلٍ مسجَّلة'),
          columns:  [
            PicPosTableColumn(tr('الشركة'), flex: 1.8),
            PicPosTableColumn(tr('الهاتف'), flex: 1.3),
            PicPosTableColumn(tr('العنوان'), flex: 2.0),
            PicPosTableColumn(tr('الحالة'), flex: 1.1),
          ],
          rows: [
            for (final c in shown)
              PicPosTableRow(
                cells: [
                  PicPosTextCell(
                    c.name,
                    icon: PhosphorIconsBold.moped,
                    tint: AppColors.primary,
                  ),
                  PicPosTextCell(c.phone ?? '—'),
                  PicPosTextCell(c.address ?? '—'),
                  PicPosPillCell(
                    c.isActive ? tr('نشطة') : tr('موقوفة'),
                    c.isActive ? AppColors.success : AppColors.textMuted,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.picposMuted,
            ),
          ),
        ),
      );
}
