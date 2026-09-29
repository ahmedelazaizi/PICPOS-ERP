import 'package:ural_erp/core/i18n/tr.dart';
// ---------------------------------------------------------------------------
// منطق منسوخ من reports_screen.dart (monolith) — أي إصلاح منطقي يتصلّح في
// المصدر أولاً ثم يُنقل بـ patch لهذا الملف (مصيدة النسخ §٥.٨). لا يُنسخ أبداً
// من D:\URAL-ERP.
//
// الشاشة الأصل (lib/presentation/screens/reports_screen.dart) مونوليث 1871
// سطر بلا `part` — مُطلِق تنقّل (شبكة فئات) لِـ ~25 شاشة تقرير وجهة. الفورك
// هنا ينسخ منطق الحالة كاملاً حرفياً بلا أي تعديل منطقي: خرائط الفئات
// والمدخلات والاختصارات (`_buildCategories`)، البحث، المفضّلة/آخر ما فُتح
// (SharedPreferences: `reports_favorites` / `reports_recent`)، الأكورديون
// المضمّن (`_expandedPanel`)، وحوارات التقارير المضمّنة (منخفض المخزون،
// منتهي/قارب على الانتهاء، تسوية الذمم، تسوية المخزون). يتغيّر بس اسم الكلاس
// وطبقة العرض الخارجية (PicPosScreenScaffold + PicPosContentCard بدل
// Scaffold يدوي وهيدر مخصص). شاشات الوجهة (٢٥ شاشة) تُستورد كما هي بلا أي
// تعديل وتأخذ شكلها من الثيم.
//
// FULL PARITY مع الأصل — كل الفئات موجودة بلا حذف: تقارير المبيعات، تقارير
// الأرباح، تقارير المرتجعات، تقارير المخزون، تقارير المشتريات، تقارير
// العملاء، تقارير الموردين، الصناديق والكاش (شامل مدخل تقرير الورديات
// `cb_shifts` → ShiftsReportScreen، مع اختصاري «فتح وإغلاق الصندوق» و«العجز
// والزيادة» — مطلوب owner لِمهمة ١١ لضمان تغطية شاشة إغلاق الوردية/مهمة ١٠)،
// تقارير المستخدمين (المدخل `u_perms` بيروح لِـ UsersManagementPicposScreen —
// فورك مهمة ١٤، بيعيد استخدام allUsersProvider وبقية مزوّدات UralCash)، تقارير
// الفروع، تقارير الضرائب، الحركة والسجلات، التحليلات والإحصائيات.
//
// راجع lib/presentation/screens/reports_screen.dart (الأصل).
// ---------------------------------------------------------------------------

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/e_invoicing_providers.dart';
import '../../../data/providers/providers.dart';
import '../../../data/providers/report_providers.dart';
import '../../../data/providers/reports_hub_kpi_provider.dart';
import '../../../data/providers/reconciliation_provider.dart';
import '../../widgets/permission_guard.dart';
import '../../providers/pending_picpos_report.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';

// Destination screens — existing in the codebase, unchanged by this fork.
import '../../activity_log_picpos/screens/activity_log_picpos_screen.dart';
import 'report_definitions_picpos.dart';
import 'report_view_picpos_screen.dart';
import '../../screens/branch_performance_screen.dart';
import '../../screens/e_invoice_dashboard_screen.dart';
// مدخلا «كشف حساب العميل» و«كشف حساب المورد» في مركز التقارير يفتحان نسخةَ
// PicPos ذاتَ التبويبات الخمس — وهما موضعان ممّا فات جردَ التسليم (ظنَّها
// ثلاثةً في `parties_picpos` وحدَها).
import '../../party_statement_picpos/screens/party_statement_picpos_screen.dart';
import '../../screens/purchase_orders_screen.dart';
import '../../screens/report_builder_screen.dart';
import 'ar_aging_report_picpos_screen.dart';
import '../../screens/reports/category_profit_report_screen.dart';
import '../../screens/reports/consumption_report_screen.dart';
import '../../screens/reports/delivery_report_screen.dart';
import '../../screens/reports/expenses_report_screen.dart';
import '../../../core/config/brand.dart';
import '../../accounting_picpos/financial_statements_picpos_screen.dart';
import '../../screens/reports/financial_statements_screen.dart';
import '../../screens/reports/inventory_report_screen.dart';
import '../../screens/reports/purchase_returns_report_screen.dart';
import '../../screens/reports/purchases_report_screen.dart';
import '../../screens/reports/sales_by_classification_report.dart';
import '../../screens/reports/sales_report_screen.dart';
import '../../screens/reports/sales_returns_report_screen.dart';
import '../../screens/reports/shifts_report_screen.dart';
import '../../screens/reports/tables_report_screen.dart';
import '../../screens/reports/tax_report_screen.dart';
import '../../screens/reports/top_products_report_screen.dart';
import '../../screens/reports/treasury_report_screen.dart';
import '../../screens/reports/vat_reconciliation_screen.dart';
import '../../screens/stock_audit_screen.dart';
import '../../screens/stock_movements_screen.dart';
import '../../users_picpos/screens/users_management_picpos_screen.dart';

// ---------------------------------------------------------------------------
const String _kPrefFavoritesKey = 'reports_favorites';
const String _kPrefRecentKey = 'reports_recent';
const int _kRecentCap = 6;

// ---------------------------------------------------------------------------
/// مُطلِق التقارير بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام منطق `reports_screen.dart` بالكامل
/// (فئات/مدخلات/اختصارات، بحث، مفضّلة/آخر ما فُتح) — فقط طبقة العرض الخارجية
/// تبدّلت لـ picpos_shell (هيدر PicPosScreenScaffold + PicPosContentCard حول
/// الشبكة بدل Scaffold يدوي).
class ReportsPicposScreen extends ConsumerStatefulWidget {
  const ReportsPicposScreen({super.key});

  @override
  ConsumerState<ReportsPicposScreen> createState() =>
      _ReportsPicposScreenState();
}

class _ReportsPicposScreenState extends ConsumerState<ReportsPicposScreen> {
  // -----------------------------------------------------------------------
  // State
  // -----------------------------------------------------------------------
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  Set<String> _favorites = <String>{};
  List<String> _recent = <String>[];

  // Accordion state — id of the currently expanded category, or null.
  String? _expandedCatId;

  late final List<_FlatItem> _allItems = _flatten(_categories);

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadPrefs();

