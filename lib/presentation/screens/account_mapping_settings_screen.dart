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
  static const _purposeGroups = <_PurposeGroup>[
    // ── المجموعة 1: النقدية والذمم ──────────────────────────────────────────
    _PurposeGroup(
      title: 'النقدية والذمم المدينة',
      icon: PhosphorIconsBold.bank,
      color: Color(0xFF2563EB),
      items: [
        _PurposeItem('cash',                'الصندوق الرئيسي',              '1111', 'حساب النقد الافتراضي للمبيعات والمصروفات النقدية'),
        _PurposeItem('petty_cash',          'صندوق العهدة',                 '1112', 'صندوق النقد الصغير والعهد'),
        _PurposeItem('bank',                'البنك الرئيسي',                '1113', 'حساب البنك للمدفوعات بالبطاقات والتحويلات'),
        _PurposeItem('bank2',               'البنك الثاني',                 '1114', 'حساب البنك الاحتياطي الثاني'),
        _PurposeItem('click',               'حساب Click / إلكتروني',        '1116', 'حساب المدفوعات الإلكترونية (Click/KNET)'),
        _PurposeItem('receivables',         'ذمم العملاء المحليون',         '1121', 'حساب الذمم المدينة للعملاء المحليين'),
        _PurposeItem('foreign_receivables', 'ذمم العملاء الخارجيون',        '1122', 'حساب الذمم المدينة للعملاء الخارجيين'),
        _PurposeItem('notes_receivable',    'أوراق القبض',                  '1123', 'حساب الشيكات وأوراق القبض من العملاء'),
      ],
    ),
    // ── المجموعة 2: المخزون والأصول المتداولة ───────────────────────────────
    _PurposeGroup(
      title: 'المخزون والأصول المتداولة',
      icon: PhosphorIconsBold.package,
      color: Color(0xFF7C3AED),
      items: [
        _PurposeItem('inventory',           'مخزون البضاعة للبيع',          '1136', 'الحساب الرئيسي لمخزون بضاعة التجارة'),
        _PurposeItem('raw_materials',       'مخزون المواد الخام',           '1131', 'مخزون المواد الخام للإنتاج'),
        _PurposeItem('wip',                 'مخزون تحت التشغيل',            '1133', 'منتجات تحت الإنتاج (WIP)'),
        _PurposeItem('applied_overhead',    'تحميل صناعي مطبّق',            '5138', 'الطرف الدائن لتحميل التكاليف غير المباشرة على أوامر التصنيع'),
        _PurposeItem('goods_in_transit',    'بضاعة تامة / عبور',            '1134', 'المنتجات النهائية والبضاعة في الطريق'),
        _PurposeItem('input_vat',           'ضريبة القيمة المضافة مدفوعة', '1141', 'ضريبة القيمة المضافة على المشتريات'),
        _PurposeItem('prepaid_expenses',    'مصروفات مقدمة',                '1143', 'المصروفات المدفوعة مسبقاً'),
        _PurposeItem('employee_advances',   'سلف الموظفين',                 '1146', 'السلف المدفوعة للموظفين'),
        _PurposeItem('fixed_assets',        'الأصول الثابتة',               '1211', 'حساب الأصول الثابتة والمعدات'),
      ],
    ),
    // ── المجموعة 3: الخصوم والالتزامات ──────────────────────────────────────
    _PurposeGroup(
      title: 'الخصوم والالتزامات',
      icon: PhosphorIconsBold.handCoins,
      color: Color(0xFFDC2626),
      items: [
        _PurposeItem('payables',            'ذمم الموردون المحليون',         '2111', 'حساب الذمم الدائنة للموردين المحليين'),
        _PurposeItem('foreign_payables',    'ذمم الموردون الخارجيون',        '2112', 'حساب الذمم الدائنة للموردين الخارجيين'),
        _PurposeItem('notes_payable',       'أوراق الدفع',                  '2113', 'الشيكات وأوراق الدفع للموردين'),
        _PurposeItem('output_vat',          'ضريبة القيمة المضافة محصلة',   '2121', 'ضريبة القيمة المضافة على المبيعات'),
        _PurposeItem('income_tax',          'ضريبة الدخل',                  '2122', 'ضريبة الدخل المستحقة'),
        _PurposeItem('accrued_salaries',    'رواتب مستحقة',                 '2131', 'الرواتب المستحقة غير المدفوعة'),
        _PurposeItem('deferred_revenue',    'إيرادات مقدمة / مؤجلة',        '2133', 'الإيرادات المحصلة قبل التسليم (IFRS 15)'),
        _PurposeItem('loans_payable',       'قروض بنكية',                   '2141', 'القروض البنكية وطويلة الأجل'),
      ],
    ),
    // ── المجموعة 4: الإيرادات ────────────────────────────────────────────────
    _PurposeGroup(
      title: 'الإيرادات',
      icon: PhosphorIconsBold.trendUp,
      color: Color(0xFF059669),
      items: [
        _PurposeItem('sales',               'مبيعات محلية',                 '4121', 'حساب إيرادات المبيعات المحلية الرئيسي'),
        _PurposeItem('export_sales',        'مبيعات تصدير',                 '4122', 'حساب إيرادات مبيعات التصدير'),
        _PurposeItem('delivery_revenue',    'إيرادات التوصيل',              '414',  'حساب إيرادات خدمات التوصيل'),
        _PurposeItem('service_revenue',     'إيرادات الخدمات',              '4131', 'حساب إيرادات الخدمات ما بعد البيع'),
        _PurposeItem('sales_return',        'مردودات المبيعات',             '4211', 'حساب مردودات وإرجاع المبيعات'),
        _PurposeItem('sales_discount',      'خصم المبيعات الممنوح',         '4212', 'خصومات الفاتورة الممنوحة للعملاء'),
        _PurposeItem('purchase_discount',   'خصم المشتريات المكتسب',        '4316', 'الخصم المحصل من الموردين عند الدفع المبكر'),
        _PurposeItem('discount_received',   'خصم مكتسب (تسوية)',            '4316', 'خصم التسوية المكتسب عند استيفاء الديون'),
        _PurposeItem('other_income',        'إيرادات متنوعة',               '4315', 'الإيرادات غير التشغيلية والمتنوعة'),
        _PurposeItem('inventory_surplus',   'فائض مخزون',                   '4317', 'إيراد فائض الجرد عند زيادة المخزون الفعلي'),
        _PurposeItem('cash_surplus',        'فائض نقدي',                    '4318', 'إيراد فائض الصندوق عند إغلاق الوردية'),
      ],
    ),
    // ── المجموعة 5: تكلفة البضاعة ───────────────────────────────────────────
    _PurposeGroup(
      title: 'تكلفة البضاعة المباعة',
      icon: PhosphorIconsBold.shoppingCartSimple,
      color: Color(0xFFB45309),
      items: [
        _PurposeItem('cogs',                'تكلفة البضاعة المباعة',        '5211', 'حساب تكلفة المبيعات (COGS) الرئيسي'),
        _PurposeItem('purchases',           'مشتريات',                      '5211', 'حساب المشتريات الرئيسي'),
        _PurposeItem('purchase_return',     'مردودات مشتريات',              '5214', 'حساب مردودات وإرجاع المشتريات'),
      ],
    ),
    // ── المجموعة 6: المصروفات التشغيلية ─────────────────────────────────────
    _PurposeGroup(
      title: 'المصروفات التشغيلية',
      icon: PhosphorIconsBold.trendDown,
      color: Color(0xFFF59E0B),
      items: [
        _PurposeItem('salary_expense',      'رواتب — إدارة',                '621',  'حساب مصروفات الرواتب والأجور الإدارية'),
        _PurposeItem('rent_expense',        'مصروف إيجار',                  '623',  'حساب مصروفات الإيجار'),
        _PurposeItem('discount_allowed',    'خصم مسموح للعملاء',            '6215', 'خصم التسوية الممنوح عند استيفاء الديون'),
        _PurposeItem('inventory_shrinkage', 'عجز مخزون',                    '6216', 'مصروف النقص والتلف في المخزون'),
        _PurposeItem('cash_shortage',       'عجز نقدي',                     '6217', 'مصروف العجز النقدي عند إغلاق الوردية'),
        _PurposeItem('misc_expense',        'مصروفات متنوعة',               '6214', 'حساب المصروفات العامة والمتنوعة'),
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
          title: Text('استعادة الربط الافتراضي', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(
            'سيتم حذف جميع الربط المحاسبي الحالي واستعادة الربط الافتراضي من دليل الحسابات. هل تريد المتابعة؟',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text('استعادة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, color: Colors.white)),
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
      if (mounted) AppToast.show(context, 'تم استعادة الربط المحاسبي الافتراضي بنجاح');
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ: $e', type: ToastType.error);
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
                        'وضع القراءة فقط — الربط المحاسبي يتم مركزيًا على السيرفر. لتعديل الربط، استخدم جهاز السيرفر.',
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
                Text('ربط الحسابات', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('تخصيص الحسابات المستخدمة في القيود التلقائية', style: GoogleFonts.cairo(fontSize: 11, color: Colors.white70)),
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
                '🏢 ${_costCenters.length} مراكز تكلفة',
                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _loadData,
            icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 16, color: Colors.white),
            label: Text('تحديث', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
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
              label: Text('استعادة الافتراضي', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
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
                  label: Text('إضافة ربط', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600)),
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
          Text('افتراضي', style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
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
                  isGlobal ? 'عالمي' : costCenter?.name ?? '؟',
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
              account?.name ?? 'حساب غير موجود',
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Edit button (disabled in client mode)
          if (!_isClientMode)
            IconButton(
              icon: Icon(PhosphorIconsBold.pencilSimple, size: 14, color: color),
              onPressed: () => _showEditMappingDialog(mapping, item, color),
              tooltip: 'تعديل',
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          // Delete button (disabled in client mode)
          if (!_isClientMode)
            IconButton(
              icon: const Icon(PhosphorIconsBold.trash, size: 14, color: AppColors.error),
              onPressed: () => _deleteMappingEntry(mapping, item),
              tooltip: 'حذف',
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
                  child: Text('إضافة ربط: ${item.label}', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15)),
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
                      Text('مركز التكلفة:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
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
                            DropdownMenuItem<int?>(value: null, child: Text('🌐 عالمي (افتراضي)', style: GoogleFonts.cairo(fontSize: 12))),
                            ..._costCenters.map((cc) => DropdownMenuItem<int?>(
                                  value: cc.id,
                                  child: Text('🏢 ${cc.name}', style: GoogleFonts.cairo(fontSize: 12)),
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
                      hintText: 'بحث بالرمز أو الاسم...',
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
                            account.name,
                            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          onTap: () async {
                            try {
                              final accountingRepo = ref.read(accountingRepositoryProvider);
                              await accountingRepo.setAccountMapping(item.purpose, account.id, costCenterId: selectedCostCenterId);
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                              if (mounted) {
                                AppToast.show(context, 'تم ربط "${item.label}" بحساب "${account.name}"');
                              }
                            } catch (e) {
                              if (mounted) {
                                AppToast.show(context, 'خطأ: $e', type: ToastType.error);
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
                child: const Text('إلغاء'),
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
                  child: Text('تعديل ربط: ${item.label}', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15)),
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
                      Text('مركز التكلفة:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
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
                            DropdownMenuItem<int?>(value: null, child: Text('🌐 عالمي (افتراضي)', style: GoogleFonts.cairo(fontSize: 12))),
                            ..._costCenters.map((cc) => DropdownMenuItem<int?>(
                                  value: cc.id,
                                  child: Text('🏢 ${cc.name}', style: GoogleFonts.cairo(fontSize: 12)),
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
                      hintText: 'بحث بالرمز أو الاسم...',
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
                            account.name,
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
                                AppToast.show(context, 'تم تعديل ربط "${item.label}" إلى "${account.name}"');
                              }
                            } catch (e) {
                              if (mounted) {
                                AppToast.show(context, 'خطأ: $e', type: ToastType.error);
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
                child: const Text('إلغاء'),
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
          title: const Text('حذف ربط حساب'),
          content: Text('هل تريد حذف ربط "${item.label}"؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف'),
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
        AppToast.show(context, 'تم حذف ربط "${item.label}"', type: ToastType.warning);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
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
