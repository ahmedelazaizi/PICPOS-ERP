// ignore_for_file: avoid_dynamic_calls

import 'data/providers/screen_navigation_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'core/config/app_config.dart';
import 'core/config/business_profile_provider.dart';
import 'core/enums/app_screen.dart';
import 'domain/models/screen_tabs.dart';
import 'presentation/shell/screen_tabs_bar.dart';
import 'core/utils/logger.dart';
import 'data/providers/providers.dart';
import 'services/license_service.dart';
import 'services/permission_sync_bridge.dart';
import 'presentation/shell/app_shell.dart';
import 'core/config/brand.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'presentation/pos/screens/pos_main_screen.dart';
import 'presentation/pos_picpos/screens/picpos_pos_screen.dart';
import 'presentation/offers_picpos/offers_picpos_screen.dart';
import 'presentation/accounting_picpos/journal_templates_picpos_screen.dart';
import 'presentation/accounting_picpos/account_mapping_picpos_screen.dart';
import 'presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart';
import 'presentation/accounting_picpos/chart_of_accounts_picpos_screen.dart';
import 'presentation/accounting_picpos/cost_centers_picpos_screen.dart';
import 'presentation/accounting_picpos/general_ledger_picpos_screen.dart';
import 'core/navigation/screen_id.dart';
import 'core/navigation/default_screen_resolver.dart';
import 'core/navigation/dirty_screens_registry.dart';
import 'presentation/shell/no_screens_available_view.dart';
import 'presentation/accounting_picpos/journal_entries_picpos_screen.dart';
import 'presentation/accounting_picpos/financial_statements_picpos_screen.dart';
import 'presentation/analytics_picpos/financial_indicators_picpos_screen.dart';
import 'presentation/screens/reports/financial_statements_screen.dart';
import 'services/shift_dialog_session_guard.dart';
// Spec 135 NOTE 1 — SessionTimeoutWrapper (POS lock screen, System B) retired;
// session timeout is handled app-wide by InactivityDetector (System A).
import 'presentation/widgets/auth/security_gate_wrapper.dart';
import 'presentation/widgets/omnibox/global_search_omnibox.dart';
import 'presentation/pos/providers/cart_controller.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart';
import 'presentation/screens/sales_invoices_screen.dart';
import 'presentation/sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart';
import 'presentation/screens/unified_parties_screen.dart';
import 'presentation/parties_picpos/screens/parties_picpos_screen.dart';
import 'presentation/distribution_picpos/screens/rep_distribution_picpos_screen.dart';
import 'presentation/hr_picpos/screens/hr_employees_picpos_screen.dart';
import 'presentation/hr_picpos/screens/hr_organization_picpos_screen.dart';
import 'presentation/hr_picpos/screens/hr_attendance_picpos_screen.dart';
import 'presentation/hr_picpos/screens/hr_leave_picpos_screen.dart';
import 'presentation/hr_picpos/screens/hr_shifts_picpos_screen.dart';
import 'presentation/hr_picpos/screens/hr_payroll_picpos_screen.dart';
import 'presentation/hr_picpos/screens/hr_advances_picpos_screen.dart';
import 'presentation/hr_picpos/screens/hr_commissions_picpos_screen.dart';
import 'presentation/screens/inventory/inventory_screen.dart';
import 'presentation/inventory_picpos/screens/inventory_picpos_screen.dart';
import 'presentation/screens/purchase_invoices_screen.dart';
import 'presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
import 'presentation/screens/treasury_screen.dart';
import 'presentation/treasury_picpos/screens/treasury_picpos_screen.dart';
import 'presentation/bookings_picpos/screens/bookings_picpos_screen.dart';
import 'presentation/template_resolution_picpos/screens/template_resolution_picpos_screen.dart';
import 'presentation/screens/reports_screen.dart';
import 'presentation/reports_picpos/screens/reports_picpos_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/settings_picpos/screens/settings_picpos_screen.dart';
import 'presentation/screens/branch_management_screen.dart';
import 'presentation/settings_picpos/screens/branches_picpos_screen.dart';
import 'presentation/screens/region_management_screen.dart';
import 'presentation/kitchen/screens/kitchen_display_screen.dart';
import 'presentation/screens/offers_screen.dart';
import 'presentation/screens/tables_screen.dart';
import 'presentation/tables_picpos/screens/tables_picpos_screen.dart';
import 'presentation/screens/products_screen.dart';
import 'presentation/products_picpos/screens/products_picpos_screen.dart';
import 'presentation/screens/categories_screen.dart';
import 'presentation/categories_picpos/screens/categories_picpos_screen.dart';
import 'presentation/screens/analytics_dashboard_screen.dart';
import 'presentation/analytics_picpos/screens/analytics_picpos_screen.dart';
import 'presentation/screens/hr_screen.dart';
import 'presentation/screens/activity_log_screen.dart';
import 'presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart';
import 'presentation/screens/inventory/inventory_bonds_screen.dart';
import 'presentation/inventory_bonds_picpos/screens/inventory_bonds_picpos_screen.dart';
import 'presentation/screens/inventory/stock_transfer_screen.dart';
import 'presentation/stock_transfer_picpos/screens/stock_transfer_picpos_screen.dart';
import 'presentation/screens/inventory/stock_requisitions_screen.dart';
import 'presentation/screens/scale_plu_export_screen.dart';
import 'presentation/scale_plu_picpos/screens/scale_plu_picpos_screen.dart';
import 'presentation/screens/e_invoice_dashboard_screen.dart';
import 'presentation/e_invoicing_picpos/screens/e_invoicing_picpos_screen.dart';
import 'presentation/screens/loyalty_screen.dart';
import 'presentation/screens/distribution_screen.dart';
import 'presentation/settings_picpos/screens/distribution_picpos_screen.dart';

