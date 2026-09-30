import 'package:ural_erp/core/i18n/tr.dart';
// ---------------------------------------------------------------------------
// Reports launcher — feature 055.
//
// Replaces the legacy flat-ListView launcher with a 13-category grid +
// popover dropdowns + global search + persisted favorites + persisted
// recents. See /specs/055-reports-launcher-redesign for spec, plan, and
// contracts.
//
// File layout (top → bottom):
//   1. Imports
//   2. ReportsScreen widget + _ReportsScreenState
//   3. _PopoverPanel widget
//   4. _HoverCard widget
//   5. Data classes (_ReportCategory, _ReportEntry, _ReportShortcut,
//      _FlatItem)
// ---------------------------------------------------------------------------

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/permissions/permission_codes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/e_invoicing_providers.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/report_providers.dart';
import '../../data/providers/reconciliation_provider.dart';
import '../widgets/permission_guard.dart';

// Destination screens — existing in the codebase, unchanged by this feature.
import 'activity_log_screen.dart';
import 'analytics_dashboard_screen.dart';
import 'branch_performance_screen.dart';
import 'e_invoice_dashboard_screen.dart';
import 'party_statement_screen.dart';
import 'report_builder_screen.dart';
import 'reports/ar_aging_report_screen.dart';
import 'reports/category_profit_report_screen.dart';
import 'reports/consumption_report_screen.dart';
import 'reports/delivery_report_screen.dart';
import 'reports/expenses_report_screen.dart';
import 'reports/financial_statements_screen.dart';
import 'reports/inventory_report_screen.dart';
import 'reports/purchase_returns_report_screen.dart';
import 'reports/purchases_report_screen.dart';
import 'reports/sales_by_classification_report.dart';
import 'reports/sales_report_screen.dart';
import 'reports/sales_returns_report_screen.dart';
import 'reports/shifts_report_screen.dart';
import 'reports/tables_report_screen.dart';
import 'reports/tax_report_screen.dart';
import 'reports/top_products_report_screen.dart';
import 'reports/treasury_report_screen.dart';
import 'reports/vat_reconciliation_screen.dart';
import 'stock_audit_screen.dart';
import 'stock_movements_screen.dart';
import 'users_management_screen.dart';

// ---------------------------------------------------------------------------
const String _kPrefFavoritesKey = 'reports_favorites';
const String _kPrefRecentKey = 'reports_recent';
const int _kRecentCap = 6;

