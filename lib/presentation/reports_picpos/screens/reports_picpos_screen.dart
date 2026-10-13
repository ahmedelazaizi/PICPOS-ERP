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
import 'rep_reports_picpos_screen.dart';
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

part 'reports_picpos_build.dart';
part 'reports_picpos_cards.dart';
part 'reports_picpos_dialogs.dart';
part 'reports_picpos_support.dart';
part 'reports_picpos_data.dart';
part 'reports_picpos_catalog_sales_inventory.dart';

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
      subtitle: tr('{p0} تقريراً واختصاراً في {p1} فئة', {'p0': _allItems.length, 'p1': _categories.length}),
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

}