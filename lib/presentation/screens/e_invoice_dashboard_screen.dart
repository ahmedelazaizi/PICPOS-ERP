import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/e_invoicing_providers.dart';
import '../../services/e_invoicing/e_invoice_service_wrapper.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/permissions/permission_codes.dart';
import '../widgets/permission_guard.dart';


part 'e_invoice_widgets.dart';
part 'e_invoice_config_forms.dart';
// ═══════════════════════════════════════════════════════════════════════════
// E-INVOICE DASHBOARD SCREEN — لوحة تحكم الفوترة الإلكترونية
// ═══════════════════════════════════════════════════════════════════════════

/// هل [permissions] تسمح بإلغاء فاتورة إلكترونية مُرسَلة؟
///
/// مستخرجة كدالة عامة (مش method جوه الـ State الخاصة) عشان تتفحص من
/// غير تركيب شاشة `EInvoiceDashboardScreen` كاملة — إلغاء فاتورة حقيقي
/// يحتاج فاتورة بيع (FK) مزروعة في القاعدة، وده تكلفة إعداد مش لازمة
/// لإثبات إن الحارس شغّال.
bool canCancelEInvoice(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.einvoiceCancel);
}

/// زرار «إعادة إرسال المعلقة» — `einvoice_submit`. مستخرج كدالة top-level
/// مستقلة عن الشاشة كلها عشان يتبنى في اختبار widget خفيف (Task 6a) —
/// تركيب الشاشة كلها بقاعدة بيانات حقيقية علّق الاختبارات.
@visibleForTesting
Widget buildEinvoiceSubmitButton({required VoidCallback onPressed}) {
  return PermissionGuard(
    permission: PermissionCodes.einvoiceSubmit,
    allowManagerOverride: true,
    actionName: tr('إعادة إرسال فواتير إلكترونية معلقة'),
    onGranted: onPressed,
    child: _ActionButton(
      label: tr('إعادة إرسال المعلقة'),
      icon: Icons.refresh,
      onPressed: onPressed,
    ),
  );
}

class EInvoiceDashboardScreen extends ConsumerStatefulWidget {
  const EInvoiceDashboardScreen({super.key});

  @override
  ConsumerState<EInvoiceDashboardScreen> createState() =>
      _EInvoiceDashboardScreenState();
}

