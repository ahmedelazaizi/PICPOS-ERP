// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_toolbar.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../screens/reports/report_export_guard.dart';
import '../screens/coa/coa_dialogs.dart';

import 'package:intl/intl.dart' hide TextDirection;

import '../../data/providers/providers.dart';
import '../../data/providers/manufacturing_providers.dart';
import '../../services/invoice_generator.dart';
import '../../services/network_service.dart';
// ⚠️ لا استيرادَ مباشرٍ لـ`data/database` من طبقة العرض: حارسُ
// `presentation_db_import_guard` يرفض أيَّ ملفٍّ **جديد** يفعلها، وقائمتُه
// البيضاء مقفولة. والأصلُ المشتركُ يستورد `sync_interceptor` مباشرةً لأنّه
// سابقٌ للحارس، والفوركُ ملفٌّ جديدٌ فيسري عليه.
// و`isClientModeProvider` يكشف نفسَ المعلومة عبر مزوِّدٍ قائمٍ في
// `inventory_providers.dart` — فالإصلاحُ توصيلٌ لا اختراع.
import '../../services/sync/sync_worker.dart';
import '../../core/constants/app_constants.dart';
import '../widgets/report_components.dart' show DateRangeFilter;
import '../../domain/entities/accounting_entities.dart' show BranchCostCenterRepairReport;

/// أيُّ تبويباتِ الشاشة تُعرَض — والشاشةُ واحدةٌ لا شاشتان.
///
/// ═══ لماذا مُعامِلٌ لا ملفٌّ جديد ═══
///
/// قرارُ المالك 2026-08-27: شريحةُ «ميزان المراجعة» في حاوية الحسابات
/// كانت تفتح هذه الشاشةَ بستِّ تبويباتٍ داخليّة — **تبويباتٌ داخل
/// تبويبات**، وأوّلُها ميزانُ المراجعة نفسُه. فيُقسَم المعروضُ على
/// شريحتَين: `tb` للميزان وحدَه، وثامنةٌ للقوائم الخمس.
///
/// وشقُّ الميزان إلى ملفٍّ مستقلٍّ كان سيُكرّر مرشِّحاتِ المدى والفرع
/// والمنطقة ومركز التكلفة، ومسارَي التصدير والطباعة — وهي مشتركةٌ بين
/// الميزان والقوائم حرفاً. فالتكرارُ كان سيُنتج نسختَين تنحرفان بأوّل
/// تعديلِ مرشِّح، والأرقامُ عندئذٍ تُقرأ على نطاقَين مختلفَين بلا أن
/// يظهر ذلك. فالانقسامُ في **ما يُعرَض** لا في **ما يُحسَب**.
enum FinancialStatementsView {
  /// ميزانُ المراجعة وحدَه — بلا شريطِ تبويباتٍ أصلاً.
  trialBalance,

  /// القوائمُ الخمسُ الباقية.
  statements,

  /// الستّةُ معاً — السلوكُ قبل الانقسام، ويبقى لأيّ مستدعٍ خارجيّ.
  all,
}

class FinancialStatementsPicPosScreen extends ConsumerStatefulWidget {
  /// Optional tab to open on startup. 5 = مطابقة الترحيل (used by sync badge).
  ///
  /// ⚠️ الرقمُ يُقاس على تبويبات **[FinancialStatementsView.all]** دائماً
  /// (‏٠ الميزان … ٥ مطابقةُ الترحيل)، ثمّ يُترجَم إلى موضعِه في العرض
  /// المختار. فمستدعٍ قديمٌ يمرّر `5` يصل إلى مطابقة الترحيل في الحالتين.
  final int initialTabIndex;

  final FinancialStatementsView view;

  const FinancialStatementsPicPosScreen({
    super.key,
    this.initialTabIndex = 0,
    this.view = FinancialStatementsView.all,
  });

  @override
  ConsumerState<FinancialStatementsPicPosScreen> createState() =>
      _FinancialStatementsPicPosScreenState();
}

