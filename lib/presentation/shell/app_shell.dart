import 'package:picpos_erp/core/i18n/tr.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as p;
import '../../core/config/app_config.dart';
import '../../core/config/brand.dart';
import '../../core/config/business_profile_provider.dart';
import '../../core/enums/app_screen.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/backup_service.dart';
import '../../domain/models/pos_shortcut_fab_gate.dart';
import '../../domain/models/nav_search.dart';
import '../../core/navigation/screen_id.dart';
import '../providers/pending_picpos_report.dart';
import '../reports_picpos/screens/reports_picpos_screen.dart';
import 'report_category_nav.dart';
import '../../data/providers/e_invoicing_providers.dart';
import '../widgets/permission_guard.dart' show hasPermissionWithAdminBypass;

import '../../data/providers/providers.dart';
import 'dart:async';
import '../../services/offline_sync_worker.dart';
import '../../services/network_service.dart';
import '../../data/database/sync_interceptor.dart';
import '../../services/sync_event_bus.dart';
import '../pos/providers/cart_controller.dart';
import '../pos/providers/cfd_controller.dart';
import '../../core/navigation/dirty_screens_registry.dart';
import 'app_shell_close_action.dart';
import '../pos/logic/open_shift_gate.dart';
import '../widgets/inactivity_detector.dart';
import '../../main_desktop.dart'
    if (dart.library.html) '../../main_web.dart'
    as platform;
import 'screen_breadcrumbs.dart';
import 'screen_tabs_bar.dart';
import '../widgets/user_language_selector.dart';
import '../../core/i18n/locale_provider.dart';
import '../widgets/sync_management_dialog.dart';
import '../widgets/sync_status_badge.dart';
import '../widgets/mirror_badge.dart';
import '../widgets/mirror_status_strip.dart';
import '../widgets/legacy_db_key_banner.dart';
import '../../services/mirror_state.dart';

part 'nav_widgets.dart';

/// Main navigation shell with RTL Arabic sidebar and dynamic permission-based navigation

