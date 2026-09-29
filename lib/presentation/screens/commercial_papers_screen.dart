import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:ural_erp/core/constants/app_constants.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/database/database.dart' as db;
import '../../data/providers/providers.dart';
import '../../domain/repositories/commercial_papers_repository.dart' hide commercialPapersRepositoryProvider;
import '../../domain/repositories/parties_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../../services/printing/report_pdf_generator.dart';
import '../../services/client_write_interceptor.dart';
import 'commercial_papers/create_paper_action.dart';
import 'commercial_papers/widgets/status_change_dialog.dart';
import 'commercial_papers/widgets/renew_paper_dialog.dart';
import 'commercial_papers/widgets/partial_collection_dialog.dart';
import 'commercial_papers/widgets/endorse_paper_dialog.dart';
import 'commercial_papers/widgets/deposit_for_collection_dialog.dart';
import 'commercial_papers/widgets/reissue_paper_dialog.dart';
import 'commercial_papers/widgets/create_paper_dialog.dart';

part 'commercial_papers_dialogs.dart';

/// Commercial Papers Screen — الأوراق التجارية (شيكات/كمبيالات)
/// Manage received and issued cheques with full status lifecycle
class CommercialPapersScreen extends ConsumerStatefulWidget {
  const CommercialPapersScreen({super.key});

  @override
  ConsumerState<CommercialPapersScreen> createState() =>
      _CommercialPapersScreenState();
}

