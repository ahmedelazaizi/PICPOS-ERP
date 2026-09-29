// ---------------------------------------------------------------------------
// منطق منسوخ من settings_screen.dart (God-file بـ٦ `part`) — أي إصلاح منطقي
// يتصلّح في المصدر أولاً ثم يُنقل بـ patch لهذا الملف ومصاحبيه (مصيدة النسخ
// §٥.٨). لا يُنسخ أبداً من D:\URAL-ERP.
//
// الشاشة الأصل (lib/presentation/screens/settings_screen.dart، 1406 سطر) بلا
// منطق مختلف — بوابة كلمة مرور الإعدادات، ثم محتوى الشاشة مقسّم لـ٦ أقسام
// (النظام والمظهر، الأجهزة والطباعة، البيع السريع، المستخدمين والأمان، حماية
// الأقسام، الإعدادات المالية، إدارة البيانات، التكاملات والخدمات) بالإضافة لـ
// عن البرنامج/الترخيص/أدوات المطوّر/نسخ اللوج. تُقسَّم عبر ٦ ملفات `part`
// (general_settings_widgets.dart / scale_barcode_settings.dart /
// admin_home_settings.dart / cfd_settings_card.dart /
// network_mode_settings.dart / touch_input_settings.dart) — الفورك هنا ينسخ
// الستة حرفياً (فقط `part of` تغيّر لهذا الملف) + هذا الـ shell. كل الكلاسات
// المُعرَّفة في الأقسام الستة وفي هذا الـ shell خاصة (بادئة `_`) — خصوصية
// Dart مكتبة-بمكتبة، فمفيش تعارض أسماء (ambiguous import) مع
// settings_screen.dart الأصلي حتى مع استيراد الاثنين بلا بادئة في
// app_main_screen.dart؛ الاسم العام الوحيد (`SettingsScreen`) اتغيّر أصلاً
// لـ `SettingsPicposScreen`. مفيش أي renames تانية مطلوبة.
//
// المنطق منسوخ حرفياً بلا أي تعديل: بوابة كلمة مرور الإعدادات (فحص/تعيين/
// تغيير)، سجل النشاط عند الدخول، منتقي المظهر (فاتح/غامق/تلقائي)، وكل محتوى
// الأقسام الثمانية بما فيها كل toggle/dialog/فتح شاشة.
//
// ⚠️ الاستثناء الوحيد (Task 14 parity): `Navigator.push` لإدارة المستخدمين
// (كان `UsersManagementScreen` بالسطر ٥٨٢ في الأصل) يفتح هنا مباشرة
// `UsersManagementPicposScreen` — لأن هذا الملف PicPos-only (لا يوجد فيه
// `Brand.isPicPos` ternary؛ الفرع بيتحدد أصلاً باختيار الشاشة كلها في
// app_main_screen.dart). الأصل (`settings_screen.dart`) فاضل يفتح
// `UsersManagementScreen` زي ما هو، من غير أي لمسة.
//
// REUSE (import لا نسخ): كل الـ providers (`settingsRepositoryProvider`/
// `themeModeProvider`/`featureFlagsProvider`/`businessProfileProvider`/
// `industryModeProvider`/`systemCurrencyProvider`/`authProvider`/
// `activityLoggerProvider`/`activationStatusProvider`/`databaseProvider`/
// `allBranchesProvider`/`branchRepositoryProvider`/`syncRepositoryProvider`/
// `adminPasswordServiceProvider`/`currentUserPermissionsProvider`/
// `sessionTimeoutProvider`/`touchModeProvider`)، ودجتس الأقسام المستوردة من
// presentation/widgets/settings/* (`BackupRestoreWidget`/`CompanyInfoWidget`/
// `HardwareSettingsWidget`/`PosSettingsWidget`/`UserManagementWidget`/
// `FingerprintSettingsWidget`/
// `KdsSettingsWidget`/`ModifierManagementWidget`/`DatabaseSettingsWidget`)،
// والحوارات/دوال الفتح (`showCompanyInfoDialog`/`showHardwareSettingsDialog`/
// `showPosSettingsDialog`/
// `showDatabaseSettingsDialog`/`showActivationDialog`/
// `showBranchScopeAdminDialog`/`showMirrorParityAuditDialog`/
// `showChequeReceiptDriftAdminDialog`/`ServerPermsToggleDialog`) كما هي —
// وشاشات الوجهة تُفتح بقشرة PicPos ذات الترويسة الموحّدة (`HEADS` في ملفّ
// التصميم): `PrintersPicposScreen`/`PosTerminalsPicposScreen`/
// `WorkHolidaysPicposScreen`/`DeliveryManagementPicposScreen`/
// `DeveloperToolsPicposScreen`، و`InvoiceDesignerScreen(picposChrome: true)`،
// و`AccountMappingPicPosScreen` (فوركُ الحسابات القائمُ أصلاً).
//
// ⚠️ **وكلُّها قشرةٌ لا نسخة**: المنطقُ باقٍ في ملفّات `screens/` المشتركة
// وتستورده القشرتان معاً (`*Body`)، فشاشةُ UralCash لم يتبدّل فيها بايت ولا
// نسخةَ ثانيةً تُصان. يحرس ذلك `settings_unified_header_test`.
//
// FULL PARITY مع الأصل — كل قسم موجود بلا حذف: إعدادات النظام والمظهر (معلومات
// الشركة، نوع النشاط، العملة، المظهر، الشاشة الرئيسية الافتراضية، قاعدة
// البيانات، أدوات صيانة المسؤول، تدقيق مزامنة المرآة/ازدواج شيكات القبض حسب
// الوضع، إعدادات الربط بين الفروع والسيرفر، نمط الإدخال اللمسي، المزامنة
// الإجبارية)، الأجهزة والطباعة (إعدادات الأجهزة، إدارة الطابعات، نقاط البيع،
// قوالب الفواتير، باركود الميزان، البصمة عند تفعيل HR)، إعدادات البيع السريع،
// المستخدمين والأمان (إدارة المستخدمين → PicPos، إدارة صلاحيات الأدوار، فحص
// الصلاحيات على السيرفر، مهلة انتهاء الجلسة، كلمة مرور الإعدادات) أو الإشعار
// في وضع العميل، حماية الأقسام بكلمات مرور بديلة (عند تفعيل المطبخ/HR)،
// الإعدادات المالية والمحاسبية (ربط الحسابات، طريقة التكلفة، سياسة نقص
// الخامات عامة/لكل فرع، إظهار ETA/JOFOTARA)، إدارة البيانات (نسخ احتياطي
// واستعادة)، التكاملات والخدمات (التوصيل، شاشة العميل CFD، شاشة المطبخ،
// إدارة الإضافات)، وأخيراً عن البرنامج والترخيص + نسخ اللوج التشخيصي + أدوات
// المطوّر (تظهر لمن لديه صلاحية system_admin أو في وضع Debug).
//
// طبقة العرض الخارجية فقط تغيّرت: `PicPosScreenScaffold` (هيدر «الإعدادات» /
// «تهيئة النظام والأجهزة والصلاحيات») بدل Directionality+Scaffold+Padding+
// Row هيدر يدوي، و`PicPosContentCard` بدل شكل `Card(elevation:2, shape:
// RoundedRectangleBorder(...))` داخل `_buildSettingsCard` — التوابع الأخرى
// (`_buildAboutCard`/`_buildLicenseCard`/`_buildDeveloperToolsCard`/
// `_buildCopyLogCard`) تفضل تستخدم `Card` بألوانها الخاصة كما فى الأصل، لأنها
// مش من ضمن "أقسام الإعدادات" المطلوب إعادة تأطيرها.
//
// راجع lib/presentation/screens/settings_screen.dart (الأصل) و٦ ملفات الـ
// part تحت lib/presentation/screens/settings/.
// ---------------------------------------------------------------------------

import '../../picpos_shell/picpos_surface.dart';
// يخدم أجزاءَ هذه المكتبة كلَّها (`part of`): حوارات المدير والعميل
// والإعدادات العامّة تستعمل `PicPosDialog` من هنا.
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_option_picker.dart';
import '../guarded_sections.dart';
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
import '../../../core/config/brand.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/design_system/typography.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/config/business_profile_provider.dart';
import '../../../data/providers/providers.dart';
import '../../pos_picpos/widgets/picpos_payment_methods.dart';
import '../../widgets/permission_guard.dart';
// دفعة ١٠ — تايلات الإعدادات المحروسة، مشتركة بين البراندين.
import '../../widgets/settings/settings_permission_tiles.dart';
import '../widgets/table_bill_qr_launcher_row.dart';
import '../../widgets/settings/backup_restore_widget.dart';
import '../../widgets/settings/company_info_widget.dart';
import '../../users_picpos/screens/users_management_picpos_screen.dart';
import '../../widgets/settings/hardware_settings_widget.dart';
import '../../widgets/settings/pos_settings_widget.dart';
import '../widgets/permissions_matrix_picpos.dart';
import '../../screens/settings/widgets/server_perms_toggle_dialog.dart';
import '../../accounting_picpos/account_mapping_picpos_screen.dart';
import 'work_holidays_picpos_screen.dart';

