import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../treasury/widgets/treasury_cash_tab.dart';
import '../treasury/widgets/treasury_metrics_panel.dart';
import '../treasury/widgets/treasury_closing_tab.dart';
import '../treasury/widgets/treasury_bank_tab.dart';
import '../treasury/widgets/daily_closing_dialog.dart';
import '../treasury/widgets/receipt_voucher_dialog.dart';
import '../treasury/widgets/payment_voucher_dialog.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import '../treasury/widgets/treasury_transactions_list.dart';
import '../treasury/widgets/treasury_safe_card.dart';
import '../treasury/widgets/safe_management_dialog.dart';
import '../../services/reconciliation_service.dart';
import '../../domain/usecases/accounting/get_cashflow_statement_usecase.dart';

/// Provider for safe transactions.
///
/// Issue 14 — proxies through `scopedRecentTransactionsProvider` so a
/// branch-restricted user only sees vouchers from safes in their allowed
/// branches. Admin / financial manager keeps the full list.
final safeTransactionsProvider = StreamProvider<List<TransactionData>>((
  ref,
) {
  final scopedAsync = ref.watch(scopedRecentTransactionsProvider);
  // Flatten the AsyncValue back into a Stream so existing consumers
  // (FutureBuilder, ListView) keep working without refactoring.
  return scopedAsync.maybeWhen(
    data: Stream<List<TransactionData>>.value,
    orElse: () => const Stream<List<TransactionData>>.empty(),
  );
});

/// Treasury management screen with party payments
class TreasuryScreen extends ConsumerStatefulWidget {
  const TreasuryScreen({super.key});