class _CommercialPapersScreenState
    extends ConsumerState<CommercialPapersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _statusFilter = 'all';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  final _dateFormat = DateFormat('yyyy/MM/dd');
  final Map<int, String> _partyNameCache = {};

  // ═══ CACHED STREAMS — prevents StreamBuilder reset on setState ═══
  Stream<List<dynamic>>? _receivedStream;
  Stream<List<dynamic>>? _issuedStream;
  Stream<List<dynamic>>? _portfolioStream;
  String _lastStatusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    // Only rebuild for tab visual changes, not entire widget tree
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _currentDirection {
    switch (_tabCtrl.index) {
      case 0: return 'received';
      case 1: return 'issued';
      case 2: return 'portfolio';
      default: return 'received';
    }
  }

  /// Create/refresh cached streams when filter changes
  void _ensureStreams(ICommercialPapersRepository repo) {
    if (_receivedStream != null && _lastStatusFilter == _statusFilter) return;
    _lastStatusFilter = _statusFilter;
    final status = _statusFilter == 'all' ? null : _statusFilter;
    _receivedStream = repo.watchCommercialPapers(direction: 'received', status: status);
    _issuedStream = repo.watchCommercialPapers(direction: 'issued', status: status);
    _portfolioStream = repo.watchCommercialPapers(direction: 'received', status: 'in_portfolio');
  }

  /// Invalidate streams to force refresh
  void _invalidateStreams() {
    _receivedStream = null;
    _issuedStream = null;
    _portfolioStream = null;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(commercialPapersRepositoryProvider);
    final partiesRepo = ref.watch(partiesRepositoryProvider);
    final treasuryRepo = ref.watch(treasuryRepositoryProvider);

    // Ensure streams are created/refreshed
    _ensureStreams(repo);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text(
            tr('الأوراق التجارية'),
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
          ),
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs:  [
              Tab(icon: const Icon(PhosphorIconsBold.arrowDown), text: tr('واردة')),
              Tab(icon: const Icon(PhosphorIconsBold.arrowUp), text: tr('صادرة')),
              Tab(icon: const Icon(PhosphorIconsBold.folder), text: tr('الحافظة')),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(PhosphorIconsBold.funnel, color: Colors.white),
              onSelected: (v) {
                _invalidateStreams(); // Force new streams with new filter
                setState(() => _statusFilter = v);
              },
              itemBuilder: (_) =>  [
                PopupMenuItem(value: 'all', child: Text(tr('الكل'))),
                PopupMenuItem(value: 'pending', child: Text(tr('معلق'))),
                PopupMenuItem(value: 'in_portfolio', child: Text(tr('في الحافظة'))),
                PopupMenuItem(value: 'deposited', child: Text(tr('مودع'))),
                PopupMenuItem(value: 'deposited_for_collection', child: Text(tr('برسم التحصيل'))),
                PopupMenuItem(value: 'cashed', child: Text(tr('محصّل'))),
                PopupMenuItem(value: 'bounced', child: Text(tr('مرتد'))),
                PopupMenuItem(value: 'endorsed', child: Text(tr('مظهّر'))),
                PopupMenuItem(value: 'cancelled', child: Text(tr('ملغي'))),
              ],
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.chartPie),
              tooltip: tr('ملخص'),
              onPressed: () => showSummary(repo),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: tr('بحث عن شيك (رقم، بنك، مبلغ)...'),
                  prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildPapersList(_receivedStream!, repo, partiesRepo, treasuryRepo, 'received'),
                  _buildPapersList(_issuedStream!, repo, partiesRepo, treasuryRepo, 'issued'),
                  _buildPortfolioList(_portfolioStream!, repo, partiesRepo, treasuryRepo),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showCreateDialog(repo, partiesRepo, treasuryRepo),
          backgroundColor: AppColors.primary,
          icon: const Icon(PhosphorIconsBold.plus, color: Colors.white),
          label: Text(
            _tabCtrl.index == 0 ? tr('شيك وارد') : _tabCtrl.index == 1 ? tr('شيك صادر') : tr('شيك وارد'),
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPapersList(Stream<List<dynamic>> stream, ICommercialPapersRepository repo, IPartiesRepository partiesRepo, ITreasuryRepository treasuryRepo, String direction) {
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        // Only show loading on FIRST load, not on stream refresh
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var papers = (snapshot.data ?? []).toList();
        if (_searchQuery.isNotEmpty) {
          papers = papers.where((p) =>
            p.paperNumber.toLowerCase().contains(_searchQuery) ||
            (p.bankName ?? '').toLowerCase().contains(_searchQuery) ||
            p.amount.toString().contains(_searchQuery)
          ).toList();
        }
        if (papers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  PhosphorIconsBold.receipt,
                  size: 64,
                  color: Colors.grey.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  direction == 'received'
                      ? tr('لا توجد شيكات واردة')
                      : tr('لا توجد شيكات صادرة'),
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        // Pre-load party names — NO setState, stream rebuild handles display
        _preloadPartyNames(partiesRepo, papers);

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: papers.length,
          itemBuilder: (context, i) {
            final paper = papers[i];
            return _buildPaperCard(repo, partiesRepo, treasuryRepo, paper);
          },
        );
      },
    );
  }

  /// Pre-load party names for all papers to avoid N+1 queries
  /// NOTE: Does NOT call setState to avoid triggering stream recreation
  void _preloadPartyNames(IPartiesRepository partiesRepo, List<dynamic> papers) {
    for (final paper in papers) {
      final partyId = paper.partyId as int;
      if (!_partyNameCache.containsKey(partyId)) {
        _partyNameCache[partyId] = '...';
        partiesRepo.getPartyById(partyId).then((party) {
          if (mounted && party != null) {
            // Update cache without setState — next stream event will pick it up
            _partyNameCache[partyId] = party.name;
            // Use a microtask to gently refresh without creating new streams
            Future.microtask(() {
              if (mounted) setState(() {});
            });
          }
        });
      }
    }
  }

  /// Portfolio tab — shows only checks in the portfolio (in_portfolio status)
  Widget _buildPortfolioList(Stream<List<dynamic>> stream, ICommercialPapersRepository repo, IPartiesRepository partiesRepo, ITreasuryRepository treasuryRepo) {
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final papers = snapshot.data ?? [];
        if (papers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  PhosphorIconsBold.folder,
                  size: 64,
                  color: Colors.grey.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  tr('لا توجد شيكات في الحافظة'),
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('حرّك الشيكات الواردة إلى الحافظة من تاب "واردة"'),
                  style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: papers.length,
          itemBuilder: (context, i) => _buildPaperCard(repo, partiesRepo, treasuryRepo, papers[i]),
        );
      },
    );
  }

  Widget _buildPaperCard(ICommercialPapersRepository repo, IPartiesRepository partiesRepo, ITreasuryRepository treasuryRepo, dynamic paper) {
    final dueDate = paper.dueDate as DateTime;
    final now = DateTime.now();
    final isOverdue = dueDate.isBefore(now) && paper.status == 'pending';
    final isDueSoon = !isOverdue && dueDate.isBefore(now.add(const Duration(days: 7))) && 
        (paper.status == 'pending' || paper.status == 'deposited');
    final statusInfo = getStatusInfo(paper.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isOverdue
            ? const BorderSide(color: AppColors.error, width: 1.5)
            : isDueSoon
                ? BorderSide(color: Colors.orange.shade400, width: 1.5)
                : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tappable info section
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showPaperDetails(repo, paper, partiesRepo),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Header: paper number + status
              Row(
                children: [
                  Icon(
                    getTypeIcon(paper.type),
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '#${paper.paperNumber}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusInfo.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusInfo.label,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusInfo.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Amount + party
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${paper.amount.toStringAsFixed(AppConstants.decimalPlaces)}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _partyNameCache[paper.partyId] ?? '...',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Dates
              Row(
                children: [
                  Icon(PhosphorIconsBold.calendarBlank,
                      size: 13, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    tr('إصدار: {p0}', {'p0': _dateFormat.format(paper.issueDate)}),
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    PhosphorIconsBold.calendarCheck,
                    size: 13,
                    color: isOverdue ? AppColors.error : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tr('استحقاق: {p0}', {'p0': _dateFormat.format(dueDate)}),
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w400,
                      color: isOverdue ? AppColors.error : Colors.grey.shade600,
                    ),
                  ),
                  if (isOverdue) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tr('متأخر'),
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                  if (isDueSoon) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tr('قريب الاستحقاق'),
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Bank info
              if (paper.bankName != null) ...[
                const SizedBox(height: 4),
                Text(
                  '🏦 ${paper.bankName}${paper.bankBranch != null ? ' - ${paper.bankBranch}' : ''}',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
                ],
              ),
            ),
            // Actions — OUTSIDE InkWell so taps reach ActionChips
            const Divider(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: _buildActionButtons(repo, paper, partiesRepo, treasuryRepo),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(ICommercialPapersRepository repo, dynamic paper, IPartiesRepository partiesRepo, ITreasuryRepository treasuryRepo) {
    final status = paper.status as String;
    // Feature 014 / Issue PAPER-WORDING — distinguish received vs
    // issued papers: for ISSUED (صادر) papers the "إيداع" action is
    // actually a settlement/payment (we pay from our bank), so the
    // label reads "تسديد"; "تحصيل" similarly becomes "تم التسديد".
    // For RECEIVED (وارد) papers the original wording stays.
    final isIssued = (paper.direction as String?) == 'issued';
    final depositLabel = isIssued ? tr('تسديد') : tr('إيداع');
    final reDepositLabel = isIssued ? tr('إعادة تسديد') : tr('إعادة إيداع');
    final cashedLabel = isIssued ? tr('تم التسديد') : tr('تحصيل');
    final partialCashedLabel = isIssued ? tr('تسديد جزئي') : tr('تحصيل جزئي');
    final buttons = <Widget>[];

    if (status == 'pending') {
      buttons.addAll([
        _actionChip(tr('حافظة'), PhosphorIconsBold.folder, Colors.indigo, () =>
            changeStatus(repo, paper.id, 'in_portfolio')),
        _actionChip(depositLabel, PhosphorIconsBold.bank, Colors.blue, () =>
            changeStatus(repo, paper.id, 'deposited')),
        _actionChip(tr('برسم التحصيل'), PhosphorIconsBold.buildings, Colors.cyan, () =>
            showDepositForCollectionDialog(repo, paper, treasuryRepo)),
        _actionChip(cashedLabel, PhosphorIconsBold.checkCircle,
            AppColors.success, () =>
                changeStatus(repo, paper.id, 'cashed')),
        _actionChip(partialCashedLabel, PhosphorIconsBold.percent,
            Colors.teal, () =>
                showPartialCollectionDialog(repo, paper)),
        _actionChip(tr('تظهير'), PhosphorIconsBold.arrowBendUpRight,
            Colors.orange, () =>
                showEndorseDialog(repo, paper, partiesRepo)),
        _actionChip(tr('تجديد'), PhosphorIconsBold.calendarPlus,
            Colors.deepPurple, () =>
                showRenewDialog(repo, paper)),
        _actionChip(tr('إلغاء'), PhosphorIconsBold.x, AppColors.error, () =>
            changeStatus(repo, paper.id, 'cancelled')),
      ]);
    } else if (status == 'in_portfolio') {
      buttons.addAll([
        _actionChip(tr('برسم التحصيل'), PhosphorIconsBold.buildings, Colors.cyan, () =>
            showDepositForCollectionDialog(repo, paper, treasuryRepo)),
        _actionChip(tr('إعادة إصدار'), PhosphorIconsBold.arrowBendDoubleUpRight,
            Colors.deepOrange, () =>
                showReissueDialog(repo, paper, partiesRepo)),
        _actionChip(tr('{depositLabel} مباشر', {'depositLabel': depositLabel}), PhosphorIconsBold.bank, Colors.blue, () =>
            changeStatus(repo, paper.id, 'deposited')),
        _actionChip(cashedLabel, PhosphorIconsBold.checkCircle,
            AppColors.success, () =>
                changeStatus(repo, paper.id, 'cashed')),
      ]);
    } else if (status == 'deposited' || status == 'deposited_for_collection') {
      buttons.addAll([
        _actionChip(cashedLabel, PhosphorIconsBold.checkCircle,
            AppColors.success, () =>
                changeStatus(repo, paper.id, 'cashed')),
        _actionChip(partialCashedLabel, PhosphorIconsBold.percent,
            Colors.teal, () =>
                showPartialCollectionDialog(repo, paper)),
        _actionChip(tr('ارتداد'), PhosphorIconsBold.arrowUUpLeft,
            AppColors.error, () =>
                changeStatus(repo, paper.id, 'bounced')),
      ]);
    } else if (status == 'bounced') {
      buttons.addAll([
        _actionChip(reDepositLabel, PhosphorIconsBold.bank, Colors.blue, () =>
            changeStatus(repo, paper.id, 'deposited')),
        _actionChip(tr('حافظة'), PhosphorIconsBold.folder, Colors.indigo, () =>
            changeStatus(repo, paper.id, 'in_portfolio')),
        _actionChip(tr('تجديد'), PhosphorIconsBold.calendarPlus,
            Colors.deepPurple, () =>
                showRenewDialog(repo, paper)),
      ]);
    }

    // Always show print & history
    buttons.add(
      _actionChip(tr('طباعة'), PhosphorIconsBold.printer, Colors.blueGrey, () {
        ReportPdfGenerator.printCheckVoucher(
          checkNumber: paper.paperNumber,
          amount: paper.amount,
          checkDate: paper.issueDate,
          dueDate: paper.dueDate,
          drawerName: _partyNameCache[paper.partyId] ?? '-',
          bankName: paper.bankName,
          direction: paper.direction,
          status: paper.status,
          notes: paper.notes,
        );
      }),
    );
    buttons.add(
      _actionChip(tr('السجل'), PhosphorIconsBold.clockCounterClockwise,
          Colors.grey.shade600, () => showHistory(repo, paper.id)),
    );

    return buttons;
  }

  Widget _actionChip(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(
        label,
        style: GoogleFonts.cairo(fontSize: 10, color: color),
      ),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.2)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}