import 'guest_services_settings_picpos.dart';
import 'printers_picpos_screen.dart';
import 'pos_terminals_picpos_screen.dart';
import 'delivery_management_picpos_screen.dart';
import '../../screens/invoice_designer_screen.dart';
import '../../widgets/settings/activation_dialog.dart';
import '../../../services/license_service.dart';
import '../../../core/config/app_config.dart';
import 'developer_tools_picpos_screen.dart';
import '../../../core/navigation/screen_id.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/network_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/websocket_sync_client.dart';
import '../../widgets/settings/fingerprint_settings_widget.dart';
import '../../../services/cfd_service.dart';
import '../../../services/cfd/cfd_transport.dart';
import '../../widgets/settings/kds_settings_widget.dart';
import '../../widgets/settings/modifier_management_widget.dart';
import '../../../services/cfd/cfd_serial_transport.dart';
import '../../../services/cfd/cfd_usb_transport.dart';
import '../../../services/cfd/cfd_hdmi_transport.dart';
import '../../../services/costing_method_service.dart';
// Spec 135 NOTE 1 — the session-timeout selector below writes the single
// canonical `session_timeout_minutes` key; invalidate its provider on save so
// the live InactivityDetector picks the change up without an app restart.
import '../../../services/session_timeout_service.dart' show sessionTimeoutProvider;
import '../../../services/stock_shortage_policy_service.dart';
import '../../widgets/settings/branch_scope_admin_dialog.dart';
import '../../widgets/settings/party_balance_repair_dialog.dart';
import '../../widgets/settings/cheque_receipt_drift_admin_dialog.dart';
import '../../widgets/settings/mirror_parity_audit_dialog.dart';
import '../../widgets/settings/database_settings_widget.dart';
import '../../widgets/settings/lan_pairing_dialog.dart';
import '../../../services/api/lan_pairing_service.dart';
import '../../touch_keyboard/providers/touch_mode_provider.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../widgets/settings_blocks.dart';
import '../widgets/settings_count.dart';
import '../widgets/settings_nav_rail.dart';
import '../widgets/settings_section_pane.dart';
import '../../template_library_picpos/screens/template_library_picpos_screen.dart';
import '../../template_resolution_picpos/screens/template_resolution_picpos_screen.dart';
import '../../screens/exchange_rate_screen.dart';
import 'quick_sale_policy_screen_picpos.dart';

// Part files — copied verbatim from lib/presentation/screens/settings/*
// (only `part of` retargeted to this shell; see the copy-trap note above).
part 'general_settings_widgets_picpos.dart';
part 'scale_barcode_settings_picpos.dart';
part 'admin_home_settings_picpos.dart';
part 'cfd_settings_card_picpos.dart';
part 'network_mode_settings_picpos.dart';
part 'touch_input_settings_picpos.dart';
part 'payment_methods_settings_picpos.dart';

/// شاشة الإعدادات بهوية PicPos. تُختار في `app_main_screen.dart` بالعلامة
/// (`Brand.isPicPos`). تعيد استخدام منطق `settings_screen.dart` بالكامل —
/// فقط طبقة العرض الخارجية تبدّلت لـ picpos_shell، ودخول إدارة المستخدمين
/// يفتح مباشرة `UsersManagementPicposScreen` (Task 14).
class SettingsPicposScreen extends ConsumerStatefulWidget {
  const SettingsPicposScreen({super.key});

  @override
  ConsumerState<SettingsPicposScreen> createState() => _SettingsPicposScreenState();
}

class _SettingsPicposScreenState extends ConsumerState<SettingsPicposScreen> {
  bool _isUnlocked = false;
  bool _isCheckingPassword = true;

