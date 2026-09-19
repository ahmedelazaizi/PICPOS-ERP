// بطاقةُ أصلٍ ثابت — تصميمُ المالك `(9)` و`(8)`.
//
// ═══ لماذا بطاقةٌ داخلَ الشاشة لا شاشةٌ سادسة ═══
//
// فاتحُها زرُّ 👁 في صفِّ الجدول، ومسارُها في التصميم
// «المالية والمحاسبة / الأصول الثابتة / بطاقة أصل ثابت» — أي **تفصيلُ صفٍّ**
// لا مدخلٌ جانبيّ. وشاشةٌ مستقلّةٌ كانت ستعني ستّةَ مواضعِ توصيلٍ وصلاحيّةً
// سابعةً لشيءٍ لا يُفتَح إلّا من هنا.
//
// ═══ ⚠️ وما يُحرَّر وما يُعرَض ═══
//
// التصميمُ يرسم «الفئة» و«تاريخ الاقتناء» و«التكلفة» حقولاً تبدو قابلةً
// للتحرير. وهي **ليست** كذلك بعد الاقتناء:
//
// ‏• **التكلفة** دخلت الأستاذَ بقيدِ اقتناءٍ مرحَّل. وتغييرُها في البطاقة
//   وحدَها يفكّ ارتباطَ الأصل بالدفتر بلا قيدِ تسوية — وبابُ تغييرها
//   المحاسبيُّ هو **إعادةُ التقييم** (`revalueAsset`) وهي تقيّد الفرقَ.
// ‏• **تاريخُ الاقتناء** أساسُ جدول الإهلاك، وأشهرٌ مُرحَّلةٌ قائمةٌ عليه.
// ‏• **الفئة** تحدّد حسابَي الأصل والإهلاك، وقيودٌ مرحَّلةٌ ذهبت إليهما.
//
// و`updateFixedAsset` لا تقبل أيّاً منها أصلاً — فحقلٌ يَعِد بالتعديل ولا
// يفعله أسوأُ من حقلٍ يقول لماذا لا يُحرَّر. **والسببُ مكتوبٌ تحت كلٍّ**.
//
// ═══ ⚠️ والعمرُ يُعرَض بالشهور ═══
//
// كما يرسم التصميمُ («٣٦ شهراً»)، والعمودُ `usefulLifeYears` **بالسنوات**.
// والتحويلُ `usefulLifeMonths` في `domain/models/depreciation_math.dart` —
// موضعٌ واحدٌ مسمّىً، ولا يُكتَب `* 12` في ملفِّ شاشةٍ أبداً.
//
// ═══ ⚠️ والمرفقاتُ تُسقَط ═══
//
// «تفاصيل إضافية (ملاحظات ومرفقات)» يُبنى منها **الملاحظاتُ وحدَها**:
// `notes` عمودٌ قائم، ولا بنيةَ مرفقاتٍ في المستودع إطلاقاً (قاعدةُ الخطّة
// ح‑٤ — بندٌ مستقلٌّ بقرار المالك).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/asset_movement_types.dart';
import '../../../domain/models/depreciation_math.dart';
import '../../../domain/repositories/fixed_assets_repository.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../picpos_shell/picpos_totals_bar.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _dateFmt = DateFormat('dd-MM-yyyy');

const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _idle = Color(0xFF6B7280);

/// أسماءُ الشهور ثابتةٌ — `DateFormat('MMMM','ar')` تحتاج
/// `initializeDateFormatting` وترمي بدونها، فتنهار الشاشةُ في أوّل اختبار.
const _monthsAr = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// ما تحتاجه البطاقةُ من الأصل — **قيمٌ خالصةٌ لا صفُّ drift**.
///
/// ⚠️ حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ **جديدٍ** من
/// استيراد `data/database`، وقائمتُه البيضاءُ مقفولة.
typedef AssetCardValue = ({
  int id,
  String code,
  String name,
  int categoryId,
  String categoryName,
  String? location,
  double purchasePrice,
  DateTime purchaseDate,
  double usefulLifeYears,
  double salvageValue,
  String depreciationMethod,
  double accumulatedDepreciation,
  String status,
  String? notes,
  int? custodianUserId,
});