// ---------------------------------------------------------------------------
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
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
  // Persistence (per /contracts/persistence-contract.md)
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
  // Category catalog (per /contracts/destination-mapping.md)
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
        title: tr('تقارير المبيعات'),
        icon: PhosphorIconsBold.chartLineUp,
        color: AppColors.success,
        mainReports: [
          _ReportEntry(
            id: 'sales_main',
            title: tr('تقرير المبيعات'),
            subtitle: tr('تقرير المبيعات الرئيسي بكافة الفلاتر'),
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const SalesReportScreen()),
          ),
          _ReportEntry(
            id: 'sales_summary',
            title: tr('ملخص المبيعات'),
            subtitle: tr('نظرة سريعة بأرقام اليوم'),
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const SalesReportScreen()),
          ),
          // ⚠️ توأمُه في `reports_picpos/screens/reports_picpos_screen.dart`
          // لا بدّ أن يُضاف معه — كتالوجٌ واحدٌ بلا الآخر يعني تقريراً يظهر
          // في هويّةٍ ويغيب عن الأخرى.
          _ReportEntry(
            id: 'tables_report',
            title: tr('تقرير الطاولات'),
            subtitle: tr('الإيراد ودوران الطاولة ونصيب الضيف لكل قسم وطاولة'),
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const TablesReportScreen()),
          ),
        ],
        shortcuts: [
           _ReportShortcut('s_today', tr('مبيعات اليوم'), 'sales_main'),
           _ReportShortcut('s_range', tr('من تاريخ إلى تاريخ'), 'sales_main'),
           _ReportShortcut('s_cashier', tr('حسب الكاشير'), 'sales_main'),
           _ReportShortcut('s_branch', tr('حسب الفرع'), 'sales_main'),
          _ReportShortcut('s_product', tr('حسب الصنف'), 'sales_main',
              action: () => nav(() => const TopProductsReportScreen())),
          _ReportShortcut('s_group', tr('حسب المجموعة'), 'sales_main',
              action: () => nav(() => const SalesByClassificationReport())),
           _ReportShortcut('s_payment', tr('حسب طريقة الدفع'), 'sales_main'),
           _ReportShortcut(
              's_credit', tr('مبيعات آجل / نقدي / فيزا'), 'sales_main'),
        ],
      ),
      _ReportCategory(
        id: 'profit',
        title: tr('تقارير الأرباح'),
        icon: PhosphorIconsBold.money,
        color: AppColors.successDark,
        mainReports: [
          _ReportEntry(
            id: 'category_profit',
            title: tr('أرباح التصنيفات'),
            subtitle: tr('تحليل تكلفة المبيعات وصافي الربح لكل تصنيف'),
            permission: 'reports_category_profit',
            action: () => nav(() => const CategoryProfitReportScreen()),
          ),
          _ReportEntry(
            id: 'consumption',
            title: tr('تقرير استهلاك الخامات'),
            subtitle: tr('استهلاك الخامات وربحية المنتجات (auto-deplete)'),
            permission: 'reports_category_profit',
            action: () => nav(() => const ConsumptionReportScreen()),
          ),
          _ReportEntry(
            id: 'top_profitable',
            title: tr('الأصناف الأكثر ربحية'),
            subtitle: tr('ترتيب المنتجات حسب الربح'),
            action: () => nav(() => const TopProductsReportScreen()),
          ),
          _ReportEntry(
            id: 'profit_margin',
            title: tr('هامش الربح'),
            subtitle: tr('تحليل هامش الربح حسب الفئة'),
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
        ],
        shortcuts: [
           _ReportShortcut('p_invoice', tr('ربح كل فاتورة'), 'category_profit'),
          _ReportShortcut('p_product', tr('ربح كل صنف'), 'category_profit',
              action: () => nav(() => const TopProductsReportScreen())),
          _ReportShortcut('p_group', tr('حسب المجموعة'), 'category_profit',
              action: () => nav(() => const CategoryProfitReportScreen())),
           _ReportShortcut('p_cashier', tr('حسب الكاشير'), 'category_profit'),
           _ReportShortcut('p_branch', tr('حسب الفرع'), 'category_profit'),
        ],
      ),
      _ReportCategory(
        id: 'returns',
        title: tr('تقارير المرتجعات'),
        icon: PhosphorIconsBold.arrowUUpLeft,
        color: AppColors.error,
        mainReports: [
          _ReportEntry(
            id: 'sales_returns',
            title: tr('مرتجعات المبيعات'),
            subtitle: tr('تحليل مرتجعات المبيعات والمبالغ المستردة'),
            action: () => nav(() => const SalesReturnsReportScreen()),
          ),
          _ReportEntry(
            id: 'purchase_returns',
            title: tr('مرتجعات المشتريات'),
            subtitle: tr('تحليل مرتجعات المشتريات من الموردين'),
            action: () => nav(() => const PurchaseReturnsReportScreen()),
          ),
        ],
        shortcuts:  [
          _ReportShortcut('r_today', tr('مرتجعات اليوم'), 'sales_returns'),
          _ReportShortcut('r_cashier', tr('حسب الكاشير'), 'sales_returns'),
          _ReportShortcut('r_product', tr('حسب الصنف'), 'sales_returns'),
          _ReportShortcut('r_customer', tr('حسب العميل'), 'sales_returns'),
        ],
      ),
      _ReportCategory(
        id: 'inventory',
        title: tr('تقارير المخزون'),
        icon: PhosphorIconsBold.warehouse,
        color: AppColors.info,
        mainReports: [
          _ReportEntry(
            id: 'inv_current',
            title: tr('تقرير المخزون الحالي'),
            subtitle: tr('أرصدة وقيم المخزون بالتكلفة والبيع'),
            action: () => nav(() => const InventoryReportScreen()),
          ),
          _ReportEntry(
            id: 'inv_gl_reconciliation',
            title: tr('تسوية المخزون مع الأستاذ العام'),
            subtitle: tr('مقارنة قيمة المخزون بحساب 1136 ومصادر الفروق'),
            action: _showInventoryGlReconciliation,
          ),
          _ReportEntry(
            id: 'inv_movement',
            title: tr('حركة الأصناف'),
            subtitle: tr('كرت صنف تفصيلي مع كل العمليات'),
            action: () => nav(() => const StockMovementsScreen()),
          ),
          _ReportEntry(
            id: 'inv_stocktake',
            title: tr('تقرير الجرد'),
            subtitle: tr('تقرير الجرد الدوري والفروق'),
            action: () => nav(() => const StockAuditScreen()),
          ),
          _ReportEntry(
            id: 'inv_top_selling',
            title: tr('الأصناف الأكثر مبيعاً'),
            subtitle: tr('تحليل الأصناف الأعلى طلباً والأكثر ربحية'),
            action: () => nav(() => const TopProductsReportScreen()),
          ),
          _ReportEntry(
            id: 'low_stock',
            title: tr('أصناف منخفضة المخزون'),
            subtitle: tr('قائمة الأصناف التي وصلت لحد الطلب'),
            action: _showLowStockReport,
          ),
          _ReportEntry(
            id: 'expired_products',
            title: tr('منتجات منتهية الصلاحية'),
            subtitle: tr('قائمة الأصناف التي انتهت صلاحيتها وتحتاج إعدام'),
            action: _showExpiredProductsReport,
          ),
          _ReportEntry(
            id: 'expiring_products',
            title: tr('منتجات قاربت على الانتهاء'),
            subtitle: tr('تنتهي صلاحيتها خلال الـ 30 يوماً القادمة'),
            action: _showExpiringProductsReport,
          ),
        ],
        shortcuts:  [
          _ReportShortcut('i_low', tr('قليلة المخزون'), 'low_stock'),
          _ReportShortcut('i_dead', tr('الأصناف الراكدة'), 'inv_movement'),
        ],
      ),
      _ReportCategory(
        id: 'purchases',
        title: tr('تقارير المشتريات'),
        icon: PhosphorIconsBold.shoppingCart,
        color: const Color(0xFFD97706),
        mainReports: [
          _ReportEntry(
            id: 'purch_main',
            title: tr('تقرير المشتريات'),
            subtitle: tr('تقرير المشتريات بفلاتر كاملة'),
            action: () => nav(() => const PurchasesReportScreen()),
          ),
          _ReportEntry(
            id: 'purch_orders',
            title: tr('أوامر الشراء'),
            subtitle: tr('متابعة أوامر الشراء المفتوحة'),
            action: () => nav(() => const ReportBuilderScreen()),
          ),
        ],
        shortcuts:  [
          _ReportShortcut('pu_today', tr('مشتريات اليوم'), 'purch_main'),
          _ReportShortcut('pu_supplier', tr('حسب المورد'), 'purch_main'),
          _ReportShortcut('pu_product', tr('حسب الصنف'), 'purch_main'),
          _ReportShortcut('pu_branch', tr('حسب الفرع'), 'purch_main'),
        ],
      ),
      _ReportCategory(
        id: 'customers',
        title: tr('تقارير العملاء'),
        icon: PhosphorIconsBold.users,
        color: const Color(0xFF8B5CF6),
        mainReports: [
          _ReportEntry(
            id: 'cust_statement',
            title: tr('كشف حساب العميل'),
            subtitle: tr('كشف حساب تفصيلي بالحركات'),
            action: () =>
                nav(() => const PartyStatementScreen(isCustomer: true)),
          ),
          _ReportEntry(
            id: 'cust_aging',
            title: tr('تقادم ذمم العملاء'),
            subtitle: tr('الذمم المتأخرة بشرائح الأيام'),
            action: () => nav(() => const ArAgingReportScreen()),
          ),
          _ReportEntry(
            id: 'cust_behavior',
            title: tr('تحليل سلوك العملاء'),
            subtitle: tr('تكرار الشراء ومتوسط الفاتورة'),
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
          _ReportEntry(
            id: 'cust_reconciliation',
            title: tr('تسوية الذمم مع الأستاذ العام'),
            subtitle: tr('مقارنة أرصدة العملاء مع حساب الذمم'),
            action: _showArReconciliation,
          ),
        ],
        shortcuts:  [
          _ReportShortcut('c_sales', tr('مبيعات العميل'), 'cust_statement'),
          _ReportShortcut('c_collect', tr('تحصيلات العملاء'), 'cust_statement'),
          _ReportShortcut('c_debt', tr('العملاء المديونين'), 'cust_aging'),
          _ReportShortcut('c_top', tr('حسب حجم المبيعات'), 'cust_behavior'),
        ],
      ),
      _ReportCategory(
        id: 'suppliers',
        title: tr('تقارير الموردين'),
        icon: PhosphorIconsBold.truck,
        color: const Color(0xFFEA580C),
        mainReports: [
          _ReportEntry(
            id: 'sup_statement',
            title: tr('كشف حساب المورد'),
            subtitle: tr('كشف تفصيلي بالحركات'),
            // دفعة ١٢ — الفئة كلها كانت بتترسم لأي حد معاه reports_view
            // (حقل permission اختياري، ولما يبقى null التايل بيظهر بلا فحص).
            permission: PermissionCodes.reportsSuppliers,
            action: () =>
                nav(() => const PartyStatementScreen(isSupplier: true)),
          ),
          _ReportEntry(
            id: 'sup_behavior',
            title: tr('تحليل سلوك الموردين'),
            subtitle: tr('الموردون النشطون وحجم التعامل'),
            permission: PermissionCodes.reportsSuppliers,
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
        ],
        shortcuts:  [
          _ReportShortcut('su_purch', tr('مشتريات المورد'), 'sup_statement'),
          _ReportShortcut('su_debt', tr('مديونية الموردين'), 'sup_statement'),
          _ReportShortcut('su_pay', tr('دفعات الموردين'), 'sup_statement'),
          _ReportShortcut('su_top', tr('حسب حجم الشراء'), 'sup_behavior'),
        ],
      ),
      _ReportCategory(
        id: 'cashbox',
        title: tr('الصناديق والكاش'),
        icon: PhosphorIconsBold.wallet,
        color: AppColors.primary,
        mainReports: [
          _ReportEntry(
            id: 'cb_treasury',
            title: tr('حركة الخزينة'),
            subtitle: tr('سجل المقبوضات والمدفوعات والمصروفات'),
            permission: PermissionCodes.reportsTreasury,
            action: () => nav(() => const TreasuryReportScreen()),
          ),
          _ReportEntry(
            id: 'cb_shifts',
            title: tr('تقرير الورديات'),
            subtitle: tr('فتح وتسكير الورديات وعجز النقدية'),
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const ShiftsReportScreen()),
          ),
          _ReportEntry(
            id: 'cb_delivery',
            title: tr('تقرير عمليات التوصيل'),
            subtitle: tr('إحصائيات المناديب ورسوم شركات التوصيل'),
            action: () => nav(() => const DeliveryReportScreen()),
          ),
          _ReportEntry(
            id: 'cb_expenses',
            title: tr('تقرير المصروفات التشغيلية'),
            subtitle: tr('إجمالي المصروفات حسب الفئة والفرع والفترة'),
            action: () => nav(() => const ExpensesReportScreen()),
          ),
        ],
        shortcuts:  [
          _ReportShortcut('cb_open', tr('فتح وإغلاق الصندوق'), 'cb_shifts'),
          _ReportShortcut('cb_diff', tr('العجز والزيادة'), 'cb_shifts'),
          _ReportShortcut('cb_in_out', tr('المقبوضات والمدفوعات'), 'cb_treasury'),
          _ReportShortcut('cb_methods', tr('نقدي / فيزا / آجل'), 'cb_treasury'),
        ],
      ),
      _ReportCategory(
        id: 'users',
        title: tr('تقارير المستخدمين'),
        icon: PhosphorIconsBold.userCircle,
        color: const Color(0xFF7C3AED),
        mainReports: [
          _ReportEntry(
            id: 'u_activity',
            title: tr('نشاط المستخدمين'),
            subtitle: tr('العمليات لكل مستخدم'),
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'u_login',
            title: tr('سجل دخول المستخدمين'),
            subtitle: tr('متى دخل كل مستخدم وخرج'),
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'u_perms',
            title: tr('صلاحيات المستخدمين'),
            subtitle: tr('مصفوفة صلاحيات لكل دور ومستخدم'),
            action: () => nav(() => const UsersManagementScreen()),
          ),
        ],
      ),
      _ReportCategory(
        id: 'branches',
        title: tr('تقارير الفروع'),
        icon: PhosphorIconsBold.buildings,
        color: const Color(0xFF0891B2),
        mainReports: [
          _ReportEntry(
            id: 'br_performance',
            title: tr('أداء الفروع'),
            subtitle: tr('مقارنة مبيعات وأرباح الفروع'),
            action: () => nav(() => const BranchPerformanceScreen()),
          ),
          _ReportEntry(
            id: 'br_transfers',
            title: tr('التحويلات بين الفروع'),
            subtitle: tr('سجل التحويلات وحركة المخزون'),
            action: () => nav(() => const StockMovementsScreen()),
          ),
        ],
      ),
      _ReportCategory(
        id: 'taxes',
        title: tr('تقارير الضرائب'),
        icon: PhosphorIconsBold.percent,
        color: const Color(0xFF0369A1),
        mainReports: [
          _ReportEntry(
            id: 'tx_main',
            title: tr('تقرير ضريبة المبيعات'),
            subtitle: tr('الضرائب المحصلة والمدفوعة وصافي الالتزام'),
            permission: PermissionCodes.reportsTaxes,
            action: () => nav(() => const TaxReportScreen()),
          ),
          _ReportEntry(
            id: 'tx_vat_recon',
            title: tr('تسوية ضريبة القيمة المضافة'),
            subtitle: tr('مقارنة ضريبة الفواتير مع الأستاذ العام'),
            permission: PermissionCodes.reportsTaxes,
            action: () => nav(() => const VatReconciliationScreen()),
          ),
          if (eInvoicePlatform != null)
            _ReportEntry(
              id: 'tx_einvoice',
              title: tr('تقرير الفوترة الإلكترونية'),
              subtitle: tr('متابعة حالات الإرسال والقبول من الضرائب'),
              action: () => nav(() => const EInvoiceDashboardScreen()),
            ),
        ],
        shortcuts:  [
          _ReportShortcut('tx_sales', tr('ضرائب المبيعات'), 'tx_main'),
          _ReportShortcut('tx_purch', tr('ضرائب المشتريات'), 'tx_main'),
        ],
      ),
      _ReportCategory(
        id: 'audit',
        title: tr('الحركة والسجلات'),
        icon: PhosphorIconsBold.listChecks,
        color: AppColors.errorDark,
        mainReports: [
          _ReportEntry(
            id: 'a_ops',
            title: tr('سجل العمليات'),
            subtitle: tr('كل العمليات في النظام'),
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'a_edits',
            title: tr('سجل التعديلات'),
            subtitle: tr('الفواتير والمستندات المعدلة'),
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'a_print',
            title: tr('سجل الطباعة'),
            subtitle: tr('متى طُبع كل مستند ومن قبل من'),
            action: () => nav(() => const ActivityLogScreen()),
          ),
          _ReportEntry(
            id: 'a_void',
            title: tr('سجل الإلغاءات'),
            subtitle: tr('الفواتير الملغاة وأسبابها'),
            action: () => nav(() => const ActivityLogScreen()),
          ),
        ],
      ),
      _ReportCategory(
        id: 'analytics',
        title: tr('التحليلات والإحصائيات'),
        icon: PhosphorIconsBold.chartDonut,
        color: const Color(0xFFA21CAF),
        mainReports: [
          _ReportEntry(
            id: 'an_sales',
            title: tr('تحليل المبيعات'),
            subtitle: tr('اتجاهات وأنماط المبيعات'),
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
          _ReportEntry(
            id: 'an_classifications',
            title: tr('المبيعات حسب التصنيف'),
            subtitle: tr('تحليل المبيعات حسب المجموعات أو أنواع البيع'),
            permission: PermissionCodes.reportsSales,
            action: () => nav(() => const SalesByClassificationReport()),
          ),
          _ReportEntry(
            id: 'an_financial',
            title: tr('القوائم المالية الختامية'),
            subtitle: tr('الميزانية، قائمة الدخل، وميزان المراجعة (Real-time)'),
            action: () => nav(() => const FinancialStatementsScreen()),
          ),
          _ReportEntry(
            id: 'an_customers',
            title: tr('تحليل العملاء'),
            subtitle: tr('تقسيم العملاء (RFM)'),
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
          _ReportEntry(
            id: 'an_inventory',
            title: tr('تحليل المخزون'),
            subtitle: tr('دوران وكفاءة المخزون'),
            action: () => nav(() => const AnalyticsDashboardScreen()),
          ),
        ],
      ),
    ];
  }

  // -----------------------------------------------------------------------
  // Build
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

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: LayoutBuilder(
          builder: (context, c) {
            final catCols = _catColumnsFor(c.maxWidth);
            final reportCols = _reportColumnsFor(c.maxWidth);
            return SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 18),
                  _searchBar(),
                  const SizedBox(height: 20),
                  if (isSearching)
                    _searchResults(results, reportCols)
                  else ...[
                    if (_favorites.isNotEmpty) ...[
                      _miniHeader(PhosphorIconsBold.star, tr('المفضلة'),
                          AppColors.warning),
                      const SizedBox(height: 8),
                      _chipsForIds(_favorites.toList()),
                      const SizedBox(height: 16),
                    ],
                    if (_recent.isNotEmpty) ...[
                      _miniHeader(PhosphorIconsBold.clockCounterClockwise,
                          tr('آخر ما فتحت'), AppColors.primary),
                      const SizedBox(height: 8),
                      _chipsForIds(_recent),
                      const SizedBox(height: 20),
                    ],
                    _miniHeader(PhosphorIconsBold.squaresFour,
                        tr('فئات التقارير'), AppColors.textSecondary),
                    const SizedBox(height: 10),
                    _categoryGrid(catCols),
                  ],
                ],
              ),
            );
          },
        ),
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
  // Header + search
  // -----------------------------------------------------------------------
  Widget _header() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(PhosphorIconsBold.chartBar,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Text(tr('التقارير والإحصائيات'),
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.headlineMedium?.color,
            )),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            tr('{p0} تقرير', {'p0': _allItems.length}),
            style: const TextStyle(
              fontSize: 10.5,
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
              fontSize: 13,
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
                  fontSize: 11,
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
  // Categories — rendered as rows of cards with an inline expanded panel
  // beneath the row containing the currently expanded category. Replaces the
  // old popover overlay per user feedback (2026-05-15).
  // -----------------------------------------------------------------------
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
        padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 10, 8),
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
                        fontSize: 12.5,
                      )),
                  const SizedBox(height: 1),
                  Text(
                    cat.shortcuts.isEmpty
                        ? tr('{p0} تقرير', {'p0': cat.mainReports.length})
                        : tr('{p0} تقرير • {p1} اختصار', {'p0': cat.mainReports.length, 'p1': cat.shortcuts.length}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
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
  // Inline expanded panel (replaces the old popover overlay).
  // -----------------------------------------------------------------------
  Widget _expandedPanel(_ReportCategory cat) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 16),
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
              Text(tr('التقارير الأساسية'),
                  style: TextStyle(
                    fontSize: 12,
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
             Row(
              children: [
                const Icon(PhosphorIconsBold.lightning,
                    size: 13, color: AppColors.warningDark),
                const SizedBox(width: 5),
                Text(tr('اختصارات سريعة'),
                    style: const TextStyle(
                      fontSize: 11,
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
        padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 10, 8),
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
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      )),
                  Text(r.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
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
                  fontSize: 11,
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
  // Search results
  // -----------------------------------------------------------------------
  Widget _searchResults(List<_FlatItem> results, int cols) {
    if (results.isEmpty) {
      return Padding(
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
    return Column(
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
                              fontSize: 12,
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
                                fontSize: 8.5,
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
                        fontSize: 10,
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
  // Inline dialog reports (migrated from legacy launcher)
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
                              fontSize: 12,
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
                  tr('حساب المخزون: {p0} — {p1}', {'p0': result.inventoryAccountCode, 'p1': trData(result.inventoryAccountName)})),
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
                    tr('أصناف بتكلفة صفر لها رصيد: {p0} صنف (كمية {p1})', {'p0': result.zeroCostItemCount, 'p1': result.zeroCostStockQty.toStringAsFixed(2)})),
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
// _HoverCard — reusable hover-aware container card.
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
// Data classes
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