    // طلبٌ كُتب **قبل** بناء الشاشة — النقرُ من الشريط وهي غيرُ معروضة.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
    // وطلبٌ يصل والشاشةُ معروضةٌ أصلاً: `onNavigate` إلى نفس الفهرس لا
    // يُعيد التركيبَ، فلا `initState` ثانٍ يقرأه.
    pendingPicposReport.addListener(_consumePending);
  }

  @override
  void dispose() {
    pendingPicposReport.removeListener(_consumePending);
    _searchCtrl.dispose();
    super.dispose();
  }

  /// تنفيذُ طلبِ الشريط الجانبيّ — فتحُ الفئة، ثمّ التقريرِ إن سُمّي.
  ///
  /// ⚠️ **ويمرّ بـ[ensurePermission] لا بـ`action()` مباشرةً.** بطاقاتُ
  /// التقارير في هذه الشاشة ملفوفةٌ بـ`PermissionGuard` مع تجاوزِ المسؤول،
  /// فنقرةٌ من الشريط تتخطّاه كانت تفتح تقريراً محجوباً بلا كلمةِ مرورٍ ولا
  /// أثرٍ في السجلّ. و`ensurePermission` هي عينُ ما يفعله الحارسُ: استهلاكُ
  /// موافقةٍ سابقة، ثمّ المِلكُ، ثمّ سؤالُ المسؤول.
  Future<void> _consumePending() async {
    final req = pendingPicposReport.take();
    if (req == null || !mounted) return;

    PicposReportCategory? cat;
    for (final c in _categories) {
      if (c.id == req.categoryId) cat = c;
    }
    if (cat == null) return;

    setState(() => _expandedCatId = cat!.id);
    if (req.reportId == null) return;

    PicposReportEntry? entry;
    for (final e in cat.mainReports) {
      if (e.id == req.reportId) entry = e;
    }
    if (entry == null) return;

    final permission = entry.permission;
    if (permission != null) {
      final granted = await ensurePermission(
        ref,
        context,
        permission,
        actionName: entry.title,
      );
      if (!granted || !mounted) return;
    }
    _registerOpen(entry.id);
    entry.action();
  }

  // ignore: unused_element
  void _toggleAccordion(PicposReportCategory cat) {
    setState(() {
      _expandedCatId = _expandedCatId == cat.id ? null : cat.id;
    });
  }

  // -----------------------------------------------------------------------
  // Persistence (منسوخ من contracts/persistence-contract.md الأصلي)
  // -----------------------------------------------------------------------
  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawFavs = prefs.getStringList(_kPrefFavoritesKey) ?? const [];
    final rawRecent = prefs.getStringList(_kPrefRecentKey) ?? const [];
    final known = {for (final i in _allItems) i.id};
    final favs = rawFavs.where(known.contains).toSet();
    final recent = rawRecent.where(known.contains).toList();
    if (!mounted) return;
    setState(() {
      _favorites = favs;
      _recent = recent;
    });
    if (favs.length != rawFavs.length) {
      await prefs.setStringList(_kPrefFavoritesKey, favs.toList());
    }
    if (recent.length != rawRecent.length) {
      await prefs.setStringList(_kPrefRecentKey, recent);
    }
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefFavoritesKey, _favorites.toList());
  }

  Future<void> _saveRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefRecentKey, _recent);
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (_favorites.contains(id)) {
        _favorites.remove(id);
      } else {
        _favorites.add(id);
      }
    });
    _saveFavorites();
  }

  void _registerOpen(String id) {
    setState(() {
      _recent.remove(id);
      _recent.insert(0, id);
      if (_recent.length > _kRecentCap) {
        _recent.removeRange(_kRecentCap, _recent.length);
      }
    });
    _saveRecent();
  }

  // -----------------------------------------------------------------------
  // Category catalog (منسوخ حرفياً من contracts/destination-mapping.md
  // الأصلي — لا يُحذف أي تقرير).
  // -----------------------------------------------------------------------
  late final List<PicposReportCategory> _categories = buildPicposReportCatalog(
    actions: PicposReportActions(
      open: _pushReport,
      showLowStock: _showLowStockReport,
      showExpired: _showExpiredProductsReport,
      showExpiring: _showExpiringProductsReport,
      showArReconciliation: _showArReconciliation,
      showInventoryGlReconciliation: _showInventoryGlReconciliation,
    ),
    eInvoicePlatform: ref.read(activeEInvoicePlatformProvider).value,
  );

  /// فتحُ شاشةِ تقريرٍ — الرابطُ الوحيدُ بين الكتالوج وشجرة الودجت.
  void _pushReport(Widget Function() builder) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => builder()),
    );
  }

  // -----------------------------------------------------------------------
  // Build — طبقة العرض الوحيدة اللي اتغيّرت عن الأصل: PicPosScreenScaffold
  // (هيدر «التقارير» / «كل تقارير المبيعات والمخزون والمالية») بدل
  // Scaffold + _header() يدوي، وPicPosContentCard حول شبكة الفئات/نتائج
  // البحث. باقي التركيب (بحث، مفضّلة، آخر ما فُتح، الأكورديون) كما هو.
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isSearching = _query.trim().isNotEmpty;
    final results = isSearching
        ? _allItems
            .where((i) =>
                i.title.contains(_query) || i.subtitle.contains(_query))
            .toList()
        : const <_FlatItem>[];

    // الفئةُ المعروضةُ في لوحة التفصيل — أوّلُ فئةٍ ما لم يُختَر غيرُها.
    final selected = _categories.firstWhere(
      (c) => c.id == _expandedCatId,
      orElse: () => _categories.first,
    );

    return PicPosScreenScaffold(
      title: tr('التقارير'),
      // ⚠️ العددُ **مقيسٌ من الشجرة** لا مكتوبٌ نصّاً: «كل تقارير المبيعات
      //    والمخزون والمالية» جملةٌ لا تتغيّر مهما أُضيف أو حُذف.
      subtitle: '${_allItems.length} تقريراً واختصاراً '
          'في ${_categories.length} فئة',
      icon: PhosphorIconsBold.chartBar,
      headerSearch: _searchBar(),
      headerActions: [_customReportButton()],
      // ⚠️ بلا حشو: الشريطُ الجانبيُّ يلتصق بالحافّة وله حدُّه الخاصّ، كما
      //    في التصميم — وحشوُ الإطار كان يجعله بطاقةً عائمةً لا عموداً.
      bodyPadding: EdgeInsets.zero,
      body: LayoutBuilder(
        builder: (context, c) {
          if (isSearching) {
            return SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(26, 18, 26, 26),
              child:
                  _searchResultsSection(results, _reportColumnsFor(c.maxWidth)),
            );
          }
          // الشريطُ ٣١٨ في التصميم، ويضيق على الشاشات الصغيرة بدل أن يبتلع
          // نصفَ العرض.
          final railWidth = c.maxWidth < 900 ? 250.0 : 318.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: railWidth, child: _categoryRail()),
              Expanded(
                child: _detailPane(
                  selected,
                  _detailColumnsFor(c.maxWidth - railWidth),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// أعمدةُ بطاقات التقارير — ثلاثةٌ في التصميم على العرض الكامل.
  int _detailColumnsFor(double w) {
    if (w >= 1150) return 3;
    if (w >= 760) return 2;
    return 1;
  }

  /// «تقرير مخصص» — يفتح مُنشئَ التقارير القائم.
  ///
  /// ⚠️ زرٌّ في التصميم ولم يكن في الشاشة، و`ReportBuilderScreen` **موجودةٌ
  /// فعلاً** ويصل إليها المستخدمُ من مكانٍ آخر — فهذا كشفُ ما هو قائمٌ لا
  /// وعدٌ بما ليس كذلك.
  Widget _customReportButton() {
    return ElevatedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ReportBuilderScreen(),
        ),
      ),
      icon: const Icon(PhosphorIconsBold.plus, size: 17),
      label:  Text(tr('تقرير مخصص')),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  int _reportColumnsFor(double w) {
    if (w >= 1500) return 5;
    if (w >= 1200) return 4;
    if (w >= 900) return 3;
    if (w >= 640) return 2;
    return 1;
  }

  Widget _searchBar() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: tr('بحث في جميع التقارير...'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Reusable mini-pieces
  // -----------------------------------------------------------------------
  Widget _miniHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            )),
      ],
    );
  }

  /// Resolves a flat item back to a real entry/shortcut and invokes its action
  /// while recording the open. Used by chip taps (favorites, recents, and
  /// search results).
  void _openFlatItem(_FlatItem item) {
    _registerOpen(item.id);
    if (item.isShortcut) {
      final cat = item.category;
      final shortcut =
          cat.shortcuts.firstWhere((s) => s.id == item.id);
      final parent = cat.mainReports.firstWhere(
        (r) => r.id == shortcut.parentReportId,
        orElse: () => cat.mainReports.first,
      );
      // Honour the shortcut's own destination here too — otherwise finding
      // «حسب المجموعة» through search would land somewhere different from
      // clicking the same chip in the category card.
      (shortcut.action ?? parent.action)();
    } else {
      final entry = item.category.mainReports.firstWhere(
        (r) => r.id == item.id,
        orElse: () => item.category.mainReports.first,
      );
      entry.action();
    }
  }

  // -----------------------------------------------------------------------
  // الشريطُ الجانبيُّ للفئات — عمودُ ٣١٨ في التصميم.
  //
  // ⚠️ **الفئاتُ مجمَّعةٌ لا مسطَّحة.** التصميمُ يرتّبها في خمس مجموعات، وثلاثَ
  //    عشرةَ بطاقةً في شبكةٍ واحدةٍ بلا تجميعٍ تُقرأ قائمةً لا بنية. والمجموعةُ
  //    تُقرأ من [_kCatGroup]، وحارسٌ يمنع أن تُضاف فئةٌ بلا مجموعةٍ فتسقط
  //    صامتةً خارجَ الشريط.
  // -----------------------------------------------------------------------
  Widget _categoryRail() {
    final byGroup = <String, List<PicposReportCategory>>{};
    for (final c in _categories) {
      byGroup.putIfAbsent(_kCatGroup[c.id] ?? _kGroupOrder.last, () => [])
          .add(c);
    }
    final side = BorderSide(color: context.picposHairline);
    final rtl = Directionality.of(context) == ui.TextDirection.rtl;
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        // الحدُّ على الحافّة المواجهة للمحتوى — يسارٌ في RTL.
        border: rtl ? Border(left: side) : Border(right: side),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 16),
              children: [
                for (final g in _kGroupOrder)
                  if ((byGroup[g] ?? const []).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 6),
                      child: Text(
                        g,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                          color: context.picposMuted,
                        ),
                      ),
                    ),
                    for (final c in byGroup[g]!) _railItem(c),
                  ],
              ],
            ),
          ),
          _railFooter(),
        ],
      ),
    );
  }

  Widget _railItem(PicposReportCategory cat) {
    final on = cat.id == _expandedCatId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => setState(() => _expandedCatId = cat.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color:
                  on ? cat.color.withValues(alpha: 0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: on ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(cat.icon, size: 17, color: cat.color),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: on ? FontWeight.w800 : FontWeight.w700,
                          color: on ? cat.color : context.picposText,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _catMeta(cat),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: context.picposMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${cat.mainReports.length}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: on ? cat.color : context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// «٣ تقارير · ٨ اختصارات» — **مقيسٌ من الفئة** لا مكتوبٌ بيد.
  String _catMeta(PicposReportCategory c) {
    final r = tr('{p0} تقرير', {'p0': c.mainReports.length});
    return c.shortcuts.isEmpty ? r : tr('{r} · {p0} اختصار', {'r': r, 'p0': c.shortcuts.length});
  }

  /// تذييلُ الشريط.
  ///
  /// ⚠️ التصميمُ يكتب هنا «آخر مزامنة 14:32 · ٣ فروع»، ولا مقياسَ لوقت
  /// المزامنة في هذه الشاشة — فما يُكتب هو ما يُعَدّ فعلاً: عددُ ما في
  /// الشاشة، وأنّ كلَّ تقريرٍ يُحسَب لحظةَ فتحه (وهو ما تفعله الشاشاتُ فعلاً).
  Widget _railFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsBold.clockCounterClockwise,
              size: 17, color: context.picposMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_allItems.length} تقريراً واختصاراً '
                  'في ${_categories.length} فئة',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.picposText,
                  ),
                ),
                Text(
                  tr('كلُّ تقريرٍ يُحسَب لحظةَ فتحه'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // لوحةُ التفصيل — الفئةُ المختارةُ وحدَها، كما في التصميم.
  // -----------------------------------------------------------------------
  Widget _detailPane(PicposReportCategory cat, int cols) {
    final pinned = _pinnedItems();
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(26, 22, 26, 30),
      children: [
        _kpiRow(cols),
        const SizedBox(height: 18),
        if (pinned.isNotEmpty) ...[
          _pinnedCard(pinned),
          const SizedBox(height: 18),
        ],
        _detailHeader(cat),
        const SizedBox(height: 14),
        _detailReports(cat, cols),
        if (cat.shortcuts.isNotEmpty) ...[
          const SizedBox(height: 14),
          _shortcutsBar(cat),
        ],
      ],
    );
  }

  // -----------------------------------------------------------------------
  // صفُّ المؤشّرات — أربعُ بطاقاتٍ في صدر التصميم.
  //
  // ⚠️ **الأرقامُ من قائمة الدخل لا من عدّادٍ في الشاشة**، ومحصورةٌ بصلاحية
  //    فروع المستخدم داخلَ الاستعلام نفسِه.
  //
  // ⚠️ **والنسبةُ تختفي حين لا أساسَ لها.** التصميمُ يرسم «١٢٪ ▲» دائماً،
  //    ويومُ أمسٍ بلا حركةٍ يجعلها قسمةً على صفر — و«٠٪» تُقرأ «لم يتغيّر»
  //    بينما الحقيقةُ «لا مقارنة». فيُحذَف السهمُ كلُّه لا يُكتَب صفر.
  // -----------------------------------------------------------------------
  Widget _kpiRow(int cols) {
    final async = ref.watch(reportsHubKpiProvider);
    return async.when(
      loading: () => _kpiSkeleton(cols),
      // ⚠️ لا تُبتلَع: مؤشّرٌ فارغٌ بلا سبب يُقرأ «صفرُ مبيعات».
      error: (e, _) => PicPosDialogBanner(
        icon: PhosphorIconsBold.warningCircle,
        color: AppColors.warning,
        text: tr('تعذّر حسابُ مؤشّرات اليوم: {e}', {'e': e}),
      ),
      data: (k) {
        final cards = <Widget>[
          _kpiCard(PhosphorIconsBold.currencyCircleDollar, tr('مبيعات اليوم'),
              _money(k.revenue.today), tr('ج.م'), k.revenue, AppColors.success),
          _kpiCard(PhosphorIconsBold.trendUp, tr('صافي الربح'),
              _money(k.netProfit.today), tr('ج.م'), k.netProfit, AppColors.primary),
          _kpiCard(PhosphorIconsBold.receipt, tr('عدد الفواتير'),
              k.invoices.today.toStringAsFixed(0), tr('فاتورة'), k.invoices,
              AppColors.info),
          _kpiCard(PhosphorIconsBold.arrowUUpLeft, tr('المرتجعات'),
              _money(k.salesReturns.today), tr('ج.م'), k.salesReturns,
              AppColors.error,
              upIsGood: false),
        ];
        return _kpiGrid(cards, cols);
      },
    );
  }

  /// أربعةُ أعمدةٍ في التصميم، وتنكسر مع ضيق لوحة التفصيل.
  Widget _kpiGrid(List<Widget> cards, int cols) {
    final n = cols >= 3 ? 4 : (cols == 2 ? 2 : 1);
    final rows = <List<Widget>>[];
    for (var i = 0; i < cards.length; i += n) {
      rows.add(cards.skip(i).take(n).toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(
                    child: i < rows[r].length
                        ? rows[r][i]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _kpiSkeleton(int cols) => _kpiGrid(
        [
          for (var i = 0; i < 4; i++)
            Container(
              height: 86,
              decoration: BoxDecoration(
                color: context.picposCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.picposHairline),
              ),
            ),
        ],
        cols,
      );

  String _money(double v) =>
      NumberFormat('#,##0', 'en').format(v.roundToDouble());

  Widget _kpiCard(
    IconData icon,
    String label,
    String value,
    String unit,
    ReportsKpiValue pair,
    Color tint, {
    bool upIsGood = true,
  }) {
    final delta = ReportsHubKpi.deltaPercent(pair);
    final up = (delta ?? 0) >= 0;
    final good = up == upIsGood;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(17, 15, 17, 15),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.picposMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: context.picposText,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.picposMuted,
                ),
              ),
              if (delta != null) ...[
                const Spacer(),
                Icon(
                  up ? PhosphorIconsBold.trendUp : PhosphorIconsBold.trendDown,
                  size: 13,
                  color: good ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 4),
                Text(
                  tr('{p0}٪', {'p0': delta.abs().toStringAsFixed(0)}),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: good ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailHeader(PicposReportCategory cat) {
    final desc = _kCatDesc[cat.id];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: cat.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(cat.icon, size: 25, color: cat.color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                cat.title,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: context.picposText,
                ),
              ),
              if (desc != null) ...[
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailReports(PicposReportCategory cat, int cols) {
    final rows = <List<PicposReportEntry>>[];
    for (var i = 0; i < cat.mainReports.length; i += cols) {
      rows.add(cat.mainReports.skip(i).take(cols).toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 13),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) const SizedBox(width: 13),
                  Expanded(
                    child: i < rows[r].length
                        ? _detailReportCard(cat, rows[r][i])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// بطاقةُ تقريرٍ كما في التصميم.
  ///
  /// ⚠️ **الشرائحُ السفليّةُ اختصاراتُ التقرير الحقيقيّة** لا «تبويبات»:
  /// التصميمُ يرسم `tabs` لكلّ بطاقةٍ، ولا حقلَ تبويباتٍ في `PicposReportEntry`
  /// — فكتابتُها كانت ستكون اختراعاً. والاختصاراتُ التي أبوها هذا التقرير
  /// بيانٌ قائمٌ يعطي نفسَ الشكل ويصدُق.
  Widget _detailReportCard(PicposReportCategory cat, PicposReportEntry r) {
    final isFav = _favorites.contains(r.id);
    final tags = cat.shortcuts.where((s) => s.parentReportId == r.id).toList();
    final shown = tags.take(3).toList();
    final rest = tags.length - shown.length;

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _registerOpen(r.id);
          r.action();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.picposCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.picposHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(cat.icon, size: 19, color: cat.color),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          r.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                            color: context.picposText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          r.subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                            color: context.picposMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _toggleFavorite(r.id),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          isFav
                              ? PhosphorIconsFill.star
                              : PhosphorIconsBold.star,
                          size: 15,
                          color:
                              isFav ? AppColors.warning : context.picposMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (shown.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.only(top: 11),
                  decoration: BoxDecoration(
                    border:
                        Border(top: BorderSide(color: context.picposHairline)),
                  ),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final s in shown)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: context.picposField,
                            borderRadius: BorderRadius.circular(7),
                            border:
                                Border.all(color: context.picposHairline),
                          ),
                          child: Text(
                            s.title,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: context.picposMuted,
                            ),
                          ),
                        ),
                      if (rest > 0)
                        Text(
                          '+$rest',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: context.picposBrandInk,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (r.permission != null) {
      return PermissionGuard(
        permission: r.permission!,
        allowManagerOverride: r.allowManagerOverride,
        actionName: r.title,
        child: card,
      );
    }
    return card;
  }

  Widget _shortcutsBar(PicposReportCategory cat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.picposHairline),
      ),
      child: Wrap(
        spacing: 11,
        runSpacing: 11,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            tr('اختصارات سريعة'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: context.picposMuted,
            ),
          ),
          for (final s in cat.shortcuts) _expandedShortcutChip(cat, s),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // «المفضّلة وآخر ما فُتح» — بطاقةٌ واحدةٌ ببلاطات، لا سطرا رقائقَ منفصلان.
  // -----------------------------------------------------------------------

  /// المفضّلةُ أوّلاً ثمّ آخرُ ما فُتح بلا تكرار، بحدٍّ أعلى ستّ بلاطاتٍ كما
  /// في التصميم (`repeat(6,1fr)`).
  List<({_FlatItem item, bool fav})> _pinnedItems() {
    final out = <({_FlatItem item, bool fav})>[];
    final seen = <String>{};
    void add(String id, bool fav) {
      if (!seen.add(id) || out.length >= 6) return;
      for (final i in _allItems) {
        if (i.id == id) {
          out.add((item: i, fav: fav));
          return;
        }
      }
      seen.remove(id);
    }

    for (final id in _favorites) {
      add(id, true);
    }
    for (final id in _recent) {
      add(id, false);
    }
    return out;
  }

  Widget _pinnedCard(List<({_FlatItem item, bool fav})> pinned) {
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.picposHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: context.picposHairline)),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.star,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    tr('المفضّلة وآخر ما فُتح'),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: context.picposText,
                    ),
                  ),
                ),
                Text(
                  tr('تُحفظ لكل مستخدم على حدة'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 18, 18),
            child: Wrap(
              spacing: 11,
              runSpacing: 11,
              children: [
                for (final p in pinned) _pinnedTile(p.item, p.fav),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pinnedTile(_FlatItem item, bool fav) {
    return SizedBox(
      width: 190,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openFlatItem(item),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: context.picposField,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.picposHairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(item.category.icon,
                        size: 17, color: item.category.color),
                    const Spacer(),
                    Icon(
                      fav
                          ? PhosphorIconsFill.star
                          : PhosphorIconsBold.clockCounterClockwise,
                      size: 13,
                      color: fav ? AppColors.warning : context.picposMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                    color: context.picposText,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  // ⚠️ التصميمُ يكتب «مفضّل · فُتح 14:20»، ولا وقتَ فتحٍ
                  //    مخزَّناً — المحفوظُ ترتيبٌ لا طابعُ وقت. فيُكتب ما
                  //    يُعرَف: أمفضّلٌ هو أم مفتوحٌ مؤخّراً، واسمُ فئته.
                  fav ? tr('مفضّل · {p0}', {'p0': item.category.title})
                      : tr('فُتح مؤخّراً · {p0}', {'p0': item.category.title}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _expandedShortcutChip(PicposReportCategory cat, PicposReportShortcut s) {
    final parent = cat.mainReports.firstWhere(
      (r) => r.id == s.parentReportId,
      orElse: () => cat.mainReports.first,
    );
    final chip = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        _registerOpen(s.id);
        (s.action ?? parent.action)();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cat.color.withValues(alpha: 0.07),
          border: Border.all(color: cat.color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.lightning, size: 11, color: cat.color),
            const SizedBox(width: 5),
            Text(s.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cat.color,
                )),
          ],
        ),
      ),
    );

    // Shortcut inherits parent's permission (FR-026).
    if (parent.permission != null) {
      return PermissionGuard(
        permission: parent.permission!,
        allowManagerOverride: parent.allowManagerOverride,
        actionName: s.title,
        child: chip,
      );
    }
    return chip;
  }

  // -----------------------------------------------------------------------
  // Search results — مُغلّفة بـ PicPosContentCard (هوية PicPos).
  // -----------------------------------------------------------------------
  Widget _searchResultsSection(List<_FlatItem> results, int cols) {
    if (results.isEmpty) {
      return PicPosContentCard(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            children: [
              Icon(PhosphorIconsBold.magnifyingGlass,
                  size: 56,
                  color: AppColors.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(tr('لا توجد تقارير مطابقة لـ "{_query}"', {'_query': _query}),
                  style: const TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
      );
    }
    return PicPosContentCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniHeader(PhosphorIconsBold.magnifyingGlass,
              tr('نتائج البحث ({p0})', {'p0': results.length}), AppColors.primary),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: results.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 3.6,
            ),
            itemBuilder: (_, i) => _flatResultCard(results[i]),
          ),
        ],
      ),
    );
  }

  Widget _flatResultCard(_FlatItem item) {
    final isFav = !item.isShortcut && _favorites.contains(item.id);
    return _HoverCard(
      onTap: () => _openFlatItem(item),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 10, 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.category.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.category.icon,
                  color: item.category.color, size: 17),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            )),
                      ),
                      if (item.isShortcut) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child:  Text(tr('اختصار'),
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.warningDark,
                              )),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.25,
                      )),
                ],
              ),
            ),
            if (!item.isShortcut)
              IconButton(
                tooltip: isFav ? tr('إزالة من المفضلة') : tr('إضافة للمفضلة'),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 22, height: 22),
                icon: Icon(
                  isFav ? PhosphorIconsFill.star : PhosphorIconsBold.star,
                  size: 13,
                  color: isFav ? AppColors.warning : AppColors.textMuted,
                ),
                onPressed: () => _toggleFavorite(item.id),
              ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Inline dialog reports (منسوخ حرفياً من legacy launcher الأصلي — بحاجة
  // Directionality خاصة بيها لأنها showDialog منفصل عن شجرة PicPosScreenScaffold).
  // -----------------------------------------------------------------------
  Future<void> _showLowStockReport() async {
    final repo = ref.read(productRepositoryProvider);
    final lowStockProducts = await repo.getLowStockProducts();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('أصناف منخفضة المخزون')),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: lowStockProducts.isEmpty
                ?  Center(child: Text(tr('لا توجد أصناف منخفضة المخزون 🎉')))
                : ListView.builder(
                    itemCount: lowStockProducts.length,
                    itemBuilder: (context, index) {
                      final p = lowStockProducts[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.error.withValues(alpha: 0.1),
                          child: Text(
                            '${p.currentStock.toInt()}',
                            style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(p.name),
                        subtitle: Text(tr('الحد الأدنى: {p0}', {'p0': p.minStock.toInt()})),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: p.currentStock <= 0
                                ? AppColors.error
                                : AppColors.warning,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p.currentStock <= 0 ? tr('نفذ') : tr('منخفض'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExpiredProductsReport() async {
    final repo = ref.read(productRepositoryProvider);
    final expiredBatches = await repo.getExpiredBatches();
    final products = ref.read(allProductsProvider).value ?? [];
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.xCircle, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('منتجات منتهية الصلاحية')),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: expiredBatches.isEmpty
                ?  Center(
                    child: Text(tr('🎉 لا توجد منتجات منتهية الصلاحية')))
                : ListView.builder(
                    itemCount: expiredBatches.length,
                    itemBuilder: (context, index) {
                      final batch = expiredBatches[index];
                      final product = products
                          .where((p) => p.id == batch.productId)
                          .firstOrNull;
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0x1AEF4444),
                          child: Icon(
                            PhosphorIconsBold.xCircle,
                            color: AppColors.error,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          product?.name ?? tr('منتج #{p0}', {'p0': batch.productId}),
                        ),
                        subtitle: Text(
                          tr('الباتش: {p0} - انتهى في {p1}', {'p0': batch.batchNumber, 'p1': DateFormat('dd/MM/yyyy').format(batch.expiryDate)}),
                        ),
                        trailing: Text(
                          tr('{p0} وحدة', {'p0': batch.quantity.toStringAsFixed(0)}),
                          style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExpiringProductsReport() async {
    final repo = ref.read(productRepositoryProvider);
    final expiringBatches = await repo.getExpiringBatches(30);
    final products = ref.read(allProductsProvider).value ?? [];
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.clock, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(tr('تنتهي خلال 30 يوم')),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: expiringBatches.isEmpty
                ?  Center(
                    child: Text(tr('🎉 لا توجد منتجات قاربت على الانتهاء')),
                  )
                : ListView.builder(
                    itemCount: expiringBatches.length,
                    itemBuilder: (context, index) {
                      final batch = expiringBatches[index];
                      final product = products
                          .where((p) => p.id == batch.productId)
                          .firstOrNull;
                      final daysLeft = batch.expiryDate
                          .difference(DateTime.now())
                          .inDays;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: daysLeft <= 7
                              ? const Color(0x1AEF4444)
                              : const Color(0x1AF59E0B),
                          child: Text(
                            '$daysLeft',
                            style: TextStyle(
                              color: daysLeft <= 7
                                  ? AppColors.error
                                  : AppColors.warning,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          product?.name ?? tr('منتج #{p0}', {'p0': batch.productId}),
                        ),
                        subtitle: Text(
                          tr('الباتش: {p0} - ينتهي في {p1}', {'p0': batch.batchNumber, 'p1': DateFormat('dd/MM/yyyy').format(batch.expiryDate)}),
                        ),
                        trailing: Text(
                          tr('{p0} وحدة', {'p0': batch.quantity.toStringAsFixed(0)}),
                          style: TextStyle(
                            color: daysLeft <= 7
                                ? AppColors.error
                                : AppColors.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showArReconciliation() async {
    try {
      final result = await ref.read(arReconciliationProvider.future);
      if (!mounted) return;
      if (result == null) {
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title:  Text(tr('تسوية الذمم')),
            content:  Text(
                tr('لم يتم تعيين حساب الذمم (receivables) في الربط المحاسبي.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child:  Text(tr('حسناً')),
              ),
            ],
          ),
        );
        return;
      }
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title:  Text(tr('تسوية الذمم مع الأستاذ العام')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  tr('حساب الذمم: {p0} — {p1}', {'p0': result.receivablesAccountCode, 'p1': result.receivablesAccountName})),
              const Divider(),
              _reconcRow(tr('رصيد بطاقات العملاء'), result.totalCardBalance),
              _reconcRow(tr('رصيد الأستاذ العام'), result.totalGlBalance),
              const Divider(),
              _reconcRow(tr('الفرق'), result.difference,
                  highlight: !result.isBalanced),
              if (result.isBalanced)
                 Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 4),
                    Text(tr('مُتسوٍّ'), style: const TextStyle(color: Colors.green)),
                  ]),
                )
              else
                 Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 4),
                    Text(tr('يوجد فرق — راجع القيود'),
                        style: const TextStyle(color: Colors.orange)),
                  ]),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('خطأ: {e}', {'e': e}))));
    }
  }

  Future<void> _showInventoryGlReconciliation() async {
    try {
      // Read the CHECK provider (not a data-only one): opening the report runs
      // the reconciliation AND fires the diagnostic-log alert when inventory
      // drifts from GL 1136, then shows the same figures.
      final check =
          await ref.read(inventoryGlReconciliationCheckProvider.future);
      final result = check.reconciliation;
      if (!mounted) return;
      if (result == null) {
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title:  Text(tr('تسوية المخزون')),
            content:  Text(
                tr('لم يتم تعيين حساب المخزون (inventory) في الربط المحاسبي.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child:  Text(tr('حسناً')),
              ),
            ],
          ),
        );
        return;
      }
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title:  Text(tr('تسوية المخزون مع الأستاذ العام')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  tr('حساب المخزون: {p0} — {p1}', {'p0': result.inventoryAccountCode, 'p1': result.inventoryAccountName})),
              const Divider(),
              _reconcRow(tr('قيمة المخزون (بالتكلفة)'), result.reportValue),
              _reconcRow(tr('رصيد الأستاذ العام'), result.glBalance),
              const Divider(),
              _reconcRow(tr('الفرق'), result.delta, highlight: !result.isBalanced),
              const SizedBox(height: 8),
               Text(tr('مصادر الفروق المحتملة:'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              _reconcRow(tr('فرق أساس التكلفة (متوسط المخزن مقابل التكلفة)'),
                  result.costBasisDivergence),
              _reconcRow(tr('فرق الرصيد الدفتري مقابل حركات المخازن'),
                  result.stockVsLedgerDivergence),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    'أصناف بتكلفة صفر لها رصيد: ${result.zeroCostItemCount} صنف '
                    '(كمية ${result.zeroCostStockQty.toStringAsFixed(2)})'),
              ),
              if (result.isBalanced)
                 Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 4),
                    Text(tr('مُتسوٍّ'), style: const TextStyle(color: Colors.green)),
                  ]),
                )
              else
                 Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 4),
                    Text(tr('يوجد فرق — راجع مصادر الفروق أعلاه'),
                        style: const TextStyle(color: Colors.orange)),
                  ]),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('خطأ: {e}', {'e': e}))));
    }
  }

  Widget _reconcRow(String label, double value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: highlight ? AppColors.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _HoverCard — reusable hover-aware container card (منسوخ حرفياً من الأصل —
// يبقى Container/MouseRegion يدوي لأن PicPosContentCard لا يوفّر منطق hover
// التفاعلي؛ السلوك يُحفظ كما هو حسب مصيدة النسخ).
// ---------------------------------------------------------------------------
class _HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  // ملحوظة: كان لها `highlighted` يُبرزها حين تكون فئتُها مفتوحةً في
  // الأكورديون. وقد حلّ محلَّ الأكورديون شريطٌ جانبيٌّ يُبرز الفئةَ المختارةَ
  // في مكانه — فلم يبقَ من يمرّر الرايةَ، وبقاؤها معطَّلةً يوهم بخيارٍ لا أثرَ له.
  const _HoverCard({
    required this.child,
    required this.onTap,
  });

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final showActive = _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: showActive
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border.withValues(alpha: 0.5),
            width: showActive ? 1.2 : 1,
          ),
          boxShadow: showActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data classes (منسوخة حرفياً من الأصل).
// ---------------------------------------------------------------------------
/// مجموعاتُ فئات التقارير في الشريط الجانبيّ — ترتيبُها ترتيبُ العرض.
List<String> get _kGroupOrder => [
  tr('البيع والربح'),
  tr('المخزون والشراء'),
  tr('العملاء والموردون'),
  tr('المال والضرائب'),
  tr('المتابعة والتحليل'),
];

/// فئةُ التقارير ← مجموعتُها.
///
/// ⚠️ **كلُّ فئةٍ لا بدّ لها من مدخلٍ هنا**: الشريطُ يرسم المجموعاتِ بترتيب
/// [_kGroupOrder]، وفئةٌ بلا مجموعةٍ تسقط في آخر مجموعةٍ صامتةً. يقيس ذلك
/// حارسٌ في `test/widget/picpos_reports_hub_test.dart`.
Map<String, String> get _kCatGroup => {
  'sales': tr('البيع والربح'),
  'profit': tr('البيع والربح'),
  'returns': tr('البيع والربح'),
  'inventory': tr('المخزون والشراء'),
  'purchases': tr('المخزون والشراء'),
  'customers': tr('العملاء والموردون'),
  'suppliers': tr('العملاء والموردون'),
  'cashbox': tr('المال والضرائب'),
  'taxes': tr('المال والضرائب'),
  'users': tr('المتابعة والتحليل'),
  'branches': tr('المتابعة والتحليل'),
  'audit': tr('المتابعة والتحليل'),
  'analytics': tr('المتابعة والتحليل'),
};

/// وصفُ الفئة في رأس لوحة التفصيل.
///
/// ⚠️ **مقصوصٌ على ما تحويه الفئةُ فعلاً.** أوصافُ التصميم تَعِد في أربعة
/// مواضعَ بما لا وجودَ له هنا: «ربح كل فاتورة» في الأرباح، و«أسباب الإرجاع»
/// في المرتجعات، و«الأصناف الراكدة» في المخزون، و«المديونية والدفعات» في
/// الموردين — فحُذفت تلك الجملُ وحدَها وبقي ما تُقابله تقاريرُ قائمة.
///
/// و«القوائم المالية» فئةٌ مستقلّةٌ في التصميم وهي هنا **تقريرٌ داخل
/// التحليلات** — فلم تُخترَع فئةٌ جديدةٌ لتطابق الرسم.
Map<String, String> get _kCatDesc => {
  'sales': 'كل ما يخص حركة البيع: الفواتير، الكاشير، الأصناف، المجموعات، '
      'وطرق الدفع',
  'profit': tr('تكلفة المبيعات وصافي الربح وهامش الربح على مستوى الصنف والتصنيف'),
  'returns': tr('مرتجعات المبيعات والمشتريات والمبالغ المستردة'),
  'inventory': tr('أرصدة وقيم المخزون، كرت الصنف، الجرد، والصلاحيات'),
  'purchases': tr('المشتريات بفلاتر كاملة ومتابعة أوامر الشراء المفتوحة'),
  'customers': 'كشوف الحساب، تقادم الذمم، سلوك الشراء، وتسوية الذمم مع '
      'الأستاذ العام',
  'suppliers': tr('كشوف حساب الموردين وحجم التعامل'),
  'cashbox': 'حركة الخزينة، الورديات وعجز النقدية، التوصيل، والمصروفات '
      'التشغيلية',
  'taxes': 'الضريبة المحصلة والمدفوعة وصافي الالتزام وحالة الفاتورة '
      'الإلكترونية',
  'users': tr('نشاط المستخدمين وسجل الدخول ومصفوفة الصلاحيات لكل دور'),
  'branches': tr('مقارنة أداء الفروع والتحويلات المخزنية بينها'),
  'audit': tr('سجل العمليات والتعديلات والطباعة والإلغاءات — أثر كامل لكل حركة'),
  'analytics': tr('اتجاهات وأنماط المبيعات وتقسيم العملاء ودوران المخزون'),
};

class PicposReportCategory {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<PicposReportEntry> mainReports;
  final List<PicposReportShortcut> shortcuts;

  const PicposReportCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.mainReports,
    this.shortcuts = const [],
  });
}

