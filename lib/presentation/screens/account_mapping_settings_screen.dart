import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import '../picpos_shell/picpos_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../core/utils/arabic_utils.dart';
import '../../core/widgets/app_toast.dart';
import '../../services/network_service.dart';

/// Account Mapping Settings — Multi-account per purpose with per-row cost center
class AccountMappingSettingsScreen extends ConsumerStatefulWidget {
  const AccountMappingSettingsScreen({super.key});

  @override
  ConsumerState<AccountMappingSettingsScreen> createState() =>
      _AccountMappingSettingsScreenState();
}

class _AccountMappingSettingsScreenState
    extends ConsumerState<AccountMappingSettingsScreen> {
  List<Account> _allAccounts = [];
  List<CostCenter> _costCenters = [];
  List<AccountMapping> _allMappings = [];
  bool _isLoading = true;

  /// Client mode = read-only (account mappings must be set on the server)
  bool get _isClientMode => NetworkService.instance.isClient;

  /// Grouped purpose definitions — 6 groups, all 47 system purposes
  static List<_PurposeGroup> get _purposeGroups => <_PurposeGroup>[
    // ── المجموعة 1: النقدية والذمم ──────────────────────────────────────────
    _PurposeGroup(
      title: tr('النقدية والذمم المدينة'),
      icon: PhosphorIconsBold.bank,
      color: const Color(0xFF2563EB),
      items: [
        _PurposeItem('cash',                tr('الصندوق الرئيسي'),              '1111', tr('حساب النقد الافتراضي للمبيعات والمصروفات النقدية')),
        _PurposeItem('petty_cash',          tr('صندوق العهدة'),                 '1112', tr('صندوق النقد الصغير والعهد')),
        _PurposeItem('bank',                tr('البنك الرئيسي'),                '1113', tr('حساب البنك للمدفوعات بالبطاقات والتحويلات')),
        _PurposeItem('bank2',               tr('البنك الثاني'),                 '1114', tr('حساب البنك الاحتياطي الثاني')),
        _PurposeItem('click',               tr('حساب Click / إلكتروني'),        '1116', tr('حساب المدفوعات الإلكترونية (Click/KNET)')),
        _PurposeItem('receivables',         tr('ذمم العملاء المحليون'),         '1121', tr('حساب الذمم المدينة للعملاء المحليين')),
        _PurposeItem('foreign_receivables', tr('ذمم العملاء الخارجيون'),        '1122', tr('حساب الذمم المدينة للعملاء الخارجيين')),
        _PurposeItem('notes_receivable',    tr('أوراق القبض'),                  '1123', tr('حساب الشيكات وأوراق القبض من العملاء')),
      ],
    ),
    // ── المجموعة 2: المخزون والأصول المتداولة ───────────────────────────────
    _PurposeGroup(
      title: tr('المخزون والأصول المتداولة'),
      icon: PhosphorIconsBold.package,
      color: const Color(0xFF7C3AED),
      items: [
        _PurposeItem('inventory',           tr('مخزون البضاعة للبيع'),          '1136', tr('الحساب الرئيسي لمخزون بضاعة التجارة')),
        _PurposeItem('raw_materials',       tr('مخزون المواد الخام'),           '1131', tr('مخزون المواد الخام للإنتاج')),
        _PurposeItem('wip',                 tr('مخزون تحت التشغيل'),            '1133', tr('منتجات تحت الإنتاج (WIP)')),
        _PurposeItem('applied_overhead',    tr('تحميل صناعي مطبّق'),            '5138', tr('الطرف الدائن لتحميل التكاليف غير المباشرة على أوامر التصنيع')),
        _PurposeItem('goods_in_transit',    tr('بضاعة تامة / عبور'),            '1134', tr('المنتجات النهائية والبضاعة في الطريق')),
        _PurposeItem('input_vat',           tr('ضريبة القيمة المضافة مدفوعة'), '1141', tr('ضريبة القيمة المضافة على المشتريات')),
        _PurposeItem('prepaid_expenses',    tr('مصروفات مقدمة'),                '1143', tr('المصروفات المدفوعة مسبقاً')),
        _PurposeItem('employee_advances',   tr('سلف الموظفين'),                 '1146', tr('السلف المدفوعة للموظفين')),
        _PurposeItem('fixed_assets',        tr('الأصول الثابتة'),               '1211', tr('حساب الأصول الثابتة والمعدات')),
      ],
    ),
    // ── المجموعة 3: الخصوم والالتزامات ──────────────────────────────────────
    _PurposeGroup(
      title: tr('الخصوم والالتزامات'),
      icon: PhosphorIconsBold.handCoins,
      color: const Color(0xFFDC2626),
      items: [
        _PurposeItem('payables',            tr('ذمم الموردون المحليون'),         '2111', tr('حساب الذمم الدائنة للموردين المحليين')),
        _PurposeItem('foreign_payables',    tr('ذمم الموردون الخارجيون'),        '2112', tr('حساب الذمم الدائنة للموردين الخارجيين')),
        _PurposeItem('notes_payable',       tr('أوراق الدفع'),                  '2113', tr('الشيكات وأوراق الدفع للموردين')),
        _PurposeItem('output_vat',          tr('ضريبة القيمة المضافة محصلة'),   '2121', tr('ضريبة القيمة المضافة على المبيعات')),
        _PurposeItem('income_tax',          tr('ضريبة الدخل'),                  '2122', tr('ضريبة الدخل المستحقة')),
        _PurposeItem('accrued_salaries',    tr('رواتب مستحقة'),                 '2131', tr('الرواتب المستحقة غير المدفوعة')),
        _PurposeItem('deferred_revenue',    tr('إيرادات مقدمة / مؤجلة'),        '2133', tr('الإيرادات المحصلة قبل التسليم (IFRS 15)')),
        _PurposeItem('loans_payable',       tr('قروض بنكية'),                   '2141', tr('القروض البنكية وطويلة الأجل')),
      ],
    ),
    // ── المجموعة 4: الإيرادات ────────────────────────────────────────────────
    _PurposeGroup(
      title: tr('الإيرادات'),
      icon: PhosphorIconsBold.trendUp,
      color: const Color(0xFF059669),
      items: [
        _PurposeItem('sales',               tr('مبيعات محلية'),                 '4121', tr('حساب إيرادات المبيعات المحلية الرئيسي')),
        _PurposeItem('export_sales',        tr('مبيعات تصدير'),                 '4122', tr('حساب إيرادات مبيعات التصدير')),
        _PurposeItem('delivery_revenue',    tr('إيرادات التوصيل'),              '414',  tr('حساب إيرادات خدمات التوصيل')),
        _PurposeItem('service_revenue',     tr('إيرادات الخدمات'),              '4131', tr('حساب إيرادات الخدمات ما بعد البيع')),
        _PurposeItem('sales_return',        tr('مردودات المبيعات'),             '4211', tr('حساب مردودات وإرجاع المبيعات')),
        _PurposeItem('sales_discount',      tr('خصم المبيعات الممنوح'),         '4212', tr('خصومات الفاتورة الممنوحة للعملاء')),
        _PurposeItem('purchase_discount',   tr('خصم المشتريات المكتسب'),        '4316', tr('الخصم المحصل من الموردين عند الدفع المبكر')),
        _PurposeItem('discount_received',   tr('خصم مكتسب (تسوية)'),            '4316', tr('خصم التسوية المكتسب عند استيفاء الديون')),
        _PurposeItem('other_income',        tr('إيرادات متنوعة'),               '4315', tr('الإيرادات غير التشغيلية والمتنوعة')),
        _PurposeItem('inventory_surplus',   tr('فائض مخزون'),                   '4317', tr('إيراد فائض الجرد عند زيادة المخزون الفعلي')),
        _PurposeItem('cash_surplus',        tr('فائض نقدي'),                    '4318', tr('إيراد فائض الصندوق عند إغلاق الوردية')),
      ],
    ),
    // ── المجموعة 5: تكلفة البضاعة ───────────────────────────────────────────
    _PurposeGroup(
      title: tr('تكلفة البضاعة المباعة'),
      icon: PhosphorIconsBold.shoppingCartSimple,
      color: const Color(0xFFB45309),
      items: [
        _PurposeItem('cogs',                tr('تكلفة البضاعة المباعة'),        '5211', tr('حساب تكلفة المبيعات (COGS) الرئيسي')),
        _PurposeItem('purchases',           tr('مشتريات'),                      '5211', tr('حساب المشتريات الرئيسي')),
        _PurposeItem('purchase_return',     tr('مردودات مشتريات'),              '5214', tr('حساب مردودات وإرجاع المشتريات')),
      ],
    ),
    // ── المجموعة 6: المصروفات التشغيلية ─────────────────────────────────────
    _PurposeGroup(
      title: tr('المصروفات التشغيلية'),
      icon: PhosphorIconsBold.trendDown,
      color: const Color(0xFFF59E0B),
      items: [
        _PurposeItem('salary_expense',      tr('رواتب — إدارة'),                '621',  tr('حساب مصروفات الرواتب والأجور الإدارية')),
        _PurposeItem('rent_expense',        tr('مصروف إيجار'),                  '623',  tr('حساب مصروفات الإيجار')),
        _PurposeItem('discount_allowed',    tr('خصم مسموح للعملاء'),            '6215', tr('خصم التسوية الممنوح عند استيفاء الديون')),
        _PurposeItem('inventory_shrinkage', tr('عجز مخزون'),                    '6216', tr('مصروف النقص والتلف في المخزون')),
        _PurposeItem('cash_shortage',       tr('عجز نقدي'),                     '6217', tr('مصروف العجز النقدي عند إغلاق الوردية')),
        _PurposeItem('misc_expense',        tr('مصروفات متنوعة'),               '6214', tr('حساب المصروفات العامة والمتنوعة')),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final accountingRepo = ref.read(accountingRepositoryProvider);
      final accounts = await accountingRepo.getAllAccounts();
      final costCenters = await accountingRepo.getActiveCostCenters();
      final mappings = await accountingRepo.getAllAccountMappings();

      if (mounted) {
        setState(() {
          _allAccounts = accounts;
          _costCenters = costCenters;
          _allMappings = mappings;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      debugPrint('[ACCOUNT_MAPPING] Error loading data: $e\n$s');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(tr('استعادة الربط الافتراضي'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(
            tr('سيتم حذف جميع الربط المحاسبي الحالي واستعادة الربط الافتراضي من دليل الحسابات. هل تريد المتابعة؟'),
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'), style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text(tr('استعادة'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final accountingRepo = ref.read(accountingRepositoryProvider);
      await accountingRepo.resetToDefaultMappings();
      await _loadData();
      if (mounted) AppToast.show(context, tr('تم استعادة الربط المحاسبي الافتراضي بنجاح'));
    } catch (e) {
      if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.picposField,
        body: Column(
          children: [
            _buildHeader(),
            if (_isClientMode)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.warning, color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr('وضع القراءة فقط — الربط المحاسبي يتم مركزيًا على السيرفر. لتعديل الربط، استخدم جهاز السيرفر.'),
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _purposeGroups.map((group) => _buildGroup(group)).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(PhosphorIconsBold.linkSimple, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('ربط الحسابات'), style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                Text(tr('تخصيص الحسابات المستخدمة في القيود التلقائية'), style: GoogleFonts.cairo(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Show cost center count
          if (_costCenters.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr('🏢 {p0} مراكز تكلفة', {'p0': _costCenters.length}),
                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _loadData,
            icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 16, color: Colors.white),
            label: Text(tr('تحديث'), style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (!_isClientMode) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _resetToDefaults,
              icon: const Icon(PhosphorIconsBold.arrowCounterClockwise, size: 16, color: Colors.white),
              label: Text(tr('استعادة الافتراضي'), style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.orange.withValues(alpha: 0.8)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroup(_PurposeGroup group) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: group.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Group Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: group.color.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(group.icon, color: group.color, size: 20),
                const SizedBox(width: 10),
                Text(
                  group.title,
                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700, color: group.color),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Items
          ...group.items.map((item) => _buildPurposeSection(item, group.color)),
        ],
      ),
    );
  }

  /// Build a section for a single purpose showing ALL its mappings
  Widget _buildPurposeSection(_PurposeItem item, Color color) {
    // Get all mappings for this purpose
    final purposeMappings = _allMappings.where((m) => m.purpose == item.purpose).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.picposHairline.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Purpose label + add button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      item.description,
                      style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              // Add mapping button (disabled in client mode)
              if (!_isClientMode)
                TextButton.icon(
                  onPressed: () => _showAddMappingDialog(item, color),
                  icon: const Icon(PhosphorIconsBold.plus, size: 14),
                  label: Text(tr('إضافة ربط'), style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Mapping entries
          if (purposeMappings.isEmpty)
            _buildDefaultIndicator(item, color)
          else
            ...purposeMappings.map((mapping) => _buildMappingEntry(mapping, item, color)),
        ],
      ),
    );
  }

  /// Show the default (fallback) account when no explicit mappings exist
  Widget _buildDefaultIndicator(_PurposeItem item, Color color) {
    final defaultAccount = _allAccounts.where((a) => a.code == item.defaultCode).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.globe, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(tr('افتراضي'), style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.defaultCode,
              style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            defaultAccount?.name ?? item.label,
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  /// Build a single mapping entry (account + cost center + actions)
  Widget _buildMappingEntry(AccountMapping mapping, _PurposeItem item, Color color) {
    final account = _allAccounts.where((a) => a.id == mapping.accountId).firstOrNull;
    final costCenter = mapping.costCenterId != null
        ? _costCenters.where((cc) => cc.id == mapping.costCenterId).firstOrNull
        : null;
    final isGlobal = mapping.costCenterId == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isGlobal ? color.withValues(alpha: 0.04) : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Cost center indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isGlobal ? Colors.blue.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isGlobal ? PhosphorIconsBold.globe : PhosphorIconsBold.buildings,
                  size: 12,
                  color: isGlobal ? Colors.blue : Colors.orange[700],
                ),
                const SizedBox(width: 4),
                Text(
                  isGlobal ? tr('عالمي') : costCenter?.name ?? tr('؟'),
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isGlobal ? Colors.blue : Colors.orange[700],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Account code
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              account?.code ?? '?',
              style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
          const SizedBox(width: 8),
          // Account name
          Expanded(
            child: Text(
              account == null ? tr('حساب غير موجود') : trData(account.name),
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Edit button (disabled in client mode)
          if (!_isClientMode)
            IconButton(
              icon: Icon(PhosphorIconsBold.pencilSimple, size: 14, color: color),
              onPressed: () => _showEditMappingDialog(mapping, item, color),
              tooltip: tr('تعديل'),
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          // Delete button (disabled in client mode)
          if (!_isClientMode)
            IconButton(
              icon: const Icon(PhosphorIconsBold.trash, size: 14, color: AppColors.error),
              onPressed: () => _deleteMappingEntry(mapping, item),
              tooltip: tr('حذف'),
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  /// Dialog to add a new mapping for a purpose
  void _showAddMappingDialog(_PurposeItem item, Color color) {
    final searchCtrl = TextEditingController();
    int? selectedCostCenterId;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          final query = ArabicUtils.normalize(searchCtrl.text.toLowerCase());
          final filtered = query.isEmpty
              ? _allAccounts
              : _allAccounts.where((a) =>
                  ArabicUtils.normalize(a.name.toLowerCase()).contains(query) ||
                  a.code.contains(query)).toList();

          return AlertDialog(
            title: Row(
              children: [
                Icon(PhosphorIconsBold.link, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('إضافة ربط: {p0}', {'p0': item.label}), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 450,
              child: Column(
                children: [
                  // Cost center selector
                  Row(
                    children: [
                      const Icon(PhosphorIconsBold.buildings, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Text(tr('مركز التكلفة:'), style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: selectedCostCenterId,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          items: [
                            DropdownMenuItem<int?>(value: null, child: Text(tr('🌐 عالمي (افتراضي)'), style: GoogleFonts.cairo(fontSize: 12))),
                            ..._costCenters.map((cc) => DropdownMenuItem<int?>(
                                  value: cc.id,
                                  child: Text('🏢 ${trData(cc.name)}', style: GoogleFonts.cairo(fontSize: 12)),
                                )),
                          ],
                          onChanged: (v) => setDialogState(() => selectedCostCenterId = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Account search
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: tr('بحث بالرمز أو الاسم...'),
                      prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Account list
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final account = filtered[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.only(
                            right: 16.0 + ((account.code.length / 2).floor() * 12.0),
                            left: 16.0,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              account.code,
                              style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                          title: Text(
                            trData(account.name),
                            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          onTap: () async {
                            try {
                              final accountingRepo = ref.read(accountingRepositoryProvider);
                              await accountingRepo.setAccountMapping(item.purpose, account.id, costCenterId: selectedCostCenterId);
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                              if (mounted) {
                                AppToast.show(context, tr('تم ربط "{p0}" بحساب "{p1}"', {'p0': item.label, 'p1': trData(account.name)}));
                              }
                            } catch (e) {
                              if (mounted) {
                                AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                              }
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء')),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// Dialog to edit an existing mapping
  void _showEditMappingDialog(AccountMapping mapping, _PurposeItem item, Color color) {
    final searchCtrl = TextEditingController();
    int? selectedCostCenterId = mapping.costCenterId;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          final query = ArabicUtils.normalize(searchCtrl.text.toLowerCase());
          final filtered = query.isEmpty
              ? _allAccounts
              : _allAccounts.where((a) =>
                  ArabicUtils.normalize(a.name.toLowerCase()).contains(query) ||
                  a.code.contains(query)).toList();

          return AlertDialog(
            title: Row(
              children: [
                Icon(PhosphorIconsBold.pencilSimple, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('تعديل ربط: {p0}', {'p0': item.label}), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 450,
              child: Column(
                children: [
                  // Cost center selector
                  Row(
                    children: [
                      const Icon(PhosphorIconsBold.buildings, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Text(tr('مركز التكلفة:'), style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: selectedCostCenterId,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          items: [
                            DropdownMenuItem<int?>(value: null, child: Text(tr('🌐 عالمي (افتراضي)'), style: GoogleFonts.cairo(fontSize: 12))),
                            ..._costCenters.map((cc) => DropdownMenuItem<int?>(
                                  value: cc.id,
                                  child: Text('🏢 ${trData(cc.name)}', style: GoogleFonts.cairo(fontSize: 12)),
                                )),
                          ],
                          onChanged: (v) => setDialogState(() => selectedCostCenterId = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Account search
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: tr('بحث بالرمز أو الاسم...'),
                      prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Account list
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final account = filtered[i];
                        final isSelected = mapping.accountId == account.id;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: color.withValues(alpha: 0.08),
                          contentPadding: EdgeInsets.only(
                            right: 16.0 + ((account.code.length / 2).floor() * 12.0),
                            left: 16.0,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              account.code,
                              style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                          title: Text(
                            trData(account.name),
                            style: GoogleFonts.cairo(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                          ),
                          trailing: isSelected
                              ? const Icon(PhosphorIconsBold.check, color: AppColors.success, size: 18)
                              : null,
                          onTap: () async {
                            try {
                              final accountingRepo = ref.read(accountingRepositoryProvider);
                              // Delete old mapping, insert new one
                              await accountingRepo.deleteAccountMappingById(mapping.id);
                              await accountingRepo.setAccountMapping(item.purpose, account.id, costCenterId: selectedCostCenterId);
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                              if (mounted) {
                                AppToast.show(context, tr('تم تعديل ربط "{p0}" إلى "{p1}"', {'p0': item.label, 'p1': trData(account.name)}));
                              }
                            } catch (e) {
                              if (mounted) {
                                AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                              }
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء')),
              ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _deleteMappingEntry(AccountMapping mapping, _PurposeItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Text(tr('حذف ربط حساب')),
          content: Text(tr('هل تريد حذف ربط "{p0}"؟', {'p0': item.label})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child:  Text(tr('إلغاء'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    try {
      final accountingRepo = ref.read(accountingRepositoryProvider);
      await accountingRepo.deleteAccountMappingById(mapping.id);
      await _loadData();
      if (mounted) {
        AppToast.show(context, tr('تم حذف ربط "{p0}"', {'p0': item.label}), type: ToastType.warning);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }
}

class _PurposeGroup {
  final String title;
  final IconData icon;
  final Color color;
  final List<_PurposeItem> items;

  const _PurposeGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });
}

class _PurposeItem {
  final String purpose;
  final String label;
  final String defaultCode;
  final String description;

  const _PurposeItem(this.purpose, this.label, this.defaultCode, this.description);
}
