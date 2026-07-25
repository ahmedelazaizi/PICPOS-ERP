import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory;
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/theme/app_colors.dart';

import '../../core/design_system/typography.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/config/business_profile_provider.dart';
import '../../data/providers/providers.dart';
import '../widgets/permission_guard.dart';
import '../widgets/settings/backup_restore_widget.dart';
import '../widgets/settings/company_info_widget.dart';
import 'users_management_screen.dart';
import '../widgets/settings/hardware_settings_widget.dart';
import '../widgets/settings/pos_settings_widget.dart';
import '../widgets/settings/user_management_widget.dart';
import '../widgets/settings/permissions_management_widget.dart';
import 'settings/widgets/server_perms_toggle_dialog.dart';
import 'account_mapping_settings_screen.dart';

import 'printers_screen.dart';
import 'pos_terminals_screen.dart';
import 'delivery_management_screen.dart';
import 'invoice_designer_screen.dart';
import '../widgets/settings/activation_dialog.dart';
import '../../services/license_service.dart';
import '../../core/config/app_config.dart';
import 'developer_tools_screen.dart';
import '../../core/navigation/screen_id.dart';
import '../../core/constants/app_constants.dart';
import '../../services/network_service.dart';
import '../../services/sync_service.dart';
import '../../services/websocket_sync_client.dart';
import '../widgets/settings/fingerprint_settings_widget.dart';
import '../../services/cfd_service.dart';
import '../../services/cfd/cfd_transport.dart';
import '../widgets/settings/kds_settings_widget.dart';
import '../widgets/settings/modifier_management_widget.dart';
import '../../services/cfd/cfd_serial_transport.dart';
import '../../services/cfd/cfd_usb_transport.dart';
import '../../services/cfd/cfd_hdmi_transport.dart';
import '../../services/costing_method_service.dart';
// Spec 135 NOTE 1 — the session-timeout selector below writes the single
// canonical `session_timeout_minutes` key; invalidate its provider on save so
// the live InactivityDetector picks the change up without an app restart.
import '../../services/session_timeout_service.dart' show sessionTimeoutProvider;
import '../../services/stock_shortage_policy_service.dart';
import '../widgets/settings/branch_scope_admin_dialog.dart';
import '../widgets/settings/cheque_receipt_drift_admin_dialog.dart';
import '../widgets/settings/mirror_parity_audit_dialog.dart';
import '../widgets/settings/database_settings_widget.dart';
import '../touch_keyboard/providers/touch_mode_provider.dart';

// Part files — extracted from this file to reduce size (PIR God File split)
part 'settings/general_settings_widgets.dart';
part 'settings/scale_barcode_settings.dart';
part 'settings/admin_home_settings.dart';
part 'settings/cfd_settings_card.dart';
part 'settings/network_mode_settings.dart';
part 'settings/touch_input_settings.dart';

