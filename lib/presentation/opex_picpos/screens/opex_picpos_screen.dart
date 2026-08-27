// شاشةُ «المصاريف التشغيلية» بهويّة PicPos — على تصميم
// `PicPos Operating Expenses.dc.html` بتبويباته الخمسة.
//
// ═══ لماذا فوركٌ كاملٌ لا إعادةُ تنسيق ═══
//
// القائمُ `operational_expenses_screen.dart` **٩٠ سطراً بتبويبَين**
// (‏فئاتُ المصروفات · سجلُّ المصروفات) بلا `picpos_shell` ولا KPI ولا رأسٍ
// بأفعال. والتصميمُ **خمسةُ تبويباتٍ** وفعلان في الرأس. فهذا بناءُ شاشةٍ
// لا تنسيقُ واحدة.
//
// ═══ والطبقةُ البيانيّةُ تغطّي أربعةً من الخمسة بلا جدولٍ جديد ═══
//
// مقيسٌ 2026-08-28:
//
// | التبويب | المصدر |
// |---|---|
// | `list` | `getExpensesForReport` — بالفئة والفرع والحالة وطريقة الدفع |
// | `cats` | `OpExpenseCategories` بأعمدتها كلِّها + `watchExpenseCategories` |
// | `mfg` | `MfgOrderCosts` + `ManufacturingOrders` |
// | `budget` | `IBudgetRepository.getBudgetVsActualReport` |
//
// ═══ 🔴 والخامسُ (`flow`) خالف التصميمُ فيه المحرّك ═══
//
// ملاحظةُ التصميم: «مسوّدة ← معتمد ← مسدَّد — **القيد ينشأ عند الاعتماد**».
// والمقيسُ خلافُه تماماً:
//
// • عمودُ `status` موجودٌ في `OpExpenses` و**لا يُكتَب في أيّ موضعٍ من
//   المستودع** — فكلُّ مصروفٍ يبقى `draft` إلى الأبد.
// • و`recordAndPostOperationalExpense` يُنشئ القيدَ وسندَ الصرف وخصمَ الخزنة
//   **عند التسجيل**.
//
// ⇒ فترحيلُ قيدٍ عند الاعتماد يعني مصروفاً مقيَّداً مرّتَين. وقرارُ المالك
//   (‏2026-08-28): تُوصَّل الانتقالاتُ بلا تحريكِ موضعِ القيد، وتُقال الحقيقةُ
//   في ملاحظة التبويب بدل نصِّ التصميم المخالف.
//
// ═══ ⚠️ ولا يستوردُ هذا الملفُّ `data/database` ═══
//
// حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ جديدٍ من ذلك.
// والأنواعُ تصل عبر واجهات `domain/repositories/` — فهي تستورد طبقةَ القاعدة
// بلا بادئةٍ فتُصدِّر أنواعَها.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/accounting_repository.dart';
import '../../../domain/repositories/manufacturing_repository.dart';
import '../../picpos_shell/picpos_bar_list.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_status_board.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _money0 = NumberFormat('#,##0', 'en');

const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _err = Color(0xFFEF4444);
const _purple = Color(0xFF8B5CF6);
const _blue = Color(0xFF4A80E8);
const _idle = Color(0xFF6B7280);

/// أرقامُ العدّ بأرقامٍ عربيّةٍ كما في التصميم؛ والمبالغُ تبقى لاتينيّةً
/// (`208,680`) كما يعرضها التصميمُ نفسُه.
String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

/// ملاحظاتُ التبويبات — `TABS.main[].note` حرفيّاً، **إلّا `flow`**.
///
/// ⚠️ نصُّ التصميم هناك «القيد ينشأ عند الاعتماد» وهو **غيرُ صحيحٍ في
/// المحرّك**: القيدُ يُرحَّل عند التسجيل. ونقلُ نصٍّ خاطئٍ حرفيّاً يجعل
/// الشاشةَ تُعلّم المستخدمَ محاسبةً لا تقع.
const _tabNotes = [
  'المصروف يتبع فئة وفرعاً ومركز تكلفة',
  'طريقة التحميل تحدد كيف يُوزَّع المصروف على الإنتاج',
  'تكلفة الأمر = خامات + أجور + تحميل غير مباشر',
  'القيد يُرحَّل عند تسجيل المصروف — والاعتماد والسداد أثرُ مراجعة',
  'الموازنة شهرية لكل حساب مصروف',
];

