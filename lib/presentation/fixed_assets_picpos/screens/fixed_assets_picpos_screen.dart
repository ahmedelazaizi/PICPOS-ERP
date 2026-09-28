// شاشةُ «الأصول الثابتة والإهلاك» بهويّة PicPos — على تصميم
// `PicPos Fixed Assets.dc.html` بتبويباته الخمسة.
//
// ═══ إعادةُ تنسيقٍ لا بناء ═══
//
// الطبقةُ البيانيّةُ تغطّي التبويباتِ الخمسةَ كلَّها سلفاً: `FixedAssets`
// و`AssetCategories` و`AssetDepreciations`، و`IFixedAssetsRepository` يعطي
// المجاري الأربعةَ و`runMonthlyDepreciation` و`disposeAsset`. فلا جدولَ
// جديدَ هنا ولا `build_runner`.
//
// ═══ ⚠️ ولا يستوردُ هذا الملفُّ `data/database` ═══
//
// حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ جديدٍ من ذلك.
// و`FixedAssetData`/`AssetCategory`/`AssetDepreciationData`/`Account` تصل
// هنا عبر واجهتَي المستودع في `domain/repositories/` — فهما تستوردان طبقةَ
// القاعدة بلا بادئةٍ فتُصدِّران أنواعَها. وهذا ما تفعله الشاشةُ الأصلُ
// (`fixed_assets_screen.dart`) وهي **ليست** في القائمة البيضاء أصلاً.
//
// ═══ ⚠️ وحسابُ القسط منقولٌ عن الـDAO حرفاً بحرف ═══
//
// `_monthlyDepreciation` تطابق `runMonthlyDepreciation` في
// `fixed_assets_dao_ext.dart`: القسطُ المتناقصُ **مضاعفٌ** (`2 / (n*12)`) لا
// ٢٠٪ كما يفترض نصُّ التصميم، والسقفُ يمنع تجاوزَ المبلغ القابل للإهلاك.
// ولو انحرف الحسابان لعرضت الشاشةُ رقماً ويُقيَّد غيرُه — وهو أسوأُ من ألّا
// يُعرَض شيء. فأيُّ تعديلٍ هناك يُنقَل هنا.
//
// ═══ ⚠️ وما لم يُنقَل من التصميم ═══
//
// التصميمُ يعرض في تبويب «الإهلاك الدوري» عموداً لرقم القيد (`JV-2026-0641`)
// وشريطَ «مصروف الإهلاك الشهري» لآخر ستّة أشهر. والقيدُ مقروءٌ فعلاً من
// `AssetDepreciations.journalEntryId`، أمّا رقمُه المعروضُ للمستخدم فيحتاج
// وصلةً بجدول القيود لا يعطيها أيُّ استعلامٍ قائم — فيُعرَض «مُرحَّل» أو
// «بانتظار الترحيل» بحسب وجود صفِّ الفترة، بلا رقمٍ مخترَع.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/asset_disposal_plan.dart';
import '../../../domain/models/depreciation_math.dart';
import 'asset_card_picpos.dart';
import 'asset_disposal_request_picpos.dart';
import 'fixed_assets_picpos_create_dialog.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_stat_tile.dart';
import '../../picpos_shell/picpos_totals_bar.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/permission_guard.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _money0 = NumberFormat('#,##0', 'en');

const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _err = Color(0xFFEF4444);
  // ignore: unused_element
const _purple = Color(0xFF8B5CF6);
const _idle = Color(0xFF6B7280);

/// أرقامُ العدّ والسنواتِ بأرقامٍ عربيّةٍ كما في التصميم؛ والمبالغُ تبقى
/// بالأرقام اللاتينيّة (‏`428,000`) كما يعرضها التصميمُ نفسُه.
String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

String _pct(double v) => '${_ar(v.toStringAsFixed(0))}٪';

/// أسماءُ الشهور — ثابتةٌ لا `DateFormat('MMMM', 'ar')`.
///
/// ⚠️ **الصيغةُ باللغة تحتاج `initializeDateFormatting('ar')`** وترمي
/// «Locale data has not been initialized» إن لم تُنادَ. وذلك يجعل الشاشةَ
/// معلَّقةً على تجهيزةٍ خارجَها: تعمل في التطبيق وتنهار في أوّل اختبار — وقد
/// انهارت هنا فعلاً في التبويبات الخمسة كلِّها. والقائمةُ الثابتةُ تُغني
/// عنها وتطابق `MONTHS_AR` في التصميم.
const _monthsAr = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

String _monthLabel(DateTime d) => '${_monthsAr[d.month - 1]} ${_ar(d.year)}';

/// الأصلُ «قارب الانتهاء» حين تجاوز إهلاكُه هذا الحدَّ من مبلغه القابل
/// للإهلاك — وهو ما يميّز الأصفرَ من الأخضر في التصميم (٨٩٪ و٩٢٪ صُنّفا
/// «قارب الانتهاء»، و٥٤٪ و٧٢٪ بقيا «نشط»).
const double _nearEndThreshold = 0.85;

// ═══════════════════════════════════════════════════════════════════════════
// المجاري
// ═══════════════════════════════════════════════════════════════════════════

final _assetsProvider = StreamProvider.autoDispose<List<FixedAssetData>>(
    (ref) => ref.watch(fixedAssetsRepositoryProvider).watchFixedAssets());

final _categoriesProvider = StreamProvider.autoDispose<List<AssetCategory>>(
    (ref) => ref.watch(fixedAssetsRepositoryProvider).watchAssetCategories());

final _depreciationsProvider =
    StreamProvider.autoDispose<List<AssetDepreciationData>>((ref) =>
        ref.watch(fixedAssetsRepositoryProvider).watchAllDepreciations());

/// طلباتُ الاستبعاد مع بيانات أصولها — v175 / المرحلة ٧.
final _disposalRequestsProvider =
    FutureProvider.autoDispose<List<AssetDisposalListRow>>((ref) {
  // يُبطَل بعد كلّ حفظٍ أو اعتماد.
  return ref.watch(fixedAssetsRepositoryProvider).getAssetDisposalRows();
});

final _disposalSafesProvider = StreamProvider.autoDispose<List<SafeData>>(
    (ref) => ref.watch(treasuryRepositoryProvider).watchSafes());

final _disposalCostCentersProvider =
    FutureProvider.autoDispose<List<CostCenter>>(
        (ref) => ref.watch(accountingRepositoryProvider).getActiveCostCenters());

final _accountsProvider = StreamProvider.autoDispose<List<Account>>(
    (ref) => ref.watch(accountingRepositoryProvider).watchAllAccounts());

/// مراكزُ التكلفة — لحوار «أصل جديد» وحدَه.
final _costCentersProvider = StreamProvider.autoDispose<List<CostCenter>>(
    (ref) => ref.watch(accountingRepositoryProvider).watchCostCenters());

/// لقطاتُ الأصول **كما في تاريخ** — مرشِّحُ «كما في» في تصميم المالك `(10)`.
///
/// ⚠️ **المفتاحُ يومٌ لا لحظة**: `DateTime` تتساوى بالقيمة، فوقتُ اللحظة
/// يجعل كلَّ إعادةِ بناءٍ مفتاحاً جديداً واستعلاماً جديداً.
final _asOfSnapshotsProvider = FutureProvider.autoDispose
    .family<Map<int, ({double accumulated, double bookValue, double cost})>,
        DateTime>((ref, day) {
  return ref.watch(fixedAssetsRepositoryProvider).getAssetSnapshotsAsOf(
        DateTime(day.year, day.month, day.day, 23, 59, 59),
      );
});