/// Settings Screen - Restored with all "new" features and premium look
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isUnlocked = false;
  bool _isCheckingPassword = true;

  @override
  void initState() {
    super.initState();
    _checkPasswordGate();
  }

  Future<void> _checkPasswordGate() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final password = await settingsRepo.getSetting('settings_access_password');
    if (password == null || password.isEmpty) {
      // No password set — allow direct access
      if (mounted) setState(() { _isUnlocked = true; _isCheckingPassword = false; });
    } else {
      if (mounted) setState(() => _isCheckingPassword = false);
      if (mounted) _showPasswordDialog(password);
    }
  }

  void _showPasswordDialog(String correctPassword) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('🔒 كلمة مرور الإعدادات'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'أدخل كلمة المرور',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (val) {
              if (val == correctPassword) {
                Navigator.pop(ctx);
                setState(() => _isUnlocked = true);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text == correctPassword) {
                  Navigator.pop(ctx);
                  setState(() => _isUnlocked = true);
                } else {
                  AppToast.show(ctx, 'كلمة المرور غير صحيحة', type: ToastType.error);
                }
              },
              child: const Text('دخول'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final currentPw = await settingsRepo.getSetting('settings_access_password');
    if (!mounted) return;
    final controller = TextEditingController(text: currentPw ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('🔑 تغيير كلمة مرور الإعدادات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الجديدة (اتركها فارغة لإلغاء الحماية)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'اتركها فارغة لإلغاء حماية كلمة المرور بالكامل',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await settingsRepo.saveSetting('settings_access_password', result);
      if (mounted) {
        AppToast.show(context, result.isEmpty ? 'تم إلغاء حماية كلمة المرور' : 'تم تغيير كلمة المرور بنجاح', type: ToastType.success);
      }
    }
  }

  Future<void> _showSectionPasswordDialog(String key, String title) async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final currentPw = await settingsRepo.getSetting(key);
    if (!mounted) return;
    
    final controller = TextEditingController(text: currentPw ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text('🔑 كلمة مرور $title'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الجديدة لـ $title',
                  border: const OutlineInputBorder(),
                  helperText: 'اتركها فارغة لإلغاء الحماية عن هذا القسم',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await settingsRepo.saveSetting(key, result);
      if (mounted) {
        AppToast.show(
          context, 
          result.isEmpty ? 'تم إلغاء الحماية عن $title' : 'تم حفظ كلمة مرور $title بنجاح', 
          type: ToastType.success
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPassword) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_isUnlocked) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('الإعدادات محمية بكلمة مرور'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final settingsRepo = ref.read(settingsRepositoryProvider);
                  final pw = await settingsRepo.getSetting('settings_access_password');
                  if (pw != null && pw.isNotEmpty && mounted) _showPasswordDialog(pw);
                },
                child: const Text('إدخال كلمة المرور'),
              ),
            ],
          ),
        ),
      );
    }
    return _buildSettingsContent(context);
  }

  Widget _buildSettingsContent(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    // Phase C2: subscribe to runtime feature flags + profile so the
    // settings sections (HR / kitchen / delivery / printer groups…)
    // appear or disappear immediately when the developer flips a flag.
    final features = ref.watch(featureFlagsProvider);
    final profile = ref.watch(businessProfileProvider);

    // #Phase3: Log screen access
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      if (user != null) {
        ref
            .read(activityLoggerProvider)
            .logNavigation(user.id, user.displayName, 'الإعدادات (Settings)');
      }
    });

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Row(
                children: [
                  Icon(
                    PhosphorIconsBold.gear,
                    size: 32,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 12),
                  Text('الإعدادات', style: AppTypography.h1),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    // ═══ 1. النظام والمظهر ═══
                    _buildSettingsCard(
                      title: 'إعدادات النظام والمظهر',
                      children: [
                        ListTile(
                          leading: const Icon(PhosphorIconsBold.buildings),
                          title: const Text('معلومات الشركة'),
                          trailing: const Icon(PhosphorIconsBold.caretLeft),
                          onTap: () => showCompanyInfoDialog(context),
                        ),
                        const _IndustryModeToggle(),
                        const _CurrencySelector(),
                        ListTile(
                          leading: Icon(
                            themeMode == ThemeMode.dark
                                ? PhosphorIconsBold.moon
                                : themeMode == ThemeMode.light
                                ? PhosphorIconsBold.sun
                                : PhosphorIconsBold.monitor,
                            color: themeMode == ThemeMode.dark
                                ? Colors.amber
                                : themeMode == ThemeMode.light
                                ? Colors.orange
                                : AppColors.primary,
                          ),
                          title: const Text('مظهر التطبيق'),
                          subtitle: Text(_getThemeModeLabel(themeMode)),
                          trailing: const Icon(PhosphorIconsBold.caretLeft),
                          onTap: () =>
                              _showThemeSelector(context, ref, themeMode),
                        ),
                        const _DefaultHomeScreenSelector(),
                        ListTile(
                          leading: const Icon(
                            PhosphorIconsBold.database,
                            color: AppColors.warning,
                          ),
                          title: const Text('قاعدة البيانات'),
                          subtitle: const Text(
                            'اختيار نوع قاعدة البيانات (SQLite/PostgreSQL)',
                          ),
                          trailing: const Icon(PhosphorIconsBold.caretLeft),
                          onTap: () => showDatabaseSettingsDialog(context),
                        ),
                        const Divider(height: 1),
                        // Phase 5C admin tools — branch-scope cleanup +
                        // orphan-JE diagnostic. Read-only by default; the
                        // destructive cleanup step requires explicit
                        // confirmation inside the dialog.
                        // Spec 114 + 114b — party sub-account repair and
                        // invoice JE re-post tools are surfaced inside the
                        // admin tools dialog (not as separate Settings
                        // rows) so all maintenance lives in one place.
                        ListTile(
                          leading: const Icon(
                            PhosphorIconsBold.shield,
                            color: AppColors.primary,
                          ),
                          title: const Text('أدوات صيانة المسؤول'),
                          subtitle: const Text(
                            'حصر بيانات الفروع، تشخيص القيود، إصلاح حسابات الأطراف، إعادة ترحيل القيود',
                          ),
                          trailing: const Icon(PhosphorIconsBold.caretLeft),
                          onTap: () => showBranchScopeAdminDialog(context),
                        ),
                        // Spec 131 FR-010 — mirror-only audit entry. Caller
                        // gates by mirror mode; the dialog itself shows an
                        // Arabic notice when invoked outside mirror mode.
                        if (NetworkService.instance.mode == NetworkMode.mirror)
                          ListTile(
                            leading: const Icon(
                              PhosphorIconsBold.arrowsCounterClockwise,
                              color: AppColors.primary,
                            ),
                            title: const Text('تدقيق مزامنة المرآة'),
                            subtitle: const Text(
                              'مقارنة البيانات الأساسية محلياً مع السيرفر + '
                              'إعادة المزامنة الكاملة عند الحاجة',
                            ),
                            trailing:
                                const Icon(PhosphorIconsBold.caretLeft),
                            onTap: () =>
                                showMirrorParityAuditDialog(context),
                          ),
                        // Spec 133 FR-011 — server-only audit for historical
                        // double-credit cheques. Read-only; repair deferred.
                        if (NetworkService.instance.isServer)
                          ListTile(
                            leading: const Icon(
                              PhosphorIconsBold.magnifyingGlass,
                              color: AppColors.warning,
                            ),
                            title: const Text('تدقيق ازدواج شيكات القبض'),
                            subtitle: const Text(
                              'سرد العملاء الذين تأثرت أرصدتهم بازدواج تسجيل '
                              'سندات قبض الشيكات قبل الإصلاح',
                            ),
                            trailing:
                                const Icon(PhosphorIconsBold.caretLeft),
                            onTap: () =>
                                showChequeReceiptDriftAdminDialog(context),
                          ),
                        const Divider(height: 1),
                        // ── Network/Sync Settings (Client ↔ Server) ──
                        const ExpansionTile(
                          leading: Icon(
                            PhosphorIconsBold.wifiHigh,
                            color: AppColors.success,
                          ),
                          title: Text('إعدادات الربط بين الفروع والسيرفر'),
                          subtitle: Text(
                            'ربط العميل بالسيرفر ومزامنة البيانات',
                          ),
                          children: [_NetworkModeSettings()],
                        ),
                        // Feature 031 — per-device on-screen touch keyboard.
                        const ExpansionTile(
                          leading: Icon(
                            PhosphorIconsBold.handTap,
                            color: AppColors.primary,
                          ),
                          title: Text('نمط الإدخال (لوحة المفاتيح اللمسية)'),
                          subtitle: Text(
                            'تفعيل لوحة المفاتيح على الشاشة لأجهزة POS واللمس',
                          ),
                          children: [_TouchInputSettings()],
                        ),
                        const _ForceSyncPanel(),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ═══ 2. الأجهزة والطباعة ═══
                    _buildSettingsCard(
                      title: 'الأجهزة والطباعة',
                      children: [
                        PermissionGuard(
                          permission: PermissionCodes.settingsPrinter,
                          allowManagerOverride: true,
                          actionName: 'إعدادات الأجهزة',
                          child: ListTile(
                            leading: const Icon(
                              PhosphorIconsBold.printer,
                              color: AppColors.info,
                            ),
                            title: const Text('إعدادات الأجهزة'),
                            subtitle: const Text(
                              'ماسح الباركود، الطابعة الحرارية، والميزان',
                            ),
                            trailing: const Icon(PhosphorIconsBold.caretLeft),
                            onTap: () => showHardwareSettingsDialog(context),
                          ),
                        ),
                        PermissionGuard(
                          permission: PermissionCodes.settingsPrinter,
                          allowManagerOverride: true,
                          actionName: 'إدارة الطابعات',
                          child: ListTile(
                            leading: const Icon(
                              PhosphorIconsBold.printer,
                              color: AppColors.secondary,
                            ),
                            title: const Text('إدارة الطابعات'),
                            subtitle: const Text('طابعات أوامر الشغل للأقسام'),
                            trailing: const Icon(PhosphorIconsBold.caretLeft),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrintersScreen(),
                              ),
                            ),
                          ),
                        ),
                        // Feature 009 / T028b — POS terminals registry +
                        // per-terminal stock-shortage policy.
                        PermissionGuard(
                          permission: PermissionCodes.settingsPrinter,
                          allowManagerOverride: true,
                          actionName: 'نقاط البيع',
                          child: ListTile(
                            leading: const Icon(
                              PhosphorIconsBold.cashRegister,
                              color: AppColors.primary,
                            ),
                            title: const Text('نقاط البيع'),
                            subtitle: const Text(
                                'إدارة الماكينات + سياسة نقص الخامات لكل ماكينة'),
                            trailing: const Icon(PhosphorIconsBold.caretLeft),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PosTerminalsScreen(),
                              ),
                            ),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(
                            PhosphorIconsBold.paintBrush,
                            color: AppColors.info,
                          ),
                          title: const Text('قوالب الفواتير'),
                          subtitle: const Text('إدارة وتخصيص قوالب الطباعة'),
                          trailing: const Icon(PhosphorIconsBold.caretLeft),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const InvoiceDesignerScreen(),
                            ),
                          ),
                        ),
                        const _ScaleBarcodeSettings(),
                        if (features.hrEnabled)
                          const FingerprintSettingsWidget(),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ═══ 3. نقطة البيع ═══
                    _buildSettingsCard(
                      title: 'إعدادات نقطة البيع',
                      children: [
                        ListTile(
                          leading: const Icon(
                            PhosphorIconsBold.shoppingCart,
                            color: AppColors.primary,
                          ),
                          title: const Text('إعدادات نقطة البيع الرئيسية'),
                          subtitle: const Text(
                            'الأزرار، التصنيفات، شبكة المنتجات، السلة، الإيصال',
                          ),
                          trailing: const Icon(PhosphorIconsBold.caretLeft),
                          onTap: () => showPosSettingsDialog(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ═══ 4. المستخدمين والأمان ═══
                    // User + role management are server-authoritative. In
                    // client mode these are hidden — the client cannot create
                    // users (would cause ID collisions) or edit permissions
                    // (they are pulled from the server on every sync).
                    _buildSettingsCard(
                      title: 'المستخدمين والأمان',
                      children: [
                        if (!NetworkService.instance.isClient) ...[
                          PermissionGuard(
                            permission: PermissionCodes.usersManage,
                            allowManagerOverride: true,
                            actionName: 'إدارة المستخدمين',
                            child: ListTile(
                              leading: const Icon(
                                PhosphorIconsBold.usersThree,
                                color: AppColors.primary,
                              ),
                              title: const Text('إدارة المستخدمين'),
                              subtitle: const Text(
                                'إضافة مستخدمين وتغيير كلمات المرور',
                              ),
                              trailing: const Icon(PhosphorIconsBold.caretLeft),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const UsersManagementScreen()),
                              ),
                            ),
                          ),
                          PermissionGuard(
                            permission: PermissionCodes.rolesManage,
                            allowManagerOverride: true,
                            actionName: 'إدارة صلاحيات الأدوار',
                            child: ListTile(
                              leading: const Icon(
                                PhosphorIconsBold.shieldPlus,
                                color: AppColors.warning,
                              ),
                              title: const Text('إدارة صلاحيات الأدوار'),
                              subtitle: const Text(
                                'تحديد صلاحيات كل دور بشكل تفصيلي',
                              ),
                              trailing: const Icon(PhosphorIconsBold.caretLeft),
                              onTap: () =>
                                  showPermissionsManagementDialog(context),
                            ),
                          ),
                          // Spec 078: server-side per-user permission toggle
                          // (Spec 060 Phase 2 slice 3). Same rolesManage gate
                          // — operators who can change role permissions can
                          // also flip the server enforcement of those perms.
                          PermissionGuard(
                            permission: PermissionCodes.rolesManage,
                            allowManagerOverride: true,
                            actionName: 'فحص الصلاحيات على السيرفر',
                            child: _ServerPermsToggleTile(),
                          ),
                          const Divider(height: 1),
                        ] else
                          // Client mode — show an informational tile instead
                          const ListTile(
                            leading: Icon(
                              PhosphorIconsBold.usersThree,
                              color: AppColors.info,
                            ),
                            title: Text('إدارة المستخدمين والصلاحيات'),
                            subtitle: Text(
                              'تتم إدارتها من السيرفر — وضع العميل للقراءة فقط',
                              style: TextStyle(fontSize: 12),
                            ),
                            enabled: false,
                          ),
                        const _SessionTimeoutSetting(),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            PhosphorIconsBold.lockKey,
                            color: AppColors.error,
                          ),
                          title: const Text('كلمة مرور الإعدادات'),
                          subtitle: const Text('حماية الإعدادات بكلمة مرور'),
                          trailing: const Icon(PhosphorIconsBold.caretLeft),
                          onTap: _showChangePasswordDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ═══ 4.1 حماية الأقسام ═══
                    // Hidden for basic supermarket — only relevant for editions with multiple sections
                    if (features.kitchenEnabled || features.hrEnabled) ...[
                      _buildSettingsCard(
                        title: 'حماية الأقسام (كلمات مرور بديلة)',
                        children: [
                          ListTile(
                            leading: const Icon(PhosphorIconsBold.archive, color: AppColors.info),
                            title: const Text('كلمة مرور المخازن والمخزون'),
                            onTap: () => _showSectionPasswordDialog('inventory_access_password', 'المخازن والمخزون'),
                          ),
                          ListTile(
                            leading: const Icon(PhosphorIconsBold.bank, color: AppColors.success),
                            title: const Text('كلمة مرور الحسابات والمالية'),
                            onTap: () => _showSectionPasswordDialog('accounting_access_password', 'الحسابات والمالية'),
                          ),
                          ListTile(
                            leading: const Icon(PhosphorIconsBold.shoppingBagOpen, color: AppColors.primary),
                            title: const Text('كلمة مرور المشلريات'),
                            onTap: () => _showSectionPasswordDialog('purchases_access_password', 'المشتريات'),
                          ),
                          ListTile(
                            leading: const Icon(PhosphorIconsBold.chartPieSlice, color: AppColors.warning),
                            title: const Text('كلمة مرور التقارير'),
                            onTap: () => _showSectionPasswordDialog('reports_access_password', 'التقارير'),
                          ),
                          if (features.hrEnabled)
                            ListTile(
                              leading: const Icon(PhosphorIconsBold.users, color: AppColors.secondary),
                              title: const Text('كلمة مرور شؤون الموظفين'),
                              onTap: () => _showSectionPasswordDialog('hr_access_password', 'شؤون الموظفين'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ═══ 5. الإعدادات المالية ═══
                    PermissionGuard(
                      permission: PermissionCodes.settingsBackup,
                      allowManagerOverride: true,
                      actionName: 'إعدادات المحاسبة',
                      child: _buildSettingsCard(
                        title: 'الإعدادات المالية والمحاسبية',
                        children: [
                          ListTile(
                            leading: const Icon(PhosphorIconsBold.bookOpen, color: AppColors.primary),
                            title: const Text('ربط الحسابات التلقائي'),
                            subtitle: const Text('تحديد الحسابات الدفترية للعمليات المؤتمتة (متقدم)'),
                            trailing: const Icon(PhosphorIconsBold.caretLeft),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AccountMappingSettingsScreen()),
                            ),
                          ),
                          const _CostingMethodToggle(),
                          // Feature 009 / T027 + T028 — global default
                          // shortage policy + per-branch overrides.
                          // Per-terminal overrides live on the new
                          // POS terminals screen (T028b).
                          const _StockShortagePolicyToggle(),
                          const _StockShortagePolicyPerBranchTile(),
                          // Negative-sales toggle moved to POS settings
                          // (Feature 022 follow-up) — operators expected
                          // it under "إعدادات نقطة البيع" → "إعدادات
                          // نقطة البيع الرئيسية", not under Financial
                          // settings. The setting key is unchanged
                          // (`enable_negative_sales`); the orchestrator
                          // reads the same value.
                          // ETA e-invoicing toggles — hidden for basic supermarket
                          if (profile != BusinessProfile.supermarket) ...[
                            const Divider(height: 1),
                            const _EInvoiceVisibilityToggles(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ═══ 6. إدارة البيانات ═══
                    PermissionGuard(
                      permission: PermissionCodes.settingsBackup,
                      allowManagerOverride: true,
                      actionName: 'إدارة البيانات',
                      child: _buildSettingsCard(
                        title: 'إدارة البيانات',
                        children: [const BackupRestoreWidget()],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ═══ 7. التكاملات والخدمات ═══
                    _buildSettingsCard(
                      title: 'التكاملات والخدمات',
                      children: [
                        if (features.deliveryEnabled) ...[
                          const _DeliveryToggle(),
                          PermissionGuard(
                            permission: PermissionCodes.deliveryManage,
                            allowManagerOverride: true,
                            actionName: 'إدارة التوصيل',
                            child: ListTile(
                              leading: const Icon(
                                PhosphorIconsBold.moped,
                                color: AppColors.success,
                              ),
                              title: const Text('إدارة التوصيل'),
                              subtitle: const Text('شركات التوصيل والمناديب'),
                              trailing: const Icon(PhosphorIconsBold.caretLeft),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const DeliveryManagementScreen(),
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                        const _CFDSettingsCard(),
                        if (features.kitchenEnabled) ...[
                          const Divider(height: 1),
                          const PermissionGuard(
                            permission: PermissionCodes.kdsSettings,
                            allowManagerOverride: true,
                            actionName: 'إعدادات شاشة المطبخ',
                            child: KdsSettingsWidget(),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                              PhosphorIconsBold.forkKnife,
                              color: AppColors.warning,
                            ),
                            title: const Text('إدارة الإضافات والمعدلات'),
                            subtitle: const Text(
                              'مجموعات الإضافات والخيارات للأصناف (صوصات، أحجام..)',
                            ),
                            trailing: const Icon(PhosphorIconsBold.caretLeft),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ModifierManagementWidget(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ═══ 8. عن البرنامج والترخيص ═══
                    _buildAboutCard(),

                    const SizedBox(height: 16),
                    _buildLicenseCard(context, ref),

                    // P5: "Copy Diagnostic Log" card — visible to ALL users.
                    // Lets a cashier/manager who hits a problem pull the
                    // last 200 log lines and send them to the admin without
                    // needing access to the developer-tools screen or the
                    // Documents folder. Pure read-only operation — no
                    // sensitive data exposure beyond what's already in the
                    // log file.
                    const SizedBox(height: 16),
                    _buildCopyLogCard(context),

                    // Phase D: developer-tools entry. The screen
                    // self-gates with a password — this tile is just a
                    // discoverable surface for the developer.
                    //
                    // P5 (visibility update): expose the tile to system
                    // admins in Release builds too — admin users routinely
                    // need DB diagnostics and feature toggles. The screen
                    // itself remains password-protected (PBKDF2-SHA256), so
                    // accidental navigation by a non-developer admin is
                    // still safe — they hit the password prompt and stop.
                    // Non-admin users (cashier/manager) never see the tile,
                    // matching the previous Release behaviour for them.
                    Consumer(
                      builder: (context, ref, _) {
                        final permsAsync =
                            ref.watch(currentUserPermissionsProvider);
                        final isAdmin = permsAsync.maybeWhen(
                          data: (codes) =>
                              codes.contains('system_admin') ||
                              codes.contains('*'),
                          orElse: () => false,
                        );
                        if (!kDebugMode && !isAdmin) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _buildDeveloperToolsCard(context),
                        );
                      },
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'تلقائي (حسب إعدادات النظام)';
      case ThemeMode.light:
        return 'الوضع النهاري';
      case ThemeMode.dark:
        return 'الوضع الليلي';
    }
  }

  void _showThemeSelector(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('اختر مظهر التطبيق'),
          children: [
            _buildThemeOption(
              ctx,
              ref,
              ThemeMode.system,
              'تلقائي (النظام)',
              PhosphorIconsBold.monitor,
              current,
            ),
            _buildThemeOption(
              ctx,
              ref,
              ThemeMode.light,
              'الوضع النهاري',
              PhosphorIconsBold.sun,
              current,
            ),
            _buildThemeOption(
              ctx,
              ref,
              ThemeMode.dark,
              'الوضع الليلي',
              PhosphorIconsBold.moon,
              current,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
    String label,
    IconData icon,
    ThemeMode current,
  ) {
    final isSelected = mode == current;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppColors.primary : null),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(PhosphorIconsBold.check, color: AppColors.success)
          : null,
      onTap: () {
        ref.read(themeModeProvider.notifier).setMode(mode);
        // #Forensic Log: Theme change
        try {
          final auth = ref.read(authProvider);
          final logger = ref.read(activityLoggerProvider);
          logger.logSettingsChange(
            auth.user?.id ?? 0,
            auth.user?.displayName ?? '',
            'مظهر التطبيق',
            newValue: label,
          );
        } catch (e) {
          debugPrint('[ActivityLog] Error: $e');
        }
        Navigator.pop(context);
      },
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: AppTypography.h4),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Logo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('logo.PNG', fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'UralCash',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const Text(
              'نظام الكاشير المتكامل',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            const Text(
              'الإصدار 1.0.0',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const Divider(height: 24),
            // Developer Info
            const Text(
              'تطوير: Ural Technology',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Contact Links
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildContactChip(
                  PhosphorIconsBold.envelope,
                  'Info@uraljo.com',
                ),
                _buildContactChip(PhosphorIconsBold.globe, 'www.uraljo.com'),
                _buildContactChip(
                  PhosphorIconsBold.whatsappLogo,
                  '+962797990989',
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Social Icons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(
                    PhosphorIconsBold.facebookLogo,
                    color: Color(0xFF1877F2),
                  ),
                  onPressed: () => launchUrl(Uri.parse('https://www.facebook.com/uraltechnology')),
                  tooltip: 'Facebook',
                ),
                IconButton(
                  icon: const Icon(
                    PhosphorIconsBold.instagramLogo,
                    color: Color(0xFFE4405F),
                  ),
                  onPressed: () => launchUrl(Uri.parse('https://www.instagram.com/uraltechnology')),
                  tooltip: 'Instagram',
                ),
                IconButton(
                  icon: const Icon(
                    PhosphorIconsBold.whatsappLogo,
                    color: Color(0xFF25D366),
                  ),
                  onPressed: () => launchUrl(Uri.parse('https://wa.me/962797990989')),
                  tooltip: 'WhatsApp',
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '© 2026 Ural Technology',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseCard(BuildContext context, WidgetRef ref) {
    final activationAsync = ref.watch(activationStatusProvider);

    return activationAsync.when(
      data: (isActivated) => Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isActivated
                ? AppColors.success.withValues(alpha: 0.5)
                : AppColors.warning.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: ListTile(
          leading: Icon(
            isActivated
                ? PhosphorIconsBold.checkCircle
                : PhosphorIconsBold.info,
            color: isActivated ? AppColors.success : AppColors.warning,
          ),
          title: Text(
            isActivated ? 'النسخة مفعلة بالكامل' : 'نسخة تجريبية محدودة',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            isActivated
                ? 'لديك صلاحية الوصول لكافة مميزات النظام بدون قيود.'
                : 'هذه النسخة محدودة بـ 50 صنف/عميل. قم بالتفعيل لإزالة القيود.',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: isActivated
              ? null
              : ElevatedButton(
                  onPressed: () => showActivationDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(100, 36),
                  ),
                  child: const Text('تفعيل الآن'),
                ),
        ),
      ),
      loading: () =>
          const Card(child: ListTile(title: Text('جاري التحقق من الترخيص...'))),
      error: (_, _) =>
          const Card(child: ListTile(title: Text('خطأ في التحقق من الترخيص'))),
    );
  }

  /// Phase D: surface for opening the developer-tools screen. The
  /// screen itself prompts for the developer password — this tile only
  /// makes the entry discoverable to anyone who can read the settings
  /// page (admin or higher).
  Widget _buildDeveloperToolsCard(BuildContext context) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.04),
      child: ListTile(
        leading: const Icon(
          PhosphorIconsBold.shieldStar,
          color: AppColors.primary,
        ),
        title: const Text(
          'أدوات المطوّر',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'تغيير ملف النشاط، نمط التشغيل، الميزات وكلمة مرور المطوّر '
          '(محمى بكلمة مرور منفصلة).',
          style: TextStyle(fontSize: 12),
        ),
        trailing: const Icon(PhosphorIconsBold.caretLeft),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DeveloperToolsScreen(),
          ),
        ),
      ),
    );
  }

  /// P5: Copies the last 200 lines of the diagnostic log to clipboard.
  /// Visible to every user — a cashier who hits a problem can grab the log
  /// in two taps and WhatsApp it to the admin without leaving the app or
  /// needing access to developer tools.
  Widget _buildCopyLogCard(BuildContext context) {
    return Card(
      color: AppColors.info.withValues(alpha: 0.04),
      child: ListTile(
        leading: const Icon(
          PhosphorIconsBold.clipboard,
          color: AppColors.info,
        ),
        title: const Text(
          'نسخ اللوج التشخيصى',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'انسخ آخر 200 سطر من سجل التشخيص لإرساله للمدير عند حدوث مشكلة.',
          style: TextStyle(fontSize: 12),
        ),
        trailing: const Icon(PhosphorIconsBold.copy),
        onTap: () async {
          try {
            final dir = await getApplicationDocumentsDirectory();
            final candidates = <String>{
              // Spec 136 ISS-5 — the active mode-labelled login log first,
              // then the legacy unlabelled name for older sessions.
              DiagnosticLogger.currentFileName,
              'uralcash_login_log.txt',
              'uralcash_startup_log.txt',
              'server_errors.log',
            }.toList();
            final buffer = StringBuffer();
            for (final name in candidates) {
              final f = File('${dir.path}/$name');
              if (!await f.exists()) continue;
              final lines = await f.readAsLines();
              final tail = lines.length > 200
                  ? lines.sublist(lines.length - 200)
                  : lines;
              buffer
                ..writeln('═══════════════════════════════════════════')
                ..writeln('FILE: $name (last ${tail.length} lines)')
                ..writeln('═══════════════════════════════════════════');
              for (final l in tail) {
                buffer.writeln(l);
              }
              buffer.writeln();
            }
            if (buffer.isEmpty) {
              if (context.mounted) {
                AppToast.show(
                  context,
                  'لا توجد ملفات لوج بعد',
                  type: ToastType.warning,
                );
              }
              return;
            }
            await Clipboard.setData(ClipboardData(text: buffer.toString()));
            if (context.mounted) {
              AppToast.show(
                context,
                'تم نسخ اللوج إلى الحافظة — الصقه فى الواتساب أو الإيميل',
                type: ToastType.success,
              );
            }
          } catch (e) {
            if (context.mounted) {
              AppToast.show(
                context,
                'تعذّر قراءة اللوج: $e',
                type: ToastType.error,
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildContactChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// E-Invoicing visibility toggles — hide/show ETA/JOFOTARA sections
class _EInvoiceVisibilityToggles extends ConsumerStatefulWidget {
  const _EInvoiceVisibilityToggles();

  @override
  ConsumerState<_EInvoiceVisibilityToggles> createState() => _EInvoiceVisibilityTogglesState();
}

class _EInvoiceVisibilityTogglesState extends ConsumerState<_EInvoiceVisibilityToggles> {
  bool _showEta = true;
  bool _showJofotara = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepositoryProvider);
    final etaVal = await repo.getSetting('show_eta_einvoice');
    final joVal = await repo.getSetting('show_jofotara_einvoice');
    if (mounted) {
      setState(() {
        _showEta = etaVal != 'false';
        _showJofotara = joVal != 'false';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Text('🇪🇬', style: TextStyle(fontSize: 22)),
          title: const Text('إظهار الفوترة المصرية (ETA)'),
          subtitle: const Text('منظومة ETA — مصلحة الضرائب المصرية'),
          value: _showEta,
          onChanged: (v) async {
            setState(() => _showEta = v);
            await ref.read(settingsRepositoryProvider).saveSetting('show_eta_einvoice', v.toString());
          },
        ),
        SwitchListTile(
          secondary: const Text('🇯🇴', style: TextStyle(fontSize: 22)),
          title: const Text('إظهار الفوترة الأردنية (JOFOTARA)'),
          subtitle: const Text('منظومة JOFOTARA — دائرة ضريبة الدخل'),
          value: _showJofotara,
          onChanged: (v) async {
            setState(() => _showJofotara = v);
            await ref.read(settingsRepositoryProvider).saveSetting('show_jofotara_einvoice', v.toString());
          },
        ),
      ],
    );
  }
}

// Spec 078 — Settings tile for server_per_user_perms_enabled.
// Self-contained ConsumerStatefulWidget so it can read the flag state,
// drive the Switch, and reload after the dialog closes — without
// burdening the parent _SettingsScreenState with another setState path.
class _ServerPermsToggleTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ServerPermsToggleTile> createState() =>
      _ServerPermsToggleTileState();
}

class _ServerPermsToggleTileState
    extends ConsumerState<_ServerPermsToggleTile> {
  bool _enabled = false;
  bool _loaded = false;

  static const String _key = 'server_per_user_perms_enabled';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final db = ref.read(databaseProvider);
    final v = await db.getSettingValue(_key);
    if (mounted) {
      setState(() {
        _enabled = v == 'true';
        _loaded = true;
      });
    }
  }

  Future<void> _openDialog() async {
    final db = ref.read(databaseProvider);
    final changed = await ServerPermsToggleDialog.show(
      context: context,
      db: db,
      currentlyEnabled: _enabled,
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = !_loaded
        ? '...'
        : (_enabled
            ? 'مُفعّل — السيرفر يفحص صلاحيات كل مستخدم على كل عملية'
            : 'غير مُفعّل — السيرفر يقبل أي مستخدم مُعرَّف (الوضع الافتراضي)');
    return ListTile(
      leading: Icon(
        PhosphorIconsBold.shieldCheck,
        color: _enabled ? AppColors.success : AppColors.primary,
      ),
      title: const Text('فحص الصلاحيات على السيرفر'),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: _loaded
          ? Switch(value: _enabled, onChanged: (_) => _openDialog())
          : const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
      onTap: _openDialog,
    );
  }
}

