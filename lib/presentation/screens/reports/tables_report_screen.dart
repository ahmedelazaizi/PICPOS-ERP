// ignore_for_file: avoid_dynamic_calls
// ═══════════════════════════════════════════════════════════════════════════
// تقريرُ الطاولات — الإيرادُ ودورانُ الطاولة ونصيبُ الضيف
// ═══════════════════════════════════════════════════════════════════════════
//
// ثمانيَ عشرةَ شاشةَ تقاريرَ في هذا المستودع ولا واحدةٌ تقيس الطاولة.
//
// ── ما لا تخترعه هذه الشاشة ────────────────────────────────────────────────
// لا فلترَ جديداً فيها. المدى من `DateRangeFilter.normalizeRange`، والشريطُ
// `ReportFilterBar`، والفرعُ والمنطقةُ من `BranchWarehouseFilterBar`،
// والتصديرُ من `report_export_guard.dart` — نفسُها التي يركبها
// `shifts_report_screen` و`sales_report_screen`. وثلاثةٌ خاصّةٌ بالطاولات
// وحدَها: القسمُ والطاولةُ والكاشير.
//
// وقائمةُ المخازن **لا تُعرَض**: `table_orders` لا `warehouse_id` فيه، فكانت
// ستُخزَّن قيمتُها ولا تُقرأ في استعلام — وعرضُ فلترٍ لا يفلتر أسوأُ من
// غيابه (نفسُ ما قرّره تقريرُ الورديات، وهو موثَّقٌ عند
// `BranchWarehouseFilterBar.showWarehouse`).
//
// ── والحساب ليس هنا ────────────────────────────────────────────────────────
// قواعدُ التجميع الثلاث (المدموجُ لا يُحسَب · المفتوحُ إشغالٌ لا إيراد ·
// مقامُ المدّة عددُ المغلقة) خالصةٌ في `domain/models/tables_report_row.dart`
// ومقيسةٌ في `test/unit/tables_report_aggregation_test.dart`. الشاشةُ تعرض.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/tables_report_row.dart';
import '../../widgets/branch_warehouse_filter.dart';
import '../../widgets/report_components.dart';
import '../../widgets/report_filter_bar.dart';
import 'report_export_guard.dart';

class TablesReportScreen extends ConsumerStatefulWidget {
  const TablesReportScreen({super.key});

  @override
  ConsumerState<TablesReportScreen> createState() => _TablesReportScreenState();
}

class _TablesReportScreenState extends ConsumerState<TablesReportScreen> {
  // Spec 065: المدى الافتراضيُّ شاملُ اليوم كاملاً [00:00, 23:59:59.999]
  // فيطابق أوّلُ تحميلٍ ما تُصدره شرائحُ «اليوم»/«الشهر» (D3-006).
  DateTimeRange _dateRange = DateRangeFilter.normalizeRange(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
    DateTime.now(),
  );

  bool _isLoading = false;

  /// الصفوفُ المجمَّعة — ما يُعرَض وما يُصدَّر، مصدرٌ واحدٌ لا اثنان.
  List<TablesReportRow> _rows = const [];

  /// متوسّطُ الدوران عبر **الجلسات**، محسوباً قبل التجميع بالطاولة: متوسّطُ
  /// متوسّطاتِ الصفوف يزن الطاولةَ ذاتَ الجلسة الواحدة وزنَ ذاتِ العشرين.
  double? _avgTurnMinutes;

  int? _selectedSectionId;
  int? _selectedTableId;
  int? _selectedUserId;
  int? _selectedRegionId;
  int? _selectedBranchId;

  /// فروعُ المنطقة المختارة — تُحلّ عند الاختيار وتُمرَّر إلى الاستعلام.
  Set<int>? _regionBranchIds;

  List<TableSection> _sections = const [];
  List<RestaurantTable> _tables = const [];
  List<UserWithRole> _allUsers = const [];

