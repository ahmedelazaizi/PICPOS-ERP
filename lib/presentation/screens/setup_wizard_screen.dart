// ignore_for_file: avoid_dynamic_calls
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
// `app_config.dart` يعيد تصدير `business_profile.dart` — فمفيش استيراد
// مباشر ليه هنا (الـ analyzer بيعتبره زيادة).
import '../../core/config/app_config.dart';
import '../../core/config/business_profile_meta.dart';
import '../../core/config/business_profile_provider.dart';
import '../../core/config/feature_key.dart';
import '../../core/config/feature_policy.dart';
import '../../core/theme/app_colors.dart';
import '../../data/database/connection_io.dart'
    show openPostgresConnection, testPostgresConnection;
import '../../data/database/pg_config.dart';
import '../../data/providers/providers.dart';
import '../../data/repositories/settings_repository_cached.dart';
import '../../services/audit_log.dart';
import '../../services/developer_auth_service.dart';
import '../../services/network_service.dart';
import '../../services/mirror_pairing_service.dart';
import '../../services/mirror_state.dart';
import '../../services/mirror_heartbeat_service.dart';
import '../../services/delta_pull_service.dart';
import '../../services/server_proxy.dart';
import '../../services/sync_service.dart';
import '../../services/sync/client_first_sync_service.dart';
import '../../services/deployment/deployment_mode_committer.dart';
import '../../services/deployment/commit_result.dart';
import '../../app_main_screen.dart';
import '../touch_keyboard/providers/touch_mode_provider.dart';
import '../../core/config/brand.dart';

part 'setup_wizard/step_company_info.dart';
part 'setup_wizard/step_branch.dart';
part 'setup_wizard/step_products.dart';
part 'setup_wizard/step_users.dart';
part 'setup_wizard/step_settings.dart';
part 'setup_wizard/step_provisioning.dart';
part 'setup_wizard/step_touch_mode.dart';