class _EInvoiceDashboardScreenState
    extends ConsumerState<EInvoiceDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _filterStatus = 'all';
  String? _filterPlatform;
  bool _showEta = true;
  bool _showJofotara = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadVisibilitySettings();
  }

  Future<void> _loadVisibilitySettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final etaVal = await settingsRepo.getSetting('show_eta_einvoice');
    final joVal = await settingsRepo.getSetting('show_jofotara_einvoice');
    if (mounted) {
      setState(() {
        _showEta = etaVal != 'false';
        _showJofotara = joVal != 'false';
      });
    }
  }

  // ignore: unused_element
  Future<void> _toggleEtaVisibility(bool value) async {
    setState(() => _showEta = value);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.saveSetting('show_eta_einvoice', value.toString());
  }

  // ignore: unused_element
  Future<void> _toggleJofotaraVisibility(bool value) async {
    setState(() => _showJofotara = value);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.saveSetting('show_jofotara_einvoice', value.toString());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final submissions = ref.watch(eInvoiceSubmissionsProvider);
    final stats = ref.watch(eInvoiceStatsProvider(_filterPlatform));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:  Text(tr('الفوترة الإلكترونية')),
          actions: [
            // Platform filter
            PopupMenuButton<String?>(
              icon: const Icon(Icons.filter_list),
              tooltip: tr('فلترة حسب المنصة'),
              onSelected: (v) => setState(() => _filterPlatform = v),
              itemBuilder: (_) => [
                 PopupMenuItem(value: null, child: Text(tr('الكل'))),
                 PopupMenuItem(value: 'eta', child: Text(tr('🇪🇬 ETA مصر'))),
                 PopupMenuItem(
                  value: 'jofotara',
                  child: Text(tr('🇯🇴 JOFOTARA الأردن')),
                ),
              ],
            ),
            // Settings
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: tr('إعدادات الفوترة'),
              onPressed: () => _showConfigDialog(context),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs:  [
              Tab(text: tr('لوحة التحكم'), icon: const Icon(Icons.dashboard)),
              Tab(text: tr('الفواتير'), icon: const Icon(Icons.receipt_long)),
              Tab(text: tr('التحليلات'), icon: const Icon(Icons.analytics)),
              Tab(text: tr('الإعدادات'), icon: const Icon(Icons.tune)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildDashboardTab(stats),
            _buildSubmissionsTab(submissions),
            _buildAnalyticsTab(stats, submissions),
            _buildSettingsTab(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: Dashboard — لوحة التحكم
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDashboardTab(AsyncValue<Map<String, int>> stats) {
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
      data: (data) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status cards
            Row(
              children: [
                _StatCard(
                  title: tr('إجمالي'),
                  value: '${data['total'] ?? 0}',
                  icon: Icons.description,
                  color: Colors.blue,
                ),
                _StatCard(
                  title: tr('مقبولة'),
                  value: '${data['valid'] ?? 0}',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
                _StatCard(
                  title: tr('معلقة'),
                  value: '${data['pending'] ?? 0}',
                  icon: Icons.hourglass_empty,
                  color: Colors.orange,
                ),
                _StatCard(
                  title: tr('مرفوضة'),
                  value: '${data['invalid'] ?? 0}',
                  icon: Icons.cancel,
                  color: AppColors.error,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Connection status
            _buildConnectionStatus(),
            const SizedBox(height: 24),

            // Quick actions
            Text(
              tr('إجراءات سريعة'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                buildEinvoiceSubmitButton(onPressed: _retryPending),
                _ActionButton(
                  label: tr('فحص الحالات'),
                  icon: Icons.sync,
                  onPressed: _pollStatuses,
                ),
                _ActionButton(
                  label: tr('تصدير التقرير'),
                  icon: Icons.picture_as_pdf,
                  onPressed: _exportReport,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final wrapper = ref.read(eInvoiceServiceProvider);
    final isConfigured = wrapper.isConfigured;
    final platform = wrapper.activePlatform;

    return Card(
      child: ListTile(
        leading: Icon(
          isConfigured ? Icons.cloud_done : Icons.cloud_off,
          color: isConfigured ? Colors.green : Colors.grey,
          size: 32,
        ),
        title: Text(
          isConfigured
              ? tr('متصل بـ {p0}', {'p0': platform == EInvoicePlatform.eta ? tr('ETA مصر 🇪🇬') : tr('JOFOTARA الأردن 🇯🇴')})
              : tr('غير متصل — قم بإعداد المنصة'),
        ),
        subtitle: Text(
          isConfigured
              ? tr('الخدمة جاهزة للإرسال')
              : tr('اذهب إلى الإعدادات لتكوين الاتصال'),
        ),
        trailing: isConfigured
            ? ElevatedButton(
                onPressed: _testConnection,
                child:  Text(tr('اختبار')),
              )
            : null,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: Submissions — قائمة الفواتير المرسلة
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSubmissionsTab(
    AsyncValue<List<EInvoiceSubmissionData>> submissions,
  ) {
    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(tr('الكل'), 'all'),
                _buildFilterChip(tr('معلقة'), 'pending'),
                _buildFilterChip(tr('مرسلة'), 'submitted'),
                _buildFilterChip(tr('مقبولة'), 'valid'),
                _buildFilterChip(tr('مرفوضة'), 'invalid'),
                _buildFilterChip(tr('ملغاة'), 'cancelled'),
              ],
            ),
          ),
        ),
        // Submissions list
        Expanded(
          child: submissions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
            data: (items) {
              final filtered = _filterStatus == 'all'
                  ? items
                  : items.where((s) => s.status == _filterStatus).toList();

              if (filtered.isEmpty) {
                return  Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inbox, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        tr('لا توجد فواتير'),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) => _SubmissionTile(
                  submission: filtered[i],
                  onRetry: () => _retrySingle(filtered[i]),
                  onCheckStatus: () => _checkSingleStatus(filtered[i]),
                  onCancel: () => _cancelSingle(filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String status) {
    final isSelected = _filterStatus == status;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _filterStatus = status),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3: Settings — الإعدادات
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ETA Config
        if (_showEta) ...[
          Card(
            child: ExpansionTile(
              leading: const Text('🇪🇬', style: TextStyle(fontSize: 24)),
              title:  Text(tr('منظومة ETA المصرية')),
              subtitle:  Text(tr('الفاتورة الإلكترونية — مصلحة الضرائب')),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _EtaConfigForm(
                    onSave: (config) => _saveConfig('eta', config),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // JOFOTARA Config
        if (_showJofotara) ...[
          Card(
            child: ExpansionTile(
              leading: const Text('🇯🇴', style: TextStyle(fontSize: 24)),
              title:  Text(tr('منظومة JOFOTARA الأردنية')),
              subtitle:  Text(tr('الفوترة الإلكترونية — دائرة ضريبة الدخل')),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _JofotaraConfigForm(
                    onSave: (config) => _saveConfig('jofotara', config),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Tax reference data
        Card(
          child: ListTile(
            leading: const Icon(Icons.data_object),
            title:  Text(tr('بيانات الضرائب المرجعية')),
            subtitle:  Text(tr('أنواع الضرائب والفئات الفرعية')),
            trailing: ElevatedButton.icon(
              icon: const Icon(Icons.sync),
              label:  Text(tr('تحديث')),
              onPressed: _seedTaxTypes,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Product coding
        Card(
          child: ListTile(
            leading: const Icon(Icons.qr_code),
            title:  Text(tr('تكويد المنتجات')),
            subtitle:  Text(tr('توليد أكواد EGS لجميع المنتجات')),
            trailing: ElevatedButton.icon(
              icon: const Icon(Icons.auto_fix_high),
              label:  Text(tr('توليد')),
              onPressed: _bulkGenerateCodes,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIONS — الإجراءات
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    final wrapper = ref.read(eInvoiceServiceProvider);
    final ok = await wrapper.testConnection();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? tr('الاتصال ناجح ✅') : tr('فشل الاتصال ❌')),
        backgroundColor: ok ? Colors.green : AppColors.error,
      ),
    );
  }

  Future<void> _retryPending() async {
    final repo = ref.read(eInvoiceRepositoryProvider);
    final wrapper = ref.read(eInvoiceServiceProvider);
    final pending = await repo.getPendingSubmissions();

    int success = 0, failed = 0;
    for (final sub in pending) {
      try {
        final payload = await repo.buildInvoicePayload(sub.saleId, sub.platform);

        final result = await wrapper.submitInvoice(
          UnifiedInvoice(
            internalId: payload['internalId'] ?? '',
            issueDate: DateTime.now(),
            seller: (payload['seller'] as Map<String, dynamic>?) ?? {},
            items: [],
          ),
        );

        if (result.success) {
          await repo.markSubmissionSuccess(
            submissionId: sub.id,
            submissionUuid: result.submissionId ?? '',
            documentUuid: result.documentUuid,
            qrCode: result.qrCode,
          );
          success++;
        } else {
          await repo.markSubmissionFailed(
            sub.id,
            result.errorMessage ?? tr('فشل غير معروف'),
          );
          failed++;
        }
      } catch (e) {
        await repo.markSubmissionFailed(sub.id, e.toString());
        failed++;
      }
    }

    if (!mounted) return;
    AppToast.show(context, tr('تم: {success} نجحت، {failed} فشلت من {p0}', {'success': success, 'failed': failed, 'p0': pending.length}), type: ToastType.error);
  }

  Future<void> _pollStatuses() async {
    final repo = ref.read(eInvoiceRepositoryProvider);
    final wrapper = ref.read(eInvoiceServiceProvider);
    final submitted = await repo.getSubmissionsByStatus('submitted');

    int updated = 0;
    for (final sub in submitted) {
      if (sub.documentUuid == null) continue;
      try {
        final status = await wrapper.checkStatus(sub.documentUuid!);
        if (status.isValid) {
          await repo.updateSubmissionStatus(sub.id, 'valid');
          updated++;
        } else if (status.isRejected) {
          await repo.updateSubmissionStatus(
            sub.id,
            'invalid',
            errorMessage: status.errors.isNotEmpty
                ? status.errors.first.toString()
                : tr('مرفوضة'),
          );
          updated++;
        }
      } catch (_) {
        // Skip individual errors
      }
    }

    if (!mounted) return;
    AppToast.show(context, tr('تم تحديث {updated} فاتورة من {p0}', {'updated': updated, 'p0': submitted.length}));
  }

  Future<void> _retrySingle(EInvoiceSubmissionData sub) async {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar( SnackBar(content: Text(tr('جاري إعادة الإرسال...'))));
  }

  Future<void> _checkSingleStatus(EInvoiceSubmissionData sub) async {
    if (sub.documentUuid == null) return;
    final wrapper = ref.read(eInvoiceServiceProvider);
    try {
      final status = await wrapper.checkStatus(sub.documentUuid!);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('الحالة: {p0}', {'p0': status.status}))));
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
    }
  }

  Future<void> _cancelSingle(EInvoiceSubmissionData sub) async {
    // فحص صريح جوه الدالة مش ودجت — الزرار اللي بينده عليها جوه
    // `PopupMenuButton` لكل صف، فمفيش نقطة إدخال واحدة تتلف بـ
    // `PermissionGuard` بسهولة. المنطق مستخرج في `canCancelEInvoice`
    // عشان يتفحص من غير ما نركّب الشاشة كلها (تحتاج فاتورة بيع حقيقية
    // كـ FK للسجل).
    final perms = ref.read(currentUserPermissionsProvider).asData?.value ??
        const <String>[];
    if (!canCancelEInvoice(perms)) {
      if (mounted) {
        AppToast.show(context, tr('ليس لديك صلاحية إلغاء الفوترة الإلكترونية'),
            type: ToastType.error);
      }
      return;
    }
    if (sub.documentUuid == null) return;
    final wrapper = ref.read(eInvoiceServiceProvider);
    final ok = await wrapper.cancelDocument(
      sub.documentUuid!,
      tr('إلغاء من المستخدم'),
    );

    if (ok) {
      final repo = ref.read(eInvoiceRepositoryProvider);
      await repo.updateSubmissionStatus(sub.id, 'cancelled');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? tr('تم الإلغاء ✅') : tr('فشل الإلغاء ❌')),
        backgroundColor: ok ? Colors.green : AppColors.error,
      ),
    );
  }

  Future<void> _exportReport() async {
    if (!mounted) return;
    AppToast.show(context, tr('قريبًا: تصدير تقرير الفوترة الإلكترونية'), type: ToastType.info);
  }

  Future<void> _saveConfig(String platform, Map<String, dynamic> config) async {
    final repo = ref.read(eInvoiceRepositoryProvider);
    await repo.saveEInvoiceConfig(
      platform: platform,
      clientId: config['clientId'] as String,
      clientSecret: config['clientSecret'] as String,
      registrationNumber: config['registrationNumber'] as String,
      activityCode: config['activityCode'] as String?,
      isProduction: config['isProduction'] as bool? ?? false,
      isEnabled: true,
    );

    // Re-initialize the service
    await initializeEInvoiceService(ref, platform);

    if (!mounted) return;
    AppToast.show(context, tr('تم حفظ الإعدادات ✅'));
  }

  Future<void> _seedTaxTypes() async {
    final repo = ref.read(eInvoiceRepositoryProvider);
    await repo.seedTaxTypes();

    if (!mounted) return;
    AppToast.show(context, tr('تم تحديث بيانات الضرائب ✅'));
  }

  Future<void> _bulkGenerateCodes() async {
    final repo = ref.read(eInvoiceRepositoryProvider);

    final count = await repo.bulkGenerateEgsCodes();

    if (!mounted) return;
    AppToast.show(context, tr('تم توليد أكواد لـ {count} منتج ✅', {'count': count}));
  }

  void _showConfigDialog(BuildContext context) {
    _tabController.animateTo(3); // Switch to settings tab
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3: Analytics — التحليلات
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAnalyticsTab(
    AsyncValue<Map<String, int>> stats,
    AsyncValue<List<EInvoiceSubmissionData>> submissions,
  ) {
    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
      data: (data) {
        final total = data['total'] ?? 0;
        final valid = data['valid'] ?? 0;
        final pending = data['pending'] ?? 0;
        final invalid = data['invalid'] ?? 0;
        final cancelled = data['cancelled'] ?? 0;
        final successRate = total > 0 ? (valid / total * 100) : 0.0;
        final failRate = total > 0 ? (invalid / total * 100) : 0.0;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Success Rate Card ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pie_chart, color: Colors.blue, size: 22),
                        const SizedBox(width: 8),
                        Text(tr('معدل النجاح'), style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${successRate.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                               Text(tr('معدل القبول'), style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${failRate.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.error,
                                ),
                              ),
                               Text(tr('معدل الرفض'), style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total > 0 ? valid / total : 0,
                        minHeight: 12,
                        backgroundColor: AppColors.error.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation(Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Breakdown by Status ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bar_chart, color: Colors.blue, size: 22),
                        const SizedBox(width: 8),
                        Text(tr('توزيع الحالات'), style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildAnalyticsRow(tr('مقبولة'), valid, total, Colors.green),
                    const SizedBox(height: 8),
                    _buildAnalyticsRow(tr('معلقة'), pending, total, Colors.orange),
                    const SizedBox(height: 8),
                    _buildAnalyticsRow(tr('مرفوضة'), invalid, total, AppColors.error),
                    const SizedBox(height: 8),
                    _buildAnalyticsRow(tr('ملغاة'), cancelled, total, Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Platform Comparison ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.compare_arrows, color: Colors.blue, size: 22),
                        const SizedBox(width: 8),
                        Text(tr('مقارنة المنصات'), style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 16),
                    submissions.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text(tr('خطأ: {e}', {'e': e})),
                      data: (items) {
                        final etaCount = items.where((s) => s.platform == 'eta').length;
                        final jofotaraCount = items.where((s) => s.platform == 'jofotara').length;
                        final etaSuccess = items.where((s) => s.platform == 'eta' && s.status == 'valid').length;
                        final jofotaraSuccess = items.where((s) => s.platform == 'jofotara' && s.status == 'valid').length;

                        return Column(
                          children: [
                            ListTile(
                              leading: const Text('🇪🇬', style: TextStyle(fontSize: 28)),
                              title:  Text(tr('ETA مصر')),
                              subtitle: Text(tr('{etaCount} فاتورة · {etaSuccess} مقبولة', {'etaCount': etaCount, 'etaSuccess': etaSuccess})),
                              trailing: etaCount > 0
                                  ? Chip(
                                      label: Text(
                                        '${(etaSuccess / etaCount * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                      backgroundColor: Colors.green,
                                    )
                                  : const Chip(label: Text('—')),
                            ),
                            const Divider(),
                            ListTile(
                              leading: const Text('🇯🇴', style: TextStyle(fontSize: 28)),
                              title:  Text(tr('JOFOTARA الأردن')),
                              subtitle: Text(tr('{jofotaraCount} فاتورة · {jofotaraSuccess} مقبولة', {'jofotaraCount': jofotaraCount, 'jofotaraSuccess': jofotaraSuccess})),
                              trailing: jofotaraCount > 0
                                  ? Chip(
                                      label: Text(
                                        '${(jofotaraSuccess / jofotaraCount * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                      backgroundColor: Colors.green,
                                    )
                                  : const Chip(label: Text('—')),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Retry Info ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.refresh, color: Colors.blue, size: 22),
                        const SizedBox(width: 8),
                        Text(tr('آلية إعادة المحاولة'), style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                     ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(tr('إعادة المحاولة التلقائية')),
                      subtitle: Text(tr('3 محاولات مع تأخير تصاعدي (2s, 4s, 6s)')),
                    ),
                     ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(tr('إعادة المصادقة التلقائية')),
                      subtitle: Text(tr('تجديد التوكن عند انتهاء الصلاحية (401)')),
                    ),
                     ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(tr('أخطاء الخادم (5xx)')),
                      subtitle: Text(tr('إعادة محاولة تلقائية مع backoff')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnalyticsRow(String label, int count, int total, Color color) {
    final ratio = total > 0 ? count / total : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 18,
              backgroundColor: color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