class PicposReportEntry {
  final String id;
  final String title;
  final String subtitle;
  final String? permission;
  final VoidCallback action;

  /// Manager override is enabled for every protected report — same UX as the
  /// legacy launcher. Kept as a getter (not a constructor field) so the
  /// analyzer doesn't complain about an "unused optional parameter" while
  /// preserving the contract documented in data-model.md.
  bool get allowManagerOverride => true;

  const PicposReportEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.action,
    this.permission,
  });
}

class PicposReportShortcut {
  final String id;
  final String title;
  final String parentReportId;

  /// Destination for shortcuts that lead somewhere OTHER than their parent
  /// report. Without this every shortcut fell through to `parent.action()`,
  /// so «حسب المجموعة» opened the plain sales report — the by-category report
  /// existed and was reachable elsewhere, but this chip never went there,
  /// which read to users as "the report is missing".
  final VoidCallback? action;

  const PicposReportShortcut(this.id, this.title, this.parentReportId,
      {this.action});
}

class _FlatItem {
  final String id;
  final String title;
  final String subtitle;
  final PicposReportCategory category;
  final bool isShortcut;
  const _FlatItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.isShortcut,
  });
}

List<_FlatItem> _flatten(List<PicposReportCategory> cats) {
  final out = <_FlatItem>[];
  for (final cat in cats) {
    for (final r in cat.mainReports) {
      out.add(_FlatItem(
        id: r.id,
        title: r.title,
        subtitle: r.subtitle,
        category: cat,
        isShortcut: false,
      ));
    }
    for (final s in cat.shortcuts) {
      out.add(_FlatItem(
        id: s.id,
        title: s.title,
        subtitle: cat.title,
        category: cat,
        isShortcut: true,
      ));
    }
  }
  return out;
}

