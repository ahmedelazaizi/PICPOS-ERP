// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'core/config/app_config.dart';
import 'core/config/business_profile_provider.dart';
import 'core/enums/app_screen.dart';
import 'core/utils/logger.dart';
import 'data/providers/providers.dart';
import 'services/license_service.dart';
import 'services/permission_sync_bridge.dart';
import 'presentation/shell/app_shell.dart';
import 'core/config/brand.dart';
import 'presentation/pos/screens/pos_main_screen.dart';
import 'presentation/pos_picpos/screens/picpos_pos_screen.dart';
import 'presentation/offers_picpos/offers_picpos_screen.dart';
import 'presentation/accounting_picpos/accounting_hub_picpos_screen.dart';
import 'presentation/accounting_picpos/chart_of_accounts_picpos_screen.dart';
import 'presentation/accounting_picpos/financial_statements_picpos_screen.dart';
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
import 'presentation/screens/inventory/inventory_screen.dart';
import 'presentation/inventory_picpos/screens/inventory_picpos_screen.dart';
import 'presentation/screens/purchase_invoices_screen.dart';
import 'presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
import 'presentation/screens/treasury_screen.dart';
import 'presentation/treasury_picpos/screens/treasury_picpos_screen.dart';
import 'presentation/bookings_picpos/screens/bookings_picpos_screen.dart';
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
import 'presentation/screens/loyalty_screen.dart';
import 'presentation/screens/distribution_screen.dart';
import 'presentation/settings_picpos/screens/distribution_picpos_screen.dart';

