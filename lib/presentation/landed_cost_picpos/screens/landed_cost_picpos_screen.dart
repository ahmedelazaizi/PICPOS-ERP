import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/design_system/typography.dart';
// شاشةُ «التكاليف المحمَّلة» بهويّة PicPos — على تصميم `PicPos Landed Costs.dc.html`.
//
// ═══ إعادةُ تنسيقٍ لا بناء ═══
//
// الطبقةُ البيانيّةُ مشحونةٌ سلفاً وكاملة: `LandedCostSheets` بحالاتها الأربع
// (‏`draft` · `applied` · `cancelled` · `voided`) و`LandedCostItems` بأنواعها
// الستّة و`LandedCostAllocations`، و`landed_cost_dao` يحسب التوزيعَ بالطرق
// الثلاث ويطبّق القيدَ ذرّيّاً. فلا جدولَ جديدَ هنا ولا `build_runner` —
// طبقةُ العرضِ وحدَها هي التي تبدّلت.
//
// ═══ ⚠️ ولا يستوردُ هذا الملفُّ `data/database` ═══
//
// حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ **جديد** من
// استيراد طبقةِ القاعدة، وقائمتُه البيضاءُ مقفولةٌ نصّاً. والشاشةُ الأصلُ
// (`landed_cost_screen.dart`) وحالتُها مُدرَجتان فيها من خطِّ الأساس، أمّا
// هذا الفوركُ فملفٌّ جديدٌ — فيلزمه ألّا يسمّيَ نوعاً من drift إطلاقاً.
//
// والتسطيحُ يقع في **الحالة** لا هنا: `LandedCostSheetView` و
// `LandedCostItemView` معرَّفتان في `landed_cost_controller.dart` (‏المُدرَجِ
// في القائمة البيضاء سلفاً)، وتخرجان عبر `sheetViews`/`selectedView`/
// `itemViews`. فتصل الشاشةَ أنواعٌ مؤكَّدةُ الحقول بلا `dynamic` ولا
// `avoid_dynamic_calls` — وهذا أنظفُ من توسيع القائمة البيضاء، ويُبقي
// الحارسَ صادقاً بدل أن يُستثنى منه.
//
// ═══ وفرقُ التقريب — صار البرنامجُ يفعل ما يقوله التصميم ═══
//
// التصميمُ يكتب في رأس جدول التوزيع «فرقُ التقريب يُحمَّل على أكبر بند»،
// و`calculateAllocations` كانت **لا تقرّب أصلاً**: كسورٌ عائمةٌ تُكتَب كما
// هي، فيبقى بين مجموعِ الأسطر وإجماليِّ الورقة فرقٌ يقيّده `applyLandedCost`
// على المخزون بلا أن يقابله تحريكُ تكلفةٍ في أيّ صنف.
//
// فبدل تخفيفِ نصِّ التصميم، نُقل السلوكُ إلى الـDAO: تقريبٌ إلى قرشَين ثمّ
// إلقاءُ الباقي على أكبر بند — فيتساوى المجموعُ بالإجماليّ بالضبط. والخانةُ
// هنا تعرض ذلك الفرقَ **مقيساً من الصفوف المكتوبة** لا منقولاً من التصميم،
// فتقرأ صفراً حين يستوي الحسابُ وقيمةً حين لا يستوي.
//
// ═══ ⚠️ وطرفُ بند التكلفة ═══
//
// التصميمُ يعرض اسمَ الطرف تحت كلِّ بندٍ («خطوط النقل الدولية»). والجدولُ
// يحمل `supplierPartyId` وحدَه بلا وصلةٍ لاسمِ الطرف في أيّ استعلامٍ قائم،
// فالمعروضُ نوعُ التكلفة وحدَه. ووصلُ الاسم دفعةُ DAO لا سطرُ عرض.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/invoice_entity.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../screens/landed_cost/landed_cost_controller.dart';
import '../../widgets/permission_guard.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _money0 = NumberFormat('#,##0', 'en');

String _pct(double v) => tr('{p0}٪', {'p0': v.toStringAsFixed(1)});

// ── ألوانُ التصميم ───────────────────────────────────────────────────────
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _err = Color(0xFFEF4444);
const _purple = Color(0xFF8B5CF6);
const _idle = Color(0xFF6B7280);