/// Global key for the nested Navigator — used by PopScope in MainScreen
final appShellNestedNavigatorKey = GlobalKey<NavigatorState>();

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final int currentIndex;
  final Function(int) onNavigate;
  final VoidCallback? onBackTap;

  /// التاباتُ المفتوحةُ بترتيب فتحها — يرسمها الشريطُ الأعلى.
  final List<ScreenTabView> tabs;

  /// تنشيطُ تابٍ مفتوح. ويُنادى أيضاً على التاب النشط نفسِه.
  final void Function(int screenIndex) onSelectTab;

  /// إغلاقُ تابٍ. حارسُ السلّة يقع هنا لا عند التنشيط: التنقّلُ بين
  /// التابات لم يبقَ يهدم شاشةَ البيع، والإغلاقُ يهدمها.
  final void Function(int screenIndex) onCloseTab;

  /// الانتقالُ إلى لوحة المعلومات — `null` لمن لا يملكها (‏الكاشير).
  final VoidCallback? onHomeTab;

  const AppShell({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onNavigate,
    this.onBackTap,
    this.tabs = const [],
    required this.onSelectTab,
    required this.onCloseTab,
    this.onHomeTab,
  });

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isExpanded = true;
  bool _isHidden =
      false; // Sidebar visible by default; hidden only for cashier in initState
  StreamSubscription<SyncEvent>? _conflictSub;
  // L4: dedupe dead-letter snackbars — fire only when the event is newer
  // than the last one we displayed (the ValueNotifier replays its current
  // value on every build, so without this we'd spam snackbars on rebuilds).
  DateTime? _lastSeenDeadLetterAt;
  void Function()? _deadLetterListener;

  /// بحثُ الشاشات في الشريط الجانبيّ — أمرُ المالك 2026-09-12.
  ///
  /// ⚠️ ويُبحَث في **المداخل المسموحة** لا في `kAllNavItemDefs`: بحثٌ يعرض
  /// شاشةً ممنوعةً يمنح خريطةَ النظام لمن لا يملكها، ونقرةٌ عليها تُفتح
  /// شاشةً يرفضها الحارسُ — أو أسوأ: لا يرفضها.
  final TextEditingController _navSearchCtrl = TextEditingController();
  String _navQuery = '';

  @override
  void initState() {
    super.initState();
    // Auto-collapse/hide sidebar for cashier users — read synchronously so the
    // very first build already has the correct sidebar state, avoiding an
    // expanded→hidden animation flash on every cashier login.
    final authState = ref.read(authProvider);
    if (authState.isCashier) {
      _isExpanded = false;
      _isHidden = true; // #12 إخفاء كامل للكاشير
    }

    // Perform automated backup asynchronously — must not block the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performAutoBackup();
      // Cluster 025 / Issues 2+7: surface sync notifications as a top
      // MaterialBanner instead of a bottom SnackBar. SnackBars overlay the
      // POS save buttons (cashier reported "shareet aHmar mass5 azrar
      // el7afZ") — MaterialBanner pushes content down and never blocks taps
      // on the cart/checkout area.
      _conflictSub = SyncEventBus.instance.stream
          .where((e) => e is SyncConflictDetected)
          .cast<SyncConflictDetected>()
          .listen((event) {
        if (!mounted) return;
        _showSyncBanner(
          message: tr('تعارض في {p0} #{p1} — البيانات المحلية أحدث، تم الاحتفاظ بها', {'p0': event.table, 'p1': event.recordId}),
          color: AppColors.warning,
          icon: PhosphorIconsBold.warning,
          actionLabel: tr('التفاصيل'),
          onAction: () => SyncManagementDialog.show(context),
          autoDismiss: const Duration(seconds: 6),
        );
      });

      // L4 (2026-04-28): listen for dead-letter events so the admin sees a
      // banner the moment an outbox item gets permanently rejected. Dedup by
      // timestamp so the event isn't re-fired on every rebuild.
      _deadLetterListener = () {
        final event = OfflineSyncWorker.instance.lastDeadLetterEvent.value;
        if (event == null) return;
        if (_lastSeenDeadLetterAt != null &&
            !event.timestamp.isAfter(_lastSeenDeadLetterAt!)) {
          return;
        }
        _lastSeenDeadLetterAt = event.timestamp;
        if (!mounted) return;
        final reasonShort = event.reason.length > 100
            ? '${event.reason.substring(0, 100)}…'
            : event.reason;
        _showSyncBanner(
          message:
              tr('عملية {p0} ({p1}) فشلت نهائياً: {reasonShort}', {'p0': event.table, 'p1': event.operation, 'reasonShort': reasonShort}),
          color: AppColors.error,
          icon: PhosphorIconsBold.cloudSlash,
          actionLabel: tr('مراجعة'),
          onAction: () => SyncManagementDialog.show(context),
          autoDismiss: const Duration(seconds: 12),
        );
      };
      OfflineSyncWorker.instance.lastDeadLetterEvent
          .addListener(_deadLetterListener!);
    });
  }

  /// Cluster 025 / Issues 2+7: shared helper that surfaces sync events as a
  /// non-blocking top MaterialBanner (replaces the previous bottom SnackBar
  /// which physically overlapped the POS save buttons). Auto-dismisses after
  /// [autoDismiss] so the banner doesn't pile up on repeated failures.
  void _showSyncBanner({
    required String message,
    required Color color,
    required IconData icon,
    required String actionLabel,
    required VoidCallback onAction,
    required Duration autoDismiss,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Clear any previous sync banner so they don't stack.
    messenger.clearMaterialBanners();
    final banner = MaterialBanner(
      backgroundColor: color.withValues(alpha: 0.95),
      leading: Icon(icon, color: Colors.white, size: 24),
      content: Text(
        message,
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
          onPressed: () {
            messenger.clearMaterialBanners();
            onAction();
          },
          child: Text(
            actionLabel,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(
          onPressed: () => messenger.clearMaterialBanners(),
          child:  Text(
            tr('تجاهل'),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
    messenger.showMaterialBanner(banner);
    Future.delayed(autoDismiss, () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    });
  }

  @override
  void dispose() {
    _navSearchCtrl.dispose();
    _conflictSub?.cancel();
    if (_deadLetterListener != null) {
      OfflineSyncWorker.instance.lastDeadLetterEvent
          .removeListener(_deadLetterListener!);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When sidebar screen changes, pop nested navigator back to root
    if (oldWidget.currentIndex != widget.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = appShellNestedNavigatorKey.currentState;
        if (nav != null) {
          nav.popUntil((route) => route.isFirst);
        }
      });
    }
  }

  void _showLogoutConfirmation() async {
    // الوردية بتتبلّغ مش بتتمنع: تفضل مفتوحة والكاشير يكمّلها لما يرجع، أو
    // اللي عنده `pos_shift_close` يقفلها من شاشة الورديات المفتوحة.
    //
    // قبل كده كان هنا إغلاق إجباري بلا تجاوز ولا للأدمن. المستخدم راجع القرار
    // وطلب إلغاءه؛ الانضباط اتنقل لشاشة الورديات المتروكة بدل المنع.
    await notifyOpenShift(
      context: context,
      ref: ref,
      reason: tr('قبل تسجيل الخروج'),
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.signOut, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('تسجيل الخروج')),
            ],
          ),
          content:  Text(tr('هل تريد تسجيل الخروج من النظام؟')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () async {
                Navigator.pop(context);
                // #Forensic Log: Logout
                final auth = ref.read(authProvider);
                try {
                  final logger = ref.read(activityLoggerProvider);
                  await logger.logLogout(
                    auth.user?.id ?? 0,
                    auth.user?.displayName ?? 'Unknown',
                  );
                } catch (e) {
                  debugPrint('[ActivityLog] Error: $e');
                }
                // Clear cart before logout
                ref.read(cartControllerProvider.notifier).clearCart();
                // Invalidate all user-scoped providers so the next login starts
                // with a clean state rather than briefly showing the previous
                // user's nav items / permissions.
                ref.invalidate(userNavItemsProvider);
                ref.invalidate(userAllowedScreensProvider);
                ref.invalidate(currentUserPermissionsProvider);
                ref.invalidate(userRoleProvider);
                ref.invalidate(activeBranchIdProvider);
                ref.read(authProvider.notifier).logout();
                // Navigation handled reactively by MaterialApp.home watching authProvider
              },
              child:  Text(tr('خروج')),
            ),
          ],
        ),
      ),
    );
  }

  /// #3: manual «إغلاق البرنامج» — see app_shell_close_action.dart.
  void _showExitConfirmation() => runCloseAppAction(
        context: context,
        cartItemCount: ref.read(cartControllerProvider).items.length,
        registry: ref.read(dirtyScreensRegistryProvider),
        backup: () => _performAutoBackup(isManual: true),
        exitApp: platform.exitApp,
      );

  /// Automated backup logic
  Future<void> _performAutoBackup({bool isManual = false}) async {
    try {
      // Fixed database path for UralCash
      final dbPath = p.join(Directory.current.path, 'database.sqlite');
      final dbFile = File(dbPath);

      if (await dbFile.exists()) {
        final backupFile = await BackupService.performBackup(dbPath);
        if (backupFile != null) {
          debugPrint('[Backup] Auto-backup successful: ${backupFile.path}');
          if (isManual && mounted) {
            AppToast.show(
              context,
              tr('تم النسخ الاحتياطي بنجاح: {p0}', {'p0': backupFile.path.split(p.separator).last}),
              type: ToastType.success,
            );
          }
        } else {
          debugPrint('[Backup] Auto-backup returned null (failed)');
          if (isManual && mounted) {
            AppToast.show(
              context,
              tr('فشل النسخ الاحتياطي'),
              type: ToastType.error,
            );
          }
        }
      } else {
        debugPrint('[Backup] Database file not found at $dbPath');
      }
    } catch (e) {
      debugPrint('[Backup] Auto-backup failed: $e');
      if (isManual && mounted) {
        AppToast.show(
          context,
          tr('خطأ في النسخ الاحتياطي: {e}', {'e': e}),
          type: ToastType.error,
        );
      }
    }
  }

  /// #12: Request admin password to show sidebar
  Future<void> _requestAdminAccessToShowSidebar() async {
    // Skip password dialog only if the ORIGINAL logged-in user is an
    // admin/manager — never grant the bypass based on a still-active
    // elevation, because the sidebar prompt is specifically the gate
    // that lets a CASHIER hand the terminal to a manager. Using the
    // `effectiveRole` here was the source of the "sidebar re-opens
    // without prompt after elevation drop" bug.
    final authState = ref.read(authProvider);
    if (authState.isOriginallyAdmin || authState.isOriginallyManager) {
      setState(() {
        _isHidden = false;
        _isExpanded = true;
      });
      return;
    }

    // §٤ — `system_sidebar_open` يُعفي حاملَه من حوار كلمة المرور.
    //
    // كان الإعفاءُ صفةً ملازمةً للمنصب (مدير/مشرف)؛ وصار صلاحيةً يمنحها
    // المالكُ لمن يشاء — وهو طلبُه بالحرف: أن يفرض فتحَ القائمة أو منعَه
    // **لمستخدمٍ بعينه** لا لدرجةٍ وظيفية.
    //
    // ⚠️ وإعفاءٌ لا منع: من لا يملكه يسقط إلى الحوار كما اليوم ولا يُحبس.
    // زرُّ «تسجيل الخروج» يعيش **داخلَ** القائمة الجانبية، فمنعٌ تامٌّ كان
    // سيترك الكاشيرَ بلا مخرجٍ من النظام (قرارُ المالك 2026-08-15).
    //
    // ويُقرأ من المستخدم **الأصليّ** لا المرفوع — نفسُ سبب `isOriginallyAdmin`
    // أعلاه: رفعُ صلاحيةٍ لفعلٍ واحدٍ يجب ألّا يفتح الشريطَ بعد سقوطه.
    final actorId = authState.user?.id;
    if (actorId != null) {
      final authRepo = ref.read(authRepositoryProvider);
      final exempt = await authRepo.userHasPermission(
        actorId,
        PermissionCodes.systemSidebarOpen,
      );
      if (exempt) {
        if (!mounted) return;
        setState(() {
          _isHidden = false;
          _isExpanded = true;
        });
        return;
      }
    }

    if (!mounted) return;
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.lock, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(tr('🔐 صلاحية المدير')),
            ],
          ),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration:  InputDecoration(
              labelText: tr('أدخل كلمة مرور المدير'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(ctx, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child:  Text(tr('تأكيد')),
            ),
          ],
        ),
      ),
    );

    if (password == null || password.isEmpty) return;

    // Trim password
    final cleanPassword = password.trim();

    try {
      final authRepo = ref.read(authRepositoryProvider);
      bool granted = false;
      UserWithRole? authenticatedAdmin;

      // Method 1: Check admin_password (stored as hash)
      if (await ref.read(adminPasswordServiceProvider).verify(cleanPassword)) {
        granted = true;
      }

      // Method 2: Fall back to user-based authentication (hashed passwords)
      if (!granted) {
        final userWithRole = await authRepo.authenticateByPasswordOrCard(
          cleanPassword,
        );
        if (userWithRole != null) {
          final roleName = userWithRole.role?.name.toLowerCase() ?? '';
          final isSystemRole = userWithRole.role?.isSystemRole ?? false;
          if (isSystemRole ||
              roleName.contains('مدير') ||
              roleName.contains('admin') ||
              roleName.contains('manager') ||
              roleName.contains('owner')) {
            granted = true;
            authenticatedAdmin = userWithRole;
          }
        }
      }

      if (granted) {
        // Elevate the auth session to unlock all screens
        UserWithRole elevationTarget;

        if (authenticatedAdmin != null) {
          // Method 2 found the admin user — use them directly
          elevationTarget = authenticatedAdmin;
        } else {
          // Method 1 (setting password) — find the system admin user
          final allUsers = await authRepo.watchAllUsers().first;

          // Priority 1: System admin role (isSystemRole=true)
          elevationTarget =
              allUsers.cast<UserWithRole?>().firstWhere(
                (u) => u?.role?.isSystemRole == true,
                orElse: () => null,
              ) ??
              allUsers.cast<UserWithRole?>().firstWhere(
                (u) =>
                    (u?.role?.name.toLowerCase().contains('admin') ?? false) ||
                    (u?.role?.name.toLowerCase().contains('مدير') ?? false),
                orElse: () => null,
              ) ??
              allUsers.first;
        }

        ref.read(authProvider.notifier).elevate(elevationTarget);
        ref.invalidate(userAllowedScreensProvider);
        ref.invalidate(userNavItemsProvider);
        setState(() {
          _isHidden = false;
          _isExpanded =
              true; // #3: Always fully expand sidebar on manager override
        });

        if (mounted) {
          AppToast.show(
            context,
            tr('تم منح الصلاحية مؤقتاً — العمليات تُسجّل باسم المستخدم الأصلي'),
            type: ToastType.success,
          );
        }
        return;
      }

      if (mounted) {
        AppToast.show(
          context,
          tr('كلمة المرور غير صحيحة أو ليس لديك صلاحية'),
          type: ToastType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('حدث خطأ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  /// فئاتُ التقارير تحت مجموعة «التقارير» — أو `null` لكلِّ مجموعةٍ سواها.
  ///
  /// ⚠️ **ومشروطٌ بحضور مدخلِ «التقارير» في [items]**: من لا يملك
  /// `reports_view` لا يرى المدخلَ، فعرضُ فئاته تحته يمنحه خريطةَ ما لا
  /// يبلغه — والنقرةُ تنقله إلى شاشةٍ يرفضها النطاق.
  ///
  /// ⚠️ **ومسيَّجٌ بـ[Brand.isPicPos]**: الكتالوجُ كتالوجُ مركزِ تقارير
  /// PicPos، والفوركُ الآخر شاشةُ تقاريرَ أخرى لا تعرف هذه المعرّفات.
  Widget? _reportCategoriesFor(NavItemDef item) {
    if (!Brand.isPicPos) return null;
    if (item.index != ScreenId.reports.navigationIndex) return null;

    return ReportCategoryNav(
      onOpen: (categoryId, reportId) => _openReport(
        item,
        categoryId: categoryId,
        reportId: reportId,
      ),
    );
  }

  /// ينتقل إلى شاشة التقارير ثمّ يُسجّل طلبَ التقرير.
  ///
  /// ⚠️ **والترتيبُ انقلب مع التابات، وانقلابُه لازم.** كان الطلبُ يُسجَّل
  /// أوّلاً لأنّ الشاشةَ تستهلكه في `initState`. ومع التابات صارت الشاشةُ
  /// قد تكون **مبنيّةً في تابٍ خلفيّ**، فمستمِعُها يفتح التقريرَ في الحال —
  /// ثمّ يأتي التنقّلُ فيمسح المسارَ المدفوعَ بـ`popUntil` قبل أن يُرى.
  /// فتقريرٌ يُفتَح ويُغلَق في إطارٍ واحد، والنقرةُ تبدو ميّتة.
  ///
  /// والحالاتُ الثلاثُ تصحّ بهذا الترتيب:
  ///   • الشاشةُ غيرُ مفتوحةٍ ⇒ التابُ يُفتَح، والطلبُ يُسجَّل في نفس
  ///     الإطار قبل أن يُركَّب `initState` ويقرأه في `postFrame`.
  ///   • مفتوحةٌ في الخلف ⇒ التنقّلُ يُظهرها، ثمّ يفتح المستمِعُ التقرير.
  ///   • معروضةٌ أصلاً ⇒ `popUntil` ثمّ الطلبُ يفتح فوقَها.
  void _openReport(
    NavItemDef reportsItem, {
    required String categoryId,
    required String? reportId,
  }) {
    _onNavItemTap(reportsItem);
    pendingPicposReport.request(categoryId: categoryId, reportId: reportId);
  }

  /// حقلُ البحث أعلى القائمة.
  Widget _navSearchField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 4),
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: _navSearchCtrl,
          onChanged: (v) => setState(() => _navQuery = v),
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          cursorColor: AppColors.primary,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: tr('ابحث عن شاشة أو ما بداخلها…'),
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
            prefixIcon: const Icon(
              PhosphorIconsBold.magnifyingGlass,
              size: 15,
              color: AppColors.textMuted,
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            suffixIcon: _navQuery.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(PhosphorIconsBold.x, size: 13),
                    color: AppColors.textMuted,
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 30, minHeight: 30),
                    tooltip: tr('مسح البحث'),
                    onPressed: () {
                      _navSearchCtrl.clear();
                      setState(() => _navQuery = '');
                    },
                  ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// نتائجُ البحث — قائمةٌ مسطَّحةٌ تحمل اسمَ الشاشة ومجموعتَها.
  ///
  /// ⚠️ **مبنيّةٌ من [items] لا من `kAllNavItemDefs`**: [items] هي المداخلُ
  /// التي نجت من نطاق الملفّ الشخصيّ ومن صلاحيّات المستخدم ومن سياج
  /// العلامة. والبحثُ في القائمة الكاملة يعرض للكاشير شاشةَ الحسابات.
  Widget _navSearchResults(List<NavItemDef> items) {
    final reportsItem = items
        .where((i) => i.index == ScreenId.reports.navigationIndex)
        .firstOrNull;

    // ⚠️ **ومداخلُ التقارير مشروطةٌ بحضور مدخلها**: من لا يملك
    // `reports_view` لا يرى الشاشةَ، فإظهارُ تقاريرها في البحث يمنحه
    // خريطةَ ما لا يبلغه — وهو عينُ سياجِ الفئات في الشريط.
    final entries = <NavSearchEntry>[
      ...navEntriesFromNavItems(items),
      if (reportsItem != null && Brand.isPicPos)
        ...reportSearchEntries(
          reportsScreenIndex: reportsItem.index,
          categories: buildPicposReportCatalog(
            actions: PicposReportActions.inert,
            eInvoicePlatform: ref.watch(activeEInvoicePlatformProvider).value,
          ),
        ),
    ];

    final hits = searchNavEntries(_navQuery, entries);
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsBold.magnifyingGlass,
                color: AppColors.textMuted, size: 22),
            const SizedBox(height: 8),
            Text(
              tr('لا شاشةَ بهذا الاسم'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final byIndex = {for (final i in items) i.index: i};
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: hits.length,
      itemBuilder: (context, i) {
        final hit = hits[i];
        final item = byIndex[hit.index]!;
        final isReport = hit.kind != NavSearchKind.screen;
        // سطرٌ ثانٍ: اسمُ الفئة للتقرير، واسمُ المجموعة للشاشة.
        final groupLabel =
            hit.parentLabel ?? _groupMeta[hit.group ?? '']?.label;
        final isSelected = !isReport && widget.currentIndex == item.index;
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.only(
            right: hit.kind == NavSearchKind.report ? 26 : 14,
            left: 14,
          ),
          leading: Icon(
            switch (hit.kind) {
              NavSearchKind.screen => item.icon,
              NavSearchKind.reportCategory => PhosphorIconsBold.folderOpen,
              NavSearchKind.report => PhosphorIconsBold.fileText,
            },
            size: isReport ? 15 : 17,
            color: isSelected ? AppColors.primary : AppColors.textMuted,
          ),
          title: Text(
            // ⚠️ **تسميةُ النتيجة لا تسميةُ الشاشة.** كلُّ مداخل التقارير
            // تحمل فهرسَ شاشة التقارير، فقراءةُ `item.label` كانت تعرض
            // ستّةً وأربعينَ صفّاً كلُّها «التقارير».
            tr(hit.label),
            style: TextStyle(
              color: isSelected ? AppColors.primary : Colors.white,
              fontSize: isReport ? 12 : 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          subtitle: groupLabel == null
              ? null
              : Text(
                  tr(groupLabel),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
          onTap: () {
            // البحثُ يُصفَّر بعد التنقّل: إبقاؤه يترك الشريطَ على نتيجةٍ
            // بينما المحتوى على شاشةٍ أخرى — ولا سبيلَ للعودة للمجموعات.
            _navSearchCtrl.clear();
            setState(() => _navQuery = '');
            if (isReport) {
              _openReport(
                item,
                categoryId: hit.reportCategoryId!,
                reportId: hit.reportId,
              );
            } else {
              _onNavItemTap(item);
            }
          },
        );
      },
    );
  }

  /// نقرةُ مدخلٍ في القائمة — من المجموعات أو من نتائج البحث.
  ///
  /// ⚠️ **كانت مُغلَقةً داخل `onItemTap` في شجرة البناء.** ونتائجُ البحث
  /// مسارُ تنقّلٍ ثانٍ، ونسخُ المنطق لها كان يترك حارسَ السلّة وتسجيلَ
  /// النشاط وفتاتَ الخبز في نسخةٍ واحدةٍ منهما — فيتنقّل المستخدمُ من البحث
  /// وسلّتُه مملوءةٌ بلا تحذير.
  void _onNavItemTap(NavItemDef item) {
      // ⚠️ **حارسُ «لا يمكن الانتقال لشاشة أخرى وهناك أصناف في السلة» نُزع.**
      //
      // كان منعاً مطلقاً: سلّةٌ فيها صنفٌ واحدٌ تُقعِد الكاشيرَ عن **كلّ**
      // شاشةٍ في النظام. وعلّتُه أنّ التنقّلَ كان يهدم شجرةَ شاشة البيع
      // فتُمسَح السلّة. والتابُ يُبقيها مبنيّةً حيّةً — فالسلّةُ تنتظر كما
      // هي، والمنعُ صار إنذاراً عن خطرٍ غيرِ قائمٍ يمنع عملاً قائماً.
      //
      // والحمايةُ لم تسقط، انتقلت إلى حيث الخطرُ فعليّ:
      //   • `_closeTab` — إغلاقُ تابِ البيع يهدم الشجرةَ، فيُسأل.
      //   • `shouldBlockAppCloseForCart` — إغلاقُ البرنامج، في ثلاثة مواضع.
      try {
        final user = ref.read(authProvider).user;
        if (user != null) {
          ref.read(activityLoggerProvider).logNavigation(
            user.id, user.displayName, item.label,
          );
        }
      } catch (_) {}
      
      
      widget.onNavigate(item.index);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final locale = ref.watch(userLocaleProvider);
    final navItemsAsync = ref.watch(userNavItemsProvider);
    final roleAsync = ref.watch(userRoleProvider);

    // اختصارُ «البيع السريع» العائم — طلبُ مالكٍ 2026-08-17: يظهر في كلّ
    // الشاشات لمن يملك صلاحيةَ `pos_access` نفسَها التي يحرس بها عنصر
    // القائمة (`kAllNavItemDefs` في auth_providers.dart)، إلا داخل شاشة
    // البيع نفسها. القرارُ الفعلي معزولٌ في [shouldShowPosShortcutFab]
    // (اختبارٌ وحدةٍ خالص) — هنا فقط قراءةُ الصلاحية والشاشة الحالية.
    final currentUserPermissions =
        ref.watch(currentUserPermissionsProvider).value ?? const <String>[];
    final showPosShortcutFab = shouldShowPosShortcutFab(
      hasPosAccess: hasPermissionWithAdminBypass(
        currentUserPermissions,
        PermissionCodes.posAccess,
      ),
      isOnPosScreen: widget.currentIndex == AppScreen.pos.value,
    );

    // Auto-hide sidebar reactively on any auth transition that leaves a
    // cashier unelevated. Previously the guard only fired when
    // `!_isHidden` — so if an earlier flow ended with the sidebar still
    // technically open (e.g. _isExpanded=true + _isHidden=true from the
    // "إخفاء" button that set only _isHidden, then a silent re-entry
    // into the same AppShell instance kept _isExpanded=true), the auth
    // transition left _isExpanded inconsistent. Result: the next time
    // the sidebar became visible it showed 56-px icon strip without any
    // password prompt, which matches the reported bug.
    //
    // Fix: react on ANY user-id change OR any (isCashier && !elevated)
    // state, and re-enforce the cashier defaults. Also react when the
    // elevation drops so the sidebar collapses back immediately even if
    // the caller forgot to update both flags.
    ref.listen<AuthState>(authProvider, (prev, next) {
      final userChanged = prev?.user?.id != next.user?.id;
      final elevationDropped =
          (prev?.isElevated ?? false) && !next.isElevated;

      // Fresh cashier session (login or elevation-drop): force-hide and
      // collapse. Clears any inherited widget state from a previous
      // admin session AND guards against the asymmetric "إخفاء" path
      // that only touched `_isHidden`.
      if (next.isCashier && !next.isElevated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_isHidden || _isExpanded) {
            setState(() {
              _isHidden = true;
              _isExpanded = false;
            });
          }
        });
        return;
      }

      // If the user id changed (switch from admin → different user) but
      // the new user isn't a cashier, still reset the expanded state
      // defensively — otherwise stale local state can carry across.
      if (userChanged || elevationDropped) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            // Admins/managers see the sidebar fully; cashiers are already
            // handled above. Other roles default to collapsed icon-only.
            // تجميلي مش قرار صلاحية: أقصى أثره إخفاء/توسيع الشريط الجانبي
            // افتراضياً، والزر العائم (FAB) بيرجّعه بكلمة سر مدير في كل
            // الأحوال — مفيش وظيفة أو بيانات بتتفتح هنا زيادة عن اللزوم.
            final isPriv = next.isAdmin || next.isManager;
            _isHidden = !isPriv; // hide for anyone non-privileged
            _isExpanded = isPriv;
          });
        });
      }
    });

    // Initialize CFD listener (SSE broadcasting)
    ref.watch(cfdControllerProvider);

    return ValueListenableBuilder<Locale>(
      valueListenable: I18nCatalog.localeNotifier,
      builder: (context, activeLocale, _) {
        final direction = activeLocale.languageCode == 'en'
            ? TextDirection.ltr
            : TextDirection.rtl;
        return Directionality(
          textDirection: direction,
          child: Scaffold(
        // #12 FAB to show sidebar when hidden - requires admin password.
        // ويتراكب معه اختصار «البيع السريع» أحياناً (كاشيرٌ اتّخذ عنه مديرٌ
        // ثم أسقط الرفع وهو على شاشةٍ غير البيع — القائمةُ تختفي والزرّان
        // كلاهما وجيهان)، فيُكدَّسان عمودياً بنفس الموضع بدل التزاحم.
        floatingActionButton: _isHidden
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isHidden)
                    FloatingActionButton.small(
                      heroTag: 'appShellShowSidebarFab',
                      backgroundColor:
                          AppColors.secondary.withValues(alpha: 0.9),
                      onPressed: () => _requestAdminAccessToShowSidebar(),
                      child: const Icon(
                        PhosphorIconsBold.list,
                        color: Colors.white,
                      ),
                    ),
                  if (_isHidden && showPosShortcutFab)
                    const SizedBox(height: 10),
                  if (_isHidden && showPosShortcutFab)
                    FloatingActionButton.small(
                      heroTag: 'appShellPosShortcutFab',
                      backgroundColor: AppColors.primary.withValues(alpha: 0.9),
                      tooltip: tr('الذهاب إلى البيع السريع'),
                      onPressed: _navigateToPosShortcut,
                      child: const Icon(
                        PhosphorIconsBold.cashRegister,
                        color: Colors.white,
                      ),
                    ),
                ],
              )
            : null,
         floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
        body: Column(children: [
          // MM.D/M2 console strip: link state + branch (collapses off a mirror).
          const MirrorStatusStrip(),
          const LegacyDbKeyBanner(), // SEC-005 (admin-only, self-collapsing)
          Expanded(child: Row(
          children: [
            // Sidebar - fully hidden when _isHidden is true
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isHidden
                  ? 0
                  : (_isExpanded ? 200 : 56), // #12 وضع الكاشير
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                // Feature 006 / MM.D — mirror mode shows a distinct
                // violet sidebar so an admin who has both a mirror
                // laptop AND a regular workstation never confuses
                // them. The other three modes keep AppColors.secondary
                // (the project's standard sidebar color).
                color: NetworkService.instance.isMirror
                    ? const Color(0xFF7C3AED)
                    : AppColors.secondary,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(-1, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    height: 56, // Reduced from 80
                    padding: EdgeInsets.symmetric(
                      horizontal: _isExpanded ? 12 : 4,
                      vertical: 10, // Reduced from 16
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: _isExpanded ? 36 : 24,
                          height: _isExpanded ? 36 : 24,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              8,
                            ), // Reduced from 10
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(Brand.logoAsset, fit: BoxFit.contain),
                          ),
                        ),
                        if (_isExpanded) ...[
                          const SizedBox(width: 8), // Reduced from 12
                          Expanded(
                            child: Text(
                              key: const ValueKey('picposSidebarBrand'),
                               AppConfig.appName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14, // Reduced from 18
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Delta pull spinner — shown while DeltaPullService is active.
                          // Spec 064: broadened to mirror mode (mirror also pulls from HQ).
                          if (SyncInterceptor.isClientMode)
                            ValueListenableBuilder<bool>(
                              valueListenable: SyncEventBus.instance.isPulling,
                              builder: (_, pulling, _) {
                                if (!pulling) return const SizedBox.shrink();
                                return  Tooltip(
                                  message: tr('جارٍ سحب التحديثات من السيرفر...'),
                                  child: const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.info,
                                    ),
                                  ),
                                );
                              },
                            ),
                          // Feature 006 (MM.B): Mirror-mode badge — only visible
                          // when the device is actually in mirror mode AND the
                          // wizard handshake completed. Listens to MirrorState's
                          // revision counter so heartbeat ticks rebuild only
                          // this widget (not the whole sidebar header).
                          if (NetworkService.instance.isMirror &&
                              MirrorState.instance.isConfigured)
                            ValueListenableBuilder<int>(
                              valueListenable: MirrorState.instance.revision,
                              builder: (_, _, _) {
                                return MirrorBadge(
                                  serverDisplayName:
                                      MirrorState.instance.serverDisplayName,
                                  lastHandshakeAt:
                                      MirrorState.instance.lastHandshakeAt,
                                );
                              },
                            ),
                          // #Phase7: Sync Status Badge — only visible in client mode.
                          // Shows pending count (yellow) + dead-letter count (red)
                          // Tapping opens the sync management dialog for review/retry.
                          if (NetworkService.instance.isClient) // keep-isClient: outbox
                            ValueListenableBuilder<int>(
                              valueListenable: OfflineSyncWorker.instance.pendingCount,
                              builder: (context, count, _) {
                                return ValueListenableBuilder<int>(
                                  valueListenable: OfflineSyncWorker.instance.deadLetterCount,
                                  builder: (context, deadLetterCount, _) {
                                    final tooltip = deadLetterCount > 0
                                        ? tr('يوجد {deadLetterCount} عملية فشلت نهائياً — اضغط للمراجعة', {'deadLetterCount': deadLetterCount})
                                        : tr('يوجد {count} عمليات بانتظار المزامنة — اضغط للمراجعة', {'count': count});
                                    return Tooltip(
                                      message: tooltip,
                                      child: SyncStatusBadge(
                                        pendingCount: count,
                                        deadLetterCount: deadLetterCount.toDouble(),
                                        onTap: () {
                                          SyncManagementDialog.show(context);
                                          OfflineSyncWorker.instance
                                              .drainOutbox(force: true);
                                        },
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                        ],
                        if (showPosShortcutFab && !_isHidden)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 4),
                            child: IconButton(
                              key: const ValueKey('picposSidebarPosShortcut'),
                              onPressed: _navigateToPosShortcut,
                              tooltip: tr('الذهاب إلى البيع السريع'),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints.tightFor(
                                width: _isExpanded ? 32 : 24,
                                height: _isExpanded ? 32 : 24,
                              ),
                              icon: Icon(
                                PhosphorIconsBold.cashRegister,
                                color: AppColors.primary,
                                size: _isExpanded ? 20 : 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const Divider(color: AppColors.secondaryLight, height: 1),

                  // بحثُ الشاشات — يظهر في الوضع الموسَّع وحدَه؛ الوضعُ
                  // المطويُّ أيقوناتٌ بعرض ٦٤ بكسل لا يسع حقلَ نصّ.
                  if (_isExpanded) _navSearchField(),

                  // Navigation Items — Collapsible Groups
                  // PERF: skipLoadingOnReload/Refresh keeps the previous nav
                  // list visible while the FutureProvider re-fetches on auth
                  // state changes — prevents the spinner flash on every tab.
                  Expanded(
                    child: navItemsAsync.when(
                      skipLoadingOnReload: true,
                      skipLoadingOnRefresh: true,
                      data: (items) {
                        if (!_isExpanded) {
                          // Collapsed mode: show only icons
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final isSelected = widget.currentIndex == item.index;
                              return _buildNavItem(item, index, isSelected);
                            },
                          );
                        }

                        // بحثٌ جارٍ: نتائجُ مسطَّحةٌ بدل المجموعات.
                        if (_navQuery.trim().isNotEmpty) {
                          return _navSearchResults(items);
                        }

                        // Expanded mode: group items by group key
                        final groupOrder = <String>[];
                        final groups = <String, List<NavItemDef>>{};
                        for (final item in items) {
                          final gk = item.group ?? 'other';
                          if (!groups.containsKey(gk)) {
                            groupOrder.add(gk);
                            groups[gk] = [];
                          }
                          groups[gk]!.add(item);
                        }

                        // Find which group the current screen belongs to
                        final activeGroup = items
                            .where((i) => i.index == widget.currentIndex)
                            .map((i) => i.group ?? 'other')
                            .firstOrNull;

                        return _CollapsibleNavGroups(
                          key: ValueKey(locale),
                          groupOrder: groupOrder,
                          groups: groups,
                          activeGroup: activeGroup,
                          currentIndex: widget.currentIndex,
                          onItemTap: _onNavItemTap,
                          itemExtraBuilder: _reportCategoriesFor,
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      error: (e, s) => const Center(
                        child: Icon(Icons.error, color: AppColors.error),
                      ),
                    ),
                  ),

                  // Elevation Banner — shows when cashier has admin override active
                  if (authState.isElevated && _isExpanded)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                PhosphorIconsBold.shieldStar,
                                color: AppColors.warning,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  tr('وضع المدير — {p0}', {'p0': trData(authState.originalUser?.displayName)}),
                                  style: const TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            height: 28,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ref.read(authProvider.notifier).dropElevation();
                                ref.invalidate(userNavItemsProvider);
                                ref.invalidate(userAllowedScreensProvider);
                                ref.invalidate(currentUserPermissionsProvider);
                                // Re-hide sidebar for cashier after elevation drop
                                setState(() {
                                  _isHidden = true;
                                  _isExpanded = false;
                                });
                                // Navigate to POS without full app rebuild
                                appShellNestedNavigatorKey.currentState
                                    ?.popUntil((route) => route.isFirst);
                                widget.onNavigate(1); // AppScreen.pos.index
                              },
                              icon: const Icon(
                                PhosphorIconsBold.arrowUDownLeft,
                                size: 14,
                              ),
                              label:  Text(
                                tr('العودة للكاشير'),
                                style: const TextStyle(fontSize: 11),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.warning,
                                side: const BorderSide(
                                  color: AppColors.warning,
                                  width: 0.5,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // User Info Section
                  if (authState.isAuthenticated) ...[
                    const Divider(color: AppColors.secondaryLight, height: 1),
                    roleAsync.when(
                      data: (role) => Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: _isExpanded ? 16 : 8,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: role == null
                                  ? AppColors.textMuted
                                  : _getRoleColor(role.name),
                              child: Icon(
                                role == null
                                    ? PhosphorIconsBold.user
                                    : _getRoleIcon(role.name),
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            if (_isExpanded) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trData(authState.originalUser?.displayName),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      role == null ? '' : trData(role.name),
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  PhosphorIconsBold.signOut,
                                  color: AppColors.textMuted,
                                  size: 20,
                                ),
                                onPressed: _showLogoutConfirmation,
                                tooltip: tr('تسجيل الخروج'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      loading: () => const SizedBox(
                        height: 60,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (e, s) => const SizedBox.shrink(),
                    ),
                  ],

                  // Language Toggle — available before opening Settings.
                  if (_isExpanded)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: UserLanguageToggle(),
                    ),

                  // Dark Mode Toggle (Sprint 18)
                  if (_isExpanded)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final themeMode = ref.watch(themeModeProvider);
                          final isDark = themeMode == ThemeMode.dark;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => ref.read(themeModeProvider.notifier).setDarkMode(!isDark),
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isDark ? PhosphorIconsBold.sun : PhosphorIconsBold.moon,
                                    color: isDark ? AppColors.warning : AppColors.textMuted,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isDark ? tr('الوضع الفاتح') : tr('الوضع الداكن'),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 20,
                                    width: 34,
                                    child: Switch(
                                      value: isDark,
                                      onChanged: (v) => ref.read(themeModeProvider.notifier).setDarkMode(v),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      activeThumbColor: AppColors.warning,
                                      inactiveThumbColor: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // Collapse / Hide Buttons (#12)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Hide button (return to cashier mode)
                      if (_isExpanded)
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              // Drop elevation if elevated
                              if (authState.isElevated) {
                                ref.read(authProvider.notifier).dropElevation();
                                ref.invalidate(userNavItemsProvider);
                                ref.invalidate(userAllowedScreensProvider);
                                ref.invalidate(currentUserPermissionsProvider);
                              }
                              // Collapse BOTH flags. Leaving `_isExpanded=true`
                              // here caused the sidebar to redisplay in 200-
                              // px "full" state the next time `_isHidden`
                              // flipped — and in some paths the subsequent
                              // re-show happened WITHOUT re-prompting for
                              // admin password. Setting both guarantees a
                              // clean hidden/collapsed state.
                              setState(() {
                                _isHidden = true;
                                _isExpanded = false;
                              });
                            },
                            child: Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child:  Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    PhosphorIconsBold.arrowUDownLeft,
                                    color: AppColors.textMuted,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tr('إخفاء'),
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // #3: Exit app button
                      if (_isExpanded)
                        InkWell(
                          onTap: _showExitConfirmation,
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child:  Row(
                              children: [
                                const Icon(
                                  PhosphorIconsBold.power,
                                  color: AppColors.error,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tr('إغلاق'),
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Main Content — wrapped in InactivityDetector (Sprint 18)
            Expanded(
              child: InactivityDetector(
                child: Column(
                  children: [
                    // ⚠️ **حلَّ محلَّ `AppBreadcrumbs`.** ذاك كان يعرض مدخلاً
                    // أو مدخلَين لأنّ `setBreadcrumbs` يستبدل القائمةَ في
                    // كلّ تنقّل — وصفرَ مداخلَ قابلةٍ للنقر، لأنّ الوحيدَ
                    // الذي يحمل `onTap` هو عينُ الوحيدِ الذي يُرسَم
                    // بـ`isLast ? null : item.onTap`.
                    if ((ref.watch(showTopBarProvider).value ?? true) &&
                        widget.tabs.isNotEmpty) ...[
                      ScreenTabsBar(
                        tabs: widget.tabs,
                        active: widget.currentIndex,
                        onSelect: widget.onSelectTab,
                        onClose: widget.onCloseTab,
                        onHome: widget.onHomeTab,
                      ),
                      // القاعدةُ ح‑٢: مسارُ التنقّل يبقى — **تحت** شريط
                      // التابات. ويُشتقُّ من فهرس الشاشة لا يُدفَع إليه،
                      // فلا شاشةَ تنسى أن تُعلن موضعَها.
                      //
                      // ⚠️ **وفي نفس الشرط لا في شرطٍ ثانٍ مطابق.** شرطان
                      // متطابقان يفترقان في أوّل تعديل، فيبقى مسارٌ معلَّقاً
                      // بلا تاباتٍ فوقَه — وهو ما يقيسه حارسُ التوصيل.
                      ScreenBreadcrumbs(screenIndex: widget.currentIndex),
                    ],
                    Expanded(
                      child: Navigator(
                        key: appShellNestedNavigatorKey,
                        onGenerateRoute: (_) => MaterialPageRoute(
                          builder: (_) => widget.child,
                          settings: RouteSettings(name: 'screen_${widget.currentIndex}'),
                        ),
                        observers: [HeroController()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        )), // close Row + close Expanded
        ]), // close Column.children + close Column
          ),
        );
      },
    );
  }

  /// اختصارُ الزرّ العائم إلى شاشة «البيع السريع» — نفسُ مسارَ التنقّل الذي
  /// يستعمله زرُّ «العودة للكاشير» أعلاه (بانر الرفع)، بلا فحصِ سلّةٍ لأن
  /// هذا الزرّ لا يظهر أصلاً وأنت داخل شاشة البيع (شوف
  /// [shouldShowPosShortcutFab]) — فلا مغادرةَ لها هنا، فقط دخولٌ إليها.
  void _navigateToPosShortcut() {
    appShellNestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    widget.onNavigate(AppScreen.pos.value);
  }

  /// مدخلُ الوضع المطويّ — أيقونةٌ بلا تسمية.
  ///
  /// ⚠️ **ويُفوِّض إلى [_onNavItemTap] الآن.** كان ينسخ منطقَ النقر كاملاً،
  /// فبقي فيه حارسُ السلّة المنزوعُ من هناك — نسختان تفترقان في أوّل تعديل.
  /// وتسجيلُ النشاط كان في إحداهما دونَ الأخرى أصلاً: من تنقّل وشريطُه
  /// مطويٌّ لم يُسجَّل تنقّلُه.
  Widget _buildNavItem(NavItemDef item, int index, bool isSelected) {
    return _EnhancedNavItem(
      item: item,
      isExpanded: _isExpanded,
      isSelected: isSelected,
      onTap: () => _onNavItemTap(item),
    );
  }

  Color _getRoleColor(String? role) {
    if (role == 'مدير النظام') return AppColors.error;
    if (role == 'مدير') return AppColors.warning;
    if (role == 'كاشير') return AppColors.info;
    return AppColors.textMuted;
  }

  IconData _getRoleIcon(String? role) {
    if (role == 'مدير النظام') return PhosphorIconsBold.shieldCheck;
    if (role == 'مدير') return PhosphorIconsBold.userGear;
    return PhosphorIconsBold.user;
  }
}
