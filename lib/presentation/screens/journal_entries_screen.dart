// ignore_for_file: avoid_dynamic_calls
import 'package:ural_erp/core/constants/app_constants.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../domain/models/journal_balance.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../widgets/compact_date_picker.dart';
import '../widgets/branch_chip.dart';
import '../../services/printing/report_pdf_generator.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../core/permissions/permission_codes.dart';
import 'journal_templates_screen.dart';

part 'journal_entry_create_dialog.dart';
part 'journal_entry_widgets.dart';

/// Journal Entries Screen — View all journal entries and create manual entries
/// Displays both auto-posted and manual journal entries with full detail
class JournalEntriesScreen extends ConsumerStatefulWidget {
  const JournalEntriesScreen({super.key});

  @override
  ConsumerState<JournalEntriesScreen> createState() =>
      _JournalEntriesScreenState();
}

class _JournalEntriesScreenState extends ConsumerState<JournalEntriesScreen> {
  DateTime _dateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _dateTo = DateTime.now();
  String _filterType = 'all'; // all, auto, manual
  // Feature 004 — branch filter. null = "كل الفروع" (no filter), -1 sentinel
  // = "بدون فرع" (legacy entries with branchId = null), positive int = branch.id.
  int? _filterBranchId;
  static const int _noBranchSentinel = -1;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('yyyy/MM/dd');
  final Set<int> _expandedEntries = {};

  /// Strips the audit-trail hash suffix [HASH:...] from description for clean display.
  /// The hash remains in the DB for integrity verification (ICR-03).
  static String _cleanDescription(String? desc) {
    if (desc == null || desc.isEmpty) return 'بدون وصف';
    return desc.replaceAll(RegExp(r'\s*\[HASH:[a-f0-9]{64}\]'), '').trim();
  }