/// أنواعُ بنود التكلفة الستّة — نفسُ الرموز التي يكتبها `LandedCostItems`.
Map<String, ({String label, IconData icon, Color tint})> get _kTypes => {
  'shipping': (label: tr('شحن'), icon: PhosphorIconsBold.boat, tint: AppColors.primary),
  'customs': (label: tr('جمارك'), icon: PhosphorIconsBold.stamp, tint: _err),
  'insurance': (label: tr('تأمين'), icon: PhosphorIconsBold.shieldCheck, tint: _purple),
  'freight': (label: tr('نقل'), icon: PhosphorIconsBold.truck, tint: _warn),
  'handling': (label: tr('مناولة'), icon: PhosphorIconsBold.handGrabbing, tint: _ok),
  'other': (label: tr('أخرى'), icon: PhosphorIconsBold.dotsThreeCircle, tint: _idle),
};

/// حالاتُ الورقة الأربع — نفسُ الرموز التي يكتبها عمودُ `status`.
Map<String, ({String label, Color tint})> get _kStatuses => {
  'draft': (label: tr('مسوّدة'), tint: _warn),
  'applied': (label: tr('مُطبَّقة'), tint: _ok),
  'cancelled': (label: tr('ملغاة'), tint: _idle),
  'voided': (label: tr('مُبطَلة'), tint: _err),
};

/// طرقُ التوزيع. `by_weight` **مقفولةٌ صراحةً** — والقفلُ ليس زينةً: عمودُ
/// `allocationMethod` يوثّق أنّها مؤجَّلةٌ لأنّها تحتاج وزناً مسجَّلاً لكلّ
/// منتج، و`calculateAllocations` لا تعرفها فتسقط على `by_value` صامتةً.
/// فإظهارُها قابلةً للنقر يعطي زرّاً يكذب.
List<
    ({
      String id,
      String label,
      IconData icon,
      String sub,
      String formula,
      bool locked
    })> get _kMethods => [
  (
    id: 'by_value',
    label: tr('بالقيمة'),
    icon: PhosphorIconsBold.currencyCircleDollar,
    sub: tr('الصنف الأغلى يحمل أكثر — الافتراضي ويناسب الشحن والتأمين'),
    formula: tr('التكلفة × (قيمة البند ÷ إجمالي القيمة)'),
    locked: false,
  ),
  (
    id: 'by_quantity',
    label: tr('بالكمية'),
    icon: PhosphorIconsBold.stack,
    sub: tr('كل وحدة تحمل بالتساوي — يناسب المناولة والنقل'),
    formula: tr('التكلفة × (كمية البند ÷ إجمالي الكمية)'),
    locked: false,
  ),
  (
    id: 'equal',
    label: tr('بالتساوي'),
    icon: PhosphorIconsBold.equals,
    sub: tr('كل بند يحمل نفس المبلغ — يناسب رسوم الفحص لكل صنف'),
    formula: tr('التكلفة ÷ عدد البنود'),
    locked: false,
  ),
  (
    id: 'by_weight',
    label: tr('بالوزن'),
    icon: PhosphorIconsBold.scales,
    sub: tr('غير متاح — يحتاج وزناً مسجَّلاً لكل منتج'),
    formula: tr('مؤجَّل في هذا الإصدار'),
    locked: true,
  ),
];

/// فاتورةُ الشراء التي تُحمَّل عليها الورقة — لقطةٌ لا بثّ.
///
/// ⚠️ `getInvoiceById` تُرجع `Future` لا `Stream`. وهذا مقصود: مجرى drift لا
/// يبثّ في المنطقة الوهميّة، فـ`.first` عليه يعلّق `pumpAndSettle` في اختبار
/// الودجت. والشاشةُ تريد لقطةً لا بثّاً.
final _sheetInvoiceProvider =
    FutureProvider.autoDispose.family<InvoiceEntity?, int>((ref, invoiceId) {
  return ref.read(purchasesRepositoryProvider).getInvoiceById(invoiceId);
});

/// حسابُ الورقة — مقيسٌ من الصفوف المكتوبة فعلاً، لا منقولٌ من التصميم.
class _Computed {
  const _Computed({
    required this.origSum,
    required this.allocSum,
    required this.qtySum,
    required this.maxAlloc,
    required this.minDelta,
    required this.maxDelta,
    required this.lines,
  });

  final double origSum;
  final double allocSum;
  final double qtySum;
  final double maxAlloc;
  final double minDelta;
  final double maxDelta;
  final List<_AllocLine> lines;

  bool get hasLines => lines.isNotEmpty;
}

