// الأصل: lib/presentation/screens/treasury_screen.dart (719 سطر، مونوليث
// بلا `part of`). ثلاث كلاسات داخلية خاصة فيه — `_TreasuryClickTab`
// (تبويب ٣: تحويل كليك)، `_CashFlowTab` (تبويب ٥: تحليل التدفقات النقدية)،
// و`_ReconciliationDialog`+`_ReconciliationDialogState` (حوار مراجعة
// الأرصدة) — منسوخة هنا حرفياً بلا أي تعديل منطقي (بما فيها التعليقات
// وأسماء الحقول). أي إصلاح منطقي حقيقي (باج) لازم يتصلّح في المصدر
// (treasury_screen.dart) أولاً ثم يتنقل بـ patch (مصيدة النسخ §٥.٨) —
// من غير ما نلمس D:\URAL-ERP.
//
// الودجتس المعيارية (`TreasuryMetricsPanel`، `TreasuryCashTab`،
// `TreasuryBankTab`، `TreasuryClosingTab`، `TreasurySafeCard`،
// `TreasuryTransactionsList`) والحوارات (`ReceiptVoucherDialog`،
// `PaymentVoucherDialog`، `DailyClosingDialog`، `SafeManagementScreen`) من
// `treasury/widgets/` مُعاد استخدامها بالـ import كما هي — مش منسوخة.
// كذلك `scopedSafesProvider`/`safeTransactionsProvider` (الأخير مستورد
// حرفياً من treasury_screen.dart بدل ما يتكرر تعريفه)،
// `reconciliationServiceProvider`، `getCashFlowStatementUseCaseProvider`،
// و`breadcrumbProvider` معاد استخدامهم بالـ import.
//
// اللي اتغيّر هو طبقة العرض فقط: هيدر + تخطيط الشاشة يستخدموا
// `PicPosScreenScaffold` بدل الـ Scaffold+Directionality+Padding اليدوي في
// الأصل. أزرار الهيدر الأربعة (سند قبض/سند صرف/إدارة الصناديق/مراجعة
// الأرصدة) انتقلوا لـ headerActions بنفس الأيقونات والألوان والمنطق.
//
// راجع lib/presentation/screens/treasury_screen.dart (الأصل).
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../widgets/permission_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../treasury/widgets/treasury_cash_tab.dart';
import '../../treasury/widgets/treasury_metrics_panel.dart';
import '../../treasury/widgets/treasury_closing_tab.dart';
import '../../treasury/widgets/treasury_bank_tab.dart';
import '../../treasury/widgets/daily_closing_dialog.dart';
import '../../treasury/widgets/receipt_voucher_dialog.dart';
import '../../treasury/widgets/payment_voucher_dialog.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import '../../treasury/widgets/treasury_transactions_list.dart';
import '../../treasury/widgets/treasury_safe_card.dart';
import '../../treasury/widgets/safe_management_dialog.dart';
import '../../../services/reconciliation_service.dart';
import '../../providers/breadcrumb_provider.dart';
import '../../../domain/usecases/accounting/get_cashflow_statement_usecase.dart';
import '../../screens/treasury_screen.dart' show safeTransactionsProvider;
import '../../picpos_shell/picpos_screen_scaffold.dart';
// نمطُ ديالوجات PicPos — غلافُ الحوارات المشترك.
import '../../picpos_shell/picpos_dialog.dart';

/// شاشة الصناديق والخزينة بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `scopedSafesProvider`/
/// `safeTransactionsProvider`/`reconciliationServiceProvider`/
/// `getCashFlowStatementUseCaseProvider` من UralCash — فقط طبقة العرض
/// تبدّلت لـ picpos_shell (هيدر PicPosScreenScaffold بدل Scaffold يدوي).
///
/// FULL PARITY مع الأصل: أزرار الهيدر الأربعة (سند قبض/سند صرف/إدارة
/// الصناديق/مراجعة الأرصدة)، لوحة المؤشرات (TreasuryMetricsPanel)، حقل
/// البحث بمنطق التصفية والمسح، التبويبات الخمسة (نقدي/بنوك/كليك/إغلاق
/// يومي/تحليل تدفقات) وكل محتواها، حوار الإغلاق اليومي، حوار مراجعة
/// الأرصدة، وتحديث الـ breadcrumbs عند تبديل التبويب.
class TreasuryPicposScreen extends ConsumerStatefulWidget {
  const TreasuryPicposScreen({super.key});

