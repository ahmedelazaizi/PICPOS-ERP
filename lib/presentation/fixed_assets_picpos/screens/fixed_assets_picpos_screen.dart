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
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/accounting_repository.dart';
import '../../../domain/repositories/fixed_assets_repository.dart';
import '../../picpos_shell/picpos_bar_list.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_stat_tile.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/permission_guard.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _money0 = NumberFormat('#,##0', 'en');

const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _err = Color(0xFFEF4444);
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

final _accountsProvider = StreamProvider.autoDispose<List<Account>>(
    (ref) => ref.watch(accountingRepositoryProvider).watchAllAccounts());

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
double _remainingYears(FixedAssetData a) =>
    (a.usefulLifeYears * (1 - _deprRatio(a))).clamp(0.0, a.usefulLifeYears);

bool _isActive(FixedAssetData a) => a.status == 'active';

bool _isNearEnd(FixedAssetData a) =>
    _isActive(a) && _deprRatio(a) >= _nearEndThreshold;

/// قسطُ الشهر لأصلٍ واحد.
///
/// ⚠️ **منقولٌ عن `runMonthlyDepreciation` حرفاً بحرف** — راجع شرحَ الرأس.
double _monthlyDepreciation(FixedAssetData a) {
  final depreciable = _depreciableAmount(a);
  double monthly;
  if (a.depreciationMethod == 'declining_balance') {
    final rate = 2 / (a.usefulLifeYears * 12);
    monthly = _bookValue(a) * rate;
    if (a.accumulatedDepreciation + monthly > depreciable) {
      monthly = depreciable - a.accumulatedDepreciation;
    }
  } else {
    monthly = depreciable / (a.usefulLifeYears * 12);
  }
  return monthly > 0 ? monthly : 0;
}

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
  int _assetChip = 0;
  int _deprChip = 0;
  int _disposalChip = 0;

  static const _tabNotes = [
    'القيمة الدفترية = التكلفة ناقص مجمع الإهلاك',
    'القسط الشهري يُرحَّل بقيد واحد لكل فئة · الأصول المستبعدة لا تُهلك',
    'الفئة تحدد العمر الافتراضي والطريقة وحسابي الأصل والإهلاك',
    'الربح أو الخسارة = ثمن البيع ناقص القيمة الدفترية',
    'الأصل يتبع موقعاً ومركز تكلفة',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this)
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
    final locations = _locationKeys(onBooks);

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
                label: 'الفئات',
                icon: PhosphorIconsBold.folders,
                badge: '${cats.length}'
              ),
              (
                label: 'الاستبعاد والبيع',
                icon: PhosphorIconsBold.trash,
                badge: '${disposed.length}'
              ),
              (
                label: 'التوزيع والمواقع',
                icon: PhosphorIconsBold.mapPin,
                badge: '${locations.length}'
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
                _scroll(_assetsTab(all, cats)),
                _scroll(_depreciationTab(onBooks, cats, deprs, accountById)),
                _scroll(_categoriesTab(cats, all, accountById)),
                _scroll(_disposalTab(disposed)),
                _scroll(_distributionTab(onBooks)),
              ],
            ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
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
  // ١ — الأصول
  // ═════════════════════════════════════════════════════════════════════════

  Widget _assetsTab(List<FixedAssetData> all, List<AssetCategory> cats) {
    final catName = {for (final c in cats) c.id: c.name};
    final onBooks = all.where(_isActive).toList();
    final cost = all.fold<double>(0, (s, a) => s + a.purchasePrice);
    final accum = all.fold<double>(0, (s, a) => s + a.accumulatedDepreciation);
    final nearEnd = all.where(_isNearEnd).toList();

    final visible = all.where(_matches).where((a) {
      if (_assetChip == 1) return _isActive(a) && !_isNearEnd(a);
      if (_assetChip == 2) return _isNearEnd(a);
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _kpis([
          PicPosStatTile(
            label: 'الأصول النشطة',
            value: _ar(onBooks.length),
            icon: PhosphorIconsBold.package,
            accent: AppColors.primary,
            caption: 'من ${_ar(all.length)} على الدفاتر',
          ),
          PicPosStatTile(
            label: 'التكلفة التاريخية',
            value: _money0.format(cost),
            icon: PhosphorIconsBold.currencyCircleDollar,
            accent: const Color(0xFF4A80E8),
          ),
          PicPosStatTile(
            label: 'مجمع الإهلاك',
            value: _money0.format(accum),
            icon: PhosphorIconsBold.arrowDownRight,
            accent: _warn,
            caption: cost > 0 ? '${_pct(accum / cost * 100)} من التكلفة' : null,
          ),
          PicPosStatTile(
            label: 'القيمة الدفترية',
            value: _money0.format(cost - accum),
            icon: PhosphorIconsBold.scales,
            accent: _ok,
          ),
          PicPosStatTile(
            label: 'أصول قارب عمرها',
            value: _ar(nearEnd.length),
            icon: PhosphorIconsBold.hourglass,
            accent: _err,
            caption: 'تجاوز إهلاكها ${_pct(_nearEndThreshold * 100)}',
          ),
        ]),
        const SizedBox(height: 12),
        PicPosDataTable(
          title: 'بطاقات الأصول',
          subtitle: 'القيمة الدفترية تُحسب لحظياً من التكلفة ومجمع الإهلاك',
          minWidth: 1080,
          chips: [
            PicPosTableChip(
                label: 'الكل',
                count: _ar(all.length),
                onTap: () => setState(() => _assetChip = 0)),
            PicPosTableChip(
                label: 'نشط',
                count: _ar(all.where((a) => _isActive(a) && !_isNearEnd(a)).length),
                onTap: () => setState(() => _assetChip = 1)),
            PicPosTableChip(
                label: 'قارب الانتهاء',
                count: _ar(nearEnd.length),
                onTap: () => setState(() => _assetChip = 2)),
          ],
          selectedChip: _assetChip,
          columns: const [
            PicPosTableColumn('الأصل', flex: 1.6),
            PicPosTableColumn('الفئة', flex: 1.4),
            PicPosTableColumn('التكلفة',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('العمر', flex: 1.2),
            PicPosTableColumn('مجمع الإهلاك',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('الدفترية',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('نسبة الإهلاك', flex: 1.5),
            PicPosTableColumn('الحالة', flex: 1.2),
          ],
          emptyLabel: _query.isEmpty
              ? 'لا أصولَ مسجَّلةً بعد'
              : 'لا أصلَ يطابق «$_query»',
          rows: [
            for (final a in visible)
              PicPosTableRow(cells: [
                PicPosTextCell('${a.code} · ${a.name}',
                    sub: (a.location ?? '').trim().isEmpty ? null : a.location,
                    icon: PhosphorIconsBold.package,
                    tint: _isNearEnd(a) ? _warn : AppColors.primary),
                PicPosTextCell(catName[a.categoryId] ?? '—'),
                PicPosTextCell(_money0.format(a.purchasePrice)),
                PicPosTextCell(
                  '${_ar(a.usefulLifeYears.toStringAsFixed(0))} سنوات',
                  sub: 'باقي ${_ar(_remainingYears(a).toStringAsFixed(1))}',
                ),
                PicPosTextCell(_money0.format(a.accumulatedDepreciation)),
                PicPosTextCell(_money0.format(_bookValue(a)), bold: true),
                PicPosBarCell(
                  _pct(_deprRatio(a) * 100),
                  _deprRatio(a),
                  _deprRatio(a) >= _nearEndThreshold
                      ? _err
                      : _deprRatio(a) >= 0.5
                          ? _warn
                          : _ok,
                ),
                PicPosPillCell(
                  _isActive(a)
                      ? (_isNearEnd(a) ? 'قارب الانتهاء' : 'نشط')
                      : (a.status == 'sold' ? 'بيع' : 'مستبعد'),
                  _isActive(a) ? (_isNearEnd(a) ? _warn : _ok) : _idle,
                ),
              ]),
          ],
          totals: visible.isEmpty
              ? null
              : [
                  '${_ar(visible.length)} أصول',
                  '',
                  _money0.format(
                      visible.fold<double>(0, (s, a) => s + a.purchasePrice)),
                  '',
                  _money0.format(visible.fold<double>(
                      0, (s, a) => s + a.accumulatedDepreciation)),
                  _money0
                      .format(visible.fold<double>(0, (s, a) => s + _bookValue(a))),
                  '',
                  '',
                ],
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
  // ٣ — الفئات
  // ═════════════════════════════════════════════════════════════════════════

  Widget _categoriesTab(
    List<AssetCategory> cats,
    List<FixedAssetData> all,
    Map<int, String> accountById,
  ) {
    final countByCat = <int, int>{};
    for (final a in all) {
      countByCat[a.categoryId] = (countByCat[a.categoryId] ?? 0) + 1;
    }

    if (cats.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.folders,
        title: 'لا فئاتِ أصولٍ بعد',
        hint: 'الفئة تحدّد العمر الافتراضي وطريقة الإهلاك وحسابي الأصل '
            'والإهلاك — ولا يُسجَّل أصلٌ بلا فئة.',
      );
    }

    return PicPosDataTable(
      title: 'فئات الأصول',
      subtitle: 'الفئة تحدد العمر الافتراضي والطريقة وحسابي الأصل والإهلاك',
      minWidth: 980,
      columns: const [
        PicPosTableColumn('الفئة', flex: 1.7),
        PicPosTableColumn('العمر الافتراضي', flex: 1.2),
        PicPosTableColumn('طريقة الإهلاك', flex: 1.5),
        PicPosTableColumn('الأصول', align: PicPosCellAlign.end),
        PicPosTableColumn('حساب الأصل', flex: 1.5),
        PicPosTableColumn('حساب الإهلاك', flex: 1.5),
      ],
      rows: [
        for (final c in cats)
          PicPosTableRow(cells: [
            PicPosTextCell(c.name,
                icon: PhosphorIconsBold.folders,
                sub: (countByCat[c.id] ?? 0) == 0
                    ? 'بلا أصول على الدفاتر'
                    : null,
                tint: (countByCat[c.id] ?? 0) == 0 ? _idle : AppColors.primary),
            PicPosTextCell(
                '${_ar(c.defaultUsefulLife.toStringAsFixed(0))} سنوات'),
            PicPosPillCell(
              _methodLabel(c.defaultDepreciationMethod),
              c.defaultDepreciationMethod == 'declining_balance'
                  ? _purple
                  : AppColors.primary,
            ),
            PicPosTextCell(_ar(countByCat[c.id] ?? 0)),
            PicPosTextCell(accountById[c.accountId] ?? '— غير مربوط',
                tint: c.accountId == null ? _err : null),
            PicPosTextCell(
                accountById[c.depreciationAccountId] ?? '— غير مربوط',
                tint: c.depreciationAccountId == null ? _err : null),
          ]),
      ],
      totals: [
        '${_ar(cats.length)} فئات',
        '',
        '',
        _ar(all.length),
        '',
        '',
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ٤ — الاستبعاد والبيع
  // ═════════════════════════════════════════════════════════════════════════

  Widget _disposalTab(List<FixedAssetData> disposed) {
    if (disposed.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.trash,
        title: 'لا أصولَ مستبعدةً أو مباعة',
        hint: 'عند الاستبعاد يُقفَل مجمعُ الإهلاك ويُقيَّد الفرقُ بين ثمن '
            'البيع والقيمة الدفترية ربحاً أو خسارة.',
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
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ٥ — التوزيع والمواقع
  // ═════════════════════════════════════════════════════════════════════════

  Widget _distributionTab(List<FixedAssetData> onBooks) {
    if (onBooks.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.mapPin,
        title: 'لا أصولَ نشطةً لتوزَّع',
        hint: 'الأصل يتبع موقعاً ومركزَ تكلفة — ويُستعمل ذلك في توزيع '
            'الإهلاك على مراكز التكلفة.',
      );
    }

    final byLocation = <String, List<FixedAssetData>>{};
    for (final a in onBooks) {
      final key =
          (a.location ?? '').trim().isEmpty ? 'بلا موقع' : a.location!.trim();
      byLocation.putIfAbsent(key, () => []).add(a);
    }

    final entries = byLocation.entries.toList()
      ..sort((x, y) => _sumBook(y.value).compareTo(_sumBook(x.value)));

    final totalBook = onBooks.fold<double>(0, (s, a) => s + _bookValue(a));
    final totalCost = onBooks.fold<double>(0, (s, a) => s + a.purchasePrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosContentCard(
          child: PicPosBarList(
            title: 'القيمة الدفترية حسب الموقع',
            subtitle: 'الأصل يتبع موقعاً ومركز تكلفة · ج.م',
            emptyHint: 'لا مواقعَ مسجَّلة',
            items: [
              for (final e in entries)
                PicPosBarItem(
                  label: e.key,
                  sub: '${_ar(e.value.length)} أصول',
                  value: _sumBook(e.value),
                  display: _money0.format(_sumBook(e.value)),
                  caption: totalBook > 0
                      ? '${_pct(_sumBook(e.value) / totalBook * 100)} من الدفترية'
                      : '',
                  icon: PhosphorIconsBold.storefront,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PicPosDataTable(
          title: 'الأصول حسب الموقع',
          subtitle: 'يُستخدم في توزيع الإهلاك على مراكز التكلفة',
          minWidth: 820,
          columns: const [
            PicPosTableColumn('الموقع', flex: 1.6),
            PicPosTableColumn('الأصول', align: PicPosCellAlign.end),
            PicPosTableColumn('التكلفة',
                flex: 1.3, align: PicPosCellAlign.end),
            PicPosTableColumn('الدفترية',
                flex: 1.3, align: PicPosCellAlign.end),
            PicPosTableColumn('نسبة الاستهلاك', flex: 1.4),
          ],
          rows: [
            for (final e in entries)
              () {
                final cost = e.value.fold<double>(0, (s, a) => s + a.purchasePrice);
                final accum = e.value
                    .fold<double>(0, (s, a) => s + a.accumulatedDepreciation);
                final ratio = cost > 0 ? (accum / cost).clamp(0.0, 1.0) : 0.0;
                return PicPosTableRow(cells: [
                  PicPosTextCell(e.key,
                      icon: PhosphorIconsBold.storefront,
                      tint: AppColors.primary),
                  PicPosTextCell(_ar(e.value.length)),
                  PicPosTextCell(_money0.format(cost)),
                  PicPosTextCell(_money0.format(cost - accum), bold: true),
                  PicPosBarCell(
                    _pct(ratio * 100),
                    ratio,
                    ratio >= _nearEndThreshold
                        ? _err
                        : ratio >= 0.5
                            ? _warn
                            : _ok,
                  ),
                ]);
              }(),
          ],
          totals: [
            '${_ar(entries.length)} مواقع',
            _ar(onBooks.length),
            _money0.format(totalCost),
            _money0.format(totalBook),
            '',
          ],
        ),
      ],
    );
  }

  double _sumBook(List<FixedAssetData> list) =>
      list.fold<double>(0, (s, a) => s + _bookValue(a));

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

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
