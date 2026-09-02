// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
// دفعة ١٢ — حارس reports_export على زرار تصدير Excel.
import 'report_export_guard.dart';
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/printing/pdf_compute_helper.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/providers.dart';
import '../../../services/excel_export_helper.dart';
import '../../../services/generators/base_generator.dart';
import '../../widgets/common/common.dart';
import '../../widgets/report_components.dart' show DateRangeFilter;
import '../../widgets/report_filter_bar.dart';

/// Expenses Report Screen — تقرير المصروفات التشغيلية
/// تصميم موحّد مع باقي شاشات النظام: AppBar بهوية النظام،
/// بطاقات KPI أعلى، تخطيط عمودين (جدول AppDataTable + chart دائري للتوزيع).
class ExpensesReportScreen extends ConsumerStatefulWidget {
  const ExpensesReportScreen({super.key});

  @override
  ConsumerState<ExpensesReportScreen> createState() =>
      _ExpensesReportScreenState();
}

class _ExpensesReportScreenState extends ConsumerState<ExpensesReportScreen> {
  // Spec 065: default range is full-day-inclusive [00:00, 23:59:59.999] (D3-006).
  DateTimeRange _dateRange = DateRangeFilter.normalizeRange(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
    DateTime.now(),
  );

  int? _selectedBranchId;
  int? _selectedUserId;
  // Spec 079b (B1): region filter — `_regionBranchIds` is null when no region
  // is selected (means "all branches"). When set, it's the resolved set of
  // branch ids in the region. Empty set => region has no branches (we still
  // apply the filter so the result is empty; FILTER-WARN fires once).
  int? _selectedRegionId;
  Set<int>? _regionBranchIds;
  bool _isLoading = false;
  List<Map<String, dynamic>> _summaryRows = [];
  List<Map<String, dynamic>> _detailRows = [];
  double _grandTotal = 0.0;

  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _currencyFormat = NumberFormat.currency(
    symbol: '',
    decimalDigits: AppConstants.decimalPlaces,
  );