/// صفُّ إهلاكٍ مُرحَّلٌ كما يصل من المستودع.
typedef AssetCardPosted = PostedDepreciation;

/// حركةٌ على الأصل — قيدٌ بلا أنواع drift.
typedef AssetCardMovement = ({
  DateTime date,
  String entryNumber,
  String? description,
  String? referenceType,
  bool isPosted,
});

/// خيارُ «المسؤول».
typedef AssetCustodianOption = ({int id, String name});

/// ما يُحفَظ — الحقولُ الثلاثةُ القابلةُ للتحرير وحدَها.
typedef AssetCardSave = Future<void> Function({
  required String name,
  required String? location,
  required String? notes,
  required int? custodianUserId,
  required bool clearCustodian,
});

class AssetCardPicpos extends ConsumerStatefulWidget {
  const AssetCardPicpos({
    super.key,
    required this.asset,
    required this.custodians,
    required this.posted,
    required this.movements,
    required this.onSave,
    required this.onBack,
    this.canEdit = true,
  });

  final AssetCardValue asset;
  final List<AssetCustodianOption> custodians;
  final List<AssetCardPosted> posted;
  final List<AssetCardMovement> movements;
  final AssetCardSave onSave;
  final VoidCallback onBack;
  final bool canEdit;

  @override
  ConsumerState<AssetCardPicpos> createState() => _AssetCardPicposState();
}

