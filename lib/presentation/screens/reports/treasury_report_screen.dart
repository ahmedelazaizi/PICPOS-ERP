// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import 'report_export_guard.dart';
import 'report_scaffold.dart';

import '../../../domain/models/safe_running_balance.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/report_components.dart';
import '../../widgets/report_filter_bar.dart';
import '../../../services/invoice_generator.dart';
import '../../../../../../core/constants/app_constants.dart';
import '../../widgets/branch_warehouse_filter.dart';

class TreasuryReportScreen extends ConsumerStatefulWidget {
  const TreasuryReportScreen({super.key});

  @override
  ConsumerState<TreasuryReportScreen> createState() =>
      _TreasuryReportScreenState();
}

class _TreasuryReportScreenState extends ConsumerState<TreasuryReportScreen> {
  // Spec 065: default range is full-day-inclusive [00:00, 23:59:59.999] (D3-006).
  DateTimeRange _dateRange = DateRangeFilter.normalizeRange(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
    DateTime.now(),
  );

  bool _isLoading = false;
  TreasuryAnalytics? _analytics;
  List<SafeTransactionData> _transactions = [];

  /// رصيدُ الخزائن المشمولة قبل بداية النافذة — مرساةُ عمود «الرصيد».
  double _openingBalance = 0;