/// أفعالُ الكتالوج التي تحتاج شجرةَ الودجت.
///
/// ⚠️ **ولماذا كائنٌ لا معاملاتٌ خمسة**: من يريد وصفَ الكتالوج — الشريطُ
/// الجانبيُّ يقرأ العناوينَ والصلاحيّات — لا شأنَ له بأيٍّ منها، ولولا
/// [inert] لاضطرَّ إلى تلفيق خمسِ دوالٍّ فارغةٍ في موضع الاستدعاء.
class PicposReportActions {
  /// دفعُ شاشةِ تقريرٍ على المُلاح.
  final void Function(Widget Function()) open;

  /// حواراتٌ تُبنى في مكانها ولا تُدفَع كشاشة.
  final VoidCallback showLowStock;
  final VoidCallback showExpired;
  final VoidCallback showExpiring;
  final VoidCallback showArReconciliation;
  final VoidCallback showInventoryGlReconciliation;

  const PicposReportActions({
    required this.open,
    required this.showLowStock,
    required this.showExpired,
    required this.showExpiring,
    required this.showArReconciliation,
    required this.showInventoryGlReconciliation,
  });

  static void _noop() {}
  static void _noopOpen(Widget Function() _) {}

  /// وصفٌ بلا فتح — لمن يقرأ الكتالوج ليعرضه لا ليفتحه.
  ///
  /// ⚠️ ونقرةٌ على نتيجةٍ بُنيت بهذه لا تفعل شيئاً بصمت. فمن يعرضها يفتح
  /// عبر مسارِ الشاشة المحروس لا عبر `action` — وهو الفرقُ الذي يحفظ فحصَ
  /// الصلاحية وموافقةَ المسؤول.
  static const inert = PicposReportActions(
    open: _noopOpen,
    showLowStock: _noop,
    showExpired: _noop,
    showExpiring: _noop,
    showArReconciliation: _noop,
    showInventoryGlReconciliation: _noop,
  );
}