class _AssetCardPicposState extends ConsumerState<AssetCardPicpos>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final TextEditingController _notes;
  int? _custodian;
  bool _saving = false;

  /// «فترة المعاينة حتى» — أفقُ التوقّع في تبويبة الإهلاك.
  late DateTime _previewUntil;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
    _name = TextEditingController(text: widget.asset.name);
    _location = TextEditingController(text: widget.asset.location ?? '');
    _notes = TextEditingController(text: widget.asset.notes ?? '');
    _custodian = widget.asset.custodianUserId;

    // الافتراضُ: نهايةُ الشهر الحاليّ — لا نهايةُ العمر. جدولٌ بستٍّ وثلاثين
    // صفّاً عند أوّل فتحٍ يُخفي المرحَّلَ وسط التوقّع.
    final now = DateTime.now();
    _previewUntil = DateTime(now.year, now.month + 1, 0);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _name.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _isActive => widget.asset.status == 'active';

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(
        name: _name.text.trim(),
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        custodianUserId: _custodian,
        // 🔴 رفعُ العهدة فعلٌ كالإسناد: `null` وحدَها تعني «لا تلمس» في
        //    توقيع `updateFixedAsset`، فبلا الراية لا سبيلَ لرفعها عمّن ترك
        //    العمل.
        clearCustodian: _custodian == null,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        PicPosReportTabs(
          controller: _tabs,
          tabs: const [
            (label: 'بيانات الأصل', icon: PhosphorIconsBold.identificationCard, badge: null),
            (label: 'الإهلاك', icon: PhosphorIconsBold.chartLineDown, badge: null),
            (label: 'الحركات', icon: PhosphorIconsBold.arrowsLeftRight, badge: null),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _scroll(_detailsTab(context)),
              _scroll(_depreciationTab(context)),
              _scroll(_movementsTab(context)),
            ],
          ),
        ),
        _actionBar(context),
      ],
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: child,
      );

  // ── الترويسة ───────────────────────────────────────────────────────────

  Widget _header(BuildContext context) {
    final a = widget.asset;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(PhosphorIconsBold.desktop,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(a.code,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: context.picposText,
                    )),
                Text('بطاقة أصل ثابت · ${a.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: context.picposMuted)),
              ],
            ),
          ),
          _pill(
            context,
            _isActive
                ? 'قيد الاستخدام'
                : (a.status == 'sold' ? 'مُباع' : 'مستبعد'),
            _isActive ? _ok : _idle,
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: .35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(text,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: tint)),
          ],
        ),
      );

  // ── لبناتُ حقلٍ ────────────────────────────────────────────────────────

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.picposText)),
      );

  Widget _reason(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(PhosphorIconsBold.info, size: 12, color: context.picposMuted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 11, color: context.picposMuted)),
            ),
          ],
        ),
      );

  Widget _editable(
    BuildContext context,
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
    String? hint,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(context, label),
          TextField(
            controller: ctrl,
            enabled: widget.canEdit && _isActive,
            maxLines: maxLines,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      );

  /// حقلٌ يُعرَض ولا يُحرَّر — **وسببُه تحته**.
  Widget _readOnly(
    BuildContext context,
    String label,
    String value,
    String reason,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(context, label),
          Container(
            height: 44,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: context.picposField,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.picposHairline),
            ),
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.picposMuted)),
          ),
          _reason(context, reason),
        ],
      );

  Widget _pair(Widget a, Widget b) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [a, const SizedBox(height: 14), b],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 14),
            Expanded(child: b),
          ],
        );
      });

  // ── ١) بيانات الأصل ────────────────────────────────────────────────────

  Widget _detailsTab(BuildContext context) {
    final a = widget.asset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _pair(
          _editable(context, 'اسم الأصل', _name),
          _readOnly(
            context,
            'الفئة',
            a.categoryName,
            'الفئةُ تحدّد حسابَي الأصل والإهلاك، وقيودٌ مرحَّلةٌ ذهبت إليهما '
                '— فتغييرُها هنا يترك الأستاذَ على حسابٍ والبطاقةَ على آخر',
          ),
        ),
        const SizedBox(height: 14),
        _pair(
          _readOnly(
            context,
            'تاريخ الاقتناء',
            _dateFmt.format(a.purchaseDate),
            'أساسُ جدول الإهلاك — وأشهرٌ مُرحَّلةٌ قائمةٌ عليه',
          ),
          _readOnly(
            context,
            'التكلفة',
            _money.format(a.purchasePrice),
            'دخلت الأستاذَ بقيد اقتناءٍ مرحَّل — وبابُ تغييرها المحاسبيُّ '
                '«إعادة التقييم» لأنّها تقيّد الفرق',
          ),
        ),
        const SizedBox(height: 14),
        _pair(
          _editable(context, 'الموقع', _location, hint: 'الإدارة · المخزن…'),
          _custodianField(context),
        ),
        const SizedBox(height: 16),
        _summaryCard(
          context,
          'إعدادات الإهلاك',
          [
            'طريقة الإهلاك: ${_methodLabel(a.depreciationMethod)}',
            '${usefulLifeMonths(a.usefulLifeYears)} شهراً',
            'قيمة تخريدية: ${_money.format(a.salvageValue)}',
          ].join('  ·  '),
        ),
        const SizedBox(height: 14),
        _editable(context, 'ملاحظات', _notes, maxLines: 3),
        _reason(
          context,
          'المرفقاتُ في التصميم لا تُبنى — لا بنيةَ مرفقاتٍ في المستودع بعد، '
              'وهي بندٌ مستقلٌّ بقرار المالك',
        ),
      ],
    );
  }

  String _methodLabel(String m) =>
      m == kDecliningBalance ? 'القسط المتناقص' : 'القسط الثابت';

  Widget _custodianField(BuildContext context) {
    // ⚠️ **قائمةُ مستخدمين لا نصٌّ حرّ** (قرارُ المالك): النصُّ يُكتَب بثلاث
    //    صيغٍ للشخص الواحد فلا يُجمَع عليه ولا يُساءَل به.
    final options = widget.custodians;
    final valid = options.any((o) => o.id == _custodian) ? _custodian : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(context, 'المسؤول'),
        DropdownButtonFormField<int?>(
          initialValue: valid,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('— بلا مسؤول —'),
            ),
            for (final o in options)
              DropdownMenuItem<int?>(value: o.id, child: Text(o.name)),
          ],
          onChanged: widget.canEdit && _isActive
              ? (v) => setState(() => _custodian = v)
              : null,
        ),
        if (_custodian != null && valid == null)
          _reason(
            context,
            'المسؤولُ المسجَّلُ لم يعد في قائمة المستخدمين — اختر بديلاً أو '
                'ارفع العهدة',
          ),
      ],
    );
  }

  Widget _summaryCard(BuildContext context, String title, String body) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.picposField,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.picposHairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposText)),
            const SizedBox(height: 6),
            Text(body,
                style:
                    TextStyle(fontSize: 12, color: context.picposMuted)),
          ],
        ),
      );

  // ── ٢) الإهلاك ─────────────────────────────────────────────────────────

  Widget _depreciationTab(BuildContext context) {
    final a = widget.asset;
    final rows = buildDepreciationSchedule(
      purchasePrice: a.purchasePrice,
      salvageValue: a.salvageValue,
      usefulLifeYears: a.usefulLifeYears,
      depreciationMethod: a.depreciationMethod,
      purchaseDate: a.purchaseDate,
      until: _previewUntil,
      posted: widget.posted,
    );
    final postedCount = rows.where((r) => r.posted).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _pair(
          _readOnly(context, 'التكلفة الأصلية',
              _money.format(a.purchasePrice), 'كما دخلت الأستاذَ عند الاقتناء'),
          // 🔴 **بالشهور كما يرسم التصميم** — والتحويلُ في موضعٍ واحدٍ مسمّى.
          _readOnly(
              context,
              'العمر الإنتاجي',
              '${usefulLifeMonths(a.usefulLifeYears)} شهراً',
              'يُخزَّن بالسنوات ويُعرَض بالشهور — والتحويلُ موضعٌ واحدٌ '
                  'في `depreciation_math`'),
        ),
        const SizedBox(height: 14),
        _pair(
          _readOnly(context, 'طريقة الإهلاك',
              _methodLabel(a.depreciationMethod), 'تتبع الفئةَ عند الإنشاء'),
          _readOnly(context, 'القيمة التخريدية',
              _money.format(a.salvageValue), 'لا يُهلَك ما دونها'),
        ),
        const SizedBox(height: 14),
        _pair(
          _readOnly(context, 'تاريخ الاقتناء',
              _dateFmt.format(a.purchaseDate), 'أوّلُ شهرٍ في الجدول'),
          _previewUntilField(context),
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: 'جدول الإهلاك',
          subtitle: postedCount == rows.length
              ? 'كلُّ الأشهر مُرحَّلة'
              : postedCount == 0
                  ? 'لا شهرَ مُرحَّلاً بعد — الجدولُ كلُّه توقّع'
                  : '$postedCount من ${rows.length} أشهرٍ مُرحَّلة',
          minWidth: 640,
          columns: const [
            PicPosTableColumn('#', flex: 0.5),
            PicPosTableColumn('الشهر', flex: 1.4),
            PicPosTableColumn('قيمة الإهلاك',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('الإهلاك المتراكم',
                flex: 1.4, align: PicPosCellAlign.end),
            PicPosTableColumn('الحالة', flex: 1.1),
          ],
          emptyLabel: 'لا أشهرَ في هذا المدى',
          rows: [
            for (var i = 0; i < rows.length; i++)
              PicPosTableRow(cells: [
                PicPosTextCell('${i + 1}'),
                PicPosTextCell(
                    '${_monthsAr[rows[i].periodDate.month - 1]} '
                    '${rows[i].periodDate.year}'),
                PicPosTextCell(_money.format(rows[i].amount)),
                PicPosTextCell(_money.format(rows[i].accumulated)),
                // 🔴 **الوسمُ على الصفّ لا على الجدول**: جدولُ أصلٍ نصفُه
                //    مُرحَّلٌ ونصفُه توقّعٌ هو الحالةُ الطبيعيّةُ بعد أوّل
                //    شهر، ووسمٌ واحدٌ فوق الكلّ يكذب على أحد النصفين.
                rows[i].posted
                    ? const PicPosPillCell('مُرحَّل', _ok)
                    : const PicPosPillCell('متوقَّع', _warn),
              ]),
          ],
        ),
        const SizedBox(height: 12),
        PicPosTotalsBar(items: [
          PicPosTotal(
            label: 'مجموع الإهلاك المتراكم',
            value: _money.format(
                rows.isEmpty ? 0 : rows.last.accumulated),
          ),
          PicPosTotal(
            label: 'صافي القيمة الدفترية',
            value: _money.format(
                rows.isEmpty ? a.purchasePrice : rows.last.bookValue),
            emphasis: true,
          ),
        ]),
      ],
    );
  }

  Widget _previewUntilField(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(context, 'فترة المعاينة حتى'),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _previewUntil,
                firstDate: widget.asset.purchaseDate,
                lastDate: DateTime(widget.asset.purchaseDate.year + 60),
              );
              if (picked != null && mounted) {
                setState(() => _previewUntil = picked);
              }
            },
            child: Container(
              height: 44,
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.picposHairline),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.calendarBlank,
                      size: 15, color: context.picposMuted),
                  const SizedBox(width: 8),
                  Text(_dateFmt.format(_previewUntil),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.picposText)),
                ],
              ),
            ),
          ),
          _reason(context, 'يمدّ التوقّعَ ولا يُرحّل شيئاً'),
        ],
      );

  // ── ٣) الحركات ─────────────────────────────────────────────────────────

  Widget _movementsTab(BuildContext context) {
    final moves = widget.movements;
    if (moves.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.arrowsLeftRight,
        title: 'لا حركاتٍ على هذا الأصل',
        hint: 'الاقتناءُ والإهلاكُ وإعادةُ التقييم والاستبعاد تظهر هنا فورَ '
            'ترحيل قيودها.',
      );
    }
    return PicPosDataTable(
      title: 'حركات الأصل',
      subtitle: 'مشتقّةٌ من القيود بالأنواع المعلَنة — لا بالرقم وحدَه',
      minWidth: 700,
      columns: const [
        PicPosTableColumn('التاريخ', flex: 1.1),
        PicPosTableColumn('النوع', flex: 1.1),
        PicPosTableColumn('رقم القيد', flex: 1.2),
        PicPosTableColumn('البيان', flex: 2.2),
        PicPosTableColumn('الحالة', flex: 1),
      ],
      rows: [
        for (final m in moves)
          PicPosTableRow(cells: [
            PicPosTextCell(_dateFmt.format(m.date)),
            PicPosPillCell(
                assetMovementLabel(m.referenceType), AppColors.primary),
            PicPosTextCell(m.entryNumber),
            PicPosTextCell(m.description ?? '—'),
            m.isPosted
                ? const PicPosPillCell('مُرحَّل', _ok)
                : const PicPosPillCell('مسودة', _warn),
          ]),
      ],
    );
  }

  // ── شريطُ الأفعال ──────────────────────────────────────────────────────

  Widget _actionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _saving ? null : widget.onBack,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('رجوع'),
          ),
          const Spacer(),
          if (!_isActive)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Text(
                'أصلٌ خارجَ الخدمة — بطاقتُه للقراءة',
                style: TextStyle(fontSize: 11.5, color: context.picposMuted),
              ),
            ),
          FilledButton.icon(
            onPressed: widget.canEdit && _isActive && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(PhosphorIconsBold.floppyDisk, size: 16),
            label: const Text('حفظ التعديلات'),
          ),
        ],
      ),
    );
  }
}