/// حالاتُ المصروف — قيمُ العمود `status` كما يعرّفها الجدول.
const _statusLabels = <String, (String, Color)>{
  'draft': ('مسوّدة', _warn),
  'approved': ('معتمد', AppColors.primary),
  'paid': ('مسدَّد', _ok),
};

const _periodLabels = <String, (String, Color)>{
  'monthly': ('شهري', AppColors.primary),
  'weekly': ('أسبوعي', _blue),
  'daily': ('يومي', _ok),
  'one_time': ('لمرة واحدة', _purple),
};

const _catTypeLabels = <String, (String, Color)>{
  'direct': ('مباشرة', _purple),
  'indirect': ('غير مباشرة', _idle),
  'fixed': ('ثابتة', AppColors.primary),
  'variable': ('متغيرة', _warn),
};

const _allocationLabels = <String, String>{
  'per_unit': 'لكل وحدة منتجة',
  'per_hour': 'لكل ساعة تشغيل',
  'per_order': 'لكل أمر تصنيع',
  'fixed_monthly': 'ثابت شهرياً',
};

/// أنواعُ تكلفة أمر التصنيع — قيمُ `MfgOrderCosts.costType`.
const _costTypeLabels = <String, String>{
  'raw_material': 'خامات',
  'labor': 'أجور',
  'overhead': 'تحميل',
  'depreciation': 'إهلاك',
  'utility': 'مرافق',
  'other': 'أخرى',
};

// ═══════════════════════════════════════════════════════════════════════════
// المزوّدات
// ═══════════════════════════════════════════════════════════════════════════

final _categoriesProvider =
    StreamProvider.autoDispose<List<OpExpenseCategoryData>>(
        (ref) => ref.watch(manufacturingRepositoryProvider)
            .watchExpenseCategories());

/// نافذةُ التقرير — الشهرُ الجاري، وهو مدى KPI «مصروفات الشهر» في التصميم.
final _monthWindowProvider = Provider.autoDispose<(DateTime, DateTime)>((ref) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, 1);
  // آخرُ لحظةٍ في الشهر — `DateTime(y, m+1, 0)` يعطي آخرَ يومٍ فيه.
  final to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  return (from, to);
});

final _expensesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final (from, to) = ref.watch(_monthWindowProvider);
  return ref
      .watch(manufacturingRepositoryProvider)
      .getExpensesForReport(from: from, to: to);
});

final _ordersProvider =
    StreamProvider.autoDispose<List<ManufacturingOrderData>>((ref) =>
        ref.watch(manufacturingRepositoryProvider).watchManufacturingOrders());

final _orderCostsProvider =
    StreamProvider.autoDispose<List<MfgOrderCostData>>((ref) =>
        ref.watch(manufacturingRepositoryProvider).watchAllMfgOrderCosts());

/// المنفَّذُ مقابلَ الموازنة للسنة الماليّة الجارية.
///
/// ⚠️ **بلا سنةٍ ماليّةٍ لا موازنة** — والقائمةُ الفارغةُ هنا تعني ذلك لا
/// «صفرُ تجاوزات». والتبويبُ يقول أيَّهما.
final _budgetProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final year =
      await ref.watch(accountingRepositoryProvider).getCurrentFiscalYear();
  if (year == null) return const [];
  return ref.watch(budgetRepositoryProvider).getBudgetVsActualReport(year.id);
});

// ═══════════════════════════════════════════════════════════════════════════

class OpexPicposScreen extends ConsumerStatefulWidget {
  const OpexPicposScreen({super.key});

  @override
  ConsumerState<OpexPicposScreen> createState() => _OpexPicposScreenState();
}