class _AllocLine {
  const _AllocLine({
    required this.name,
    required this.code,
    required this.qty,
    required this.unitCost,
    required this.origTotal,
    required this.alloc,
    required this.newUnit,
    required this.deltaPct,
  });

  final String name;
  final String code;
  final double qty;
  final double unitCost;
  final double origTotal;
  final double alloc;
  final double newUnit;
  final double deltaPct;
}

_Computed _compute(List<Map<String, dynamic>> rows) {
  final lines = <_AllocLine>[];
  var origSum = 0.0, allocSum = 0.0, qtySum = 0.0, maxAlloc = 0.0;
  var minDelta = double.infinity, maxDelta = -double.infinity;

  for (final r in rows) {
    final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
    final unitCost = (r['original_cost'] as num?)?.toDouble() ?? 0;
    final alloc = (r['allocated_amount'] as num?)?.toDouble() ?? 0;
    final newUnit = (r['new_unit_cost'] as num?)?.toDouble() ?? 0;
    final origTotal = qty * unitCost;
    // قسمةٌ على صفرٍ تعطي `NaN`/`Infinity` فتُطبَع على الشاشة نصّاً قبيحاً —
    // والصفرُ هنا وارد: بندُ شراءٍ بكمّيّةٍ صفرٍ أو تكلفةٍ صفر.
    final deltaPct = origTotal > 0 ? alloc / origTotal * 100 : 0.0;

    origSum += origTotal;
    allocSum += alloc;
    qtySum += qty;
    if (alloc > maxAlloc) maxAlloc = alloc;
    if (deltaPct < minDelta) minDelta = deltaPct;
    if (deltaPct > maxDelta) maxDelta = deltaPct;

    lines.add(_AllocLine(
      name: (r['product_name'] as String?) ?? '—',
      code: (r['product_code'] as String?) ?? '',
      qty: qty,
      unitCost: unitCost,
      origTotal: origTotal,
      alloc: alloc,
      newUnit: newUnit,
      deltaPct: deltaPct,
    ));
  }

  return _Computed(
    origSum: origSum,
    allocSum: allocSum,
    qtySum: qtySum,
    maxAlloc: maxAlloc,
    minDelta: lines.isEmpty ? 0 : minDelta,
    maxDelta: lines.isEmpty ? 0 : maxDelta,
    lines: lines,
  );
}

class LandedCostPicposScreen extends ConsumerStatefulWidget {
  const LandedCostPicposScreen({super.key});

  @override
  ConsumerState<LandedCostPicposScreen> createState() =>
      _LandedCostPicposScreenState();
}

