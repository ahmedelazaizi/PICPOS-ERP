import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/searchable_dropdown.dart';

/// Full-screen for managing treasury safes — create, edit, toggle active
class SafeManagementScreen extends ConsumerStatefulWidget {
  const SafeManagementScreen({super.key});

  @override
  ConsumerState<SafeManagementScreen> createState() =>
      _SafeManagementScreenState();
}

class _SafeManagementScreenState extends ConsumerState<SafeManagementScreen> {
  final _nameController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  String _selectedType = 'custom';
  int? _selectedCostCenterId;
  int? _selectedBranchId;
  int? _selectedLinkedAccountId;
  List<CostCenter> _costCenters = [];
  List<Branche> _branches = [];
  List<Account> _accounts = [];
  // Payment method mapping
  int? _posCashSafeId;
  int? _posBankSafeId;
  int? _posClickSafeId;
  // Expand/collapse creation form
  bool _showCreateForm = true;
  // Double-submission guards
  bool _savingSafe = false;
  bool _savingMapping = false;

  @override
  void initState() {
    super.initState();
    _loadDropdownData();
  }

  Future<void> _loadDropdownData() async {
    try {
      final accountingRepo = ref.read(accountingRepositoryProvider);
      final branchRepo = ref.read(branchRepositoryProvider);
      final s = ref.read(settingsRepositoryProvider);
      
      final cc = await accountingRepo.getActiveCostCenters();
      final branches = await branchRepo.getActiveBranches();
      final accounts = await accountingRepo.getActiveAccounts();
      final cashSafeId = await s.getSetting('pos_cash_safe_id');
      final bankSafeId = await s.getSetting('pos_bank_safe_id');
      final clickSafeId = await s.getSetting('pos_click_safe_id');
      
      if (mounted) {
        setState(() {
          _costCenters = cc;
          _branches = branches;
          _accounts = accounts;
          _posCashSafeId = int.tryParse(cashSafeId ?? '1');
          _posBankSafeId = int.tryParse(bankSafeId ?? '');
          _posClickSafeId = int.tryParse(clickSafeId ?? '');
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safesAsync = ref.watch(allSafesProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ═══════════════════════════════════════════════
              // HEADER
              // ═══════════════════════════════════════════════
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(PhosphorIconsBold.arrowRight, size: 24),
                    tooltip: tr('رجوع'),
                  ),
                  const SizedBox(width: 8),
                  const Icon(PhosphorIconsBold.vault, size: 28, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Text(
                    tr('إدارة الصناديق والحسابات'),
                    style: GoogleFonts.cairo(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.headlineMedium?.color,
                    ),
                  ),
                  const Spacer(),
                  // Quick stats
                  safesAsync.when(
                    data: (safes) => Row(
                      children: [
                        _statChip(tr('إجمالي'), safes.length, AppColors.primary),
                        const SizedBox(width: 8),
                        _statChip(tr('نقدي'), safes.where((s) => s.safeType == 'cash').length, AppColors.success),
                        const SizedBox(width: 8),
                        _statChip(tr('بنك'), safes.where((s) => s.safeType == 'bank').length, AppColors.info),
                        const SizedBox(width: 8),
                        _statChip(tr('كليك'), safes.where((s) => s.safeType == 'click').length, const Color(0xFF8B5CF6)),
                      ],
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ═══════════════════════════════════════════════
              // BODY — Two-column layout
              // ═══════════════════════════════════════════════
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── LEFT: Create Form + Payment Mapping ───
                    SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildCreateSafeCard(),
                            const SizedBox(height: 16),
                            _buildPaymentMappingCard(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),

                    // ─── RIGHT: Safes List ───
                    Expanded(
                      child: _buildSafesListCard(safesAsync),
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

  // ═══════════════════════════════════════════════════════════════════════
  // STAT CHIP
  // ═══════════════════════════════════════════════════════════════════════

  Widget _statChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 14, color: color)),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.cairo(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CREATE SAFE CARD
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildCreateSafeCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // Card Header
          InkWell(
            onTap: () => setState(() => _showCreateForm = !_showCreateForm),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: _showCreateForm
                    ? const BorderRadius.vertical(top: Radius.circular(16))
                    : BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.plusCircle, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(tr('إنشاء صندوق جديد'),
                      style: GoogleFonts.cairo(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Icon(_showCreateForm ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
                      color: Colors.white, size: 18),
                ],
              ),
            ),
          ),

          // Collapsible form
          if (_showCreateForm)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Name + Type
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: tr('اسم الصندوق'),
                            hintText: tr('مثال: صندوق فودافون كاش'),
                            prefixIcon: const Icon(PhosphorIconsBold.textAa),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedType,
                          decoration: InputDecoration(
                            labelText: tr('النوع'),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items:  [
                            DropdownMenuItem(value: 'cash', child: Text(tr('نقدي'))),
                            DropdownMenuItem(value: 'bank', child: Text(tr('بنك'))),
                            DropdownMenuItem(value: 'click', child: Text(tr('تحويل كليك'))),
                            DropdownMenuItem(value: 'custom', child: Text(tr('مخصص'))),
                          ],
                          onChanged: (v) => setState(() => _selectedType = v ?? 'custom'),
                        ),
                      ),
                    ],
                  ),

                  // Bank fields
                  if (_selectedType == 'bank') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bankNameController,
                            decoration: InputDecoration(
                              labelText: tr('اسم البنك'),
                              hintText: tr('مثال: البنك الأهلي'),
                              prefixIcon: const Icon(PhosphorIconsBold.bank, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _accountNumberController,
                            decoration: InputDecoration(
                              labelText: tr('رقم الحساب البنكي'),
                              hintText: tr('مثال: 1234567890'),
                              prefixIcon: const Icon(PhosphorIconsBold.hash, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Cost Center / Branch / Linked Account
                  const SizedBox(height: 12),
                  if (_costCenters.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SearchableDropdown<CostCenter>(
                        items: _costCenters,
                        value: _costCenters.where((cc) => cc.id == _selectedCostCenterId).firstOrNull,
                        label: tr('مركز التكلفة'),
                        hint: tr('بدون'),
                        searchHint: tr('بحث في مراكز التكلفة...'),
                        showClearButton: true,
                        labelBuilder: (cc) => cc.name,
                        onChanged: (cc) => setState(() => _selectedCostCenterId = cc?.id),
                      ),
                    ),
                  if (_branches.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SearchableDropdown<Branche>(
                        items: _branches,
                        value: _branches.where((b) => b.id == _selectedBranchId).firstOrNull,
                        label: tr('الفرع'),
                        hint: tr('بدون'),
                        searchHint: tr('بحث في الفروع...'),
                        showClearButton: true,
                        labelBuilder: (b) => b.name,
                        onChanged: (b) => setState(() => _selectedBranchId = b?.id),
                      ),
                    ),
                  if (_accounts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SearchableDropdown<Account>(
                        items: _accounts,
                        value: _accounts.where((a) => a.id == _selectedLinkedAccountId).firstOrNull,
                        label: tr('الحساب المرتبط'),
                        hint: tr('بدون'),
                        searchHint: tr('بحث بالاسم أو الرمز...'),
                        showClearButton: true,
                        labelBuilder: (a) => '${a.code} - ${a.name}',
                        secondarySearchBuilder: (a) => a.code,
                        onChanged: (a) => setState(() => _selectedLinkedAccountId = a?.id),
                      ),
                    ),

                  // Create button
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _savingSafe ? null : _createSafe,
                      icon: _savingSafe
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(PhosphorIconsBold.plus),
                      label:  Text(tr('إنشاء الصندوق')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PAYMENT MAPPING CARD
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPaymentMappingCard() {
    final safesAsync = ref.watch(allSafesProvider);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsBold.bank, color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('ربط طرق التحصيل بالخزائن'),
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                TextButton.icon(
                  onPressed: _savingMapping ? null : _savePaymentMapping,
                  icon: _savingMapping
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(PhosphorIconsBold.floppyDisk, size: 16),
                  label:  Text(tr('حفظ الربط')),
                  style: TextButton.styleFrom(foregroundColor: AppColors.success),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(tr('تحديد الخزينة التي يتم توجيه كل طريقة دفع إليها تلقائياً'),
                style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
            const Divider(height: 16),
            safesAsync.when(
              data: (safes) {
                final cashSafes = safes.where((s) => s.safeType == 'cash').toList();
                final bankSafes = safes.where((s) => s.safeType == 'bank').toList();

                return Column(
                  children: [
                    SearchableDropdown<SafeData>(
                      items: cashSafes,
                      value: cashSafes.where((s) => s.id == _posCashSafeId).firstOrNull,
                      label: tr('خزينة النقدية (Cash)'),
                      hint: tr('اختر صندوق...'),
                      searchHint: tr('بحث في الصناديق...'),
                      labelBuilder: (s) => '${s.name} (${s.balance.toStringAsFixed(AppConstants.decimalPlaces)})',
                      onChanged: (s) => setState(() => _posCashSafeId = s?.id),
                    ),
                    const SizedBox(height: 10),
                    SearchableDropdown<SafeData>(
                      items: bankSafes,
                      value: bankSafes.where((s) => s.id == _posBankSafeId).firstOrNull,
                      label: tr('خزينة الفيزا/البنك (Visa/Bank)'),
                      hint: tr('استخدام الخيار الافتراضي'),
                      searchHint: tr('بحث في الصناديق...'),
                      showClearButton: true,
                      labelBuilder: (s) => '${s.name} (${s.balance.toStringAsFixed(AppConstants.decimalPlaces)})',
                      onChanged: (s) => setState(() => _posBankSafeId = s?.id),
                    ),
                    const SizedBox(height: 10),
                    SearchableDropdown<SafeData>(
                      items: safes,
                      value: safes.where((s) => s.id == _posClickSafeId).firstOrNull,
                      label: tr('خزينة كليك (Click)'),
                      hint: tr('استخدام الخيار الافتراضي'),
                      searchHint: tr('بحث في الصناديق...'),
                      showClearButton: true,
                      labelBuilder: (s) => '${s.name} (${s.balance.toStringAsFixed(AppConstants.decimalPlaces)})',
                      onChanged: (s) => setState(() => _posClickSafeId = s?.id),
                    ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, _) =>  Text(tr('فشل تحميل الخزائن')),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SAFES LIST CARD
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSafesListCard(AsyncValue<List<SafeData>> safesAsync) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // List header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: context.picposField,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.listBullets, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(tr('الصناديق الحالية'),
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                safesAsync.when(
                  data: (safes) => Text(tr('{p0} صندوق', {'p0': safes.length}),
                      style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // List body
          Expanded(
            child: safesAsync.when(
              data: (safes) {
                if (safes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.vault, size: 48, color: AppColors.textMuted.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(tr('لا توجد صناديق بعد'),
                            style: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(tr('قم بإنشاء صندوق جديد من النموذج على اليمين'),
                            style: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: safes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final safe = safes[index];
                    final typeColor = _colorForType(safe.safeType);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: typeColor.withValues(alpha: 0.1),
                        child: Icon(_iconForType(safe.safeType), color: typeColor, size: 22),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              safe.name,
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                decoration: safe.isActive ? null : TextDecoration.lineThrough,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (safe.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(tr('افتراضي'),
                                  style: GoogleFonts.cairo(
                                      color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          if (!safe.isActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.textMuted.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(tr('معطّل'),
                                  style: GoogleFonts.cairo(
                                      color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        _buildSafeSubtitle(safe),
                        style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(PhosphorIconsBold.dotsThreeVertical, size: 20),
                        onSelected: (action) => _handleSafeAction(safe, action),
                        itemBuilder: (_) => [
                           PopupMenuItem(
                            value: 'edit',
                            child: Row(children: [
                              const Icon(PhosphorIconsBold.pencilSimple, size: 16, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text(tr('تعديل')),
                            ]),
                          ),
                          if (!safe.isDefault)
                             PopupMenuItem(
                              value: 'set_default',
                              child: Row(children: [
                                const Icon(PhosphorIconsBold.star, size: 16, color: AppColors.warning),
                                const SizedBox(width: 8),
                                Text(tr('تعيين كافتراضي')),
                              ]),
                            ),
                          PopupMenuItem(
                            value: 'toggle_active',
                            child: Row(children: [
                              Icon(
                                safe.isActive ? PhosphorIconsBold.eyeSlash : PhosphorIconsBold.eye,
                                size: 16,
                                color: safe.isActive ? AppColors.textMuted : AppColors.success,
                              ),
                              const SizedBox(width: 8),
                              Text(safe.isActive ? tr('إلغاء التفعيل') : tr('تفعيل')),
                            ]),
                          ),
                          if (!safe.isDefault)
                             PopupMenuItem(
                              value: 'delete',
                              child: Row(children: [
                                const Icon(PhosphorIconsBold.trash, size: 16, color: AppColors.error),
                                const SizedBox(width: 8),
                                Text(tr('حذف'), style: const TextStyle(color: AppColors.error)),
                              ]),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  Color _colorForType(String type) {
    switch (type) {
      case 'cash': return AppColors.success;
      case 'click': return const Color(0xFF8B5CF6);
      case 'bank': return AppColors.info;
      default: return const Color(0xFFEA580C);
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'cash': return PhosphorIconsBold.money;
      case 'click': return PhosphorIconsBold.cellSignalFull;
      case 'bank': return PhosphorIconsBold.bank;
      default: return PhosphorIconsBold.vault;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'cash': return tr('نقدي');
      case 'click': return tr('تحويل كليك');
      case 'bank': return tr('بنك');
      default: return 'مخصص';
    }
  }

  String _buildSafeSubtitle(SafeData safe) {
    final parts = <String>[_labelForType(safe.safeType)];
    if (safe.safeType == 'bank') {
      if (safe.bankName != null && safe.bankName!.isNotEmpty) parts.add(safe.bankName!);
      if (safe.accountNumber != null && safe.accountNumber!.isNotEmpty) parts.add(tr('حساب: {p0}', {'p0': safe.accountNumber}));
    }
    parts.add(tr('الرصيد: {p0}', {'p0': safe.balance.toStringAsFixed(AppConstants.decimalPlaces)}));
    return parts.join(' • ');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CRUD OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _createSafe() async {
    if (_savingSafe) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, tr('أدخل اسم الصندوق'));
      return;
    }
    setState(() => _savingSafe = true);
    try {
      final repo = ref.read(treasuryRepositoryProvider);
      final bankName = _selectedType == 'bank' ? _bankNameController.text.trim() : null;
      final accountNumber = _selectedType == 'bank' ? _accountNumberController.text.trim() : null;
      await repo.createSafe(
        name: name,
        safeType: _selectedType,
        bankName: bankName,
        accountNumber: accountNumber,
        costCenterId: _selectedCostCenterId,
        branchId: _selectedBranchId,
        linkedAccountId: _selectedLinkedAccountId,
      );
      _nameController.clear();
      _bankNameController.clear();
      _accountNumberController.clear();
      setState(() {
        _selectedCostCenterId = null;
        _selectedBranchId = null;
        _selectedLinkedAccountId = null;
      });
      if (mounted) AppToast.show(context, tr('تم إنشاء الصندوق "{name}" بنجاح', {'name': name}), type: ToastType.success);
      ref.invalidate(allSafesProvider);
    } catch (e) {
      if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}));
    } finally {
      if (mounted) setState(() => _savingSafe = false);
    }
  }

  Future<void> _handleSafeAction(SafeData safe, String action) async {
    switch (action) {
      case 'edit':
        _showEditSafeDialog(safe);
      case 'set_default':
        _setDefaultSafe(safe.id);
      case 'toggle_active':
        _toggleSafe(safe.id, !safe.isActive);
      case 'delete':
        _deleteSafe(safe);
    }
  }

  void _showEditSafeDialog(SafeData safe) {
    final nameCtrl = TextEditingController(text: safe.name);
    final bankCtrl = TextEditingController(text: safe.bankName ?? '');
    final acctCtrl = TextEditingController(text: safe.accountNumber ?? '');
    int? editCostCenterId = safe.costCenterId;
    int? editBranchId = safe.branchId;
    int? editLinkedAccountId = safe.linkedAccountId;
    bool savingEdit = false;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx2, setDialogState) => AlertDialog(
            title:  Row(children: [
              const Icon(PhosphorIconsBold.pencilSimple, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('تعديل الصندوق')),
            ]),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: tr('اسم الصندوق'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    if (safe.safeType == 'bank') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: bankCtrl,
                        decoration: InputDecoration(
                          labelText: tr('اسم البنك'),
                          prefixIcon: const Icon(PhosphorIconsBold.bank, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: acctCtrl,
                        decoration: InputDecoration(
                          labelText: tr('رقم الحساب البنكي'),
                          prefixIcon: const Icon(PhosphorIconsBold.hash, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                    if (_costCenters.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SearchableDropdown<CostCenter>(
                        items: _costCenters,
                        value: _costCenters.where((cc) => cc.id == editCostCenterId).firstOrNull,
                        label: tr('مركز التكلفة'),
                        hint: tr('بدون'),
                        searchHint: tr('بحث في مراكز التكلفة...'),
                        showClearButton: true,
                        labelBuilder: (cc) => cc.name,
                        onChanged: (cc) => setDialogState(() => editCostCenterId = cc?.id),
                      ),
                    ],
                    if (_branches.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SearchableDropdown<Branche>(
                        items: _branches,
                        value: _branches.where((b) => b.id == editBranchId).firstOrNull,
                        label: tr('الفرع'),
                        hint: tr('بدون'),
                        searchHint: tr('بحث في الفروع...'),
                        showClearButton: true,
                        labelBuilder: (b) => b.name,
                        onChanged: (b) => setDialogState(() => editBranchId = b?.id),
                      ),
                    ],
                    if (_accounts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SearchableDropdown<Account>(
                        items: _accounts,
                        value: _accounts.where((a) => a.id == editLinkedAccountId).firstOrNull,
                        label: tr('الحساب المرتبط'),
                        hint: tr('بدون'),
                        searchHint: tr('بحث في الحسابات...'),
                        showClearButton: true,
                        labelBuilder: (a) => a.name,
                        onChanged: (a) => setDialogState(() => editLinkedAccountId = a?.id),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
              ElevatedButton(
                onPressed: savingEdit
                    ? null
                    : () async {
                        setDialogState(() => savingEdit = true);
                        try {
                          final repo = ref.read(treasuryRepositoryProvider);
                          final bankName = safe.safeType == 'bank' ? bankCtrl.text.trim() : null;
                          final accountNumber = safe.safeType == 'bank' ? acctCtrl.text.trim() : null;
                          await repo.updateSafeDetails(
                            safeId: safe.id,
                            name: nameCtrl.text.trim(),
                            bankName: bankName,
                            accountNumber: accountNumber,
                            costCenterId: editCostCenterId,
                            branchId: editBranchId,
                            linkedAccountId: editLinkedAccountId,
                          );
                          ref.invalidate(allSafesProvider);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) AppToast.show(context, tr('تم تحديث الصندوق بنجاح'));
                        } catch (e) {
                          if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}));
                          if (ctx.mounted) setDialogState(() => savingEdit = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: savingEdit
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    :  Text(tr('حفظ')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setDefaultSafe(int safeId) async {
    try {
      final repo = ref.read(treasuryRepositoryProvider);
      await repo.setDefaultSafe(safeId);
      ref.invalidate(allSafesProvider);
      if (mounted) AppToast.show(context, tr('تم تعيين الصندوق الافتراضي'));
    } catch (e) {
      if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}));
    }
  }

  Future<void> _toggleSafe(int safeId, bool isActive) async {
    try {
      final repo = ref.read(treasuryRepositoryProvider);
      await repo.toggleSafeActive(safeId, isActive);
      ref.invalidate(allSafesProvider);
    } catch (e) {
      if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}));
    }
  }

  Future<void> _deleteSafe(SafeData safe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(children: [
            const Icon(PhosphorIconsBold.warning, color: AppColors.error),
            const SizedBox(width: 8),
            Text(tr('تأكيد الحذف')),
          ]),
          content: Text(tr('هل تريد حذف الصندوق "{p0}" نهائياً؟\nلن يتم حذف الصندوق إذا كان مرتبطاً بعمليات.', {'p0': safe.name})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child:  Text(tr('إلغاء'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        final repo = ref.read(treasuryRepositoryProvider);
        await repo.deleteSafeById(safe.id);
        ref.invalidate(allSafesProvider);
        if (mounted) AppToast.show(context, tr('تم حذف الصندوق'));
      } catch (e) {
        if (mounted) AppToast.show(context, tr('لا يمكن حذف الصندوق — مرتبط بعمليات'));
      }
    }
  }

  Future<void> _savePaymentMapping() async {
    if (_savingMapping) return;
    setState(() => _savingMapping = true);
    try {
      final s = ref.read(settingsRepositoryProvider);
      await s.saveSetting('pos_cash_safe_id', _posCashSafeId?.toString() ?? '1');
      await s.saveSetting('pos_bank_safe_id', _posBankSafeId?.toString() ?? '');
      await s.saveSetting('pos_click_safe_id', _posClickSafeId?.toString() ?? '');
      ref.invalidate(posCashSafeIdProvider);
      ref.invalidate(posBankSafeIdProvider);
      ref.invalidate(posClickSafeIdProvider);
      if (mounted) AppToast.show(context, tr('تم حفظ ربط طرق التحصيل بنجاح'), type: ToastType.success);
    } catch (e) {
      if (mounted) AppToast.show(context, tr('خطأ في الحفظ: {e}', {'e': e}));
    } finally {
      if (mounted) setState(() => _savingMapping = false);
    }
  }
}

/// Legacy alias — kept for backward compat, redirects to the new screen.
/// Use SafeManagementScreen directly for new code.
@Deprecated('Use SafeManagementScreen instead')
typedef SafeManagementDialog = SafeManagementScreen;
