import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'setup_wizard/setup_step_meta.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
// `app_config.dart` يعيد تصدير `business_profile.dart` — فمفيش استيراد
// مباشر ليه هنا (الـ analyzer بيعتبره زيادة).
import '../../core/config/app_config.dart';
import '../../core/config/business_profile_meta.dart';
import '../../domain/models/setup_step_order.dart';
import '../../core/config/business_profile_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/database/connection.dart'
    show openPostgresConnection, testPostgresConnection;
import '../../data/database/pg_config.dart';
import '../../data/providers/providers.dart';
import '../../services/network_service.dart';
import '../../services/mirror_pairing_service.dart';
import '../../services/mirror_state.dart';
import '../../services/delta_pull_service.dart';
import '../../services/server_proxy.dart';
import '../../services/sync_service.dart';
import '../../services/sync/client_first_sync_service.dart';
import '../../services/deployment/deployment_mode_committer.dart';
import '../../services/deployment/commit_result.dart';
import '../../app_main_screen.dart';
import '../touch_keyboard/providers/touch_mode_provider.dart';
import '../../core/config/brand.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, KeyDownEvent;
import '../../core/constants/app_constants.dart' show CurrencyInfo;
import '../../core/i18n/locale_provider.dart';
import '../../services/license_service.dart';
import '../picpos_shell/picpos_surface.dart';
import 'setup_wizard/setup_finish_runner.dart';
import 'setup_wizard/setup_persistence_riverpod.dart';

part 'setup_wizard/step_company_info.dart';
part 'setup_wizard/step_branch.dart';
part 'setup_wizard/step_products.dart';
part 'setup_wizard/step_users.dart';
part 'setup_wizard/step_settings.dart';
part 'setup_wizard/step_provisioning.dart';
part 'setup_wizard/step_touch_mode.dart';
// ── بندُ المالك ٦ — الهيكلُ الجديد (‏واجهةٌ جديدةٌ في ملفّاتٍ جديدة) ──
part 'setup_wizard/step_welcome.dart';
part 'setup_wizard/step_currency_tax.dart';
part 'setup_wizard/step_cash_banks.dart';
part 'setup_wizard/step_chart_preview.dart';
part 'setup_wizard/step_review.dart';
part 'setup_wizard/setup_wizard_flow.dart';

/// لونُ النصّ الخافت **من الثيم** لا مثبَّتاً.
///
/// 🔴 `AppColors.textMuted` رماديٌّ مضبوطٌ للوضع الفاتح وحدَه، ويذوب في
/// الداكن. وقد وقع ذلك فعلاً في ترويسة المعالج — بلّغ عنه المالكُ أنّ
/// العنوانَ الفرعيَّ «شبهُ مخفيّ».
Color? _mutedInk(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.85);

