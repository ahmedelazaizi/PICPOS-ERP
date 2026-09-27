// ignore_for_file: avoid_dynamic_calls
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/utils/arabic_utils.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/manufacturing_providers.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../services/excel_export_helper.dart';
import '../../services/printing/report_pdf_generator.dart';
import '../widgets/report_components.dart' show DateRangeFilter;

/// General Ledger Screen (دفتر الأستاذ)
/// Shows all journal movements for a selected account with running balance
/// and comprehensive filters (date, cost center).
class GeneralLedgerScreen extends ConsumerStatefulWidget {
  const GeneralLedgerScreen({super.key});

  @override
  ConsumerState<GeneralLedgerScreen> createState() => _GeneralLedgerScreenState();
}

class _GeneralLedgerScreenState extends ConsumerState<GeneralLedgerScreen> {
  int? _selectedAccountId;
  String? _selectedAccountName;
  int? _selectedCostCenterId;
  int? _selectedBranchId;
  DateTime _fromDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _toDate = DateTime.now();
  List<Map<String, dynamic>> _ledgerData = [];
  bool _isLoading = false;
  final String _searchQuery = '';

  final _fmt = NumberFormat('#,##0.00', 'ar_EG');
  final _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  Widget build(BuildContext context) {
    final accountingRepo = ref.watch(accountingRepositoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1a237e), const Color(0xFF0d47a1)]
                      : [const Color(0xFF1565C0), const Color(0xFF0D47A1)],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(PhosphorIconsBold.book, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Text('دفتر الأستاذ', style: GoogleFonts.cairo(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (_ledgerData.isNotEmpty) ...[
                        IconButton(
                          icon: const Icon(PhosphorIconsBold.printer, color: Colors.white, size: 20),
                          tooltip: 'طباعة PDF',
                          onPressed: () => ReportPdfGenerator.printGeneralLedger(
                            accountName: _selectedAccountName ?? '',
                            data: _ledgerData,
                            fromDate: _fromDate,
                            toDate: _toDate,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(PhosphorIconsBold.fileXls, color: Colors.white, size: 20),
                          tooltip: 'تصدير Excel',
                          onPressed: () => ExcelExportHelper.export(
                            context: context,
                            title: 'دفتر الأستاذ - $_selectedAccountName',
                            headers: ['التاريخ', 'رقم القيد', 'البيان', 'مدين', 'دائن', 'الرصيد'],
                            rows: _ledgerData.map((r) => [
                              r['entry_date'],
                              r['entry_number'],
                              r['description'],
                              r['debit'],
                              r['credit'],
                              r['balance'],
                            ]).toList(),
                            fromDate: _fromDate,
                            toDate: _toDate,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (_ledgerData.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_ledgerData.length} حركة',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Filter Bar ──
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.start,
                    children: [
                      // Account Picker
                      _buildFilterChip(
                        icon: PhosphorIconsBold.treeStructure,
                        label: _selectedAccountName ?? 'اختر الحساب',
                        isActive: _selectedAccountId != null,
                        onTap: () => _showAccountPicker(accountingRepo),
                      ),
                      // Date Range
                      _buildFilterChip(
                        icon: PhosphorIconsBold.calendar,
                        label: '${_dateFmt.format(_fromDate)} - ${_dateFmt.format(_toDate)}',
                        isActive: true,
                        onTap: () => _selectDateRange(),
                      ),
                      // Cost Center
                      FutureBuilder<List<dynamic>>(
                        future: accountingRepo.getActiveCostCenters(),
                        builder: (ctx, snap) {
                          if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                          final centers = snap.data!;
                          final name = _selectedCostCenterId != null
                              ? centers.where((c) => c.id == _selectedCostCenterId).map((c) => c.name).firstOrNull ?? 'مركز التكلفة'
                              : 'كل المراكز';
                          return _buildFilterChip(
                            icon: PhosphorIconsBold.target,
                            label: name,
                            isActive: _selectedCostCenterId != null,
                            onTap: () => _showCostCenterPicker(centers),
                          );
                        },
                      ),
                      // Branch Filter
                      Consumer(
                        builder: (ctx, ref, _) {
                          final branchesAsync = ref.watch(branchListProvider);
                          return branchesAsync.when(
                            data: (branches) {
                              if (branches.isEmpty) return const SizedBox.shrink();
                              final name = _selectedBranchId != null
                                  ? branches.where((b) => b.id == _selectedBranchId).map((b) => b.name).firstOrNull ?? 'الفرع'
                                  : 'كل الفروع';
                              return _buildFilterChip(
                                icon: PhosphorIconsBold.buildings,
                                label: name,
                                isActive: _selectedBranchId != null,
                                onTap: () => _showBranchPicker(branches),
                              );
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, _) => const SizedBox.shrink(),
                          );
                        },
                      ),
                      // Search Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1565C0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onPressed: _selectedAccountId != null ? () => _loadLedger(accountingRepo) : null,
                        icon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                        label: const Text('عرض'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Summary Cards ──
            if (_ledgerData.isNotEmpty) _buildSummaryBar(isDark),

            // ── Data Table ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _ledgerData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsBold.book, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                _selectedAccountId == null ? 'اختر حساباً لعرض الحركات' : 'لا توجد حركات للفترة المحددة',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : _buildLedgerTable(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: isActive ? 0.4 : 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar(bool isDark) {
    final openingBalance = _ledgerData.isNotEmpty && _ledgerData.first['is_opening'] == true
        ? (_ledgerData.first['balance'] as double? ?? 0)
        : 0.0;
    final closingBalance = _ledgerData.isNotEmpty
        ? (_ledgerData.last['balance'] as double? ?? 0)
        : 0.0;
    final totalDebit = _ledgerData.where((r) => r['is_opening'] != true).fold<double>(0, (s, r) => s + (r['debit'] as double? ?? 0));
    final totalCredit = _ledgerData.where((r) => r['is_opening'] != true).fold<double>(0, (s, r) => s + (r['credit'] as double? ?? 0));

    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(
        children: [
          _summaryCard('رصيد أول المدة', openingBalance, PhosphorIconsBold.arrowFatLineRight, Colors.blue, isDark),
          const SizedBox(width: 12),
          _summaryCard('إجمالي المدين', totalDebit, PhosphorIconsBold.arrowUp, Colors.green, isDark),
          const SizedBox(width: 12),
          _summaryCard('إجمالي الدائن', totalCredit, PhosphorIconsBold.arrowDown, Colors.red, isDark),
          const SizedBox(width: 12),
          _summaryCard('الرصيد الختامي', closingBalance, PhosphorIconsBold.equals, Colors.deepPurple, isDark),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, double value, IconData icon, Color color, bool isDark) {
    String displayLabel = label;
    if (label == 'ضريبة المبيعات' || label == 'ضريبة المشتريات' || (_selectedAccountName != null && (_selectedAccountName!.contains('ضريبة المبيعات') || _selectedAccountName!.contains('ضريبة المشتريات')) && label == 'الرصيد الختامي')) {
       // Append %16 for clarity as requested in Task 11
       if (label == 'الرصيد الختامي') {
         displayLabel = '$label (%16)';
       } else {
         displayLabel = '$label (%16)';
       }
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(displayLabel, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _fmt.format(value),
              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerTable(bool isDark) {
    // FIX: Removed redundant client-side cost center re-filtering.
    // The SQL query already filters by cost center (with header fallback).
    // Re-filtering here by line-level cost_center_id alone was incorrectly
    // hiding entries where the CC was only on the journal_entries header.
    final filtered = _ledgerData;

    // Cluster 024 / Issue 1 (perf) — switched from DataTable in
    // SingleChildScrollView (built every JE row eagerly, froze the screen
    // for accounts with thousands of journal lines) to DataTable2 which
    // virtualizes via ListView.builder. Always-visible scrollbars give
    // operators a draggable thumb for fast navigation.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DataTable2(
        isVerticalScrollBarVisible: true,
        isHorizontalScrollBarVisible: true,
        minWidth: 900,
        headingRowHeight: 44,
        dataRowHeight: 40,
        columnSpacing: 20,
        horizontalMargin: 12,
        columns: const [
          // Cluster 025 / Issue 5 — narrow columns get fixedWidth so the
          // البيان (description) absorbs the remainder. Long entry
          // descriptions also get wrapped in Tooltip below.
          DataColumn2(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), fixedWidth: 100),
          DataColumn2(label: Text('رقم القيد', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), fixedWidth: 100),
          DataColumn2(label: Text('البيان', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.L),
          DataColumn2(label: Text('مدين', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), numeric: true, fixedWidth: 100),
          DataColumn2(label: Text('دائن', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), numeric: true, fixedWidth: 100),
          DataColumn2(label: Text('الرصيد', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), numeric: true, fixedWidth: 100),
        ],
        rows: filtered.map((row) {
            final isOpening = row['is_opening'] == true;
            final debit = row['debit'] as double? ?? 0;
            final credit = row['credit'] as double? ?? 0;
            final balance = row['balance'] as double? ?? 0;
            final date = row['entry_date'];
            final dateStr = date is DateTime ? _dateFmt.format(date) : '';

            return DataRow(
              color: isOpening
                  ? WidgetStateProperty.all(isDark ? Colors.blue.withValues(alpha: 0.08) : Colors.blue.withValues(alpha: 0.04))
                  : null,
              cells: [
                DataCell(Text(dateStr, style: const TextStyle(fontSize: 12))),
                DataCell(Text(row['entry_number']?.toString() ?? '', style: const TextStyle(fontSize: 12))),
                DataCell(
                  // Cluster 025 / Issue 5 — wrap long JE descriptions in
                  // Tooltip so the operator can hover/long-press to see
                  // the full text. Drop the fixed 200px so the column's
                  // L size soaks up the leftover viewport.
                  Tooltip(
                    message: row['description']?.toString() ?? '',
                    child: Text(
                      row['description']?.toString() ?? '',
                      style: TextStyle(fontSize: 12, fontWeight: isOpening ? FontWeight.w700 : FontWeight.normal),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(debit > 0 ? _fmt.format(debit) : '', style: TextStyle(fontSize: 12, color: Colors.green.shade700))),
                DataCell(Text(credit > 0 ? _fmt.format(credit) : '', style: TextStyle(fontSize: 12, color: Colors.red.shade700))),
                DataCell(Text(
                  _fmt.format(balance),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: balance >= 0 ? Colors.green.shade800 : Colors.red.shade800),
                )),
              ],
            );
        }).toList(),
      ),
    );
  }

  Future<void> _loadLedger(IAccountingRepository repo) async {
    if (_selectedAccountId == null) return;
    setState(() => _isLoading = true);
    try {
      // Phase 5C.5 (Issue 4) — auth-level branch scope. The DAO query
      // is now scope-aware: passing `allowedBranchIds` restricts the
      // result to JEs whose branch_id is in the set OR is null
      // (legacy data). Admin / financial-manager hits
      // BranchScope.fullAccess (allowedBranchIds == null) and the
      // filter is a no-op. Independent of and AND-ed with the manual
      // UI `branchId` dropdown, so a restricted user who picks a
      // specific branch sees the intersection.
      final scope = await ref.read(branchScopeProvider.future);
      final data = await repo.getAccountLedger(
        _selectedAccountId!,
        _fromDate,
        _toDate,
        costCenterId: _selectedCostCenterId,
        branchId: _selectedBranchId,
        allowedBranchIds: scope.hasFullAccess ? null : scope.allowedBranchIds,
      );
      if (mounted) setState(() { _ledgerData = data; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _selectDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      initialEntryMode: DatePickerEntryMode.input,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          datePickerTheme: const DatePickerThemeData(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          ),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 380),
              child: child!,
            ),
          ),
        ),
      ),
    );
    if (range != null) {
      // FIL-1: normalize start/end-of-day so last-day entries (entry_date has
      // real time-of-day) aren't dropped from the ledger by a midnight bound.
      setState(() {
        _fromDate = DateRangeFilter.normalizeStart(range.start);
        _toDate = DateRangeFilter.normalizeEnd(range.end);
      });
    }
  }

  void _showAccountPicker(IAccountingRepository repo) async {
    final accounts = await repo.getAllAccounts();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        String filterText = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text('اختر الحساب', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 420,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم أو الرمز...',
                        prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      onChanged: (v) => setDialogState(() => filterText = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: accounts.where((a) {
                          if (filterText.isEmpty) return true;
                          final normalizedQuery = ArabicUtils.normalize(filterText.toLowerCase());
                          final normalizedName = ArabicUtils.normalize(a.name.toLowerCase());
                          return normalizedName.contains(normalizedQuery) ||
                                 a.code.contains(normalizedQuery);
                        }).length,
                        itemBuilder: (ctx, i) {
                          final filtered = accounts.where((a) {
                            if (filterText.isEmpty) return true;
                            final normalizedQuery = ArabicUtils.normalize(filterText.toLowerCase());
                            final normalizedName = ArabicUtils.normalize(a.name.toLowerCase());
                            return normalizedName.contains(normalizedQuery) ||
                                   a.code.contains(normalizedQuery);
                          }).toList();
                          final acc = filtered[i];
                          
                          // Determine indentation level based on code length (e.g. 1, 11, 1101, 1101001)
                          final int level = (acc.code.length / 2).floor();
                          
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsetsDirectional.only(start: 16.0 + (level * 12.0), end: 16.0),
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.blue.shade50,
                              child: Text(acc.code.substring(0, 1), style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
                            ),
                            title: Text(
                              '${acc.code} — ${acc.name}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: level <= 2 ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(_getAccountTypeLabel(acc.accountType), style: const TextStyle(fontSize: 11)),
                            onTap: () {
                              setState(() {
                                _selectedAccountId = acc.id;
                                _selectedAccountName = '${acc.code} - ${acc.name}';
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCostCenterPicker(List<dynamic> centers) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: Text('مركز التكلفة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          children: [
            SimpleDialogOption(
              onPressed: () { setState(() => _selectedCostCenterId = null); Navigator.pop(ctx); },
              child: const Text('الكل (بدون فلتر)'),
            ),
            ...centers.map((c) => SimpleDialogOption(
              onPressed: () { setState(() => _selectedCostCenterId = c.id); Navigator.pop(ctx); },
              child: Text('${c.code} — ${c.name}'),
            )),
          ],
        ),
      ),
    );
  }

  void _showBranchPicker(List<dynamic> branches) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: Text('الفرع', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          children: [
            SimpleDialogOption(
              onPressed: () { setState(() => _selectedBranchId = null); Navigator.pop(ctx); },
              child: const Text('الكل (بدون فلتر)'),
            ),
            ...branches.map((b) => SimpleDialogOption(
              onPressed: () { setState(() => _selectedBranchId = b.id); Navigator.pop(ctx); },
              child: Text(b.name),
            )),
          ],
        ),
      ),
    );
  }

  String _getAccountTypeLabel(String type) {
    switch (type) {
      case 'asset': return 'أصول';
      case 'contra_asset': return 'أصول مقابلة';
      case 'liability': return 'خصوم';
      case 'equity': return 'حقوق ملكية';
      case 'revenue': return 'إيرادات';
      case 'contra_revenue': return 'إيرادات مقابلة';
      case 'expense': return 'مصروفات';
      default: return type;
    }
  }
}