  // نطاقُ صلاحية الفروع للمستخدم الحالي — **سقفُ صلاحيةٍ** يختلف عن اختيار
  // الفرع/المنطقة أعلاه. null = وصولٌ كامل (مدير النظام/المدير المالي/مرآة).
  // يُحلّ في `build()` **و** في رأس `_loadData()` معاً — كما في
  // `sales_report_screen` و`shifts_report_screen` — فلا يسبق جلبٌ إمبراطيٌّ
  // من `initState` حلَّ النطاق.
  Set<int>? _allowedBranchIds;

  // Feature 058: حارسٌ لمرّةٍ واحدةٍ لتنبيه «لا فرعَ لهذا المستخدم».
  bool _noBranchNoticeShown = false;

  final _currencyFormat =
      NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // Feature 058: ابذر الفرعَ النشطَ للجهاز قبل أوّل جلب (FR-001/FR-002).
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
              content:
                  Text('لم يتم تعيين فرع لهذا المستخدم — يتم عرض كل الفروع'),
              duration: Duration(seconds: 6),
            ));
          });
        }
      }
      await _loadFilters();
      await _loadData();
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(
              user?.id ?? 0,
              user?.displayName ?? 'مجهول',
              'تقرير الطاولات',
            );
      } catch (_) {}
    });
  }

  /// قوائمُ الفلاتر الخاصّة بالطاولات: الأقسامُ والطاولاتُ والكاشيرات.
  Future<void> _loadFilters() async {
    try {
      final restaurantRepo = ref.read(restaurantRepositoryProvider);
      final sections = await restaurantRepo.getAllSections();
      final tables = await restaurantRepo.getAllTables();
      final users =
          await ref.read(reportingRepositoryProvider).watchAllUsers().first;
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _tables = tables;
        _allUsers = users;
      });
    } catch (_) {
      // قوائمُ الفلاتر زينةٌ للتقرير لا شرطٌ له — إخفاقُ تحميلها لا يمنع
      // عرضَ الأرقام.
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // يُحلّ النطاقُ الآمرُ **قبل** الاستعلام في كلّ نداء: هذه الدالّةُ
      // تُنادى من `initState` ومن كلّ `onChanged`، فإعادةُ الحلّ هنا تقفل
      // السباقَ الذي يجعل أوّلَ جلبٍ يمرّ بلا حصر.
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final orders =
          await ref.read(restaurantRepositoryProvider).getTableOrdersForReport(
                from: _dateRange.start,
                to: _dateRange.end,
                sectionId: _selectedSectionId,
                tableId: _selectedTableId,
                userId: _selectedUserId,
                branchIds: _queryBranchIds(),
                // ← سقفُ الصلاحية يدخل الاستعلامَ نفسَه، لا الترشيحَ بعده.
                allowedBranchIds: _allowedBranchIds,
              );
      if (!mounted) return;

      setState(() {
        _rows = aggregateTablesReport(orders);
        _avgTurnMinutes = overallAvgTurnMinutes(orders);
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// نطاقُ الفروع الذي **اختاره المستخدم** — الفرعُ إن اختير، وإلّا فروعُ
  /// المنطقة. مستقلٌّ عن `_allowedBranchIds` الذي يسقفه فوقه.
  Set<int>? _queryBranchIds() {
    if (_selectedBranchId != null) return {_selectedBranchId!};
    return _regionBranchIds;
  }

  double get _totalRevenue => _rows.fold(0.0, (s, r) => s + r.revenue);
  double get _totalDiscount => _rows.fold(0.0, (s, r) => s + r.discount);
  int get _totalOrders => _rows.fold(0, (s, r) => s + r.orderCount);
  int get _totalGuests => _rows.fold(0, (s, r) => s + r.guestCount);

  @override
  Widget build(BuildContext context) {
    // لا يُرسَم التقريرُ ولا ومضةً والنطاقُ مجهول: مستخدمٌ محصورٌ يلمح تقريراً
    // غيرَ محصورٍ هو التسريبُ نفسُه. مطابقةً لـ`sales_report_screen`.
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
          body: Center(
              child: Text('تعذر تحديد صلاحيات الفرع: ${scopeAsync.error}')),
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
          title: const Text('تقرير الطاولات'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            buildReportExportAction(
              onExport: _rows.isEmpty ? null : _exportToExcel,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            ReportFilterBar(
              selectedRange: _dateRange,
              onRangeChanged: (start, end) {
                setState(
                  () => _dateRange = DateTimeRange(start: start, end: end),
                );
                _loadData();
              },
              trailing: [
                _sectionFilter(),
                _tableFilter(),
                _cashierFilter(),
                BranchWarehouseFilterBar(
                  selectedRegionId: _selectedRegionId,
                  selectedBranchId: _selectedBranchId,
                  // الطاولةُ لا تخصّ مخزناً — انظر ترويسةَ الملفّ.
                  showWarehouse: false,
                  selectedWarehouseId: null,
                  onRegionChanged: (v) async {
                    _selectedRegionId = v;
                    _selectedBranchId = null;
                    if (v != null) {
                      // نداءُ الـDAO مباشرةً كما في `shifts_report_screen`:
                      // مسارُ `regionBranchesProvider(v).future` كان يرمي
                      // «disposed during loading» في الدخان الميدانيّ فيترك
                      // النطاقَ فارغاً بلا أن ينطق.
                      final db = ref.read(databaseProvider);
                      final regionBranches = await db.getBranchesByRegion(v);
                      _regionBranchIds =
                          regionBranches.map((b) => b.id).toSet();
                      if (_regionBranchIds!.isEmpty) {
                        unawaited(DiagnosticLogger.log(
                          'FILTER-WARN',
                          'Region $v selected on tables report but no '
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
                          _kpiRow(),
                          const SizedBox(height: 24),
                          Text(
                            'أداء الطاولات',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).textTheme.titleLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _rows.isEmpty ? _emptyState() : _table(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── الفلاترُ الثلاثةُ الخاصّة ─────────────────────────────────────────────

  Widget _sectionFilter() => SizedBox(
        width: 160,
        child: DropdownButtonFormField<int?>(
          initialValue: _selectedSectionId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'القسم',
            isDense: true,
            prefixIcon: Icon(PhosphorIconsBold.squaresFour, size: 16),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
            ..._sections.map((s) => DropdownMenuItem<int?>(
                  value: s.id,
                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (v) {
            setState(() {
              _selectedSectionId = v;
              // طاولةٌ مختارةٌ من قسمٍ آخرَ تُنتج تقريراً فارغاً بلا سبب
              // ظاهر — فالاختيارُ الأضيقُ يسقط مع تغيّر الأوسع.
              _selectedTableId = null;
            });
            _loadData();
          },
        ),
      );

  Widget _tableFilter() {
    final visible = _selectedSectionId == null
        ? _tables
        : _tables.where((t) => t.sectionId == _selectedSectionId).toList();
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<int?>(
        initialValue:
            visible.any((t) => t.id == _selectedTableId) ? _selectedTableId : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'الطاولة',
          isDense: true,
          prefixIcon: Icon(PhosphorIconsBold.table, size: 16),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
          ...visible.map((t) => DropdownMenuItem<int?>(
                value: t.id,
                child: Text(t.name, overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: (v) {
          setState(() => _selectedTableId = v);
          _loadData();
        },
      ),
    );
  }

  Widget _cashierFilter() => SizedBox(
        width: 180,
        child: DropdownButtonFormField<int?>(
          initialValue: _selectedUserId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'الكاشير / النادل',
            isDense: true,
            prefixIcon: Icon(PhosphorIconsBold.user, size: 16),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
            ..._allUsers.map((u) => DropdownMenuItem<int?>(
                  value: u.user.id,
                  child: Text(u.user.displayName,
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (v) {
            setState(() => _selectedUserId = v);
            _loadData();
          },
        ),
      );

  // ── العرض ────────────────────────────────────────────────────────────────

  Widget _kpiRow() {
    final currency = AppConstants.currencySymbolEn;
    return Row(
      children: [
        Expanded(
          child: ReportKpiCard(
            title: 'إيراد الطاولات',
            value: '${_currencyFormat.format(_totalRevenue)} $currency',
            icon: PhosphorIconsBold.chartLineUp,
            color: AppColors.primary,
            subtitle:
                'صافٍ من خصمٍ قدرُه ${_currencyFormat.format(_totalDiscount)}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ReportKpiCard(
            title: 'عدد الطلبات',
            value: '$_totalOrders',
            icon: PhosphorIconsBold.receipt,
            color: AppColors.info,
            subtitle: 'المدموجُ محسوبٌ على هدفه لا مرّتين',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ReportKpiCard(
            title: 'عدد الضيوف',
            value: '$_totalGuests',
            icon: PhosphorIconsBold.users,
            color: AppColors.success,
            subtitle: _totalGuests > 0
                ? 'نصيب الضيف: '
                    '${_currencyFormat.format(_totalRevenue / _totalGuests)}'
                : 'لا ضيوف في هذا المدى',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ReportKpiCard(
            title: 'متوسط مدة الجلوس',
            value: _avgTurnMinutes == null
                ? '—'
                : '${_avgTurnMinutes!.toStringAsFixed(0)} د',
            icon: PhosphorIconsBold.clock,
            color: const Color(0xFF7C3AED),
            subtitle: 'للطلبات المغلقة وحدَها',
          ),
        ),
      ],
    );
  }

  Widget _emptyState() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.table, size: 44, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'لا توجد طلباتُ طاولاتٍ في هذا المدى بهذه الفلاتر',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      );

  Widget _table() => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(Theme.of(context).cardColor),
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('الطاولة')),
              DataColumn(label: Text('عدد الطلبات'), numeric: true),
              DataColumn(label: Text('الضيوف'), numeric: true),
              DataColumn(label: Text('الإيراد'), numeric: true),
              DataColumn(label: Text('الخصم'), numeric: true),
              DataColumn(label: Text('نصيب الضيف'), numeric: true),
              DataColumn(label: Text('متوسط الجلوس (د)'), numeric: true),
            ],
            rows: _rows
                .map(
                  (r) => DataRow(
                    cells: [
                      DataCell(Text(r.tableName)),
                      DataCell(Text('${r.orderCount}')),
                      DataCell(Text('${r.guestCount}')),
                      DataCell(Text(_currencyFormat.format(r.revenue))),
                      DataCell(Text(
                        r.discount > 0
                            ? _currencyFormat.format(r.discount)
                            : '—',
                        style: r.discount > 0
                            ? const TextStyle(
                                color: AppColors.warning,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      )),
                      DataCell(Text(_perGuestLabel(r))),
                      DataCell(Text(_turnLabel(r))),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      );

  /// «—» لا صفرٌ حين لا مقامَ: صفرٌ مطبوعٌ يُقرأ رقماً مقيساً.
  String _perGuestLabel(TablesReportRow r) {
    final share = r.revenuePerGuest;
    return share == null ? '—' : _currencyFormat.format(share);
  }

  String _turnLabel(TablesReportRow r) {
    final turn = r.avgTurnMinutes;
    return turn == null ? '—' : turn.toStringAsFixed(0);
  }

  Future<void> _exportToExcel() async {
    if (_rows.isEmpty) {
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
      title: 'تقرير الطاولات',
      headers: [
        'الطاولة',
        'عدد الطلبات',
        'الضيوف',
        'الإيراد',
        'الخصم',
        'نصيب الضيف',
        'متوسط الجلوس (دقيقة)',
      ],
      // نفسُ `_rows` التي يعرضها الجدولُ حرفياً — الملفُّ يقول ما تقوله
      // الشاشة، وإلّا جمع المحاسبُ عموداً لا يطابق ما رآه.
      rows: _rows
          .map<List<dynamic>>((r) => [
                r.tableName,
                r.orderCount,
                r.guestCount,
                r.revenue,
                r.discount,
                r.revenuePerGuest ?? 0,
                r.avgTurnMinutes ?? 0,
              ])
          .toList(),
    );
    if (path != null && mounted) {
      AppToast.show(context, 'تم تصدير التقرير بنجاح: $path',
          type: ToastType.success);
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportExport(
              user?.id ?? 0,
              user?.displayName ?? 'مجهول',
              'تقرير الطاولات',
              'Excel',
            );
      } catch (_) {}
    }
  }
}