/// ملاحظةٌ ملوّنةٌ داخلَ جسم الخطوة — نفسُ شكل `SetupNote` في اللوحة الجانبيّة.
Widget _inlineNote(
  BuildContext context, {
  required IconData icon,
  required Color tone,
  required String title,
  required String body,
}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.07),
      border: Border.all(color: tone.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: tone),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: TextStyle(fontSize: 12, color: _mutedInk(context)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// First-Run Setup Wizard — shown once after first login
/// Guides the user through essential setup steps.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({
    super.key,
    @visibleForTesting this.initialStep,
    @visibleForTesting this.initialMode,
  });

  /// للاختبار: يبدأ المعالجُ على خطوةٍ بعينها (‏`SetupStepIds`) لتُقاس وحدَها.
  final int? initialStep;

  /// للاختبار: نمطُ تشغيلٍ ابتدائيٌّ غيرُ المستقلّ.
  final NetworkMode? initialMode;

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  // بندُ المالك ٦: المسارُ يبدأ بالترحيب واللغة — `SetupStepIds.welcome`.
  int _currentStep = SetupStepIds.welcome;

  @override
  void initState() {
    super.initState();
    if (widget.initialMode != null) _networkMode = widget.initialMode!;
    if (widget.initialStep != null) _currentStep = widget.initialStep!;
  }

  // Step 1: Company Info
  final _companyNameController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyAddressController = TextEditingController();
  String _businessType = 'retail';
  String _currency = 'EGP';

  // ── بندُ المالك ٦: هويّةُ الشركة الكاملة ──
  final _companyNameEnController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _commercialRegisterController = TextEditingController();
  Uint8List? _logo;

  /// اختارها المستخدمُ بيده ⇒ لا يبدّلها افتراضيُّ ملفّ النشاط بعد ذلك.
  bool _businessTypeTouched = false;

  // ── العملة والضريبة ──
  bool _pricesIncludeTax = true;
  bool _pricesIncludeTaxTouched = false;
  bool _taxRateTouched = false;
  SetupEInvoiceCountry _eInvoiceCountry = SetupEInvoiceCountry.egypt;
  bool _eInvoiceTouched = false;

  // ── الفرع ──
  final _branchCodeController = TextEditingController();
  final _branchAddressController = TextEditingController();

  // ── الصناديق والبنوك — تُملأ من الصفوف المزروعة عند أوّل زيارة ──
  final _cashBoxNameController = TextEditingController();
  final _bankSafeNameController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAccountController = TextEditingController();
  final _cliqSafeNameController = TextEditingController();
  Future<void>? _safesLoad;

  /// القيمُ المزروعةُ كما قُرئت — «تخطٍّ» يعيد الحقولَ إليها.
  final Map<TextEditingController, String> _safeOriginals = {};

  // ── معاينةُ دليل الحسابات — قراءةٌ واحدةٌ مذكَّرة ──
  Future<List<Account>>? _accountsLoad;

  // ── كلمة مرور المدير ──
  final _adminPasswordController = TextEditingController();
  final _adminPasswordConfirmController = TextEditingController();
  bool _adminPasswordVisible = false;

  // ── المراجعة والتشغيل ──
  final SetupFinishRunner _runner = SetupFinishRunner();
  SetupRunStage? _runStage;
  SetupRunResult? _runResult;

  /// دخل الخطوةَ من رابط «تعديل» في المراجعة ⇒ زرٌّ يعود إليها مباشرة.
  bool _returnToReview = false;

  // Phase-B: runtime-selected business profile (new). Backed by the
  // `BusinessProfileCatalog` so the UI and the persisted `business_profile`
  // setting stay in sync.
  //
  // Seeded from `AppConfig.profile` — the brand/flavour boot default — NOT
  // hard-coded. This step persists its value on finish (`_finishSetup`
  // writes `business_profile`), so a hard-coded seed here silently
  // overwrote the build-time default: a PicPos install would boot `lite`,
  // then land on `unified` the moment setup completed, with every screen
  // visible. Seeding from the actual boot profile makes "just click Next"
  // preserve the product's intended scope.
  BusinessProfile _selectedProfile = AppConfig.profile;

  // Phase-B: developer password (separate from admin password). Required
  // before finishing setup; can only be changed later from the hidden
  // developer-tools screen, and reset via CLI `--reset-dev-password`.
  final _developerPasswordController = TextEditingController();
  final _developerPasswordConfirmController = TextEditingController();
  bool _developerPasswordVisible = false;

  // Step 2: Branch & Warehouse
  final _branchNameController = TextEditingController(text: tr('الفرع الرئيسي'));
  final _warehouseNameController = TextEditingController(text: tr('المخزن الرئيسي'));

  // Step 3: First Products
  final List<Map<String, String>> _sampleProducts = [];
  final _productNameController = TextEditingController();
  final _productPriceController = TextEditingController();
  final _productCostController = TextEditingController();

  // Step 3: Users
  final List<Map<String, dynamic>> _wizardUsers = [];
  final _userDisplayNameController = TextEditingController();
  final _userUsernameController = TextEditingController();
  final _userPasswordController = TextEditingController();
  int? _userSelectedRoleId;

  // Step 4: Payment & Tax
  bool _enableTax = true;
  double _taxRate = 14.0;

  // Feature 031 — Step 9: Touch Mode (per-device on-screen keyboard).
  bool _touchMode = false;

  // Network mode (added for client setup). Typed as the canonical
  // `NetworkMode` enum (Feature 006 / MM.D cleanup) — previously a
  // free-form String that was easy to mistype.
  NetworkMode _networkMode = NetworkMode.standalone;
  final _serverAddressController = TextEditingController();
  final _serverPortController = TextEditingController(text: '8080');
  // Mirror-mode admin verification (Feature 006 / MM.C). Captured during
  // the pairing step so MirrorState.adminUserId can be stamped after a
  // successful POST /api/auth/verify-admin.
  final _mirrorAdminUsernameController = TextEditingController();
  final _mirrorAdminPasswordController = TextEditingController();
  bool _isConnecting = false;
  String? _connectionResult;
  int? _selectedBranchId;
  List<Branche> _syncedBranches = [];

  // Step 5: PostgreSQL server config (server mode only)
  final _pgHostController = TextEditingController(text: 'localhost');
  final _pgPortController = TextEditingController(text: '5432');
  final _pgDatabaseController = TextEditingController(text: Brand.pgIdentifier);
  final _pgUserController = TextEditingController(text: 'postgres');
  final _pgPasswordController = TextEditingController();
  bool _pgTestInProgress = false;
  bool _pgConnectionOk = false;
  String? _pgTestMessage;

  // Step 6: Provisioning (server mode only)
  bool _provisioningInProgress = false;
  bool _provisioningDone = false;
  String? _provisioningError;
  final List<_ProvisionStep> _provisionSteps = [
    _ProvisionStep(tr('اختبار الاتصال بالسيرفر')),
    _ProvisionStep(tr('إنشاء جداول قاعدة البيانات')),
    _ProvisionStep(tr('زرع البيانات الأساسية (أدوار، فرع، مخزن، خزائن…)')),
    _ProvisionStep(tr('زرع شجرة الحسابات')),
    _ProvisionStep(tr('إنشاء السنة المالية الحالية')),
    _ProvisionStep(tr('التحقق من اكتمال البيانات')),
  ];

  bool _isSaving = false;

  /// Steps available based on network mode.
  /// Each element is the internal step index used by `_buildCurrentStep`.
  ///   0: company info
  ///   1: branch / network-mode selection
  ///   2: products (standalone only)
  ///   3: users (not server — server seeds admin + expects post-setup user creation)
  ///   4: tax / settings
  ///   5: PostgreSQL config (server only)
  ///   6: provisioning progress (server only)
  ///   7: developer password (Phase B — all modes, before provisioning)
  ///   8: business profile selection (Phase B — all modes)
  ///
  /// Developer password (7) and business profile (8) are inserted BEFORE
  /// the heavy-lifting steps so the admin picks them up front. Once set,
  /// the end-user cannot change them without the developer password.
  /// ⚠️ **الترتيبُ في `domain/models/setup_step_order.dart`** — حسابٌ خالصٌ
  /// يُقاس بلا تركيبِ شجرة، ويحرسه `test/unit/setup_step_order_test.dart`.
  ///
  /// كان مكتوباً هنا بثلاثة `return`، و**بلا اختبارٍ واحد** فوق ٣٨٤١ سطرٍ من
  /// المعالج. وأوّلُ ما تكسره إعادةُ تنسيقٍ بصريّةٌ هو ترتيبُ الخطوات: تُنقَل
  /// كتلةٌ فتُزاح خطوةٌ ولا شيءَ يقول، ويظهر النقصُ بعد أيّامٍ في تنصيبِ عميل.
  ///
  /// 🔴 **وهو قرارُ مالكٍ مثبَّت** (‏2026-08-28) يخالف التصميمَ عمداً —
  /// راجع تعليقَ الملفّ قبل أيّ تعديل.
  List<int> get _activeSteps => setupStepOrderFor(_deploymentMode);

  /// `NetworkMode` مترجَماً إلى نوع الحساب الخالص.
  ///
  /// ⚠️ **نسخةٌ لا استيراد**: `setup_step_order.dart` لا يستورد
  /// `services/network_service.dart` عمداً — فذلك يجرّ الشبكةَ والقاعدةَ إلى
  /// اختبارِ وحدةٍ لا يحتاجهما.
  SetupDeploymentMode get _deploymentMode {
    switch (_networkMode) {
      case NetworkMode.client:
        return SetupDeploymentMode.client;
      case NetworkMode.server:
        return SetupDeploymentMode.server;
      case NetworkMode.mirror:
        return SetupDeploymentMode.mirror;
      case NetworkMode.standalone:
        return SetupDeploymentMode.standalone;
    }
  }

  int get _totalSteps => _activeSteps.length;

  int get _activeStepIndex => _activeSteps.indexOf(_currentStep);

  bool get _isLastStep => _activeStepIndex == _totalSteps - 1;

  int get _nextStep => setupNextStep(_activeSteps, _currentStep);

  int get _prevStep => setupPreviousStep(_activeSteps, _currentStep);

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyPhoneController.dispose();
    _companyAddressController.dispose();
    _branchNameController.dispose();
    _warehouseNameController.dispose();
    _productNameController.dispose();
    _productPriceController.dispose();
    _productCostController.dispose();
    _userDisplayNameController.dispose();
    _userUsernameController.dispose();
    _userPasswordController.dispose();
    _serverAddressController.dispose();
    _serverPortController.dispose();
    _mirrorAdminUsernameController.dispose();
    _mirrorAdminPasswordController.dispose();
    _pgHostController.dispose();
    _pgPortController.dispose();
    _pgDatabaseController.dispose();
    _pgUserController.dispose();
    _pgPasswordController.dispose();
    _developerPasswordController.dispose();
    _developerPasswordConfirmController.dispose();
    _companyNameEnController.dispose();
    _taxNumberController.dispose();
    _commercialRegisterController.dispose();
    _branchCodeController.dispose();
    _branchAddressController.dispose();
    _cashBoxNameController.dispose();
    _bankSafeNameController.dispose();
    _bankNameController.dispose();
    _bankAccountController.dispose();
    _cliqSafeNameController.dispose();
    _adminPasswordController.dispose();
    _adminPasswordConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // بندُ المالك ٦: الاتجاهُ من لغة الواجهة لا مثبَّتاً RTL — اختيارُ
    // «English» في خطوة الترحيب يقلب المعالجَ كلَّه LTR فوراً.
    final isEnglish = I18nCatalog.activeLocale.languageCode == 'en';
    return Directionality(
      textDirection: isEnglish ? ui.TextDirection.ltr : ui.TextDirection.rtl,
      // Enter = التالي (‏لوحةُ المفاتيح أوّلاً) — راجع `_onWizardKey`.
      child: Focus(
        onKeyEvent: _onWizardKey,
        child: Scaffold(
        // 🔴 **عطبُ التباين الذي بلّغ عنه المالك.** كان اللونُ الأوسطُ
        //    `Colors.white` مثبَّتاً، فيرسم شريطاً أبيضَ عبر وسط الشاشة في
        //    الوضع الداكن — والعنوانُ الفرعيُّ `AppColors.textMuted` عليه
        //    يكاد لا يُقرَأ.
        //
        // ⚠️ **والأبيضُ هنا أرضيّةُ `BoxDecoration` فيؤمَن تبديلُه.** أكثرُ
        //    ما في المستودع من `Colors.white` **مقدّمةٌ** لا خلفيّة (‏نصٌّ
        //    على زرٍّ ملوّن)، وتبديلُه هناك يجعله غيرَ مقروء. فالفحصُ
        //    السطريُّ لا يكفي — وهذا الموضعُ مقيسٌ أرضيّةً.
        //
        //    والبديلُ `scaffoldBackgroundColor` من الثيم: يتبع الوضعَين،
        //    فيبقى التدرّجُ لمسةً فوقه لا طبقةً تُخفيه.
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topEnd,
              end: AlignmentDirectional.bottomStart,
              colors: [
                AppColors.primary.withValues(alpha: 0.05),
                Theme.of(context).scaffoldBackgroundColor,
                AppColors.primary.withValues(alpha: 0.02),
              ],
            ),
          ),
          child: Column(
            children: [
              // Header
              // ⚠️ حشوةٌ رأسيّةٌ ١٦ لا ٢٤: على ١٣٦٦×٧٦٨ كلُّ بكسلٍ رأسيٍّ هنا
              //    يُقتطع من جسم الخطوة (‏بندُ المالك ٦ — بلا فيضٍ على ٧٦٨).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        PhosphorIconsBold.rocketLaunch,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // تسريب هوية: أول شاشة يشوفها عميل PicPos كانت
                          // بترحّب بيه باسم المنتج التاني. النص عربي، يعني
                          // مخزّن UTF-16 في الـ snapshot — فحص ASCII في
                          // قسم ٣.٤ **مبيشوفهوش**. اتكشف بفحص UTF-16.
                          //
                          // الشرط `const` فبيتحسم وقت الترجمة والفرع التاني
                          // بيتشال من الـ snapshot أصلاً. وقيمة UralCash
                          // متروكة بالحرف عشان شكله ما يتغيّرش.
                          tr('مرحباً بك في {p0}',
                              {'p0': Brand.isPicPos ? Brand.name : 'URAL-ERP'}),
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.titleLarge?.color,
                          ),
                        ),
                        // 🔴 **الشقُّ الثاني من عطب التباين**: كان
                        //    `AppColors.textMuted` مثبَّتاً — رماديٌّ مضبوطٌ
                        //    للوضع الفاتح وحدَه، فيذوب في الداكن. ولونُ
                        //    `bodySmall` من الثيم يتبع الوضعَين.
                        Text(
                          tr('دعنا نُعد نظامك في دقائق معدودة'),
                          style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color
                                ?.withValues(alpha: 0.85),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Progress
                    _buildProgressIndicator(),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Body
              Expanded(
                child: Row(
                  children: [
                    // Side Steps
                    //
                    // ⚠️ **يُبنى من `_activeSteps` لا من قائمةٍ مكتوبةٍ بيد.**
                    //    كانت القائمةُ تُكتَب سطراً سطراً وتُغفل الخطوتَين `8`
                    //    (نوع النشاط) و`7` (كلمة مرور المطوّر) رغم أنّهما في
                    //    `_activeSteps` وتُحسبان في `_totalSteps` — فيقف
                    //    المستخدمُ على إحداهما فيقرأ «الخطوة ٢ من ٨» ولا
                    //    يُضاء شيءٌ أمامه في العمود. والبناءُ من المصدر يجعل
                    //    ذلك مستحيلاً: ما يُزار يظهر.
                    Container(
                      width: 272,
                      // ⚠️ حدٌّ رفيعٌ يفصل العمودَ عن الجسم (‏DESIGN.md: أسطحٌ
                      //    مسطّحةٌ بخطوطٍ رفيعة) بلا ظلّ.
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        border: BorderDirectional(
                          end: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  for (final s in _activeSteps)
                                    if (kSetupSteps[s] != null)
                                      _buildStepItem(kSetupSteps[s]!),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 20),
                          _buildSidebarFooter(),
                        ],
                      ),
                    ),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(28, 18, 28, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildStepHeader(),
                            const SizedBox(height: 16),
                            Expanded(
                              // جسمُ الخطوة على اليمين ولوحةُ الشرح على اليسار،
                              // كما في التصميم. وتنهار اللوحةُ تحت ١٤٠٠px بدل
                              // أن تسحق الجسمَ إلى عرضٍ لا يُدخَل فيه.
                              child: LayoutBuilder(
                                builder: (context, c) {
                                  final body = SingleChildScrollView(
                                    child: _buildCurrentStep(),
                                  );
                                  final aside = _buildStepAside();
                                  if (c.maxWidth < 1400 || aside == null) {
                                    return body;
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: body),
                                      const SizedBox(width: 18),
                                      SizedBox(
                                        width: 330,
                                        child: SingleChildScrollView(
                                            child: aside),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Navigation buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (_activeStepIndex > 0)
                                  OutlinedButton.icon(
                                    key: const Key('setup_back'),
                                    onPressed: _runStage != null
                                        ? null
                                        : () => setState(() {
                                              _returnToReview = false;
                                              _currentStep = _prevStep;
                                            }),
                                    // `arrow_back` بـ`matchTextDirection` — → في
                                    // RTL و← في LTR، كما في `PicPosPageHeader`.
                                    icon: const Icon(Icons.arrow_back, size: 18),
                                    label:  Text(tr('السابق')),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 26,
                                        vertical: 14,
                                      ),
                                    ),
                                  )
                                else
                                  TextButton(
                                    onPressed: _skipSetup,
                                    child: Text(
                                      tr('تخطي الإعداد'),
                                      style: TextStyle(color: _mutedInk(context)),
                                    ),
                                  ),
                                // نقاطُ الترقيم في وسط التذييل — كما في
                                // التصميم. تُطوى تحت ٩٠٠px حيث لا يبقى لها
                                // عرضٌ بين الزرَّين.
                                Flexible(
                                  child: LayoutBuilder(
                                    builder: (context, c) => c.maxWidth < 260
                                        ? const SizedBox.shrink()
                                        : _buildStepDots(),
                                  ),
                                ),
                                // تخطّي الخطوة الاختياريّة — بجوار «التالي».
                                if (!_isLastStep &&
                                    kOptionalSetupSteps.contains(_currentStep) &&
                                    !_returnToReview)
                                  Padding(
                                    padding:
                                        const EdgeInsetsDirectional.only(end: 10),
                                    child: TextButton(
                                      key: const Key('setup_skip_step'),
                                      onPressed: _skipOptionalStep,
                                      child: Text(tr('تخطي هذه الخطوة')),
                                    ),
                                  ),
                                !_isLastStep
                                    ? ElevatedButton.icon(
                                        key: const Key('setup_next'),
                                        onPressed: _canAdvance() ? _goNext : null,
                                        // `arrow_forward` ← في RTL و→ في LTR.
                                        icon: Icon(
                                          _returnToReview
                                              ? PhosphorIconsBold.listChecks
                                              : Icons.arrow_forward,
                                          size: 18,
                                        ),
                                        label: Text(_returnToReview
                                            ? tr('العودة إلى المراجعة')
                                            : tr('التالي')),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 28,
                                            vertical: 14,
                                          ),
                                        ),
                                      )
                                    : ElevatedButton.icon(
                                        key: const Key('setup_finish'),
                                        onPressed: _isSaving ? null : _finishSetup,
                                        icon: _isSaving
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : Icon(_runResult?.ok == false
                                                ? PhosphorIconsBold.arrowsClockwise
                                                : PhosphorIconsBold.checkCircle),
                                        // فشلت محاولةٌ ⇒ الزرُّ نفسُه «إعادة من البداية».
                                        label: Text(_runResult?.ok == false
                                            ? tr('إعادة المحاولة من البداية')
                                            : tr('إنهاء الإعداد والبدء')),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 28,
                                            vertical: 14,
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ],
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
      ),
    );
  }

  /// نقاطُ الترقيم في التذييل — موضعُ الخطوة من المسار بلمحة.
  ///
  /// ⚠️ **تُقرأ ولا يُنقَر عليها**: القفزُ إلى خطوةٍ لاحقةٍ يتخطّى
  /// `_canAdvance()` الذي يحرس الحقولَ الإلزاميّة — فيصل المستخدمُ إلى
  /// التهيئة باسمِ شركةٍ فارغ. والتنقّلُ يبقى بالزرَّين.
  Widget _buildStepDots() {
    final steps = _activeSteps;
    final at = _activeStepIndex;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              // الحاليّةُ أعرضُ — فيُعرَف موضعُها بلا لونٍ وحدَه (‏عمى
              // الألوان يجعل النقاطَ المتساويةَ بلا معنى).
              width: i == at ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i <= at
                    ? AppColors.primary
                    : Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }

  /// ذيلُ الشريط الجانبيّ — مبدّلُ السمة.
  ///
  /// ═══ ⚠️ وبندان في التصميم لا يُعرَضان ═══
  ///
  /// 🔴 **«استعادة نسخة»**: `BackupRestoreWidget` قائمٌ فعلاً، لكنّه يستبدل
  ///    القاعدةَ **تحت** معالجٍ يجري تهيئتَها الآن. والخطوةُ ٦ تكتب الجداولَ
  ///    وشجرةَ الحسابات والسنةَ الماليّة، واستعادةٌ في منتصفها تترك تنصيباً
  ///    نصفَه من النسخة ونصفَه من التهيئة — ولا تراجعَ فيه.
  ///    ⇒ يحتاج مسارَ «استعادة بدل تنصيب» يبدأ **قبل** المعالج، وهو بناءٌ
  ///      لا تنسيق. فلا يُعرَض زرٌّ يَعِد بما لم يُبنَ.
  ///
  /// 🔴 **«مساعدة»**: لا شاشةَ مساعدةٍ في التطبيق، ولا رابطَ توثيقٍ مستقرّ.
  Widget _buildSidebarFooter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () => ref
            .read(themeModeProvider.notifier)
            .setMode(isDark ? ThemeMode.light : ThemeMode.dark),
        icon: Icon(
          isDark ? PhosphorIconsBold.sun : PhosphorIconsBold.moon,
          size: 16,
        ),
        label: Text(isDark ? tr('الوضع الفاتح') : tr('الوضع الداكن')),
        style: TextButton.styleFrom(foregroundColor: _mutedInk(context)),
      ),
    );
  }

  /// عنوانُ حقلٍ داخلَ جسم الخطوة — فوق مجموعةِ بطاقاتٍ أو رقاقات.
  Widget _stepFieldLabel(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: _mutedInk(context),
        ),
      );

  /// بطاقةُ اختيارٍ — أيقونةٌ وعنوانٌ وسطرٌ يشرح الفرق.
  ///
  /// ⚠️ **الوصفُ ليس زخرفة**: هو ما يفرّق «تجزئة» عن «جملة وتوزيع» لمن
  /// يُنصّب أوّلَ مرّة، والقائمةُ المنسدلةُ تُخفيه خلفَ نقرة.
  Widget _choiceCard({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : theme.cardColor,
          border: Border.all(
            color: selected ? AppColors.primary : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? _brandInk(context) : _mutedInk(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: selected ? _brandInk(context) : null,
                    ),
                  ),
                ),
                if (selected)
                  Icon(
                    PhosphorIconsBold.checkCircle,
                    size: 16,
                    color: _brandInk(context),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11.5, color: _mutedInk(context)),
            ),
          ],
        ),
      ),
    );
  }

  /// شريطُ التقدّم — عدّادُ الخطوة ونسبةٌ مئويّةٌ كما في التصميم.
  ///
  /// ⚠️ **النسبةُ على الخطوة المكتملة لا الحاليّة** (`setupProgress`):
  /// الوقوفُ على أوّل خطوةٍ تقدّمُه صفرٌ لا `1/8`. وشريطٌ يبدأ ممتلئاً
  /// جزئيّاً قبل أن يُكتَب حرفٌ يَعِد بما لم يقع.
  ///
  /// والعدّادُ يبقى `الخطوة ١ من ٨` — وهو موضعٌ لا تقدّم، فلا تناقضَ بينهما.
  Widget _buildProgressIndicator() {
    final progress = setupProgress(_activeSteps, _currentStep);
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr('الخطوة {p0} من {_totalSteps}', {'p0': _activeStepIndex + 1, '_totalSteps': _totalSteps}),
          style: TextStyle(color: muted, fontSize: 14),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.border,
              color: AppColors.primary,
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          tr('{p0}٪', {'p0': (progress * 100).round()}),
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  /// ترويسةُ الخطوة — أيقونةٌ في مربّعٍ ملوّنٍ ثمّ العنوانُ الكبيرُ ووصفُه،
  /// وشارةٌ على الطرف تقول موضعَ الخطوة من المسار.
  Widget _buildStepHeader() {
    final meta = kSetupSteps[_currentStep];
    if (meta == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(meta.icon, size: 24, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(meta.title, style: text.headlineSmall),
              const SizedBox(height: 2),
              // لونُ الثيم لا `AppColors.textMuted` — ذاك يذوب في الداكن.
              Text(
                meta.sub,
                style: text.bodySmall?.copyWith(color: _mutedInk(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
          ),
          child: Text(
            tr('الخطوة {p0} من {_totalSteps}', {'p0': _activeStepIndex + 1, '_totalSteps': _totalSteps}),
            style: text.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  /// لوحةُ الشرح — «لماذا هذه الخطوة» وقائمةُ التحقّق والملاحظة.
  ///
  /// ⚠️ **ليست زينةً**: تصميمُ المعالج يعطي لكلّ خطوةٍ `why` و`checks`
  /// و`note`، وهي ما يحوّل المعالجَ من سلسلةِ حقولٍ إلى شرحٍ للأثر. وأخطرُ ما
  /// فيها الملاحظاتُ التي تقول ما لا رجعةَ فيه (‏العملة · تصفير البيانات ·
  /// كلمة مرور المطوّر) — وإخفاؤها يجعل المستخدمَ يقرّر بلا علم.
  ///
  /// تعود `null` لخطوةٍ بلا سجلّ، فلا تُرسَم لوحةٌ فارغة.
  Widget? _buildStepAside() {
    final meta = kSetupSteps[_currentStep];
    if (meta == null) return null;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(PhosphorIconsBold.lightbulb,
                      size: 17, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(tr('لماذا هذه الخطوة'),
                      style: text.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                meta.why,
                style: text.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.7,
                ),
              ),
              const Divider(height: 24),
              Text(tr('تحقّقْ قبل المتابعة'),
                  style:
                      text.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final c in meta.checks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        c.required
                            ? PhosphorIconsBold.checkCircle
                            : PhosphorIconsBold.circleDashed,
                        size: 15,
                        color: c.required
                            ? AppColors.success
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.label,
                          style: text.labelSmall?.copyWith(
                            height: 1.5,
                            color: c.required ? null : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: meta.note.tone.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: meta.note.tone.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(meta.note.icon, size: 17, color: meta.note.tone),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      meta.note.title,
                      style: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: meta.note.tone,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                meta.note.body,
                style: text.labelSmall?.copyWith(
                  height: 1.6,
                  color: meta.note.tone,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// بندُ خطوةٍ في العمود — على تخطيط التصميم: مربّعُ رقمٍ (أو علامةُ تمامٍ)
  /// ثمّ العنوانُ وتلميحُه ثمّ أيقونةُ الخطوة.
  ///
  /// ⚠️ **الرقمُ ترتيبيٌّ في المسار لا الرقمُ الداخليّ**: `_activeSteps` تعيد
  /// `[0, 8, 7, 1, …]`، فعرضُ `8` بجانب الخطوة الثانية يقرأ خطأً. المعروضُ هو
  /// موضعُها في المسار + ١ — وهو عينُ ما يقوله شريطُ «الخطوة N من M».
  Widget _buildStepItem(SetupStepMeta meta) {
    final isActive = _currentStep == meta.index;
    final myStepIdx = _activeSteps.indexOf(meta.index);
    final isCompleted = myStepIdx >= 0 && _activeStepIndex > myStepIdx;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        // ⚠️ القفزُ عبر `_jumpTo` لا تعيينٌ مباشر: الأمامُ مقفولٌ حتّى تصحَّ
        //    كلُّ خطوةٍ قبله — وإلّا وصل المستخدمُ إلى المراجعة باسمِ شركةٍ فارغ.
        onTap: _runStage != null ? null : () => _jumpTo(meta.index),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.30)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: isCompleted
                      ? AppColors.success
                      : isActive
                          ? AppColors.primary
                          : Colors.transparent,
                  border: Border.all(
                    color: isCompleted
                        ? AppColors.success
                        : isActive
                            ? AppColors.primary
                            : Theme.of(context).dividerColor,
                    width: 1.5,
                  ),
                ),
                child: isCompleted
                    ? const Icon(PhosphorIconsBold.check,
                        color: Colors.white, size: 15)
                    : Text(
                        '${myStepIdx + 1}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color:
                              isActive ? Colors.white : _mutedInk(context),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(
                        fontWeight:
                            isActive ? FontWeight.w800 : FontWeight.w600,
                        color: isActive ? _brandInk(context) : null,
                      ),
                    ),
                    Text(
                      meta.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall
                          ?.copyWith(color: _mutedInk(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                meta.icon,
                size: 17,
                color: isActive ? _brandInk(context) : _mutedInk(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// جسمُ الخطوة الحاليّة.
  ///
  /// ⚠️ ٤ و٧ و٨ و٩ لم تعد في أيّ مسار (‏بندُ المالك ٦) — أجسامُها صارت أقساماً
  /// في الترحيب والشركة والمستخدمين والعملة. وتبقى هنا موجَّهةً إلى الخطوة
  /// التي استوعبتها، فلا تُرسَم صفحةٌ فارغةٌ لو وصلها أحدٌ برقمها القديم.
  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case SetupStepIds.welcome:
      case SetupStepIds.touchMode:
        return _buildWelcomeStep();
      case SetupStepIds.company:
      case SetupStepIds.businessProfile:
        return _buildCompanyInfoStep();
      case SetupStepIds.currencyTax:
      case SetupStepIds.tax:
        return _buildCurrencyTaxStep();
      case SetupStepIds.branchAndMode:
        return _buildBranchStep();
      case SetupStepIds.cashBanks:
        return _buildCashBanksStep();
      case SetupStepIds.chartOfAccounts:
        return _buildChartPreviewStep();
      case SetupStepIds.users:
      case SetupStepIds.developerPassword:
        return _buildUsersStep();
      case SetupStepIds.products:
        return _buildProductsStep();
      case SetupStepIds.postgres:
        return _buildPgConfigStep();
      case SetupStepIds.provisioning:
        return _buildProvisioningStep();
      case SetupStepIds.review:
        return _buildReviewStep();
      default:
        return const SizedBox();
    }
  }

  Future<void> _connectAndSync() async {
    final addr = _serverAddressController.text.trim();
    if (addr.isEmpty) return;
    setState(() {
      _isConnecting = true;
      _connectionResult = null;
    });

    try {
      final port = int.tryParse(_serverPortController.text) ?? 8080;
      final ns = NetworkService.instance;

      // CRITICAL: Set server address BEFORE switching mode
      // so that saveSettings() inside setMode persists the correct URL
      ns.setServerAddress(addr, port: port);
      final db = ref.read(databaseProvider);

      // Save as client mode (this calls saveSettings internally)
      await ns.setMode(NetworkMode.client, db: db);
      // Persist again to ensure address is saved
      await ns.saveSettings();

      // Test connection first (extracts API token from health endpoint)
      final testResult = await ns.testServerConnection(addr, port);
      if (!testResult['success']) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
            _connectionResult = tr('❌ فشل الاتصال بالسيرفر: {p0}', {'p0': testResult['error']});
          });
        }
        return;
      }

      // Build server URL
      final serverUrl = ns.buildServerUrl(address: addr, port: port);
      final syncService = SyncService(serverUrl: serverUrl, localDb: db);

      // Spec 001: client-first-sync invariant — the local seeder ran with
      // isClientMode=false at first DB open (mode unknown then). Wipe its
      // master rows before pulling so the server's data lands in clean
      // tables. If the device was already paired, this is a re-pair; ask
      // for explicit confirmation per Spec Risk Register.
      final firstSyncService = ClientFirstSyncService(db: db);
      final pending = await firstSyncService.isFirstSyncPending();
      if (!pending) {
        final confirmed = await _confirmRePair();
        if (!confirmed) {
          if (mounted) {
            setState(() {
              _isConnecting = false;
              _connectionResult = null;
            });
          }
          return;
        }
        await firstSyncService.reset();
      }

      late final FirstSyncResult firstSyncResult;
      try {
        firstSyncResult = await firstSyncService.performFirstSync(
          syncService: syncService,
          onProgress: (stage) {
            if (!mounted) return;
            setState(() => _connectionResult = '⏳ ${_progressLabel(stage)}…');
          },
        );
      } on FirstSyncException catch (e) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
            _connectionResult = tr('⚠️ فشلت المزامنة: {p0}', {'p0': e.message});
          });
        }
        return;
      }

      // Seed watermarks so the first periodic delta pull is incremental
      // rather than redundantly re-pulling what the strategies just loaded.
      // Prefer the authoritative server clock over a client clock that may
      // run ahead of the server and cause rows modified in the skew window
      // to be skipped.
      final serverSec = await ServerProxy.instance.fetchServerTime();
      final seedSec = serverSec ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 60;
      await DeltaPullService.instance.seedWatermarks(seedSec);

      // Load synced branches
      final branchRepo = ref.read(branchRepositoryProvider);
      final branches = await branchRepo.getAllBranches();

      if (mounted) {
        final warningSuffix = firstSyncResult.warningCount > 0
            ? tr(' ({p0} تحذير)', {'p0': firstSyncResult.warningCount})
            : '';
        setState(() {
          _isConnecting = false;
          _syncedBranches = branches;
          _connectionResult =
              tr('✅ تم الاتصال والمزامنة — {p0} جدول{warningSuffix}', {'p0': firstSyncResult.tablesSynced, 'warningSuffix': warningSuffix});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionResult = tr('❌ خطأ: {e}', {'e': e});
        });
      }
    }
  }

  /// Mirror-mode handshake. Validates reachability to the HQ server,
  /// captures + persists the API token (via testServerConnection), and
  /// records the server identity in [MirrorState]. The actual
  /// `NetworkService.setMode(NetworkMode.mirror)` call is deferred to
  /// `_finishSetup` so the wizard can fall back cleanly if the user
  /// changes their mind on a later step.
  ///
  /// Spec 097: pairing logic lives in [MirrorPairingService] so the
  /// Developer Tools "مرآة" toggle (`MirrorPairingDialog`) can reuse it.
  Future<void> _pairMirror() async {
    final addr = _serverAddressController.text.trim();
    final adminUsername = _mirrorAdminUsernameController.text.trim();
    final adminPassword = _mirrorAdminPasswordController.text;
    final port = int.tryParse(_serverPortController.text) ?? 8080;

    setState(() {
      _isConnecting = true;
      _connectionResult = null;
    });

    try {
      final result = await MirrorPairingService.instance.pair(
        host: addr,
        port: port,
        adminUsername: adminUsername,
        adminPassword: adminPassword,
        // Spec 151 P1-8b — mint an admin session token now so the mirror's
        // first-sync (run by the committer in _finishSetup) pulls ALL
        // branches' transactions instead of fail-closing to zero rows.
        acquireAdminSession: true,
      );

      if (!result.isSuccess) {
        if (mounted) {
          final icon = result.outcome == MirrorPairingOutcome.missingFields
              ? '⚠️'
              : '❌';
          setState(() {
            _isConnecting = false;
            _connectionResult = '$icon ${result.message}';
          });
        }
        return;
      }

      // Wipe the password from memory immediately after pairing — the
      // controller only existed to drive verify-admin and is no longer
      // needed for the rest of the wizard / runtime.
      _mirrorAdminPasswordController.clear();

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionResult =
              tr('✅ تم التحقق من المدير "{p0}" — سيتم تفعيل وضع المرآة عند إنهاء المعالج', {'p0': result.adminDisplayName});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionResult = tr('❌ خطأ: {e}', {'e': e});
        });
      }
    }
  }

  String _progressLabel(String stage) {
    switch (stage) {
      case 'wipe':
        return tr('تجهيز قاعدة البيانات');
      case 'sync':
        return tr('مزامنة الجداول');
      case 'finalize':
        return tr('الانتهاء');
      default:
        return stage;
    }
  }

  /// Re-pair confirmation dialog — shown when the device was already paired
  /// to a server (`client_first_sync_completed == 'true'`) and the user
  /// triggers another sync. Default focus is on "إلغاء" so an accidental
  /// Enter press doesn't wipe local master data.
  Future<bool> _confirmRePair() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('إعادة ربط الجهاز')),
        content:  Text(
          tr('سيتم مسح البيانات الرئيسية المحلية (الفروع، المخازن، الخزائن، شركات التوصيل، دليل الحسابات) واستبدالها بنسخة السيرفر.\n\nهل أنت متأكد من المتابعة؟'),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child:  Text(tr('إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:  Text(tr('متابعة')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _addProduct() {
    final name = _productNameController.text.trim();
    final price = _productPriceController.text.trim();
    final cost = _productCostController.text.trim();
    if (name.isEmpty) {
      // BUG-U11: tell the user why "إضافة" did nothing.
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(tr('أدخل اسم المنتج أولاً'))),
      );
      return;
    }
    setState(() {
      _sampleProducts.add({
        'name': name,
        'price': price.isEmpty ? '0' : price,
        'cost': cost.isEmpty ? '0' : cost,
      });
      _productNameController.clear();
      _productPriceController.clear();
      _productCostController.clear();
    });
  }

  void _addWizardUser() {
    final displayName = _userDisplayNameController.text.trim();
    final username = _userUsernameController.text.trim();
    final password = _userPasswordController.text;

    if (displayName.isEmpty || username.isEmpty || password.isEmpty) {
      AppToast.show(context, tr('يجب ملء جميع الحقول المطلوبة'), type: ToastType.error);
      return;
    }
    if (_userSelectedRoleId == null) {
      AppToast.show(context, tr('يجب اختيار دور للمستخدم'), type: ToastType.error);
      return;
    }

    // Check duplicate username
    if (_wizardUsers.any((u) => u['username'] == username)) {
      AppToast.show(context, tr('اسم المستخدم "{username}" مضاف بالفعل', {'username': username}), type: ToastType.error);
      return;
    }

    // §١ — نفسُ منع `DuplicatePasswordException` لكن **هنا** لا عند الحفظ:
    // القائمةُ تُلتزم دفعةً واحدة في نهاية المعالج، فلو تُرك التصادمُ
    // لـ`createUser` لسقط مستخدمٌ من الدفعة والمشغّلُ قد جاوز الخطوة.
    // والمقارنةُ نصّيّةٌ مباشرة لأن الكلماتِ هنا غيرُ مجزَّأةٍ بعد — ولا
    // حاجةَ لـArgon2 ولا لكلفته.
    final duplicateOf = _wizardUsers
        .where((u) => u['password'] == password)
        .map((u) => u['username'] as String)
        .firstOrNull;
    // وكلمةُ المدير الجديدة من نفس الدفعة (‏بندُ المالك ٦) — نفسُ المنع.
    if (_asksAdminPassword && password == _adminPasswordController.text) {
      AppToast.show(
        context,
        tr('كلمةُ المرور هذه مستعملةٌ سلفاً للمستخدم "{duplicateOf}". اختر كلمةً مختلفة — كلمتان متطابقتان تمنعان أحدَ صاحبَيهما من الدخول.', {'duplicateOf': 'admin'}),
        type: ToastType.error,
      );
      return;
    }
    if (duplicateOf != null) {
      AppToast.show(
        context,
        tr('كلمةُ المرور هذه مستعملةٌ سلفاً للمستخدم "{duplicateOf}". اختر كلمةً مختلفة — كلمتان متطابقتان تمنعان أحدَ صاحبَيهما من الدخول.', {'duplicateOf': duplicateOf}),
        type: ToastType.error,
      );
      return;
    }

    // Resolve role name for display
    final roles = ref.read(allRolesProvider).value ?? [];
    final roleName = roles.where((r) => r.id == _userSelectedRoleId).map((r) => r.name).firstOrNull ?? '';

    setState(() {
      _wizardUsers.add({
        'displayName': displayName,
        'username': username,
        'password': password,
        'roleId': _userSelectedRoleId,
        'roleName': roleName,
      });
      _userDisplayNameController.clear();
      _userUsernameController.clear();
      _userPasswordController.clear();
      _userSelectedRoleId = null;
    });

    AppToast.show(context, tr('تم إضافة المستخدم "{displayName}"', {'displayName': displayName}), type: ToastType.success);
  }

  Future<void> _skipSetup() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    // SAFETY: Reset network to standalone when skipping setup
    // to clear any stale prefs from a previous installation.
    // Spec 089: pass DB so the canonical settings.network_mode is also
    // set to 'standalone' — prevents the prefs/DB split-brain.
    await NetworkService.instance.resetToStandalone(db: ref.read(databaseProvider));

    // Auto-create fiscal year for the current calendar year
    try {
      final accountingRepo = ref.read(accountingRepositoryProvider);
      final now = DateTime.now();
      final fyStart = DateTime(now.year, 1, 1);
      final fyEnd = DateTime(now.year, 12, 31);
      final fyId = await accountingRepo.createFiscalYear(
        name: '${now.year}',
        startDate: fyStart,
        endDate: fyEnd,
      );
      await accountingRepo.generatePeriodsForYear(fyId, fyStart, fyEnd);
    } catch (_) {
      // Fiscal year may already exist — silently continue
    }

    await settingsRepo.saveSetting('setup_completed', 'true');

    // Owner decision 2026-08-17: hardening applies to EITHER exit path —
    // shared with `_finishSetup()` via
    // `ConfigService.rehydrateRuntimeConfigCache` (Spec B3) instead of a
    // wizard-private copy that only `_finishSetup()` used to have. Skip
    // writes nothing for business_profile/deployment_mode/developer
    // password by design (the whole point of "skip" is "use the
    // compiled defaults"), so DB and cache already agree on those; this
    // call keeps `setup_completed` (written above through the uncached
    // repo) in lock-step and guards against any future step that starts
    // writing more state before Skip is reachable.
    final cacheOk = await ref
        .read(configServiceProvider)
        .rehydrateRuntimeConfigCache(exitPath: 'skip');

    if (mounted) {
      if (!cacheOk) {
        AppToast.show(
          context,
          tr('تم تخطي الإعداد، لكن تعذّر تحديث ذاكرة الإعدادات المؤقتة. يُفضَّل إعادة تشغيل التطبيق قبل استخدام أدوات المطوّر.'),
          type: ToastType.warning,
        );
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (r) => false,
      );
    }
  }
  // ⚠️ _finishSetup انتقل إلى setup_wizard/setup_wizard_flow.dart، وكتاباتُه
  //    كلُّها إلى SetupFinishRunner (‏setup_finish_runner.dart) بالترتيب
  //    نفسِه — ويحرس التكافؤَ 	est/unit/setup_finish_runner_parity_test.dart.
}