  @override
  ConsumerState<TreasuryPicposScreen> createState() =>
      _TreasuryPicposScreenState();
}

class _TreasuryPicposScreenState extends ConsumerState<TreasuryPicposScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Initial breadcrumb update
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBreadcrumbs());
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _updateBreadcrumbs();
  }

  void _updateBreadcrumbs() {
    final labels = ['نقدي', 'بنوك', 'كليك', 'إغلاق', 'تحليل'];
    final label = labels[_tabController.index];

    ref.read(breadcrumbProvider.notifier).setBreadcrumbs([
      BreadcrumbItem(
        label: AppLocalizations.of(context)!.treasuryManagement,
        // Assuming index 10 is treasury based on common patterns in this app
        onTap: () => ref.read(breadcrumbProvider.notifier).popToLabel(
            AppLocalizations.of(context)!.treasuryManagement),
      ),
      BreadcrumbItem(label: label),
    ]);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

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

    return PicPosScreenScaffold(
      title: 'الصناديق والخزينة',
      subtitle: 'النقدية والبنوك وإغلاق اليوم',
      icon: PhosphorIconsBold.wallet,
      headerActions: [
        // ⚠️ هذا الزرُّ كان **بلا حراسة** بينما جارُه «سند صرف» محروس، وبينما
        // نفسُ الحوار محروسٌ بـ`treasury_receipts_create` في
        // `treasury/widgets/treasury_metrics_panel.dart:100` — واللوحةُ تلك
        // مرسومةٌ **على هذه الشاشة نفسِها** (`:209` أدناه).
        //
        // فبابان لنفس الفعل على شاشةٍ واحدة، أحدُهما محروسٌ والآخرُ لا. وهو
        // سهوٌ لا سياسة: الجارُ يثبت أن النيّةَ كانت الحراسة.
        PermissionGuard(
          permission: PermissionCodes.treasuryReceiptsCreate,
          allowManagerOverride: true,
          actionName: 'إنشاء سند قبض',
          child: OutlinedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (context) => const ReceiptVoucherDialog(),
            ),
            icon: const Icon(
              PhosphorIconsBold.arrowCircleDown,
              color: AppColors.success,
            ),
            label: const Text('سند قبض'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.success,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // `treasury_payments_create` كان محروساً في
        // `treasury/widgets/treasury_metrics_panel.dart` وحدَه — وهي شاشةٌ لا
        // يصل إليها PicPos، فسندُ الصرف كان يُفتح هنا بلا أيّ فحص.
        //
        // نفسُ لفّة النظير القديم بالحرف: `PermissionGuard` بـ
        // `allowManagerOverride` — فمن ينقصه الكودُ يرى حوارَ كلمة مرور
        // المسؤول بدل زرٍّ صامت.
        PermissionGuard(
          permission: PermissionCodes.treasuryPaymentsCreate,
          allowManagerOverride: true,
          actionName: 'إنشاء سند صرف',
          child: OutlinedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (context) => const PaymentVoucherDialog(),
            ),
            icon: const Icon(
              PhosphorIconsBold.arrowCircleUp,
              color: AppColors.error,
            ),
            label: const Text('سند صرف'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
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
          label: const Text('إدارة الصناديق'),
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
          label: const Text('مراجعة الأرصدة'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.info,
          ),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Balance Card
          const TreasuryMetricsPanel(),
          const SizedBox(height: 16),

          // Search bar
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث في الخزينة (سندات، صناديق)...',
                prefixIcon:
                    const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        })
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                const Tab(
                  icon: Icon(PhosphorIconsBold.cellSignalFull),
                  text: 'تحويل كليك',
                ),
                Tab(
                  icon: const Icon(PhosphorIconsBold.lockKey),
                  text: AppLocalizations.of(context)!.dailyClosing,
                ),
                const Tab(
                  icon: Icon(PhosphorIconsBold.chartLineUp),
                  text: 'تدفقات نقدية',
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
              const Text(
                'صناديق تحويل كليك',
                style: TextStyle(
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
                      return const Center(
                        child: Text(
                          'لا توجد صناديق كليك',
                          style: TextStyle(color: AppColors.textMuted),
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
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text('لا توجد حركات مالية',
                style: GoogleFonts.cairo(color: AppColors.textMuted)),
          );
        }

        final cashFlowUseCase = ref.read(getCashFlowStatementUseCaseProvider);
        final result = cashFlowUseCase.executeFromTransactions(list);

        final catLabels = <String, String>{
          'customer_payment': 'عملاء',
          'supplier_payment': 'موردين',
          'sales': 'مبيعات',
          'purchase': 'مشتريات',
          'expense': 'مصروفات',
          'salary': 'رواتب',
          'advance': 'سلف',
          'loan': 'قروض',
        };

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KPI Row
              Row(
                children: [
                  _flowCard('إجمالي الواردات', result.totalInflows,
                      PhosphorIconsBold.arrowCircleDown,
                      const Color(0xFF059669)),
                  const SizedBox(width: 16),
                  _flowCard('إجمالي الصادرات', result.totalOutflows,
                      PhosphorIconsBold.arrowCircleUp,
                      const Color(0xFFDC2626)),
                  const SizedBox(width: 16),
                  _flowCard('صافي التدفق', result.netFlow,
                      PhosphorIconsBold.arrowsLeftRight,
                      result.netFlow >= 0
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626)),
                ],
              ),
              const SizedBox(height: 24),

              // Inflow Categories
              if (result.inflowsByCategory.isNotEmpty) ...[
                Text('تفصيل الواردات',
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
                Text('تفصيل الصادرات',
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
    // نمطُ ديالوجات PicPos (تصميمُ 2026-08-21) — والعرضُ ٦٦٠ كما في التصميم
    // لا ٧٦٠: هذا حوارُ مراجعةٍ لا سندُ إدخال.
    //
    // ‏`scrollable: false` بقصد: الجسمُ يحمل قائمةً لها ارتفاعُها وتمريرُها
    // الداخليّ، فتمريرٌ خارجيٌّ فوقه يعطي شريطَي تمريرٍ متداخلَين.
    final hasDiscrepancies =
        _reports != null && _reports!.any((r) => r.discrepanciesFound > 0);

    return PicPosDialog(
      icon: PhosphorIconsBold.scales,
      accent: AppColors.info,
      title: 'مراجعة الأرصدة',
      subtitle: 'مطابقة الأرصدة الفعلية مع دفتر الأستاذ',
      width: 660,
      scrollable: false,
      onCancel: () => Navigator.pop(context),
      cancelLabel: 'إغلاق',
      secondaryActions: [
        PicPosDialogAction(
          label: 'إعادة الفحص',
          icon: PhosphorIconsBold.arrowsClockwise,
          onPressed: _loading ? null : () => _runReconciliation(),
        ),
      ],
      // لا زرَّ إصلاحٍ حين لا فرقَ يُصلَح — إجراءٌ بلا أثرٍ أسوأُ من غيابه.
      primaryAction: hasDiscrepancies
          ? PicPosDialogAction(
              label: 'إصلاح تلقائي',
              icon: PhosphorIconsBold.wrench,
              color: AppColors.warning,
              // الدوّارةُ تبقى كما كانت: الإصلاحُ يمسّ أرصدةً، فإخفاءُ
              // انشغاله كان يغري بنقرةٍ ثانية.
              busy: _fixing,
              onPressed: _fixing ? null : () => _runReconciliation(autoFix: true),
            )
          : null,
      body: [
        SizedBox(
          height: 380,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _reports == null
                  ? const Center(child: Text('لم يتم تشغيل المراجعة بعد'))
                  : _buildReportsView(),
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
                      ? 'جميع الأرصدة متطابقة ✅'
                      : '$totalDiscrepancies فرق مكتشف${totalFixed > 0 ? ' — تم إصلاح $totalFixed' : ''}',
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
          'تم فحص ${report.totalChecked} — ${report.discrepanciesFound} فرق${report.fixed > 0 ? ' — تم إصلاح ${report.fixed}' : ''}',
          style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
        ),
        children: report.discrepancies.map((d) => ListTile(
          dense: true,
          title: Text(d.entityName, style: GoogleFonts.cairo(fontSize: 12)),
          subtitle: Text(
            'مخزّن: ${d.cachedValue.toStringAsFixed(AppConstants.decimalPlaces)} | محسوب: ${d.calculatedValue.toStringAsFixed(AppConstants.decimalPlaces)} | فرق: ${d.difference.toStringAsFixed(AppConstants.decimalPlaces)}',
            style: GoogleFonts.cairo(fontSize: 10, color: AppColors.error),
          ),
        )).toList(),
      ),
    );
  }
}