  @override
  ConsumerState<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends ConsumerState<TreasuryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RECEIPT VOUCHER (PARTY PAYMENT FROM CUSTOMER)
  // ═══════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // Feature 005 Phase 8 — branch-scoped: a branch manager sees only their
    // branch's safes (e.g. مدير فرع العقبة sees only صناديق العقبة, not
    // الادارة / مطعم معان / سوبر ماركت معان). Admin / financial manager keep
    // the full list because their BranchScope is fullAccess.
    final safes = ref.watch(scopedSafesProvider);
    final transactions = ref.watch(safeTransactionsProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    PhosphorIconsBold.wallet,
                    size: 32,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)!.treasuryManagement,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.headlineMedium?.color,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (context) => const ReceiptVoucherDialog(),
                    ),
                    icon: const Icon(
                      PhosphorIconsBold.arrowCircleDown,
                      color: AppColors.success,
                    ),
                    label:  Text(tr('سند قبض')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (context) => const PaymentVoucherDialog(),
                    ),
                    icon: const Icon(
                      PhosphorIconsBold.arrowCircleUp,
                      color: AppColors.error,
                    ),
                    label:  Text(tr('سند صرف')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SafeManagementScreen(),
                      ),
                    ),
                    icon: const Icon(
                      PhosphorIconsBold.vault,
                      color: AppColors.primary,
                    ),
                    label:  Text(tr('إدارة الصناديق')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showReconciliationDialog(context),
                    icon: const Icon(
                      PhosphorIconsBold.scales,
                      color: AppColors.info,
                    ),
                    label:  Text(tr('مراجعة الأرصدة')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Total Balance Card
              const TreasuryMetricsPanel(),
              const SizedBox(height: 16),

              // Search bar
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: tr('بحث في الخزينة (سندات، صناديق)...'),
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

              // Tab Bar for Cash / Bank / Daily Closing
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textMuted,
                  indicatorColor: AppColors.primary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    Tab(
                      icon: const Icon(PhosphorIconsBold.money),
                      text: AppLocalizations.of(context)!.cashSafes,
                    ),
                    Tab(
                      icon: const Icon(PhosphorIconsBold.bank),
                      text: AppLocalizations.of(context)!.bankAccounts,
                    ),
                     Tab(
                      icon: const Icon(PhosphorIconsBold.cellSignalFull),
                      text: tr('تحويل كليك'),
                    ),
                    Tab(
                      icon: const Icon(PhosphorIconsBold.lockKey),
                      text: AppLocalizations.of(context)!.dailyClosing,
                    ),
                     Tab(
                      icon: const Icon(PhosphorIconsBold.chartLineUp),
                      text: tr('تدفقات نقدية'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Cash Report
                    TreasuryCashTab(safes: safes, transactions: transactions),

                    // Tab 2: Bank Transfers
                    TreasuryBankTab(safes: safes, transactions: transactions),

                    // Tab 3: Click Transfer
                    _TreasuryClickTab(safes: safes, transactions: transactions),

                    // Tab 4: Daily Closing
                    TreasuryClosingTab(
                      safes: safes,
                      onClosing: _showDailyClosingDialog,
                    ),

                    // Tab 5: Cash Flow Analytics
                    _CashFlowTab(transactions: transactions),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDailyClosingDialog(SafeData safe) {
    showDialog(
      context: context,
      builder: (context) => DailyClosingDialog(safe: safe),
    );
  }

  void _showReconciliationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: _ReconciliationDialog(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3: CLICK TRANSFER — تحويل كليك
// ═══════════════════════════════════════════════════════════════════════════

class _TreasuryClickTab extends StatelessWidget {
  final AsyncValue<List<SafeData>> safes;
  final AsyncValue<List<TransactionData>> transactions;

  const _TreasuryClickTab({
    required this.safes,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Click Safes List
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(
                tr('صناديق تحويل كليك'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: safes.when(
                  data: (list) {
                    final clickSafes = list
                        .where((s) => s.safeType == 'click')
                        .toList();
                    if (clickSafes.isEmpty) {
                      return  Center(
                        child: Text(
                          tr('لا توجد صناديق كليك'),
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: clickSafes.length,
                      itemBuilder: (context, index) {
                        return TreasurySafeCard(
                          safe: clickSafes[index],
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Click Transactions
        Expanded(
          flex: 2,
          child: safes.when(
            data: (list) {
              final clickSafeIds = list
                  .where((s) => s.safeType == 'click')
                  .map((s) => s.id)
                  .toList();
              return TreasuryTransactionsList(
                transactions: transactions,
                typeFilter: 'click',
                safeIds: clickSafeIds,
              );
            },
            loading: () => TreasuryTransactionsList(
              transactions: transactions,
              typeFilter: 'click',
            ),
            error: (_, _) => TreasuryTransactionsList(
              transactions: transactions,
              typeFilter: 'click',
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 5: CASH FLOW ANALYTICS — تحليل التدفقات النقدية
// ═══════════════════════════════════════════════════════════════════════════

class _CashFlowTab extends ConsumerWidget {
  final AsyncValue<List<TransactionData>> transactions;

  const _CashFlowTab({required this.transactions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return transactions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(tr('لا توجد حركات مالية'),
                style: GoogleFonts.cairo(color: AppColors.textMuted)),
          );
        }

        final cashFlowUseCase = ref.read(getCashFlowStatementUseCaseProvider);
        final result = cashFlowUseCase.executeFromTransactions(list);

        final catLabels = <String, String>{
          'customer_payment': tr('عملاء'),
          'supplier_payment': tr('موردين'),
          'sales': tr('مبيعات'),
          'purchase': tr('مشتريات'),
          'expense': tr('مصروفات'),
          'salary': tr('رواتب'),
          'advance': tr('سلف'),
          'loan': tr('قروض'),
        };

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KPI Row
              Row(
                children: [
                  _flowCard(tr('إجمالي الواردات'), result.totalInflows,
                      PhosphorIconsBold.arrowCircleDown,
                      const Color(0xFF059669)),
                  const SizedBox(width: 16),
                  _flowCard(tr('إجمالي الصادرات'), result.totalOutflows,
                      PhosphorIconsBold.arrowCircleUp,
                      const Color(0xFFDC2626)),
                  const SizedBox(width: 16),
                  _flowCard(tr('صافي التدفق'), result.netFlow,
                      PhosphorIconsBold.arrowsLeftRight,
                      result.netFlow >= 0
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626)),
                ],
              ),
              const SizedBox(height: 24),

              // Inflow Categories
              if (result.inflowsByCategory.isNotEmpty) ...[
                Text(tr('تفصيل الواردات'),
                    style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...result.inflowsByCategory.entries.map((e) => _catBar(
                      catLabels[e.key] ?? e.key,
                      e.value,
                      result.totalInflows,
                      const Color(0xFF059669),
                    )),
                const SizedBox(height: 20),
              ],

              // Outflow Categories
              if (result.outflowsByCategory.isNotEmpty) ...[
                Text(tr('تفصيل الصادرات'),
                    style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...result.outflowsByCategory.entries.map((e) => _catBar(
                      catLabels[e.key] ?? e.key,
                      e.value,
                      result.totalOutflows,
                      const Color(0xFFDC2626),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _flowCard(
      String title, double amount, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(amount.toStringAsFixed(AppConstants.decimalPlaces),
                style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color)),
            Text(title,
                style: GoogleFonts.cairo(
                    fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _catBar(String label, double value, double total, Color color) {
    final pct = total > 0 ? value / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
              width: 80,
              child: Text(label,
                  style: GoogleFonts.cairo(
                      fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 14,
                backgroundColor: color.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
                '${value.toStringAsFixed(0)} (${(pct * 100).toStringAsFixed(0)}%)',
                textAlign: TextAlign.end,
                style: GoogleFonts.cairo(
                    fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

}

/// Dialog showing full reconciliation report
class _ReconciliationDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ReconciliationDialog> createState() => _ReconciliationDialogState();
}

class _ReconciliationDialogState extends ConsumerState<_ReconciliationDialog> {
  List<ReconciliationReport>? _reports;
  bool _loading = false;
  bool _fixing = false;

  @override
  void initState() {
    super.initState();
    _runReconciliation();
  }

  Future<void> _runReconciliation({bool autoFix = false}) async {
    setState(() => autoFix ? _fixing = true : _loading = true);
    final service = ref.read(reconciliationServiceProvider);
    final reports = await service.runFullReconciliation(autoFix: autoFix);
    if (mounted) {
      setState(() {
        _reports = reports;
        _loading = false;
        _fixing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.scales, color: AppColors.info, size: 22),
          const SizedBox(width: 8),
          Text(tr('مراجعة الأرصدة'),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 380,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _reports == null
                ?  Center(child: Text(tr('لم يتم تشغيل المراجعة بعد')))
                : _buildReportsView(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr('إغلاق')),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : () => _runReconciliation(),
          icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 16),
          label:  Text(tr('إعادة الفحص')),
        ),
        if (_reports != null && _reports!.any((r) => r.discrepanciesFound > 0))
          ElevatedButton.icon(
            onPressed: _fixing ? null : () => _runReconciliation(autoFix: true),
            icon: _fixing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(PhosphorIconsBold.wrench, size: 16),
            label:  Text(tr('إصلاح تلقائي')),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
          ),
      ],
    );
  }

  Widget _buildReportsView() {
    final totalDiscrepancies = _reports!.fold<int>(0, (sum, r) => sum + r.discrepanciesFound);
    final totalFixed = _reports!.fold<int>(0, (sum, r) => sum + r.fixed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: totalDiscrepancies == 0
                ? AppColors.success.withValues(alpha: 0.08)
                : AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: totalDiscrepancies == 0
                  ? AppColors.success.withValues(alpha: 0.3)
                  : AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                totalDiscrepancies == 0
                    ? PhosphorIconsBold.checkCircle
                    : PhosphorIconsBold.warning,
                color: totalDiscrepancies == 0 ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  totalDiscrepancies == 0
                      ? tr('جميع الأرصدة متطابقة ✅')
                      : tr('{totalDiscrepancies} فرق مكتشف{p0}', {'totalDiscrepancies': totalDiscrepancies, 'p0': totalFixed > 0 ? ' — تم إصلاح $totalFixed' : ''}),
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700,
                    color: totalDiscrepancies == 0 ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Reports table
        Expanded(
          child: ListView(
            children: _reports!.map((report) => _buildReportCard(report)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildReportCard(ReconciliationReport report) {
    final hasIssues = report.discrepanciesFound > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          hasIssues ? PhosphorIconsBold.warning : PhosphorIconsBold.checkCircle,
          color: hasIssues ? AppColors.warning : AppColors.success,
          size: 20,
        ),
        title: Text(report.entityType, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        subtitle: Text(
          tr('تم فحص {p0} — {p1} فرق{p2}', {'p0': report.totalChecked, 'p1': report.discrepanciesFound, 'p2': report.fixed > 0 ? ' — تم إصلاح ${report.fixed}' : ''}),
          style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
        ),
        children: report.discrepancies.map((d) => ListTile(
          dense: true,
          title: Text(d.entityName, style: GoogleFonts.cairo(fontSize: 12)),
          subtitle: Text(
            tr('مخزّن: {p0} | محسوب: {p1} | فرق: {p2}', {'p0': d.cachedValue.toStringAsFixed(AppConstants.decimalPlaces), 'p1': d.calculatedValue.toStringAsFixed(AppConstants.decimalPlaces), 'p2': d.difference.toStringAsFixed(AppConstants.decimalPlaces)}),
            style: GoogleFonts.cairo(fontSize: 10, color: AppColors.error),
          ),
        )).toList(),
      ),
    );
  }
}
