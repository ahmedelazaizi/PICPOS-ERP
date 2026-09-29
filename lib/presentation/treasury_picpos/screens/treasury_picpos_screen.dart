import 'package:ural_erp/core/i18n/tr.dart';
// الأصل: lib/presentation/screens/treasury_screen.dart (719 سطر، مونوليث
// بلا `part of`). كلاسان داخليان منسوخان منه حرفياً — `_CashFlowTab`
// (تبويب ٥: تحليل التدفقات النقدية) و`_ReconciliationDialog`+
// `_ReconciliationDialogState` (حوار مراجعة الأرصدة) — بلا أي تعديل منطقي.
//
// ⚠️ **وتعليقُ «مصيدة النسخ §٥.٨» الذي كان هنا حُذف**: كان يوجب إصلاحَ أيّ
// باجٍ في المصدر أوّلاً ثمّ نقلَه بـ patch — وقد كُتب حين كان النقلُ إلى
// UralCash هدفاً. وقرارُ المالك 2026-08-22 ألغى ذلك صراحةً: «العملُ على
// UralCash موقوف، فإذا أردتَ أن تعمل بشيءٍ على PicPos فانسخه إلى PicPos ولا
// تشارك تعديلاتِ PicPos على UralCash».
//
// ── ما صار فوركاً بهذا القرار ────────────────────────────────────────────
//   • `treasury_metrics_panel_picpos.dart`  — البطاقةُ الداكنة + التقسيم
//   • `treasury_actions_grid_picpos.dart`   — شبكةُ الأزرار ٢×٢ + حرّاسُها
//   • `treasury_tab_bar_picpos.dart`        — شريطُ التبويبات + البحث
//   • `treasury_panes_picpos.dart`          — لوحا الصناديق والحركات
//   • `treasury_safe_card_picpos.dart` · `treasury_movements_list_picpos.dart`
//
// و`TreasuryPanesPicpos` **تحلُّ محلَّ ثلاثِ ودجتات** كان الأصلُ يكتبها نسخاً
// متطابقةً (`TreasuryCashTab` · `TreasuryBankTab` · `_TreasuryClickTab`) —
// القرارُ يمنع المشاركةَ مع UralCash، لا يأمر بالنسخ ثلاثاً داخلَ PicPos.
//
// ويبقى معادَ استخدامه بالـ import كما هو: `TreasuryClosingTab` والحوارات
// (`ReceiptVoucherDialog`، `PaymentVoucherDialog`، `DailyClosingDialog`،
// `SafeManagementScreen`)، و`scopedSafesProvider`/`safeTransactionsProvider`
// (الأخير مستورد حرفياً من treasury_screen.dart بدل ما يتكرر تعريفه)،
// `reconciliationServiceProvider` و`getCashFlowStatementUseCaseProvider`.
//
// راجع lib/presentation/screens/treasury_screen.dart (الأصل).
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
// لوحُ المقاييس صار فوركاً في PicPos (قرارُ المالك 2026-08-22) — يضيف شريطَ
// تقسيم الرصيد، وشاشةُ UralCash تبقى على الأصل.
import '../widgets/treasury_metrics_panel_picpos.dart';
// شبكةُ الأزرار ٢×٢ وشريطُ التبويبات ولوحا الصناديق/الحركات — كلُّها من
// التصميم، وكلُّها فوركٌ داخلَ مجلد التوأم.
import '../widgets/treasury_actions_grid_picpos.dart';
import '../widgets/treasury_panes_picpos.dart';
import '../widgets/treasury_tab_bar_picpos.dart';
import '../../../domain/models/picpos_treasury_view.dart';
import '../../treasury/widgets/treasury_closing_tab.dart';
import '../../treasury/widgets/daily_closing_dialog.dart';
import '../widgets/receipt_voucher_dialog_picpos.dart';
import '../widgets/payment_voucher_dialog_picpos.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import '../../treasury/widgets/safe_management_dialog.dart';
import '../../../services/reconciliation_service.dart';
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
/// الأرصدة.
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
  }

  @override
  void dispose() {
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
      title: tr('الصناديق والخزينة'),
      subtitle: tr('النقدية والبنوك وإغلاق اليوم'),
      icon: PhosphorIconsBold.wallet,
      // ⚠️ **الأزرارُ الأربعةُ لم تعد هنا.** التصميمُ يضعها شبكةَ ٢×٢ يسارَ
      // البطاقة الداكنة (`grid-template-columns: 1fr 620px`) لا في شريط
      // الهيدر — وحرّاسُها انتقلت معها إلى
      // `widgets/treasury_actions_grid_picpos.dart`. راجع تعليقَ ذلك الملفّ:
      // النقلُ وحدَه كان سيُسقط الفعلَ بعد موافقة المدير.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // التصميم: `1fr 620px`. وعلى نافذةٍ أضيقَ يُقلَّص العمودُ الثابت
              // بدل أن يُصفَّر عرضُ البطاقة الداكنة أو يفيض الصفّ.
              final actionsWidth = math.min(620.0, constraints.maxWidth * .45);
              // ⚠️ `IntrinsicHeight` إلزاميّة: `stretch` داخلَ `Column` تطلب
              // ارتفاعاً غيرَ محدودٍ فتُرمى — وفي الإصدار تُرسم شاشةٌ بيضاء.
              // مقيسٌ في `picpos_treasury_layout_test`.
              return IntrinsicHeight(
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Total Balance Card
                  // تقسيمُ الرصيد يُمرَّر إلى اللوح فيرسمه **داخل** بطاقته
                  // الداكنة — كما في التصميم، وكما يوجب عقدُ الألوان.
                  //
                  // ويُبنى من **نفس** `scopedSafesProvider` الذي تقرؤه بطاقاتُ
                  // الصناديق، فالمجموعُ هو مجموعُ ما يُعرض تحته بالضبط
                  // (مسقوفاً بنطاق الفرع كما هو).
                  Expanded(
                    child: TreasuryMetricsPanelPicpos(
                      split: safes.whenOrNull(
                        data: (rows) => PicPosTreasurySplit.from([
                          for (final s in rows)
                            (kind: s.safeType, balance: s.balance),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: actionsWidth,
                    child: TreasuryActionsGridPicpos(
                      onReceipt: () => showDialog(
                        context: context,
                        builder: (_) => const ReceiptVoucherDialogPicpos(),
                      ),
                      onPayment: () => showDialog(
                        context: context,
                        builder: (_) => const PaymentVoucherDialogPicpos(),
                      ),
                      onSafes: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SafeManagementScreen(),
                        ),
                      ),
                      onReconcile: () => _showReconciliationDialog(context),
                    ),
                  ),
                ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // شريطُ التبويبات على شكل التصميم، وبحثُ الشاشة في آخره.
          TreasuryTabBarPicpos(
            controller: _tabController,
            searchController: _searchController,
            searchQuery: _searchQuery,
            onSearchChanged: (v) =>
                setState(() => _searchQuery = v.trim().toLowerCase()),
            tabs: [
              (
                label: AppLocalizations.of(context)!.cashSafes,
                icon: PhosphorIconsBold.money
              ),
              (
                label: AppLocalizations.of(context)!.bankAccounts,
                icon: PhosphorIconsBold.bank
              ),
              (label: tr('تحويل كليك'), icon: PhosphorIconsBold.cellSignalFull),
              (
                label: AppLocalizations.of(context)!.dailyClosing,
                icon: PhosphorIconsBold.lockKey
              ),
              (label: tr('تدفقات نقدية'), icon: PhosphorIconsBold.chartLineUp),
            ],
          ),
          const SizedBox(height: 12),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // التبويباتُ الثلاثةُ الأولى **لوحٌ واحدٌ مرشَّح** لا ثلاثُ
                // نسخ — كما يقول التصميمُ نفسُه
                // (`list = tab==='bank' ? bank : tab==='click' ? click : …`).
                TreasuryPanesPicpos(
                  safes: safes,
                  transactions: transactions,
                  safeType: 'cash',
                  emptyLabel: tr('لا توجد صناديق نقدية'),
                  searchQuery: _searchQuery,
                ),
                TreasuryPanesPicpos(
                  safes: safes,
                  transactions: transactions,
                  safeType: 'bank',
                  emptyLabel: AppLocalizations.of(context)!.noBankAccounts,
                  searchQuery: _searchQuery,
                ),
                TreasuryPanesPicpos(
                  safes: safes,
                  transactions: transactions,
                  safeType: 'click',
                  emptyLabel: tr('لا توجد صناديق كليك'),
                  searchQuery: _searchQuery,
                ),

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
      title: tr('مراجعة الأرصدة'),
      subtitle: tr('مطابقة الأرصدة الفعلية مع دفتر الأستاذ'),
      width: 660,
      scrollable: false,
      onCancel: () => Navigator.pop(context),
      cancelLabel: tr('إغلاق'),
      secondaryActions: [
        PicPosDialogAction(
          label: tr('إعادة الفحص'),
          icon: PhosphorIconsBold.arrowsClockwise,
          onPressed: _loading ? null : () => _runReconciliation(),
        ),
      ],
      // لا زرَّ إصلاحٍ حين لا فرقَ يُصلَح — إجراءٌ بلا أثرٍ أسوأُ من غيابه.
      primaryAction: hasDiscrepancies
          ? PicPosDialogAction(
              label: tr('إصلاح تلقائي'),
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
                  ?  Center(child: Text(tr('لم يتم تشغيل المراجعة بعد')))
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