  /// `{معرّفُ الحركة: الرصيدُ الجاري بعدها}` — فارغةٌ حين يكون فلترُ المستخدم
  /// فعّالاً، لأن الصفوفَ عندئذٍ مجموعةٌ جزئيةٌ لا يصحّ المشيُ فوقها.
  Map<int, double> _runningBalances = const {};
  List<UserTreasurySummary> _perUserSummary = [];
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);

  // User filter state
  int? _selectedUserId;
  List<User> _users = [];
  // Cost center filter
  int? _selectedCostCenterId;
  List<CostCenter> _costCenters = [];
  // Safe filter
  int? _selectedSafeId;
  List<SafeData> _safes = [];
  int? _selectedRegionId;
  int? _selectedBranchId;
  int? _selectedWarehouseId;
  List<int>? _branchSafeIds;

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // Feature 058: seed _selectedBranchId from the device's active branch
      // BEFORE the first data fetch (FR-001 + FR-002).
      if (_selectedBranchId == null) {
        final activeBranchId = await ref.read(activeBranchIdProvider.future);
        if (!mounted) return;
        if (activeBranchId != null) {
          setState(() => _selectedBranchId = activeBranchId);
          // H13 · بذرُ الاسم وحدَه كان يجعل العنوانَ يقول فرعاً والأرقامَ
          // تقول شركة. الحلُّ لازم يسبق أوّلَ `_loadData` تحت.
          await _resolveBranchSafeIds(activeBranchId);
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
      await _loadUsers();
      await _loadFilters();
      _loadData();
      // #Forensic Log: Report View
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير الخزينة');
      } catch (_) {}
    });
  }

  /// H13 · يحلّ خزائنَ الفرع المختار.
  ///
  /// كان هذا الجسمُ داخل `onBranchChanged` وحدَه، بينما `initState` يبذر
  /// `_selectedBranchId` من فرع الجهاز **بلا** أن يحلّه. فعلى أوّل تحميل:
  /// القائمةُ تُظهر اسمَ الفرع، و`_branchSafeIds` تظل `null`، والاستعلامُ
  /// يقرأ **كلَّ الفروع**. العنوانُ يقول فرعاً والأرقامُ تقول شركة —
  /// والمستخدمُ لا يملك ما يكشف الفرق.
  ///
  /// (‏`allowedBranchIds` سقفُ **صلاحية** لا فلترُ عرض: صاحبُ الوصول الكامل
  ///  يأخذ `null` فلا يحدّ شيئاً.)
  ///
  /// Spec 079b b142 hotfix: نقرأ من الـDAO مباشرةً بدل المزوّد — نفسُ مشكلة
  /// التخلّص في `regionBranchesProvider`.
  Future<void> _resolveBranchSafeIds(int? branchId) async {
    if (branchId != null) {
      final db = ref.read(databaseProvider);
      final rows = await (db.select(db.safes)
            ..where((s) => s.branchId.equals(branchId)))
          .get();
      _branchSafeIds = rows.map((s) => s.id).toList();
    } else if (_selectedRegionId == null) {
      _branchSafeIds = null;
    }
  }

  Future<void> _loadUsers() async {
    final repo = ref.read(reportingRepositoryProvider);
    final usersWithRoles = await repo.watchAllUsers().first;
    setState(() => _users = usersWithRoles.map((dynamic ur) => ur.user as User).toList());
  }

  Future<void> _loadFilters() async {
    final accountingRepo = ref.read(accountingRepositoryProvider);
    final treasuryRepo = ref.read(treasuryRepositoryProvider);
    final cc = await accountingRepo.getActiveCostCenters();
    // Spec 151 D-01: scope the "الصندوق" dropdown to the user's branches too, so
    // a branch-scoped manager doesn't see foreign branches' safe names/balances
    // in the picker. The financial queries are already capped, so this only
    // closes the master-data name leak. BranchScope.isAllowed keeps NULL-branch
    // (shared) safes visible and lets full-access users through unchanged.
    final scope = await ref.read(branchScopeProvider.future);
    final safes = (await treasuryRepo.getSafesList())
        .where((s) => scope.isAllowed(s.branchId))
        .toList();
    setState(() {
      _costCenters = cc;
      _safes = safes;
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(reportingRepositoryProvider);
      // Spec 151 D-01: authoritative branch-scope cap. `_branchSafeIds` is only
      // populated when the user manually picks a branch in the dropdown, so on
      // first load it is null and the DAO would aggregate EVERY branch's
      // vouchers — a cross-branch financial leak for a branch-scoped manager
      // holding reportsTreasury. Resolve the user's scope here and pass it so
      // the query is capped server-side regardless of the safe-id filter.
      // branchScopeProvider is a plain (non-autoDispose) FutureProvider, so
      // reading `.future` from this callback is safe. Full-access users
      // (admin / userId=1 / mirror / cross-branch-elevated) get null → no cap.
      final scope = await ref.read(branchScopeProvider.future);
      final allowedBranchIds =
          scope.hasFullAccess ? null : scope.allowedBranchIds;
      final analytics = await repo.getTreasuryReportAnalytics(
        _dateRange.start,
        _dateRange.end,
        // H12 · نفسُ فلتر الجدول تحتها بالضبط — بدونه تتحرّك الصفوفُ وتبقى
        // البطاقاتُ على إجمالي كلّ المستخدمين: ١٬٤٠٠ فوق و١٬٠٠٠ تحت.
        userId: _selectedUserId,
        costCenterId: _selectedCostCenterId,
        safeId: _selectedSafeId,
        safeIds: _branchSafeIds,
        allowedBranchIds: allowedBranchIds,
      );
      final transactions = await repo.getTransactionsByDateRange(
        _dateRange.start,
        _dateRange.end,
        userId: _selectedUserId,
        costCenterId: _selectedCostCenterId,
        safeId: _selectedSafeId,
        safeIds: _branchSafeIds,
        allowedBranchIds: allowedBranchIds,
      );
      final perUser = await repo.getPerUserTreasurySummary(
        _dateRange.start,
        _dateRange.end,
        safeId: _selectedSafeId,
        costCenterId: _selectedCostCenterId,
        safeIds: _branchSafeIds,
        allowedBranchIds: allowedBranchIds,
      );

      // §٣-ج — «الرصيد» رصيداً جارياً على النافذة المفلترة.
      //
      // العمودُ كان يعرض `balanceAfter` المخزَّن: لقطةٌ وقتَ الإدراج لا تعني
      // شيئاً تحت التصفية، وتصير خاطئةً صامتةً بعد إلغاء حركةٍ سابقة.
      //
      // ⚠️ وفلترُ **المستخدم** يصفّي الصفوفَ ولا يملك رصيداً: الصفوفُ
      // المعروضةُ عندئذٍ مجموعةٌ جزئيةٌ من حركات الخزنة، فأيُّ مشيٍ فوقها
      // يعطي رقماً منحرفاً. فيُخفى العمودُ بدل أن يكذب.
      final rows = List<SafeTransactionData>.from(transactions);
      var opening = 0.0;
      var running = const <int, double>{};
      if (_selectedUserId == null) {
        opening = await repo.getSafeOpeningBalance(
          _dateRange.start,
          safeId: _selectedSafeId,
          costCenterId: _selectedCostCenterId,
          safeIds: _branchSafeIds,
          allowedBranchIds: allowedBranchIds,
        );
        running = runningBalances(
          // تصل من الاستعلام **الأحدثَ أولاً**؛ الدالّةُ تتولّى الاتجاه.
          rowsNewestFirst: [
            for (final t in rows)
              SafeMovementRow(
                id: t.id,
                type: t.transactionType,
                amount: t.amount,
              ),
          ],
          openingBalance: opening,
        );
      }
      if (!mounted) return;

      setState(() {
        _analytics = analytics;
        _transactions = rows;
        _openingBalance = opening;
        _runningBalances = running;
        _perUserSummary = perUser;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getUserName(int? userId) {
    if (userId == null) return '-';
    final user = _users.where((u) => u.id == userId).firstOrNull;
    return user?.displayName ?? 'مستخدم #$userId';
  }

  @override
  Widget build(BuildContext context) {
    return reportScaffold(
      context: context,
      title: 'تقرير حركة الخزينة والتدفق النقدي',
      subtitle: 'الوارد والمنصرف وأرصدةُ الخزائن في المدى المحدَّد',
      icon: PhosphorIconsBold.vault,
      actions: [
            buildReportExportAction(onExport: _exportToExcel),
            IconButton(
              onPressed: _printReport,
              icon: const Icon(PhosphorIconsBold.printer),
              tooltip: 'طباعة/PDF',
            ),
            const SizedBox(width: 8),
          ],
        body: Column(
          children: [
            // Spec 076: unified two-row filter bar.
            ReportFilterBar(
              selectedRange: _dateRange,
              onRangeChanged: (start, end) {
                setState(
                  () => _dateRange = DateTimeRange(start: start, end: end),
                );
                _loadData();
              },
              trailing: [
                SizedBox(
                  width: 240,
                  child: Autocomplete<User>(
                    optionsBuilder: (textValue) {
                      if (textValue.text.isEmpty) return _users;
                      return _users.where(
                        (u) =>
                            u.displayName.toLowerCase().contains(
                              textValue.text.toLowerCase(),
                            ) ||
                            u.username.toLowerCase().contains(
                              textValue.text.toLowerCase(),
                            ),
                      );
                    },
                    displayStringForOption: (u) => u.displayName,
                    initialValue: _selectedUserId != null
                        ? TextEditingValue(
                            text:
                                _users
                                    .where((u) => u.id == _selectedUserId)
                                    .firstOrNull
                                    ?.displayName ??
                                '',
                          )
                        : null,
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'المستخدم',
                              hintText: 'ابحث عن مستخدم...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              prefixIcon: const Icon(
                                PhosphorIconsBold.user,
                                size: 18,
                              ),
                              suffixIcon: _selectedUserId != null
                                  ? IconButton(
                                      icon: const Icon(
                                        PhosphorIconsBold.x,
                                        size: 14,
                                      ),
                                      onPressed: () {
                                        controller.clear();
                                        setState(
                                          () => _selectedUserId = null,
                                        );
                                        _loadData();
                                      },
                                    )
                                  : null,
                            ),
                          );
                        },
                    onSelected: (user) {
                      setState(() => _selectedUserId = user.id);
                      _loadData();
                    },
                  ),
                ),
                if (_costCenters.isNotEmpty)
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      initialValue: _selectedCostCenterId,
                      decoration: InputDecoration(
                        labelText: 'مركز التكلفة',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('الكل', style: TextStyle(fontSize: 13))),
                        ..._costCenters.map((cc) => DropdownMenuItem<int?>(
                              value: cc.id,
                              child: Text(cc.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedCostCenterId = val);
                        _loadData();
                      },
                    ),
                  ),
                if (_safes.isNotEmpty)
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      initialValue: _selectedSafeId,
                      decoration: InputDecoration(
                        labelText: 'الصندوق',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('الكل', style: TextStyle(fontSize: 13))),
                        ..._safes.map((s) => DropdownMenuItem<int?>(
                              value: s.id,
                              child: Text(s.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedSafeId = val);
                        _loadData();
                      },
                    ),
                  ),
                BranchWarehouseFilterBar(
                  selectedRegionId: _selectedRegionId,
                  selectedBranchId: _selectedBranchId,
                  selectedWarehouseId: _selectedWarehouseId,
                  onRegionChanged: (v) async {
                    _selectedRegionId = v;
                    _selectedBranchId = null;
                    _selectedWarehouseId = null;
                    if (v != null) {
                      try {
                        // Spec 079b b142 hotfix: bypass `regionBranchesProvider`
                        // and `branchSafeIdsProvider` — both are
                        // autoDispose.family providers whose `.future`
                        // getter throws "disposed during loading" when
                        // read transiently, silently zeroing the safe-id
                        // resolution. Direct DAO access has no lifecycle.
                        final db = ref.read(databaseProvider);
                        final regionBranches = await db.getBranchesByRegion(v);
                        final branchIds =
                            regionBranches.map((b) => b.id).toList();
                        List<int> allSafeIds = [];
                        if (branchIds.isNotEmpty) {
                          final rows = await (db.select(db.safes)
                                ..where((s) => s.branchId.isIn(branchIds)))
                              .get();
                          allSafeIds = rows.map((s) => s.id).toList();
                        }
                        _branchSafeIds = allSafeIds.toSet().toList();
                        // Spec 079b (B2): surface "region resolves to no
                        // safes" — could mean region has no branches OR
                        // branches have no safes. Either way operator
                        // needs to know before the empty table misleads.
                        if (_branchSafeIds!.isEmpty) {
                          unawaited(DiagnosticLogger.log(
                            'FILTER-WARN',
                            'Region $v selected on treasury report but no '
                            'safes resolved (region has '
                            '${regionBranches.length} branch(es)). '
                            'Check region→branch→safe links.',
                          ));
                        }
                      } catch (e) {
                        _branchSafeIds = null;
                      }
                    } else {
                      _branchSafeIds = null;
                    }
                    _loadData();
                  },
                  onBranchChanged: (v) async {
                    _selectedBranchId = v;
                    _selectedWarehouseId = null;
                    await _resolveBranchSafeIds(v);
                    _loadData();
                  },
                  onWarehouseChanged: (v) {
                    setState(() => _selectedWarehouseId = v);
                    _loadData();
                  },
                ),
              ],
            ),

            Expanded(
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: ShimmerLoading.list(itemCount: 6),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_analytics != null)
                            Row(
                              children: [
                                Expanded(
                                  child: ReportKpiCard(
                                    title: 'رصيد الخزينة الحالي',
                                    value:
                                        '${_currencyFormat.format(_analytics!.totalBalance)} ${AppConstants.currencySymbolEn}',
                                    icon: PhosphorIconsBold.bank,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ReportKpiCard(
                                    title: 'إجمالي المقبوضات',
                                    value:
                                        '${_currencyFormat.format(_analytics!.totalReceipts)} ${AppConstants.currencySymbolEn}',
                                    icon: PhosphorIconsBold.arrowDownLeft,
                                    color: AppColors.success,
                                    subtitle: 'خلال الفترة المحددة',
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ReportKpiCard(
                                    title: 'إجمالي المدفوعات',
                                    value:
                                        '${_currencyFormat.format(_analytics!.totalPayments)} ${AppConstants.currencySymbolEn}',
                                    icon: PhosphorIconsBold.arrowUpRight,
                                    color: AppColors.error,
                                    subtitle:
                                        'صافي التدفق: ${_currencyFormat.format(_analytics!.netFlow)}',
                                  ),
                                ),
                              ],
                            ),

                          // ===== Per-User Breakdown =====
                          if (_perUserSummary.isNotEmpty) ...[
                            const SizedBox(height: 32),
                            Text(
                              'تقرير حسب المستخدم',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: _perUserSummary.map((us) {
                                final userName = _getUserName(us.userId);
                                final isPositive = us.netFlow >= 0;
                                return SizedBox(
                                  width: 280,
                                  child: Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: AppColors.border.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  PhosphorIconsBold.user,
                                                  color: AppColors.primary,
                                                  size: 18,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  userName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      (isPositive
                                                              ? AppColors
                                                                    .success
                                                              : AppColors.error)
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  '${us.transactionCount} عملية',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isPositive
                                                        ? AppColors.success
                                                        : AppColors.error,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          _UserStatRow(
                                            label: 'مقبوضات',
                                            value: _currencyFormat.format(
                                              us.totalReceipts,
                                            ),
                                            color: AppColors.success,
                                          ),
                                          const SizedBox(height: 4),
                                          _UserStatRow(
                                            label: 'مدفوعات',
                                            value: _currencyFormat.format(
                                              us.totalPayments,
                                            ),
                                            color: AppColors.error,
                                          ),
                                          const Divider(height: 16),
                                          _UserStatRow(
                                            label: 'صافي التدفق',
                                            value:
                                                '${isPositive ? "+" : ""}${_currencyFormat.format(us.netFlow)} ${AppConstants.currencySymbolEn}',
                                            color: isPositive
                                                ? AppColors.success
                                                : AppColors.error,
                                            isBold: true,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],

                          const SizedBox(height: 32),

                          Text(
                            'سجل العمليات المالية',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.titleLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: AppColors.border),
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: DataTable(
                                columns: [
                                  const DataColumn(label: Text('رقم السند')),
                                  const DataColumn(label: Text('التاريخ')),
                                  const DataColumn(label: Text('الصندوق')),
                                  const DataColumn(label: Text('النوع')),
                                  const DataColumn(label: Text('الفئة')),
                                  const DataColumn(label: Text('المبلغ')),
                                  // الرصيدُ الافتتاحيُّ معلنٌ في العنوان:
                                  // عمودٌ جارٍ بلا مرساةٍ ظاهرةٍ لا يمكن
                                  // للمستخدم أن يتحقّق من أوّل صفٍّ فيه.
                                  DataColumn(
                                    label: Text(
                                      _runningBalances.isEmpty
                                          ? 'الرصيد'
                                          : 'الرصيد (افتتاحي: '
                                              '${_currencyFormat.format(_openingBalance)})',
                                    ),
                                  ),
                                  const DataColumn(label: Text('المستخدم')),
                                  const DataColumn(label: Text('البيان')),
                                ],
                                rows: _transactions.map((t) {
                                  final isReceipt =
                                      t.transactionType == 'receipt';
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(t.voucherNumber)),
                                      DataCell(
                                        Text(_dateFormat.format(t.createdAt)),
                                      ),
                                      // GAP-12: Safe name column
                                      DataCell(Text(
                                        _safes.where((s) => s.id == t.safeId).firstOrNull?.name ?? '-',
                                      )),
                                      DataCell(
                                        Text(
                                          isReceipt ? 'قبض' : 'صرف',
                                          style: TextStyle(
                                            color: isReceipt
                                                ? AppColors.success
                                                : AppColors.error,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(t.category)),
                                      DataCell(
                                        Text(
                                          '${isReceipt ? "+" : "-"}${_currencyFormat.format(t.amount)}',
                                          style: TextStyle(
                                            color: isReceipt
                                                ? AppColors.success
                                                : AppColors.error,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          // مشيٌ فوق الرصيد الافتتاحي للنافذة.
                                          // و«—» حين يُخفى (فلترُ المستخدم):
                                          // لا رقمَ خيرٌ من رقمٍ منحرف.
                                          _runningBalances.containsKey(t.id)
                                              ? _currencyFormat.format(
                                                  _runningBalances[t.id])
                                              : '—',
                                        ),
                                      ),
                                      DataCell(Text(_getUserName(t.userId))),
                                      DataCell(Text(t.description ?? '-')),
                                    ],
                                  );
                                }).whereType<DataRow>().toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
    );
  }

  Future<void> _exportToExcel() async {
    final service = ref.read(excelServiceProvider);

    // Include per-user summary rows at the top
    final List<List<dynamic>> allRows = [];

    if (_perUserSummary.isNotEmpty) {
      allRows.add(['تقرير حسب المستخدم', '', '', '', '', '', '', '']);
      allRows.add([
        'المستخدم',
        'مقبوضات',
        'مدفوعات',
        'صافي',
        'عدد العمليات',
        '',
        '',
        '',
      ]);
      for (final us in _perUserSummary) {
        allRows.add([
          _getUserName(us.userId),
          us.totalReceipts,
          us.totalPayments,
          us.netFlow,
          us.transactionCount,
          '',
          '',
          '',
        ]);
      }
      allRows.add(['', '', '', '', '', '', '', '']);
    }

    // مرساةُ العمود الجاري — بدونها لا يمكن التحقّقُ من أوّل صفّ.
    if (_runningBalances.isNotEmpty) {
      allRows.add([
        '',
        '',
        '',
        'رصيد افتتاحي',
        '',
        _openingBalance,
        '',
        'الرصيد قبل بداية الفترة',
      ]);
    }

    for (final t in _transactions) {
      allRows.add([
        t.voucherNumber,
        _dateFormat.format(t.createdAt),
        t.transactionType == 'receipt' ? 'قبض' : 'صرف',
        t.category,
        t.amount,
        // نفسُ عمود الشاشة: مشيٌ فوق الرصيد الافتتاحي، و«—» حين يُخفى.
        // تصديرُ اللقطة المخزَّنة هنا كان يخالف ما يراه المستخدمُ فوقه.
        _runningBalances.containsKey(t.id) ? _runningBalances[t.id]! : '—',
        _getUserName(t.userId),
        t.description ?? '-',
      ]);
    }

    final path = await service.exportReport(
      periodFrom: _dateRange.start,
      periodTo: _dateRange.end,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
      title: 'تقرير الخزينة',
      headers: [
        'رقم السند',
        'التاريخ',
        'النوع',
        'الفئة',
        'المبلغ',
        'الرصيد بعد',
        'المستخدم',
        'البيان',
      ],
      rows: allRows,
    );

    if (path != null && mounted) {
      AppToast.show(
        context,
        'تم تصدير التقرير بنجاح: $path',
        type: ToastType.success,
      );
    }
  }

  Future<void> _printReport() async {
    if (_analytics == null) return;

      // GAP-15: Use actual company name from settings instead of hardcoded value
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final receiptSettings = await settingsRepo.getReceiptSettings();
      final companyName = receiptSettings['companyName'] as String? ?? 'الشركة';

      await InvoiceGenerator.printTreasuryReport(
        transactions: _transactions,
        openingBalance: _analytics!.openingBalance,
        totalIn: _analytics!.totalIn,
        totalOut: _analytics!.totalOut,
        closingBalance: _analytics!.closingBalance,
        fromDate: _dateRange.start,
        toDate: _dateRange.end,
        companyName: companyName,
      );
  }
}

/// Reusable row widget for per-user stats
class _UserStatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _UserStatRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 15 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}