  /// MJE-3 (batch B13 / S-EXP-REST): local per-user permission gate for
  /// manual journal-entry posting/reversal.
  ///
  /// The gate previously existed ONLY server-side (api_data_handler.dart
  /// postJournalEntry → PermissionCodes.accountingJournal, see line ~2280).
  /// Locally, `saveManualEntry` called `repo.createJournalEntry(...,
  /// isAutoPosted: false)` with no permission check at all — any user who
  /// got past the screen-password (a shared secret, not a per-user gate)
  /// could post arbitrary GL entries on a standalone/server install. Mirrors
  /// the server-side check on the client, for BOTH creating a manual entry
  /// and reversing one (same missing-gate shape).
  ///
  /// Returns true and does nothing when the user holds the permission.
  /// Returns false and shows an Arabic error toast when they don't (or
  /// aren't logged in) — callers must NOT proceed with the post/reverse.
  Future<bool> _requireAccountingJournalPermission() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      if (mounted) {
        AppToast.show(context, 'يجب تسجيل الدخول لتنفيذ هذا الإجراء',
            type: ToastType.error);
      }
      return false;
    }

    final authRepo = ref.read(authRepositoryProvider);
    final allowed = await authRepo.userHasPermission(
        userId, PermissionCodes.accountingJournal);
    if (!allowed) {
      if (mounted) {
        AppToast.show(
            context, 'ليست لديك صلاحية إنشاء أو عكس القيود المحاسبية اليدوية',
            type: ToastType.error);
      }
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountingRepo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _buildHeader(context, accountingRepo),
            _buildFilterBar(context, accountingRepo),
            Expanded(
              child: StreamBuilder<List<JournalEntryData>>(
                stream: accountingRepo.watchJournalEntries(from: _dateFrom, to: _dateTo),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  var entries = snapshot.data!;

                  // Phase 5C.4 (Issue 4) — branch-scope guard. The
                  // `watchJournalEntries` repo call has no native branch
                  // scope, so we filter the snapshot data here. Admin
                  // (BranchScope.fullAccess) skips. Restricted users
                  // see only entries whose branch_id is in their allowed
                  // set OR is null (legacy data without branch link).
                  final scope = ref.watch(branchScopeProvider).asData?.value;
                  if (scope != null && !scope.hasFullAccess) {
                    entries = entries
                        .where((e) => scope.isAllowed(e.branchId))
                        .toList();
                  }

                  if (_filterType == 'auto') {
                    entries = entries.where((e) => e.isAutoPosted).toList();
                  } else if (_filterType == 'manual') {
                    entries = entries.where((e) => !e.isAutoPosted).toList();
                  }

                  // Feature 004 — branch filter applied AFTER scope guard.
                  if (_filterBranchId != null) {
                    final id = _filterBranchId!;
                    if (id == _noBranchSentinel) {
                      entries = entries.where((e) => e.branchId == null).toList();
                    } else {
                      entries = entries.where((e) => e.branchId == id).toList();
                    }
                  }

                  if (_searchQuery.isNotEmpty) {
                    final q = _searchQuery.toLowerCase();
                    entries = entries.where((e) {
                      final matchNumber = e.entryNumber.toLowerCase().contains(q);
                      final matchDesc = (e.description ?? '').toLowerCase().contains(q);
                      final matchDate = _dateFormat.format(e.entryDate).contains(q);
                      final matchRef = (e.referenceType ?? '').toLowerCase().contains(q);
                      return matchNumber || matchDesc || matchDate || matchRef;
                    }).toList();
                  }

                  if (entries.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhosphorIconsBold.bookOpen, size: 56, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text('لا توجد قيود في هذه الفترة',
                              style: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 15)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _buildEntryCard(context, accountingRepo, entry);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, IAccountingRepository accountingRepo) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
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
            child: const Icon(PhosphorIconsBold.notebook, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'دفتر اليومية',
                style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              Text(
                'جميع القيود المحاسبية (التلقائية واليدوية)',
                style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
          const Spacer(),
          // Bulk print/export
          OutlinedButton.icon(
            onPressed: () => _printAllEntries(accountingRepo),
            icon: const Icon(PhosphorIconsBold.printer, size: 16),
            label: Text('طباعة/PDF', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          // Excel export
          OutlinedButton.icon(
            onPressed: () => _exportAllEntriesToExcel(accountingRepo),
            icon: const Icon(PhosphorIconsBold.fileXls, size: 16),
            label: Text('تصدير Excel', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JournalTemplatesScreen())),
            icon: const Icon(PhosphorIconsBold.notebook, size: 16),
            label: Text('قوالب القيود', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => showTemplateSelectionDialog(context, accountingRepo),
            icon: const Icon(PhosphorIconsBold.copy, size: 18),
            label: Text('من قالب', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.9),
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => showCreateEntryDialog(context),
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: Text('قيد يدوي', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, IAccountingRepository accountingRepo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            decoration: InputDecoration(
              hintText: 'بحث برقم القيد أو الوصف أو التاريخ...',
              hintStyle: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted),
              prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18, color: AppColors.primary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(PhosphorIconsBold.x, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            style: GoogleFonts.cairo(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickDateRange(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(PhosphorIconsBold.calendar, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          '${_dateFormat.format(_dateFrom)} — ${_dateFormat.format(_dateTo)}',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Feature 004 — branch filter dropdown. Sourced from
              // allBranchesProvider; respects branchScopeProvider so a
              // branch-scoped user only sees their assigned branches.
              _buildBranchFilterDropdown(),
              const SizedBox(width: 12),
              ToggleButtons(
                isSelected: [_filterType == 'all', _filterType == 'auto', _filterType == 'manual'],
                onPressed: (index) {
                  setState(() {
                    _filterType = ['all', 'auto', 'manual'][index];
                  });
                },
                borderRadius: BorderRadius.circular(8),
                constraints: const BoxConstraints(minHeight: 36, minWidth: 60),
                textStyle: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('الكل')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('تلقائي')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('يدوي')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Feature 004 — branch filter dropdown for the journal entries screen.
  /// Pulls the full branch list, intersects with `branchScopeProvider` so a
  /// branch-scoped user (cashier, branch manager) only sees their assigned
  /// branches in the menu, and exposes a sentinel for "بدون فرع" entries.
  Widget _buildBranchFilterDropdown() {
    final branchesAsync = ref.watch(allBranchesProvider);
    final scope = ref.watch(branchScopeProvider).asData?.value;
    final allBranches = branchesAsync.value ?? const [];
    // Apply scope: a branch-scoped user only filters within their allowed set.
    final visibleBranches = (scope == null || scope.hasFullAccess)
        ? allBranches
        : allBranches.where((b) => scope.isAllowed(b.id)).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _filterBranchId,
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsBold.buildings, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('كل الفروع',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          icon: const Icon(PhosphorIconsBold.caretDown, size: 12),
          style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsBold.buildings, size: 13, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('كل الفروع', style: GoogleFonts.cairo(fontSize: 12)),
                ],
              ),
            ),
            ...visibleBranches.map((b) => DropdownMenuItem<int?>(
                  value: b.id,
                  child: Text(b.name, style: GoogleFonts.cairo(fontSize: 12)),
                )),
            DropdownMenuItem<int?>(
              value: _noBranchSentinel,
              child: Text('بدون فرع (قديم)',
                  style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
            ),
          ],
          onChanged: (v) => setState(() => _filterBranchId = v),
        ),
      ),
    );
  }

  Widget _buildEntryCard(BuildContext context, IAccountingRepository repo, JournalEntryData entry) {
    final isExpanded = _expandedEntries.contains(entry.id);
    final refLabel = _getReferenceLabel(entry.referenceType);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: entry.isAutoPosted
              ? AppColors.info.withValues(alpha: 0.2)
              : AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (isExpanded) {
                _expandedEntries.remove(entry.id);
              } else {
                _expandedEntries.add(entry.id);
              }
            }),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.entryNumber,
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _dateFormat.format(entry.entryDate),
                    style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 6),
                  // Feature 004 — Branch chip: gives the auditor an immediate
                  // visual cue of which branch the JE belongs to. Hidden when
                  // the entry has no branch link (legacy data) so it never
                  // shows a misleading "بدون فرع" placeholder.
                  BranchChip(branchId: entry.branchId),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _cleanDescription(entry.description),
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: entry.isAutoPosted
                          ? AppColors.info.withValues(alpha: 0.1)
                          : AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.isAutoPosted ? 'تلقائي' : 'يدوي',
                      style: GoogleFonts.cairo(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: entry.isAutoPosted ? AppColors.info : AppColors.warning,
                      ),
                    ),
                  ),
                  // Manual entries show "يدوي" badge
                  if (!entry.isAutoPosted) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'يدوي',
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                  if (refLabel != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        refLabel,
                        style: GoogleFonts.cairo(fontSize: 9, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(PhosphorIconsBold.caretLeft, size: 14, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),

          if (isExpanded) ...[
            const Divider(height: 1),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: repo.getJournalEntryLinesWithAccounts(entry.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                final lines = snapshot.data!;
                double totalDebit = 0, totalCredit = 0;
                for (final line in lines) {
                  totalDebit += line['debit'] as double;
                  totalCredit += line['credit'] as double;
                }

                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Table(
                        columnWidths: const {
                          0: FixedColumnWidth(80),
                          1: FlexColumnWidth(),
                          2: FlexColumnWidth(),
                          3: FixedColumnWidth(90),
                          4: FixedColumnWidth(90),
                        },
                        border: TableBorder.all(color: AppColors.border, width: 0.5),
                        children: [
                          TableRow(
                            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.05)),
                            children: [
                              _tableCell('رمز الحساب', isHeader: true),
                              _tableCell('اسم الحساب', isHeader: true),
                              _tableCell('البيان', isHeader: true),
                              _tableCell('مدين', isHeader: true),
                              _tableCell('دائن', isHeader: true),
                            ],
                          ),
                          ...lines.map((line) => TableRow(
                                children: [
                                  _tableCell(line['account_code'] as String? ?? ''),
                                  _tableCell(line['account_name'] as String? ?? ''),
                                  _tableCell(line['description'] as String? ?? ''),
                                  _tableCell(
                                    (line['debit'] as double) > 0
                                        ? (line['debit'] as double).toStringAsFixed(AppConstants.decimalPlaces)
                                        : '',
                                  ),
                                  _tableCell(
                                    (line['credit'] as double) > 0
                                        ? (line['credit'] as double).toStringAsFixed(AppConstants.decimalPlaces)
                                        : '',
                                  ),
                                ],
                              )),
                          TableRow(
                            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.05)),
                            children: [
                              _tableCell('', isHeader: true),
                              _tableCell('الإجمالي', isHeader: true),
                              _tableCell(''),
                              _tableCell(totalDebit.toStringAsFixed(AppConstants.decimalPlaces), isHeader: true),
                              _tableCell(totalCredit.toStringAsFixed(AppConstants.decimalPlaces), isHeader: true),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Reverse button for all posted entries
                            TextButton.icon(
                              onPressed: () => _confirmReverseEntry(context, entry),
                              icon: const Icon(PhosphorIconsBold.arrowUUpLeft, size: 16, color: Colors.orange),
                              label: Text('عكس القيد', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange)),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => _printEntry(entry, lines),
                              icon: const Icon(PhosphorIconsBold.printer, size: 16),
                              label: Text('طباعة القيد', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _tableCell(String text, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Text(
        text,
        style: GoogleFonts.cairo(
          fontSize: 11,
          fontWeight: isHeader ? FontWeight.w700 : FontWeight.normal,
          color: isHeader ? AppColors.primary : AppColors.textPrimary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String? _getReferenceLabel(String? type) {
    switch (type) {
      case 'sale':
        return 'مبيعات';
      case 'purchase':
      case 'purchase_invoice':
        return 'مشتريات';
      case 'receipt':
        return 'تحصيل';
      case 'payment':
        return 'سداد';
      case 'return':
        return 'مرتجع';
      case 'fiscal_close':
        return 'إقفال';
      case 'manufacturing':
        return 'تصنيع';
      case 'daily':
        return 'يومية';
      case 'adjustment':
        return 'تسوية';
      case 'salary':
        return 'رواتب';
      default:
        return null;
    }
  }

  Future<void> _printEntry(JournalEntryData entry, List<Map<String, dynamic>> lines) async {
    // Feature 004 — pass branch name + deterministic colour so the printed
    // PDF carries the same visual identity as the on-screen chip.
    String? branchName;
    int? branchColorHex;
    final id = entry.branchId;
    if (id != null) {
      final branches = ref.read(allBranchesProvider).value;
      final branch = branches?.where((b) => b.id == id).firstOrNull;
      if (branch != null) {
        branchName = branch.name;
        // ignore: deprecated_member_use
        branchColorHex = BranchChip.colorFor(id).value;
      }
    }
    await ReportPdfGenerator.printJournalEntry(
      entryNumber: entry.entryNumber,
      entryDate: entry.entryDate,
      description: _cleanDescription(entry.description),
      referenceType: entry.referenceType,
      isAutoPosted: entry.isAutoPosted,
      lines: lines,
      branchName: branchName,
      branchColorHex: branchColorHex,
    );
  }

  /// Bulk print all journal entries in current date range
  Future<void> _printAllEntries(IAccountingRepository accountingRepo) async {
    try {
      final entries = await accountingRepo.getJournalEntries(from: _dateFrom, to: _dateTo);
      if (entries.isEmpty) {
        if (mounted) AppToast.show(context, 'لا توجد قيود للطباعة في هذه الفترة', type: ToastType.warning);
        return;
      }

      // Build flat data for the general ledger report
      final allRows = <Map<String, dynamic>>[];
      for (final entry in entries) {
        final lines = await accountingRepo.getJournalEntryLinesWithAccounts(entry.id);
        // Entry separator row
        allRows.add({
          'entry_date': entry.entryDate,
          'entry_number': entry.entryNumber,
          'description': '${_cleanDescription(entry.description)} ${entry.isAutoPosted ? '[تلقائي]' : '[يدوي]'}',
          'debit': 0.0,
          'credit': 0.0,
          'balance': 0.0,
          'is_opening': true,
        });
        for (final line in lines) {
          allRows.add({
            'entry_date': entry.entryDate,
            'entry_number': line['account_code'] ?? '',
            'description': line['account_name'] ?? '',
            'debit': (line['debit'] as double?) ?? 0.0,
            'credit': (line['credit'] as double?) ?? 0.0,
            'balance': 0.0,
          });
        }
      }

      await ReportPdfGenerator.printGeneralLedger(
        accountName: 'دفتر اليومية (${entries.length} قيد)',
        data: allRows,
        fromDate: _dateFrom,
        toDate: _dateTo,
      );
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
    }
  }

  /// Export all journal entries to Excel
  Future<void> _exportAllEntriesToExcel(IAccountingRepository accountingRepo) async {
    try {
      final entries = await accountingRepo.getJournalEntries(from: _dateFrom, to: _dateTo);
      if (entries.isEmpty) {
        if (mounted) AppToast.show(context, 'لا توجد قيود للتصدير في هذه الفترة', type: ToastType.warning);
        return;
      }

      final rows = <List<dynamic>>[];
      for (final entry in entries) {
        final lines = await accountingRepo.getJournalEntryLinesWithAccounts(entry.id);
        // Entry header row
        rows.add([
          entry.entryNumber,
          DateFormat('yyyy/MM/dd').format(entry.entryDate),
          _cleanDescription(entry.description),
          entry.isAutoPosted ? 'تلقائي' : 'يدوي',
          '',
          '',
        ]);
        // Lines
        for (final line in lines) {
          rows.add([
            '',
            '',
            '  ${line['account_code'] ?? ''} - ${line['account_name'] ?? ''}',
            line['description'] ?? '',
            (line['debit'] as double?) ?? 0.0,
            (line['credit'] as double?) ?? 0.0,
          ]);
        }
      }

      final service = ref.read(excelServiceProvider);
      final path = await service.exportReport(
      periodFrom: _dateFrom,
      periodTo: _dateTo,
      branchId: _filterBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
        title: 'دفتر اليومية (${entries.length} قيد)',
        headers: ['رقم القيد', 'التاريخ', 'البيان', 'النوع/الوصف', 'مدين', 'دائن'],
        rows: rows,
      );
      if (path != null && mounted) {
        AppToast.show(context, 'تم تصدير دفتر اليومية بنجاح', type: ToastType.success);
        try {
          final user = ref.read(authProvider).user;
          ref.read(activityLoggerProvider).logReportExport(
            user?.id ?? 0, user?.displayName ?? 'مجهول', 'دفتر اليومية', 'Excel',
          );
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في التصدير: $e', type: ToastType.error);
    }
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final range = await CompactDatePicker.showCompactRange(
      context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
    );
    if (range != null) {
      setState(() {
        _dateFrom = range.start;
        _dateTo = range.end;
      });
    }
  }

  // ICR-01: Approve a draft journal entry — shows confirmation then posts it
  Future<void> _approveEntry(BuildContext context, IAccountingRepository repo, JournalEntryData entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.checkCircle, color: AppColors.success, size: 22),
              const SizedBox(width: 8),
              Text('اعتماد القيد', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('هل تريد اعتماد هذا القيد؟', style: GoogleFonts.cairo(fontSize: 14)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رقم القيد: ${entry.entryNumber}', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                    if (entry.description != null)
                      Text('الوصف: ${_cleanDescription(entry.description)}', style: GoogleFonts.cairo(fontSize: 12)),
                    Text('التاريخ: ${_dateFormat.format(entry.entryDate)}', style: GoogleFonts.cairo(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'سيظهر في القوائم المالية بعد الاعتماد.',
                style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(PhosphorIconsBold.checkCircle, size: 16),
              label: const Text('تأكيد الاعتماد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final user = ref.read(authProvider).user;
      await repo.approveJournalEntry(entry.id, user?.id ?? 0);
      if (mounted) {
        AppToast.show(context, 'تم اعتماد القيد بنجاح', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في اعتماد القيد: $e', type: ToastType.error);
      }
    }
  }

  // F-02: Confirm and execute journal entry reversal
  Future<void> _confirmReverseEntry(BuildContext context, JournalEntryData entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.arrowUUpLeft, color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              Text('عكس القيد', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('هل أنت متأكد من عكس هذا القيد؟', style: GoogleFonts.cairo(fontSize: 14)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رقم القيد: ${entry.entryNumber}', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                    if (entry.description != null)
                      Text('الوصف: ${_cleanDescription(entry.description)}', style: GoogleFonts.cairo(fontSize: 12)),
                    Text('التاريخ: ${_dateFormat.format(entry.entryDate)}', style: GoogleFonts.cairo(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'سيتم إنشاء قيد عكسي بمبالغ معكوسة (المدين يصبح دائن والعكس)',
                style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
              ),
              // MJE-2: an auto-posted JE is normally the byproduct of a
              // source document (invoice/voucher/...). Reversing it here
              // fixes the GL but doesn't touch that document's own status,
              // so the two can drift apart — warn, but still allow it.
              if (entry.isAutoPosted) ...[
                const SizedBox(height: 8),
                Text(
                  'هذا قيد آلي — الأفضل عكسه من المستند المصدر (الفاتورة/السند).',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(PhosphorIconsBold.arrowUUpLeft, size: 16),
              label: const Text('تأكيد العكس'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // MJE-3: same local permission gate as saveManualEntry — reversing a
    // journal entry posts a brand-new manual GL entry and is just as much
    // an escape hatch as creating one.
    if (!await _requireAccountingJournalPermission() || !mounted) return;

    try {
      final accountingService = ref.read(accountingServiceProvider);
      // F-02 fix (MJE-1 / MJE-2): reverse by the entry's OWN primary key,
      // not by (referenceType, referenceId) — see reverseJournalEntryById
      // doc for why the old reverseTransaction call was unsafe here.
      final newEntryId = await accountingService.reverseJournalEntryById(
        entryId: entry.id,
        descriptionPrefix: 'عكس قيد: ${entry.entryNumber}',
      );
      if (mounted) {
        if (newEntryId > 0) {
          AppToast.show(context, 'تم عكس القيد بنجاح', type: ToastType.success);
        } else {
          AppToast.show(
            context,
            'القيد معكوس بالفعل أو تعذّر العكس',
            type: ToastType.warning,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في عكس القيد: $e', type: ToastType.error);
      }
    }
  }
}