class _OpexPicposScreenState extends ConsumerState<OpexPicposScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Map<int, int> _chip = {};

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

  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  static String _d(DateTime? x) => x == null
      ? '—'
      : '${x.year}-${x.month.toString().padLeft(2, '0')}-'
          '${x.day.toString().padLeft(2, '0')}';

  // ── الرأس ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(_expensesProvider).value ?? const [];
    final categories = ref.watch(_categoriesProvider).value ?? const [];
    final orders = ref.watch(_ordersProvider).value ?? const [];
    final costs = ref.watch(_orderCostsProvider).value ?? const [];
    final budget = ref.watch(_budgetProvider).value ?? const [];

    final drafts = expenses.where((e) => e['status'] == 'draft').length;

    return PicPosScreenScaffold(
      title: 'المصاريف التشغيلية',
      subtitle: 'المصروفات وفئاتها وقواعد التحميل والاعتماد والسداد',
      icon: PhosphorIconsBold.receiptX,
      // ⚠️ **فعلا الرأس يأتيان في الدفعة التالية.** `HEADS.main` يعرّف
      //    «مصروف جديد» و«تحميل على أمر تصنيع»، وكلاهما **كتابةٌ ماليّة**:
      //    الأوّلُ يقيّد قيدَ يوميّةٍ ويخصم من الخزنة، والثاني يدخل تكلفةَ
      //    أمرٍ ثمّ تكلفةَ الوحدة.
      //
      // 🔴 ولا كودَ صلاحيّةٍ للمصروفات التشغيليّة في `PermissionCodes` —
      //    الشاشةُ محصورةٌ بالنطاق وحدَه (`screen_registry.dart:202`). فزرُّ
      //    كتابةٍ اليومَ يكون بلا حارسٍ، وحصرُ التنقّل يفتح الشاشةَ للقراءة
      //    لأيّ دور. ⇒ الكودُ يُسَنّ ويُنفَّذ مع الفعلَين معاً لا قبلهما.
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'ابحث بالمرجع أو الفئة...',
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
                label: 'المصروفات',
                icon: PhosphorIconsBold.receiptX,
                badge: '${expenses.length}'
              ),
              (
                label: 'الفئات وقواعد التحميل',
                icon: PhosphorIconsBold.folders,
                badge: '${categories.length}'
              ),
              (
                label: 'تحميل أوامر التصنيع',
                icon: PhosphorIconsBold.factory,
                badge: '${orders.length}'
              ),
              (
                label: 'الاعتماد والسداد',
                icon: PhosphorIconsBold.sealCheck,
                badge: '$drafts'
              ),
              (
                label: 'مقابل الموازنة',
                icon: PhosphorIconsBold.chartLine,
                badge: null
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
          _scroll(_listTab(expenses)),
          _scroll(_catsTab(categories)),
          _scroll(_mfgTab(orders, costs)),
          _scroll(_flowTab(expenses)),
          _scroll(_budgetTab(budget, expenses)),
        ],
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
        child: child,
      );

  // ── ١ · المصروفات ───────────────────────────────────────────────────────

  Widget _listTab(List<Map<String, dynamic>> expenses) {
    final chipDefs = <(String, bool Function(Map<String, dynamic>))>[
      ('الكل', (e) => true),
      ('مسوّدة', (e) => e['status'] == 'draft'),
      ('معتمد', (e) => e['status'] == 'approved'),
      ('مسدَّد', (e) => e['status'] == 'paid'),
    ];
    final pick = _chip[0] ?? 0;
    final shown = expenses
        .where((e) =>
            chipDefs[pick].$2(e) &&
            (_hit(e['category_name'] as String?) ||
                _hit(e['reference'] as String?) ||
                _hit(e['notes'] as String?)))
        .toList();

    final total = expenses.fold<double>(0, (s, e) => s + _num(e['amount']));
    // ⚠️ «ثابتة/متغيرة» من **نوع الفئة** لا من الدورية: التصميمُ يفصلهما
    //    في KPI مستقلَّين، ونوعُ الفئة هو ما يحملهما.
    final fixed = expenses
        .where((e) => e['category_type'] == 'fixed')
        .fold<double>(0, (s, e) => s + _num(e['amount']));
    final variable = expenses
        .where((e) => e['category_type'] == 'variable')
        .fold<double>(0, (s, e) => s + _num(e['amount']));
    final pending = expenses.where((e) => e['status'] == 'draft').toList();
    final pendingSum =
        pending.fold<double>(0, (s, e) => s + _num(e['amount']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.receiptX,
              label: 'مصروفات الشهر',
              value: _money0.format(total),
              tint: _err,
              vs: '${_ar(expenses.length)} بنداً',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.lockSimple,
              label: 'ثابتة',
              value: _money0.format(fixed),
              tint: AppColors.primary,
              vs: total > 0
                  ? '${_ar((fixed / total * 100).round())}٪ من المصروف'
                  : '',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.waves,
              label: 'متغيرة',
              value: _money0.format(variable),
              tint: _warn,
              vs: total > 0
                  ? '${_ar((variable / total * 100).round())}٪'
                  : '',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.clock,
              label: 'بانتظار الاعتماد',
              value: _ar(pending.length),
              tint: _warn,
              up: false,
              vs: '${_money0.format(pendingSum)} ج.م',
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: 'سجل المصروفات',
          subtitle: 'كل مصروف بفئته وفرعه وحالته وطريقة دفعه',
          emptyLabel: 'لا مصروفاتِ مطابقة في هذا الشهر',
          columns: const [
            PicPosTableColumn('الفئة والبيان', flex: 1.8),
            PicPosTableColumn('الفرع', flex: 1.3),
            PicPosTableColumn('المبلغ', flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('التاريخ', flex: 1.2),
            PicPosTableColumn('الدورية', flex: 1.2),
            PicPosTableColumn('طريقة الدفع', flex: 1.1),
            PicPosTableColumn('الحالة', flex: 1.2),
          ],
          chips: [
            for (var i = 0; i < chipDefs.length; i++)
              PicPosTableChip(
                label: chipDefs[i].$1,
                count: '${expenses.where(chipDefs[i].$2).length}',
                onTap: () => setState(() => _chip[0] = i),
              ),
          ],
          selectedChip: pick,
          rows: [
            for (final e in shown)
              PicPosTableRow(cells: [
                PicPosTextCell(
                  '${e['category_name'] ?? '—'}',
                  sub: (e['notes'] ?? e['reference']) as String?,
                  icon: PhosphorIconsBold.receiptX,
                  tint: _catTypeLabels[e['category_type']]?.$2 ??
                      AppColors.primary,
                ),
                PicPosTextCell('${e['branch_name'] ?? 'كل الفروع'}'),
                PicPosTextCell(_money.format(_num(e['amount']))),
                PicPosTextCell(_d(e['expense_date'] as DateTime?)),
                PicPosPillCell(
                  _periodLabels[e['period']]?.$1 ?? '${e['period'] ?? '—'}',
                  _periodLabels[e['period']]?.$2 ?? _idle,
                ),
                PicPosTextCell(
                  e['payment_method'] == 'bank' ? 'بنك' : 'نقدي',
                ),
                // ⚠️ صفُّ `safe_tx` يصل بـ`status == null` — راجع
                //    `getExpensesForReport`. و«—» أصدقُ من «مسوّدة».
                PicPosPillCell(
                  _statusLabels[e['status']]?.$1 ?? '—',
                  _statusLabels[e['status']]?.$2 ?? _idle,
                ),
              ]),
          ],
          totals: [
            '${_ar(shown.length)} بنداً',
            '',
            _money.format(
                shown.fold<double>(0, (s, e) => s + _num(e['amount']))),
            '',
            '',
            '',
            '',
          ],
        ),
      ],
    );
  }

  // ── ٢ · الفئات وقواعد التحميل ───────────────────────────────────────────

  Widget _catsTab(List<OpExpenseCategoryData> categories) {
    final chipDefs = <(String, bool Function(OpExpenseCategoryData))>[
      ('الكل', (c) => true),
      ('إنتاجية', (c) => c.isProductionRelated),
      ('غير إنتاجية', (c) => !c.isProductionRelated),
    ];
    final pick = _chip[1] ?? 0;
    final shown = categories
        .where((c) => chipDefs[pick].$2(c) && _hit(c.name))
        .toList();

    final active = categories.where((c) => c.isActive).length;
    final production = categories.where((c) => c.isProductionRelated).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.folders,
              label: 'فئات نشطة',
              value: _ar(active),
              tint: AppColors.primary,
              vs: 'من ${_ar(categories.length)}',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.factory,
              label: 'مرتبطة بالإنتاج',
              value: _ar(production),
              tint: _purple,
              vs: 'تُحمَّل على الأوامر',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.lockSimple,
              label: 'ثابتة شهرياً',
              value: _ar(categories
                  .where((c) => c.allocationMethod == 'fixed_monthly')
                  .length),
              tint: _blue,
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.waves,
              label: 'متغيرة',
              value:
                  _ar(categories.where((c) => c.type == 'variable').length),
              tint: _warn,
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: 'فئات المصروفات',
          subtitle:
              'النوع وطريقة التحميل تحددان كيف يدخل المصروف في تكلفة الوحدة',
          emptyLabel: 'لا فئاتِ مصروفاتٍ بعد',
          columns: const [
            PicPosTableColumn('الفئة', flex: 1.8),
            PicPosTableColumn('النوع', flex: 1.2),
            PicPosTableColumn('مرتبطة بالإنتاج', flex: 1.4),
            PicPosTableColumn('طريقة التحميل', flex: 1.6),
            PicPosTableColumn('المعدل', flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('حساب الأستاذ', flex: 1.3),
          ],
          chips: [
            for (var i = 0; i < chipDefs.length; i++)
              PicPosTableChip(
                label: chipDefs[i].$1,
                count: '${categories.where(chipDefs[i].$2).length}',
                onTap: () => setState(() => _chip[1] = i),
              ),
          ],
          selectedChip: pick,
          rows: [
            for (final c in shown)
              PicPosTableRow(cells: [
                PicPosTextCell(
                  c.name,
                  icon: PhosphorIconsBold.folders,
                  tint: _catTypeLabels[c.type]?.$2 ?? _idle,
                  sub: c.isActive ? null : 'غير نشطة',
                ),
                PicPosPillCell(
                  _catTypeLabels[c.type]?.$1 ?? c.type,
                  _catTypeLabels[c.type]?.$2 ?? _idle,
                ),
                PicPosTextCell(c.isProductionRelated ? 'نعم' : 'لا'),
                PicPosTextCell(
                  _allocationLabels[c.allocationMethod] ?? c.allocationMethod,
                ),
                // ⚠️ «ثابت شهرياً» لا معدّلَ له — و«0.00» تُقرأ معدّلاً
                //    صفريّاً مضبوطاً عمداً، وهو معنًى آخر. التصميمُ يكتب «—».
                PicPosTextCell(
                  c.allocationMethod == 'fixed_monthly'
                      ? '—'
                      : _money.format(c.defaultRate),
                ),
                PicPosTextCell(c.accountCode),
              ]),
          ],
        ),
      ],
    );
  }

  // ── ٣ · تحميل أوامر التصنيع ─────────────────────────────────────────────

  Widget _mfgTab(
    List<ManufacturingOrderData> orders,
    List<MfgOrderCostData> costs,
  ) {
    // تجميعُ التكاليف بالأمر **مرّةً واحدة** — لا استعلامَ لكلّ صفّ.
    final byOrder = <int, Map<String, double>>{};
    for (final c in costs) {
      (byOrder[c.orderId] ??= {})
          .update(c.costType, (v) => v + c.amount, ifAbsent: () => c.amount);
    }

    double part(int orderId, String type) => byOrder[orderId]?[type] ?? 0;
    double loaded(int orderId) =>
        part(orderId, 'overhead') +
        part(orderId, 'utility') +
        part(orderId, 'depreciation');

    final open = orders
        .where((o) => o.status != 'cancelled' && _hit(o.orderNumber))
        .toList();

    final chipDefs = <(String, bool Function(ManufacturingOrderData))>[
      ('الكل', (o) => true),
      ('ناقص التحميل', (o) => loaded(o.id) == 0),
    ];
    final pick = _chip[2] ?? 0;
    final shown = open.where(chipDefs[pick].$2).toList();

    final totalLoaded = open.fold<double>(0, (s, o) => s + loaded(o.id));
    final totalCost = open.fold<double>(0, (s, o) => s + o.totalCost);
    final unloaded = open.where((o) => loaded(o.id) == 0).length;

    final raw = open.fold<double>(0, (s, o) => s + part(o.id, 'raw_material'));
    final labor = open.fold<double>(0, (s, o) => s + part(o.id, 'labor'));
    final depr =
        open.fold<double>(0, (s, o) => s + part(o.id, 'depreciation'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.factory,
              label: 'أوامر تصنيع',
              value: _ar(open.length),
              tint: _purple,
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.handCoins,
              label: 'تكلفة محمَّلة',
              value: _money0.format(totalLoaded),
              tint: _warn,
              vs: 'تحميلٌ ومرافقُ وإهلاك',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.percent,
              label: 'نسبة التحميل غير المباشر',
              value: totalCost > 0
                  ? '${_ar((totalLoaded / totalCost * 100).toStringAsFixed(1))}٪'
                  : '—',
              tint: AppColors.primary,
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.warning,
              label: 'أوامر بلا تحميل',
              value: _ar(unloaded),
              tint: _err,
              up: false,
              vs: 'تكلفتها ناقصة',
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: 'تفصيل تكلفة أوامر التصنيع',
          subtitle: 'كل أمر يُحمَّل خامات وأجوراً وتحميلاً غير مباشر',
          emptyLabel: 'لا أوامرَ تصنيعٍ مطابقة',
          columns: const [
            PicPosTableColumn('أمر التصنيع', flex: 1.6),
            PicPosTableColumn('الكمية', flex: 1.1, align: PicPosCellAlign.end),
            PicPosTableColumn('خامات', flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('أجور', flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('تحميل', flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('التكلفة', flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('تكلفة الوحدة',
                flex: 1.3, align: PicPosCellAlign.end),
          ],
          chips: [
            for (var i = 0; i < chipDefs.length; i++)
              PicPosTableChip(
                label: chipDefs[i].$1,
                count: '${open.where(chipDefs[i].$2).length}',
                onTap: () => setState(() => _chip[2] = i),
              ),
          ],
          selectedChip: pick,
          rows: [
            for (final o in shown)
              PicPosTableRow(cells: [
                PicPosTextCell(
                  o.orderNumber,
                  sub: loaded(o.id) == 0 ? 'بلا تحميل' : o.status,
                  icon: loaded(o.id) == 0
                      ? PhosphorIconsBold.warning
                      : PhosphorIconsBold.factory,
                  tint: loaded(o.id) == 0 ? _err : _ok,
                ),
                // ⚠️ **المنتَجةُ لا المطلوبة**: تكلفةُ الوحدة تُقسَم على ما
                //    خرج فعلاً، وأمرٌ جارٍ أنتج نصفَ كمّيّته تكلفةُ وحدته
                //    ضِعفُ ما يُحسَب بالمطلوبة.
                PicPosTextCell(_ar(
                    (o.producedQty > 0 ? o.producedQty : o.orderedQty)
                        .toStringAsFixed(0))),
                PicPosTextCell(_money0.format(part(o.id, 'raw_material'))),
                PicPosTextCell(_money0.format(part(o.id, 'labor'))),
                PicPosTextCell(_money0.format(loaded(o.id))),
                PicPosTextCell(_money0.format(o.totalCost)),
                PicPosTextCell(
                  o.producedQty > 0
                      ? _money.format(o.totalCost / o.producedQty)
                      : '—',
                ),
              ]),
          ],
          totals: [
            '${_ar(shown.length)} أمراً',
            '',
            _money0.format(raw),
            _money0.format(labor),
            _money0.format(totalLoaded),
            _money0.format(totalCost),
            '',
          ],
        ),
        const SizedBox(height: 16),
        PicPosBarList(
          title: 'مكوّنات تكلفة الإنتاج',
          subtitle: 'الأوامر المعروضة · ج.م',
          emptyHint: 'لا تكاليفَ مسجّلةٌ على الأوامر بعد',
          items: [
            PicPosBarItem(
              label: 'خامات مباشرة',
              sub: _costTypeLabels['raw_material']!,
              value: raw,
              display: _money0.format(raw),
              icon: PhosphorIconsBold.package,
              tint: AppColors.primary,
            ),
            PicPosBarItem(
              label: 'أجور مباشرة',
              sub: _costTypeLabels['labor']!,
              value: labor,
              display: _money0.format(labor),
              icon: PhosphorIconsBold.users,
              tint: _ok,
            ),
            PicPosBarItem(
              label: 'تحميل غير مباشر',
              sub: 'تحميلٌ ومرافق',
              value: totalLoaded - depr,
              display: _money0.format(totalLoaded - depr),
              icon: PhosphorIconsBold.lightning,
              tint: _warn,
            ),
            PicPosBarItem(
              label: 'إهلاك آلات',
              sub: _costTypeLabels['depreciation']!,
              value: depr,
              display: _money0.format(depr),
              icon: PhosphorIconsBold.arrowDownRight,
              tint: _purple,
            ),
          ],
        ),
      ],
    );
  }

  // ── ٤ · الاعتماد والسداد ────────────────────────────────────────────────

  Widget _flowTab(List<Map<String, dynamic>> expenses) {
    List<Map<String, dynamic>> of(String status) =>
        expenses.where((e) => e['status'] == status).toList();

    double sum(List<Map<String, dynamic>> l) =>
        l.fold<double>(0, (s, e) => s + _num(e['amount']));

    final drafts = of('draft');
    final approved = of('approved');
    final paid = of('paid');

    PicPosBoardColumn column(
      String label,
      IconData icon,
      Color tint,
      List<Map<String, dynamic>> rows,
    ) =>
        PicPosBoardColumn(
          label: label,
          icon: icon,
          tint: tint,
          total: rows.length,
          cards: [
            // ‏ستٌّ لكلّ عمود — واللوحةُ تعرض العددَ الكاملَ في ترويستها،
            // فلا يُخفى شيءٌ بلا ذكر.
            for (final e in rows.take(6))
              PicPosBoardCard(
                title: '${e['category_name'] ?? '—'}',
                subtitle: '${e['branch_name'] ?? 'كل الفروع'} · '
                    '${_d(e['expense_date'] as DateTime?)}',
                value: _money.format(_num(e['amount'])),
                meta: '${e['user_name'] ?? 'غير معروف'}',
                metaIcon: PhosphorIconsBold.user,
                metaTint: tint,
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.fileDashed,
              label: 'مسوّدات',
              value: _ar(drafts.length),
              tint: _warn,
              up: false,
              vs: '${_money0.format(sum(drafts))} ج.م',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.sealCheck,
              label: 'معتمدة بانتظار السداد',
              value: _ar(approved.length),
              tint: AppColors.primary,
              vs: '${_money0.format(sum(approved))} ج.م',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.checkCircle,
              label: 'مسدَّدة',
              value: _ar(paid.length),
              tint: _ok,
              vs: '${_money0.format(sum(paid))} ج.م',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.receiptX,
              label: 'إجمالي الشهر',
              value: _money0.format(sum(expenses)),
              tint: _err,
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosStatusBoard(
          emptyLabel: 'لا مصروفاتِ هذا الشهر',
          columns: [
            column('مسوّدة', PhosphorIconsBold.fileDashed, _warn, drafts),
            column('معتمدة', PhosphorIconsBold.sealCheck, AppColors.primary,
                approved),
            column('مسدَّدة', PhosphorIconsBold.checkCircle, _ok, paid),
          ],
        ),
      ],
    );
  }

  // ── ٥ · مقابل الموازنة ──────────────────────────────────────────────────

  Widget _budgetTab(
    List<Map<String, dynamic>> budget,
    List<Map<String, dynamic>> expenses,
  ) {
    if (budget.isEmpty) {
      // ⚠️ **فراغان مختلفان**: لا سنةَ ماليّةً، أو سنةٌ بلا موازنات. وكلاهما
      //    ليس «صفرَ تجاوزات» — وقولُ ذلك يمنع قراءةَ الجدول الفارغ اطمئناناً.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(PhosphorIconsBold.chartLine, size: 34, color: _idle),
            SizedBox(height: 10),
            Text(
              'لا موازناتٌ مسجَّلةٌ للسنة المالية الجارية',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text(
              'الجدولُ فارغٌ لغياب الموازنة لا لانعدام التجاوز.',
              style: TextStyle(fontSize: 12, color: _idle),
            ),
          ],
        ),
      );
    }

    final chipDefs = <(String, bool Function(Map<String, dynamic>))>[
      ('كل البنود', (b) => true),
      ('تجاوز', (b) => _num(b['utilizationPct']) > 100),
    ];
    final pick = _chip[4] ?? 0;
    final shown = budget
        .where((b) =>
            chipDefs[pick].$2(b) && _hit(b['accountName'] as String?))
        .toList();

    (String, Color) verdict(double pct) {
      if (pct > 100) return ('تجاوز', _err);
      if (pct >= 95) return ('قارب الحد', _warn);
      if (pct < 40) return ('غير مستغلة', _err);
      return ('سليم', _ok);
    }

    // مصروفُ الشهر بمركز التكلفة — شريطُ التصميم الثاني.
    final byCostCentre = <String, double>{};
    for (final e in expenses) {
      final key = '${e['category_name'] ?? 'غير مصنَّف'}';
      byCostCentre.update(key, (v) => v + _num(e['amount']),
          ifAbsent: () => _num(e['amount']));
    }
    final topCategories = byCostCentre.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosDataTable(
          title: 'المنفَّذ مقابل الموازنة',
          subtitle: 'الموازنة لكل حساب مصروف في السنة المالية الجارية',
          emptyLabel: 'لا بنودَ مطابقة',
          columns: const [
            PicPosTableColumn('البند', flex: 1.8),
            PicPosTableColumn('الحساب', flex: 1.1),
            PicPosTableColumn('الموازنة',
                flex: 1.3, align: PicPosCellAlign.end),
            PicPosTableColumn('المنفَّذ', flex: 1.3, align: PicPosCellAlign.end),
            PicPosTableColumn('الفرق', flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('الاستهلاك', flex: 1.5),
            PicPosTableColumn('الحالة', flex: 1.3),
          ],
          chips: [
            for (var i = 0; i < chipDefs.length; i++)
              PicPosTableChip(
                label: chipDefs[i].$1,
                count: '${budget.where(chipDefs[i].$2).length}',
                onTap: () => setState(() => _chip[4] = i),
              ),
          ],
          selectedChip: pick,
          rows: [
            for (final b in shown)
              () {
                final planned = _num(b['totalPlanned']);
                final actual = _num(b['totalActual']);
                final pct = _num(b['utilizationPct']);
                final (label, tint) = verdict(pct);
                return PicPosTableRow(cells: [
                  PicPosTextCell(
                    '${b['accountName']}',
                    icon: PhosphorIconsBold.chartLine,
                    tint: tint,
                  ),
                  PicPosTextCell('${b['accountCode']}'),
                  PicPosTextCell(_money0.format(planned)),
                  PicPosTextCell(_money0.format(actual)),
                  // ⚠️ **الفرقُ موازنةٌ ناقصَ منفَّذ**: `variance` في التقرير
                  //    معكوسٌ (`actual - planned`)، فنقلُه كما هو يجعل
                  //    التوفيرَ سالباً والتجاوزَ موجباً — وهو عكسُ ما يقرؤه
                  //    المحاسب.
                  PicPosTextCell(_money0.format(planned - actual)),
                  PicPosBarCell(
                    '${_ar(pct.round())}٪',
                    // الشريطُ يُقصَّ عند المائة والنصُّ يقول الحقيقةَ كاملةً.
                    pct.clamp(0, 100) / 100,
                    tint,
                  ),
                  PicPosPillCell(label, tint),
                ]);
              }(),
          ],
          totals: [
            '${_ar(shown.length)} بنداً',
            '',
            _money0.format(
                shown.fold<double>(0, (s, b) => s + _num(b['totalPlanned']))),
            _money0.format(
                shown.fold<double>(0, (s, b) => s + _num(b['totalActual']))),
            _money0.format(shown.fold<double>(
                0,
                (s, b) =>
                    s + _num(b['totalPlanned']) - _num(b['totalActual']))),
            '',
            '',
          ],
        ),
        const SizedBox(height: 16),
        PicPosBarList(
          title: 'المصروف حسب الفئة',
          subtitle: 'الشهر الجاري · ج.م',
          emptyHint: 'لا مصروفاتِ هذا الشهر',
          items: [
            for (final e in topCategories.take(6))
              PicPosBarItem(
                label: e.key,
                sub: '',
                value: e.value,
                display: _money0.format(e.value),
                icon: PhosphorIconsBold.target,
                tint: AppColors.primary,
              ),
          ],
        ),
      ],
    );
  }
}
