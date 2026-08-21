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
import '../../../data/providers/providers.dart';
import '../../../domain/models/user_shift_summary.dart';
import '../../widgets/report_components.dart';
import '../../widgets/report_filter_bar.dart';
import '../../../../../../core/constants/app_constants.dart';
import '../../widgets/branch_warehouse_filter.dart';
import 'report_export_guard.dart';

/// سقفُ صفحةِ تقرير الورديات.
///
/// كان `limit: 100` رقماً مدفوناً في النداء بتعليق `// Load top 100 for now`:
/// لا المستخدمُ يعلم بوجوده ولا شيءَ ينطق حين يُقتطع التقرير. والتقريرُ
/// المقتطعُ لا يُميَّز عن الكامل — وهذا أخطرُ من فشلٍ، لأن الفشلَ يُرى.
/// (نفسُ العلاج المقيس في `report_builder_dao.dart` — سقفٌ معلَنٌ ينطق.)
const int kShiftsReportPageLimit = 100;

class ShiftsReportScreen extends ConsumerStatefulWidget {
  const ShiftsReportScreen({super.key});

  @override
  ConsumerState<ShiftsReportScreen> createState() => _ShiftsReportScreenState();
}

class _ShiftsReportScreenState extends ConsumerState<ShiftsReportScreen> {
  // Spec 065: default range is full-day-inclusive [00:00, 23:59:59.999] (D3-006).
  DateTimeRange _dateRange = DateRangeFilter.normalizeRange(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
    DateTime.now(),
  );

  bool _isLoading = false;
  List<ShiftReportDto> _shifts = [];