  /// القسم المعروض في اللوحة اليمنى. الشاشة كانت `ListView` واحد طوله ٨ كروت
  /// بلا تبويب ولا بحث — الوصول لأي إعداد كان تمرير أعمى.
  String _selectedSectionId = 'system';

  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _checkPasswordGate();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        child: PicPosDialog(
          icon: PhosphorIconsBold.lockKey,
          title: 'كلمة مرور الإعدادات',
          subtitle: 'الشاشةُ محميّةٌ بكلمةِ مرور',
          width: 460,
          // ⚠️ الإلغاءُ يخرج من **الشاشة** لا من الحوار وحدَه: الحوارُ
          //    `barrierDismissible: false` وهو بوّابةُ الدخول، فإغلاقُه
          //    وحدَه كان يترك الشاشةَ مفتوحةً بلا قفلٍ ولا محتوى.
          onCancel: () {
            Navigator.pop(ctx);
            Navigator.pop(context);
          },
          body: [
            PicPosDialogField(
              label: 'أدخل كلمة المرور',
              child: TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (val) {
                  if (val == correctPassword) {
                    Navigator.pop(ctx);
                    setState(() => _isUnlocked = true);
                  }
                },
              ),
            ),
          ],
          primaryAction: PicPosDialogAction(
            label: 'دخول',
            icon: PhosphorIconsBold.signIn,
            onPressed: () {
              if (controller.text == correctPassword) {
                Navigator.pop(ctx);
                setState(() => _isUnlocked = true);
              } else {
                AppToast.show(ctx, 'كلمة المرور غير صحيحة',
                    type: ToastType.error);
              }
            },
          ),
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
        child: PicPosDialog(
          icon: PhosphorIconsBold.key,
          title: 'تغيير كلمة مرور الإعدادات',
          subtitle: 'اتركها فارغةً لإلغاء الحماية بالكامل',
          width: 460,
          onCancel: () => Navigator.pop(ctx),
          body: [
            PicPosDialogField(
              label: 'كلمة المرور الجديدة',
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
          primaryAction: PicPosDialogAction(
            label: 'حفظ',
            icon: PhosphorIconsBold.floppyDisk,
            onPressed: () => Navigator.pop(ctx, controller.text),
          ),
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

  // ignore: unused_element
  Future<void> _showSectionPasswordDialog(String key, String title) async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final currentPw = await settingsRepo.getSetting(key);
    if (!mounted) return;

    final controller = TextEditingController(text: currentPw ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: PicPosDialog(
          icon: PhosphorIconsBold.key,
          title: 'كلمة مرور $title',
          subtitle: 'اتركها فارغةً لإلغاء الحماية عن هذا القسم',
          width: 460,
          onCancel: () => Navigator.pop(ctx),
          body: [
            PicPosDialogField(
              label: 'كلمة المرور الجديدة لـ $title',
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
          primaryAction: PicPosDialogAction(
            label: 'حفظ',
            icon: PhosphorIconsBold.floppyDisk,
            onPressed: () => Navigator.pop(ctx, controller.text),
          ),
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

    final sections = <_SettingsSection>[
      _SettingsSection(
        id: 'system',
        title: 'النظام والمظهر',
        icon: PhosphorIconsBold.slidersHorizontal,
        group: 'التشغيل',
        desc: 'الشركة · العملة · المظهر',
        keywords: 'شركة صناعة عملة مظهر ثيم داكن نهاري شاشة رئيسية قاعدة '
            'بيانات صيانة مزامنة مرآة شيكات فروع سيرفر شبكة لمس كيبورد',
        children: () => [
          // ═══ 1. النظام والمظهر — على بلوكات التصميم ═══
          SettingsBlockGrid(
            blocks: [
              SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'مظهر البرنامج',
                  subtitle: 'يُطبَّق على كل الشاشات وشاشة العميل',
                  child: SettingsChoiceBlock<ThemeMode>(
                    selected: themeMode,
                    onSelect: (m) =>
                        ref.read(themeModeProvider.notifier).setMode(m),
                    options: const [
                      SettingsChoiceOption(
                        value: ThemeMode.light,
                        label: 'فاتح',
                        sub: 'الأنسب للإضاءة القوية والطباعة من الشاشة',
                      ),
                      SettingsChoiceOption(
                        value: ThemeMode.dark,
                        label: 'غامق',
                        sub: 'مريح للكاشير في الورديات الليلية',
                      ),
                      SettingsChoiceOption(
                        value: ThemeMode.system,
                        label: 'تلقائي',
                        sub: 'يتبع مظهر ويندوز',
                      ),
                    ],
                  ),
                ),
              ),
              SettingsBlockSpan(
                span: 7,
                child: SettingsBlock(
                  title: 'هوية الشركة والتشغيل',
                  subtitle: 'تظهر في الفواتير والتقارير المطبوعة',
                  tint: AppColors.info,
                  child: SettingsRowsBody(
                    children: [
                      // ⚠️ الحُرّاسُ باقون: `settingsCompany` هنا و
                      //    `systemDatabase` في مربّع قاعدة البيانات أسفل.
                      PermissionGuard(
                        permission: PermissionCodes.settingsCompany,
                        fallback: const SizedBox.shrink(),
                        child: SettingsValueRow(
                          first: true,
                          icon: PhosphorIconsBold.buildings,
                          title: 'معلومات الشركة',
                          sub: 'الاسم، السجل التجاري، الرقم الضريبي، الشعار',
                          onTap: () => showCompanyInfoDialog(context, picpos: true),
                        ),
                      ),
                      // الودجتاتُ القائمةُ نفسُها — بُدِّل رسمُها إلى صفِّ
                      // بلوك، ومنتقياتُها ومعالجةُ القفل فيها كما هي.
                      const _IndustryModeToggle(),
                      const _CurrencySelector(),
                      const _DefaultHomeScreenSelector(),
                    ],
                  ),
                ),
              ),
              const SettingsBlockSpan(
                span: 5,
                child: SettingsBlock(
                  title: 'سلوك التشغيل',
                  subtitle: 'خيارات تسري على هذا الجهاز فقط',
                  tint: AppColors.warning,
                  child: SettingsRowsBody(
                    children: [
                      // ⚠️ مفتاحٌ واحدٌ لا ثلاثة: التصميمُ يعرض معه
                      //    «المزامنة الإجبارية» و«بدء تلقائي مع ويندوز»،
                      //    والأولى في التطبيق **زرُّ إجراءٍ** لا مفتاحاً
                      //    (‏لوحةُ المزامنة أسفل)، والثانيةُ لا وجودَ لها
                      //    أصلاً. ومفتاحٌ لا يبدّل شيئاً أسوأُ من غيابه.
                      _TouchModeSwitchRow(),
                    ],
                  ),
                ),
              ),
              const SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'الشاشات المتقدمة',
                  subtitle: 'قاعدة البيانات، الربط، وأدوات الصيانة',
                  tint: AppColors.textMuted,
                  child: _AdvancedTiles(),
                ),
              ),
              // ⚠️ لوحةُ الدفع اليدويِّ بلوكٌ لا مربّع: لها حالةُ تشغيلٍ
              //    وزرٌّ يخمُد أثناء العمل، ولا تُختصر في سطرِ حالة.
              const SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'مزامنة يدويّة',
                  subtitle: 'دفعُ التغييرات إلى السيرفر عند الحاجة',
                  tint: AppColors.info,
                  child: _ForceSyncPanel(),
                ),
              ),
            ],
          ),
        ],
      ),
      _SettingsSection(
        id: 'devices',
        title: 'الأجهزة والطباعة',
        icon: PhosphorIconsBold.printer,
        group: 'التشغيل',
        desc: 'طابعات · نقاط بيع · قوالب',
        keywords: 'طابعة باركود ماسح ميزان حراري قوالب فواتير نقاط بيع '
            'بصمة تصميم',
        children: () => [
          // ═══ 2. الأجهزة والطباعة — شبكةُ بلوكاتِ التصميم ═══
          SettingsBlockGrid(
            blocks: [
              const SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'إدارة الأجهزة',
                  subtitle: 'كل جهاز طرفي مربوط بالنظام',
                  child: _DeviceTiles(),
                ),
              ),
              const SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'باركود الميزان',
                  subtitle: 'بادئةُ الملصق وتوزيعُ خاناته',
                  tint: AppColors.textMuted,
                  child: _ScaleBarcodeSettings(),
                ),
              ),
              if (features.hrEnabled)
                const SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'جهاز البصمة',
                    subtitle: 'ربطُ الحضور والانصراف',
                    tint: AppColors.info,
                    child: FingerprintSettingsWidget(),
                  ),
                ),
            ],
          ),
        ],
      ),
      _SettingsSection(
        id: 'pos',
        title: 'البيع السريع',
        icon: PhosphorIconsBold.shoppingCart,
        group: 'التشغيل',
        desc: 'الكاشير · الدفع · الخصم',
        keywords: 'تراكم أصناف ميزان وزن سلة أزرار تصنيفات شبكة منتجات '
            'إيصال طباعة تلقائية بيع بالسالب خصم ضريبة درج مصروفات وردية '
            'مخزن افتراضي بادئة ترقيم طرق الدفع نقدي بطاقة تحويل آجل متعدد',
        children: () => [
          // ═══ 3. البيع السريع — شبكةُ بلوكاتِ التصميم ═══
          //
          // ⚠️ الحارسُ `buildPosSettingsTileGuarded` يبقى كما هو: هو نفسُه
          //    ودجتٌ يحمل فحصَ الصلاحية، فيُوضَع جسماً للبلوك لا يُفكَّك.
          SettingsBlockGrid(
            blocks: [
              SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'إعدادات البيع السريع',
                  subtitle: 'سلوكُ شاشة الكاشير وحدودُ الخصم',
                  child: buildPosSettingsTileGuarded(
                    onOpen: () => showPosSettingsDialog(context, picpos: true),
                  ),
                ),
              ),
              // §٤ — شاشةُ السياسة بجوار ديالوج العرض.
              //
              // ⚠️ **بلوكان لا واحد عن قصد.** البلوكُ أعلاه يفتح ديالوجاً
              // يضبط **ما يُعرَض** (مقاساتٌ وأعمدةٌ وأيقونات)، وهذا يفتح
              // شاشةً تضبط **ما يحدث** (‏البيعُ بالسالب · سقفُ الخصم · من
              // يصادق على الإغلاق). ودمجُهما كان يخلط قرارَ مظهرٍ بقرارٍ
              // محاسبيّ في نافذةٍ واحدة.
              SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'سياسة البيع السريع',
                  subtitle: 'ما يحدث بين المسح والإغلاق — بخمس خطوات',
                  tint: AppColors.info,
                  child: buildQuickSalePolicyTileGuarded(
                    onOpen: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const QuickSalePolicyScreenPicpos(),
                      ),
                    ),
                  ),
                ),
              ),
              const SettingsBlockSpan(
                span: 7,
                child: SettingsBlock(
                  title: 'طرق الدفع الظاهرة',
                  subtitle: 'ما يراه الكاشير في لوحة الدفع',
                  tint: AppColors.success,
                  child: _PaymentMethodsSettingsCard(),
                ),
              ),
              const SettingsBlockSpan(
                span: 5,
                child: SettingsBlock(
                  title: 'إغلاق الوردية',
                  subtitle: 'الإغلاقُ السريع بلا جرد',
                  tint: AppColors.warning,
                  child: _QuickCloseSettingTile(),
                ),
              ),
            ],
          ),
        ],
      ),
      _SettingsSection(
        id: 'users',
        title: 'المستخدمون والأمان',
        icon: PhosphorIconsBold.shieldCheck,
        group: 'الأمان',
        desc: 'الحسابات · الأدوار · الصلاحيات',
        keywords: 'مستخدمين صلاحيات أدوار كلمة مرور جلسة مهلة حماية أقسام',
        children: () => [
          // ═══ 4. المستخدمون والأمان — شبكةُ بلوكاتِ التصميم ═══
          //
          // إدارةُ المستخدمين والأدوار سلطتُها على السيرفر: العميلُ لا
          // يُنشئ مستخدماً (تصادمُ معرّفات) ولا يحرّر صلاحيةً (تُسحَب من
          // السيرفر كلَّ مزامنة) — فيرى بلوكاً إعلاميّاً مكانَها.
          SettingsBlockGrid(
            blocks: [
              if (!NetworkService.instance.isClient) ...[
                const SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'المستخدمون والأدوار',
                    subtitle: 'الحساباتُ وصلاحياتُ كل دور',
                    child: _UserTiles(),
                  ),
                ),
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'فحص الصلاحيات على السيرفر',
                    subtitle: 'تفعيلُ التحقّق من الصلاحية عند السيرفر',
                    tint: AppColors.warning,
                    // ⚠️ الحارسُ باقٍ بحرفه: `rolesManage` — من يغيّر صلاحياتِ
                    //    الأدوار هو وحدَه من يفتح فرضَها على السيرفر.
                    child: PermissionGuard(
                      permission: PermissionCodes.rolesManage,
                      allowManagerOverride: true,
                      actionName: 'فحص الصلاحيات على السيرفر',
                      child: _ServerPermsToggleTile(),
                    ),
                  ),
                ),
              ] else
                const SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'إدارة المستخدمين والصلاحيات',
                    subtitle: 'تتم إدارتها من السيرفر — وضع العميل للعرض فقط',
                    tint: AppColors.info,
                    child: SizedBox.shrink(),
                  ),
                ),
              const SettingsBlockSpan(
                span: 7,
                child: SettingsBlock(
                  title: 'انتهاء الجلسة',
                  subtitle: 'إغلاقٌ تلقائيٌّ بعد خمولٍ',
                  tint: AppColors.info,
                  child: _SessionTimeoutSetting(),
                ),
              ),
              SettingsBlockSpan(
                span: 5,
                child: SettingsBlock(
                  title: 'كلمة مرور الإعدادات',
                  subtitle: 'حمايةُ هذه الشاشة',
                  tint: AppColors.error,
                  child: SettingsRowsBody(
                    children: [
                      SettingsValueRow(
                        first: true,
                        icon: PhosphorIconsBold.lockKey,
                        title: 'تغيير كلمة المرور',
                        sub: 'اتركها فارغةً لإلغاء الحماية',
                        tint: AppColors.error,
                        onTap: _showChangePasswordDialog,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
      // ═══ ٤-ب. حماية الأقسام — قسمٌ مستقلٌّ على التصميم الجديد ═══
      //
      // كان بلوكاً داخلَ «المستخدمون والأمان»، وفصلَه التصميمُ لأنّ حراستَه
      // **مستقلّةٌ عن الصلاحيات**: كلمةٌ يعرفها من يجلس على الجهاز، لا دورٌ
      // يُسنَد لحساب. فخلطُهما في قسمٍ واحدٍ يوحي بأنّ أحدَهما يُغني عن الآخر.
      //
      // ⚠️ **ولا تسييجَ بـ`kitchenEnabled || hrEnabled` بعد اليوم.** كان
      //    القسمُ كلُّه مخفيّاً في بروفايل السوبرماركت، فيختفي معه قفلُ
      //    **المخازن والمشتريات والتقارير** — وهي أقسامٌ موجودةٌ في كلّ
      //    بروفايل. التسييجُ صار على البند: `hr_access_password` وحدَه يتبع
      //    `features.hrEnabled`.
      _SettingsSection(
        id: 'guards',
        title: 'حماية الأقسام',
        icon: PhosphorIconsBold.lockKey,
        group: 'الأمان',
        desc: 'أقفال الشاشات',
        keywords: 'قفل كلمة مرور حماية اقسام مخازن مشتريات تقارير حسابات '
            'موظفين بديلة',
        children: () => [
          SettingsBlockGrid(
            blocks: [
              SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'الأقسام المحميّة',
                  subtitle: 'تُطلَب كلمةٌ عند الدخول لكلِّ قسمٍ مفعَّل',
                  tint: AppColors.error,
                  child: _GuardedSectionRows(features: features),
                ),
              ),
            ],
          ),
        ],
      ),
      _SettingsSection(
        id: 'finance',
        title: 'المالية والمحاسبة',
        icon: PhosphorIconsBold.bank,
        group: 'المال والبيانات',
        desc: 'ربط الحسابات · التكلفة · الفوترة',
        keywords: 'حسابات ربط تلقائي تكلفة تسعير نقص مخزون فوترة إلكترونية '
            'ضريبة قيمة مضافة',
        children: () => [
          // ═══ 5. الإعدادات المالية ═══
          PermissionGuard(
            permission: PermissionCodes.settingsBackup,
            allowManagerOverride: true,
            actionName: 'إعدادات المحاسبة',
            child: SettingsBlockGrid(
              blocks: [
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'ربط الحسابات',
                    subtitle: 'تحديد الحسابات الدفترية للعمليات',
                    child: SettingsRowsBody(
                      children: [
                        SettingsValueRow(
                          first: true,
                          icon: PhosphorIconsBold.bookOpen,
                          title: 'ربط الحسابات التلقائي',
                          sub: 'حسابُ كلِّ عمليةٍ في الدفتر',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const AccountMappingPicPosScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'التكلفة والمخزون',
                    subtitle: 'طريقةُ التسعير وسياسةُ نقص الخامات',
                    tint: AppColors.info,
                    // ⚠️ الثلاثةُ ودجتاتٌ لها حالتُها ومزوّداتُها، فتُوضَع
                    //    كما هي جسماً للبلوك ولا تُفكَّك إلى صفوفِ قيمة.
                    //    وتبديلُ «البيع بالسالب» ليس هنا: نُقل إلى إعدادات
                    //    البيع السريع بطلبِ المشغّلين، والمفتاحُ نفسُه
                    //    (`enable_negative_sales`) لم يتبدّل.
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CostingMethodToggle(),
                        _StockShortagePolicyToggle(),
                        _StockShortagePolicyPerBranchTile(),
                      ],
                    ),
                  ),
                ),
                // الفوترةُ الإلكترونيّةُ مخفيّةٌ في بروفايل السوبرماركت.
                if (profile != BusinessProfile.supermarket)
                  const SettingsBlockSpan(
                    span: 12,
                    child: SettingsBlock(
                      title: 'الفوترة الإلكترونية',
                      subtitle: 'حقولُ مصلحة الضرائب في المستندات',
                      tint: AppColors.warning,
                      child: _EInvoiceVisibilityToggles(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      _SettingsSection(
        id: 'hr',
        title: 'شؤون الموظفين',
        icon: PhosphorIconsBold.calendarCheck,
        // ⚠️ قسمٌ **لا يذكره التصميم** — فلا يقرّره. باقٍ كما هو، ومسيَّجٌ
        //    أصلاً بـ`features.hrEnabled` (‏قرارُ المالك: lite تؤجّل الأجور).
        group: 'المال والبيانات',
        desc: 'الورديات · الإجازات · الرواتب',
        keywords: 'عطلات عطل إجازات أسبوعية أعياد أيام العمل رواتب '
            'أجر الساعة إضافي وقت',
        children: () => [
          // ═══ 5.1 شؤون الموظفين ═══
          // `features.hrEnabled` **شرطٌ لا تجميل**: بروفايل `lite` — وهو
          // افتراضيُّ PicPos (`Brand.defaultProfileCode`) — يضبطه `false`،
          // فالوحدةُ غيرُ موجودةٍ في هذا المنتج. المدخلُ هنا لأن الشاشتين
          // فوركان من نفس الكود ويعملان لبروفايلاتٍ أخرى.
          if (features.hrEnabled)
            SettingsBlockGrid(
              blocks: [
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'العطلات وأيام العمل',
                    subtitle: 'الأيامُ التي لا يقع عليها غياب',
                    tint: AppColors.secondary,
                    // الحارسُ ودجتٌ يحمل فحصَه، فيُوضَع جسماً للبلوك.
                    child: buildWorkHolidaysTileGuarded(
                      onOpen: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WorkHolidaysPicposScreen()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      _SettingsSection(
        id: 'data',
        title: 'إدارة البيانات',
        icon: PhosphorIconsBold.database,
        group: 'المال والبيانات',
        desc: 'النسخ الاحتياطي · الاستعادة',
        keywords: 'نسخ احتياطي استعادة باك اب backup restore تصدير',
        children: () => [
          // ═══ 6. إدارة البيانات ═══
          // ⚠️ الحارسُ يلفُّ الشبكةَ كلَّها لا بلوكاً فيها: النسخُ
          //    والاستعادةُ عمليّةٌ واحدة، وإظهارُ نصفِها بلا صلاحيةٍ يوهم
          //    بأن الشاشةَ ناقصةٌ لا محميّة.
          const PermissionGuard(
            permission: PermissionCodes.settingsBackup,
            allowManagerOverride: true,
            actionName: 'إدارة البيانات',
            child: SettingsBlockGrid(
              blocks: [
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'النسخ الاحتياطي والاستعادة',
                    subtitle: 'حفظُ نسخةٍ من القاعدة واستعادتُها',
                    tint: AppColors.success,
                    child: BackupRestoreWidget(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      _SettingsSection(
        id: 'integrations',
        title: 'التكاملات والخدمات',
        icon: PhosphorIconsBold.plugsConnected,
        group: 'الامتدادات',
        desc: 'شاشة العميل · المطبخ · التوصيل · رمز الطاولة · واتساب',
        keywords: 'توصيل مناديب شاشة عميل CFD مطبخ KDS إضافات معدلات '
            'رمز طاولة QR حساب ضيف دومين واتساب whatsapp رمز دولة رسائل عملاء',
        children: () => [
          // ═══ 7. التكاملات والخدمات ═══
          SettingsBlockGrid(
            blocks: [
              // ⚠️ **هنا لا في حوار الطباعة وحدَه.** كانت رايتا رمز الطاولة
              // تُضبطان داخلَ حوارٍ يُفتَح لطباعة الأكواد — فمن بحث عنها في
              // الإعدادات لم يجدها، وهو بلاغُ المالك بنصّه. ورايةُ طلبِ
              // الضيف لم يكن لها **كاتبٌ في `lib/` كلِّها**، فالنصفُ الذي
              // طُلب صراحةً كان مطفأً إلى الأبد.
              if (features.tablesEnabled)
                const SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'رمز حساب الطاولة',
                    subtitle: 'الضيفُ يرى حسابَه ويطلب من هاتفه',
                    tint: AppColors.info,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TableBillSettingsCard(),
                        // قسمُ ٧ — طباعةُ الأكواد نُقلت من رأس شاشة
                        // الطاولات: ورقةٌ تُطبَع مرّةً عند التجهيز، وموضعُها
                        // في رأسِ شاشةٍ يفتحها النادلُ كلَّ دقيقةٍ يزاحم
                        // أفعالَه اليوميّة بفعلٍ لا يفعلُه.
                        TableBillQrLauncherRow(),
                      ],
                    ),
                  ),
                ),
              const SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'رسائل العملاء — واتساب',
                  subtitle: 'الفاتورةُ وكشفُ الحساب والمطالبة',
                  tint: AppColors.success,
                  child: WhatsAppSettingsCard(),
                ),
              ),
              if (features.deliveryEnabled)
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'التوصيل',
                    subtitle: 'شركاتُ التوصيل والمناديب',
                    tint: AppColors.success,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _DeliveryToggle(),
                        // ⚠️ الحارسُ باقٍ بحرفه — `deliveryManage` مع
                        //    تجاوزِ المدير، كما كان قبل النقل.
                        PermissionGuard(
                          permission: PermissionCodes.deliveryManage,
                          allowManagerOverride: true,
                          actionName: 'إدارة التوصيل',
                          child: SettingsRowsBody(
                            children: [
                              SettingsValueRow(
                                first: true,
                                icon: PhosphorIconsBold.moped,
                                title: 'إدارة التوصيل',
                                sub: 'شركات التوصيل والمناديب',
                                tint: AppColors.success,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const DeliveryManagementPicposScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: 'شاشة العميل',
                  subtitle: 'العرضُ الخارجيُّ ووصلتُه',
                  tint: AppColors.info,
                  child: _CFDSettingsCard(),
                ),
              ),
              if (features.kitchenEnabled) ...[
                const SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'شاشة المطبخ',
                    subtitle: 'توزيعُ أوامر الشغل على الأقسام',
                    tint: AppColors.warning,
                    child: PermissionGuard(
                      permission: PermissionCodes.kdsSettings,
                      allowManagerOverride: true,
                      actionName: 'إعدادات شاشة المطبخ',
                      child: KdsSettingsWidget(),
                    ),
                  ),
                ),
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: 'الإضافات والمعدلات',
                    subtitle: 'مجموعات الإضافات والخيارات للأصناف',
                    tint: AppColors.warning,
                    // ⚠️ `onGranted` باقٍ: هو المسارُ الذي يفتح الشاشةَ بعد
                    //    موافقةِ المسؤول، وحذفُه يجعل الموافقةَ بلا أثر.
                    child: PermissionGuard(
                      permission: PermissionCodes.modifiersManage,
                      allowManagerOverride: true,
                      actionName: 'إدارة الإضافات والمعدلات',
                      onGranted: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ModifierManagementWidget(),
                        ),
                      ),
                      child: SettingsRowsBody(
                        children: [
                          SettingsValueRow(
                            first: true,
                            icon: PhosphorIconsBold.forkKnife,
                            title: 'إدارة الإضافات والمعدلات',
                            sub: 'مجموعات الإضافات والخيارات للأصناف',
                            tint: AppColors.warning,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ModifierManagementWidget(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      _SettingsSection(
        id: 'about',
        title: 'عن البرنامج',
        icon: PhosphorIconsBold.info,
        group: 'الامتدادات',
        desc: 'الإصدار · الترخيص · التشخيص',
        keywords: 'إصدار نسخة ترخيص تفعيل لوج تشخيصي مطور دعم',
        children: () => [
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
        ],
      ),
    ];

    final query = _searchQuery.trim();
    // A selected section can vanish between builds — a feature flag flips, or
    // client mode hides one — so fall back rather than render an empty pane.
    final selected = sections.firstWhere(
      (s) => s.id == _selectedSectionId,
      orElse: () => sections.first,
    );

    return PicPosScreenScaffold(
      title: 'الإعدادات',
      subtitle: 'تهيئة النظام والأجهزة والصلاحيات',
      icon: PhosphorIconsBold.gear,
      // ⚠️ البحثُ انتقل من ترويسة الصفحة إلى **رأس العمود** كما في التصميم.
      //    وترويسةُ `PicPosPageHeader` صفٌّ بلا تقييد، فإخلاؤها يبعد عنها
      //    خطرَ الفيضان الذي وقع مرّتين في تبويبات الحسابات.
      bodyPadding: EdgeInsets.zero,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsNavRail(
            items: [
              for (final s in sections)
                SettingsNavRailItem(
                  id: s.id,
                  title: s.title,
                  icon: s.icon,
                  group: s.group,
                  desc: s.desc,
                  // ⚠️ مقيسٌ من الشجرة لا مكتوبٌ بيد: `s.children()` هي عينُ
                  //    ما يُبنى في اللوح، فالرقمُ يتبع الواقعَ دوماً. انظر
                  //    `settings_count.dart` لسببِ رفضِ رقم التصميم.
                  //
                  // ⚠️ **وصفرٌ ⇒ لا شارة، لا شارةُ «٠».** قسمُ «عن البرنامج»
                  //    يبني بطاقاتٍ خاصّةً (‏الإصدار · الترخيص · نسخُ السجلّ)
                  //    لا يعرفها العدّاد، فيعود بصفر. و«٠ إعداد» بجانب قسمٍ
                  //    فيه أربعُ بطاقاتٍ كذبٌ من نوعٍ آخر — فالصمتُ أصدق.
                  count: countVisibleSettingsOrNull(s.children()),
                ),
            ],
            selectedId: selected.id,
            onSelect: (id) => setState(() {
              _selectedSectionId = id;
              _searchController.clear();
              _searchQuery = '';
            }),
            search: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'بحث في الإعدادات…',
                prefixIcon:
                    const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                isDense: true,
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(PhosphorIconsBold.x, size: 14),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? _buildSectionPane(selected)
                : _buildSearchResults(sections, query),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionPane(_SettingsSection section) {
    return SettingsSectionPane(
      sectionId: section.id,
      children: [
        _SectionHeader(section: section),
        const SizedBox(height: 20),
        for (final child in section.children()) ...[
          child,
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  /// Search over section titles + their keyword lists.
  ///
  /// It resolves to a SECTION, not to an individual control, because most
  /// settings here live inside nested dialogs and expansion tiles that have
  /// no addressable identity. Landing the user on the right section is the
  /// honest thing this data can support — and it already fixes the case that
  /// motivated it, where «منع تراكم الأصناف» sits behind a tile inside a
  /// dialog inside a card and was effectively unfindable.
  Widget _buildSearchResults(List<_SettingsSection> sections, String query) {
    final q = query.toLowerCase();
    final matches = sections
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.keywords.toLowerCase().contains(q))
        .toList();

    if (matches.isEmpty) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.magnifyingGlass,
        title: 'لا يوجد إعداد بهذا الاسم',
        hint: 'جرّب كلمة أقصر — «طابعة» بدل «إعدادات الطابعة الحرارية».',
        action: TextButton(
          onPressed: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
          child: const Text('مسح البحث'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 24),
      children: [
        Text(
          '${matches.length} قسم مطابق',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        for (final s in matches)
          PicPosContentCard(
            child: ListTile(
              leading: Icon(s.icon, color: AppColors.primary),
              title: Text(s.title),
              subtitle: Text(
                s.keywords,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(PhosphorIconsBold.caretLeft, size: 16),
              onTap: () => setState(() {
                _selectedSectionId = s.id;
                _searchController.clear();
                _searchQuery = '';
              }),
            ),
          ),
      ],
    );
  }

  // ignore: unused_element
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

  /// ⚠️ كان `SimpleDialog` — بلاغُ المالك بالصورة 2026-08-25. والأوصافُ
  /// أدناه من التصميم (‏`SECTIONS.system` → بلوكُ «مظهر البرنامج»).
  // ignore: unused_element
  Future<void> _showThemeSelector(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    const labels = {
      ThemeMode.system: 'تلقائي',
      ThemeMode.light: 'فاتح',
      ThemeMode.dark: 'غامق',
    };

    final picked = await showPicPosOptionPicker<ThemeMode>(
      context: context,
      icon: PhosphorIconsBold.palette,
      title: 'مظهر البرنامج',
      subtitle: 'يُطبَّق على كل الشاشات وشاشة العميل',
      selected: current,
      options: const [
        PicPosOption(
          value: ThemeMode.light,
          label: 'فاتح',
          sub: 'الأنسب للإضاءة القويّة والطباعة من الشاشة',
          icon: PhosphorIconsBold.sun,
        ),
        PicPosOption(
          value: ThemeMode.dark,
          label: 'غامق',
          sub: 'مريحٌ للكاشير في الورديات الليليّة',
          icon: PhosphorIconsBold.moon,
        ),
        PicPosOption(
          value: ThemeMode.system,
          label: 'تلقائي',
          sub: 'يتبع مظهرَ ويندوز',
          icon: PhosphorIconsBold.monitor,
        ),
      ],
    );

    if (picked == null || picked == current) return;
    ref.read(themeModeProvider.notifier).setMode(picked);

    // #Forensic Log: Theme change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      logger.logSettingsChange(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        'مظهر التطبيق',
        newValue: labels[picked] ?? '',
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
  }

  Widget _buildAboutCard() {
    // كان `Card(elevation: 2)` — آخر أربع كروت فضلوا بالشكل المرفوع بتاع
    // UralCash جنب كروت PicPos المسطّحة، فالشاشة كانت بتبان نصّين تصميم.
    return PicPosContentCard(
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
                child: Image.asset(Brand.logoAsset, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              Brand.name,
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
            // ⚠️ **كان نصّاً ثابتاً `'الإصدار 1.0.0'`** — بلاغُ المالك
            // 2026-08-22: «رقمُ الإصدار لا يظهر تحديثُه في إعدادات النظام».
            //
            // والسببُ ليس أن القيمةَ غيرُ متاحة: `AppVersionService.initialize()`
            // تُنادى في `main.dart` **قبل** `runApp` وتملأ
            // [AppConstants.appVersion] من `pubspec` عبر `package_info_plus`
            // (‏وهي اليومَ 3.1.3+248). الكارتُ وحدَه كان يطبع حرفاً محفوراً
            // فلا يتحرّك مهما تغيّرت النسخة — فيقرأ المشغّلُ نسخةً غيرَ التي
            // يشغّلها، وهو أسوأُ من ألّا يُعرض رقمٌ أصلاً.
            //
            // ورقمُ البناء يُعرض معه: نسختان بنفس الرقم وبناءَين مختلفَين
            // تقعان فعلاً بين إصدارَين تجريبيَّين، والرقمُ وحدَه لا يفرّقهما.
            Text(
              'الإصدار ${AppConstants.appVersion} '
              '(${AppConstants.appBuildNumber})',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
            // Vendor block — values from `Brand`. A brand that declares no
            // vendor info renders nothing here; printing another product's
            // support contacts is worse than printing none.
            if (Brand.hasVendorInfo) ...[
              const Divider(height: 24),
              const Text(
                'تطوير: ${Brand.vendorName}',
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
                    Brand.vendorEmail,
                  ),
                  _buildContactChip(
                      PhosphorIconsBold.globe, Brand.vendorWebsite),
                  _buildContactChip(
                    PhosphorIconsBold.whatsappLogo,
                    Brand.vendorPhone,
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
                    onPressed: () =>
                        launchUrl(Uri.parse(Brand.vendorFacebookUrl)),
                    tooltip: 'Facebook',
                  ),
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsBold.instagramLogo,
                      color: Color(0xFFE4405F),
                    ),
                    onPressed: () =>
                        launchUrl(Uri.parse(Brand.vendorInstagramUrl)),
                    tooltip: 'Instagram',
                  ),
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsBold.whatsappLogo,
                      color: Color(0xFF25D366),
                    ),
                    onPressed: () =>
                        launchUrl(Uri.parse(Brand.vendorWhatsappUrl)),
                    tooltip: 'WhatsApp',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '© 2026 ${Brand.vendorName}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseCard(BuildContext context, WidgetRef ref) {
    final activationAsync = ref.watch(activationStatusProvider);

    return activationAsync.when(
      // مسطّح زي باقي كروت PicPos، بس بحد ملوّن بيفرّق حالة التفعيل — الحد
      // هنا معلومة مش زينة، فاتساب على `Container` بدل `PicPosContentCard`
      // اللي حدّه ثابت.
      data: (isActivated) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.picposCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActivated
                ? AppColors.success.withValues(alpha: 0.5)
                : AppColors.warning.withValues(alpha: 0.5),
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
              : buildLicenseActivateButtonGuarded(
                  onOpen: () => showActivationDialog(context, picpos: true),
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
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
            builder: (_) => const DeveloperToolsPicposScreen(),
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
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
              '${Brand.dbPrefix}_login_log.txt',
              '${Brand.dbPrefix}_startup_log.txt',
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
        color: context.picposField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.picposHairline),
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

// Spec 078 — بلاطةُ جاهزيّة صلاحيّات السيرفر (‏توأمُ نظيرتها في
// `settings_screen.dart`).
//
// ⚠️ كانت مفتاحَ تشغيلٍ يقرأ `server_per_user_perms_enabled` ويعرض
// «غير مُفعّل» على كلِّ تنصيبةٍ لأنّ المفتاحَ لا يُزرع أبداً. والفحصُ صار
// يُنفَّذ بلا شرط، فالبلاطةُ الآن **تصف الحقيقة** وتفتح تقريرَ الاستطلاع.
class _ServerPermsToggleTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ServerPermsToggleTile> createState() =>
      _ServerPermsToggleTileState();
}

class _ServerPermsToggleTileState
    extends ConsumerState<_ServerPermsToggleTile> {
  Future<void> _openDialog() async {
    final db = ref.read(databaseProvider);
    await ServerPermsToggleDialog.show(context: context, db: db);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(
        PhosphorIconsBold.shieldCheck,
        color: AppColors.success,
      ),
      title: const Text('فحص الصلاحيات على السيرفر'),
      subtitle: const Text(
        'مُفعّل دائماً — اضغط لفحص الأدوار التي ينقصها منح',
        style: TextStyle(fontSize: 12),
      ),
      trailing: const Icon(PhosphorIconsBold.caretLeft, size: 18),
      onTap: _openDialog,
    );
  }
}

/// قسم واحد في شاشة الإعدادات.
///
/// [children] دالة مش قائمة جاهزة عن قصد: محتوى الأقسام بيقرا feature flags
/// و`NetworkService.isClient` و`PermissionGuard`، فلازم يتبني وقت العرض مش
/// وقت تعريف القائمة.
class _SettingsSection {
  final String id;
  final String title;
  final IconData icon;

  /// مجموعةُ القسم في عمود التصميم — أربعُ مجموعاتٍ تجمع الأقسام التسعة.
  ///
  /// ⚠️ **ولا عدّادَ إعداداتٍ هنا.** التصميمُ يعرض رقماً لكلّ قسم (‏١٤ · ١٢ ·
  /// ١١ …) ومجموعَه ٩٤ في نصّ البحث، وهو رقمٌ **لا يمكن قياسُه من الشجرة**:
  /// معظمُ الإعدادات داخلَ حواراتٍ وبطاقاتٍ متداخلةٍ بلا هويّةٍ مُعنوَنة.
  /// ورقمٌ مكتوبٌ بيدٍ يبطُل عند أوّل إضافة — فالعدُّ مُسقَطٌ عمداً بدل عرضِ
  /// عددٍ يكذب.
  final String group;

  /// سطرُ الوصف تحت العنوان في العمود — يشرح ما يضمّه القسم.
  final String desc;

  /// كلمات البحث. بتظهر كمان كسطر وصف تحت اسم القسم في نتايج البحث، فهي
  /// مش مخفية — المستخدم بيشوف ليه القسم ده طلع.
  final String keywords;

  final List<Widget> Function() children;

  const _SettingsSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.group,
    required this.desc,
    required this.keywords,
    required this.children,
  });
}

/// ترتيبُ مجموعات العمود كما في التصميم.
  // ignore: unused_element
const _kSettingsGroupOrder = <String>[
  'التشغيل',
  'الأمان',
  'المال والبيانات',
  'الامتدادات',
];

/// ترويسةُ القسم — أيقونةٌ ٥٦px وعنوانٌ كبيرٌ وسطرُ وصف، كما في التصميم.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final _SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(section.icon, size: 27, color: AppColors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: text.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                section.desc,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// صفوفُ بلوكات قسم «النظام والمظهر»
// ═══════════════════════════════════════════════════════════════════════════

class _TouchModeSwitchRow extends ConsumerWidget {
  const _TouchModeSwitchRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(touchModeProvider);
    return SettingsSwitchRow(
      first: true,
      icon: PhosphorIconsBold.handTap,
      title: 'نمط الإدخال اللمسي',
      sub: 'لوحة مفاتيح على الشاشة في حقول الأرقام',
      value: on,
      onChanged: (v) => ref.read(touchModeProvider.notifier).set(v),
    );
  }
}

/// مربّعاتُ «الشاشات المتقدمة» — بحالةٍ مقيسةٍ لا مفترَضة.
/// صفوفُ «الأقسام المحميّة» — تُبنى من [kPicPosGuardedSections] لا من قائمةٍ
/// مكتوبةٍ هنا.
///
/// ⚠️ **ولماذا سجلٌّ في ملفٍّ آخر:** لأنّ المفتاحَ المعروضَ وعدٌ، والوفاءُ به
/// عند `SecurityScreenGate` في `app_main_screen.dart`. والسجلُّ هو الرابطُ
/// الذي يقيسه `guarded_sections_have_real_gates_test` — فلا يُعرَض قفلٌ لقسمٍ
/// بلا بوّابة.
///
/// و**الحالةُ تُقرأ لا تُفترَض**: مفتاحٌ مضبوطٌ ⇒ «مفعَّل»، وفارغٌ ⇒ «مفتوح».
class _GuardedSectionRows extends ConsumerWidget {
  const _GuardedSectionRows({required this.features});

  final FeaturePolicy features;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_guardedSectionStateProvider);

    // `hr_access_password` وحدَه يتبع `features.hrEnabled`: الوحدةُ نفسُها
    // غيرُ موجودةٍ في `lite`، فقفلُها بلا معنى. وبقيّةُ الأقسام في كلّ
    // بروفايل.
    final sections = kPicPosGuardedSections.where((s) {
      if (s.settingKey == 'hr_access_password') return features.hrEnabled;
      return true;
    }).toList();

    return SettingsRowsBody(
      children: [
        for (var i = 0; i < sections.length; i++)
          SettingsValueRow(
            first: i == 0,
            icon: sections[i].icon,
            title: sections[i].title,
            sub: sections[i].sub,
            // ⚠️ القيمةُ من الحالة الحيّة لا من افتراض. وقبل وصولِها
            //    تُترك فارغةً بدل أن تُعرض «مفتوح» تفاؤلاً — فقفلٌ يُقرأ
            //    مفتوحاً وهو مقفولٌ يُقلق، والعكسُ يُطمئن كذباً.
            value: state.when(
              data: (m) => (m[sections[i].settingKey] ?? false)
                  ? 'مفعَّل'
                  : 'مفتوح',
              loading: () => null,
              error: (_, _) => null,
            ),
            tint: state.value?[sections[i].settingKey] == true
                ? AppColors.error
                : AppColors.textMuted,
            onTap: () => _showSectionPasswordDialogFor(
              context,
              ref,
              sections[i].settingKey,
              sections[i].title,
            ),
          ),
      ],
    );
  }
}

/// حالةُ الأقفال — `true` يعني أنّ للقسم كلمةً مضبوطة.
final _guardedSectionStateProvider =
    FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final repo = ref.watch(settingsRepositoryProvider);
  final out = <String, bool>{};
  for (final s in kPicPosGuardedSections) {
    final pw = await repo.getSetting(s.settingKey);
    out[s.settingKey] = pw != null && pw.isNotEmpty;
  }
  return out;
});

/// نسخةٌ حرّةٌ من حوار كلمة القسم تصلح خارجَ حالةِ الشاشة.
///
/// ⚠️ وتُبطِل [_guardedSectionStateProvider] بعد الحفظ: بلا ذلك يبقى الصفُّ
/// يقول «مفتوح» بعد ضبطِ كلمةٍ للتوّ — والحالةُ الكاذبةُ هنا تُطمئن بغير حقّ.
Future<void> _showSectionPasswordDialogFor(
  BuildContext context,
  WidgetRef ref,
  String key,
  String title,
) async {
  final repo = ref.read(settingsRepositoryProvider);
  final current = await repo.getSetting(key);
  if (!context.mounted) return;

  final controller = TextEditingController(text: current ?? '');
  final result = await showDialog<String?>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: PicPosDialog(
        icon: PhosphorIconsBold.lockKey,
        title: 'كلمة مرور $title',
        subtitle: 'اتركها فارغةً لفتح القسم بلا كلمة',
        width: 460,
        onCancel: () => Navigator.pop(ctx),
        body: [
          PicPosDialogField(
            label: 'كلمة المرور',
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ],
        primaryAction: PicPosDialogAction(
          label: 'حفظ',
          icon: PhosphorIconsBold.floppyDisk,
          onPressed: () => Navigator.pop(ctx, controller.text),
        ),
      ),
    ),
  );
  controller.dispose();

  if (result == null) return;
  await repo.saveSetting(key, result);
  ref.invalidate(_guardedSectionStateProvider);
  if (context.mounted) {
    AppToast.show(
      context,
      result.isEmpty ? 'فُتح القسم — بلا كلمة' : 'حُفظت كلمة $title',
      type: ToastType.success,
    );
  }
}

/// مربّعاتُ «المستخدمون والأدوار».
///
/// الحارسُ على الضغطة لا على العرض — لنفس سببِ [_DeviceTiles]، وبنفس
/// أكواد الصلاحيات: `usersManage` للحسابات و`rolesManage` للأدوار.
class _UserTiles extends ConsumerWidget {
  const _UserTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> guarded(
      String permission,
      String actionName,
      VoidCallback open,
    ) async {
      final ok = await ensurePermission(
        ref,
        context,
        permission,
        actionName: actionName,
      );
      if (ok && context.mounted) open();
    }

    return SettingsTilesBlock(
      columns: 2,
      tiles: [
        SettingsTile(
          icon: PhosphorIconsBold.usersThree,
          title: 'إدارة المستخدمين',
          sub: 'إضافة مستخدمين وتغيير كلمات المرور',
          meta: 'الحساباتُ والدخول',
          tint: AppColors.primary,
          onTap: () => guarded(
            PermissionCodes.usersManage,
            'إدارة المستخدمين',
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const UsersManagementPicposScreen(),
              ),
            ),
          ),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.table,
          title: 'مصفوفة الأدوار والصلاحيات',
          sub: 'قارن الأدوار جنباً إلى جنب وبدّل الصلاحية في مكانها',
          meta: 'مصفوفةٌ لا دورٌ واحد',
          tint: AppColors.warning,
          onTap: () => guarded(
            PermissionCodes.rolesManage,
            'إدارة صلاحيات الأدوار',
            () => showPermissionsMatrixPicpos(context),
          ),
        ),
      ],
    );
  }
}

/// مربّعاتُ «إدارة الأجهزة» — بلوكُ `tiles` في قسم الأجهزة من التصميم.
///
/// ⚠️ **الحارسُ انتقل من العرض إلى الضغطة، وهذا تشديدٌ لا تخفيف.**
/// كانت الصفوفُ ملفوفةً بـ`PermissionGuard(allowManagerOverride: true)`،
/// وهو يحرس **الودجت**: يُخفي الصفَّ أو يطلب موافقةَ مسؤول. و`SettingsTile`
/// وصفُ بياناتٍ لا ودجت، فلا يُلفّ.
///
/// فبدل إسقاطِ الحراسة أو إخفاءِ المربّع، تُحرَس الضغطةُ بـ`ensurePermission`
/// — وهي **القِمع** الذي تمرُّ منه كلُّ المداخل، وتستهلك موافقةَ المسؤول من
/// `ManagerApprovalCache` فلا يُسأل مرّتين. أي أنّ `allowManagerOverride`
/// محفوظٌ بحرفه، والحمايةُ صارت فعليّةً لا بصريّة.
class _DeviceTiles extends ConsumerWidget {
  const _DeviceTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> guarded(
      String permission,
      String actionName,
      VoidCallback open,
    ) async {
      final ok = await ensurePermission(
        ref,
        context,
        permission,
        actionName: actionName,
      );
      if (ok && context.mounted) open();
    }

    return SettingsTilesBlock(
      tiles: [
        SettingsTile(
          icon: PhosphorIconsBold.printer,
          title: 'إعدادات الأجهزة',
          sub: 'الماسح والطابعة الحرارية والميزان',
          // ⚠️ وصفٌ لا عدّاد: التصميمُ يعرض «٤ طابعات معرّفة» وهو رقمُ
          //    عرضٍ في ملفّ التصميم لا شيءٌ تحمله القاعدةُ اليوم.
          meta: 'ماسح · طابعة · ميزان',
          tint: AppColors.info,
          onTap: () => guarded(
            PermissionCodes.settingsPrinter,
            'إعدادات الأجهزة',
            () => showHardwareSettingsDialog(context, picpos: true),
          ),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.printer,
          title: 'إدارة الطابعات',
          sub: 'طابعات أوامر الشغل للأقسام',
          meta: 'توزيعُ الطباعة على الأقسام',
          tint: AppColors.secondary,
          onTap: () => guarded(
            PermissionCodes.settingsPrinter,
            'إدارة الطابعات',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrintersPicposScreen()),
            ),
          ),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.cashRegister,
          title: 'نقاط البيع',
          sub: 'إدارة الماكينات وسياسة نقص الخامات',
          meta: 'سياسةٌ لكل نقطة',
          tint: AppColors.primary,
          onTap: () => guarded(
            PermissionCodes.settingsPrinter,
            'نقاط البيع',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const PosTerminalsPicposScreen()),
            ),
          ),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.books,
          title: 'مكتبة النماذج',
          sub: 'استعراضُ قوالب الطباعة وربطُها بالمستندات',
          meta: 'المطبوعات',
          tint: AppColors.info,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const TemplateLibraryPicposScreen(),
            ),
          ),
        ),
        // بلوغٌ ثانٍ لشاشةِ الحسم بجوار المكتبة: من يربط قالباً هنا يسأل
        // فوراً «هل وصل؟» — والقائمةُ الجانبيّةُ بعيدةٌ عن لحظة السؤال.
        SettingsTile(
          icon: PhosphorIconsBold.gitFork,
          title: 'حسم القوالب',
          sub: 'أيُّ مستندٍ يخرج بأيِّ قالبٍ — وسلسلةُ السقوط',
          meta: 'تشخيصُ الطباعة',
          tint: AppColors.info,
          onTap: () => guarded(
            PermissionCodes.settingsPrinter,
            'حسم القوالب',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TemplateResolutionPicposScreen(),
              ),
            ),
          ),
        ),
        // ⚠️ **السطحُ القديمُ باقٍ عن قصدٍ لا عن إهمال**: هو الوحيدُ الذي
        //    يحرّر **ملصقاتِ الباركود** (‏`templateCategory == 'barcode'`)،
        //    والمكتبةُ تُرشِّحها والمحرّرُ الجديدُ لا يخدمها. فإخفاؤه كان
        //    سيُلغي الطريقَ الوحيدَ لتعديل الملصقات.
        //
        //    وتحريرُ قوالب الفواتير مدخلُه **المكتبة**: المحرّرُ الجديدُ يفتح
        //    على قالبٍ بعينه (`templateId`)، فلا معنى لفتحه بلا اختيار.
        SettingsTile(
          icon: PhosphorIconsBold.barcode,
          title: 'مصمّم ملصقات الباركود',
          sub: 'السطحُ القديم — ملصقاتُ الباركود وقوالبُها',
          meta: 'الملصقات',
          tint: AppColors.info,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const InvoiceDesignerScreen(picposChrome: true),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdvancedTiles extends ConsumerWidget {
  const _AdvancedTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = NetworkService.instance.mode;
    final isServer = NetworkService.instance.isServer;

    return SettingsTilesBlock(
      tiles: [
        SettingsTile(
          icon: PhosphorIconsBold.database,
          title: 'قاعدة البيانات',
          sub: 'نوع القاعدة ومسارها',
          meta: 'إعدادات الاتصال',
          tint: AppColors.success,
          dot: AppColors.success,
          onTap: () => showDatabaseSettingsDialog(context),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.wifiHigh,
          title: 'الربط بين الفروع والسيرفر',
          sub: 'وضع الشبكة والمزامنة',
          // ⚠️ الحالةُ من `NetworkService` الحيّ لا نصٌّ ثابت.
          meta: switch (mode) {
            NetworkMode.server => 'سيرفر رئيسي',
            NetworkMode.client => 'عميل مرتبط',
            NetworkMode.mirror => 'مرآة',
            _ => 'مستقل',
          },
          tint: AppColors.primary,
          dot: isServer ? AppColors.success : AppColors.primary,
          // ‏`_NetworkModeSettings` لوحةٌ كانت داخلَ `ExpansionTile`، فتُفتَح
          // هنا في حوارٍ بدل أن تُبنى نسخةٌ ثانيةٌ من منطقها.
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: const SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: _NetworkModeSettings(),
                ),
              ),
            ),
          ),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.shield,
          title: 'أدوات صيانة المسؤول',
          sub: 'حصر الفروع وتشخيص القيود',
          meta: 'أدوات تشخيصية',
          tint: AppColors.warning,
          onTap: () => showBranchScopeAdminDialog(context),
         ),
         SettingsTile(
           icon: PhosphorIconsBold.currencyCircleDollar,
           title: 'أسعار الصرف وإعادة التقييم',
           sub: 'إدارة العملات وقيد فروق الصرف الدوري',
           meta: 'معاينة ثم تنفيذ محمي',
           tint: AppColors.info,
           permission: PermissionCodes.accountingJournal,
           onTap: () => Navigator.push(
             context,
             MaterialPageRoute(builder: (_) => const ExchangeRateScreen()),
           ),
         ),
         SettingsTile(
           icon: PhosphorIconsBold.scales,
           title: 'تدقيق أرصدة الأطراف',
           sub: 'مقارنة أرصدة العملاء والموردين بالأستاذ',
           meta: 'إعادة احتساب محمية بالصلاحية',
           tint: AppColors.warning,
           permission: PermissionCodes.accountingJournal,
           onTap: () {
             final userId = ref.read(authProvider).effectiveUser?.id;
             if (userId == null) return;
             showPartyBalanceRepairDialog(
               context,
               repository: ref.read(partiesRepositoryProvider),
               userId: userId,
             );
           },
         ),
         // ⚠️ التدقيقان مشروطان بالوضع لا معطَّلَين فيه: تدقيقُ المرآة
        //    يقارن بالسيرفر فلا معنى له في وضعٍ مستقلّ، وتدقيقُ الشيكات
        //    يقرأ سجلَّ السيرفر. ومربّعٌ حاضرٌ لا يعمل يُسأل عنه.
        if (mode == NetworkMode.mirror)
          SettingsTile(
            icon: PhosphorIconsBold.arrowsCounterClockwise,
            title: 'تدقيق مزامنة المرآة',
            sub: 'مقارنة البيانات الأساسية بالسيرفر',
            meta: 'قراءةٌ ثمّ إعادةُ مزامنة',
            tint: AppColors.primary,
            onTap: () => showMirrorParityAuditDialog(context),
          ),
        if (isServer)
          SettingsTile(
            icon: PhosphorIconsBold.magnifyingGlass,
            title: 'تدقيق ازدواج شيكات القبض',
            sub: 'أرصدةٌ تأثّرت بازدواج سندات القبض',
            meta: 'قراءةٌ فقط — الإصلاحُ مؤجَّل',
            tint: AppColors.warning,
            onTap: () => showChequeReceiptDriftAdminDialog(context),
          ),
      ],
    );
  }
}