import 'presentation/screens/manufacturing_screen.dart';
import 'presentation/manufacturing_picpos/manufacturing_picpos_screen.dart';
import 'presentation/screens/operational_expenses_screen.dart';
import 'presentation/screens/chart_of_accounts_screen.dart';
import 'presentation/screens/fiscal_year_screen.dart';
import 'presentation/screens/account_mapping_settings_screen.dart';
import 'presentation/screens/journal_entries_screen.dart';
import 'presentation/screens/cost_centers_screen.dart';
import 'presentation/screens/stock_movements_screen.dart';
import 'presentation/screens/purchase_orders_screen.dart';
import 'presentation/screens/commercial_papers_screen.dart';
import 'presentation/settings_picpos/screens/cheques_picpos_screen.dart';
import 'presentation/screens/fixed_assets_screen.dart';
import 'presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart';
import 'presentation/accounting_picpos/journal_voucher_picpos_screen.dart';
import 'presentation/treasury_picpos/screens/voucher_records_picpos_screen.dart';
import 'domain/models/document_record.dart';
import 'presentation/treasury_picpos/screens/cheque_books_picpos_screen.dart';
import 'presentation/fixed_assets_picpos/screens/asset_categories_picpos_screen.dart';
import 'presentation/fixed_assets_picpos/screens/asset_locations_picpos_screen.dart';
import 'presentation/opex_picpos/screens/opex_picpos_screen.dart';
import 'presentation/screens/general_ledger_screen.dart';
import 'presentation/screens/sales_orders_screen.dart';
import 'presentation/screens/branch_performance_screen.dart';
import 'presentation/screens/help_center_screen.dart';
import 'presentation/screens/landed_cost_screen.dart';
import 'presentation/landed_cost_picpos/screens/landed_cost_picpos_screen.dart';
import 'presentation/import_purchases_picpos/screens/import_purchases_picpos_screen.dart';
import 'presentation/floor_plan_picpos/screens/floor_plan_designer_picpos_screen.dart';
import 'presentation/screens/cycle_count_screen.dart';
import 'presentation/cycle_count_picpos/screens/cycle_count_picpos_screen.dart';
import 'presentation/screens/report_builder_screen.dart';
import 'presentation/report_builder_picpos/screens/report_builder_picpos_screen.dart';
import 'presentation/screens/sales_returns_screen.dart';
import 'presentation/sales_returns_picpos/screens/sales_return_records_picpos_screen.dart';
import 'presentation/screens/purchase_returns_screen.dart';
import 'presentation/purchase_returns_picpos/screens/purchase_return_records_picpos_screen.dart';
import 'presentation/screens/shift_close_screen.dart';
import 'presentation/shift_close_picpos/screens/shift_close_picpos_screen.dart';
import 'presentation/screens/sync/sync_conflicts_screen.dart';
import 'presentation/screens/audit/audit_dashboard_screen.dart';
import 'main_desktop.dart' if (dart.library.html) 'main_web.dart' as platform;
import 'data/database/pg_config.dart';
import 'data/database/connection.dart' show testPostgresConnection;
import 'services/client_write_interceptor.dart';
import 'services/delta_pull_service.dart';
import 'services/offline_fallback_sync_service.dart';
import 'services/cloud_sync/cloud_link_controller.dart';
import 'services/network_service.dart';
import 'core/logging/diagnostic_logger.dart';
import 'presentation/pos/widgets/pos_opening_balance_dialog.dart';
import 'presentation/widgets/fiscal_year_gate_dialog.dart';
import 'domain/models/app_close_cart_gate.dart';
import 'presentation/widgets/dialogs/cart_not_empty_close_dialog.dart';