  // Stable color palette assigned per category index — keeps the pie chart
  // and the table dot-indicator in sync visually.
  static const _categoryPalette = <Color>[
    Color(0xFF2B737F),
    Color(0xFFE76F51),
    Color(0xFFE9C46A),
    Color(0xFF8AB17D),
    Color(0xFF6A4C93),
    Color(0xFFEF476F),
    Color(0xFF118AB2),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFF059669),
  ];

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
          // The old copy promised «يتم عرض كل الفروع» unconditionally, which
          // was both a lie and the leak's user-facing symptom: a branch-scoped
          // user without an active branch is capped to their own branches (or
          // to nothing), never to the company. Say what actually happens.
          final scope = await ref.read(branchScopeProvider.future);
          if (!mounted) return;
          final message = scope.hasFullAccess
              ? 'لم يتم تعيين فرع لهذا المستخدم — يتم عرض كل الفروع'
              : 'لم يتم تعيين فرع لهذا المستخدم — يتم عرض الفروع المصرّح بها فقط';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 6),
            ));
          });
        }
      }
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      // Authoritative branch-scope cap. `_selectedBranchId` is a UI convenience
      // filter seeded from activeBranchIdProvider — which is null for a user
      // with NO branch assignment, i.e. exactly the user branchScopeProvider
      // hands `{}` («sees nothing»). Relying on it alone inverted fail-closed
      // into fail-open: that user read the WHOLE company's expenses. The cap is
      // resolved here and enforced in SQL, so it holds no matter what the
      // dropdown says. Full-access users get null → unchanged behaviour.
      final scope = await ref.read(branchScopeProvider.future);
      final allowedBranchIds =
          scope.hasFullAccess ? null : scope.allowedBranchIds;
      final summary = await db.getMonthlyExpenseSummary(
        from: _dateRange.start,
        to: _dateRange.end,
        branchId: _selectedBranchId,
        userId: _selectedUserId,
        allowedBranchIds: allowedBranchIds,
      );
      final detail = await db.getExpensesForReport(
        from: _dateRange.start,
        to: _dateRange.end,
        branchId: _selectedBranchId,
        userId: _selectedUserId,
        allowedBranchIds: allowedBranchIds,
      );

      // Spec 079b (B1): apply region scope client-side. The DAO doesn't
      // accept a branchIds list, so we filter the merged result by
      // `branch_id`. Rows with NULL branch_id drop out when a region is
      // active — documented behavior, user can clear region to see them.
      // Summary is re-aggregated from filtered detail so the pie chart and
      // legend stay consistent with the table.
      List<Map<String, dynamic>> filteredDetail = detail;
      List<Map<String, dynamic>> filteredSummary = summary;
      if (_regionBranchIds != null) {
        final allowed = _regionBranchIds!;
        filteredDetail = detail
            .where((r) => allowed.contains(r['branch_id'] as int?))
            .toList();
        // Re-aggregate by category_name. Preserves the keys downstream UI
        // expects (`name`, `total_amount`, `entry_count`).
        final byCategory = <String, Map<String, dynamic>>{};
        for (final r in filteredDetail) {
          final name = (r['category_name'] as String?) ?? '—';
          final amount = (r['amount'] as num?)?.toDouble() ?? 0.0;
          final bucket = byCategory.putIfAbsent(
              name,
              () => <String, dynamic>{
                    'name': name,
                    'total_amount': 0.0,
                    'entry_count': 0,
                  });
          bucket['total_amount'] =
              (bucket['total_amount'] as double) + amount;
          bucket['entry_count'] = (bucket['entry_count'] as int) + 1;
        }
        filteredSummary = byCategory.values.toList()
          ..sort((a, b) => (b['total_amount'] as double)
              .compareTo(a['total_amount'] as double));
      }

      final total = filteredSummary.fold<double>(
        0.0,
        (sum, row) => sum + ((row['total_amount'] as num?)?.toDouble() ?? 0.0),
      );
      setState(() {
        _summaryRows = filteredSummary;
        _detailRows = filteredDetail;
        _grandTotal = total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      // Force the compact "calendar dialog" layout instead of the
      // full-screen input mode that Material 3 picks by default on
      // wide windows.
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
            child: Dialog(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: child,
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      // H10 · التقويم يرجّع النهايةَ عند منتصف ليل آخر يوم، والاستعلامات
      // `BETWEEN` — فأخذُه خاماً يبتر اليومَ الأخير. نفسُ تطبيع الحالة
      // الابتدائية في السطر ٣٧.
      setState(() => _dateRange =
          DateRangeFilter.normalizeRange(picked.start, picked.end));
      _loadData();
    }
  }

  // ── Export & Print helpers (unchanged) ──────────────────────────────────

  Future<void> _exportExcel() async {
    final headers = [
      'التاريخ',
      'الفئة',
      'المبلغ',
      'طريقة الدفع',
      'الفرع',
      'المستخدم',
      'ملاحظات',
    ];
    final rows = _detailRows.map((r) {
      final raw = r['expense_date'];
      String dateStr = '';
      if (raw is int) {
        dateStr = _dateFormat
            .format(DateTime.fromMillisecondsSinceEpoch(raw * 1000));
      } else if (raw is String) {
        dateStr = raw.length > 10 ? raw.substring(0, 10) : raw;
      }
      return [
        dateStr,
        r['category_name'] ?? '',
        (r['amount'] as num?)?.toDouble() ?? 0.0,
        r['payment_method'] ?? '',
        r['branch_name'] ?? '',
        r['user_name'] ?? '',
        r['notes'] ?? '',
      ];
    }).toList();

    rows.add(['', '', '', '', '', '', '']);
    rows.add(['ملخص حسب الفئة', '', '', '', '', '', '']);
    for (final s in _activeSummary) {
      rows.add([
        '',
        s['name'] ?? '',
        (s['total_amount'] as num?)?.toDouble() ?? 0.0,
        '',
        '',
        '',
        'عدد: ${s['entry_count'] ?? 0}',
      ]);
    }
    rows.add(['', 'الإجمالي الكلي', _grandTotal, '', '', '', '']);

    await ExcelExportHelper.export(
      context: context,
      title: 'تقرير المصروفات التشغيلية',
      headers: headers,
      rows: rows,
      fromDate: _dateRange.start,
      toDate: _dateRange.end,
    );
  }

  Future<void> _printPdf() async {
    final font = await BaseGenerator.initFont();
    final pdf = await BaseGenerator.newDocument();
    fmtMoney(num v) => _currencyFormat.format(v.toDouble());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'تقرير المصروفات التشغيلية',
              style: pw.TextStyle(
                  font: font, fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              'الفترة: ${_dateFormat.format(_dateRange.start)} → ${_dateFormat.format(_dateRange.end)}',
              style: pw.TextStyle(font: font, fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'إجمالي المصروفات',
                  style: pw.TextStyle(
                      font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  '${fmtMoney(_grandTotal)} ${AppConstants.currencySymbol}',
                  style: pw.TextStyle(
                      font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'الملخص حسب الفئة',
            style: pw.TextStyle(
                font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
                font: font, fontSize: 10, fontWeight: pw.FontWeight.bold),
            cellStyle: pw.TextStyle(font: font, fontSize: 10),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerRight,
            headers: ['الفئة', 'الإجمالي', 'العدد'],
            data: _activeSummary
                .map((r) => [
                      r['name']?.toString() ?? '—',
                      fmtMoney((r['total_amount'] as num?) ?? 0),
                      '${r['entry_count'] ?? 0}',
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'تفاصيل المصروفات (${_detailRows.length} سجل)',
            style: pw.TextStyle(
                font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
                font: font, fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: pw.TextStyle(font: font, fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerRight,
            headers: [
              'التاريخ',
              'الفئة',
              'المبلغ',
              'الفرع',
              'المستخدم',
            ],
            data: _detailRows.map((r) {
              final raw = r['expense_date'];
              String dateStr = '—';
              if (raw is int) {
                dateStr = _dateFormat
                    .format(DateTime.fromMillisecondsSinceEpoch(raw * 1000));
              } else if (raw is String) {
                dateStr = raw.length > 10 ? raw.substring(0, 10) : raw;
              }
              return [
                dateStr,
                r['category_name']?.toString() ?? '—',
                fmtMoney((r['amount'] as num?) ?? 0),
                r['branch_name']?.toString() ?? '—',
                r['user_name']?.toString() ?? '—',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await PdfComputeHelper.layoutPdf(pdf, name: 'تقرير_المصروفات_${_dateFormat.format(DateTime.now())}');
  }

  // ── Computed helpers ────────────────────────────────────────────────────

  /// Categories that actually have expenses (filters out the zero rows the
  /// summary query returns for every defined category).
  List<Map<String, dynamic>> get _activeSummary => _summaryRows
      .where((r) => ((r['total_amount'] as num?)?.toDouble() ?? 0) > 0)
      .toList();

  int get _totalEntries => _detailRows.length;
  double get _averagePerEntry =>
      _totalEntries == 0 ? 0.0 : _grandTotal / _totalEntries;

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Scoped list, not allBranchesProvider: the picker used to name every
    // branch in the company to a branch-restricted user — a master-data leak
    // on top of the amounts leak, and it let them pick a branch they may not
    // read (the SQL cap now returns nothing for it, so the picker would just
    // lie). Mirrors treasury_report_screen's scoped safe picker.
    final branchesAsync = ref.watch(userAccessibleBranchesProvider);
    final usersAsync = ref.watch(allUsersProvider);
    final regionsAsync = ref.watch(allRegionsProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('تقرير المصروفات التشغيلية'),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.printer),
              tooltip: 'طباعة',
              onPressed: _isLoading || _detailRows.isEmpty ? null : _printPdf,
            ),
            buildReportExportAction(onExport: _isLoading || _detailRows.isEmpty ? null : _exportExcel),
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              tooltip: 'تحديث',
              onPressed: _isLoading ? null : _loadData,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            _buildFilterBar(branchesAsync, usersAsync, regionsAsync),
            _buildKpiCards(),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _activeSummary.isEmpty
                      ? _buildEmpty()
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(
    AsyncValue branchesAsync,
    AsyncValue usersAsync,
    AsyncValue regionsAsync,
  ) {
    // Spec 076: unified two-row filter bar. Replaces the previous AppCard
    // wrapper + inline InkWell date picker. The custom-range button inside
    // ReportFilterBar already does what _pickDateRange did.
    // Spec 079b (B1): region dropdown added before branch. Selecting a
    // region resolves to a set of branchIds via regionBranchesProvider, and
    // the result is filtered client-side in _loadData. The branch
    // dropdown is reset to "all" when region changes so the two filters
    // can't fight each other.
    return ReportFilterBar(
      selectedRange: _dateRange,
      onRangeChanged: (start, end) {
        setState(() => _dateRange = DateTimeRange(start: start, end: end));
        _loadData();
      },
      trailing: [
        SizedBox(
          width: 220,
          child: regionsAsync.when(
            data: (regions) => DropdownButtonFormField<int?>(
              isExpanded: true,
              initialValue: _selectedRegionId,
              isDense: true,
              decoration: InputDecoration(
                labelText: 'المنطقة',
                prefixIcon: const Icon(PhosphorIconsBold.mapPin, size: 16),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 8),
              ),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('كل المناطق')),
                ...regions.map<DropdownMenuItem<int?>>(
                  (r) => DropdownMenuItem<int?>(
                      value: r.id as int?, child: Text(r.name as String)),
                ),
              ],
              onChanged: (v) async {
                _selectedRegionId = v;
                _selectedBranchId = null;
                if (v != null) {
                  // Spec 079b hotfix (b142): call the DAO directly instead
                  // of going through `regionBranchesProvider(v).future`.
                  // The provider is autoDispose+family: reading `.future`
                  // creates a transient instance that Riverpod disposes
                  // before the underlying Stream emits, so the await
                  // throws "disposed during loading" and `_regionBranchIds`
                  // never gets set — leaving the client-side filter inert
                  // and showing all branches. Direct DAO call has no
                  // lifecycle. Confirmed in field smoke 2026-05-16.
                  final db = ref.read(databaseProvider);
                  final regionBranches = await db.getBranchesByRegion(v);
                  _regionBranchIds =
                      regionBranches.map((b) => b.id).toSet();
                  // Spec 079b FR-B1-5: surface "region with no branches"
                  // so an operator can spot a data-integrity issue (a
                  // region whose branches were unassigned or deleted)
                  // instead of mistaking it for "no expenses in period".
                  if (_regionBranchIds!.isEmpty) {
                    unawaited(DiagnosticLogger.log(
                      'FILTER-WARN',
                      'Region $v selected on expenses report but no '
                      'branches linked. Check that branches in this '
                      'region have a regionId set.',
                    ));
                  }
                } else {
                  _regionBranchIds = null;
                }
                if (!mounted) return;
                setState(() {});
                _loadData();
              },
            ),
            loading: () => const SizedBox(height: 40),
            error: (_, _) => const SizedBox(height: 40),
          ),
        ),
        SizedBox(
          width: 220,
          child: branchesAsync.when(
            data: (branches) => DropdownButtonFormField<int?>(
              isExpanded: true,
              initialValue: _selectedBranchId,
              isDense: true,
              decoration: InputDecoration(
                labelText: 'الفرع',
                prefixIcon:
                    const Icon(PhosphorIconsBold.buildings, size: 16),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 8),
              ),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('كل الفروع')),
                ...branches.map<DropdownMenuItem<int?>>(
                  (b) => DropdownMenuItem<int?>(
                      value: b.id as int?, child: Text(b.name as String)),
                ),
              ],
              onChanged: (v) {
                setState(() => _selectedBranchId = v);
                _loadData();
              },
            ),
            loading: () => const SizedBox(height: 40),
            error: (_, _) => const SizedBox(height: 40),
          ),
        ),
        SizedBox(
          width: 220,
          child: usersAsync.when(
            data: (users) => DropdownButtonFormField<int?>(
              isExpanded: true,
              initialValue: _selectedUserId,
              isDense: true,
              decoration: InputDecoration(
                labelText: 'المستخدم',
                prefixIcon: const Icon(PhosphorIconsBold.user, size: 16),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 8),
              ),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('كل المستخدمين')),
                ...users.map<DropdownMenuItem<int?>>(
                  (u) => DropdownMenuItem<int?>(
                    value: u.user.id as int?,
                    child: Text(
                      (u.user.displayName as String).isNotEmpty
                          ? u.user.displayName as String
                          : u.user.username as String,
                    ),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _selectedUserId = v);
                _loadData();
              },
            ),
            loading: () => const SizedBox(height: 40),
            error: (_, _) => const SizedBox(height: 40),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCards() {
    final cards = [
      AppKpiCard(
        icon: PhosphorIconsBold.coins,
        label: 'إجمالي المصروفات',
        value:
            '${_currencyFormat.format(_grandTotal)} ${AppConstants.currencySymbolEn}',
        color: AppColors.error,
      ),
      AppKpiCard(
        icon: PhosphorIconsBold.tag,
        label: 'عدد الفئات النشطة',
        value: '${_activeSummary.length}',
        color: AppColors.warning,
      ),
      AppKpiCard(
        icon: PhosphorIconsBold.listChecks,
        label: 'عدد القيود',
        value: '$_totalEntries',
        color: AppColors.info,
      ),
      AppKpiCard(
        icon: PhosphorIconsBold.calculator,
        label: 'متوسط القيد',
        value:
            '${_currencyFormat.format(_averagePerEntry)} ${AppConstants.currencySymbolEn}',
        color: AppColors.primary,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final perRow = w >= 900 ? 4 : w >= 600 ? 2 : 1;
          const spacing = 10.0;
          final cardWidth = (w - (perRow - 1) * spacing) / perRow;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: cards
                .map((c) => SizedBox(
                    width: cardWidth, height: 72, child: c))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On narrow screens, stack vertically.
          if (constraints.maxWidth < 900) {
            return ListView(
              children: [
                _buildBreakdownCard(),
                const SizedBox(height: 12),
                _buildDetailsCard(),
              ],
            );
          }
          // Wide screens: 2 columns (details on right since RTL).
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: _buildDetailsCard()),
              const SizedBox(width: 12),
              SizedBox(width: 360, child: _buildBreakdownCard()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBreakdownCard() {
    final summary = _activeSummary;
    return AppCard(
      density: AppCardDensity.regular,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(PhosphorIconsBold.chartPieSlice,
                  color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text('التوزيع حسب الفئة',
                  style:
                      TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          const Divider(height: 18),
          // Pie chart
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 36,
                sections: List.generate(summary.length, (i) {
                  final amount =
                      (summary[i]['total_amount'] as num?)?.toDouble() ?? 0;
                  final pct = _grandTotal > 0
                      ? (amount / _grandTotal * 100)
                      : 0.0;
                  final color = _categoryPalette[i % _categoryPalette.length];
                  return PieChartSectionData(
                    color: color,
                    value: amount,
                    radius: 50,
                    title: pct >= 5 ? '${pct.toStringAsFixed(0)}%' : '',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend list (scrollable inside the breakdown card)
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: summary.length,
              itemBuilder: (_, i) {
                final row = summary[i];
                final amount =
                    (row['total_amount'] as num?)?.toDouble() ?? 0;
                final pct = _grandTotal > 0
                    ? (amount / _grandTotal * 100)
                    : 0.0;
                final color =
                    _categoryPalette[i % _categoryPalette.length];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          row['name'] as String? ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currencyFormat.format(amount),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return AppCard(
      density: AppCardDensity.compact,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.listDashes,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'تفاصيل القيود (${_detailRows.length} سجل)',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ],
            ),
          ),
          Expanded(
            child: AppDataTable(
              margin: EdgeInsets.zero,
              columns: const [
                DataColumn(label: Text('التاريخ')),
                DataColumn(label: Text('الفئة')),
                DataColumn(label: Text('المبلغ'), numeric: true),
                DataColumn(label: Text('طريقة الدفع')),
                DataColumn(label: Text('الفرع')),
                DataColumn(label: Text('المستخدم')),
                DataColumn(label: Text('ملاحظات')),
              ],
              rows: _detailRows.map<DataRow>((row) {
                final rawDate = row['expense_date'];
                String dateStr = '—';
                if (rawDate is int) {
                  dateStr = _dateFormat.format(
                      DateTime.fromMillisecondsSinceEpoch(rawDate * 1000));
                } else if (rawDate is String) {
                  dateStr = rawDate.length > 10
                      ? rawDate.substring(0, 10)
                      : rawDate;
                }
                final categoryName =
                    row['category_name'] as String? ?? '—';
                final amount =
                    (row['amount'] as num?)?.toDouble() ?? 0.0;
                // Map this row's category back to its color via summary index
                final catIdx = _activeSummary.indexWhere(
                    (s) => s['name'] == categoryName);
                final color = catIdx >= 0
                    ? _categoryPalette[catIdx % _categoryPalette.length]
                    : AppColors.textMuted;

                return DataRow(cells: [
                  DataCell(Text(dateStr,
                      style: const TextStyle(fontSize: 12))),
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(categoryName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ])),
                  DataCell(Text(
                    '${_currencyFormat.format(amount)} ${AppConstants.currencySymbolEn}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error),
                  )),
                  DataCell(Text(row['payment_method'] as String? ?? '—',
                      style: const TextStyle(fontSize: 12))),
                  DataCell(Text(row['branch_name'] as String? ?? '—',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700))),
                  DataCell(Text(row['user_name'] as String? ?? '—',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700))),
                  DataCell(SizedBox(
                    width: 200,
                    child: Text(
                      row['notes'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  )),
                ]);
              }).toList(),
              emptyState: const Text('لا توجد قيود مصروفات في هذه الفترة'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.coins,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'لا توجد مصروفات في هذه الفترة',
            style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}