import 'presentation/screens/manufacturing_screen.dart';
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
import 'presentation/screens/general_ledger_screen.dart';
import 'presentation/screens/sales_orders_screen.dart';
import 'presentation/screens/branch_performance_screen.dart';
import 'presentation/screens/help_center_screen.dart';
import 'presentation/screens/landed_cost_screen.dart';
import 'presentation/screens/cycle_count_screen.dart';
import 'presentation/cycle_count_picpos/screens/cycle_count_picpos_screen.dart';
import 'presentation/screens/report_builder_screen.dart';
import 'presentation/screens/sales_returns_screen.dart';
import 'presentation/sales_returns_picpos/screens/sales_returns_picpos_screen.dart';
import 'presentation/screens/purchase_returns_screen.dart';
import 'presentation/purchase_returns_picpos/screens/purchase_returns_picpos_screen.dart';
import 'presentation/screens/shift_close_screen.dart';
import 'presentation/shift_close_picpos/screens/shift_close_picpos_screen.dart';
import 'presentation/screens/sync/sync_conflicts_screen.dart';
import 'presentation/screens/audit/audit_dashboard_screen.dart';
import 'main_desktop.dart' if (dart.library.html) 'main_web.dart' as platform;
import 'data/database/pg_config.dart';
import 'data/database/connection_io.dart' show testPostgresConnection;
import 'services/client_write_interceptor.dart';
import 'services/delta_pull_service.dart';
import 'services/offline_fallback_sync_service.dart';
import 'services/network_service.dart';
import 'core/logging/diagnostic_logger.dart';
import 'presentation/pos/widgets/pos_opening_balance_dialog.dart';
import 'presentation/widgets/fiscal_year_gate_dialog.dart';
import 'domain/models/app_close_cart_gate.dart';
import 'presentation/widgets/dialogs/cart_not_empty_close_dialog.dart';


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
  // Default to first screen in allowed list (position 0)
  // For cashiers: position 0 = POS (dashboard is hidden)
  // For admins: position 0 = Dashboard, POS is found via _initDefaultScreen
  int _currentIndex = 0;

  /// Navigation history stack for back button support
  final List<int> _navigationHistory = [];

  @override
  void initState() {
    super.initState();
    // Add window listener for close confirmation
    if (platform.isDesktop()) {
      windowManager.addListener(this);
      // Auto-connect to scale on desktop startup
      _autoConnectScale();
    }
    // Check for expiring products on app launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Materialize the permission sync bridge so any role/permission/user/
      // role_permission delta-pull or full-sync immediately invalidates the
      // Riverpod permission caches. Without this, PermissionGuard reads stale
      // data after a server-side permission change and the manager-override
      // dialog fires unnecessarily.
      ref.read(permissionSyncBridgeProvider);
      _checkFiscalYear();
      _checkExpiringProducts();
      _initDefaultScreen();
      _enforceShiftForCashier();
      // Auto-link cost centers to branches/warehouses/regions by name match
      ref.read(databaseProvider).autoLinkCostCenters();
      // Refresh license activation cache for demo builds
      if (AppConfig.isDemo) {
        ref.read(licenseServiceProvider).refreshActivationStatus();
      }
      // Start auto-sync if in offline fallback mode
      if (PostgresConfig.isOfflineFallback) {
        final db = ref.read(databaseProvider);
        OfflineFallbackSyncService.instance.startAutoSync(db);
      }
    });
  }

  /// Flag: `_initDefaultScreen()` applies the per-user default screen to
  /// `_currentIndex`. If the user already navigated manually, we must not
  /// reset them back to the default. This flag flips to true once an
  /// explicit navigation (other than the initial auto-pick) happens.
  bool _userHasNavigatedManually = false;

  /// Initialize default screen based on per-user setting, then global fallback.
  ///
  /// Called twice:
  ///   1. In `initState` postFrameCallback — first run, most data ready
  ///   2. Re-invoked in `build()` if the auth'd user's `defaultScreen` or
  ///      allowedIndices have changed since last run (covers the "client
  ///      refresh on login" case where the user object is patched after
  ///      the first frame).
  String? _lastDefaultScreenApplied;
  List<int>? _lastAllowedIndicesApplied;

  Future<void> _initDefaultScreen() async {
    final db = ref.read(databaseProvider);
    final authState = ref.read(authProvider);
    final allowedIndices = await ref.read(userAllowedScreensProvider.future);

    debugPrint('[NAV] _initDefaultScreen: userDefault='
        '${authState.user?.defaultScreen}, allowed=$allowedIndices, '
        'userId=${authState.user?.id}');
    await DiagnosticLogger.log('NAV',
        'init: userId=${authState.user?.id} '
        'username=${authState.user?.username} '
        'defaultScreen=${authState.user?.defaultScreen} '
        'allowedIndices=$allowedIndices '
        'userHasNavigatedManually=$_userHasNavigatedManually');

    // 1. Per-user default screen (set in user management)
    int targetScreenIndex = 1; // fallback: POS
    final userDefault = authState.user?.defaultScreen;
    if (userDefault != null && userDefault.isNotEmpty) {
      switch (userDefault) {
        case 'pos':
          targetScreenIndex = 1;
        case 'dashboard':
          targetScreenIndex = 0;
        case 'tables':
          targetScreenIndex = 3;
        case 'products':
          targetScreenIndex = 4;
        case 'inventory':
          targetScreenIndex = 8;
        default:
          targetScreenIndex = int.tryParse(userDefault) ?? 1;
      }
    } else {
      // 2. Global setting fallback
      final savedSetting = await db.getSettingValue('default_home_screen');
      if (savedSetting != null) {
        targetScreenIndex = int.tryParse(savedSetting) ?? 1;
      }
    }

    // 3. Validate against allowed indices for current user
    if (!allowedIndices.contains(targetScreenIndex)) {
      debugPrint('[NAV] Target screen $targetScreenIndex not in allowed '
          '$allowedIndices — falling back');
      targetScreenIndex = allowedIndices.contains(1)
          ? 1
          : (allowedIndices.isNotEmpty ? allowedIndices.first : 0);
    }

    final targetListPosition = allowedIndices.indexOf(targetScreenIndex);
    debugPrint('[NAV] _initDefaultScreen: target=$targetScreenIndex → '
        'position=$targetListPosition');
    await DiagnosticLogger.log('NAV',
        'resolved: targetScreenIndex=$targetScreenIndex '
        'position=$targetListPosition '
        '(will ${targetListPosition >= 0 && !_userHasNavigatedManually ? "apply" : "skip"})');

    // Cache for re-entry detection
    _lastDefaultScreenApplied = userDefault;
    _lastAllowedIndicesApplied = List.of(allowedIndices);

    if (targetListPosition >= 0 && mounted && !_userHasNavigatedManually) {
      setState(() => _currentIndex = targetListPosition);
      await DiagnosticLogger.log('NAV',
          '✓ _currentIndex set to $targetListPosition (screen '
          'index=$targetScreenIndex)');
    }
  }

  /// Attempt to auto-connect to previously used scale
  Future<void> _autoConnectScale() async {
    try {
      // ScaleService is only available on desktop platform
      // This is safe because _autoConnectScale is only called when platform.isDesktop() is true
      await platform.autoConnectScale();
    } catch (e) {
      // Silently fail - scale connection is not critical
      debugPrint('Scale auto-connect failed: $e');
    }
  }

  /// غلاف رفيع حوالين [enforceShiftForUser] — نقطة نداء `initState`.
  Future<void> _enforceShiftForCashier() =>
      enforceShiftForUser(context, ref, callSite: 'AppMainScreen.initState');


  Future<void> _checkFiscalYear() async {
    if (!mounted) return;
    final result = await FiscalYearGateDialog.check(context, ref);
    // If dialog returned true, navigate to fiscal year screen
    if (result == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FiscalYearScreen()),
      );
    }
  }

  Future<void> _checkExpiringProducts() async {
    if (!mounted) return;

    final db = ref.read(databaseProvider);
    try {
      // Get products expiring within 30 days
      final expiringBatches = await db.getExpiringBatches(30);

      if (expiringBatches.isNotEmpty && mounted) {
        _showExpiryAlertDialog(expiringBatches);
      }
    } catch (e, stackTrace) {
      // Log error on startup using the new AppLogger
      AppLogger.e('Error checking expiring products', e, stackTrace);
    }
  }

  void _showExpiryAlertDialog(List<dynamic> expiringBatches) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('تنبيه: منتجات قاربت على انتهاء الصلاحية'),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'يوجد ${expiringBatches.length} منتج(ات) ستنتهي صلاحيتها خلال 30 يوم:',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: expiringBatches.length > 10
                        ? 10
                        : expiringBatches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final batch = expiringBatches[index];
                      final daysUntilExpiry = batch.expiryDate != null
                          ? batch.expiryDate!.difference(DateTime.now()).inDays
                          : 0;

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: daysUntilExpiry <= 7
                              ? Colors.red.shade100
                              : Colors.orange.shade100,
                          child: Icon(
                            Icons.inventory_2,
                            color: daysUntilExpiry <= 7
                                ? Colors.red.shade700
                                : Colors.orange.shade700,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          batch.productName ?? 'منتج غير معروف',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          'الكمية: ${batch.quantity} | تاريخ الشراء: ${batch.purchaseDate != null ? '${batch.purchaseDate!.day}/${batch.purchaseDate!.month}/${batch.purchaseDate!.year}' : 'غير محدد'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: daysUntilExpiry <= 7
                                ? Colors.red.shade100
                                : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            daysUntilExpiry <= 0
                                ? 'منتهي'
                                : '$daysUntilExpiry يوم',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: daysUntilExpiry <= 7
                                  ? Colors.red.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (expiringBatches.length > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'و ${expiringBatches.length - 10} منتج(ات) أخرى...',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.check),
              label: const Text('حسناً، فهمت'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (platform.isDesktop()) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // First, close any open dialogs/overlays before showing our close confirmation
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      // Small delay to ensure dialogs are closed
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;

    // ── SERVER MODE: hide window instead of destroying process ──
    // This keeps the HTTP API server alive for client machines without
    // requiring anyone to be physically logged in at the server terminal.
    final ns = platform.getNetworkService();
    if (ns.isServer) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.cloud_done_rounded, color: Color(0xFF16C79A), size: 28),
                  SizedBox(width: 10),
                  Text('السيرفر يعمل في الخلفية'),
                ],
              ),
              content: const Text(
                'تم تصغير النافذة وإخفاؤها.\n'
                'السيرفر لا يزال يعمل في الخلفية ويستقبل اتصالات العملاء.\n\n'
                'لإغلاق السيرفر نهائياً، افتح النافذة وأغلقها من الإعدادات.',
                style: TextStyle(height: 1.6),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16C79A),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('حسناً'),
                ),
              ],
            ),
          ),
        );
      }
      // Hide window: server keeps running, clients stay connected
      await windowManager.hide();
      return;
    }

    // #B2: منعُ إغلاق البرنامج وسلّةُ البيع عامرة — طلبُ مالكٍ 2026-08-17.
    // القرارُ عمداً **بعد** فرع وضع السيرفر لا قبله: في وضع السيرفر أعلاه
    // النافذةُ تُخفى فقط (`windowManager.hide()`) والعمليةُ تبقى حيّةً —
    // فسلّةُ البيع لا تُفقد، ولا داعي لمنعها هناك. من هنا وأسفلَ، كلا
    // الفرعين (مدير/كاشير) ينتهيان بـ`windowManager.destroy()` الذي يُنهي
    // العمليةَ فعلياً — فهنا وحده يجب المنعُ قبل عرض أيّ حوار تأكيدٍ آخر.
    if (mounted) {
      final saleCartItemCount = ref.read(cartControllerProvider).items.length;
      if (shouldBlockAppCloseForCart(saleCartItemCount)) {
        await showCartNotEmptyCloseBlockedDialog(context);
        return;
      }
    }

    final authState = ref.read(authProvider);
    // ده قرار صلاحية حقيقي: بيقرر هل غلق البرنامج محتاج كلمة سر مدير ولا لأ.
    // قبل كده كانت `isAdmin || isManager` بتتحدد بمطابقة اسم الدور، فأي دور
    // اسمه فيه «مدير» كان بيتخطى كلمة السر.
    final canSkipPassword = canCloseAppWithoutPassword(authState);

    if (canSkipPassword) {
      // Admin/Manager: simple yes/no confirmation
      final shouldClose = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.95),
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                SizedBox(width: 12),
                Text('تأكيد إغلاق البرنامج'),
              ],
            ),
            content: const Text('هل أنت متأكد من أنك تريد إغلاق البرنامج؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لا، البقاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('نعم، إغلاق'),
              ),
            ],
          ),
        ),
      );

      if (shouldClose == true) {
        windowManager.destroy();
      }
    } else {
      // Cashier/Non-admin: require admin password to close
      final shouldClose = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.95),
        builder: (ctx) => const Directionality(
          textDirection: TextDirection.rtl,
          child: _AdminCloseDialog(),
        ),
      );

      if (shouldClose == true) {
        windowManager.destroy();
      }
    }
  }

  /// Cached list of all available screens to avoid redundant object creation
  List<ScreenConfig>? _allScreensCache;

  List<ScreenConfig> _getAllScreens() {
    return _allScreensCache ??= [
      ScreenConfig(
        appScreen: AppScreen.dashboard,
        // Brand fork, not a profile fork — matches the `Brand.isPicPos`
        // pattern used by every other forked screen below (e.g. `pos`,
        // `products`, `categories`): exactly one branch is reachable per
        // build, both wired to the exact same `onNavigate` callback.
        builder: (_) => Brand.isPicPos
            ? DashboardPicposScreen(
                onNavigate: (index) => _navigateToScreen(index),
              )
            : DashboardScreen(
                onNavigate: (index) => _navigateToScreen(index),
              ),
        label: 'Dashboard',
        icon: PhosphorIconsBold.house,
      ),
      ScreenConfig(
        appScreen: AppScreen.pos,
        // Spec 135 NOTE 1 — the POS lock-screen wrapper (System B) was retired
        // in favour of the single app-wide InactivityDetector (System A,
        // session_timeout_minutes). Two parallel timeout systems on different
        // keys meant "disable" never fully disabled. PosScreenV2 mounts
        // directly now; session timeout is handled once, app-wide.
        //
        // Brand fork, not a profile fork. `Brand.isPicPos` is a compile-time
        // const, so exactly one of these two screens is even reachable in a
        // given build — UralCash cannot land on the PicPos layout by picking
        // the `lite` profile, and vice versa. Both screens drive the same
        // cart/checkout controllers; only layout and key bindings differ.
        builder: (_) =>
            Brand.isPicPos ? const PicPosPosScreen() : const PosScreenV2(),
        label: 'البيع السريع',
        icon: PhosphorIconsBold.shoppingCart,
      ),
      ScreenConfig(
        appScreen: AppScreen.offers,
        // Brand fork, not a profile fork — same pattern as its neighbours.
        builder: (_) =>
            Brand.isPicPos ? const OffersPicPosScreen() : const OffersScreen(),
        label: 'العروض',
        icon: PhosphorIconsBold.tag,
      ),
      ScreenConfig(
        appScreen: AppScreen.tables,
        // Brand fork, not a profile fork — same pattern as its neighbours.
        // Tables was the only screen here without one, so PicPos landed on
        // the UralCash layout and its view toggle drove nothing.
        builder: (_) => Brand.isPicPos
            ? const TablesPicposScreen()
            : const TablesScreen(),
        label: 'الطاولات',
        icon: PhosphorIconsBold.circlesThree,
      ),
      ScreenConfig(
        appScreen: AppScreen.products,
        builder: (_) => Brand.isPicPos
            ? const ProductsPicposScreen()
            : const ProductsScreen(),
        label: 'الأصناف',
        icon: PhosphorIconsBold.package,
      ),
      ScreenConfig(
        appScreen: AppScreen.categories,
        builder: (_) => Brand.isPicPos
            ? const CategoriesPicposScreen()
            : const CategoriesScreen(),
        label: 'التصنيفات',
        icon: PhosphorIconsBold.squaresFour,
      ),
      ScreenConfig(
        appScreen: AppScreen.parties,
        builder: (_) => Brand.isPicPos
            ? const PartiesPicposScreen()
            : const UnifiedPartiesScreen(),
        label: 'العملاء والموردين',
        icon: PhosphorIconsBold.usersThree,
      ),
      ScreenConfig(
        appScreen: AppScreen.inventory,
        builder: (_) => const SecurityScreenGate(
          settingKey: 'inventory_access_password',
          title: 'المخازن',
          child: Brand.isPicPos ? InventoryPicposScreen() : InventoryScreen(),
        ),
        label: 'المخزون',
        icon: PhosphorIconsBold.warehouse,
      ),
      ScreenConfig(
        appScreen: AppScreen.purchases,
        builder: (_) => const SecurityScreenGate(
          settingKey: 'purchases_access_password',
          title: 'المشتريات',
          child: Brand.isPicPos
              ? PurchasesPicposScreen()
              : PurchaseInvoicesScreen(),
        ),
        label: 'المشتريات',
        icon: PhosphorIconsBold.receipt,
      ),
      ScreenConfig(
        appScreen: AppScreen.treasury,
        builder: (_) => const SecurityScreenGate(
          settingKey: 'accounting_access_password',
          title: 'الحسابات والمالية',
          child: Brand.isPicPos ? TreasuryPicposScreen() : TreasuryScreen(),
        ),
        label: 'الخزينة',
        icon: PhosphorIconsBold.wallet,
      ),
      ScreenConfig(
        appScreen: AppScreen.reports,
        builder: (_) => const SecurityScreenGate(
          settingKey: 'reports_access_password',
          title: 'التقارير',
          child: Brand.isPicPos ? ReportsPicposScreen() : ReportsScreen(),
        ),
        label: 'التقارير',
        icon: PhosphorIconsBold.chartBar,
      ),
      ScreenConfig(
        appScreen: AppScreen.settings,
        builder: (_) =>
            Brand.isPicPos ? const SettingsPicposScreen() : const SettingsScreen(),
        label: 'الإعدادات',
        icon: PhosphorIconsBold.gear,
      ),
      ScreenConfig(
        appScreen: AppScreen.branches,
        // فوركُ PicPos يأخذ تصميمَ «الفروع والمنشآت» بتبويباته الخمس،
        // وشاشةُ UralCash تبقى كما هي بلا مساس.
        builder: (_) => Brand.isPicPos
            ? const BranchesPicposScreen()
            : const BranchManagementScreen(),
        label: 'الفروع',
        icon: PhosphorIconsBold.buildings,
      ),
      ScreenConfig(
        appScreen: AppScreen.regions,
        builder: (_) => const RegionManagementScreen(),
        label: 'المناطق',
        icon: PhosphorIconsBold.mapPin,
      ),
      ScreenConfig(
        appScreen: AppScreen.kitchen,
        builder: (_) => const KitchenDisplayScreen(),
        label: 'المطبخ',
        icon: PhosphorIconsBold.cookingPot,
      ),
      ScreenConfig(
        appScreen: AppScreen.analytics,
        builder: (_) => const AnalyticsDashboardScreen(),
        label: 'التحليلات',
        icon: PhosphorIconsBold.chartPie,
      ),
      ScreenConfig(
        appScreen: AppScreen.hr,
        builder: (_) => const SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: 'شؤون الموظفين',
          child: HRScreen(),
        ),
        label: 'الموظفين',
        icon: PhosphorIconsBold.users,
      ),
      ScreenConfig(
        appScreen: AppScreen.salesInvoices,
        builder: (_) => Brand.isPicPos
            ? const SalesInvoicesPicposScreen()
            : const SalesInvoicesScreen(),
        label: 'فواتير المبيعات',
        icon: PhosphorIconsBold.fileText,
      ),
      ScreenConfig(
        appScreen: AppScreen.activityLog,
        builder: (_) => Brand.isPicPos
            ? const ActivityLogPicposScreen()
            : const ActivityLogScreen(),
        label: 'سجل العمليات',
        icon: PhosphorIconsBold.clipboardText,
      ),
      ScreenConfig(
        appScreen: AppScreen.inventoryBonds,
        builder: (_) => Brand.isPicPos
            ? const InventoryBondsPicposScreen()
            : const InventoryBondsScreen(),
        label: 'أرصدة المخزون',
        icon: PhosphorIconsBold.clipboardText,
      ),
      ScreenConfig(
        appScreen: AppScreen.stockTransfer,
        builder: (_) => Brand.isPicPos
            ? const StockTransferPicposScreen()
            : const StockTransferScreen(),
        label: 'تحويل مخزني',
        icon: PhosphorIconsBold.arrowsLeftRight,
      ),
      ScreenConfig(
        appScreen: AppScreen.stockRequisitions,
        builder: (_) => const StockRequisitionsScreen(),
        label: 'طلبات الصرف',
        icon: PhosphorIconsBold.truck,
      ),
      ScreenConfig(
        appScreen: AppScreen.scalePlu,
        builder: (_) => Brand.isPicPos
            ? const ScalePluPicposScreen()
            : const ScalePluExportScreen(),
        label: 'ميزان التسعير',
        icon: PhosphorIconsBold.scales,
      ),
      ScreenConfig(
        appScreen: AppScreen.eInvoice,
        builder: (_) => const EInvoiceDashboardScreen(),
        label: 'الفوترة الإلكترونية',
        icon: PhosphorIconsBold.invoice,
      ),
      ScreenConfig(
        appScreen: AppScreen.loyalty,
        builder: (_) => const LoyaltyScreen(),
        label: 'نقاط الولاء',
        icon: PhosphorIconsBold.trophy,
      ),
      ScreenConfig(
        appScreen: AppScreen.distribution,
        // فوركُ PicPos يأخذ وحدةَ `regions` من التصميم بتبويباتها الأربع،
        // وشاشةُ UralCash تبقى كما هي بلا مساس.
        builder: (_) => Brand.isPicPos
            ? const DistributionPicposScreen()
            : const DistributionScreen(),
        label: 'التوزيع',
        icon: PhosphorIconsBold.truck,
      ),
      ScreenConfig(
        appScreen: AppScreen.manufacturing,
        builder: (_) => const ManufacturingScreen(),
        label: 'التصنيع',
        icon: PhosphorIconsBold.factory,
      ),
      ScreenConfig(
        appScreen: AppScreen.operationalExpenses,
        builder: (_) => const OperationalExpensesScreen(),
        label: 'المصروفات التشغيلية',
        icon: PhosphorIconsBold.coins,
      ),
      ScreenConfig(
        appScreen: AppScreen.chartOfAccounts,
        // Brand fork, not a profile fork — same pattern as its neighbours.
        // ⚠️ و`SecurityScreenGate` يبقى **حول الاثنين**: الفوركُ يبدّل الشكلَ
        //    لا الحراسة، وإسقاطُه هنا يفتح دليلَ الحسابات بلا كلمة مرور.
        builder: (_) => const SecurityScreenGate(
          settingKey: 'accounting_access_password',
          title: 'دليل الحسابات',
          child: Brand.isPicPos
              ? ChartOfAccountsPicPosScreen()
              : ChartOfAccountsScreen(),
        ),
        label: 'دليل الحسابات',
        icon: PhosphorIconsBold.treeStructure,
      ),
      ScreenConfig(
        appScreen: AppScreen.fiscalYear,
        builder: (_) => const FiscalYearScreen(),
        label: 'السنوات المالية',
        icon: PhosphorIconsBold.calendar,
      ),
      ScreenConfig(
        appScreen: AppScreen.stockMovements,
        builder: (_) => const StockMovementsScreen(),
        label: 'حركة المخزون',
        icon: PhosphorIconsBold.arrowsDownUp,
      ),
      ScreenConfig(
        appScreen: AppScreen.purchaseOrders,
        builder: (_) => const PurchaseOrdersScreen(),
        label: 'أوامر الشراء',
        icon: PhosphorIconsBold.clipboardText,
      ),
      ScreenConfig(
        appScreen: AppScreen.accountMapping,
        builder: (_) => const AccountMappingSettingsScreen(),
        label: 'ربط الحسابات',
        icon: PhosphorIconsBold.link,
      ),
      ScreenConfig(
        appScreen: AppScreen.journalEntries,
        builder: (_) => const SecurityScreenGate(
          settingKey: 'accounting_access_password',
          title: 'دفتر اليومية',
          child: JournalEntriesScreen(),
        ),
        label: 'دفتر اليومية',
        icon: PhosphorIconsBold.notebook,
      ),
      ScreenConfig(
        appScreen: AppScreen.costCenters,
        builder: (_) => const CostCentersScreen(),
        label: 'مراكز التكلفة',
        icon: PhosphorIconsBold.treeStructure,
      ),
      ScreenConfig(
        appScreen: AppScreen.commercialPapers,
        // فوركُ PicPos على «PicPos Cheques.dc.html» بتبويباته الخمس،
        // وشاشةُ UralCash تبقى كما هي بلا مساس.
        builder: (_) => Brand.isPicPos
            ? const ChequesPicposScreen()
            : const CommercialPapersScreen(),
        label: 'الشيكات',
        icon: PhosphorIconsBold.receipt,
      ),
      ScreenConfig(
        appScreen: AppScreen.fixedAssets,
        builder: (_) => const FixedAssetsScreen(),
        label: 'الأصول الثابتة',
        icon: PhosphorIconsBold.buildings,
      ),
      ScreenConfig(
        appScreen: AppScreen.generalLedger,
        builder: (_) => const SecurityScreenGate(
          settingKey: 'accounting_access_password',
          title: 'دفتر الأستاذ',
          child: GeneralLedgerScreen(),
        ),
        label: 'دفتر الأستاذ',
        icon: PhosphorIconsBold.book,
      ),
      ScreenConfig(
        appScreen: AppScreen.salesOrders,
        builder: (_) => const SalesOrdersScreen(),
        label: 'طلبات البيع',
        icon: PhosphorIconsBold.fileText,
      ),
      ScreenConfig(
        appScreen: AppScreen.branchPerformance,
        builder: (_) => const BranchPerformanceScreen(),
        label: 'أداء الفروع',
        icon: PhosphorIconsBold.chartBar,
      ),
      ScreenConfig(
        appScreen: AppScreen.helpCenter,
        builder: (_) => const HelpCenterScreen(),
        label: 'مركز المساعدة',
        icon: PhosphorIconsBold.question,
      ),
      ScreenConfig(
        appScreen: AppScreen.landedCost,
        builder: (_) => const LandedCostScreen(),
        label: 'التكاليف المحملة',
        icon: PhosphorIconsBold.money,
      ),
      ScreenConfig(
        appScreen: AppScreen.cycleCounting,
        builder: (_) => Brand.isPicPos
            ? const CycleCountPicposScreen()
            : const CycleCountScreen(),
        label: 'الجرد الدوري',
        icon: PhosphorIconsBold.listChecks,
      ),
      ScreenConfig(
        appScreen: AppScreen.reportBuilder,
        builder: (_) => const ReportBuilderScreen(),
        label: 'تقارير مخصصة',
        icon: PhosphorIconsBold.chartBar,
      ),
      ScreenConfig(
        appScreen: AppScreen.salesReturns,
        builder: (_) => Brand.isPicPos
            ? const SalesReturnsPicposScreen()
            : const SalesReturnsScreen(),
        label: 'مرتجع المبيعات',
        icon: PhosphorIconsBold.arrowUUpLeft,
      ),
      ScreenConfig(
        appScreen: AppScreen.purchaseReturns,
        builder: (_) => Brand.isPicPos
            ? const PurchaseReturnsPicposScreen()
            : const PurchaseReturnsScreen(),
        label: 'مرتجع المشتريات',
        icon: PhosphorIconsBold.arrowUUpLeft,
      ),
      ScreenConfig(
        appScreen: AppScreen.shiftClose,
        builder: (_) => Brand.isPicPos
            ? const ShiftClosePicposScreen()
            : const ShiftCloseScreen(),
        label: 'إغلاق الوردية',
        icon: PhosphorIconsBold.lockKey,
      ),
      // الحجوزات — PicPos وحدَها اليوم: لا نظيرَ لها في UralCash، والشاشةُ
      // مبنيّةٌ على `picpos_shell`. ونطاقُها `restaurant`/`cafe`/`unified`.
      ScreenConfig(
        appScreen: AppScreen.bookings,
        builder: (_) => const BookingsPicPosScreen(),
        label: 'الحجوزات',
        icon: PhosphorIconsBold.calendarCheck,
      ),
      ScreenConfig(
        appScreen: AppScreen.financialStatements,
        // Brand fork, not a profile fork — same pattern as its neighbours.
        builder: (_) => Brand.isPicPos
            ? const FinancialStatementsPicPosScreen()
            : const FinancialStatementsScreen(),
        label: 'القوائم المالية',
        icon: PhosphorIconsBold.scales,
      ),
      ScreenConfig(
        appScreen: AppScreen.accountingHub,
        builder: (_) => const AccountingHubPicPosScreen(),
        label: 'الحسابات',
        icon: PhosphorIconsBold.bookOpen,
      ),
      ScreenConfig(
        appScreen: AppScreen.syncConflicts,
        builder: (_) => const SyncConflictsScreen(),
        label: 'تعارضات المزامنة',
        icon: PhosphorIconsBold.arrowsClockwise,
      ),
      ScreenConfig(
        appScreen: AppScreen.auditDashboard,
        builder: (_) => const AuditDashboardScreen(),
        label: 'لوحة التدقيق',
        icon: PhosphorIconsBold.shieldCheck,
      ),
    ];
  }

  /// Get screens based on allowed indices (from permissions).
  ///
  /// In CLIENT mode we additionally hide the HR (employees) screen — user,
  /// employee, and permission management are server-authoritative and must
  /// only be accessed from the server to avoid ID collisions and out-of-sync
  /// accounts. These settings carry over to the client via user pull sync.
  List<ScreenConfig> _getScreensForAllowed(List<int> allowedIndices) {
    final allScreens = _getAllScreens();
    final isClientMode = NetworkService.instance.isClient;
    const clientHiddenScreens = <AppScreen>{
      AppScreen.hr, // Employees / HR — managed centrally on the server
    };
    return allScreens.where((s) {
      if (!allowedIndices.contains(s.index)) return false;
      if (isClientMode && clientHiddenScreens.contains(s.appScreen)) return false;
      return true;
    }).toList();
  }

  void _navigateToScreen(int screenIndex) {
    final allowedAsync = ref.read(userAllowedScreensProvider);
    allowedAsync.whenData((allowedIndices) {
      final targetListIndex = allowedIndices.indexOf(screenIndex);
      if (targetListIndex >= 0) {
        _navigationHistory.add(_currentIndex);
        // Record that the user manually navigated — stops the auto-default
        // re-pick on subsequent builds from overriding the user's choice.
        _userHasNavigatedManually = true;
        setState(() => _currentIndex = targetListIndex);
      }
    });
  }

  /// Fast equality for small int lists (allowed-screens comparisons).
  bool _listsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final allowedScreensAsync = ref.watch(userAllowedScreensProvider);
    final authState = ref.watch(authProvider);

    // Re-apply the per-user default screen when either the auth'd user's
    // `defaultScreen` or the allowed-indices list changes AFTER the first
    // paint. This covers the case where a client login triggers a background
    // user refresh that arrives *after* the initial `_initDefaultScreen()`
    // has already run with stale data.
    if (allowedScreensAsync.hasValue) {
      final current = allowedScreensAsync.value!;
      final userDefault = authState.user?.defaultScreen;
      final defaultChanged = _lastDefaultScreenApplied != userDefault;
      final allowedChanged = _lastAllowedIndicesApplied == null ||
          !_listsEqual(_lastAllowedIndicesApplied!, current);
      if (!_userHasNavigatedManually &&
          authState.isAuthenticated &&
          (defaultChanged || allowedChanged)) {
        // Defer to avoid calling setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _initDefaultScreen();
        });
      }
    }

    // Use cached value to keep AppShell alive during provider reloads
    // (e.g. admin elevation). This prevents _isHidden state from being reset.
    final allowedIndices = allowedScreensAsync.hasValue
        ? allowedScreensAsync.value
        : null;

    if (allowedIndices == null) {
      if (allowedScreensAsync.hasError) {
        return const Scaffold(
          body: Center(child: Text('خطأ في تحميل الصلاحيات')),
        );
      }
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F3460),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  size: 44,
                  color: Color(0xFF16C79A),
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF16C79A),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'جاري تحميل الصلاحيات...',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    {
      final screens = _getScreensForAllowed(allowedIndices);

      // Reset index if out of bounds
      if (_currentIndex >= screens.length) {
        _currentIndex = 0;
      }

      // Get the actual screen index for the current position
      final currentScreenIndex = screens.isNotEmpty
          ? screens[_currentIndex].index
          : 0;

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;

          // 1. Try popping the nested navigator (sub-screens like UOM, reports)
          final nestedNav = appShellNestedNavigatorKey.currentState;
          if (nestedNav != null && nestedNav.canPop()) {
            nestedNav.pop();
            return;
          }

          // 2. Try popping sidebar navigation history
          if (_navigationHistory.isNotEmpty) {
            setState(() => _currentIndex = _navigationHistory.removeLast());
            return;
          }

          // 3. No history — show exit dialog
          //
          // #B2: منعُ الخروجَ هنا أيضاً وسلّةُ البيع عامرة. هذا المسارُ
          // ينادي `platform.exitApp()` (= `dart:io exit(0)` بعد نسخة
          // احتياطية) مباشرةً — بلا مرورٍ بـ`onWindowClose`/`windowManager`
          // إطلاقاً — فحارسُ `onWindowClose` وحده لا يغطّيه.
          final cartItemCountForBackExit =
              ref.read(cartControllerProvider).items.length;
          if (shouldBlockAppCloseForCart(cartItemCountForBackExit)) {
            await showCartNotEmptyCloseBlockedDialog(context);
            return;
          }

          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('تأكيد الخروج'),
                  ],
                ),
                content: const Text(
                  'هل أنت متأكد من أنك تريد الخروج من البرنامج؟',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('خروج'),
                  ),
                ],
              ),
            ),
          );
          if (shouldExit == true) {
            platform.exitApp();
          }
        },
        child: AppShell(
          // Pass actual screen index for proper highlighting
          currentIndex: currentScreenIndex,
          // Back navigation via history stack — always pass callback
          onBackTap: () {
            if (_navigationHistory.isEmpty) return;
            setState(() => _currentIndex = _navigationHistory.removeLast());
          },
          // Convert screen index to list position
          onNavigate: (screenIndex) async {
            final listPosition = screens.indexWhere(
              (s) => s.index == screenIndex,
            );
            if (listPosition < 0) return;

            // #9: Guard navigation away from POS when cart has items
            if (currentScreenIndex == 1 && screenIndex != 1) {
              final cartState = ref.read(cartControllerProvider);
              if (cartState.items.isNotEmpty) {
                final shouldLeave =
                    await showDialog<bool>(
                      context: context,
                      builder: (ctx) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: AlertDialog(
                          title: const Text('تنبيه'),
                          content: const Text(
                            'يوجد أصناف في السلة. هل تريد المغادرة بدون حفظ؟',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('لا'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('نعم، مغادرة'),
                            ),
                          ],
                        ),
                      ),
                    ) ??
                    false;
                if (!shouldLeave) return;
              }
            }

            _navigationHistory.add(_currentIndex);
            setState(() => _currentIndex = listPosition);
          },
          child: Column(
            children: [
              // ── Offline fallback banner ──────────────────────
              // Only show for PostgreSQL offline fallback, NOT for client mode
              // (client mode uses SQLite + HTTP sync, not PostgreSQL).
              //
              // Defensive: hex Color literals instead of Colors.orange.shadeNNN.
              // The previous implementation crashed during build with
              //   RangeError (length): Invalid value: Valid value range is empty: 0
              //   #0  MaterialColor.shade800
              //   #1  _MainScreenState.build (app_main_screen.dart:1084)
              // for some users on the server (offline-fallback path) — likely a
              // Flutter framework swatch lookup quirk in this build chain.
              // Literal const Color values eliminate the indirection entirely.
              if (PostgresConfig.isOfflineFallback && !NetworkService.instance.isClient)
                MaterialBanner(
                  backgroundColor: const Color(0xFFFFF3E0), // orange shade50
                  leading: const Icon(PhosphorIconsBold.wifiSlash,
                      color: Color(0xFFEF6C00)), // orange shade800
                  content: Text(
                    'وضع أوفلاين — العمل على قاعدة البيانات المحلية. '
                    '${PostgresConfig.offlineFallbackStart != null ? "منذ ${_formatOfflineTime(PostgresConfig.offlineFallbackStart!)}" : ""}',
                    style: const TextStyle(
                        color: Color(0xFFE65100), // orange shade900
                        fontSize: 13),
                  ),
                  actions: [
                    // ── Sync Now button ──
                    TextButton.icon(
                      icon: const Icon(PhosphorIconsBold.arrowsClockwise,
                          size: 16,
                          color: Color(0xFF388E3C)), // green shade700
                      label: const Text('مزامنة الآن',
                          style: TextStyle(
                              color: Color(0xFF388E3C),
                              fontWeight: FontWeight.bold)),
                      onPressed: () => _showSyncDialog(context),
                    ),
                    // ── Test Connection button ──
                    TextButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final pgConfig = await PostgresConfig.load();
                        final error = await testPostgresConnection(pgConfig);
                        if (error == null) {
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('✅ السيرفر متاح — اضغط "مزامنة الآن" لنقل البيانات'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('❌ السيرفر غير متاح: $error'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('اختبار الاتصال',
                          style: TextStyle(
                              color: Color(0xFFE65100))), // orange shade900
                    ),
                  ],
                ),
              // ── Main content ──────────────────────────────────
              Expanded(
                child: GlobalSearchOmnibox(
                  onNavigateToScreen: (index) {
                    final listPosition = screens.indexWhere(
                      (s) => s.index == index,
                    );
                    if (listPosition >= 0) {
                      _navigationHistory.add(_currentIndex);
                      setState(() => _currentIndex = listPosition);
                    }
                  },
                  // Guard: screens can be transiently empty during a provider
                  // reload (e.g. after updateActivity() triggers a rebuild while
                  // userAllowedScreensProvider is still computing). Without this
                  // guard, screens[0] on an empty list throws
                  // RangeError (length): Invalid value: Valid value range is empty: 0.
                  child: screens.isNotEmpty
                      ? screens[_currentIndex].screen
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ── Offline sync helpers ────────────────────────────────────────

  String _formatOfflineTime(DateTime start) {
    final diff = DateTime.now().difference(start);
    if (diff.inDays > 0) return '${diff.inDays} يوم';
    if (diff.inHours > 0) return '${diff.inHours} ساعة';
    return '${diff.inMinutes} دقيقة';
  }

  void _showSyncDialog(BuildContext context) {
    final syncService = OfflineFallbackSyncService.instance;
    final db = ref.read(databaseProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: _OfflineSyncDialog(
          syncService: syncService,
          localDb: db,
          onDone: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }
}

/// Screen configuration with permission-based access.
/// PIR: Uses lazy [WidgetBuilder] — screens are only constructed when first accessed.
/// بتضمن إن المستخدم الحالي عنده وردية مفتوحة، وبتسأله يفتح واحدة لو لأ.
///
/// ── ليه دالة عليا مش دالة خاصة في `State` ────────────────────────────────
/// كانت بتتنادى من `initState` **وبس**، وده كان كفاية وقت ما كل دخول مستخدم
/// جديد كان بيمرّ بإعادة بناء الشجرة. بعد إلغاء الإغلاق الإجباري بقى فيه
/// مسار تاني: `switchUser()` بتغيّر المستخدم **من غير** ما تهدّ الشجرة —
/// مقصود، عشان ديالوج التبديل ما يموتش مع مفتاح `MaterialApp` في
/// `main.dart:1217`. فـ`initState` ما بتشتغلش، والكاشير الجاي كان هيبيع بلا
/// وردية مفتوحة وفواتيره ما تتنسبش لأي وردية.
///
/// [callSite] بيتكتب في سجل التشخيص عشان نعرف أي مسار سأل — الدخول ولا
/// التبديل.
Future<void> enforceShiftForUser(
  BuildContext context,
  WidgetRef ref, {
  required String callSite,
}) async {
  if (!context.mounted) return;
  final authState = ref.read(authProvider);
  // Spec 135 NOTE 2 — سياسة وردية مقصودة، مش قرار صلاحية: مدير النظام
  // عمداً ما بيفتحش وردية لنفسه، وبيتصل بوردية الكاشير المفتوحة عشان
  // يسويها. `isAdmin || isManager` هنا تفادياً لتضييق السلوك على «مدير
  // فرع» لغاية ما فحص «مين المدير» ده يتراجع فيه قرار منفصل.
  if (authState.isAdmin || authState.isManager) return; // admins/managers skip
  final userId = authState.user?.id;
  if (userId == null) return;

  // Pull latest shift state from server before checking locally.
  if (NetworkService.instance.isClient) {
    try {
      await DeltaPullService.instance.pullTable('shifts');
    } catch (e) {
      debugPrint('[ShiftGuard] Shift pull failed (non-fatal): $e');
    }
  }

  final treasuryRepo = ref.read(treasuryRepositoryProvider);
  final openShift = await treasuryRepo.getCurrentOpenShift(userId);
  unawaited(DiagnosticLogger.log(
      'SHIFT-GUARD',
      'enforceShiftForUser check userId=$userId '
      'openShiftId=${openShift?.id} '
      'alreadyPrompted=${shiftDialogPromptedUserIds.contains(userId)} '
      'callSite=$callSite'));
  if (openShift != null) return; // shift already open — nothing to do

  // Feature 012 / Issue C-SHIFT-LOOP: same-session guard. If we
  // already prompted this user once in this app session, do not
  // re-prompt — even if the local shift row was transiently
  // overwritten or removed by an upstream sync. The user can still
  // open a shift manually from the treasury screen if needed.
  //
  // `switchUser()` بتفضّي المجموعة دي (`clearShiftDialogPromptedUsers`)،
  // فالكاشير الجاي بيتسأل عادي — الحارس بيمنع تكرار السؤال لنفس المستخدم
  // في نفس الجلسة بس.
  if (shiftDialogPromptedUserIds.contains(userId)) {
    unawaited(DiagnosticLogger.log(
        'SHIFT-GUARD',
        '⚠ suppressed re-prompt for userId=$userId '
        '(already prompted in this session) — see ShiftSyncStrategy'));
    return;
  }
  shiftDialogPromptedUserIds.add(userId);

  if (!context.mounted) return;
  final userName =
      authState.user?.displayName ?? authState.user?.username ?? 'كاشير';

  // Prompt for opening balance — barrierDismissible: false makes it mandatory.
  final opening = await showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PosOpeningBalanceDialog(userName: userName),
  );

  // Spec 008 / FR-004: resolve the operating branch from BranchScope so
  // multi-branch users open the shift on their CURRENT branch (not always
  // their first user_branch_access row). Full-access users (system admin,
  // mirror admin) get null — close-time logic falls back gracefully.
  int? scopedBranchId;
  try {
    final scope = await ref.read(branchScopeProvider.future);
    scopedBranchId = scope.primaryBranchId;
  } catch (e) {
    debugPrint('[ShiftGuard] BranchScope lookup failed (non-fatal): $e');
  }

  // Open shift locally first so the cashier can work even while offline.
  await treasuryRepo.openShift(userId, opening ?? 0.0,
      branchId: scopedBranchId);

  // Mirror to server (fire-and-forget — will queue if offline).
  // R9 (2026-05-12 fix): forward the local shift's globalId so the server
  // resolves close-shift by globalId — fixes the recurring "Shift not
  // found" 500 / DEAD-LETTER on every close.
  try {
    int? localShiftId;
    String? localShiftGlobalId;
    final active = await treasuryRepo.getCurrentOpenShift(userId);
    localShiftId = active?.id;
    localShiftGlobalId = active?.globalId;
    unawaited(
      ClientWriteInterceptor.openShift(userId, opening ?? 0.0,
          localShiftId: localShiftId,
          branchId: scopedBranchId,
          globalId: localShiftGlobalId),
    );
  } catch (e) {
    debugPrint('[ShiftGuard] openShift server mirror failed (non-fatal): $e');
  }
  // Re-fetch the freshly inserted shift so the diag entry carries id +
  // globalId — these are the values the server-side close-shift now keys
  // off, so logging them lets us correlate the open ↔ close end-to-end.
  int? loggedShiftId;
  String? loggedShiftGid;
  try {
    final fresh = await treasuryRepo.getCurrentOpenShift(userId);
    loggedShiftId = fresh?.id;
    loggedShiftGid = fresh?.globalId;
  } catch (_) {}
  unawaited(DiagnosticLogger.log(
      'SHIFT',
      'New shift opened userId=$userId '
      'localShiftId=$loggedShiftId globalId=$loggedShiftGid '
      'opening=${opening ?? 0.0} branchId=$scopedBranchId callSite=$callSite'));
}

class ScreenConfig {
  final AppScreen appScreen;
  final WidgetBuilder _builder;
  final String label;
  final IconData icon;

  /// Lazily-built screen widget (cached after first access)
  Widget? _cachedScreen;

  /// Get screen widget — built on first access, then cached.
  Widget get screen => _cachedScreen ??= Builder(builder: _builder);

  /// Backward-compatible integer index
  int get index => appScreen.value;

  ScreenConfig({
    required this.appScreen,
    required WidgetBuilder builder,
    required this.label,
    required this.icon,
  }) : _builder = builder;
}

/// Dialog that requires admin password to close the app (shown to non-admin users)
class _AdminCloseDialog extends ConsumerStatefulWidget {
  const _AdminCloseDialog();

  @override
  ConsumerState<_AdminCloseDialog> createState() => _AdminCloseDialogState();
}

class _AdminCloseDialogState extends ConsumerState<_AdminCloseDialog> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final input = _passwordController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال كلمة المرور');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check admin_password (stored as hash)
      if (ref.read(adminPasswordServiceProvider).verify(input)) {
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // Try authenticating by password or card code
      final db = ref.read(databaseProvider);
      final userWithRole = await db.authenticateByPasswordOrCard(input);
      if (userWithRole != null) {
        final roleName = userWithRole.role?.name.toLowerCase() ?? '';
        final isSystemRole = userWithRole.role?.isSystemRole ?? false;
        final isAdmin =
            isSystemRole ||
            roleName.contains('admin') ||
            roleName.contains('مدير') ||
            roleName.contains('مسؤول') ||
            roleName.contains('manager') ||
            roleName.contains('owner');

        if (isAdmin) {
          if (mounted) Navigator.pop(context, true);
          return;
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = 'هذا المستخدم ليس لديه صلاحية إغلاق البرنامج';
          });
          return;
        }
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'كلمة المرور غير صحيحة';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'خطأ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline, color: Colors.red, size: 28),
          SizedBox(width: 12),
          Expanded(child: Text('إغلاق البرنامج يتطلب كلمة مرور المدير')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'لا يمكن إغلاق البرنامج إلا بإدخال كلمة مرور مدير النظام.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'كلمة مرور المدير',
              prefixIcon: const Icon(Icons.vpn_key),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: _errorMessage,
            ),
            onSubmitted: (_) => _verify(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _verify,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('إغلاق البرنامج'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Offline Sync Progress Dialog
// ═══════════════════════════════════════════════════════════════════════════

class _OfflineSyncDialog extends StatefulWidget {
  final OfflineFallbackSyncService syncService;
  final AppDatabase localDb;
  final VoidCallback onDone;

  const _OfflineSyncDialog({
    required this.syncService,
    required this.localDb,
    required this.onDone,
  });

  @override
  State<_OfflineSyncDialog> createState() => _OfflineSyncDialogState();
}

class _OfflineSyncDialogState extends State<_OfflineSyncDialog> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSync());
  }

  Future<void> _startSync() async {
    if (_started) return;
    _started = true;
    final success = await widget.syncService.syncToPostgres(widget.localDb);
    if (success) {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncProgress>(
      valueListenable: widget.syncService.progress,
      builder: (context, progress, _) {
        final isDone = progress.isDone;
        final hasError = progress.error != null;

        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isDone
                    ? (hasError ? Icons.error_outline : Icons.check_circle_outline)
                    : Icons.sync,
                color: isDone
                    ? (hasError ? Colors.red : Colors.green)
                    : Colors.blue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isDone
                      ? (hasError ? 'فشلت المزامنة' : 'تمت المزامنة بنجاح')
                      : 'جاري المزامنة...',
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isDone) ...[
                  LinearProgressIndicator(
                    value: progress.progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    progress.statusText,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${progress.rowsSynced} سجل تم مزامنته',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                if (isDone && !hasError) ...[
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'تم نقل ${progress.rowsSynced} سجل إلى سيرفر PostgreSQL.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أعد تشغيل البرنامج للعمل مباشرة على قاعدة بيانات السيرفر.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (isDone && hasError) ...[
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    progress.error!,
                    style: const TextStyle(fontSize: 13, color: Colors.red),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تم مزامنة ${progress.rowsSynced} سجل قبل الخطأ.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (isDone)
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasError ? Colors.grey : Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text(hasError ? 'إغلاق' : 'حسناً'),
              ),
            if (isDone && hasError)
              TextButton(
                onPressed: () {
                  _started = false;
                  _startSync();
                },
                child: const Text('إعادة المحاولة'),
              ),
          ],
        );
      },
    );
  }
}