class _LandedCostPicposScreenState
    extends ConsumerState<LandedCostPicposScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(landedCostControllerProvider);
    final selected = state.selectedView;

    return PicPosScreenScaffold(
      title: tr('التكاليف المحملة'),
      subtitle:
          tr('ورقة تحميل تكاليف على فاتورة شراء — تُوزَّع على الأصناف فتغيّر تكلفة الوحدة'),
      icon: PhosphorIconsBold.stackPlus,
      headerSearch: selected != null ? null : _searchField(),
      headerActions: [
        if (selected != null)
          OutlinedButton.icon(
            onPressed: () => ref
                .read(landedCostControllerProvider.notifier)
                .clearSelection(),
            icon: const Icon(PhosphorIconsBold.files, size: 16),
            label:  Text(tr('كل الأوراق')),
          ),
      ],
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : selected == null
              ? _buildSheetList(state.sheetViews)
              : _buildDetail(selected, state),
    );
  }

  Widget _searchField() => TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim()),
        decoration:  InputDecoration(
          hintText: tr('ابحث برقم الورقة...'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 17),
          isDense: true,
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════
  // قائمةُ الأوراق
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSheetList(List<LandedCostSheetView> rawSheets) {
    final sheets = rawSheets.where((s) {
      if (_query.isEmpty) return true;
      return s.number.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    if (sheets.isEmpty) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.stackPlus,
        title: _query.isEmpty
            ? tr('لا أوراقَ تحميلٍ بعد')
            : tr('لا ورقةَ تطابق «{_query}»', {'_query': _query}),
        hint: _query.isEmpty
            ? tr('ورقةُ التحميل تُنشأ على فاتورة شراءٍ قائمة، ثمّ تُضاف بنودُ التكلفة فتُوزَّع على أصناف الفاتورة.')
            : null,
      );
    }

    return ListView.separated(
      itemCount: sheets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _sheetCard(sheets[i]),
    );
  }

  Widget _sheetCard(LandedCostSheetView s) {
    final st = _kStatuses[s.status] ?? _kStatuses['draft']!;
    final method = _kMethods.where((m) => m.id == s.method).firstOrNull;

    return PicPosContentCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ref
            .read(landedCostControllerProvider.notifier)
            .selectSheetById(s.id),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: st.tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(PhosphorIconsBold.receipt,
                    size: 21, color: st.tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.number,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _pill(st.label, st.tint),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr('طريقة التوزيع: {p0}', {'p0': method?.label ?? s.method}),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.picposMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _money0.format(s.totalCost),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: context.picposBrandInk),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // تفصيلُ الورقة
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildDetail(LandedCostSheetView s, LandedCostState state) {
    final items = state.itemViews;
    final c = _compute(state.allocations);

    return LayoutBuilder(builder: (context, box) {
      // ⚠️ قِيس على عرضين: العمودان جنباً إلى جنبٍ يفيضان تحت ١١٠٠، فيصيران
      //    مكدَّسَين. والحدُّ من القياس لا من الذوق — ٤١٠ للعمود الأيمن
      //    زائدَ ٦٤٠ حدًّا أدنى للأيسر زائدَ الفراغ.
      final stacked = box.maxWidth < 1100;

      final left = _costItemsPanel(s, items, c);
      final right = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _methodsPanel(s),
          const SizedBox(height: 12),
          _impactPanel(s, c),
        ],
      );

      return ListView(
        children: [
          _summaryStrip(s, c),
          const SizedBox(height: 12),
          if (stacked) ...[
            left,
            const SizedBox(height: 12),
            right,
          ] else
            // ⚠️ **لا `IntrinsicHeight` حول هذين الصفَّين.** `_methodsPanel`
            //    يحوي `LayoutBuilder` (‏ليختار عمودَين أو أربعة بحسب العرض)،
            //    و`LayoutBuilder` لا يقبل قياسَ ارتفاعٍ جوهريّ فيرمي
            //    «does not support returning intrinsic dimensions» — أمسكه
            //    اختبارُ التركيب عند ١٢٨٠ و١٩٢٠ معاً. والعمودان لا يحتاجان
            //    تساويَ ارتفاعٍ أصلاً، فالحذفُ إصلاحٌ لا تنازل.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 410, child: left),
                const SizedBox(width: 12),
                Expanded(child: right),
              ],
            ),
          const SizedBox(height: 12),
          _allocationTable(s, c),
          const SizedBox(height: 12),
          if (stacked) ...[
            _journalPanel(s, c),
            const SizedBox(height: 12),
            _flowPanel(s),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 135, child: _journalPanel(s, c)),
                const SizedBox(width: 12),
                Expanded(flex: 100, child: _flowPanel(s)),
              ],
            ),
        ],
      );
    });
  }

  /// شريطُ الملخّص: رقمُ الورقة وحالتُها وفاتورتُها وأربعةُ أرقامٍ وزرُّ التطبيق.
  Widget _summaryStrip(LandedCostSheetView s, _Computed c) {
    final st = _kStatuses[s.status] ?? _kStatuses['draft']!;
    final invoice = ref.watch(_sheetInvoiceProvider(s.purchaseInvoiceId));
    final applied = s.status == 'applied';
    final busy = ref.watch(landedCostControllerProvider).isApplying;
    final loadPct = c.origSum > 0 ? s.totalCost / c.origSum * 100 : 0.0;

    final stats = <({String label, String value, Color fg})>[
      (
        label: tr('قيمة الفاتورة الأصلية'),
        value: _money0.format(c.origSum),
        fg: context.picposText
      ),
      (
        label: tr('التكلفة الإضافية'),
        value: _money0.format(s.totalCost),
        fg: _warn
      ),
      (
        label: tr('قيمة المخزون الجديدة'),
        value: _money0.format(c.origSum + s.totalCost),
        fg: context.picposBrandInk
      ),
      (label: tr('نسبة التحميل'), value: _pct(loadPct), fg: _err),
    ];

    return PicPosContentCard(
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: context.picposBrandInk.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(PhosphorIconsBold.receipt,
                      size: 24, color: context.picposBrandInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(s.number,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          _pill(st.label, st.tint),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        invoice.when(
                          data: (inv) => inv == null
                              ? tr('فاتورة الشراء #{p0}', {'p0': s.purchaseInvoiceId})
                              : tr('فاتورة الشراء {p0}{p1} · {p2}', {'p0': inv.invoiceNumber, 'p1': inv.partyName == null ? '' : ' · ${inv.partyName}', 'p2': DateFormat('yyyy-MM-dd').format(inv.invoiceDate)}),
                          // العارضُ يبتلع رمْيَ SQL في بطاقة، فالإخفاقُ يُقال
                          // صراحةً بدل أن يبدو التقريرُ عاملاً وهو ليس كذلك.
                          error: (_, _) => tr('تعذّر قراءةُ فاتورة الشراء'),
                          loading: () => '…',
                        ),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.picposMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final st2 in stats)
            SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(st2.label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.picposMuted),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(st2.value,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: st2.fg),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          // ⚠️ زرُّ التطبيق حاضرٌ **موصولاً** لأنّ `applyLandedCost` مبنيّةٌ
          //    فعلاً في الـDAO. و`isApplying` يقفله فلا يُقيَّد مرّتين.
          //
          // 🔴 **وحارسُ الصلاحيّة ليس زينةً هنا.** `applyLandedCost` تفعل
          //    أربعةً ماليّةً دفعةً واحدة: تمزج `products.costPrice` بالمتوسّط
          //    المرجَّح، وتمزج `inventory_balances.average_cost`، وترحّل قيدَ
          //    يوميّةٍ متوازناً (‏مدين المخزون / دائن ذمم المورد أو النقديّة)،
          //    وتختم الورقةَ `applied`. وأوّلُ صيغةٍ لهذا الفورك جاءت بلا أيِّ
          //    ذكرٍ لـ`PermissionCodes` إطلاقاً — فصار الترحيلُ مباحاً لكلِّ
          //    مَن يفتح الشاشة.
          //
          //    وحصرُ التنقّل وحدَه لا يكفي: `ScreenId.landedCost` محكومٌ
          //    بـ`purchases_create` وهو إذنُ قراءةِ الورقة، والتطبيقُ فعلُ
          //    كتابةٍ أعلى. نفسُ تفريقِ `assets_view` عن `assets_depreciation`
          //    في `fixed_assets_picpos_screen.dart` حرفاً بحرف.
          //
          //    ⚠️ وبلا `allowManagerOverride`: الإخفاءُ التامُّ مقصود. تجاوزُ
          //    المسؤول يُظهر الزرَّ ويطلب كلمةَ مرور، وقيدُ اليوميّة لا رجوعَ
          //    عنه إلّا بإلغاء التطبيق — فهو منعٌ لا اشتراط، تماماً كزرِّ
          //    ترحيل الإهلاك المجاور.
          PermissionGuard(
            permission: PermissionCodes.landedCostApply,
            child: FilledButton.icon(
              onPressed: applied || busy || !c.hasLines
                  ? null
                  : () => _confirmApply(s),
              icon: const Icon(PhosphorIconsBold.checkCircle, size: 16),
              label: Text(applied ? tr('مُطبَّقة') : tr('تطبيق الورقة')),
              style: FilledButton.styleFrom(
                  backgroundColor: applied ? _idle : _ok),
            ),
          ),
        ],
      ),
    );
  }

  /// عمودُ بنود التكلفة.
  Widget _costItemsPanel(LandedCostSheetView s, List<LandedCostItemView> items, _Computed c) {
    final editable = s.status == 'draft';
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PicPosSectionHeader(
            title: tr('بنود التكلفة'),
            subtitle: tr('كل بند بنوعه — المجموع هو ما يُوزَّع'),
            icon: PhosphorIconsBold.listPlus,
            actions: [
              // زرٌّ يظهر ولا يفعل أسوأُ من زرٍّ غائب: الإضافةُ تُعرَض على
              // المسوّدة وحدَها لأنّ الورقةَ المطبَّقة لها قيدٌ منشور.
              if (editable)
                IconButton(
                  onPressed: () => _openAddItem(s),
                  icon: const Icon(PhosphorIconsBold.plus, size: 15),
                  tooltip: tr('بند تكلفة جديد'),
                ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Text(tr('لا بنودَ تكلفةٍ بعد'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.picposMuted)),
            )
          else
            for (final it in items) _costItemRow(it, s.totalCost),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: context.picposField,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsBold.equals,
                    size: 15, color: context.picposBrandInk),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(tr('إجمالي التكلفة الإضافية'),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: context.picposMuted),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(_money0.format(s.totalCost),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: context.picposBrandInk)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _costItemRow(LandedCostItemView it, double total) {
    final t = _kTypes[it.type] ?? _kTypes['other']!;
    final share = total > 0 ? it.amount / total * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(t.icon, size: 16, color: t.tint),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(it.description,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                Text(t.label,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: context.picposMuted),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_money0.format(it.amount),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
              Text(_pct(share),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: context.picposMuted)),
            ],
          ),
        ],
      ),
    );
  }

  /// بطاقاتُ طرق التوزيع الأربع.
  Widget _methodsPanel(LandedCostSheetView s) {
    final editable = s.status == 'draft';
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
           PicPosSectionHeader(
            title: tr('طريقة التوزيع'),
            subtitle: tr('تغيير الطريقة يعيد حساب تكلفة كل وحدة'),
            icon: PhosphorIconsBold.arrowsSplit,
          ),
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth < 620 ? 2 : 4;
            final w = (box.maxWidth - (cols - 1) * 11) / cols;
            return Wrap(
              spacing: 11,
              runSpacing: 11,
              children: [
                for (final m in _kMethods)
                  SizedBox(width: w, child: _methodCard(m, s, editable)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _methodCard(
    ({
      String id,
      String label,
      IconData icon,
      String sub,
      String formula,
      bool locked
    }) m,
    LandedCostSheetView s,
    bool editable,
  ) {
    final on = m.id == s.method;
    final enabled = editable && !m.locked;
    final fg = m.locked
        ? context.picposMuted
        : on
            ? context.picposBrandInk
            : context.picposText;

    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: enabled ? () => _changeMethod(s, m.id) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: m.locked
              ? context.picposField
              : on
                  ? context.picposBrandInk.withValues(alpha: 0.08)
                  : Colors.transparent,
          border: Border.all(
            color: on && !m.locked
                ? context.picposBrandInk
                : context.picposHairline,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(m.icon, size: 17, color: fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(m.label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: fg),
                      overflow: TextOverflow.ellipsis),
                ),
                if (m.locked)
                  Icon(PhosphorIconsBold.prohibit,
                      size: 13, color: context.picposMuted),
              ],
            ),
            const SizedBox(height: 6),
            Text(m.sub,
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted)),
            const SizedBox(height: 7),
            Text(m.formula,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: AppTypography.mono,
                    color: fg)),
          ],
        ),
      ),
    );
  }

  /// أثرُ الطريقة — أرقامٌ مقيسةٌ من الصفوف المكتوبة.
  Widget _impactPanel(LandedCostSheetView s, _Computed c) {
    final drift = s.totalCost - c.allocSum;
    final spread = c.maxDelta - c.minDelta;

    final stats = <({String label, String value, Color fg})>[
      (label: tr('أدنى نسبة تحميل'), value: _pct(c.minDelta), fg: _ok),
      (
        label: tr('أعلى نسبة تحميل'),
        value: _pct(c.maxDelta),
        fg: spread < 0.05 ? _ok : _err
      ),
      (
        label: tr('تباعد النسب'),
        value: spread < 0.05 ? tr('متساوية') : _pct(spread),
        fg: spread < 0.05 ? _ok : _warn
      ),
      // مقيسٌ من الصفوف: إجماليُّ الورقة ناقصَ مجموعِ ما وُزِّع. وبعد أن صار
      // الـDAO يقرّب ويُلقي الباقيَ على أكبر بندٍ يقرأ صفراً — وبقاؤه محسوباً
      // لا مكتوباً هو ما يجعله يكشف الخللَ إن عاد.
      (
        label: tr('فرق التقريب'),
        value: _money.format(drift.abs()),
        fg: drift.abs() < 0.005 ? _ok : _warn
      ),
    ];

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PicPosSectionHeader(
            title: tr('أثر الطريقة على تكلفة الوحدة'),
            subtitle: c.hasLines
                ? tr('مقيسٌ من صفوف التوزيع المكتوبة لهذه الورقة')
                : tr('لا صفوفَ توزيعٍ محسوبةً بعد'),
            icon: PhosphorIconsBold.scales,
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final st in stats)
                Container(
                  width: 128,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    color: context.picposField,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(st.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: context.picposMuted),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(st.value,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: st.fg)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// جدولُ التوزيع على الأصناف.
  Widget _allocationTable(LandedCostSheetView s, _Computed c) {
    return PicPosDataTable(
      title: tr('جدول التوزيع على الأصناف'),
      subtitle: tr('التكلفة الأصلية زائد المحمَّل يساوي التكلفة الجديدة — وهي ما يُقيَّد في المخزون · فرق التقريب يُحمَّل على أكبر بند'),
      minWidth: 980,
      columns:  [
        PicPosTableColumn(tr('الصنف'), flex: 2),
        PicPosTableColumn(tr('الكمية'), align: PicPosCellAlign.end),
        PicPosTableColumn(tr('تكلفة الوحدة'),
            flex: 1.2, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('قيمة البند'), flex: 1.3, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('المحمَّل'), flex: 1.5),
        PicPosTableColumn(tr('التكلفة الجديدة'),
            flex: 1.3, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('الزيادة'), flex: 1.1, align: PicPosCellAlign.end),
      ],
      emptyLabel: tr('لا صفوفَ توزيعٍ — أضف بندَ تكلفةٍ ثمّ احسب التوزيع'),
      rows: [
        for (final l in c.lines)
          PicPosTableRow(cells: [
            PicPosTextCell(l.name,
                sub: l.code.isEmpty ? null : l.code,
                icon: PhosphorIconsBold.cube),
            PicPosTextCell(_money0.format(l.qty)),
            PicPosTextCell(_money.format(l.unitCost)),
            PicPosTextCell(_money0.format(l.origTotal)),
            PicPosBarCell(
              _money.format(l.alloc),
              c.maxAlloc > 0 ? l.alloc / c.maxAlloc : 0,
              _warn,
            ),
            PicPosTextCell(_money.format(l.newUnit), bold: true),
            PicPosTextCell('+${_pct(l.deltaPct)}', tint: _err),
          ]),
      ],
      totals: c.hasLines
          ? [
              tr('{p0} صنفاً', {'p0': c.lines.length}),
              _money0.format(c.qtySum),
              '—',
              _money0.format(c.origSum),
              _money0.format(c.allocSum),
              _money0.format(c.origSum + c.allocSum),
              '+${_pct(c.origSum > 0 ? c.allocSum / c.origSum * 100 : 0)}',
            ]
          : null,
    );
  }

  /// بطاقةُ القيد الذي يُنشأ عند التطبيق.
  ///
  /// ⚠️ الأرقامُ هنا **وصفُ ما ستفعله** `applyLandedCost` لا قراءةٌ لقيدٍ
  /// منشور: القيدُ الفعليُّ لا يوجد قبل التطبيق. ولذلك العنوانُ «الذي يُنشأ».
  Widget _journalPanel(LandedCostSheetView s, _Computed c) {
    final rows = <({
      String account,
      String note,
      String side,
      IconData icon,
      Color tint,
      String amount
    })>[
      (
        account: tr('1301 · المخزون'),
        note: tr('يرتفع بقيمة التكلفة المحمَّلة كاملة'),
        side: tr('مدين'),
        icon: PhosphorIconsBold.package,
        tint: _ok,
        amount: _money0.format(s.totalCost),
      ),
      (
        account: tr('2101 · موردو خدمات'),
        note: tr('مقابلُ بنود التكلفة'),
        side: tr('دائن'),
        icon: PhosphorIconsBold.usersThree,
        tint: _err,
        amount: _money0.format(s.totalCost),
      ),
      (
        account: tr('متوسط التكلفة المرجَّح'),
        note: tr('يُعاد حسابه لكلّ صنفٍ في الورقة'),
        side: tr('تحديث'),
        icon: PhosphorIconsBold.arrowsClockwise,
        tint: AppColors.primary,
        amount: tr('{p0} صنفاً', {'p0': c.lines.length}),
      ),
    ];

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
           PicPosSectionHeader(
            title: tr('القيد الذي يُنشأ عند التطبيق'),
            subtitle: tr('التطبيق يرفع قيمة المخزون ويُقيَّد في مواجهة أطراف التكلفة'),
            icon: PhosphorIconsBold.scales,
          ),
          for (final j in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: j.tint.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(j.icon, size: 14, color: j.tint),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(j.account,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                        Text(j.note,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: context.picposMuted),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _pill(j.side, j.tint),
                  const SizedBox(width: 10),
                  Text(j.amount,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// مراحلُ الورقة الأربع — الحاليّةُ مضاءةٌ والباقي خافت.
  Widget _flowPanel(LandedCostSheetView s) {
    final steps = <({String key, String label, String sub, IconData icon})>[
      (
        key: 'draft',
        label: tr('مسوّدة'),
        sub: tr('قابلةٌ للتعديل ولا قيدَ لها ولا أثرَ على تكلفة المخزون'),
        icon: PhosphorIconsBold.fileDashed
      ),
      (
        key: 'applied',
        label: tr('مُطبَّقة'),
        sub: tr('القيدُ يُنشأ وتكلفةُ الوحدة تتغيّر'),
        icon: PhosphorIconsBold.checkCircle
      ),
      (
        key: 'cancelled',
        label: tr('ملغاة'),
        sub: tr('إلغاءٌ قبل التطبيق — تبقى للسجلّ بلا أثر'),
        icon: PhosphorIconsBold.xCircle
      ),
      (
        key: 'voided',
        label: tr('مُبطَلة'),
        sub: tr('تُبطَل تلقائيّاً لو أُبطلت فاتورةُ الشراء الأصليّة'),
        icon: PhosphorIconsBold.prohibit
      ),
    ];

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
           PicPosSectionHeader(
            title: tr('حالة الورقة'),
            icon: PhosphorIconsBold.flowArrow,
          ),
          for (final st in steps) ...[
            _flowRow(st, on: st.key == s.status),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }

  Widget _flowRow(
    ({String key, String label, String sub, IconData icon}) st, {
    required bool on,
  }) {
    final tint = _kStatuses[st.key]?.tint ?? _idle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: on ? tint.withValues(alpha: 0.10) : Colors.transparent,
        border: Border.all(
          color: on ? tint.withValues(alpha: 0.35) : context.picposHairline,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(st.icon, size: 16, color: on ? tint : context.picposMuted),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(st.label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: on ? context.picposText : context.picposMuted),
                    overflow: TextOverflow.ellipsis),
                Text(st.sub,
                    style: TextStyle(
                        fontSize: 10.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: context.picposMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: tint)),
      );

  // ═══════════════════════════════════════════════════════════════════════
  // الأفعال
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _changeMethod(LandedCostSheetView s, String method) async {
    final notifier = ref.read(landedCostControllerProvider.notifier);
    try {
      await notifier.changeAllocationMethod(s.id, method);
      if (!mounted) return;
      AppToast.show(context, tr('أُعيد حسابُ التوزيع بالطريقة الجديدة'));
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, tr('تعذّر تغييرُ طريقة التوزيع: {e}', {'e': e}));
    }
  }

  Future<void> _confirmApply(LandedCostSheetView s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(PhosphorIconsBold.warning, color: _warn),
        title:  Text(tr('تطبيق ورقة التحميل')),
        content: Text(
          tr('سيُنشأ قيدٌ بقيمة {p0} وتتغيّر تكلفةُ الوحدة لكلّ صنفٍ في الورقة. ولا رجوعَ عن ذلك إلّا بإلغاء التطبيق.', {'p0': _money0.format(s.totalCost)}),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('تطبيق'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final notifier = ref.read(landedCostControllerProvider.notifier);
    try {
      await notifier.applySheet(s.id);
      if (!mounted) return;
      AppToast.show(context, tr('طُبِّقت الورقة وأُنشئ قيدُها'));
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, tr('تعذّر تطبيقُ الورقة: {e}', {'e': e}));
    }
  }

  Future<void> _openAddItem(LandedCostSheetView s) async {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    var type = 'shipping';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title:  Text(tr('بند تكلفة جديد')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in _kTypes.entries)
                      ChoiceChip(
                        selected: type == e.key,
                        onSelected: (_) => setDialog(() => type = e.key),
                        avatar: Icon(e.value.icon, size: 15),
                        label: Text(e.value.label),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descCtrl,
                  decoration:  InputDecoration(
                      labelText: tr('الوصف'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:  InputDecoration(
                      labelText: tr('المبلغ'), border: const OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('إلغاء'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:  Text(tr('إضافة'))),
          ],
        ),
      ),
    );

    final desc = descCtrl.text.trim();
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    descCtrl.dispose();
    amountCtrl.dispose();

    if (saved != true || !mounted) return;
    if (desc.isEmpty || amount <= 0) {
      AppToast.show(context, tr('الوصفُ مطلوبٌ والمبلغُ يجب أن يكون أكبرَ من صفر'));
      return;
    }

    final notifier = ref.read(landedCostControllerProvider.notifier);
    try {
      await notifier.addCostItem(
        sheetId: s.id,
        costType: type,
        description: desc,
        amount: amount,
      );
      if (!mounted) return;
      AppToast.show(context, tr('أُضيف البندُ وأُعيد حسابُ التوزيع'));
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, tr('تعذّرت إضافةُ البند: {e}', {'e': e}));
    }
  }
}