/// كتالوجُ تقارير PicPos — **المصدرُ الوحيد**.
///
/// ⚠️ **رُفع من داخل `State` إلى مستوى الملفّ** ليقرأه الشريطُ الجانبيّ:
/// أمرُ المالك 2026-09-12 يضع رؤوسَ فئات التقارير في الشريط وتحتَها
/// تقاريرُها. ونسخُ العناوين هناك كان يُنتج مصدراً ثانياً — والملفُّ يحمل
/// أصلاً تحذيراً من ازدواجٍ قائم («الكتالوجُ وحدَه مفروك»)، فثالثٌ يضاعفه.
///
/// و[open] هي كلُّ ما كان يربطه بالشجرة: من يريد **وصفَ** الكتالوج لا فتحَه
/// يمرّر دالّةً لا تفعل شيئاً، فيقرأ العناوينَ والمعرّفاتِ والصلاحيّاتِ
/// من عين ما يُفتَح منه.
List<PicposReportCategory> buildPicposReportCatalog({
  required PicposReportActions actions,
  required String? eInvoicePlatform,
}) {
    return [
      PicposReportCategory(
        id: 'sales',
        title: tr('تقارير المبيعات'),
        icon: PhosphorIconsBold.chartLineUp,
        color: AppColors.success,
        mainReports: [
          PicposReportEntry(
            id: 'sales_main',
            title: tr('تقرير المبيعات'),
            subtitle: tr('تقرير المبيعات الرئيسي بكافة الفلاتر'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const SalesReportScreen()),
          ),
          PicposReportEntry(
            id: 'sales_summary',
            title: tr('ملخص المبيعات'),
            subtitle: tr('نظرة سريعة بأرقام اليوم'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const SalesReportScreen()),
          ),
          // منسوخٌ عن الأصل (`screens/reports_screen.dart`) — الشاشةُ الوجهةُ
          // نفسُها بلا تعديل. الكتالوجُ وحدَه مفروك، فالبطاقةُ تُضاف في
          // الاثنين معاً وإلّا ظهر التقريرُ في هويّةٍ وغاب عن الأخرى.
          PicposReportEntry(
            id: 'tables_report',
            title: tr('تقرير الطاولات'),
            subtitle: tr('الإيراد ودوران الطاولة ونصيب الضيف لكل قسم وطاولة'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const TablesReportScreen()),
          ),
        ],
        shortcuts: [
           PicposReportShortcut('s_today', tr('مبيعات اليوم'), 'sales_main'),
           PicposReportShortcut('s_range', tr('من تاريخ إلى تاريخ'), 'sales_main'),
          // ⚠️ كانت بلا `action` فتسقط على `parent.action()` = تقريرُ
          // المبيعات العامّ **بلا أيّ ترشيحٍ بالكاشير** — وهو بعينه العطبُ
          // الموثَّقُ فوق لشريحة «حسب المجموعة»، ومصدرُ بلاغ المالك
          // 2026-08-14 «التقريرُ حسب المستخدم غيرُ دقيق»: الشريحةُ تَعِد
          // بترشيحٍ لا يقع.
          PicposReportShortcut('s_cashier', tr('حسب الكاشير'), 'sales_main',
              action: () => actions.open(() => const ShiftsReportScreen())),
           PicposReportShortcut('s_branch', tr('حسب الفرع'), 'sales_main'),
          PicposReportShortcut('s_product', tr('حسب الصنف'), 'sales_main',
              action: () => actions.open(() => const TopProductsReportScreen())),
          PicposReportShortcut('s_group', tr('حسب المجموعة'), 'sales_main',
              action: () => actions.open(() => const SalesByClassificationReport())),
           PicposReportShortcut('s_payment', tr('حسب طريقة الدفع'), 'sales_main'),
           PicposReportShortcut(
              's_credit', tr('مبيعات آجل / نقدي / فيزا'), 'sales_main'),
        ],
      ),
      PicposReportCategory(
        id: 'profit',
        title: tr('تقارير الأرباح'),
        icon: PhosphorIconsBold.money,
        color: AppColors.successDark,
        mainReports: [
          PicposReportEntry(
            id: 'category_profit',
            title: tr('أرباح التصنيفات'),
            subtitle: tr('تحليل تكلفة المبيعات وصافي الربح لكل تصنيف'),
            permission: 'reports_category_profit',
            action: () => actions.open(() => const CategoryProfitReportScreen()),
          ),
          PicposReportEntry(
            id: 'consumption',
            title: tr('تقرير استهلاك الخامات'),
            subtitle: tr('استهلاك الخامات وربحية المنتجات (auto-deplete)'),
            permission: 'reports_category_profit',
            action: () => actions.open(() => const ConsumptionReportScreen()),
          ),
          PicposReportEntry(
            id: 'top_profitable',
            title: tr('الأصناف الأكثر ربحية'),
            subtitle: tr('ترتيب المنتجات حسب الربح'),
            action: () => actions.open(() => const TopProductsReportScreen()),
          ),
          PicposReportEntry(
            id: 'profit_margin',
            title: tr('هامش الربح'),
            subtitle: tr('تحليل هامش الربح حسب الفئة'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: profitMarginReport()),
            ),
          ),
        ],
        shortcuts: [
           PicposReportShortcut('p_invoice', tr('ربح كل فاتورة'), 'category_profit'),
          PicposReportShortcut('p_product', tr('ربح كل صنف'), 'category_profit',
              action: () => actions.open(() => const TopProductsReportScreen())),
          PicposReportShortcut('p_group', tr('حسب المجموعة'), 'category_profit',
              action: () => actions.open(() => const CategoryProfitReportScreen())),
          // تقريرُ أرباح التصنيفات **لا مرشِّحَ مستخدمٍ فيه أصلاً** (مقيسٌ:
          // صفرُ ذكرٍ لـ`_selectedUserId`)، فالشريحةُ كانت تَعِد بما لا
          // يستطيعه المصدر. وجهتُها «الإغلاق حسب المستخدم» حيث الأرقامُ
          // مبوّبةٌ بالاسم فعلاً.
          PicposReportShortcut('p_cashier', tr('حسب الكاشير'), 'category_profit',
              action: () => actions.open(() => const ShiftsReportScreen())),
           PicposReportShortcut('p_branch', tr('حسب الفرع'), 'category_profit'),
        ],
      ),
      PicposReportCategory(
        id: 'returns',
        title: tr('تقارير المرتجعات'),
        icon: PhosphorIconsBold.arrowUUpLeft,
        color: AppColors.error,
        mainReports: [
          PicposReportEntry(
            id: 'sales_returns',
            title: tr('مرتجعات المبيعات'),
            subtitle: tr('تحليل مرتجعات المبيعات والمبالغ المستردة'),
            action: () => actions.open(() => const SalesReturnsReportScreen()),
          ),
          PicposReportEntry(
            id: 'purchase_returns',
            title: tr('مرتجعات المشتريات'),
            subtitle: tr('تحليل مرتجعات المشتريات من الموردين'),
            action: () => actions.open(() => const PurchaseReturnsReportScreen()),
          ),
        ],
        // ⚠️ `r_cashier` («حسب الكاشير») **أُزيلت** 2026-08-14: تقريرُ
        // مرتجعات المبيعات لا مرشِّحَ مستخدمٍ فيه إطلاقاً (صفرُ ذكرٍ لـ
        // `_selectedUserId` فيه)، والشريحةُ كانت بلا `action` فتسقط على
        // التقرير العامّ وتعرض مرتجعاتِ **كلّ** الكاشيرين تحت عنوانٍ يقول
        // «حسب الكاشير». وهذا بعينه بلاغُ المالك «التقريرُ حسب المستخدم غيرُ
        // دقيق». وإعادتُها تحتاج مرشِّحَ مستخدمٍ في التقرير نفسِه — بندٌ
        // مستقلٌّ مصرَّحٌ به عند التسليم، لا شريحةٌ تكذب.
        shortcuts:  [
          PicposReportShortcut('r_today', tr('مرتجعات اليوم'), 'sales_returns'),
          PicposReportShortcut('r_product', tr('حسب الصنف'), 'sales_returns'),
          PicposReportShortcut('r_customer', tr('حسب العميل'), 'sales_returns'),
        ],
      ),
      PicposReportCategory(
        id: 'inventory',
        title: tr('تقارير المخزون'),
        icon: PhosphorIconsBold.warehouse,
        color: AppColors.info,
        mainReports: [
          PicposReportEntry(
            id: 'inv_current',
            title: tr('تقرير المخزون الحالي'),
            subtitle: tr('أرصدة وقيم المخزون بالتكلفة والبيع'),
            action: () => actions.open(() => const InventoryReportScreen()),
          ),
          PicposReportEntry(
            id: 'inv_gl_reconciliation',
            title: tr('تسوية المخزون مع الأستاذ العام'),
            subtitle: tr('مقارنة قيمة المخزون بحساب 1136 ومصادر الفروق'),
            action: actions.showInventoryGlReconciliation,
          ),
          PicposReportEntry(
            id: 'inv_movement',
            title: tr('حركة الأصناف'),
            subtitle: tr('كرت صنف تفصيلي مع كل العمليات'),
            action: () => actions.open(() => const StockMovementsScreen()),
          ),
          PicposReportEntry(
            id: 'inv_stocktake',
            title: tr('تقرير الجرد'),
            subtitle: tr('تقرير الجرد الدوري والفروق'),
            action: () => actions.open(() => const StockAuditScreen()),
          ),
          PicposReportEntry(
            id: 'inv_top_selling',
            title: tr('الأصناف الأكثر مبيعاً'),
            subtitle: tr('تحليل الأصناف الأعلى طلباً والأكثر ربحية'),
            action: () => actions.open(() => const TopProductsReportScreen()),
          ),
          PicposReportEntry(
            id: 'low_stock',
            title: tr('أصناف منخفضة المخزون'),
            subtitle: tr('قائمة الأصناف التي وصلت لحد الطلب'),
            action: actions.showLowStock,
          ),
          PicposReportEntry(
            id: 'expired_products',
            title: tr('منتجات منتهية الصلاحية'),
            subtitle: tr('قائمة الأصناف التي انتهت صلاحيتها وتحتاج إعدام'),
            action: actions.showExpired,
          ),
          PicposReportEntry(
            id: 'expiring_products',
            title: tr('منتجات قاربت على الانتهاء'),
            subtitle: tr('تنتهي صلاحيتها خلال الـ 30 يوماً القادمة'),
            action: actions.showExpiring,
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('i_low', tr('قليلة المخزون'), 'low_stock'),
          PicposReportShortcut('i_dead', tr('الأصناف الراكدة'), 'inv_movement'),
        ],
      ),
      PicposReportCategory(
        id: 'purchases',
        title: tr('تقارير المشتريات'),
        icon: PhosphorIconsBold.shoppingCart,
        color: const Color(0xFFD97706),
        mainReports: [
          PicposReportEntry(
            id: 'purch_main',
            title: tr('تقرير المشتريات'),
            subtitle: tr('تقرير المشتريات بفلاتر كاملة'),
            action: () => actions.open(() => const PurchasesReportScreen()),
          ),
          PicposReportEntry(
            id: 'purch_orders',
            title: tr('أوامر الشراء'),
            subtitle: tr('متابعة أوامر الشراء المفتوحة'),
            action: () => actions.open(() => const PurchaseOrdersScreen()),
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('pu_today', tr('مشتريات اليوم'), 'purch_main'),
          PicposReportShortcut('pu_supplier', tr('حسب المورد'), 'purch_main'),
          PicposReportShortcut('pu_product', tr('حسب الصنف'), 'purch_main'),
          PicposReportShortcut('pu_branch', tr('حسب الفرع'), 'purch_main'),
        ],
      ),
      PicposReportCategory(
        id: 'customers',
        title: tr('تقارير العملاء'),
        icon: PhosphorIconsBold.users,
        color: const Color(0xFF8B5CF6),
        mainReports: [
          PicposReportEntry(
            id: 'cust_statement',
            title: tr('كشف حساب العميل'),
            subtitle: tr('كشف حساب تفصيلي بالحركات'),
            action: () => actions.open(() => const PartyStatementPicposScreen()),
          ),
          PicposReportEntry(
            id: 'cust_aging',
            title: tr('تقادم ذمم العملاء'),
            subtitle: tr('الذمم المتأخرة بشرائح الأيام'),
            action: () => actions.open(() => const ArAgingReportPicposScreen()),
          ),
          PicposReportEntry(
            id: 'cust_behavior',
            title: tr('تحليل سلوك العملاء'),
            subtitle: tr('تكرار الشراء ومتوسط الفاتورة'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: partyBehaviorReport(suppliers: false)),
            ),
          ),
          PicposReportEntry(
            id: 'cust_reconciliation',
            title: tr('تسوية الذمم مع الأستاذ العام'),
            subtitle: tr('مقارنة أرصدة العملاء مع حساب الذمم'),
            action: actions.showArReconciliation,
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('c_sales', tr('مبيعات العميل'), 'cust_statement'),
          PicposReportShortcut('c_collect', tr('تحصيلات العملاء'), 'cust_statement'),
          PicposReportShortcut('c_debt', tr('العملاء المديونين'), 'cust_aging'),
          PicposReportShortcut('c_top', tr('حسب حجم المبيعات'), 'cust_behavior'),
        ],
      ),
      PicposReportCategory(
        id: 'suppliers',
        title: tr('تقارير الموردين'),
        icon: PhosphorIconsBold.truck,
        color: const Color(0xFFEA580C),
        mainReports: [
          PicposReportEntry(
            id: 'sup_statement',
            title: tr('كشف حساب المورد'),
            subtitle: tr('كشف تفصيلي بالحركات'),
            // دفعة ١٢ — الفئة كلها كانت بتترسم لأي حد معاه reports_view
            // (حقل permission اختياري، ولما يبقى null التايل بيظهر بلا فحص).
            permission: PermissionCodes.reportsSuppliers,
            action: () =>
                actions.open(() => const PartyStatementPicposScreen(isSupplier: true)),
          ),
          PicposReportEntry(
            id: 'sup_behavior',
            title: tr('تحليل سلوك الموردين'),
            subtitle: tr('الموردون النشطون وحجم التعامل'),
            permission: PermissionCodes.reportsSuppliers,
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: partyBehaviorReport(suppliers: true)),
            ),
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('su_purch', tr('مشتريات المورد'), 'sup_statement'),
          PicposReportShortcut('su_debt', tr('مديونية الموردين'), 'sup_statement'),
          PicposReportShortcut('su_pay', tr('دفعات الموردين'), 'sup_statement'),
          PicposReportShortcut('su_top', tr('حسب حجم الشراء'), 'sup_behavior'),
        ],
      ),
      PicposReportCategory(
        id: 'cashbox',
        title: tr('الصناديق والكاش'),
        icon: PhosphorIconsBold.wallet,
        color: AppColors.primary,
        mainReports: [
          PicposReportEntry(
            id: 'cb_treasury',
            title: tr('حركة الخزينة'),
            subtitle: tr('سجل المقبوضات والمدفوعات والمصروفات'),
            permission: PermissionCodes.reportsTreasury,
            action: () => actions.open(() => const TreasuryReportScreen()),
          ),
          PicposReportEntry(
            id: 'cb_shifts',
            title: tr('تقرير الورديات'),
            subtitle: tr('فتح وتسكير الورديات وعجز النقدية'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const ShiftsReportScreen()),
          ),
          PicposReportEntry(
            id: 'cb_delivery',
            title: tr('تقرير عمليات التوصيل'),
            subtitle: tr('إحصائيات المناديب ورسوم شركات التوصيل'),
            action: () => actions.open(() => const DeliveryReportScreen()),
          ),
          PicposReportEntry(
            id: 'cb_expenses',
            title: tr('تقرير المصروفات التشغيلية'),
            subtitle: tr('إجمالي المصروفات حسب الفئة والفرع والفترة'),
            action: () => actions.open(() => const ExpensesReportScreen()),
          ),
        ],
        shortcuts:  [
          PicposReportShortcut('cb_open', tr('فتح وإغلاق الصندوق'), 'cb_shifts'),
          PicposReportShortcut('cb_diff', tr('العجز والزيادة'), 'cb_shifts'),
          PicposReportShortcut('cb_in_out', tr('المقبوضات والمدفوعات'), 'cb_treasury'),
          PicposReportShortcut('cb_methods', tr('نقدي / فيزا / آجل'), 'cb_treasury'),
        ],
      ),
      PicposReportCategory(
        id: 'users',
        title: tr('تقارير المستخدمين'),
        icon: PhosphorIconsBold.userCircle,
        color: const Color(0xFF7C3AED),
        mainReports: [
          // ⚠️ الثلاثةُ كانت **بلا `permission:`** حتى 2026-08-13، والمُصيِّر
          // لا يلفّ إلا ما له كود (`r.permission != null` أدناه). فكانت
          // «التقارير» باباً خلفياً: من يملك `reports_view` وحدَه يفتح سجلَّ
          // النشاط، و**شاشةَ إدارة المستخدمين** التي فيها إسنادُ الأدوار
          // وتصفيرُ كلمات المرور — أي تصعيدُ امتيازٍ كامل. والبابُ الأماميُّ
          // لنفس الشاشة محروسٌ في `settings_picpos_screen.dart:654`.
          PicposReportEntry(
            id: 'u_activity',
            title: tr('نشاط المستخدمين'),
            subtitle: tr('العمليات لكل مستخدم'),
            permission: PermissionCodes.auditView,
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: userActivityReport()),
            ),
          ),
          PicposReportEntry(
            id: 'u_login',
            title: tr('سجل دخول المستخدمين'),
            subtitle: tr('متى دخل كل مستخدم وخرج'),
            permission: PermissionCodes.auditView,
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل دخول المستخدمين'),
                presetSubtitle: tr('من دخل ومتى خرج — بما فيه ترقية الصلاحيات'),
                presetCategory: 'auth',
              ),
            ),
          ),
          PicposReportEntry(
            id: 'u_perms',
            title: tr('صلاحيات المستخدمين'),
            subtitle: tr('مصفوفة صلاحيات لكل دور ومستخدم'),
            // مهمة 14: هذا الفورك (reports_picpos_screen.dart) خاص بـ PicPos
            // فقط (Brand.isPicPos) — فالـ push يروح مباشرة لشاشة المستخدمين
            // بهوية PicPos، بلا حاجة لفحص العلامة هنا.
            permission: PermissionCodes.usersManage,
            action: () => actions.open(() => const UsersManagementPicposScreen()),
          ),
        ],
      ),
      PicposReportCategory(
        id: 'branches',
        title: tr('تقارير الفروع'),
        icon: PhosphorIconsBold.buildings,
        color: const Color(0xFF0891B2),
        mainReports: [
          PicposReportEntry(
            id: 'br_performance',
            title: tr('أداء الفروع'),
            subtitle: tr('مقارنة مبيعات وأرباح الفروع'),
            action: () => actions.open(() => const BranchPerformanceScreen()),
          ),
          PicposReportEntry(
            id: 'br_transfers',
            title: tr('التحويلات بين الفروع'),
            subtitle: tr('سجل التحويلات وحركة المخزون'),
            action: () => actions.open(() => const StockMovementsScreen()),
          ),
        ],
      ),
      PicposReportCategory(
        id: 'taxes',
        title: tr('تقارير الضرائب'),
        icon: PhosphorIconsBold.percent,
        color: const Color(0xFF0369A1),
        mainReports: [
          PicposReportEntry(
            id: 'tx_main',
            title: tr('تقرير ضريبة المبيعات'),
            subtitle: tr('الضرائب المحصلة والمدفوعة وصافي الالتزام'),
            permission: PermissionCodes.reportsTaxes,
            action: () => actions.open(() => const TaxReportScreen()),
          ),
          PicposReportEntry(
            id: 'tx_vat_recon',
            title: tr('تسوية ضريبة القيمة المضافة'),
            subtitle: tr('مقارنة ضريبة الفواتير مع الأستاذ العام'),
            permission: PermissionCodes.reportsTaxes,
            action: () => actions.open(() => const VatReconciliationScreen()),
          ),
          if (eInvoicePlatform != null)
            PicposReportEntry(
              id: 'tx_einvoice',
              title: tr('تقرير الفوترة الإلكترونية'),
              subtitle: tr('متابعة حالات الإرسال والقبول من الضرائب'),
              action: () => actions.open(() => const EInvoiceDashboardScreen()),
            ),
        ],
        shortcuts:  [
          PicposReportShortcut('tx_sales', tr('ضرائب المبيعات'), 'tx_main'),
          PicposReportShortcut('tx_purch', tr('ضرائب المشتريات'), 'tx_main'),
        ],
      ),
      PicposReportCategory(
        id: 'audit',
        title: tr('الحركة والسجلات'),
        icon: PhosphorIconsBold.listChecks,
        color: AppColors.errorDark,
        mainReports: [
          PicposReportEntry(
            id: 'a_ops',
            title: tr('سجل العمليات'),
            subtitle: tr('كل العمليات في النظام'),
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل العمليات'),
                presetSubtitle: tr('كل ما جرى على النظام بلا ترشيح'),
              ),
            ),
          ),
          PicposReportEntry(
            id: 'a_edits',
            title: tr('سجل التعديلات'),
            subtitle: tr('الفواتير والمستندات المعدلة'),
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل التعديلات'),
                presetSubtitle: tr('تعديلٌ وقع على مستندٍ صادر'),
                presetActions: ActivityLogPresets.documentEdits,
              ),
            ),
          ),
          PicposReportEntry(
            id: 'a_print',
            title: tr('سجل الطباعة'),
            subtitle: tr('متى طُبع كل مستند ومن قبل من'),
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل الطباعة'),
                presetSubtitle: tr('كل طباعةٍ بمن نفّذها ووقتها'),
                presetActions: ActivityLogPresets.printed,
              ),
            ),
          ),
          PicposReportEntry(
            id: 'a_void',
            title: tr('سجل الإلغاءات'),
            subtitle: tr('الفواتير الملغاة وأسبابها'),
            action: () => actions.open(
              () =>  ActivityLogPicposScreen(
                presetTitle: tr('سجل الإلغاءات'),
                presetSubtitle: tr('إلغاءُ مستندٍ صادرٍ أو حذفُه'),
                presetActions: ActivityLogPresets.voided,
              ),
            ),
          ),
        ],
      ),
      PicposReportCategory(
        id: 'analytics',
        title: tr('التحليلات والإحصائيات'),
        icon: PhosphorIconsBold.chartDonut,
        color: const Color(0xFFA21CAF),
        mainReports: [
          PicposReportEntry(
            id: 'an_sales',
            title: tr('تحليل المبيعات'),
            subtitle: tr('اتجاهات وأنماط المبيعات'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: salesTrendReport()),
            ),
          ),
          PicposReportEntry(
            id: 'an_classifications',
            title: tr('المبيعات حسب التصنيف'),
            subtitle: tr('تحليل المبيعات حسب المجموعات أو أنواع البيع'),
            permission: PermissionCodes.reportsSales,
            action: () => actions.open(() => const SalesByClassificationReport()),
          ),
          PicposReportEntry(
            id: 'an_financial',
            title: tr('القوائم المالية الختامية'),
            subtitle: tr('الميزانية، قائمة الدخل، وميزان المراجعة (Real-time)'),
            action: () => actions.open(() => Brand.isPicPos
                ? const FinancialStatementsPicPosScreen()
                : const FinancialStatementsScreen()),
          ),
          PicposReportEntry(
            id: 'an_customers',
            title: tr('تحليل العملاء'),
            subtitle: tr('تقسيم العملاء (RFM)'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: customerSegmentsReport()),
            ),
          ),
          PicposReportEntry(
            id: 'an_inventory',
            title: tr('تحليل المخزون'),
            subtitle: tr('دوران وكفاءة المخزون'),
            action: () => actions.open(
              () => ReportViewPicposScreen(definition: inventoryTurnoverReport()),
            ),
          ),
        ],
      ),
    ];
  }