/// حركاتُ أصلٍ بعينه — تبويبةُ «الحركات» في البطاقة.
final _assetMovementsProvider = FutureProvider.autoDispose
    .family<List<JournalEntryData>, int>((ref, assetId) =>
        ref.watch(fixedAssetsRepositoryProvider).getAssetMovements(assetId));

/// مستخدمو النظام — قائمةُ «المسؤول».
final _usersProvider = StreamProvider.autoDispose<List<UserWithRole>>(
    (ref) => ref.watch(authRepositoryProvider).watchAllUsers());

// ═══════════════════════════════════════════════════════════════════════════
// الحساب — خالصٌ وقابلٌ للقياس وحدَه
// ═══════════════════════════════════════════════════════════════════════════

/// المبلغُ القابلُ للإهلاك — نفسُ تعريفِ الـDAO.
double _depreciableAmount(FixedAssetData a) => a.purchasePrice - a.salvageValue;

/// القيمةُ الدفتريّة = التكلفة ناقص مجمع الإهلاك.
double _bookValue(FixedAssetData a) =>
    a.purchasePrice - a.accumulatedDepreciation;

/// نسبةُ ما أُهلك من المبلغ القابل للإهلاك — من صفرٍ إلى واحد.
double _deprRatio(FixedAssetData a) {
  final base = _depreciableAmount(a);
  if (base <= 0) return 1;
  final r = a.accumulatedDepreciation / base;
  return r.clamp(0.0, 1.0);
}

/// السنواتُ الباقية — مشتقّةٌ من نسبة الإهلاك فتتّسق مع الشريط المعروض
/// بجوارها، بدل أن تُحسَب من التاريخ فتخالفه.
  // ignore: unused_element
double _remainingYears(FixedAssetData a) =>
    (a.usefulLifeYears * (1 - _deprRatio(a))).clamp(0.0, a.usefulLifeYears);

bool _isActive(FixedAssetData a) => a.status == 'active';

bool _isNearEnd(FixedAssetData a) =>
    _isActive(a) && _deprRatio(a) >= _nearEndThreshold;

/// قسطُ الشهر لأصلٍ واحد.
///
/// ⚠️ **الصيغةُ في `domain/models/depreciation_math.dart`** — نسخةٌ واحدةٌ
/// يشاركها هذا العرضُ وحوارُ «أصل جديد»، ومصدرُها `runMonthlyDepreciation`.
/// وكانت مكتوبةً هنا بيدٍ ثانية، فلمّا صار الحوارُ يعرض جدولَ إهلاكٍ قبل
/// الإنشاء كانت ستصير ثالثة.
double _monthlyDepreciation(FixedAssetData a) => monthlyDepreciation(
      purchasePrice: a.purchasePrice,
      salvageValue: a.salvageValue,
      usefulLifeYears: a.usefulLifeYears,
      depreciationMethod: a.depreciationMethod,
      accumulatedDepreciation: a.accumulatedDepreciation,
    );

String _methodLabel(String method) =>
    method == 'declining_balance' ? 'قسط متناقص' : 'قسط ثابت';

class FixedAssetsPicposScreen extends ConsumerStatefulWidget {
  const FixedAssetsPicposScreen({super.key});

  @override
  ConsumerState<FixedAssetsPicposScreen> createState() =>
      _FixedAssetsPicposScreenState();
}