/// First-Run Setup Wizard — shown once after first login
/// Guides the user through essential setup steps.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  int _currentStep = 0;

  // Step 1: Company Info
  final _companyNameController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyAddressController = TextEditingController();
  String _businessType = 'retail';
  String _currency = 'EGP';

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
  final _branchNameController = TextEditingController(text: 'الفرع الرئيسي');
  final _warehouseNameController = TextEditingController(text: 'المخزن الرئيسي');

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
    _ProvisionStep('اختبار الاتصال بالسيرفر'),
    _ProvisionStep('إنشاء جداول قاعدة البيانات'),
    _ProvisionStep('زرع البيانات الأساسية (أدوار، فرع، مخزن، خزائن…)'),
    _ProvisionStep('زرع شجرة الحسابات'),
    _ProvisionStep('إنشاء السنة المالية الحالية'),
    _ProvisionStep('التحقق من اكتمال البيانات'),
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
  List<int> get _activeSteps {
    // Feature 031 — step `9` (Touch Mode) inserted AFTER network selection
    // (step 1) and BEFORE the first heavy data step. Same position in
    // every mode so operators on any deployment shape see it (research D13).
    if (_networkMode == NetworkMode.client) {
      return [0, 8, 7, 1, 9, 3, 4]; // company, profile, dev-pwd, network, touch, users, tax
    }
    if (_networkMode == NetworkMode.server) {
      return [0, 8, 7, 1, 9, 5, 6]; // company, profile, dev-pwd, network, touch, PG, provision
    }
    // standalone + mirror share the user-facing skeleton; mirror finalises
    // via _pairMirror inside step 1, so it doesn't need extra steps.
    return [0, 8, 7, 1, 9, 2, 3, 4];
  }

  int get _totalSteps => _activeSteps.length;

  int get _activeStepIndex => _activeSteps.indexOf(_currentStep);

  bool get _isLastStep => _activeStepIndex == _totalSteps - 1;

  int get _nextStep {
    final idx = _activeStepIndex;
    if (idx < _totalSteps - 1) return _activeSteps[idx + 1];
    return _currentStep;
  }

  int get _prevStep {
    final idx = _activeStepIndex;
    if (idx > 0) return _activeSteps[idx - 1];
    return _currentStep;
  }

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.05),
                Colors.white,
                AppColors.primary.withValues(alpha: 0.02),
              ],
            ),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        PhosphorIconsBold.rocketLaunch,
                        color: Colors.white,
                        size: 28,
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
                          Brand.isPicPos
                              ? 'مرحباً بك في ${Brand.name}'
                              : 'مرحباً بك في URAL-ERP',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.titleLarge?.color,
                          ),
                        ),
                        const Text(
                          'دعنا نُعد نظامك في دقائق معدودة',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
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
                    Container(
                      width: 280,
                      color: Theme.of(context).cardColor,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          _buildStepItem(0, 'معلومات الشركة', PhosphorIconsBold.buildings),
                          _buildStepItem(1, 'الفرع ووضع التشغيل', PhosphorIconsBold.mapPin),
                          if (_activeSteps.contains(9))
                            _buildStepItem(9, 'نمط الإدخال', PhosphorIconsBold.handTap),
                          if (_activeSteps.contains(5))
                            _buildStepItem(5, 'إعدادات PostgreSQL', PhosphorIconsBold.database),
                          if (_activeSteps.contains(6))
                            _buildStepItem(6, 'تهيئة القاعدة', PhosphorIconsBold.hardDrives),
                          if (_activeSteps.contains(2))
                            _buildStepItem(2, 'المنتجات الأولى', PhosphorIconsBold.package),
                          if (_activeSteps.contains(3))
                            _buildStepItem(3, 'المستخدمين', PhosphorIconsBold.users),
                          if (_activeSteps.contains(4))
                            _buildStepItem(4, 'الضرائب والإعدادات', PhosphorIconsBold.gear),
                        ],
                      ),
                    ),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: _buildCurrentStep(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Navigation buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (_activeStepIndex > 0)
                                  OutlinedButton.icon(
                                    onPressed: () => setState(() => _currentStep = _prevStep),
                                    icon: const Icon(PhosphorIconsBold.arrowRight),
                                    label: const Text('السابق'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                        vertical: 16,
                                      ),
                                    ),
                                  )
                                else
                                  TextButton(
                                    onPressed: _skipSetup,
                                    child: const Text(
                                      'تخطي الإعداد',
                                      style: TextStyle(color: AppColors.textMuted),
                                    ),
                                  ),
                                !_isLastStep
                                    ? ElevatedButton.icon(
                                        onPressed: _canAdvance()
                                            ? () => setState(() => _currentStep = _nextStep)
                                            : null,
                                        icon: const Icon(PhosphorIconsBold.arrowLeft),
                                        label: const Text('التالي'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 32,
                                            vertical: 16,
                                          ),
                                        ),
                                      )
                                    : ElevatedButton.icon(
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
                                            : const Icon(PhosphorIconsBold.checkCircle),
                                        label: const Text('إنهاء الإعداد والبدء'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 32,
                                            vertical: 16,
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
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: [
        Text(
          'الخطوة ${_activeStepIndex + 1} من $_totalSteps',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (_activeStepIndex + 1) / _totalSteps,
              backgroundColor: AppColors.border,
              color: AppColors.primary,
              minHeight: 8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepItem(int index, String title, IconData icon) {
    final isActive = _currentStep == index;
    final myStepIdx = _activeSteps.indexOf(index);
    final isCompleted = myStepIdx >= 0 && _activeStepIndex > myStepIdx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _currentStep = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? AppColors.success
                      : isActive
                          ? AppColors.primary
                          : AppColors.border,
                ),
                child: Icon(
                  isCompleted ? PhosphorIconsBold.check : icon,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive
                      ? AppColors.primary
                      : Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildCompanyInfoStep();
      case 1:
        return _buildBranchStep();
      case 2:
        return _buildProductsStep();
      case 3:
        return _buildUsersStep();
      case 4:
        return _buildSettingsStep();
      case 5:
        return _buildPgConfigStep();
      case 6:
        return _buildProvisioningStep();
      case 7:
        return _buildDeveloperPasswordStep();
      case 8:
        return _buildBusinessProfileStep();
      case 9:
        return _buildTouchModeStep();
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
            _connectionResult = '❌ فشل الاتصال بالسيرفر: ${testResult['error']}';
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
            _connectionResult = '⚠️ فشلت المزامنة: ${e.message}';
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
            ? ' (${firstSyncResult.warningCount} تحذير)'
            : '';
        setState(() {
          _isConnecting = false;
          _syncedBranches = branches;
          _connectionResult =
              '✅ تم الاتصال والمزامنة — ${firstSyncResult.tablesSynced} جدول'
              '$warningSuffix';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionResult = '❌ خطأ: $e';
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
              '✅ تم التحقق من المدير "${result.adminDisplayName}" — '
              'سيتم تفعيل وضع المرآة عند إنهاء المعالج';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionResult = '❌ خطأ: $e';
        });
      }
    }
  }

  String _progressLabel(String stage) {
    switch (stage) {
      case 'wipe':
        return 'تجهيز قاعدة البيانات';
      case 'sync':
        return 'مزامنة الجداول';
      case 'finalize':
        return 'الانتهاء';
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
        title: const Text('إعادة ربط الجهاز'),
        content: const Text(
          'سيتم مسح البيانات الرئيسية المحلية (الفروع، المخازن، الخزائن، '
          'شركات التوصيل، دليل الحسابات) واستبدالها بنسخة السيرفر.\n\n'
          'هل أنت متأكد من المتابعة؟',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('متابعة'),
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
        const SnackBar(content: Text('أدخل اسم المنتج أولاً')),
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
      AppToast.show(context, 'يجب ملء جميع الحقول المطلوبة', type: ToastType.error);
      return;
    }
    if (_userSelectedRoleId == null) {
      AppToast.show(context, 'يجب اختيار دور للمستخدم', type: ToastType.error);
      return;
    }

    // Check duplicate username
    if (_wizardUsers.any((u) => u['username'] == username)) {
      AppToast.show(context, 'اسم المستخدم "$username" مضاف بالفعل', type: ToastType.error);
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
    if (duplicateOf != null) {
      AppToast.show(
        context,
        'كلمةُ المرور هذه مستعملةٌ سلفاً للمستخدم "$duplicateOf". اختر كلمةً '
        'مختلفة — كلمتان متطابقتان تمنعان أحدَ صاحبَيهما من الدخول.',
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

    AppToast.show(context, 'تم إضافة المستخدم "$displayName"', type: ToastType.success);
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
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (r) => false,
      );
    }
  }

  Future<void> _finishSetup() async {
    setState(() => _isSaving = true);
    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final branchRepo = ref.read(branchRepositoryProvider);
      final productRepo = ref.read(productRepositoryProvider);

      // Phase B: mark setup as in-progress so a crash between here and
      // the final `setup_completed=true` leaves a breadcrumb for the
      // resume-on-crash UX.
      await settingsRepo.saveSetting('setup_in_progress', 'true');

      // Phase B: persist the runtime business profile choice so the
      // feature-flag providers load it at boot.
      await settingsRepo.saveSetting(
          'business_profile', _selectedProfile.name);

      // Phase B: seed the developer password. Uses the cached settings
      // repository wrapped around the same DAO the rest of the wizard
      // is writing through.
      try {
        final db = ref.read(databaseProvider);
        final cache = SettingsRepositoryCached(db);
        final devAuth = DeveloperAuthService(cache);
        await devAuth.setPassword(_developerPasswordController.text.trim());
      } catch (e, st) {
        debugPrint('[SetupWizard] developer password save failed: $e\n$st');
      }

      // Save company info
      final companyName = _companyNameController.text.trim();
      if (companyName.isNotEmpty) {
        await settingsRepo.saveSetting('company_name', companyName);
      }
      if (_companyPhoneController.text.trim().isNotEmpty) {
        await settingsRepo.saveSetting(
          'company_phone',
          _companyPhoneController.text.trim(),
        );
      }
      if (_companyAddressController.text.trim().isNotEmpty) {
        await settingsRepo.saveSetting(
          'company_address',
          _companyAddressController.text.trim(),
        );
      }
      await settingsRepo.saveSetting('business_type', _businessType);

      // Save currency
      await ref.read(systemCurrencyProvider.notifier).setCurrency(_currency);

      // Create branch & warehouse.
      // BUG 5a fix: seedInitialData() already inserted a flagged
      // isSystemDefault branch/warehouse before the wizard ever runs
      // (standalone/server mode). Blind-creating here used to mint a
      // second, unflagged row right next to it — branches.name has no
      // UNIQUE constraint, so nothing caught it. Reuse the seeded row
      // instead (rename it if the operator typed something different)
      // and only fall back to createBranch when no seeded row exists —
      // client mode, where seeding is skipped and ClientFirstSyncService
      // reconciles the branch on first sync (R8).
      final branchName = _branchNameController.text.trim();
      int? branchId;
      if (branchName.isNotEmpty) {
        try {
          final existingBranches = await branchRepo.getAllBranches();
          final seededBranch = existingBranches
                  .where((b) => b.isSystemDefault)
                  .firstOrNull ??
              existingBranches
                  .where((b) => b.name.trim() == branchName)
                  .firstOrNull;
          if (seededBranch != null) {
            branchId = seededBranch.id;
            if (seededBranch.name.trim() != branchName) {
              await branchRepo.updateBranch(seededBranch.copyWith(
                name: branchName,
                lastModifiedAt: Value(DateTime.now()),
              ));
            }
          } else {
            branchId = await branchRepo.createBranch(name: branchName);
          }
        } catch (_) {
          final existing = await branchRepo.getAllBranches();
          branchId = existing
              .where((b) => b.name.trim() == branchName)
              .map((b) => b.id)
              .firstOrNull;
        } // May already exist
      }

      final warehouseName = _warehouseNameController.text.trim();
      int? warehouseId;
      if (warehouseName.isNotEmpty && branchId != null) {
        try {
          final existingWarehouses =
              await branchRepo.getWarehousesByBranch(branchId);
          final seededWarehouse = existingWarehouses
                  .where((w) => w.isSystemDefault)
                  .firstOrNull ??
              existingWarehouses
                  .where((w) => w.name.trim() == warehouseName)
                  .firstOrNull;
          if (seededWarehouse != null) {
            warehouseId = seededWarehouse.id;
            if (seededWarehouse.name.trim() != warehouseName) {
              await branchRepo.updateWarehouse(seededWarehouse.copyWith(
                name: warehouseName,
                lastModifiedAt: Value(DateTime.now()),
              ));
            }
          } else {
            warehouseId = await branchRepo.createWarehouseForBranch(
              name: warehouseName,
              branchId: branchId,
              isDefault: true,
            );
          }
        } catch (_) {
          final existing = await branchRepo.getWarehousesByBranch(branchId);
          warehouseId = existing
              .where((w) => w.name.trim() == warehouseName)
              .map((w) => w.id)
              .firstOrNull;
        } // May already exist
      }
      if (branchId != null && warehouseId != null) {
        await settingsRepo.saveSetting(
          'pos_default_warehouse_branch_$branchId',
          warehouseId.toString(),
        );
        await settingsRepo.saveSetting(
          'pos_default_warehouse_id',
          warehouseId.toString(),
        );
      }

      // Create sample products
      for (int i = 0; i < _sampleProducts.length; i++) {
        final p = _sampleProducts[i];
        try {
          final code = 'SETUP-${DateTime.now().millisecondsSinceEpoch}-$i';
          await productRepo.insertProduct(
            ProductsCompanion.insert(
              code: code,
              name: p['name']!,
              salePrice: Value(double.tryParse(p['price'] ?? '0') ?? 0),
              costPrice: Value(double.tryParse(p['cost'] ?? '0') ?? 0),
            ),
          );
        } catch (_) {}
      }

      // Create wizard users
      if (_wizardUsers.isNotEmpty) {
        final authRepo = ref.read(authRepositoryProvider);
        // ⚠️ كان هذا `catch` يكتفي بـ`debugPrint`: فمستخدمٌ يفشل إنشاؤه يسقط
        // من الدفعة **صامتاً** والمشغّلُ يمضي ظانّاً أن الكلَّ أُنشئ — ثم
        // يكتشف الغيابَ يومَ يحاول ذلك الموظّفُ الدخول. والصمتُ هنا ينقض
        // «رسالةً صريحة» في §١ من أصله.
        final failed = <String>[];
        for (final u in _wizardUsers) {
          try {
            await authRepo.createUser(
              username: u['username'] as String,
              password: u['password'] as String,
              displayName: u['displayName'] as String,
              roleId: u['roleId'] as int?,
              forcePasswordChange: true,
            );
          } catch (e) {
            debugPrint('[SetupWizard] Error creating user ${u['username']}: $e');
            failed.add('${u['username']}: $e');
          }
        }
        if (failed.isNotEmpty && mounted) {
          AppToast.show(
            context,
            'تعذّر إنشاءُ ${failed.length} مستخدم:\n${failed.join('\n')}',
            type: ToastType.error,
          );
        }
      }

      // Save tax settings (both global key and POS-specific key)
      await settingsRepo.saveSetting('tax_enabled', _enableTax ? 'true' : 'false');
      await settingsRepo.saveSetting('tax_rate', _taxRate.toString());
      // POS reads tax as decimal (e.g. 0.14 for 14%), so convert percentage → decimal
      final taxDecimal = _enableTax ? (_taxRate / 100.0) : 0.0;
      await settingsRepo.saveSetting('pos_default_tax_rate', taxDecimal.toString());

      // ─── Spec 125 (US1): atomic deployment-mode commit ───────────────
      // Replaces the previous mix of saveSetting('network_mode')+resetToStandalone
      // +setMode+per-mode adhoc blocks. The committer:
      //   • for standalone — calls setMode(standalone) which writes
      //     network_mode AND clears stale network state.
      //   • for client/mirror — skips pair+sync because _connectAndSync /
      //     _pairMirror already ran in earlier wizard steps (committer
      //     gates on isFirstSyncPending). Still calls setMode + starts
      //     heartbeat (mirror) + writes owned settings (standalone/server
      //     flags + last_committed_mode) atomically.
      //   • on any failure — CommitFailed surfaces with an Arabic reason
      //     and the wizard stays on the current step.
      final db = ref.read(databaseProvider);
      final committer = DeploymentModeCommitter(db: db);
      final contract = committer.buildContract(
        target: _networkMode,
        serverPort: int.tryParse(_serverPortController.text) ?? 8080,
        serverHost: NetworkService.instance.serverAddress,
      );
      final commitResult = await committer.commit(contract: contract);
      if (commitResult is CommitFailed) {
        // BUG 5 + BUG 7 + BUG 1 (Spec 125): no partial DB state. Stay on
        // the current step so the user can retry or back out.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(commitResult.reasonAr),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        setState(() => _isSaving = false);
        return;
      }
      // CommitOk — proceed to finalise wizard (setup_completed flag below).


      if (_networkMode == NetworkMode.client && _selectedBranchId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('client_branch_id', _selectedBranchId!);
        final clientWarehouseId =
            await _resolveDefaultWarehouseForBranch(_selectedBranchId!);
        if (clientWarehouseId != null) {
          await settingsRepo.saveSetting(
            'pos_default_warehouse_branch_$_selectedBranchId',
            clientWarehouseId.toString(),
          );
          await settingsRepo.saveSetting(
            'pos_default_warehouse_id',
            clientWarehouseId.toString(),
          );
        }

        // Auto-generate document numbering prefixes based on the selected branch's short code
        Branche? selectedBranch;
        for (final b in _syncedBranches) {
          if (b.id == _selectedBranchId) {
            selectedBranch = b;
            break;
          }
        }

        if (selectedBranch != null && selectedBranch.code != null && selectedBranch.code!.trim().isNotEmpty) {
          final branchCode = selectedBranch.code!.trim();
          await settingsRepo.saveSetting('invoice_code_prefix', '$branchCode-POS');
          await settingsRepo.saveSetting('prefix_sales_pos', '$branchCode-POS');
          await settingsRepo.saveSetting('prefix_sales_manual', '$branchCode-SINV');
          await settingsRepo.saveSetting('prefix_sales_return', '$branchCode-SRET');
          await settingsRepo.saveSetting('prefix_purchase', '$branchCode-PINV');
          await settingsRepo.saveSetting('prefix_purchase_return', '$branchCode-PRET');
          await settingsRepo.saveSetting('prefix_receipt_voucher', '$branchCode-RCPT');
          await settingsRepo.saveSetting('prefix_payment_voucher', '$branchCode-PMT');
          await settingsRepo.saveSetting('prefix_quotation', '$branchCode-QUOT');
        }

        // Spec 001: master-data wipe now happens earlier inside
        // _connectAndSync() via ClientFirstSyncService — see that method
        // for the new contract (wipe-then-pull, gated by
        // client_first_sync_completed). Nothing to do here.
      }

      // Mirror mode finalisation — handled by DeploymentModeCommitter above.
      // The committer guarantees setMode(mirror) + first-sync wipe (if pending)
      // + heartbeat start + atomic settings write. If MirrorState wasn't
      // configured (user skipped _pairMirror), commit() returned CommitFailed
      // and we already early-returned above with an Arabic snackbar.

      // Auto-create fiscal year for the current calendar year — only in
      // standalone/server mode. In client mode the server is the source of
      // truth and its fiscal year already arrived via sync (per Spec 001).
      if (_networkMode != NetworkMode.client) {
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
      }

      // Mark setup as completed and clear the in-progress breadcrumb.
      await settingsRepo.saveSetting('setup_completed', 'true');
      await settingsRepo.saveSetting('setup_in_progress', '');

      // Phase B: audit trail entry so the developer can confirm which
      // profile + mode the install was configured with.
      await AuditLog.record(
        'setup_completed',
        level: AuditLevel.critical,
        payload: {
          'profile': _selectedProfile.name,
          'mode': _networkMode.name,
          'business_type': _businessType,
        },
      );

      // Phase C2 hot-fix: every wizard write went through the regular
      // `settingsRepo` (uncached). The runtime-profile providers, on
      // the other hand, read from `SettingsRepositoryCached` which was
      // warmed at app startup before any of these writes existed.
      //
      // Re-preload the cache with the keys we just wrote AND invalidate
      // the dependent providers so the navigation, feature flags and
      // mode selectors all reflect the new state immediately when the
      // user lands on the main screen — without requiring a restart.
      try {
        final cache = ref.read(settingsRepositoryCachedProvider);
        await cache.preload(<String>[
          'setup_completed',
          'setup_in_progress',
          'business_profile',
          'deployment_mode',
          'developer_password_salt',
          'developer_password_hash',
          'feature_schema_version',
          'runtime_config_hash',
          ...FeatureKey.values.map((k) => k.settingKey),
        ]);
        // Force the notifiers to rebuild from the fresh cache. Without
        // this, `BusinessProfileNotifier.build()`'s initial read still
        // wins and the navigation looks like the compile-time default.
        ref.invalidate(businessProfileProvider);
        ref.invalidate(featureOverridesProvider);
        ref.invalidate(deploymentModeProvider);
      } catch (e, st) {
        debugPrint('[SetupWizard] cache invalidation failed: $e\n$st');
      }

      if (mounted) {
        AppToast.show(
          context,
          'تم إعداد النظام بنجاح! مرحباً بك 🎉',
          type: ToastType.success,
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (r) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الحفظ: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<int?> _resolveDefaultWarehouseForBranch(int branchId) async {
    final branchRepo = ref.read(branchRepositoryProvider);
    final warehouses = await branchRepo.getWarehousesByBranch(branchId);
    if (warehouses.isEmpty) return null;
    return warehouses.where((w) => w.isDefault).map((w) => w.id).firstOrNull ??
        warehouses.first.id;
  }
}
