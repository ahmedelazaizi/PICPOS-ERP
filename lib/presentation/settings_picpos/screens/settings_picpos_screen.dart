import 'package:picpos_erp/core/i18n/tr.dart';
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
import 'dart:ui' as ui;
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory;
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/config/brand.dart';
import '../../widgets/user_language_selector.dart';
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
import '../widgets/web_access_settings_panel.dart';
import 'linked_devices_section.dart';
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
import 'device_reprovision_tile.dart';
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
part 'settings_picpos_sections_core.dart';
part 'settings_picpos_sections_security.dart';
part 'settings_picpos_sections_services.dart';
part 'settings_picpos_about.dart';
part 'settings_picpos_support.dart';
part 'settings_picpos_tiles.dart';
part 'settings_picpos_navigation.dart';

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
        textDirection: Directionality.of(context),
        child: PicPosDialog(
          icon: PhosphorIconsBold.lockKey,
          title: tr('كلمة مرور الإعدادات'),
          subtitle: tr('الشاشةُ محميّةٌ بكلمةِ مرور'),
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
              label: tr('أدخل كلمة المرور'),
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
            label: tr('دخول'),
            icon: PhosphorIconsBold.signIn,
            onPressed: () {
              if (controller.text == correctPassword) {
                Navigator.pop(ctx);
                setState(() => _isUnlocked = true);
              } else {
                AppToast.show(ctx, tr('كلمة المرور غير صحيحة'),
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
        textDirection: Directionality.of(context),
        child: PicPosDialog(
          icon: PhosphorIconsBold.key,
          title: tr('تغيير كلمة مرور الإعدادات'),
          subtitle: tr('اتركها فارغةً لإلغاء الحماية بالكامل'),
          width: 460,
          onCancel: () => Navigator.pop(ctx),
          body: [
            PicPosDialogField(
              label: tr('كلمة المرور الجديدة'),
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
            label: tr('حفظ'),
            icon: PhosphorIconsBold.floppyDisk,
            onPressed: () => Navigator.pop(ctx, controller.text),
          ),
        ),
      ),
    );
    if (result != null) {
      await settingsRepo.saveSetting('settings_access_password', result);
      if (mounted) {
        AppToast.show(context, result.isEmpty ? tr('تم إلغاء حماية كلمة المرور') : tr('تم تغيير كلمة المرور بنجاح'), type: ToastType.success);
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
        textDirection: Directionality.of(context),
        child: PicPosDialog(
          icon: PhosphorIconsBold.key,
          title: tr('كلمة مرور {title}', {'title': title}),
          subtitle: tr('اتركها فارغةً لإلغاء الحماية عن هذا القسم'),
          width: 460,
          onCancel: () => Navigator.pop(ctx),
          body: [
            PicPosDialogField(
              label: tr('كلمة المرور الجديدة لـ {title}', {'title': title}),
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
            label: tr('حفظ'),
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
          result.isEmpty ? tr('تم إلغاء الحماية عن {title}', {'title': title}) : tr('تم حفظ كلمة مرور {title} بنجاح', {'title': title}),
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
               Text(tr('الإعدادات محمية بكلمة مرور')),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final settingsRepo = ref.read(settingsRepositoryProvider);
                  final pw = await settingsRepo.getSetting('settings_access_password');
                  if (pw != null && pw.isNotEmpty && mounted) _showPasswordDialog(pw);
                },
                child:  Text(tr('إدخال كلمة المرور')),
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
            .logNavigation(user.id, user.displayName, tr('الإعدادات (Settings)'));
      }
    });

    final sections = <_SettingsSection>[
      _buildSystemSection(context, themeMode, features, profile),
      _buildDevicesSection(context, themeMode, features, profile),
      _buildPosSection(context, themeMode, features, profile),
      _buildUsersSection(context, themeMode, features, profile),
      _buildLinkedDevicesSection(context, themeMode, features, profile),
      _buildGuardsSection(context, themeMode, features, profile),
      _buildFinanceSection(context, themeMode, features, profile),
      _buildHrSection(context, themeMode, features, profile),
      _buildDataSection(context, themeMode, features, profile),
      _buildIntegrationsSection(context, themeMode, features, profile),
      _buildAboutSection(context, themeMode, features, profile),
    ];
    final query = _searchQuery.trim();
    // A selected section can vanish between builds — a feature flag flips, or
    // client mode hides one — so fall back rather than render an empty pane.
    final selected = sections.firstWhere(
      (s) => s.id == _selectedSectionId,
      orElse: () => sections.first,
    );

    return PicPosScreenScaffold(
      title: tr('الإعدادات'),
      subtitle: tr('تهيئة النظام والأجهزة والصلاحيات'),
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
                hintText: tr('بحث في الإعدادات…'),
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

}
