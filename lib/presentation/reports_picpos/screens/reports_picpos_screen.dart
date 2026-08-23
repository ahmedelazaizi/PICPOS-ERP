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
import '../../../data/providers/reconciliation_provider.dart';
import '../../widgets/permission_guard.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';

// Destination screens — existing in the codebase, unchanged by this fork.
import '../../screens/activity_log_screen.dart';
import '../../screens/analytics_dashboard_screen.dart';
import '../../screens/branch_performance_screen.dart';
import '../../screens/e_invoice_dashboard_screen.dart';
import '../../screens/party_statement_screen.dart';
import '../../screens/report_builder_screen.dart';
import '../../screens/reports/ar_aging_report_screen.dart';
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

  late final List<_ReportCategory> _categories = _buildCategories();
  late final List<_FlatItem> _allItems = _flatten(_categories);

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleAccordion(_ReportCategory cat) {
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
  List<_ReportCategory> _buildCategories() {
    void nav(Widget Function() builder) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => builder()),
      );
    }

    final eInvoicePlatform =
        ref.read(activeEInvoicePlatformProvider).value;

    return [
      _ReportCategory(
        id: 'sales',
        title: 'تقارير المبيعات',
        icon: PhosphorIconsBold.chartLineUp,
        color: AppColors.success,
        mainReports: [
          _ReportEntry(
            id: 'sales_main',
            title: 'تقرير المبيعات',
            subtitle: 'تقرير المبيعات الرئيسي بكافة الفلاتر',
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const SalesReportScreen()),
          ),
          _ReportEntry(
            id: 'sales_summary',
            title: 'ملخص المبيعات',
            subtitle: 'نظرة سريعة بأرقام اليوم',
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const SalesReportScreen()),
          ),
          // منسوخٌ عن الأصل (`screens/reports_screen.dart`) — الشاشةُ الوجهةُ
          // نفسُها بلا تعديل. الكتالوجُ وحدَه مفروك، فالبطاقةُ تُضاف في
          // الاثنين معاً وإلّا ظهر التقريرُ في هويّةٍ وغاب عن الأخرى.
          _ReportEntry(
            id: 'tables_report',
            title: 'تقرير الطاولات',
            subtitle: 'الإيراد ودوران الطاولة ونصيب الضيف لكل قسم وطاولة',
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const TablesReportScreen()),
          ),
        ],
        shortcuts: [
          const _ReportShortcut('s_today', 'مبيعات اليوم', 'sales_main'),
          const _ReportShortcut('s_range', 'من تاريخ إلى تاريخ', 'sales_main'),
          // ⚠️ كانت بلا `action` فتسقط على `parent.action()` = تقريرُ
          // المبيعات العامّ **بلا أيّ ترشيحٍ بالكاشير** — وهو بعينه العطبُ
          // الموثَّقُ فوق لشريحة «حسب المجموعة»، ومصدرُ بلاغ المالك
          // 2026-08-14 «التقريرُ حسب المستخدم غيرُ دقيق»: الشريحةُ تَعِد
          // بترشيحٍ لا يقع.
          _ReportShortcut('s_cashier', 'حسب الكاشير', 'sales_main',
              action: () => nav(() => const ShiftsReportScreen())),
          const _ReportShortcut('s_branch', 'حسب الفرع', 'sales_main'),
          _ReportShortcut('s_product', 'حسب الصنف', 'sales_main',
              action: () => nav(() => const TopProductsReportScreen())),
          _ReportShortcut('s_group', 'حسب المجموعة', 'sales_main',
              action: () => nav(() => const SalesByClassificationReport())),
          const _ReportShortcut('s_payment', 'حسب طريقة الدفع', 'sales_main'),
          const _ReportShortcut(
              's_credit', 'مبيعات آجل / نقدي / فيزا', 'sales_main'),
        ],
      ),
      _ReportCategory(
        id: 'profit',
        title: 'تقارير الأرباح',
        icon: PhosphorIconsBold.money,
        color: AppColors.successDark,
        mainReports: [
          _ReportEntry(
            id: 'category_profit',
            title: 'أرباح التصنيفات',
            subtitle: 'تحليل تكلفة المبيعات وصافي الربح لكل تصنيف',
            permission: 'reports_category_profit',
            action: () => nav(() => const CategoryProfitReportScreen()),
          ),
          _ReportEntry(
            id: 'consumption',
            title: 'تقرير استهلاك الخامات',
            subtitle: 'استهلاك الخامات وربحية المنتجات (auto-deplete)',
            permission: 'reports_category_profit',
            action: () => nav(() => const ConsumptionReportScreen()),
          ),
          _ReportEntry(
            id: 'top_profitable',
            title: 'الأصناف الأكثر ربحية',
            subtitle: 'ترتيب المنتجات حسب الربح',
            action: () => nav(() => const TopProductsReportScreen()),
          ),
          _ReportEntry(
            id: 'profit_margin',
            title: 'هامش الربح',
            subtitle: 'تحليل هامش الربح حسب الفئة',
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
        ],
        shortcuts: [
          const _ReportShortcut('p_invoice', 'ربح كل فاتورة', 'category_profit'),
          _ReportShortcut('p_product', 'ربح كل صنف', 'category_profit',
              action: () => nav(() => const TopProductsReportScreen())),
          _ReportShortcut('p_group', 'حسب المجموعة', 'category_profit',
              action: () => nav(() => const CategoryProfitReportScreen())),
          // تقريرُ أرباح التصنيفات **لا مرشِّحَ مستخدمٍ فيه أصلاً** (مقيسٌ:
          // صفرُ ذكرٍ لـ`_selectedUserId`)، فالشريحةُ كانت تَعِد بما لا
          // يستطيعه المصدر. وجهتُها «الإغلاق حسب المستخدم» حيث الأرقامُ
          // مبوّبةٌ بالاسم فعلاً.
          _ReportShortcut('p_cashier', 'حسب الكاشير', 'category_profit',
              action: () => nav(() => const ShiftsReportScreen())),
          const _ReportShortcut('p_branch', 'حسب الفرع', 'category_profit'),
        ],
      ),
      _ReportCategory(
        id: 'returns',
        title: 'تقارير المرتجعات',
        icon: PhosphorIconsBold.arrowUUpLeft,
        color: AppColors.error,
        mainReports: [
          _ReportEntry(
            id: 'sales_returns',
            title: 'مرتجعات المبيعات',
            subtitle: 'تحليل مرتجعات المبيعات والمبالغ المستردة',
            action: () => nav(() => const SalesReturnsReportScreen()),
          ),
          _ReportEntry(
            id: 'purchase_returns',
            title: 'مرتجعات المشتريات',
            subtitle: 'تحليل مرتجعات المشتريات من الموردين',
            action: () => nav(() => const PurchaseReturnsReportScreen()),
          ),
        ],
        // ⚠️ `r_cashier` («حسب الكاشير») **أُزيلت** 2026-08-14: تقريرُ
        // مرتجعات المبيعات لا مرشِّحَ مستخدمٍ فيه إطلاقاً (صفرُ ذكرٍ لـ
        // `_selectedUserId` فيه)، والشريحةُ كانت بلا `action` فتسقط على
        // التقرير العامّ وتعرض مرتجعاتِ **كلّ** الكاشيرين تحت عنوانٍ يقول
        // «حسب الكاشير». وهذا بعينه بلاغُ المالك «التقريرُ حسب المستخدم غيرُ
        // دقيق». وإعادتُها تحتاج مرشِّحَ مستخدمٍ في التقرير نفسِه — بندٌ
        // مستقلٌّ مصرَّحٌ به عند التسليم، لا شريحةٌ تكذب.
        shortcuts: const [
          _ReportShortcut('r_today', 'مرتجعات اليوم', 'sales_returns'),
          _ReportShortcut('r_product', 'حسب الصنف', 'sales_returns'),
          _ReportShortcut('r_customer', 'حسب العميل', 'sales_returns'),
        ],
      ),
      _ReportCategory(
        id: 'inventory',
        title: 'تقارير المخزون',
        icon: PhosphorIconsBold.warehouse,
        color: AppColors.info,
        mainReports: [
          _ReportEntry(
            id: 'inv_current',
            title: 'تقرير المخزون الحالي',
            subtitle: 'أرصدة وقيم المخزون بالتكلفة والبيع',
            action: () => nav(() => const InventoryReportScreen()),
          ),
          _ReportEntry(
            id: 'inv_gl_reconciliation',
            title: 'تسوية المخزون مع الأستاذ العام',
            subtitle: 'مقارنة قيمة المخزون بحساب 1136 ومصادر الفروق',
            action: _showInventoryGlReconciliation,
          ),
          _ReportEntry(
            id: 'inv_movement',
            title: 'حركة الأصناف',
            subtitle: 'كرت صنف تفصيلي مع كل العمليات',
            action: () => nav(() => const StockMovementsScreen()),
          ),
          _ReportEntry(
            id: 'inv_stocktake',
            title: 'تقرير الجرد',
            subtitle: 'تقرير الجرد الدوري والفروق',
            action: () => nav(() => const StockAuditScreen()),
          ),
          _ReportEntry(
            id: 'inv_top_selling',
            title: 'الأصناف الأكثر مبيعاً',
            subtitle: 'تحليل الأصناف الأعلى طلباً والأكثر ربحية',
            action: () => nav(() => const TopProductsReportScreen()),
          ),
          _ReportEntry(
            id: 'low_stock',
            title: 'أصناف منخفضة المخزون',
            subtitle: 'قائمة الأصناف التي وصلت لحد الطلب',
            action: _showLowStockReport,
          ),
          _ReportEntry(
            id: 'expired_products',
            title: 'منتجات منتهية الصلاحية',
            subtitle: 'قائمة الأصناف التي انتهت صلاحيتها وتحتاج إعدام',
            action: _showExpiredProductsReport,
          ),
          _ReportEntry(
            id: 'expiring_products',
            title: 'منتجات قاربت على الانتهاء',
            subtitle: 'تنتهي صلاحيتها خلال الـ 30 يوماً القادمة',
            action: _showExpiringProductsReport,
          ),
        ],
        shortcuts: const [
          _ReportShortcut('i_low', 'قليلة المخزون', 'low_stock'),
          _ReportShortcut('i_dead', 'الأصناف الراكدة', 'inv_movement'),
        ],
      ),
      _ReportCategory(
        id: 'purchases',
        title: 'تقارير المشتريات',
        icon: PhosphorIconsBold.shoppingCart,
        color: const Color(0xFFD97706),
        mainReports: [
          _ReportEntry(
            id: 'purch_main',
            title: 'تقرير المشتريات',
            subtitle: 'تقرير المشتريات بفلاتر كاملة',
            action: () => nav(() => const PurchasesReportScreen()),
          ),
          _ReportEntry(
            id: 'purch_orders',
            title: 'أوامر الشراء',
            subtitle: 'متابعة أوامر الشراء المفتوحة',
            action: () => nav(() => const ReportBuilderScreen()),
          ),
        ],
        shortcuts: const [
          _ReportShortcut('pu_today', 'مشتريات اليوم', 'purch_main'),
          _ReportShortcut('pu_supplier', 'حسب المورد', 'purch_main'),
          _ReportShortcut('pu_product', 'حسب الصنف', 'purch_main'),
          _ReportShortcut('pu_branch', 'حسب الفرع', 'purch_main'),
        ],
      ),
      _ReportCategory(
        id: 'customers',
        title: 'تقارير العملاء',
        icon: PhosphorIconsBold.users,
        color: const Color(0xFF8B5CF6),
        mainReports: [
          _ReportEntry(
            id: 'cust_statement',
            title: 'كشف حساب العميل',
            subtitle: 'كشف حساب تفصيلي بالحركات',
            action: () =>
                nav(() => const PartyStatementScreen(isCustomer: true)),
          ),
          _ReportEntry(
            id: 'cust_aging',
            title: 'تقادم ذمم العملاء',
            subtitle: 'الذمم المتأخرة بشرائح الأيام',
            action: () => nav(() => const ArAgingReportScreen()),
          ),
          _ReportEntry(
            id: 'cust_behavior',
            title: 'تحليل سلوك العملاء',
            subtitle: 'تكرار الشراء ومتوسط الفاتورة',
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
          _ReportEntry(
            id: 'cust_reconciliation',
            title: 'تسوية الذمم مع الأستاذ العام',
            subtitle: 'مقارنة أرصدة العملاء مع حساب الذمم',
            action: _showArReconciliation,
          ),
        ],
        shortcuts: const [
          _ReportShortcut('c_sales', 'مبيعات العميل', 'cust_statement'),
          _ReportShortcut('c_collect', 'تحصيلات العملاء', 'cust_statement'),
          _ReportShortcut('c_debt', 'العملاء المديونين', 'cust_aging'),
          _ReportShortcut('c_top', 'حسب حجم المبيعات', 'cust_behavior'),
        ],
      ),
      _ReportCategory(
        id: 'suppliers',
        title: 'تقارير الموردين',
        icon: PhosphorIconsBold.truck,
        color: const Color(0xFFEA580C),
        mainReports: [
          _ReportEntry(
            id: 'sup_statement',
            title: 'كشف حساب المورد',
            subtitle: 'كشف تفصيلي بالحركات',
            // دفعة ١٢ — الفئة كلها كانت بتترسم لأي حد معاه reports_view
            // (حقل permission اختياري، ولما يبقى null التايل بيظهر بلا فحص).
            permission: PermissionCodes.reportsSuppliers,
            action: () =>
                nav(() => const PartyStatementScreen(isSupplier: true)),
          ),
          _ReportEntry(
            id: 'sup_behavior',
            title: 'تحليل سلوك الموردين',
            subtitle: 'الموردون النشطون وحجم التعامل',
            permission: PermissionCodes.reportsSuppliers,
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
        ],
        shortcuts: const [
          _ReportShortcut('su_purch', 'مشتريات المورد', 'sup_statement'),
          _ReportShortcut('su_debt', 'مديونية الموردين', 'sup_statement'),
          _ReportShortcut('su_pay', 'دفعات الموردين', 'sup_statement'),
          _ReportShortcut('su_top', 'حسب حجم الشراء', 'sup_behavior'),
        ],
      ),
      _ReportCategory(
        id: 'cashbox',
        title: 'الصناديق والكاش',
        icon: PhosphorIconsBold.wallet,
        color: AppColors.primary,
        mainReports: [
          _ReportEntry(
            id: 'cb_treasury',
            title: 'حركة الخزينة',
            subtitle: 'سجل المقبوضات والمدفوعات والمصروفات',
            permission: PermissionCodes.reportsTreasury,
            action: () => nav(() => const TreasuryReportScreen()),
          ),
          _ReportEntry(
            id: 'cb_shifts',
            title: 'تقرير الورديات',
            subtitle: 'فتح وتسكير الورديات وعجز النقدية',
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const ShiftsReportScreen()),
          ),
          _ReportEntry(
            id: 'cb_delivery',
            title: 'تقرير عمليات التوصيل',
            subtitle: 'إحصائيات المناديب ورسوم شركات التوصيل',
            action: () => nav(() => const DeliveryReportScreen()),
          ),
          _ReportEntry(
            id: 'cb_expenses',
            title: 'تقرير المصروفات التشغيلية',
            subtitle: 'إجمالي المصروفات حسب الفئة والفرع والفترة',
            action: () => nav(() => const ExpensesReportScreen()),
          ),
        ],
        shortcuts: const [
          _ReportShortcut('cb_open', 'فتح وإغلاق الصندوق', 'cb_shifts'),
          _ReportShortcut('cb_diff', 'العجز والزيادة', 'cb_shifts'),
          _ReportShortcut('cb_in_out', 'المقبوضات والمدفوعات', 'cb_treasury'),
          _ReportShortcut('cb_methods', 'نقدي / فيزا / آجل', 'cb_treasury'),
        ],
      ),
      _ReportCategory(
        id: 'users',
        title: 'تقارير المستخدمين',
        icon: PhosphorIconsBold.userCircle,
        color: const Color(0xFF7C3AED),
        mainReports: [
          // ⚠️ الثلاثةُ كانت **بلا `permission:`** حتى 2026-08-13، والمُصيِّر
          // لا يلفّ إلا ما له كود (`r.permission != null` أدناه). فكانت
          // «التقارير» باباً خلفياً: من يملك `reports_view` وحدَه يفتح سجلَّ
          // النشاط، و**شاشةَ إدارة المستخدمين** التي فيها إسنادُ الأدوار
          // وتصفيرُ كلمات المرور — أي تصعيدُ امتيازٍ كامل. والبابُ الأماميُّ
          // لنفس الشاشة محروسٌ في `settings_picpos_screen.dart:654`.
          _ReportEntry(
            id: 'u_activity',
            title: 'نشاط المستخدمين',
            subtitle: 'العمليات لكل مستخدم',
            permission: PermissionCodes.auditView,
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'u_login',
            title: 'سجل دخول المستخدمين',
            subtitle: 'متى دخل كل مستخدم وخرج',
            permission: PermissionCodes.auditView,
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'u_perms',
            title: 'صلاحيات المستخدمين',
            subtitle: 'مصفوفة صلاحيات لكل دور ومستخدم',
            // مهمة 14: هذا الفورك (reports_picpos_screen.dart) خاص بـ PicPos
            // فقط (Brand.isPicPos) — فالـ push يروح مباشرة لشاشة المستخدمين
            // بهوية PicPos، بلا حاجة لفحص العلامة هنا.
            permission: PermissionCodes.usersManage,
            action: () => nav(() => const UsersManagementPicposScreen()),
          ),
        ],
      ),
      _ReportCategory(
        id: 'branches',
        title: 'تقارير الفروع',
        icon: PhosphorIconsBold.buildings,
        color: const Color(0xFF0891B2),
        mainReports: [
          _ReportEntry(
            id: 'br_performance',
            title: 'أداء الفروع',
            subtitle: 'مقارنة مبيعات وأرباح الفروع',
            action: () => nav(() => const BranchPerformanceScreen()),
          ),
          _ReportEntry(
            id: 'br_transfers',
            title: 'التحويلات بين الفروع',
            subtitle: 'سجل التحويلات وحركة المخزون',
            action: () => nav(() => const StockMovementsScreen()),
          ),
        ],
      ),
      _ReportCategory(
        id: 'taxes',
        title: 'تقارير الضرائب',
        icon: PhosphorIconsBold.percent,
        color: const Color(0xFF0369A1),
        mainReports: [
          _ReportEntry(
            id: 'tx_main',
            title: 'تقرير ضريبة المبيعات',
            subtitle: 'الضرائب المحصلة والمدفوعة وصافي الالتزام',
            permission: PermissionCodes.reportsTaxes,
            action: () => nav(() => const TaxReportScreen()),
          ),
          _ReportEntry(
            id: 'tx_vat_recon',
            title: 'تسوية ضريبة القيمة المضافة',
            subtitle: 'مقارنة ضريبة الفواتير مع الأستاذ العام',
            permission: PermissionCodes.reportsTaxes,
            action: () => nav(() => const VatReconciliationScreen()),
          ),
          if (eInvoicePlatform != null)
            _ReportEntry(
              id: 'tx_einvoice',
              title: 'تقرير الفوترة الإلكترونية',
              subtitle: 'متابعة حالات الإرسال والقبول من الضرائب',
              action: () => nav(() => const EInvoiceDashboardScreen()),
            ),
        ],
        shortcuts: const [
          _ReportShortcut('tx_sales', 'ضرائب المبيعات', 'tx_main'),
          _ReportShortcut('tx_purch', 'ضرائب المشتريات', 'tx_main'),
        ],
      ),
      _ReportCategory(
        id: 'audit',
        title: 'الحركة والسجلات',
        icon: PhosphorIconsBold.listChecks,
        color: AppColors.errorDark,
        mainReports: [
          _ReportEntry(
            id: 'a_ops',
            title: 'سجل العمليات',
            subtitle: 'كل العمليات في النظام',
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'a_edits',
            title: 'سجل التعديلات',
            subtitle: 'الفواتير والمستندات المعدلة',
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'a_print',
            title: 'سجل الطباعة',
            subtitle: 'متى طُبع كل مستند ومن قبل من',
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'a_void',
            title: 'سجل الإلغاءات',
            subtitle: 'الفواتير الملغاة وأسبابها',
            action: () => nav(() => const ActivityLogScreen()),
          ),
        ],
      ),
      _ReportCategory(
        id: 'analytics',
        title: 'التحليلات والإحصائيات',
        icon: PhosphorIconsBold.chartDonut,
        color: const Color(0xFFA21CAF),
        mainReports: [
          _ReportEntry(
            id: 'an_sales',
            title: 'تحليل المبيعات',
            subtitle: 'اتجاهات وأنماط المبيعات',
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
          _ReportEntry(
            id: 'an_classifications',
            title: 'المبيعات حسب التصنيف',
            subtitle: 'تحليل المبيعات حسب المجموعات أو أنواع البيع',
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const SalesByClassificationReport()),
          ),
          _ReportEntry(
            id: 'an_financial',
            title: 'القوائم المالية الختامية',
            subtitle: 'الميزانية، قائمة الدخل، وميزان المراجعة (Real-time)',
            action: () => nav(() => Brand.isPicPos
                ? const FinancialStatementsPicPosScreen()
                : const FinancialStatementsScreen()),
          ),
          _ReportEntry(
            id: 'an_customers',
            title: 'تحليل العملاء',
            subtitle: 'تقسيم العملاء (RFM)',
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
          _ReportEntry(
            id: 'an_inventory',
            title: 'تحليل المخزون',
            subtitle: 'دوران وكفاءة المخزون',
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
        ],
      ),
    ];
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

    return PicPosScreenScaffold(
      title: 'التقارير',
      subtitle: 'كل تقارير المبيعات والمخزون والمالية',
      icon: PhosphorIconsBold.chartBar,
      body: LayoutBuilder(
        builder: (context, c) {
          final catCols = _catColumnsFor(c.maxWidth);
          final reportCols = _reportColumnsFor(c.maxWidth);
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _searchBarRow(),
                const SizedBox(height: 18),
                if (isSearching)
                  _searchResultsSection(results, reportCols)
                else ...[
                  if (_favorites.isNotEmpty) ...[
                    _miniHeader(PhosphorIconsBold.star, 'المفضلة',
                        AppColors.warning),
                    const SizedBox(height: 8),
                    _chipsForIds(_favorites.toList()),
                    const SizedBox(height: 16),
                  ],
                  if (_recent.isNotEmpty) ...[
                    _miniHeader(PhosphorIconsBold.clockCounterClockwise,
                        'آخر ما فتحت', AppColors.primary),
                    const SizedBox(height: 8),
                    _chipsForIds(_recent),
                    const SizedBox(height: 20),
                  ],
                  _miniHeader(PhosphorIconsBold.squaresFour,
                      'فئات التقارير', AppColors.textSecondary),
                  const SizedBox(height: 10),
                  _categoriesSection(catCols),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  int _catColumnsFor(double w) {
    if (w >= 1500) return 6;
    if (w >= 1200) return 5;
    if (w >= 900) return 4;
    if (w >= 640) return 3;
    return 2;
  }

  int _reportColumnsFor(double w) {
    if (w >= 1500) return 5;
    if (w >= 1200) return 4;
    if (w >= 900) return 3;
    if (w >= 640) return 2;
    return 1;
  }

  // -----------------------------------------------------------------------
  // Search bar — نفس منطق الأصل، مع عداد إجمالي التقارير بجانبها بدل ما كان
  // شارة داخل _header() القديم (اللي بقى دلوقتي هيدر PicPosScreenScaffold).
  // -----------------------------------------------------------------------
  Widget _searchBarRow() {
    return Row(
      children: [
        Flexible(child: _searchBar()),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_allItems.length} تقرير',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchBar() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'بحث في جميع التقارير...',
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

  Widget _chipsForIds(List<String> ids) {
    final items = ids
        .map((id) => _allItems.where((i) => i.id == id).cast<_FlatItem?>().firstOrNull)
        .whereType<_FlatItem>()
        .toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map(_chip).toList(),
    );
  }

  Widget _chip(_FlatItem item) {
    final c = item.category.color;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openFlatItem(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          border: Border.all(color: c.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.category.icon, size: 11, color: c),
            const SizedBox(width: 5),
            Text(item.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c,
                )),
          ],
        ),
      ),
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
  // Categories — تُعرض كصفوف من الكروت مع لوحة موسّعة inline تحت الصف الذي
  // يحتوي الفئة المفتوحة حالياً. مُغلّفة بـ PicPosContentCard (هوية PicPos)
  // بدل ما كانت طليقة على خلفية الشاشة مباشرة.
  // -----------------------------------------------------------------------
  Widget _categoriesSection(int cols) {
    return PicPosContentCard(
      padding: const EdgeInsets.all(14),
      child: _categoryGrid(cols),
    );
  }

  Widget _categoryGrid(int cols) {
    final rows = <List<_ReportCategory>>[];
    for (int i = 0; i < _categories.length; i += cols) {
      rows.add(_categories.skip(i).take(cols).toList());
    }
    return Column(
      children: [
        for (final row in rows) ...[
          _categoryRow(row, cols),
          if (row.any((c) => c.id == _expandedCatId))
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _expandedPanel(
                _categories.firstWhere((c) => c.id == _expandedCatId),
              ),
            ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _categoryRow(List<_ReportCategory> row, int cols) {
    return Row(
      children: [
        for (var i = 0; i < row.length; i++) ...[
          Expanded(child: _categoryCard(row[i])),
          if (i < row.length - 1) const SizedBox(width: 10),
        ],
        // Pad the trailing slots so the last (partial) row stays aligned
        // with the rows above.
        for (var i = row.length; i < cols; i++) ...[
          const SizedBox(width: 10),
          const Expanded(child: SizedBox.shrink()),
        ],
      ],
    );
  }

  Widget _categoryCard(_ReportCategory cat) {
    final isOpen = _expandedCatId == cat.id;
    return _HoverCard(
      highlighted: isOpen,
      onTap: () => _toggleAccordion(cat),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: isOpen ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(cat.icon, color: cat.color, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(cat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      )),
                  const SizedBox(height: 1),
                  Text(
                    cat.shortcuts.isEmpty
                        ? '${cat.mainReports.length} تقرير'
                        : '${cat.mainReports.length} تقرير • ${cat.shortcuts.length} اختصار',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: isOpen ? -0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(PhosphorIconsBold.caretLeft,
                  size: 12, color: cat.color.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Inline expanded panel (نفس منطق الأصل حرفياً).
  // -----------------------------------------------------------------------
  Widget _expandedPanel(_ReportCategory cat) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cat.color.withValues(alpha: 0.04),
        border: Border.all(color: cat.color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cat.icon, size: 16, color: cat.color),
              const SizedBox(width: 6),
              Text('التقارير الأساسية',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cat.color,
                  )),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _expandedCatId = null),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(PhosphorIconsBold.x,
                      size: 14, color: cat.color.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in cat.mainReports) _expandedReportButton(cat, r),
            ],
          ),
          if (cat.shortcuts.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(PhosphorIconsBold.lightning,
                    size: 13, color: AppColors.warningDark),
                SizedBox(width: 5),
                Text('اختصارات سريعة',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.warningDark,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in cat.shortcuts) _expandedShortcutChip(cat, s),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _expandedReportButton(_ReportCategory cat, _ReportEntry r) {
    final isFav = _favorites.contains(r.id);
    final button = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        _registerOpen(r.id);
        r.action();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: cat.color.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(cat.icon, color: cat.color, size: 15),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      )),
                  Text(r.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        height: 1.2,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _toggleFavorite(r.id),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  isFav ? PhosphorIconsFill.star : PhosphorIconsBold.star,
                  size: 13,
                  color: isFav ? AppColors.warning : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (r.permission != null) {
      return PermissionGuard(
        permission: r.permission!,
        allowManagerOverride: r.allowManagerOverride,
        actionName: r.title,
        child: button,
      );
    }
    return button;
  }

  Widget _expandedShortcutChip(_ReportCategory cat, _ReportShortcut s) {
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
              Text('لا توجد تقارير مطابقة لـ "$_query"',
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
              'نتائج البحث (${results.length})', AppColors.primary),
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
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
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
                          child: const Text('اختصار',
                              style: TextStyle(
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
                tooltip: isFav ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
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
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.error),
              SizedBox(width: 8),
              Text('أصناف منخفضة المخزون'),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: lowStockProducts.isEmpty
                ? const Center(child: Text('لا توجد أصناف منخفضة المخزون 🎉'))
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
                        subtitle: Text('الحد الأدنى: ${p.minStock.toInt()}'),
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
                            p.currentStock <= 0 ? 'نفذ' : 'منخفض',
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
              child: const Text('إغلاق'),
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
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.xCircle, color: AppColors.error),
              SizedBox(width: 8),
              Text('منتجات منتهية الصلاحية'),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: expiredBatches.isEmpty
                ? const Center(
                    child: Text('🎉 لا توجد منتجات منتهية الصلاحية'))
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
                          product?.name ?? 'منتج #${batch.productId}',
                        ),
                        subtitle: Text(
                          'الباتش: ${batch.batchNumber} - انتهى في ${DateFormat('dd/MM/yyyy').format(batch.expiryDate)}',
                        ),
                        trailing: Text(
                          '${batch.quantity.toStringAsFixed(0)} وحدة',
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
              child: const Text('إغلاق'),
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
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.clock, color: AppColors.warning),
              SizedBox(width: 8),
              Text('تنتهي خلال 30 يوم'),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: expiringBatches.isEmpty
                ? const Center(
                    child: Text('🎉 لا توجد منتجات قاربت على الانتهاء'),
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
                          product?.name ?? 'منتج #${batch.productId}',
                        ),
                        subtitle: Text(
                          'الباتش: ${batch.batchNumber} - ينتهي في ${DateFormat('dd/MM/yyyy').format(batch.expiryDate)}',
                        ),
                        trailing: Text(
                          '${batch.quantity.toStringAsFixed(0)} وحدة',
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
              child: const Text('إغلاق'),
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
            title: const Text('تسوية الذمم'),
            content: const Text(
                'لم يتم تعيين حساب الذمم (receivables) في الربط المحاسبي.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
        return;
      }
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('تسوية الذمم مع الأستاذ العام'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'حساب الذمم: ${result.receivablesAccountCode} — ${result.receivablesAccountName}'),
              const Divider(),
              _reconcRow('رصيد بطاقات العملاء', result.totalCardBalance),
              _reconcRow('رصيد الأستاذ العام', result.totalGlBalance),
              const Divider(),
              _reconcRow('الفرق', result.difference,
                  highlight: !result.isBalanced),
              if (result.isBalanced)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                    SizedBox(width: 4),
                    Text('مُتسوٍّ', style: TextStyle(color: Colors.green)),
                  ]),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.warning, color: Colors.orange, size: 16),
                    SizedBox(width: 4),
                    Text('يوجد فرق — راجع القيود',
                        style: TextStyle(color: Colors.orange)),
                  ]),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
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
            title: const Text('تسوية المخزون'),
            content: const Text(
                'لم يتم تعيين حساب المخزون (inventory) في الربط المحاسبي.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
        return;
      }
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('تسوية المخزون مع الأستاذ العام'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'حساب المخزون: ${result.inventoryAccountCode} — ${result.inventoryAccountName}'),
              const Divider(),
              _reconcRow('قيمة المخزون (بالتكلفة)', result.reportValue),
              _reconcRow('رصيد الأستاذ العام', result.glBalance),
              const Divider(),
              _reconcRow('الفرق', result.delta, highlight: !result.isBalanced),
              const SizedBox(height: 8),
              const Text('مصادر الفروق المحتملة:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              _reconcRow('فرق أساس التكلفة (متوسط المخزن مقابل التكلفة)',
                  result.costBasisDivergence),
              _reconcRow('فرق الرصيد الدفتري مقابل حركات المخازن',
                  result.stockVsLedgerDivergence),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    'أصناف بتكلفة صفر لها رصيد: ${result.zeroCostItemCount} صنف '
                    '(كمية ${result.zeroCostStockQty.toStringAsFixed(2)})'),
              ),
              if (result.isBalanced)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                    SizedBox(width: 4),
                    Text('مُتسوٍّ', style: TextStyle(color: Colors.green)),
                  ]),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.warning, color: Colors.orange, size: 16),
                    SizedBox(width: 4),
                    Text('يوجد فرق — راجع مصادر الفروق أعلاه',
                        style: TextStyle(color: Colors.orange)),
                  ]),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
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
              color: highlight ? Colors.red : null,
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
  final bool highlighted;

  const _HoverCard({
    required this.child,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final showActive = widget.highlighted || _hover;
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
class _ReportCategory {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<_ReportEntry> mainReports;
  final List<_ReportShortcut> shortcuts;

  const _ReportCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.mainReports,
    this.shortcuts = const [],
  });
}

class _ReportEntry {
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

  const _ReportEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.action,
    this.permission,
  });
}

class _ReportShortcut {
  final String id;
  final String title;
  final String parentReportId;

  /// Destination for shortcuts that lead somewhere OTHER than their parent
  /// report. Without this every shortcut fell through to `parent.action()`,
  /// so «حسب المجموعة» opened the plain sales report — the by-category report
  /// existed and was reachable elsewhere, but this chip never went there,
  /// which read to users as "the report is missing".
  final VoidCallback? action;

  const _ReportShortcut(this.id, this.title, this.parentReportId,
      {this.action});
}

class _FlatItem {
  final String id;
  final String title;
  final String subtitle;
  final _ReportCategory category;
  final bool isShortcut;
  const _FlatItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.isShortcut,
  });
}

List<_FlatItem> _flatten(List<_ReportCategory> cats) {
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