class _FixedAssetsPicposScreenState
    extends ConsumerState<FixedAssetsPicposScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  String _query = '';
  int _deprChip = 0;
  int _disposalChip = 0;

  // ── تصميمُ المالك `(10)`: مرشِّحاتٌ وترقيمُ صفحات ──────────────────────
  late DateTime _asOf = _today();
  int? _filterCategoryId;
  String? _filterLocation;
  String _filterStatus = 'all';
  int _page = 0;
  int _perPage = 10;

  /// الأصلُ المفتوحةُ بطاقتُه — `null` = الجدول.
  ///
  /// ⚠️ **حالةٌ في الشاشة لا شاشةٌ سادسة**: البطاقةُ تفصيلُ صفٍّ يفتحه 👁،
  /// ومسارُها في التصميم «الأصول الثابتة / بطاقة أصل ثابت». وشاشةٌ مستقلّةٌ
  /// كانت ستعني ستّةَ مواضعِ توصيلٍ وصلاحيّةً سابعةً لشيءٍ لا يُفتَح إلّا
  /// من هنا.
  int? _openAssetId;

  /// طلبُ استبعادٍ مفتوحٌ — إمّا جديدٌ لأصلٍ (`_disposalAssetId`) وإمّا
  /// قائمٌ (`_disposalRequestId`). واللوحُ يحلّ محلَّ الشاشة كما البطاقة.
  int? _disposalAssetId;
  int? _disposalRequestId;
  bool _disposalBusy = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static final DateFormat _dateFmt = DateFormat('dd-MM-yyyy');

  /// ⚠️ **ثلاثةٌ لا خمسة**: «الفئات» و«التوزيع والمواقع» خرجتا إلى مدخلَين
  /// جانبيَّين مستقلَّين بقرار المالك 2026-09-18. وطولُ هذه القائمة يُفهرَس
  /// بـ`_tabs.index` — فتركُ سطرَيهما كان يُظهر شرحَ الفئات تحت الاستبعاد.
  static const _tabNotes = [
    'القيمة الدفترية = التكلفة ناقص مجمع الإهلاك',
    'القسط الشهري يُرحَّل بقيد واحد لكل فئة · الأصول المستبعدة لا تُهلك',
    'الربح أو الخسارة = ثمن البيع ناقص القيمة الدفترية',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(_assetsProvider);
    final categories = ref.watch(_categoriesProvider);
    final depreciations = ref.watch(_depreciationsProvider);
    final accounts = ref.watch(_accountsProvider);

    final all = assets.value ?? const <FixedAssetData>[];
    final cats = categories.value ?? const <AssetCategory>[];
    final deprs = depreciations.value ?? const <AssetDepreciationData>[];
    final accountById = {
      for (final a in accounts.value ?? const <Account>[])
        a.id: '${a.code} · ${a.name}',
    };

    final onBooks = all.where((a) => _isActive(a)).toList();
    final disposed = all.where((a) => !_isActive(a)).toList();
  // ignore: unused_local_variable
    final locations = _locationKeys(onBooks);
    final snaps = ref.watch(_asOfSnapshotsProvider(_asOf)).value ??
        const <int, ({double accumulated, double bookValue, double cost})>{};

    // بطاقةُ أصلٍ مفتوحةٌ ⇒ تحلّ محلَّ الشاشة كلِّها: التصميمُ يعطيها الصفحةَ
    // ومسارَها الخاصّ، وعرضُها داخلَ تبويبةٍ كان سيترك شريطَ التبويبات فوقها
    // فيبدو أنّ «الإهلاك» في البطاقة و«الإهلاك الدوري» في الشاشة شيءٌ واحد.
    final open = _openAssetId == null
        ? null
        : all.where((a) => a.id == _openAssetId).firstOrNull;
    if (_openAssetId != null && open == null && !assets.isLoading) {
      // حُذف الأصلُ أو خرج من المجرى — لا بطاقةَ لشيءٍ غيرِ موجود.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _openAssetId = null);
      });
    }
    if (open != null) {
      return PicPosScreenScaffold(
        title: 'بطاقة أصل ثابت',
        subtitle: '${open.code} · ${open.name}',
        icon: PhosphorIconsBold.identificationCard,
        bodyPadding: EdgeInsets.zero,
        body: _assetCard(open, cats, deprs),
      );
    }

    // لوحُ طلبِ الاستبعاد — يحلّ محلَّ الشاشة كما البطاقة. والتصميمُ يعطيه
    // الصفحةَ كاملةً ومسارَه الخاصّ «الأصول الثابتة / طلب استبعاد أصل».
    final disposalForm = _disposalFormOrNull(all);
    if (disposalForm != null) return disposalForm;

    return PicPosScreenScaffold(
      title: 'الأصول الثابتة والإهلاك',
      subtitle: 'بطاقات الأصول والإهلاك الدوري والفئات والاستبعاد',
      icon: PhosphorIconsBold.buildings,
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'ابحث بكود الأصل أو اسمه...',
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
      headerActions: [
        // 🔴 **حارسُ الصلاحيّة ليس زينةً هنا.** «ترحيل إهلاك الشهر» يقيّد
        //    قيوداً محاسبيّةً ويزيد مجمعَ الإهلاك لكلّ أصل. والشاشةُ الأصلُ
        //    (`fixed_assets_screen.dart`) تحرسه بـ`assetsDepreciation` —
        //    وأوّلُ صيغةٍ لهذا الفورك أسقطت الحارسَ فصار الترحيلُ مبلوغاً
        //    لأيّ مَن يفتح الشاشة. وحصرُ التنقّل وحدَه لا يكفي: `assets_view`
        //    يفتح الشاشةَ للقراءة، والترحيلُ فعلُ كتابةٍ أعلى.
        PermissionGuard(
          permission: PermissionCodes.assetsDepreciation,
          child: OutlinedButton.icon(
            onPressed: () => _confirmRunDepreciation(onBooks, deprs),
            icon: const Icon(PhosphorIconsBold.arrowDownRight, size: 15),
            label: const Text('ترحيل إهلاك الشهر'),
          ),
        ),
        // ⚠️ **`HEADS.main.action` كان غائباً كلّيّاً**: الرأسُ في التصميم
        //    فعلان — «أصل جديد» و«ترحيل إهلاك الشهر» — وهذا الفوركُ حمل
        //    الثانيَ وحدَه. فالشاشةُ تعرض بطاقاتِ الأصول ولا تُنشئ أصلاً،
        //    والمستخدمُ يرجع إلى الشاشة القديمة ليضيف ثمّ يعود ليرى.
        //
        // 🔴 وحارسُه `assetsManage` لا `assetsDepreciation`: إنشاءُ أصلٍ
        //    يقيّد قيدَ اقتناءٍ ويُنشئ حساباً فرعيّاً، وهو فعلٌ آخرُ غيرُ
        //    الترحيل — ومَن يملك الترحيلَ قد لا يملك الإنشاء.
        PermissionGuard(
          permission: PermissionCodes.assetsManage,
          child: FilledButton.icon(
            onPressed: _createAsset,
            icon: const Icon(PhosphorIconsBold.plus, size: 15),
            label: const Text('أصل جديد'),
          ),
        ),
      ],
      subHeader: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosReportTabs(
            controller: _tabs,
            tabs: [
              (
                label: 'الأصول',
                icon: PhosphorIconsBold.package,
                badge: '${all.length}'
              ),
              (
                label: 'الإهلاك الدوري',
                icon: PhosphorIconsBold.arrowDownRight,
                badge: '${_activeCategoryIds(onBooks).length}'
              ),
              (
                label: 'الاستبعاد والبيع',
                icon: PhosphorIconsBold.trash,
                badge: '${disposed.length}'
              ),
            ],
          ),
          PicPosTabNote(note: _tabNotes[_tabs.index]),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: assets.isLoading && all.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _scroll(_assetsTab(all, cats, snaps)),
                _scroll(_depreciationTab(onBooks, cats, deprs, accountById)),
                _scroll(_disposalTab(disposed)),
              ],
            ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 20),
        child: child,
      );

  /// صفُّ عدّاداتٍ يلتفّ بدل أن يفيض.
  ///
  /// ⚠️ `LayoutBuilder` هنا آمنٌ لأنّ شيئاً لا يطلب منه ارتفاعاً جوهريّاً —
  /// و`IntrinsicHeight` حول `LayoutBuilder` كان قد أسقط شاشةَ التكاليف
  /// المحمَّلة كاملةً، فلا يُلَفّ هذا الصفُّ بها أبداً.
  Widget _kpis(List<Widget> tiles) {
    return LayoutBuilder(builder: (context, box) {
      final perRow = box.maxWidth < 900 ? 2 : tiles.length;
      final w = (box.maxWidth - (perRow - 1) * 12) / perRow;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }

  bool _matches(FixedAssetData a) {
    if (_query.isEmpty) return true;
    return a.code.toLowerCase().contains(_query) ||
        a.name.toLowerCase().contains(_query);
  }

  Set<int> _activeCategoryIds(List<FixedAssetData> onBooks) =>
      {for (final a in onBooks) a.categoryId};

  List<String> _locationKeys(List<FixedAssetData> onBooks) {
    final seen = <String>{};
    for (final a in onBooks) {
      seen.add((a.location ?? '').trim().isEmpty ? 'بلا موقع' : a.location!);
    }
    return seen.toList()..sort();
  }


  // ═════════════════════════════════════════════════════════════════════════
  // بطاقةُ الأصل — تحويلُ صفوف drift إلى قيمٍ خالصة
  // ═════════════════════════════════════════════════════════════════════════
  //
  // ⚠️ **التحويلُ هنا لا في البطاقة**: `asset_card_picpos.dart` ملفُّ عرضٍ
  // **جديد**، وحارسُ `presentation_db_import_guard` يمنعه من استيراد
  // `data/database` وقائمتُه البيضاءُ مقفولة. وهذه الشاشةُ سابقةٌ للحارس
  // فتستورد الأنواعَ عبر واجهات `domain/repositories/`.

  Widget _assetCard(
    FixedAssetData a,
    List<AssetCategory> cats,
    List<AssetDepreciationData> deprs,
  ) {
    final users = ref.watch(_usersProvider).value ?? const <UserWithRole>[];
    final moves = ref.watch(_assetMovementsProvider(a.id)).value ??
        const <JournalEntryData>[];

    return AssetCardPicpos(
      key: ValueKey('asset_card_${a.id}'),
      asset: (
        id: a.id,
        code: a.code,
        name: a.name,
        categoryId: a.categoryId,
        categoryName:
            cats.where((c) => c.id == a.categoryId).firstOrNull?.name ?? '—',
        location: a.location,
        purchasePrice: a.purchasePrice,
        purchaseDate: a.purchaseDate,
        usefulLifeYears: a.usefulLifeYears,
        salvageValue: a.salvageValue,
        depreciationMethod: a.depreciationMethod,
        accumulatedDepreciation: a.accumulatedDepreciation,
        status: a.status,
        notes: a.notes,
        custodianUserId: a.custodianUserId,
      ),
      custodians: [
        for (final u in users)
          if (u.user.isActive) (id: u.user.id, name: u.user.displayName),
      ],
      posted: [
        for (final d in deprs)
          if (d.assetId == a.id)
            (
              periodDate: d.periodDate,
              amount: d.depreciationAmount,
              accumulated: d.accumulatedDepreciation,
              bookValue: d.bookValue,
            ),
      ],
      movements: [
        for (final m in moves)
          (
            date: m.entryDate,
            entryNumber: m.entryNumber,
            description: m.description,
            referenceType: m.referenceType,
            isPosted: m.isPosted,
          ),
      ],
      // 🔴 **حارسُ الصلاحيّة على الحفظ لا على الفتح**: `assets_view` يفتح
      //    الشاشةَ للقراءة، وتعديلُ اسمِ أصلٍ أو مسؤوليّتِه فعلُ كتابةٍ أعلى.
      canEdit: ref
          .watch(hasPermissionProvider(PermissionCodes.assetsManage))
          .value ??
          false,
      onBack: () => setState(() => _openAssetId = null),
      onSave: ({
        required String name,
        required String? location,
        required String? notes,
        required int? custodianUserId,
        required bool clearCustodian,
      }) async {
        await ref.read(fixedAssetsRepositoryProvider).updateFixedAsset(
              a.id,
              name: name,
              location: location,
              notes: notes,
              custodianUserId: custodianUserId,
              clearCustodian: clearCustodian,
            );
        if (!mounted) return;
        ref.invalidate(_assetMovementsProvider(a.id));
        AppToast.show(context, 'حُفظت تعديلاتُ البطاقة');
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ١ — الأصول (تصميمُ المالك `(10)`: مرشِّحاتٌ · شريطٌ نحيفٌ · جدولٌ بترقيم)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _assetsTab(
    List<FixedAssetData> all,
    List<AssetCategory> cats,
    Map<int, ({double accumulated, double bookValue, double cost})> snaps,
  ) {
  // ignore: unused_local_variable
    final catName = {for (final c in cats) c.id: c.name};

    // 🔴 **اليومُ يُقرأ حيّاً والماضي يُقرأ لقطةً.**
    //
    // `fixed_assets.accumulated_depreciation` هو **حاضرُ** الأصل: تكتبه
    // `runMonthlyDepreciation` و`disposeAsset` وأيُّ استيرادٍ سابق. وقصرُ
    // القراءة على `asset_depreciations` كان سيُظهر صفراً لأصلٍ مجمَّعُه
    // قائمٌ في بطاقته لكنّ صفوفَه لم تُكتَب (تجهيزةٌ مرحَّلةٌ من نظامٍ آخر
    // مثلاً) — أي إخفاءُ تعارضٍ بدل إظهاره.
    //
    // وسؤالُ «كم كان في تاريخٍ مضى؟» لا يجيبه العمودُ الحيُّ إطلاقاً،
    // فجوابُه اللقطة.
    final historical = _asOf.isBefore(_today());

    /// أرقامُ الأصل **كما في التاريخ المختار**.
    ///
    /// ⚠️ وأصلٌ بلا لقطةٍ حتى تاريخٍ ماضٍ يُقرأ بتكلفته ومجمَّعِ صفر — وهو ما
    /// كان عليه فعلاً قبل أوّل ترحيلِ إهلاك.
    ({double cost, double accum, double book}) figures(FixedAssetData a) {
      if (!historical) {
        return (
          cost: a.purchasePrice,
          accum: a.accumulatedDepreciation,
          book: a.purchasePrice - a.accumulatedDepreciation,
        );
      }
      final s = snaps[a.id];
      if (s == null) {
        return (cost: a.purchasePrice, accum: 0, book: a.purchasePrice);
      }
      return (cost: s.cost, accum: s.accumulated, book: s.bookValue);
    }

    // 🔴 الشرطُ في `domain/models` ومُختبَرٌ وحدَه — راجع
    //    [assetOnBooksAt].
    final onDate =
        all.where((a) => assetOnBooksAt(a.purchaseDate, _asOf)).toList();

    final visible = onDate.where(_matches).where((a) {
      if (_filterCategoryId != null && a.categoryId != _filterCategoryId) {
        return false;
      }
      if (_filterLocation != null && _locationOf(a) != _filterLocation) {
        return false;
      }
      if (_filterStatus == 'active' && !_isActive(a)) return false;
      if (_filterStatus == 'disposed' && _isActive(a)) return false;
      return true;
    }).toList();

    final cost = visible.fold<double>(0, (s, a) => s + figures(a).cost);
    final accum = visible.fold<double>(0, (s, a) => s + figures(a).accum);
    final nearEnd = visible.where(_isNearEnd).length;

    // ترقيمُ الصفحات — والصفحةُ تُقصّ إلى المدى بعد أيّ ترشيح.
    final pages = visible.isEmpty ? 1 : ((visible.length - 1) ~/ _perPage) + 1;
    final page = _page >= pages ? pages - 1 : _page;
    final from = page * _perPage;
    final shown = visible.skip(from).take(_perPage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _assetFilters(context, cats, onDate),
        const SizedBox(height: 12),
        // **شريطٌ نحيفٌ** بدل خمسِ بطاقات — التصميمُ يعطي الجدولَ الصفحةَ.
        PicPosTotalsBar(items: [
          PicPosTotal(label: 'الأصول', value: _ar(visible.length)),
          PicPosTotal(label: 'التكلفة', value: _money0.format(cost)),
          PicPosTotal(label: 'مجمع الإهلاك', value: _money0.format(accum)),
          PicPosTotal(
              label: 'صافي القيمة',
              value: _money0.format(cost - accum),
              emphasis: true),
          PicPosTotal(
            label: 'قارب عمرها',
            value: _ar(nearEnd),
            tone: nearEnd > 0 ? _warn : null,
          ),
        ]),
        const SizedBox(height: 12),
        PicPosDataTable(
          title: 'بطاقات الأصول',
          subtitle: historical
              ? 'الأرقامُ كما في ${_dateFmt.format(_asOf)} — من لقطات '
                  'الإهلاك المرحَّلة لا من أرصدة اليوم'
              : 'القيمة الدفترية = التكلفة ناقص مجمع الإهلاك',
          minWidth: 1020,
          columns: const [
            PicPosTableColumn('#', flex: 0.4),
            PicPosTableColumn('رقم الأصل', flex: 1),
            PicPosTableColumn('الأصل', flex: 1.7),
            PicPosTableColumn('الموقع', flex: 1.1),
            PicPosTableColumn('التكلفة',
                flex: 1.1, align: PicPosCellAlign.end),
            PicPosTableColumn('مجمع الإهلاك',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('صافي القيمة',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('الحالة', flex: 1.1),
            PicPosTableColumn('إجراءات', flex: 0.9),
            PicPosTableColumn('استبعاد', flex: 1.0),
          ],
          emptyLabel: _query.isEmpty
              ? 'لا أصولَ تطابق المرشِّحات'
              : 'لا أصلَ يطابق «$_query»',
          rows: [
            for (var i = 0; i < shown.length; i++)
              () {
                final a = shown[i];
                final f = figures(a);
                return PicPosTableRow(cells: [
                  PicPosTextCell(_ar(from + i + 1)),
                  PicPosTextCell(a.code),
                  PicPosTextCell(a.name,
                      icon: PhosphorIconsBold.package,
                      tint: _isNearEnd(a) ? _warn : AppColors.primary),
                  PicPosTextCell(_locationOf(a)),
                  PicPosTextCell(_money0.format(f.cost)),
                  PicPosTextCell(_money0.format(f.accum)),
                  PicPosTextCell(_money0.format(f.book), bold: true),
                  PicPosPillCell(
                    _isActive(a)
                        ? (_isNearEnd(a) ? 'قارب الانتهاء' : 'قيد الاستخدام')
                        : (a.status == 'sold' ? 'بيع' : 'مستبعد'),
                    _isActive(a) ? (_isNearEnd(a) ? _warn : _ok) : _idle,
                  ),
                  // 👁 — البطاقة.
                  PicPosButtonCell(
                    'البطاقة',
                    icon: PhosphorIconsBold.eye,
                    tint: AppColors.primary,
                    onPressed: () => setState(() => _openAssetId = a.id),
                  ),
                  // ⋮ في التصميم — وصار فيه فعلٌ واحدٌ حقيقيٌّ (v175)، فبُني
                  // زرّاً مسمّى لا قائمةً بعنصرٍ واحد.
                  //
                  // ⚠️ **ويُعطَّل لأصلٍ غيرِ نشط**: استبعادٌ ثانٍ يقيّد التكلفةَ
                  //    والمجمَّعَ مرّةً أخرى، والقيدُ متّزنٌ فلا فحصَ اتّزانٍ
                  //    يمسكه.
                  PicPosButtonCell(
                    _isActive(a) ? 'طلب استبعاد' : '—',
                    icon: PhosphorIconsBold.trash,
                    tint: _isActive(a) ? _err : _idle,
                    onPressed: _isActive(a)
                        ? () => setState(() {
                              _disposalRequestId = null;
                              _disposalAssetId = a.id;
                            })
                        : null,
                  ),
                ]);
              }(),
          ],
          totals: shown.isEmpty
              ? null
              : [
                  '',
                  '${_ar(visible.length)} أصول',
                  '',
                  '',
                  _money0.format(cost),
                  _money0.format(accum),
                  _money0.format(cost - accum),
                  '',
                  '',
                  '',
                ],
        ),
        const SizedBox(height: 10),
        _pager(context, visible.length, page, pages, from, shown.length),
      ],
    );
  }

  String _locationOf(FixedAssetData a) =>
      (a.location ?? '').trim().isEmpty ? 'بلا موقع' : a.location!.trim();

  Widget _assetFilters(
    BuildContext context,
    List<AssetCategory> cats,
    List<FixedAssetData> onDate,
  ) {
    final locations = _locationKeys(onDate);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.picposHairline),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _asOfButton(context),
          _dropFilter<int?>(
            context,
            label: 'الفئة',
            value: _filterCategoryId,
            allLabel: 'كل الفئات',
            items: [for (final c in cats) (value: c.id, label: c.name)],
            onChanged: (v) => setState(() {
              _filterCategoryId = v;
              _page = 0;
            }),
          ),
          _dropFilter<String?>(
            context,
            label: 'الموقع',
            value: _filterLocation,
            allLabel: 'كل المواقع',
            items: [for (final l in locations) (value: l, label: l)],
            onChanged: (v) => setState(() {
              _filterLocation = v;
              _page = 0;
            }),
          ),
          _dropFilter<String?>(
            context,
            label: 'الحالة',
            value: _filterStatus == 'all' ? null : _filterStatus,
            allLabel: 'كل الحالات',
            items: const [
              (value: 'active', label: 'قيد الاستخدام'),
              (value: 'disposed', label: 'مستبعد أو مُباع'),
            ],
            onChanged: (v) => setState(() {
              _filterStatus = v ?? 'all';
              _page = 0;
            }),
          ),
          OutlinedButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(PhosphorIconsBold.arrowCounterClockwise, size: 15),
            label: const Text('إعادة تعيين'),
          ),
        ],
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _asOf = _today();
      _filterCategoryId = null;
      _filterLocation = null;
      _filterStatus = 'all';
      _page = 0;
      _query = '';
      _searchCtrl.clear();
    });
  }

  Widget _asOfButton(BuildContext context) {
    final isToday = _sameDay(_asOf, _today());
    return _filterShell(
      context,
      label: 'كما في',
      on: !isToday,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.calendarBlank,
              size: 14, color: context.picposMuted),
          const SizedBox(width: 6),
          Text(_dateFmt.format(_asOf),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.picposText)),
        ],
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _asOf,
          firstDate: DateTime(2015),
          lastDate: DateTime(DateTime.now().year + 5),
        );
        if (picked != null && mounted) {
          setState(() {
            _asOf = picked;
            _page = 0;
          });
        }
      },
    );
  }

  Widget _dropFilter<T>(
    BuildContext context, {
    required String label,
    required T value,
    required String allLabel,
    required List<({T value, String label})> items,
    required ValueChanged<T?> onChanged,
  }) {
    return _filterShell(
      context,
      label: label,
      on: value != null,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isDense: true,
          hint: Text(allLabel,
              style: TextStyle(fontSize: 12, color: context.picposText)),
          items: [
            DropdownMenuItem<T?>(value: null, child: Text(allLabel)),
            for (final i in items)
              DropdownMenuItem<T?>(value: i.value, child: Text(i.label)),
          ],
          onChanged: onChanged,
          style: TextStyle(fontSize: 12, color: context.picposText),
        ),
      ),
    );
  }

  Widget _filterShell(
    BuildContext context, {
    required String label,
    required bool on,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final body = Container(
      height: 38,
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: on ? AppColors.primary.withValues(alpha: .06) : context.picposField,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: on ? AppColors.primary : context.picposHairline),
      ),
      child: child,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(label,
              style: TextStyle(fontSize: 11, color: context.picposMuted)),
        ),
        if (onTap == null)
          body
        else
          InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: onTap,
              child: body),
      ],
    );
  }

  Widget _pager(
    BuildContext context,
    int total,
    int page,
    int pages,
    int from,
    int count,
  ) {
    return Row(
      children: [
        Text('عرض', style: TextStyle(fontSize: 12, color: context.picposMuted)),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: _perPage,
          isDense: true,
          items: [
            for (final n in const [10, 25, 50])
              DropdownMenuItem(value: n, child: Text(_ar(n))),
          ],
          onChanged: (v) => setState(() {
            _perPage = v ?? 10;
            _page = 0;
          }),
        ),
        const SizedBox(width: 8),
        Text('لكل صفحة',
            style: TextStyle(fontSize: 12, color: context.picposMuted)),
        const Spacer(),
        Text(
          total == 0
              ? 'لا نتائج'
              : 'عرض ${_ar(from + 1)} إلى ${_ar(from + count)} '
                  'من ${_ar(total)} نتيجة',
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'السابق',
          onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
          icon: const Icon(Icons.chevron_right, size: 18),
        ),
        Text('${_ar(page + 1)} / ${_ar(pages)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        IconButton(
          tooltip: 'التالي',
          onPressed:
              page < pages - 1 ? () => setState(() => _page = page + 1) : null,
          icon: const Icon(Icons.chevron_left, size: 18),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ٢ — الإهلاك الدوري
  // ═════════════════════════════════════════════════════════════════════════

  Widget _depreciationTab(
    List<FixedAssetData> onBooks,
    List<AssetCategory> cats,
    List<AssetDepreciationData> deprs,
    Map<int, String> accountById,
  ) {
    final period = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final periodLabel = _monthLabel(period);

    // أصولُ الفترة التي رُحِّلت بالفعل — نفسُ شرطِ الـDAO (‏صفٌّ لهذا الأصل
    // في هذه الفترة يعني «رُحِّل» ويُتخطّى).
    final postedAssetIds = {
      for (final d in deprs)
        if (DateTime(d.periodDate.year, d.periodDate.month, 1) == period)
          d.assetId,
    };

    final byCat = <int, List<FixedAssetData>>{};
    for (final a in onBooks) {
      if (_monthlyDepreciation(a) <= 0) continue;
      byCat.putIfAbsent(a.categoryId, () => []).add(a);
    }

    final catById = {for (final c in cats) c.id: c};
    final rows = byCat.entries.toList()
      ..sort((x, y) => (catById[x.key]?.name ?? '')
          .compareTo(catById[y.key]?.name ?? ''));

    final monthTotal = onBooks.fold<double>(
        0, (s, a) => s + (_monthlyDepreciation(a)));
    final postedTotal = onBooks
        .where((a) => postedAssetIds.contains(a.id))
        .fold<double>(0, (s, a) => s + _monthlyDepreciation(a));
    final pendingCats = rows
        .where((e) => e.value.any((a) => !postedAssetIds.contains(a.id)))
        .length;

    final visible = rows.where((e) {
      final allPosted = e.value.every((a) => postedAssetIds.contains(a.id));
      if (_deprChip == 1) return allPosted;
      if (_deprChip == 2) return !allPosted;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _kpis([
          PicPosStatTile(
            label: 'قسط الشهر',
            value: _money.format(monthTotal),
            icon: PhosphorIconsBold.arrowDownRight,
            accent: _warn,
            caption: periodLabel,
          ),
          PicPosStatTile(
            label: 'مُرحَّل',
            value: '${_ar(rows.length - pendingCats)} فئات',
            icon: PhosphorIconsBold.checkCircle,
            accent: _ok,
            caption: '${_money0.format(postedTotal)} ج.م',
          ),
          PicPosStatTile(
            label: 'بانتظار الترحيل',
            value: '${_ar(pendingCats)} فئات',
            icon: PhosphorIconsBold.clock,
            accent: pendingCats == 0 ? _ok : _err,
            caption: '${_money0.format(monthTotal - postedTotal)} ج.م',
          ),
          PicPosStatTile(
            label: 'أصول تُهلك',
            value: _ar(onBooks.where((a) => _monthlyDepreciation(a) > 0).length),
            icon: PhosphorIconsBold.package,
            accent: AppColors.primary,
            caption: 'المستبعدة لا تُهلك',
          ),
        ]),
        const SizedBox(height: 12),
        PicPosDataTable(
          title: 'أقساط الإهلاك — $periodLabel',
          subtitle:
              'قيد واحد لكل فئة يخصم المصروف ويزيد مجمع الإهلاك · الأصول المستبعدة لا تُهلك',
          minWidth: 940,
          chips: [
            PicPosTableChip(
                label: 'الكل',
                count: _ar(rows.length),
                onTap: () => setState(() => _deprChip = 0)),
            PicPosTableChip(
                label: 'مُرحَّل',
                count: _ar(rows.length - pendingCats),
                onTap: () => setState(() => _deprChip = 1)),
            PicPosTableChip(
                label: 'بانتظار',
                count: _ar(pendingCats),
                onTap: () => setState(() => _deprChip = 2)),
          ],
          selectedChip: _deprChip,
          columns: const [
            PicPosTableColumn('الفئة', flex: 1.7),
            PicPosTableColumn('الطريقة', flex: 1.4),
            PicPosTableColumn('الأصول', align: PicPosCellAlign.end),
            PicPosTableColumn('قسط الشهر',
                flex: 1.3, align: PicPosCellAlign.end),
            PicPosTableColumn('حساب الإهلاك', flex: 1.6),
            PicPosTableColumn('الحالة', flex: 1.3),
          ],
          emptyLabel: 'لا فئةَ لها أصولٌ تُهلك هذا الشهر',
          rows: [
            for (final e in visible)
              () {
                final cat = catById[e.key];
                final assets = e.value;
                final posted =
                    assets.every((a) => postedAssetIds.contains(a.id));
                final amount = assets.fold<double>(
                    0, (s, a) => s + _monthlyDepreciation(a));
                final method =
                    cat?.defaultDepreciationMethod ?? 'straight_line';
                return PicPosTableRow(cells: [
                  PicPosTextCell(cat?.name ?? 'فئة #${e.key}',
                      icon: PhosphorIconsBold.folders,
                      tint: posted ? _ok : _err),
                  PicPosTextCell(
                    _methodLabel(method),
                    sub: method == 'declining_balance' && cat != null
                        ? 'مضاعف · ${_pct(2 / cat.defaultUsefulLife * 100)} سنوياً'
                        : null,
                  ),
                  PicPosTextCell(_ar(assets.length)),
                  PicPosTextCell(_money.format(amount), bold: true),
                  PicPosTextCell(
                      accountById[cat?.depreciationAccountId] ?? '— غير مربوط',
                      tint: cat?.depreciationAccountId == null ? _err : null),
                  PicPosPillCell(posted ? 'مُرحَّل' : 'بانتظار الترحيل',
                      posted ? _ok : _warn),
                ]);
              }(),
          ],
          totals: visible.isEmpty
              ? null
              : [
                  '${_ar(visible.length)} فئات',
                  '',
                  _ar(visible.fold<int>(0, (s, e) => s + e.value.length)),
                  _money.format(visible.fold<double>(
                      0,
                      (s, e) =>
                          s +
                          e.value.fold<double>(
                              0, (x, a) => x + _monthlyDepreciation(a)))),
                  '',
                  '',
                ],
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ٤ — الاستبعاد والبيع
  // ═════════════════════════════════════════════════════════════════════════

  /// اللوحُ إن كان مفتوحاً — وإلّا `null`.
  ///
  /// ⚠️ **ويُغلَق من تلقائه إن ذهب أصلُه**: طلبٌ لأصلٍ حُذف يترك نموذجاً
  ///    يعمل على ما لا يُرى، وأوّلُ حفظٍ منه يسقط برسالةِ محرّكٍ غامضة.
  Widget? _disposalFormOrNull(List<FixedAssetData> all) {
    if (_disposalAssetId == null && _disposalRequestId == null) return null;

    final rows = ref.watch(_disposalRequestsProvider).value ??
        const <AssetDisposalListRow>[];
    final existing = _disposalRequestId == null
        ? null
        : rows.where((r) => r.request.id == _disposalRequestId).firstOrNull;

    final assetId = existing?.request.assetId ?? _disposalAssetId;
    final asset = all.where((a) => a.id == assetId).firstOrNull;
    if (asset == null) {
      if (!ref.watch(_assetsProvider).isLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _closeDisposal();
        });
      }
      return null;
    }

    final parties = ref.watch(allPartiesProvider).value ?? const <Party>[];
    final safes = ref.watch(_disposalSafesProvider).value ?? const <SafeData>[];
    final costCenters =
        ref.watch(_disposalCostCentersProvider).value ?? const <CostCenter>[];

    return PicPosScreenScaffold(
      title: 'طلب استبعاد أصل',
      subtitle: '${asset.code} · ${asset.name}',
      icon: PhosphorIconsBold.trash,
      bodyPadding: EdgeInsets.zero,
      body: AssetDisposalRequestForm(
        key: ValueKey('disposal_form_${existing?.request.id ?? 'new_$assetId'}'),
        asset: (
          id: asset.id,
          code: asset.code,
          name: asset.name,
          originalCost: asset.purchasePrice,
          accumulatedDepreciation: asset.accumulatedDepreciation,
          status: asset.status,
        ),
        value: existing == null
            ? null
            : (
                id: existing.request.id,
                number: existing.request.disposalNumber,
                status: existing.request.status,
                disposalDate: existing.request.disposalDate,
                method: existing.request.method,
                disposalValue: existing.request.disposalValue,
                collectionMethod: existing.request.collectionMethod,
                buyerPartyId: existing.request.buyerPartyId,
                costCenterId: existing.request.costCenterId,
                reason: existing.request.notes ?? '',
              ),
        parties: [for (final p in parties) (id: p.id, name: p.name)],
        safes: [
          for (final s in safes)
            if (s.isActive) (id: s.id, name: s.name),
        ],
        costCenters: [for (final c in costCenters) (id: c.id, name: c.name)],
        busy: _disposalBusy,
        onBack: _closeDisposal,
        onSubmit: _submitDisposal,
      ),
    );
  }

  void _closeDisposal() => setState(() {
        _disposalAssetId = null;
        _disposalRequestId = null;
      });

  Future<void> _submitDisposal(DisposalSubmission v) async {
    if (_disposalBusy) return;
    setState(() => _disposalBusy = true);
    final repo = ref.read(fixedAssetsRepositoryProvider);
    final user = ref.read(authProvider).user;
    try {
      var id = v.requestId;
      if (id == null) {
        id = await repo.createAssetDisposalRequest(
          assetId: v.assetId,
          disposalDate: v.disposalDate,
          method: v.method,
          disposalValue: v.disposalValue,
          collectionMethod: v.collectionMethod,
          reason: v.reason,
          buyerPartyId: v.buyerPartyId,
          safeId: v.safeId,
          costCenterId: v.costCenterId,
          createdBy: user?.id,
        );
      } else {
        await repo.updateAssetDisposalRequest(
          id: id,
          disposalDate: v.disposalDate,
          method: v.method,
          disposalValue: v.disposalValue,
          collectionMethod: v.collectionMethod,
          reason: v.reason,
          buyerPartyId: v.buyerPartyId,
          safeId: v.safeId,
          costCenterId: v.costCenterId,
        );
      }

      // 🔴 **الاعتمادُ خطوةٌ ثانيةٌ على مستندٍ محفوظ** — فلو سقط القيدُ بقيت
      //    المسوّدةُ قائمةً يُعاد الاعتمادُ عليها بعد إصلاح السبب، ولم يضع
      //    ما كتبه المستخدم.
      if (v.approve) {
        await repo.approveAssetDisposal(
          id,
          safeId: v.safeId,
          approvedBy: user?.id,
          approvedByName: user?.displayName,
        );
      }

      ref.invalidate(_disposalRequestsProvider);
      if (!mounted) return;
      AppToast.show(
          context, v.approve ? 'تم اعتماد الاستبعاد' : 'حُفظت المسودة');
      _closeDisposal();
    } catch (e) {
      // 🔴 **ورسالةُ المحرّك كما هي**: هو وحدَه يعرف أيُّ حسابٍ غاب وأيُّ
      //    فئةٍ بلا ربط.
      if (!mounted) return;
      AppToast.show(context, '$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _disposalBusy = false);
    }
  }

  Widget _disposalTab(List<FixedAssetData> disposed) {
    final requests = ref.watch(_disposalRequestsProvider).value ??
        const <AssetDisposalListRow>[];

    if (disposed.isEmpty && requests.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.trash,
        title: 'لا طلباتِ استبعادٍ ولا أصولَ مستبعدة',
        hint: 'ابدأ من «طلب استبعاد» في جدول الأصول — والمسوّدةُ بلا أثرٍ '
            'محاسبيّ حتى تُعتمَد.',
      );
    }

    double proceeds(FixedAssetData a) => a.disposalValue ?? 0;
    double gain(FixedAssetData a) => proceeds(a) - _bookValue(a);

    final visible = disposed.where(_matches).where((a) {
      if (_disposalChip == 1) return a.status == 'sold';
      if (_disposalChip == 2) return a.status != 'sold';
      return true;
    }).toList();

    final totalProceeds = disposed.fold<double>(0, (s, a) => s + proceeds(a));
    final totalBook = disposed.fold<double>(0, (s, a) => s + _bookValue(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (requests.isNotEmpty) ...[
          _disposalRequestsTable(requests),
          const SizedBox(height: 12),
        ],
        if (disposed.isEmpty)
          const PicPosEmptyState(
            icon: PhosphorIconsBold.trash,
            title: 'لا أصولَ خرجت من الدفاتر بعد',
            hint: 'الطلباتُ أعلاه مسوّداتٌ — والاعتمادُ وحدَه يُخرج الأصل.',
          )
        else ...[
        _kpis([
          PicPosStatTile(
            label: 'أصول مستبعدة',
            value: _ar(disposed.length),
            icon: PhosphorIconsBold.trash,
            accent: _idle,
          ),
          PicPosStatTile(
            label: 'ثمن البيع',
            value: _money0.format(totalProceeds),
            icon: PhosphorIconsBold.currencyCircleDollar,
            accent: _ok,
          ),
          PicPosStatTile(
            label: 'القيمة الدفترية عند البيع',
            value: _money0.format(totalBook),
            icon: PhosphorIconsBold.scales,
            accent: AppColors.primary,
          ),
          PicPosStatTile(
            label: 'صافي الربح من البيع',
            value: _money0.format(totalProceeds - totalBook),
            icon: PhosphorIconsBold.trendUp,
            accent: totalProceeds - totalBook >= 0 ? _ok : _err,
            caption: 'إيراد غير تشغيلي',
          ),
        ]),
        const SizedBox(height: 12),
        PicPosDataTable(
          title: 'الاستبعاد والبيع',
          subtitle:
              'الربح أو الخسارة = ثمن البيع ناقص القيمة الدفترية عند الاستبعاد',
          minWidth: 1060,
          chips: [
            PicPosTableChip(
                label: 'الكل',
                count: _ar(disposed.length),
                onTap: () => setState(() => _disposalChip = 0)),
            PicPosTableChip(
                label: 'بيع',
                count: _ar(disposed.where((a) => a.status == 'sold').length),
                onTap: () => setState(() => _disposalChip = 1)),
            PicPosTableChip(
                label: 'إعدام',
                count: _ar(disposed.where((a) => a.status != 'sold').length),
                onTap: () => setState(() => _disposalChip = 2)),
          ],
          selectedChip: _disposalChip,
          columns: const [
            PicPosTableColumn('الأصل', flex: 1.7),
            PicPosTableColumn('التاريخ', flex: 1.2),
            PicPosTableColumn('التكلفة',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('مجمع الإهلاك',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('الدفترية',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('ثمن البيع',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('الربح / الخسارة',
                flex: 1.4, align: PicPosCellAlign.end),
            PicPosTableColumn('النوع', flex: 1.2),
          ],
          rows: [
            for (final a in visible)
              PicPosTableRow(cells: [
                PicPosTextCell('${a.code} · ${a.name}',
                    icon: PhosphorIconsBold.package,
                    tint: a.status == 'sold' ? _ok : _err),
                PicPosTextCell(a.disposalDate == null
                    ? '—'
                    : DateFormat('yyyy-MM-dd').format(a.disposalDate!)),
                PicPosTextCell(_money0.format(a.purchasePrice)),
                PicPosTextCell(_money0.format(a.accumulatedDepreciation)),
                PicPosTextCell(_money0.format(_bookValue(a))),
                PicPosTextCell(_money0.format(proceeds(a))),
                gain(a).abs() < 0.005
                    ? const PicPosTextCell('لا ربح ولا خسارة')
                    : PicPosTrendCell(
                        '${_money0.format(gain(a).abs())} '
                        '${gain(a) > 0 ? 'ربح' : 'خسارة'}',
                        up: gain(a) > 0),
                PicPosPillCell(a.status == 'sold' ? 'بيع' : 'إعدام',
                    a.status == 'sold' ? _ok : _err),
              ]),
          ],
          totals: visible.isEmpty
              ? null
              : [
                  '${_ar(visible.length)} أصول',
                  '',
                  _money0.format(
                      visible.fold<double>(0, (s, a) => s + a.purchasePrice)),
                  _money0.format(visible.fold<double>(
                      0, (s, a) => s + a.accumulatedDepreciation)),
                  _money0
                      .format(visible.fold<double>(0, (s, a) => s + _bookValue(a))),
                  _money0
                      .format(visible.fold<double>(0, (s, a) => s + proceeds(a))),
                  _money0.format(visible.fold<double>(0, (s, a) => s + gain(a))),
                  '',
                ],
        ),
        ],
      ],
    );
  }

  /// جدولُ الطلبات — **والمسوّدةُ تُفتَح بالنقر**.
  ///
  /// ⚠️ بلا هذا الجدول تختفي المسوّدةُ لحظةَ إغلاق اللوح: لا مدخلَ يعيد
  ///    فتحَها، والأصلُ يبقى ممنوعاً من طلبٍ ثانٍ بسببها.
  Widget _disposalRequestsTable(List<AssetDisposalListRow> rows) {
    return PicPosDataTable(
      title: 'طلبات الاستبعاد',
      subtitle: 'المسوّدةُ بلا أثرٍ محاسبيّ — والاعتمادُ يُخرج الأصلَ ويقيّد '
          'الفرق',
      minWidth: 1020,
      emptyLabel: 'لا طلبات',
      columns: const [
        PicPosTableColumn('رقم الطلب', flex: 1.1),
        PicPosTableColumn('الأصل', flex: 1.7),
        PicPosTableColumn('التاريخ', flex: 1.1),
        PicPosTableColumn('الطريقة', flex: 1.0),
        PicPosTableColumn('القيمة', flex: 1.1, align: PicPosCellAlign.end),
        PicPosTableColumn('التحصيل', flex: 1.1),
        PicPosTableColumn('الحالة', flex: 1.0),
      ],
      rows: [
        for (final r in rows)
          PicPosTableRow(
            selected: _disposalRequestId == r.request.id,
            onTap: () => setState(() {
              _disposalAssetId = null;
              _disposalRequestId = r.request.id;
            }),
            cells: [
              PicPosTextCell(r.request.disposalNumber,
                  icon: PhosphorIconsBold.fileText),
              PicPosTextCell(r.assetName, sub: r.assetCode),
              PicPosTextCell(_dateFmt.format(r.request.disposalDate)),
              PicPosTextCell(disposalMethodLabel(r.request.method)),
              PicPosTextCell(
                disposalCarriesProceeds(r.request.method)
                    ? _money0.format(r.request.disposalValue)
                    : '—',
              ),
              // ⚠️ «التحصيل» بلا معنًى لما لا ثمنَ له — وعرضُ «نقدي» على
              //    تبرّعٍ يُقرأ أنّ مالاً قُبض.
              PicPosTextCell(
                disposalCarriesProceeds(r.request.method)
                    ? disposalCollectionLabel(r.request.collectionMethod)
                    : '—',
              ),
              PicPosPillCell(
                switch (r.request.status) {
                  'approved' => 'معتمد',
                  'cancelled' => 'ملغى',
                  _ => 'مسودة',
                },
                switch (r.request.status) {
                  'approved' => _ok,
                  'cancelled' => _idle,
                  _ => _warn,
                },
              ),
            ],
          ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // الأفعال
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _confirmRunDepreciation(
    List<FixedAssetData> onBooks,
    List<AssetDepreciationData> deprs,
  ) async {
    final now = DateTime.now();
    final period = DateTime(now.year, now.month, 1);
    final periodLabel = _monthLabel(period);

    final postedAssetIds = {
      for (final d in deprs)
        if (DateTime(d.periodDate.year, d.periodDate.month, 1) == period)
          d.assetId,
    };
    final pending = onBooks
        .where((a) =>
            !postedAssetIds.contains(a.id) && _monthlyDepreciation(a) > 0)
        .toList();
    final amount =
        pending.fold<double>(0, (s, a) => s + _monthlyDepreciation(a));

    if (pending.isEmpty) {
      // ⚠️ الـDAO يتخطّى الأصلَ الذي له صفٌّ في الفترة، فالنداءُ يعيد صفراً
      //    بلا أثر. وقولُ ذلك قبلَه أصدقُ من رسالة نجاحٍ لا شيءَ خلفها.
      _toast('لا أصولَ تنتظر إهلاكَ $periodLabel — كلُّها مُرحَّلة');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(PhosphorIconsBold.arrowDownRight, color: _warn),
        title: Text('ترحيل إهلاك $periodLabel'),
        content: Text(
          'سيُقيَّد قسطُ ${_ar(pending.length)} أصلٍ بإجمالي '
          '${_money.format(amount)} — يخصم مصروفَ الإهلاك ويزيد مجمعَه. '
          'والأصولُ المُرحَّلةُ لهذا الشهر لا تُرحَّل مرّتين.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ترحيل')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final count = await ref
          .read(fixedAssetsRepositoryProvider)
          .runMonthlyDepreciation(period);
      if (!mounted) return;
      _toast(count > 0
          ? 'رُحِّل إهلاكُ ${_ar(count)} أصلٍ لشهر $periodLabel'
          : 'لا أصولَ تحتاج إهلاكاً لهذا الشهر');
    } catch (e) {
      if (!mounted) return;
      _toast('تعذّر ترحيلُ الإهلاك: $e');
    }
  }

  /// «أصل جديد» — الفعلُ الأوّلُ في رأس التصميم (`HEADS.main.action`).
  ///
  /// ⚠️ **الحساباتُ الورقيّةُ وحدَها** في قائمة الحساب المقابل: الحسابُ
  /// الأبُ مجموعُ أبنائه، والقيدُ عليه مباشرةً يجعل مجموعَ الأبناء يخالف
  /// رصيدَ الأب — وهو خللٌ لا يُظهره ميزانُ المراجعة لأنّه متوازن.
  Future<void> _createAsset() async {
    final categories = ref.read(_categoriesProvider).value ?? const [];
    final accounts = ref.read(_accountsProvider).value ?? const [];
    final costCenters = ref.read(_costCentersProvider).value ?? const [];

    final leafIds = {for (final a in accounts) a.parentId}..remove(null);

    final form = await showFixedAssetPicposCreateDialog(
      context,
      categories: [
        for (final c in categories)
          (
            id: c.id,
            name: c.name,
            defaultUsefulLife: c.defaultUsefulLife.toDouble(),
          ),
      ],
      accounts: [
        for (final a in accounts)
          if (!leafIds.contains(a.id))
            (id: a.id, code: a.code, name: a.name),
      ],
      costCenters: [
        for (final cc in costCenters) (id: cc.id, name: cc.name),
      ],
    );
    if (form == null || !mounted) return;

    try {
      await ref.read(fixedAssetsRepositoryProvider).createFixedAsset(
            code: form.code,
            name: form.name,
            categoryId: form.categoryId,
            location: form.location,
            purchasePrice: form.purchasePrice,
            purchaseDate: form.purchaseDate,
            usefulLifeYears: form.usefulLifeYears,
            salvageValue: form.salvageValue,
            depreciationMethod: form.depreciationMethod,
            notes: form.notes,
            costCenterId: form.costCenterId,
            contraAccountId: form.contraAccountId,
          );
      if (!mounted) return;
      ref.invalidate(_assetsProvider);
      _toast('أُنشئ الأصلُ ${form.name}');
    } catch (e) {
      if (!mounted) return;
      _toast('تعذّر الإنشاء: $e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