  /// تلخيصُ `_shifts` حسب المستخدم — طلبُ المالك 2026-08-14: «تقريرٌ خاصٌّ
  /// باسم المستخدم مع الإغلاق والطباعة، أوضحُ من تقرير المبيعات حسب
  /// المستخدم».
  ///
  /// ⚠️ مشتقٌّ من `_shifts` نفسِها — لا استعلامَ ثانٍ ولا مصدرَ ثانٍ. مصدران
  /// لنفس الرقم يفترقان، وهو بعينه ما جعل «الشاشةُ تقول غيرَ الورقة» عطباً
  /// متكرّراً في هذا المستودع.
  List<UserShiftSummary> _byUser = const [];
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);
  int? _selectedUserId;
  // 072 (D3-004 + D3-005): cost-center and safe dropdowns dropped — the
  // Shifts table carries neither field, so the controls were silent
  // no-ops. Re-introducing them needs a "shifts that touched
  // safe/cost-center via safe_transactions" sub-query (own future spec).
  List<UserWithRole> _allUsers = [];
  int? _selectedRegionId; // Feature 017
  int? _selectedBranchId;
  // قائمةُ المخازن أُسقطت لنفس سبب مركزِ التكلفة والخزنة أعلاه: جدولُ
  // `shifts` لا يحمل `warehouse_id` أصلاً، فكانت القيمةُ تُخزَّن ولا تُقرأ
  // في أيّ استعلامٍ ولا في أيّ فلترةٍ بعد الجلب — يختار المستخدمُ مخزناً
  // فلا يتغيّر شيء.
  Set<int>? _regionBranchIds; // resolved when a region is picked

  /// هل اقتُطع التقرير على السقف؟ يُعرَض للمستخدم — لا يُبتلع.
  bool _truncated = false;

  // Spec 151 Track-3: the logged-in user's branch authorization scope — an
  // AUTH CAP distinct from the user-chosen branch/region filter above. null =
  // full access (admin/financial-manager/mirror/userId=1). Resolved in BOTH
  // build() and _loadData() so no imperative fetch races ahead of the scope.
  Set<int>? _allowedBranchIds;

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
      _loadData();
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير الورديات');
      } catch (_) {}
    });
  }

  // 072: _loadFilters removed — its only consumers were the deleted
  // cost-center + safe dropdowns. Active-branch resolution is handled
  // inline in initState (Feature 058 path, lines above).

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Spec 151 Track-3: resolve the auth-level branch scope BEFORE the query
      // runs, on every call (closes the initState-microtask race).
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final repo = ref.read(reportingRepositoryProvider);

      // Load user names for filter
      final users = await repo.watchAllUsers().first;

      // Fetch shifts. الحصرُ الآمر **واختيارُ المستخدم** كلاهما في SQL الآن.
      //
      // كان اختيارُ الفرع يُطبَّق هنا بعد الجلب، فالسقفُ يمتلئ بشفتاتِ
      // فروعٍ أخرى أحدث ولا يبقى للفرع المختار شيء ⇒ جدولٌ فارغٌ بينما
      // للفرع شفتاتٌ فعلاً.
      //
      // ونجلب `+1` كي نعرف أن هناك ما هو أكثرُ من السقف فنقولَه.
      final page = await repo.getShiftsReportPaginated(
        startDate: _dateRange.start,
        endDate: _dateRange.end,
        userId: _selectedUserId,
        limit: kShiftsReportPageLimit + 1,
        allowedBranchIds: _allowedBranchIds,
        branchId: _selectedBranchId,
        regionBranchIds: _selectedBranchId == null ? _regionBranchIds : null,
      );

      final truncated = page.length > kShiftsReportPageLimit;
      final shifts =
          truncated ? page.sublist(0, kShiftsReportPageLimit) : page;

      setState(() {
        _shifts = shifts;
        _byUser = summarizeShiftsByUser(shifts.map(
          (s) => ShiftSummaryInput(
            userName: s.userName,
            status: s.status,
            openingBalance: s.openingBalance,
            expectedCash: s.expectedCash,
            actualCash: s.actualCash,
            variance: s.variance,
          ),
        ));
        _truncated = truncated;
        _allUsers = users;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Spec 151 Track-3: resolve the auth-level branch scope BEFORE the report
    // renders. The report MUST NOT render (even a flash) while the scope is
    // unknown — a restricted user briefly seeing an unscoped report is itself
    // the leak this fix closes.
    final scopeAsync = ref.watch(branchScopeProvider);
    if (scopeAsync.isLoading) {
      return const Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (scopeAsync.hasError) {
      return Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(
          body: Center(child: Text('تعذر تحديد صلاحيات الفرع: ${scopeAsync.error}')),
        ),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('تقرير الورديات المطول'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            buildReportExportAction(onExport: _exportToExcel),
            buildReportPrintAsExportAction(onExport: _printReport),
            const SizedBox(width: 8),
          ],
        ),
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
                  width: 180,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedUserId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المستخدم / الكاشير',
                      isDense: true,
                      prefixIcon: Icon(PhosphorIconsBold.user, size: 16),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('الكل'),
                      ),
                      ..._allUsers.map(
                        (u) => DropdownMenuItem<int?>(
                          value: u.user.id,
                          child: Text(
                            u.user.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedUserId = v);
                      _loadData();
                    },
                  ),
                ),
                // 072 (D3-004 + D3-005): cost-center + safe dropdowns
                // removed — the Shifts table carries neither field, so the
                // controls were silent no-ops. Reintroducing them needs a
                // "shifts that touched safe/cost-center via safe_transactions"
                // sub-query (own future spec).
                BranchWarehouseFilterBar(
                  selectedRegionId: _selectedRegionId,
                  selectedBranchId: _selectedBranchId,
                  // الورديةُ لا تخصّ مخزناً — انظر التعليقَ عند التصريح.
                  showWarehouse: false,
                  selectedWarehouseId: null,
                  onRegionChanged: (v) async {
                    _selectedRegionId = v;
                    _selectedBranchId = null;
                    if (v != null) {
                      // Spec 079b b142 hotfix: call DAO directly. The
                      // `regionBranchesProvider(v).future` path was throwing
                      // a "disposed during loading" error in field smoke,
                      // leaving `_regionBranchIds` null and silently
                      // disabling the client-side filter on shifts.
                      final db = ref.read(databaseProvider);
                      final regionBranches = await db.getBranchesByRegion(v);
                      _regionBranchIds = regionBranches.map((b) => b.id).toSet();
                      // Spec 079b (B2): empty branch set means the region
                      // has no branches assigned — common after a region
                      // is created without wiring branches yet. Without
                      // this signal the operator just sees an empty
                      // shifts table and can't tell why.
                      if (_regionBranchIds!.isEmpty) {
                        unawaited(DiagnosticLogger.log(
                          'FILTER-WARN',
                          'Region $v selected on shifts report but no '
                          'branches linked. Check that branches in this '
                          'region have a regionId set.',
                        ));
                      }
                    } else {
                      _regionBranchIds = null;
                    }
                    _loadData();
                  },
                  onBranchChanged: (v) {
                    setState(() => _selectedBranchId = v);
                    _loadData();
                  },
                  onWarehouseChanged: (_) {},
                ),
              ],
            ),

            // السقفُ ينطق: التقريرُ المقتطعُ لا يُميَّز عن الكامل بلا هذا.
            if (_truncated && !_isLoading)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                color: AppColors.warning.withValues(alpha: 0.12),
                child: const Row(
                  children: [
                    Icon(PhosphorIconsBold.warning,
                        size: 16, color: AppColors.warning),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'معروضٌ أحدثُ $kShiftsReportPageLimit ورديةٍ فقط — '
                        'هناك ورديّاتٌ أقدمُ خارج هذه الصفحة. ضيّق المدى '
                        'الزمنيّ أو الفرعَ أو المستخدمَ لرؤيتها.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
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
                          const Text(
                            'سجل الورديات',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          _buildByUserCard(),
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
                                columns: const [
                                  DataColumn(label: Text('# الوردية')),
                                  DataColumn(label: Text('المستخدم')),
                                  DataColumn(label: Text('بداية الشفت')),
                                  DataColumn(label: Text('نهاية الشفت')),
                                  DataColumn(label: Text('رصيد الإفتتاح')),
                                  DataColumn(
                                    label: Text('نقدي النظام (متوقع)'),
                                  ),
                                  DataColumn(label: Text('نقدي فعلي (مُدخل)')),
                                  DataColumn(
                                    label: Text('الفرق (العجز/الزيادة)'),
                                  ),
                                  DataColumn(label: Text('الحالة')),
                                ],
                                rows: _shifts.map((s) {
                                  final varColor = s.variance == null
                                      ? null
                                      : (s.variance!.abs() < 0.001
                                            ? AppColors.success
                                            : (s.variance! < 0
                                                  ? AppColors.error
                                                  : AppColors.warning));
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        InkWell(
                                          onTap: () => _viewShiftDetails(s),
                                          child: Text(
                                            s.id.toString(),
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(s.userName)),
                                      DataCell(
                                        Text(_dateFormat.format(s.startTime)),
                                      ),
                                      DataCell(
                                        Text(
                                          s.endTime != null
                                              ? _dateFormat.format(s.endTime!)
                                              : '---',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          _currencyFormat.format(
                                            s.openingBalance,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          s.expectedCash != null
                                              ? _currencyFormat.format(
                                                  s.expectedCash!,
                                                )
                                              : '---',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          s.actualCash != null
                                              ? _currencyFormat.format(
                                                  s.actualCash!,
                                                )
                                              : '---',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          s.variance != null
                                              ? _currencyFormat.format(
                                                  s.variance!,
                                                )
                                              : '---',
                                          style: TextStyle(
                                            color: varColor,
                                            fontWeight:
                                                s.variance != null &&
                                                    s.variance!.abs() > 0.001
                                                ? FontWeight.bold
                                                : null,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: s.status == 'closed'
                                                ? AppColors.success.withValues(
                                                    alpha: 0.1,
                                                  )
                                                : AppColors.warning.withValues(
                                                    alpha: 0.1,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            s.status == 'closed'
                                                ? 'مغلق'
                                                : 'مفتوح',
                                            style: TextStyle(
                                              color: s.status == 'closed'
                                                  ? AppColors.success
                                                  : AppColors.warning,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _viewShiftDetails(ShiftReportDto shift) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text('تفاصيل الوردية #${shift.id}'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الكاشير: ${shift.userName}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text('البداية: ${_dateFormat.format(shift.startTime)}'),
                if (shift.endTime != null)
                  Text('النهاية: ${_dateFormat.format(shift.endTime!)}'),
                const Divider(),
                if (shift.status == 'closed') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('النقدي المتوقع (نظام):'),
                      Text(
                        '${_currencyFormat.format(shift.expectedCash ?? 0)} ${AppConstants.currencySymbolEn}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('النقدي الفعلي (مُدخل):'),
                      Text(
                        '${_currencyFormat.format(shift.actualCash ?? 0)} ${AppConstants.currencySymbolEn}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الفرق:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_currencyFormat.format(shift.variance ?? 0)} ${AppConstants.currencySymbolEn}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: shift.variance == null
                              ? Colors.black
                              : (shift.variance!.abs() < 0.001
                                    ? AppColors.success
                                    : (shift.variance! < 0
                                          ? AppColors.error
                                          : AppColors.warning)),
                        ),
                      ),
                    ],
                  ),
                  if (shift.notes != null && shift.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'الملاحظات / تفاصيل بطاقات الدفع:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(shift.notes!),
                  ],
                ] else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'الوردية ما زالت مفتوحة',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  /// «الإغلاق حسب المستخدم» — سطرٌ لكلّ مستخدمٍ فوق جدول الورديات.
  ///
  /// العجزُ والزيادةُ **عمودان منفصلان** لا صافٍ واحد: كاشيرٌ عجز ١٠٠ في
  /// وردية وزاد ١٠٠ في أخرى يظهر صافيه صفراً فيُقرأ منضبطاً، وهو خطآن
  /// يتقاصّان. والمديرُ الذي يجرد يحتاج الرقمَين — وهذا هو «أوضح» الذي طلبه.
  Widget _buildByUserCard() {
    if (_byUser.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'الإغلاق حسب المستخدم',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'العجز والزيادة منفصلان — الصافي وحده يخفي خطأين يتقاصّان.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('المستخدم')),
                DataColumn(label: Text('الورديات')),
                DataColumn(label: Text('مغلقة')),
                DataColumn(label: Text('مفتوحة')),
                DataColumn(label: Text('نقدي متوقع')),
                DataColumn(label: Text('نقدي فعلي')),
                DataColumn(label: Text('العجز')),
                DataColumn(label: Text('الزيادة')),
                DataColumn(label: Text('الصافي')),
              ],
              rows: _byUser
                  .map(
                    (u) => DataRow(
                      cells: [
                        DataCell(Text(u.userName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold))),
                        DataCell(Text('${u.shiftCount}')),
                        DataCell(Text('${u.closedCount}')),
                        DataCell(Text(
                          '${u.openCount}',
                          style: TextStyle(
                            color: u.openCount > 0 ? AppColors.warning : null,
                            fontWeight:
                                u.openCount > 0 ? FontWeight.bold : null,
                          ),
                        )),
                        DataCell(
                            Text(_currencyFormat.format(u.expectedCashTotal))),
                        DataCell(
                            Text(_currencyFormat.format(u.actualCashTotal))),
                        DataCell(Text(
                          _currencyFormat.format(u.shortageTotal),
                          style: TextStyle(
                            color:
                                u.shortageTotal > 0 ? AppColors.error : null,
                          ),
                        )),
                        DataCell(Text(
                          _currencyFormat.format(u.surplusTotal),
                          style: TextStyle(
                            color:
                                u.surplusTotal > 0 ? AppColors.warning : null,
                          ),
                        )),
                        DataCell(Text(
                          _currencyFormat.format(u.varianceTotal),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToExcel() async {
    if (_shifts.isEmpty) {
      AppToast.show(context, 'لا توجد بيانات للتصدير', type: ToastType.error);
      return;
    }
    final service = ref.read(excelServiceProvider);
    final path = await service.exportReport(
      periodFrom: _dateRange.start,
      periodTo: _dateRange.end,
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
      title: 'تقرير الورديات',
      // الورقةُ تحمل الجدولَين بنفس ترتيب الشاشة: التلخيصُ حسب المستخدم
      // أوّلاً ثم التفصيل. وكلاهما تسعةُ أعمدةٍ فيتّسقان في ورقةٍ واحدة.
      // ⚠️ ولا يُبنى أيٌّ منهما من استعلامٍ ثانٍ — كلاهما من `_shifts`
      // نفسِها، وإلا افترقت الورقةُ عن الشاشة كما وقع مراراً في هذا
      // المستودع (`report_export_matches_screen_test`).
      headers: const [
        'المستخدم',
        'عدد الورديات',
        'مغلقة',
        'مفتوحة',
        'نقدي متوقع',
        'نقدي فعلي',
        'العجز',
        'الزيادة',
        'الصافي',
      ],
      rows: <List<dynamic>>[
        ..._byUser.map<List<dynamic>>((u) => [
              u.userName,
              u.shiftCount,
              u.closedCount,
              u.openCount,
              u.expectedCashTotal,
              u.actualCashTotal,
              u.shortageTotal,
              u.surplusTotal,
              u.varianceTotal,
            ]),
        const <dynamic>['', '', '', '', '', '', '', '', ''],
        const <dynamic>[
          '# الوردية',
          'المستخدم',
          'بداية الشفت',
          'نهاية الشفت',
          'رصيد الإفتتاح',
          'نقدي متوقع',
          'نقدي فعلي',
          'الفرق',
          'الحالة',
        ],
        ..._shifts.map<List<dynamic>>((s) => [
              s.id,
              s.userName,
              _dateFormat.format(s.startTime),
              s.endTime != null ? _dateFormat.format(s.endTime!) : '---',
              s.openingBalance,
              s.expectedCash ?? 0,
              s.actualCash ?? 0,
              s.variance ?? 0,
              s.status == 'closed' ? 'مغلق' : 'مفتوح',
            ]),
      ],
    );
    if (path != null && mounted) {
      AppToast.show(context, 'تم تصدير التقرير بنجاح: \$path', type: ToastType.success);
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportExport(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير الورديات', 'Excel');
      } catch (_) {}
    }
  }

  Future<void> _printReport() async {
    if (_shifts.isEmpty) {
      AppToast.show(context, 'لا توجد بيانات للطباعة', type: ToastType.error);
      return;
    }
    // Use the same Excel export as a workaround for print — the user can open and print the file
    await _exportToExcel();
  }
}