class _FinancialStatementsPicPosScreenState
    extends ConsumerState<FinancialStatementsPicPosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Spec 065: defaults are full-day-inclusive — month-day-1 (already at 00:00)
  // and end-of-today at 23:59:59.999 (D3-006).
  DateTime _fromDate = DateRangeFilter.normalizeStart(
      DateTime(DateTime.now().year, DateTime.now().month, 1));
  DateTime _toDate = DateRangeFilter.normalizeEnd(DateTime.now());
  int _refreshKey = 0;
  int? _selectedCostCenterId; // null = all cost centers
  int? _selectedRegionId; // null = all regions
  int? _selectedBranchId; // null = all branches
  bool _showReceivables = true; // toggle for aged receivables vs payables

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  // FIL-2 (spec 149 B12): the logged-in user's branch authorization scope.
  // null = full access (admin/financial-manager/mirror) → no restriction.
  // Populated at the top of build() from branchScopeProvider and read by
  // every report call-site (export/print/render) below so a restricted
  // user can never pull another branch's financial data through this
  // screen, regardless of what they pick in the branch dropdown.
  Set<int>? _allowedBranchIds;

  /// تبويباتُ الشاشة الستّةُ بترتيبها الأصليّ.
  ///
  /// ⚠️ `slot` هو الرقمُ **الثابت** الذي يعرفه المستدعون الخارجيّون
  /// (‏شارةُ المزامنة تمرّر `5` لمطابقة الترحيل). فلا يُشتقّ من الموضع في
  /// القائمة المعروضة، وإلّا صار «٥» يعني تبويباً مختلفاً بكلّ عرض.
  static final List<({int slot, String label, IconData icon})> _allTabs = [
    (slot: 0, label: 'ميزان المراجعة', icon: PhosphorIconsBold.scales),
    (slot: 1, label: 'قائمة الدخل (P&L)', icon: PhosphorIconsBold.chartLineUp),
    (slot: 2, label: 'الميزانية العمومية', icon: PhosphorIconsBold.bank),
    (
      slot: 3,
      label: 'التدفقات النقدية',
      icon: PhosphorIconsBold.currencyCircleDollar
    ),
    (slot: 4, label: 'تقادم الذمم', icon: PhosphorIconsBold.hourglass),
    (
      slot: 5,
      label: 'مطابقة الترحيل',
      icon: PhosphorIconsBold.checkSquareOffset
    ),
  ];

  List<({int slot, String label, IconData icon})> get _tabs =>
      switch (widget.view) {
        FinancialStatementsView.trialBalance => [_allTabs.first],
        FinancialStatementsView.statements => _allTabs.sublist(1),
        FinancialStatementsView.all => _allTabs,
      };

  Widget _tabBody(int slot) => switch (slot) {
        0 => _buildTrialBalanceTab(),
        1 => _buildIncomeStatementTab(),
        2 => _buildBalanceSheetTab(),
        3 => _buildCashFlowTab(),
        4 => _buildAgingReportTab(),
        _ => _buildReconciliationTab(),
      };

  @override
  void initState() {
    super.initState();
    final tabs = _tabs;
    // الرقمُ المطلوبُ قد لا يكون معروضاً في هذا العرض — فيُرتدّ إلى أوّله
    // بدل أن يُقصَّ إلى تبويبٍ غيرِ الذي طُلب.
    final wanted = tabs.indexWhere((t) => t.slot == widget.initialTabIndex);
    _tabController = TabController(
      length: tabs.length,
      vsync: this,
      initialIndex: wanted < 0 ? 0 : wanted,
    );
    Future.microtask(() async {
      // Feature 058: seed _selectedBranchId from the device's active branch
      // so the FIRST tab fetch (driven by the build path's repo calls) sees
      // the active-branch filter (FR-001 + FR-002). _refreshKey is bumped so
      // any FutureBuilders keyed by it pick up the new value.
      if (_selectedBranchId == null) {
        final activeBranchId = await ref.read(activeBranchIdProvider.future);
        if (!mounted) return;
        if (activeBranchId != null) {
          setState(() {
            _selectedBranchId = activeBranchId;
            _refreshKey++;
          });
        } else if (!_noBranchNoticeShown) {
          _noBranchNoticeShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('لم يتم تعيين فرع لهذا المستخدم — يتم عرض كل الفروع'),
              duration: Duration(seconds: 6),
            ));
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    // FIL-2 (spec 149 B12): resolve the auth-level branch scope BEFORE any
    // report query runs. Reports MUST NOT render (even a flash) while the
    // scope is unknown — a restricted user briefly seeing an unscoped
    // report is itself the leak this fix closes.
    final scopeAsync = ref.watch(branchScopeProvider);
    if (scopeAsync.isLoading) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (scopeAsync.hasError) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(child: Text('تعذر تحديد صلاحيات الفرع: ${scopeAsync.error}')),
        ),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PicPosScreenScaffold(
        title: switch (widget.view) {
          FinancialStatementsView.trialBalance => 'ميزان المراجعة',
          FinancialStatementsView.statements => 'القوائم المالية',
          FinancialStatementsView.all => 'القوائم المالية',
        },
        // عنوانُ الميزان الفرعيُّ منقولٌ من `HEADS.tb` في التصميم حرفاً.
        subtitle: switch (widget.view) {
          FinancialStatementsView.trialBalance =>
            'أرصدة افتتاحية وحركة وأرصدة ختامية',
          FinancialStatementsView.statements =>
            'قائمةُ الدخل · المركزُ المالي · التدفّقات · تقادمُ الذمم · مطابقةُ الترحيل',
          FinancialStatementsView.all =>
            'ميزانُ المراجعة · قائمةُ الدخل · المركزُ المالي · التدفّقات',
        },
        icon: switch (widget.view) {
          FinancialStatementsView.statements => PhosphorIconsBold.chartLineUp,
          _ => PhosphorIconsBold.scales,
        },
        // ⚠️ التبويباتُ في `subHeader` لا في `AppBar.bottom`: الغلافُ
        //    المشتركُ لا يحمل `AppBar` أصلاً، والترويسةُ فيه جزءٌ منه.
        //
        // وشريطٌ بتبويبٍ واحدٍ ليس تبويباً — هو صفٌّ يشغل ارتفاعاً ويكرّر
        // عنوانَ الشاشة. فيسقط كلَّه في عرض الميزان.
        subHeader: tabs.length < 2
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final t in tabs)
                    Tab(text: t.label, icon: Icon(t.icon)),
                ],
              ),
        // ⚠️ المرشِّحاتُ في الشريط لا في `AppBar.actions`: الشريطُ `Wrap`
        //    يلتفّ، و`actions` صفٌّ يفيض. وهي مرشِّحاتٌ حقيقيّة (المنطقةُ
        //    والفرعُ ومركزُ التكلفة) تغيّر أرقامَ القوائم — إسقاطُها في
        //    إعادة التنسيق يعني قوائمَ تُقرأ على نطاقٍ غيرِ الذي يظنّه
        //    القارئ.
        toolbar: PicPosToolbar(
          children: [
            // Region Filter
            Consumer(
              builder: (context, ref, _) {
                final regionsAsync = ref.watch(allRegionsProvider);
                return regionsAsync.when(
                  data: (regions) {
                    if (regions.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: regions.any((r) => r.id == _selectedRegionId) ? _selectedRegionId : null,
                          hint: const Text('المنطقة', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          dropdownColor: AppColors.primary,
                          iconEnabledColor: Colors.white70,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('كل المناطق')),
                            ...regions.map((r) => DropdownMenuItem<int?>(value: r.id, child: Text(r.name))),
                          ],
                          onChanged: (v) => setState(() { _selectedRegionId = v; _selectedBranchId = null; _refreshKey++; }),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                );
              },
            ),
            // Branch Filter (filtered by region when a region is selected)
            Consumer(
              builder: (context, ref, _) {
                final branchesAsync = _selectedRegionId != null
                    ? ref.watch(regionBranchesProvider(_selectedRegionId!))
                    : ref.watch(branchListProvider);
                return branchesAsync.when(
                  data: (branches) {
                    // FIL-2: defense-in-depth — a restricted user shouldn't
                    // even be offered other branches in the dropdown. The
                    // real enforcement is server-side (auth-scope filter on
                    // every report query above); this just keeps the UI
                    // honest. `scope` is the same BranchScope resolved at
                    // the top of build(). With auth-scope enforced, "كل
                    // الفروع" (null) now means "all MY branches", not the
                    // whole company.
                    final visibleBranches = scope.hasFullAccess
                        ? branches
                        : branches.where((b) => scope.allowedBranchIds!.contains(b.id)).toList();
                    if (visibleBranches.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: visibleBranches.any((b) => b.id == _selectedBranchId) ? _selectedBranchId : null,
                          hint: const Text('الفرع', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          dropdownColor: AppColors.primary,
                          iconEnabledColor: Colors.white70,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('كل الفروع')),
                            ...visibleBranches.map((b) => DropdownMenuItem<int?>(value: b.id, child: Text(b.name))),
                          ],
                          onChanged: (v) => setState(() { _selectedBranchId = v; _refreshKey++; }),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                );
              },
            ),
            // Cost Center Filter
            FutureBuilder<List<CostCenter>>(
              future: ref.read(accountingRepositoryProvider).getActiveCostCenters(),
              builder: (context, snap) {
                final centers = snap.data ?? [];
                if (centers.isEmpty) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedCostCenterId,
                      hint: const Text('مركز التكلفة', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      dropdownColor: AppColors.primary,
                      iconEnabledColor: Colors.white70,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
                        ...centers.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => setState(() { _selectedCostCenterId = v; _refreshKey++; }),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              onPressed: () => setState(() => _refreshKey++),
              tooltip: 'تحديث البيانات',
            ),
            buildReportExportAction(onExport: _exportToExcel),
            IconButton(
              icon: const Icon(PhosphorIconsBold.printer),
              onPressed: _printReport,
              tooltip: 'طباعة/PDF',
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.calendar),
              onPressed: _selectDateRange,
            ),
            // Remediation Button (PIR Remediation)
            IconButton(
              icon: const Icon(PhosphorIconsBold.magicWand, color: Colors.orangeAccent),
              tooltip: 'إصلاح فروقات التقارير والمراكز',
              onPressed: () => _showRemediationDialog(),
            ),
          ],
        ),
        // ⚠️ `TabBarView` يطلب ارتفاعاً محدَّداً، وجسمُ الغلاف يُمرَّر داخل
        //    `Expanded` فيعطيه إيّاه. ولو لُفَّ في تمريرةٍ لطلب ارتفاعاً لا
        //    نهائيّاً وانهار — وهو عطبُ الخزينة البيضاء نفسُه.
        body: TabBarView(
          controller: _tabController,
          children: [for (final t in tabs) _tabBody(t.slot)],
        ),
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        // FIL-1: normalize to start-of-day / end-of-day so entries posted
        // after 00:00 on the selected end day are not dropped from the
        // Trial Balance / Income Statement / Balance Sheet (entry_date carries
        // real time-of-day; the picker returns midnight).
        _fromDate = DateRangeFilter.normalizeStart(picked.start);
        _toDate = DateRangeFilter.normalizeEnd(picked.end);
        _refreshKey++;
      });
    }
  }

  Future<void> _exportToExcel() async {
    final repo = ref.read(reportingRepositoryProvider);
    final service = ref.read(excelServiceProvider);

    try {
      switch (_tabController.index) {
        case 0: // Trial Balance
          final data = await repo.getTrialBalance(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: 'ميزان المراجعة من ${_fromDate.toString().split(' ')[0]} إلى ${_toDate.toString().split(' ')[0]}',
            headers: [
              'كود الحساب',
              'اسم الحساب',
              'رصيد أول مدين',
              'رصيد أول دائن',
              'حركة الفترة مدين',
              'حركة الفترة دائن',
              'رصيد نهائي مدين',
              'رصيد نهائي دائن',
            ],
            rows: data
                .map<List<dynamic>>(
                  (row) => [
                    row['code'],
                    row['name'],
                    row['openingDebit'],
                    row['openingCredit'],
                    row['movementDebit'],
                    row['movementCredit'],
                    row['closingDebit'],
                    row['closingCredit'],
                  ],
                )
                .toList(),
          );
          break;
        case 1: // Income Statement
          final data = await repo.getIncomeStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          final List<List<dynamic>> rows = [];
          for (final item in (data['revenueDetails'] as List)) {
            rows.add(['إيراد', item['name'], item['amount']]);
          }
          for (final item in (data['expenseDetails'] as List)) {
            rows.add(['مصروف', item['name'], item['amount']]);
          }
          rows.add(['', 'صافي الربح', data['netProfit']]);
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: 'قائمة الدخل',
            headers: ['النوع', 'البيان', 'المبلغ'],
            rows: rows,
          );
          break;
        case 2: // Balance Sheet
          final data = await repo.getBalanceSheet(_toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          final List<List<dynamic>> rows = [];
          for (final item in (data['assetDetails'] as List)) {
            rows.add(['أصل', item['name'], item['balance']]);
          }
          for (final item in (data['liabilityDetails'] as List)) {
            rows.add(['التزام', item['name'], item['balance']]);
          }
          for (final item in (data['equityDetails'] as List)) {
            rows.add(['حقوق ملكية', item['name'], item['balance']]);
          }
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: 'الميزانية العمومية',
            headers: ['النوع', 'البيان', 'الرصيد'],
            rows: rows,
          );
          break;
        case 3: // Cash Flow
          final data = await ref.read(accountingRepositoryProvider).getCashFlowStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          final op = data['operating'] as Map<String, dynamic>;
          final inv = data['investing'] as Map<String, dynamic>;
          final fin = data['financing'] as Map<String, dynamic>;
          final List<List<dynamic>> rows = [
            ['تشغيلي', 'إيرادات المبيعات النقدية', op['salesCash']],
            ['تشغيلي', 'مدفوعات المشتريات', op['purchasesCash']],
            ['تشغيلي', 'الرواتب', op['salaries']],
            ['تشغيلي', 'المصاريف التشغيلية', op['expenses']],
            ['تشغيلي', 'صافي النشاط التشغيلي', op['net']],
            ['استثماري', 'شراء أصول', inv['assetPurchases']],
            ['استثماري', 'بيع أصول', inv['assetDisposals']],
            ['استثماري', 'صافي النشاط الاستثماري', inv['net']],
            ['تمويلي', 'شيكات محصلة', fin['checksCollected']],
            ['تمويلي', 'شيكات مصدرة', fin['checksIssued']],
            ['تمويلي', 'صافي النشاط التمويلي', fin['net']],
            ['', 'الرصيد الافتتاحي', data['openingBalance']],
            ['', 'صافي التغير', data['netChange']],
            ['', 'الرصيد الختامي', data['closingBalance']],
          ];
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: 'قائمة التدفقات النقدية',
            headers: ['النشاط', 'البيان', 'المبلغ'],
            rows: rows,
          );
          break;
        case 4: // Aged Receivables/Payables
          final accountingRepo = ref.read(accountingRepositoryProvider);
          final List<Map<String, dynamic>> agingData;
          final String title;
          if (_showReceivables) {
            agingData = await accountingRepo.getAgedReceivables(_toDate, costCenterId: _selectedCostCenterId, allowedBranchIds: _allowedBranchIds);
            title = 'تقادم الذمم المدينة (العملاء)';
          } else {
            agingData = await accountingRepo.getAgedPayables(_toDate, costCenterId: _selectedCostCenterId, allowedBranchIds: _allowedBranchIds);
            title = 'تقادم الذمم الدائنة (الموردين)';
          }
          await service.exportReport(
      periodFrom: _fromDate,
      periodTo: _toDate,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
            title: title,
            headers: ['الاسم', 'الإجمالي', '0-30 يوم', '31-60 يوم', '61-90 يوم', '+90 يوم'],
            rows: agingData.map<List<dynamic>>((r) => [
              r['name'], r['totalBalance'], r['current'],
              r['days31_60'], r['days61_90'], r['over90'],
            ]).toList(),
          );
          break;
      }

      if (mounted) {
        AppToast.show(
          context,
          'تم تصدير التقرير بنجاح',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في التصدير: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _printReport() async {
    final repo = ref.read(reportingRepositoryProvider);

    try {
      switch (_tabController.index) {
        case 0: // Trial Balance
          final data = await repo.getTrialBalance(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await InvoiceGenerator.printFinancialStatement(
            title: 'ميزان المراجعة',
            data: data,
            statementType: 'trial_balance',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
        case 1: // Income Statement
          final data = await repo.getIncomeStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await InvoiceGenerator.printFinancialStatement(
            title: 'قائمة الدخل',
            data: [data],
            statementType: 'income_statement',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
        case 2: // Balance Sheet
          final data = await repo.getBalanceSheet(_toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await InvoiceGenerator.printFinancialStatement(
            title: 'الميزانية العمومية',
            data: [data],
            statementType: 'balance_sheet',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
        case 3: // Cash Flow
          final data = await ref.read(accountingRepositoryProvider).getCashFlowStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds);
          await InvoiceGenerator.printFinancialStatement(
            title: 'قائمة التدفقات النقدية',
            data: [data],
            statementType: 'cash_flow',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
        case 4: // Aged Receivables/Payables
          final accountingRepo = ref.read(accountingRepositoryProvider);
          final List<Map<String, dynamic>> agingData;
          final String title;
          if (_showReceivables) {
            agingData = await accountingRepo.getAgedReceivables(_toDate, costCenterId: _selectedCostCenterId, allowedBranchIds: _allowedBranchIds);
            title = 'تقادم الذمم المدينة';
          } else {
            agingData = await accountingRepo.getAgedPayables(_toDate, costCenterId: _selectedCostCenterId, allowedBranchIds: _allowedBranchIds);
            title = 'تقادم الذمم الدائنة';
          }
          await InvoiceGenerator.printFinancialStatement(
            title: title,
            data: agingData,
            statementType: 'aging_report',
            fromDate: _fromDate,
            toDate: _toDate,
          );
          break;
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }

  Widget _buildTrialBalanceTab() {
    final repo = ref.read(reportingRepositoryProvider);
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('trial_${_refreshKey}_${_fromDate}_${_toDate}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: repo.getTrialBalance(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;

        return Column(
          children: [
            _buildReportHeader(
              'ميزان المراجعة من ${_fromDate.toString().split(' ')[0]} إلى ${_toDate.toString().split(' ')[0]}',
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 16,
                    horizontalMargin: 12,
                    columns: const [
                      DataColumn(label: Text('كود', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('اسم الحساب', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('رصيد أول\nمدين', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text('رصيد أول\nدائن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text('حركة الفترة\nمدين', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text('حركة الفترة\nدائن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text('رصيد نهائي\nمدين', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                      DataColumn(label: Text('رصيد نهائي\nدائن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                    ],
                    rows: data.map((row) {
                      final isTotal = row['type'] == 'total';
                      final style = TextStyle(
                        fontWeight: isTotal ? FontWeight.w900 : FontWeight.normal,
                        fontFamily: 'monospace',
                        fontSize: isTotal ? 13 : 12,
                      );
                      final nameStyle = TextStyle(
                        fontWeight: isTotal ? FontWeight.w900 : FontWeight.w500,
                        fontSize: isTotal ? 13 : 12,
                      );

                      String fmt(double v) => v == 0 ? '-' : v.toStringAsFixed(AppConstants.decimalPlaces);

                      return DataRow(
                        color: isTotal
                            ? WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08))
                            : null,
                        // ⚠️ **هذا هو مكسبُ النقل إلى مجموعة الحسابات**:
                        //    ميزانٌ لا يتوازن ⇒ تنقر السطرَ المشبوه ⇒ ترى
                        //    قيودَه. وقبله كان المحاسبُ يخرج من التقارير
                        //    ويدخل الحسابات ويبحث بالرمز بيده.
                        //    و`showAccountLedger` قائمةٌ ومستعملةٌ في شجرة
                        //    الحسابات — فلا كودَ جديد.
                        //
                        // ⚠️ وسطرُ الإجماليّات مستثنًى: لا حسابَ خلفه،
                        //    والبحثُ عن رمزٍ لا وجودَ له يفتح حواراً فارغاً.
                        onSelectChanged: isTotal
                            ? null
                            : (_) => _openAccountLedger(row['code'] as String?),
                        cells: [
                          DataCell(Text(row['code'] ?? '', style: style)),
                          DataCell(Text(row['name'] ?? '', style: nameStyle)),
                          DataCell(Text(fmt(row['openingDebit'] as double), style: style)),
                          DataCell(Text(fmt(row['openingCredit'] as double), style: style)),
                          DataCell(Text(fmt(row['movementDebit'] as double), style: style)),
                          DataCell(Text(fmt(row['movementCredit'] as double), style: style)),
                          DataCell(Text(fmt(row['closingDebit'] as double), style: style)),
                          DataCell(Text(fmt(row['closingCredit'] as double), style: style)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// يفتح أستاذَ الحساب من سطرِ ميزان المراجعة.
  ///
  /// ⚠️ ورمزٌ لا يقابل حساباً **يُقال صراحةً** لا يُبتلَع: الميزانُ يُبنى من
  /// استعلامٍ مجمَّعٍ قد يحمل رمزاً حُذف حسابُه بعد الترحيل، ونقرةٌ لا تفعل
  /// شيئاً تبدو عطباً في التطبيق.
  Future<void> _openAccountLedger(String? code) async {
    if (code == null || code.isEmpty) return;
    final repo = ref.read(accountingRepositoryProvider);
    final account = await repo.getAccountByCode(code);
    if (!mounted) return;
    if (account == null) {
      AppToast.show(context, 'لا يوجد حسابٌ بالرمز «$code»',
          type: ToastType.warning);
      return;
    }
    showAccountLedger(context, repo, account);
  }

  Widget _buildIncomeStatementTab() {
    final repo = ref.read(reportingRepositoryProvider);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('income_${_refreshKey}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: repo.getIncomeStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;
        final netProfit = data['netProfit'] as double;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              _buildReportHeader(
                'قائمة الدخل للفترة من ${_fromDate.toString().split(' ')[0]} إلى ${_toDate.toString().split(' ')[0]}',
              ),
              // Revenue Section
              _buildSectionTitle('الإيرادات والمبيعات'),
              ...(data['revenueDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['amount']),
              ),
              const Divider(thickness: 2),
              _buildReportLine(
                'إجمالي الإيرادات',
                data['totalRevenue'],
                isBold: true,
              ),
              const SizedBox(height: 16),
              // COGS Section
              if ((data['totalCOGS'] as double) > 0) ...[
                _buildSectionTitle('تكلفة البضاعة المباعة'),
                ...(data['cogsDetails'] as List? ?? []).map(
                  (d) => _buildReportLine(d['name'], d['amount']),
                ),
                const Divider(),
                _buildReportLine(
                  'إجمالي تكلفة البضاعة المباعة',
                  data['totalCOGS'],
                  isBold: true,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _buildReportLine(
                    'مجمل الربح',
                    data['grossProfit'],
                    isBold: true,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Operating & Other Expenses
              _buildSectionTitle('المصاريف والتكاليف'),
              ...(data['expenseDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['amount']),
              ),
              const Divider(thickness: 2),
              _buildReportLine(
                'إجمالي المصاريف التشغيلية',
                data['totalExpenses'] as double,
                isBold: true,
              ),
              const SizedBox(height: 8),
              // Operating Profit (before depreciation)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildReportLine(
                  'الربح التشغيلي (قبل الإهلاك)',
                  data['operatingProfit'] as double,
                  isBold: true,
                ),
              ),
              const SizedBox(height: 16),
              // Item 10: Depreciation Section
              if ((data['totalDepreciation'] as double) > 0) ...[
                _buildSectionTitle('الإهلاك والاستهلاك (IAS 16)'),
                ...(data['depreciationDetails'] as List).map(
                  (d) => _buildReportLine(d['name'], d['amount']),
                ),
                const Divider(),
                _buildReportLine(
                  'إجمالي مصاريف الإهلاك',
                  data['totalDepreciation'] as double,
                  isBold: true,
                ),
                const SizedBox(height: 16),
              ],
              // البند 1 — «إيرادات/مصروفات أخرى» (غير تشغيلية). These were
              // computed but rendered NOWHERE, so the statement did not foot on
              // screen: the reader added Revenue − COGS − Expenses and got a
              // different number from the printed «صافي الربح». That is the
              // exact "can't reconcile by hand" complaint, so leaving them
              // hidden after re-classifying purchase discounts and cash
              // surpluses into this bucket would have made it worse.
              if ((data['otherIncome'] as double? ?? 0) != 0 ||
                  (data['otherExpense'] as double? ?? 0) != 0) ...[
                _buildSectionTitle('إيرادات ومصروفات أخرى (غير تشغيلية)'),
                ...((data['otherIncomeDetails'] as List?) ?? const []).map(
                  (d) => _buildReportLine(d['name'], d['amount']),
                ),
                ...((data['otherExpenseDetails'] as List?) ?? const []).map(
                  (d) => _buildReportLine(d['name'], -(d['amount'] as num)),
                ),
                const Divider(),
                _buildReportLine(
                  'صافي الإيرادات الأخرى',
                  (data['otherIncome'] as double? ?? 0) -
                      (data['otherExpense'] as double? ?? 0),
                  isBold: true,
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 16),
              // Net Profit
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: netProfit >= 0
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: netProfit >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
                child: _buildReportLine(
                  netProfit >= 0 ? 'صافي الربح' : 'صافي الخسارة',
                  netProfit.abs(),
                  isBold: true,
                  large: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBalanceSheetTab() {
    final repo = ref.read(reportingRepositoryProvider);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('balance_${_refreshKey}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: repo.getBalanceSheet(_toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              _buildReportHeader(
                'الميزانية العمومية كما في ${_toDate.toString().split(' ')[0]}',
              ),
              _buildSectionTitle('الأصول (Assets)'),
              ...(data['assetDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['balance']),
              ),
              const Divider(thickness: 2),
              _buildReportLine(
                'إجمالي الأصول',
                data['totalAssets'],
                isBold: true,
              ),
              const SizedBox(height: 24),
              // ─── Liabilities Section (IAS 1.54) ───
              _buildSectionTitle('الالتزامات (Liabilities)'),
              ...(data['liabilityDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['balance']),
              ),
              const Divider(),
              _buildReportLine(
                'إجمالي الالتزامات',
                data['totalLiabilities'],
                isBold: true,
              ),
              const SizedBox(height: 16),
              // ─── Equity Section (IAS 1.54) ───
              _buildSectionTitle('حقوق الملكية (Equity)'),
              ...(data['equityDetails'] as List).map(
                (d) => _buildReportLine(d['name'], d['balance']),
              ),
              const Divider(),
              _buildReportLine(
                'إجمالي حقوق الملكية',
                data['totalEquity'],
                isBold: true,
              ),
              const SizedBox(height: 16),
              const Divider(thickness: 2),
              _buildReportLine(
                'إجمالي الالتزامات وحقوق الملكية',
                data['totalLiabilities'] + data['totalEquity'],
                isBold: true,
              ),
              const SizedBox(height: 24),
              if (!data['isBalanced'])
                const Card(
                  color: Colors.redAccent,
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'تحذير: الميزانية غير متزنة! يرجى مراجعة القيود.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCashFlowTab() {
    final accountingRepo = ref.read(accountingRepositoryProvider);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('cashflow_${_refreshKey}_${_fromDate}_${_toDate}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: accountingRepo.getCashFlowStatement(_fromDate, _toDate, costCenterId: _selectedCostCenterId, branchId: _selectedBranchId, regionId: _selectedRegionId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;
        final op = data['operating'] as Map<String, dynamic>;
        final inv = data['investing'] as Map<String, dynamic>;
        final fin = data['financing'] as Map<String, dynamic>;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              _buildReportHeader(
                'قائمة التدفقات النقدية — IAS 7\nمن ${_fromDate.toString().split(' ')[0]} إلى ${_toDate.toString().split(' ')[0]}',
              ),
              const SizedBox(height: 8),

              // ─── Opening Balance ───
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildReportLine('الرصيد النقدي الافتتاحي', data['openingBalance'] as double, isBold: true),
              ),
              const SizedBox(height: 16),

              // ─── Operating Activities (IAS 7.14) ───
              _buildSectionTitle('أولاً: الأنشطة التشغيلية'),
              _buildReportLine('إيرادات المبيعات النقدية', (op['salesCash'] as num).toDouble()),
              _buildReportLine('متحصلات أخرى من العملاء', (op['receiptsFromCustomers'] as num).toDouble()),
              _buildReportLine('مدفوعات المشتريات', -(op['purchasesCash'] as num).toDouble()),
              _buildReportLine('مدفوعات للموردين', -(op['paymentsToSuppliers'] as num).toDouble()),
              _buildReportLine('الرواتب والأجور', -(op['salaries'] as num).toDouble()),
              _buildReportLine('المصاريف التشغيلية', -(op['expenses'] as num).toDouble()),
              const Divider(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: (op['net'] as num).toDouble() >= 0
                      ? AppColors.success.withValues(alpha: 0.06)
                      : AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildReportLine('صافي التدفق التشغيلي', (op['net'] as num).toDouble(), isBold: true),
              ),
              const SizedBox(height: 16),

              // ─── Investing Activities (IAS 7.16) ───
              _buildSectionTitle('ثانياً: الأنشطة الاستثمارية'),
              _buildReportLine('شراء أصول ثابتة', -(inv['assetPurchases'] as num).toDouble()),
              _buildReportLine('حصيلة بيع أصول', (inv['assetDisposals'] as num).toDouble()),
              const Divider(),
              _buildReportLine('صافي التدفق الاستثماري', (inv['net'] as num).toDouble(), isBold: true),
              const SizedBox(height: 16),

              // ─── Financing Activities (IAS 7.17) ───
              _buildSectionTitle('ثالثاً: الأنشطة التمويلية'),
              _buildReportLine('شيكات محصلة', (fin['checksCollected'] as num).toDouble()),
              _buildReportLine('شيكات مصدرة', -(fin['checksIssued'] as num).toDouble()),
              const Divider(),
              _buildReportLine('صافي التدفق التمويلي', (fin['net'] as num).toDouble(), isBold: true),
              const SizedBox(height: 24),

              // ─── Net Change & Closing ───
              const Divider(thickness: 2),
              _buildReportLine('صافي التغير في النقدية', (data['netChange'] as num).toDouble(), isBold: true),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary),
                ),
                child: _buildReportLine(
                  'الرصيد النقدي الختامي',
                  (data['closingBalance'] as num).toDouble(),
                  isBold: true,
                  large: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAgingReportTab() {
    final accountingRepo = ref.read(accountingRepositoryProvider);
    final future = _showReceivables
        ? accountingRepo.getAgedReceivables(
            _toDate,
            costCenterId: _selectedCostCenterId,
            branchId: _selectedBranchId,
            regionId: _selectedRegionId,
            allowedBranchIds: _allowedBranchIds,
          )
        : accountingRepo.getAgedPayables(
            _toDate,
            costCenterId: _selectedCostCenterId,
            branchId: _selectedBranchId,
            regionId: _selectedRegionId,
            allowedBranchIds: _allowedBranchIds,
          );

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(
        'aging_${_refreshKey}_${_showReceivables}_${_selectedCostCenterId}_${_selectedRegionId}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}',
      ),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsBold.warning, size: 48, color: AppColors.error.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text('خطأ في تحميل البيانات', style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(PhosphorIconsBold.arrowClockwise),
                  label: const Text('إعادة المحاولة'),
                  onPressed: () => setState(() => _refreshKey++),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;
        final currFmt = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);

        return Column(
          children: [
            // Toggle between receivables and payables
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildReportHeader(
                    _showReceivables ? 'تقادم الذمم المدينة (العملاء)' : 'تقادم الذمم الدائنة (الموردين)',
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('العملاء'), icon: Icon(PhosphorIconsBold.user, size: 16)),
                      ButtonSegment(value: false, label: Text('الموردين'), icon: Icon(PhosphorIconsBold.truck, size: 16)),
                    ],
                    selected: {_showReceivables},
                    onSelectionChanged: (v) => setState(() { _showReceivables = v.first; _refreshKey++; }),
                  ),
                ],
              ),
            ),
            if (data.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsBold.checkCircle, size: 64, color: AppColors.success.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text(
                        _showReceivables ? 'لا توجد ذمم مدينة مستحقة' : 'لا توجد ذمم دائنة مستحقة',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 20,
                      columns: const [
                        DataColumn(label: Text('الطرف', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('إجمالي الرصيد', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                        DataColumn(label: Text('0-30 يوم', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                        DataColumn(label: Text('31-60 يوم', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                        DataColumn(label: Text('61-90 يوم', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                        DataColumn(label: Text('+90 يوم', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)), numeric: true),
                      ],
                      rows: data.map((row) {
                        final over90 = (row['over90'] as num?)?.toDouble() ?? 0;
                        return DataRow(cells: [
                          DataCell(Text(row['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500))),
                          DataCell(Text(currFmt.format(row['totalBalance'] ?? 0), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                          DataCell(Text(currFmt.format(row['current'] ?? 0), style: const TextStyle(fontFamily: 'monospace'))),
                          DataCell(Text(currFmt.format(row['days31_60'] ?? 0), style: const TextStyle(fontFamily: 'monospace'))),
                          DataCell(Text(currFmt.format(row['days61_90'] ?? 0), style: const TextStyle(fontFamily: 'monospace'))),
                          DataCell(Text(
                            currFmt.format(over90),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: over90 > 0 ? FontWeight.bold : FontWeight.normal,
                              color: over90 > 0 ? Colors.red : null,
                            ),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildReportHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildReportLine(
    String label,
    dynamic amount, {
    bool isBold = false,
    bool large = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: large ? 18 : 14,
            ),
          ),
          Text(
            '${(amount as double).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: large ? 18 : 14,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tab 6: مطابقة الترحيل (Posting Reconciliation)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildReconciliationTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('reconciliation_${_refreshKey}_${_fromDate}_${_toDate}_${_selectedBranchId}_${_allowedBranchIds?.join('-')}'),
      future: ref.read(accountingRepositoryProvider)
          .getPostingReconciliation(_fromDate, _toDate, branchId: _selectedBranchId, allowedBranchIds: _allowedBranchIds),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsBold.warning, size: 48, color: AppColors.error.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text('خطأ في تحميل البيانات', style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Text('${snapshot.error}', style: const TextStyle(fontSize: 11, color: Colors.red)),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(PhosphorIconsBold.arrowClockwise),
                  label: const Text('إعادة المحاولة'),
                  onPressed: () => setState(() => _refreshKey++),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: ShimmerLoading.list(itemCount: 6),
          );
        }
        final data = snapshot.data!;
        if (data.isEmpty && !ref.read(isClientModeProvider)) {
          return const Center(child: Text('لا توجد فواتير في هذه الفترة'));
        }

        // Summary stats
        final matched = data.where((d) => d['statusCode'] == 'matched').length;
        final missing = data.where((d) => d['statusCode'] == 'missing').length;
        final draft = data.where((d) => d['statusCode'] == 'draft').length;
        final mismatch = data.where((d) => d['statusCode'] == 'mismatch').length;
        final orphan = data.where((d) => d['statusCode'] == 'orphan').length;

        return Column(
          children: [
            // ── Sync Outbox Panel (Client mode only) ──────────────────────
            if (NetworkService.instance.isClient) // keep-isClient: outbox
              _buildSyncOutboxPanel(),
            // Summary Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _reconcileStat('مطابق', matched, Colors.green),
                  _reconcileStat('غير مرحل', missing, Colors.red),
                  _reconcileStat('مسودة', draft, Colors.orange),
                  _reconcileStat('فرق قيمة', mismatch, Colors.purple),
                  _reconcileStat('قيد يتيم', orphan, Colors.blueGrey),
                ],
              ),
            ),
            // Data Table
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 20,
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    dataTextStyle: const TextStyle(fontSize: 11),
                    columns: const [
                      DataColumn(label: Text('النوع')),
                      DataColumn(label: Text('رقم الفاتورة')),
                      DataColumn(label: Text('التاريخ')),
                      DataColumn(label: Text('المبلغ'), numeric: true),
                      DataColumn(label: Text('رقم القيد')),
                      DataColumn(label: Text('مدين قيد'), numeric: true),
                      DataColumn(label: Text('دائن قيد'), numeric: true),
                      DataColumn(label: Text('الحالة')),
                    ],
                    rows: data.map((row) {
                      final statusCode = row['statusCode'] as String;
                      final statusColor = switch (statusCode) {
                        'matched' => Colors.green,
                        'missing' => Colors.red,
                        'draft' => Colors.orange,
                        'mismatch' => Colors.purple,
                        'orphan' => Colors.blueGrey,
                        _ => Colors.grey,
                      };
                      final dateVal = row['invoiceDate'];
                      String dateStr;
                      if (dateVal is DateTime) {
                        dateStr = DateFormat('yyyy-MM-dd').format(dateVal);
                      } else if (dateVal is String) {
                        dateStr = dateVal.length > 10 ? dateVal.substring(0, 10) : dateVal;
                      } else {
                        dateStr = '-';
                      }
                      return DataRow(
                        color: WidgetStateProperty.resolveWith((states) {
                          if (statusCode == 'missing') return Colors.red.withValues(alpha: 0.08);
                          if (statusCode == 'orphan') return Colors.blue.withValues(alpha: 0.08);
                          if (statusCode == 'mismatch') return Colors.purple.withValues(alpha: 0.08);
                          return null;
                        }),
                        cells: [
                          DataCell(Text(row['source'] as String)),
                          DataCell(Text('${row['invoiceNumber']}')),
                          DataCell(Text(dateStr)),
                          DataCell(Text(NumberFormat('#,##0.00').format(row['invoiceTotal'] ?? 0))),
                          DataCell(Text(row['jeNumber']?.toString() ?? '-')),
                          DataCell(Text(NumberFormat('#,##0.00').format(row['jeDebit'] ?? 0))),
                          DataCell(Text(NumberFormat('#,##0.00').format(row['jeCredit'] ?? 0))),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              row['status'] as String,
                              style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Sync Outbox Panel — embedded in مطابقة الترحيل, visible in client mode only
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSyncOutboxPanel() {
    final syncRepo = ref.watch(syncRepositoryProvider);
    final syncState = ref.watch(syncWorkerProvider);
    return StreamBuilder<List<SyncOutboxItem>>(
      stream: syncRepo.watchPendingItems(),
      builder: (context, snapshot) {
        final allItems = snapshot.data ?? [];
        final pending = allItems.where((i) => i.status == 'pending').toList();
        final failed = allItems.where((i) => i.status == 'dead_letter' || i.status == 'failed').toList();
        final total = pending.length + failed.length;
        if (total == 0 && !syncState.isSyncing) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: failed.isNotEmpty
                ? AppColors.error.withValues(alpha: 0.05)
                : AppColors.warning.withValues(alpha: 0.05),
            border: Border.all(
              color: failed.isNotEmpty
                  ? AppColors.error.withValues(alpha: 0.3)
                  : AppColors.warning.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: failed.isNotEmpty,
              leading: Icon(
                failed.isNotEmpty
                    ? PhosphorIconsBold.cloudSlash
                    : PhosphorIconsBold.cloudArrowUp,
                color: failed.isNotEmpty ? AppColors.error : AppColors.warning,
              ),
              title: Row(
                children: [
                  Text(
                    'قائمة انتظار المزامنة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: failed.isNotEmpty ? AppColors.error : AppColors.warning,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (pending.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${pending.length} بانتظار',
                          style: const TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 4),
                  if (failed.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${failed.length} فشل نهائي',
                          style: const TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (syncState.isSyncing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton.icon(
                      onPressed: () =>
                          ref.read(syncWorkerProvider.notifier).processOutbox(),
                      icon: const Icon(PhosphorIconsBold.cloudArrowUp, size: 14),
                      label: const Text('مزامنة الكل', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    ),
                  const Icon(Icons.expand_more),
                ],
              ),
              children: [
                const Divider(height: 1),
                ...allItems.where((i) => i.status != 'synced').map((item) {
                  final isDeadLetter = item.status == 'dead_letter';
                  final isFailed = isDeadLetter || item.status == 'failed' || item.attempts > 0;
                  final color = isDeadLetter
                      ? AppColors.error
                      : (isFailed ? AppColors.warning : Colors.grey.shade600);

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(_syncTableIcon(item.targetTable), color: color, size: 14),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_syncTableTitle(item.targetTable)} #${item.recordId}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isDeadLetter)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                            ),
                            child: const Text('فشل نهائي',
                                style: TextStyle(fontSize: 9, color: AppColors.error, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_syncOperationTitle(item.operation)} | المحاولات: ${item.attempts}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                        if (item.lastError != null)
                          Text(
                            item.lastError!.replaceAll('DEAD_LETTER: ', ''),
                            style: TextStyle(
                              fontSize: 10,
                              color: isDeadLetter ? AppColors.error : AppColors.warning,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 16, color: AppColors.info),
                          tooltip: 'إعادة محاولة',
                          onPressed: () async {
                            await syncRepo.retryItem(item.id);
                            ref.read(syncWorkerProvider.notifier).processOutbox();
                          },
                        ),
                        IconButton(
                          icon: const Icon(PhosphorIconsBold.trash, size: 16, color: AppColors.error),
                          tooltip: 'حذف',
                          onPressed: () => syncRepo.deleteItem(item.id),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  String _syncTableTitle(String table) {
    switch (table) {
      case 'sales':
      case 'sales_invoices': return 'فاتورة مبيعات';
      case 'sales_returns': return 'مرتجع مبيعات';
      case 'purchase_invoices':
      case 'purchases': return 'فاتورة مشتريات';
      case 'shifts': return 'وردية';
      case 'expenses': return 'مصروف';
      case 'receipts': return 'قبض';
      case 'held_orders': return 'طلب محفوظ';
      case 'parties': return 'عميل/مورد';
      case 'products': return 'صنف';
      case 'users': return 'مستخدم';
      default: return table;
    }
  }

  IconData _syncTableIcon(String table) {
    switch (table) {
      case 'sales':
      case 'sales_invoices':
      case 'sales_returns': return PhosphorIconsBold.receipt;
      case 'purchases':
      case 'purchase_invoices': return PhosphorIconsBold.truck;
      case 'shifts': return PhosphorIconsBold.clock;
      case 'expenses': return PhosphorIconsBold.arrowDown;
      case 'receipts': return PhosphorIconsBold.arrowUp;
      case 'users': return PhosphorIconsBold.user;
      default: return PhosphorIconsBold.shoppingBag;
    }
  }

  String _syncOperationTitle(String op) {
    switch (op) {
      case 'insert': return 'إضافة';
      case 'update': return 'تعديل';
      case 'delete': return 'حذف';
      case 'open': return 'فتح';
      case 'close': return 'إغلاق';
      default: return op;
    }
  }

  Widget _reconcileStat(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  Future<void> _showRemediationDialog() async {
    final accounting = ref.read(accountingServiceProvider);

    // Dry-run preview of the branch cost-center repair (read-only) so the
    // operator sees exactly how many entries would move before committing.
    BranchCostCenterRepairReport? preview;
    try {
      preview = await accounting.repairBranchCostCenters(dryRun: true);
    } catch (_) {
      preview = null;
    }
    if (!mounted) return;

    final String branchLine;
    if (preview == null) {
      branchLine = 'تعذّر حساب معاينة إصلاح مراكز الفروع.';
    } else if (preview.hasWork) {
      branchLine =
          'قيود آلية مسجّلة على «عام» وتخص فروعاً لها مركز تكلفة خاص: '
          '${preview.affectedEntries} قيد / ${preview.affectedLines} سطر — '
          'ستُنقل إلى مركز تكلفة الفرع.';
    } else {
      branchLine = 'لا توجد قيود بحاجة لإعادة التوزيع على مراكز الفروع.';
    }

    // ⚠️ يبقى `showDialog<bool>` بـ`ok == true` لا `ok != false`: الإغلاقُ
    //    العرَضيَّ يُرجع `null`، وهذا الحوارُ يبدأ عمليّةً تمسّ بياناتٍ —
    //    فالافتراضُ **الرفض**.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PicPosDialog(
        icon: PhosphorIconsBold.magicWand,
        accent: AppColors.warning,
        title: 'إصلاح فروقات التقارير والمراكز',
        subtitle: 'خطوتان تعيدان تصنيفَ مراكز التكلفة — بلا مساسٍ بالمبالغ',
        width: 560,
        onCancel: () => Navigator.pop(ctx, false),
        primaryAction: PicPosDialogAction(
          label: 'بدء الإصلاح',
          icon: PhosphorIconsBold.magicWand,
          color: AppColors.warning,
          onPressed: () => Navigator.pop(ctx, true),
        ),
        body: [
          const Text('١) تعبئة مراكز التكلفة للأسطر التاريخية من رؤوس القيود.'),
          // ⚠️ سطرُ المعاينة: هو **كلُّ** ما يعرفه المشغّلُ عن حجم ما
          //    سيتحرّك قبل أن يضغط. ولا يُختصَر ولا يُطوى.
          Text('٢) $branchLine'),
          const PicPosDialogBanner(
            icon: PhosphorIconsBold.shieldCheck,
            color: AppColors.success,
            text: 'العملية آمنة ولا تغيّر أي مبالغ مدينة/دائنة — تعيد فقط تصنيف مركز التكلفة.',
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        // 1) Backfill line-level cost centers from headers (existing behaviour).
        await accounting.remediateHistoricalData();
        // 2) Re-attribute auto-posted «عام» entries to their branch centre.
        final res = await accounting.repairBranchCostCenters(dryRun: false);
        if (mounted) {
          final moved = res.applied && res.hasWork
              ? ' — نُقل ${res.affectedEntries} قيد إلى مراكز الفروع'
              : '';
          AppToast.show(context, 'تمت عملية الإصلاح بنجاح$moved. يرجى تحديث التقارير.',
              type: ToastType.success);
          setState(() => _refreshKey++);
        }
      } catch (e) {
        if (mounted) AppToast.show(context, 'خطأ أثناء الإصلاح: $e', type: ToastType.error);
      }
    }
  }
}