part 'app_main_screen_catalog.dart';
part 'app_main_screen_navigation.dart';
part 'app_main_screen_lifecycle.dart';
part 'app_main_screen_dialogs.dart';
part 'app_main_screen_shift.dart';

/// هل المستخدم يقفل البرنامج من غير ما يتطلب كلمة سر المدير؟
///
/// ── ليه الفرع الأصلي كان غلط ──────────────────────────────────────────────
/// كان فيه `|| (role?.isSystemRole ?? false)`، و`isSystemRole` بيوصف إن الدور
/// **مزروع وغير قابل للحذف**، مش إنه دور عالي الصلاحية. الأدوار المزروعة
/// كنظام هي مدير النظام و**كاشير** ومخزني ومحاسب ومدير مالي — فالكاشير كان
/// بيتخطى البوابة اللي موجودة عشانه هو تحديداً.
///
/// البوابة دي سؤالها «يتطلب كلمة سر مدير؟»، فالمدير وحده هو اللي يعفى منها.
@visibleForTesting
bool canCloseAppWithoutPassword(AuthState auth) => auth.hasSystemAdminBypass;

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with WindowListener {
  ScreenTabs _tabs = ScreenTabs.of(AppScreen.dashboard.value);
  final List<int> _navigationHistory = [];
  bool _userHasNavigatedManually = false;
  String? _lastDefaultScreenApplied;
  List<int>? _lastAllowedIndicesApplied;
  List<ScreenConfig>? _allScreensCache;
  final Map<int, FocusScopeNode> _tabFocusScopes = {};

  @override
  void initState() {
    super.initState();
    initializeMainScreen();
  }

  Future<void> _initDefaultScreen() => initializeDefaultScreen();

  Future<void> _autoConnectScale() => autoConnectScale();

  Future<void> _enforceShiftForCashier() =>
      enforceShiftForUser(context, ref, callSite: 'AppMainScreen.initState');

  Future<void> _checkFiscalYear() => checkFiscalYear();

  Future<void> _checkExpiringProducts() => checkExpiringProducts();

  void _showExpiryAlertDialog(List<dynamic> expiringBatches) =>
      showExpiryAlertDialog(expiringBatches);
  @override
  void dispose() {
    if (platform.isDesktop()) {
      windowManager.removeListener(this);
    }
    for (final node in _tabFocusScopes.values) {
      node.dispose();
    }
    _tabFocusScopes.clear();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    await handleWindowClose();
  }

  List<ScreenConfig> _getAllScreens() => _allScreensCache ??= buildAllScreens();

  List<ScreenConfig> _getScreensForAllowed(List<int> allowedIndices) =>
      getScreensForAllowed(allowedIndices);

  void _navigateToScreen(int screenIndex) => _navigateToScreenImpl(screenIndex);

  void _activateScreen(int screenIndex) => _activateScreenImpl(screenIndex);

  String _screenLabelFor(int screenIndex) => _screenLabelForImpl(screenIndex);

  void _pruneTabScopes() => _pruneTabScopesImpl();

  Widget _openScreensStack(Map<int, ScreenConfig> byScreenIndex) =>
      _openScreensStackImpl(byScreenIndex);

  bool _goBack() => _goBackImpl();

  Future<void> _closeTab(int screenIndex) => _closeTabImpl(screenIndex);

  bool _listsEqual(List<int> a, List<int> b) => _listsEqualImpl(a, b);

  @override
  Widget build(BuildContext context) => buildMainScreen(context);

  String _formatOfflineTime(DateTime start) => formatOfflineTime(start);

  void _showSyncDialog(BuildContext context) => showSyncDialog(context);
}
