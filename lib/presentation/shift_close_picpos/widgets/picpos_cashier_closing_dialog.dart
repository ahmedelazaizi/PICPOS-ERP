import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../pos/providers/pos_notification_provider.dart';
import '../../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../pos/providers/pos_closing_controller.dart';

// منطق منسوخ حرفياً من lib/presentation/pos/widgets/pos_cashier_closing_dialog.dart
// (الأصل، ١٠٦٦ سطر — حوار مطابقة/إغلاق وردية الكاشير: مطابقة نقد/بنك/كليك/آجل،
// التحقق من فرق الجرد، مصادقة كلمة مرور/بطاقة/مدير، ونشر قيد التسوية المحاسبي
// عبر `handleClosing`). أي إصلاح منطقي هنا يتصلّح في المصدر أولاً ثم يُنقل
// بـ patch (مصيدة النسخ §٥.٨). النسخ من ملفنا الموجود في هذا الريبو — أبداً من
// D:\URAL-ERP.
//
// هذا كود مالي حساس (يُنهي الوردية ويسجّل قيد محاسبي فعلي) — لذلك كل جسم
// method اتنسخ حرفياً بلا أي تعديل منطقي. المتغيّر الوحيد هو الـ presentation
// chrome: شكل/حدود/رأس AlertDialog الخارجي، تنسيق حاويات الأقسام (بطاقات
// المطابقة/الاختيار)، تنسيق رأس جدول المطابقة، وشكل الأزرار — لهوية PicPos
// أنظف (بطاقات مسطحة بحدود بدل ظل Material، زوايا دائرية أوسع، رأس بشريط لون
// سفلي زي بقية شاشات PicPos). كل الـ TextEditingControllers، كل نداءات
// ref.read/watch، تدفق `_handleClosingAction` بالكامل (بما فيه حواري
// التأكيد المتداخلين)، فروع المصادقة (quick/msr_card/admin_password/normal)،
// منطق تجاوز الفرق (variance)، `_buildShiftPicker`، ومنطق حساب كل خلايا جدول
// المطابقة — كل ده منسوخ حرفياً بلا أي تغيير. لو شلت كل تعديلات الـ chrome،
// المنطق المتبقي لازم يكون مطابق حرفياً للأصل.
/// Dialog for cashier shift closing and reconciliation — نسخة PicPos.
class PicposCashierClosingDialog extends ConsumerStatefulWidget {
  const PicposCashierClosingDialog({super.key});

  @override
  ConsumerState<PicposCashierClosingDialog> createState() =>
      _PicposCashierClosingDialogState();

  /// Static helper to show the dialog
  static Future<void> show(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PicposCashierClosingDialog(),
    );
  }
}

class _PicposCashierClosingDialogState
    extends ConsumerState<PicposCashierClosingDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _actualCashController = TextEditingController();
  final TextEditingController _actualCardController = TextEditingController();
  final TextEditingController _actualClickController = TextEditingController();
  final TextEditingController _msrCardController = TextEditingController();
  String? _selectedMethod;

  @override
  void dispose() {
    _passwordController.dispose();
    _actualCashController.dispose();
    _actualCardController.dispose();
    _actualClickController.dispose();
    _msrCardController.dispose();
    super.dispose();
  }

  /// Spec 135 NOTE 2 (req 4) — picker shown to a system admin when more than
  /// one cashier shift is open on the terminal. Selecting one reloads the
  /// closing dialog scoped to that shift, which the admin then reconciles and
  /// closes (recording any variance).
  Widget _buildShiftPicker(PosClosingState closingState) {
    String fmt(DateTime d) {
      final m = d.minute.toString().padLeft(2, '0');
      return '${d.day}/${d.month} ${d.hour}:$m';
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'توجد أكثر من وردية مفتوحة — اختر الوردية المراد مطابقتها وإغلاقها',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          ...closingState.selectableShifts.map(
            (s) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(PhosphorIconsBold.cashRegister,
                    color: AppColors.primary),
                title: Text('وردية رقم ${s.id} — كاشير #${s.userId}'),
                subtitle: Text(
                    'بدأت: ${fmt(s.startTime)} — رصيد افتتاحي: ${s.openingBalance.toStringAsFixed(AppConstants.decimalPlaces)}'),
                trailing: const Icon(PhosphorIconsBold.caretLeft),
                onTap: () => ref
                    .read(posClosingControllerProvider.notifier)
                    .selectTargetShift(s.id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final perms = ref.watch(currentUserPermissionsProvider).value ?? [];
    final isAdmin = authState.isAdmin || authState.isManager;
    final canViewDetails = isAdmin || perms.contains(PermissionCodes.posClosingViewDetails);

    final closingState = ref.watch(posClosingControllerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        // ── PicPos chrome: نفس أسلوب رأس الحوارات الأخرى (أيقونة داخل
        // مربع ملون + عنوان، وشريط لون سفلي بدل ظل الـ AlertDialog الافتراضي).
        title: Container(
          padding: const EdgeInsets.only(bottom: 14),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.error, width: 2.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  PhosphorIconsBold.signOut,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'إغلاق الوردية',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 600,
          child: closingState.needsShiftSelection
              // Spec 135 NOTE 2 (req 4) — system admin reconciling, more than
              // one cashier shift open on the terminal: pick which to close.
              ? _buildShiftPicker(closingState)
              : closingState.isLoading
              ? const Center(child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator()))
              : (closingState.error == 'no_open_shift')
                  // Spec 029 corrective patch — explicit empty-state UI
                  // when the cashier has no open shift. The previous
                  // behaviour rendered phantom aggregates from
                  // already-closed shifts. Now we tell the operator
                  // exactly why and route them to the open-shift flow.
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsBold.warningCircle,
                              size: 48,
                              color: AppColors.warning,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'لا توجد وردية مفتوحة لإغلاقها',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'افتح وردية جديدة من شاشة نقطة البيع قبل '
                              'محاولة إغلاقها. القيم التي تظهر هنا '
                              'تُحسب فقط على معاملات الوردية الحالية '
                              'لتمنع اختلاط أرقام ورديات سابقة.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : (closingState.error != null)
                      ? Center(child: Text('خطأ في تحميل البيانات: ${closingState.error}', style: const TextStyle(color: AppColors.error)))
                      : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // === Per-channel reconciliation table ===
                          // Shows the accountant every cash flow that
                          // touched the shift, organised into one column
                          // per payment channel (cash / bank / click /
                          // credit). Visible only after "reveal" so the
                          // cashier can't peek at the system numbers
                          // before counting their drawer.
                          if (closingState.isRevealed)
                            _buildReconciliationTable(
                              closingState,
                              canViewDetails,
                              authState.user?.displayName ?? 'غير معروف',
                            ),

                          const SizedBox(height: 16),
                          if (isAdmin) ...[
                            _buildReconciliationSection(canViewDetails, closingState),
                            const SizedBox(height: 16),
                            _buildAdminMessage(),
                          ] else ...[
                            _buildNonAdminClosingSection(closingState),
                          ],
                        ],
                      ),
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (!closingState.isProcessing) Navigator.pop(context);
            },
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: closingState.isLoading || closingState.needsShiftSelection || (!isAdmin && _selectedMethod == null) ? null : () => _handleClosingAction(isAdmin, closingState),
            icon: closingState.isProcessing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(PhosphorIconsBold.signOut),
            label: const Text('تأكيد إغلاق الوردية'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // RECONCILIATION TABLE (per-channel)
  // ═══════════════════════════════════════════════════════════════════

  String _fmt(double v) =>
      '${v.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}';

  /// Cell helper for the reconciliation table. Renders a right-aligned
  /// number with an optional colour tint and a leading sign. Shows `—`
  /// for channels that don't apply (e.g. opening balance on bank/click).
  Widget _cell(double? value, {Color? color, bool emphasis = false, String prefix = ''}) {
    if (value == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text('—', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        '$prefix${_fmt(value)}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: emphasis ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _labelCell(String text, {bool emphasis = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: emphasis ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  TableRow _headerRow() {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: AppColors.textMuted,
    );
    Widget h(String t, {Color? bg}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          color: bg,
          child: Text(t, textAlign: TextAlign.center, style: headerStyle),
        );
    return TableRow(
      // PicPos chrome: خلفية محايدة من AppColors بدل Colors.grey الخام.
      decoration: const BoxDecoration(color: AppColors.surface),
      children: [
        h('البند'),
        h('نقد', bg: AppColors.primary.withValues(alpha: 0.08)),
        h('بنك', bg: AppColors.info.withValues(alpha: 0.08)),
        h('كليك', bg: AppColors.warning.withValues(alpha: 0.08)),
        h('آجل', bg: AppColors.textMuted.withValues(alpha: 0.08)),
        h('الإجمالى'),
      ],
    );
  }

  TableRow _dataRow(
    String label, {
    double? cash,
    double? bank,
    double? click,
    double? credit,
    double? total,
    Color? color,
    bool emphasis = false,
    bool canViewDetails = true,
    String prefix = '',
    Color? rowBackground,
  }) {
    final hideValue = !canViewDetails;
    Widget v(double? val) => hideValue
        ? const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('---',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          )
        : _cell(val, color: color, emphasis: emphasis, prefix: prefix);
    return TableRow(
      decoration: rowBackground != null
          ? BoxDecoration(color: rowBackground)
          : null,
      children: [
        _labelCell(label, emphasis: emphasis),
        v(cash),
        v(bank),
        v(click),
        v(credit),
        v(total),
      ],
    );
  }

  Widget _buildReconciliationTable(
    PosClosingState s,
    bool canViewDetails,
    String cashierName,
  ) {
    final a = s.aggregates;
    // Totals for the right-most summary column (omit credit where it
    // doesn't make sense: opening balance, expenses, payment vouchers).
    double total(double c, double b, double k, [double? cr]) =>
        c + b + k + (cr ?? 0);

    final expensesStart = a.shiftStartTime;
    final shiftTimeText = expensesStart == null
        ? 'بدون وقت بدء مسجل'
        : 'بدأت الساعة ${_hhmm(expensesStart)} — الآن ${_hhmm(DateTime.now())}';

    return Card(
      // PicPos chrome: بطاقة مسطحة بحدود بدل ظل Material الافتراضي —
      // نفس أسلوب PicPosContentCard المستخدم في بقية شاشات PicPos.
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: cashier + shift time ──────────────────────
            Row(
              children: [
                const Icon(PhosphorIconsBold.userCircle,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ملخص وردية $cashierName',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(shiftTimeText,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
            const Divider(height: 20),

            // ── Reconciliation table ──────────────────────────────
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.4),
                4: FlexColumnWidth(1.4),
                5: FlexColumnWidth(1.5),
              },
              defaultVerticalAlignment:
                  TableCellVerticalAlignment.middle,
              border: TableBorder(
                horizontalInside: BorderSide(
                    color: Colors.grey.shade200, width: 0.5),
              ),
              children: [
                _headerRow(),

                // Opening balance — cash only (bank/click start at 0).
                _dataRow('رصيد افتتاحى',
                    cash: a.openingBalance,
                    bank: 0,
                    click: 0,
                    credit: null,
                    total: a.openingBalance,
                    color: AppColors.info,
                    canViewDetails: canViewDetails),

                // Sales per channel — always a positive inflow.
                _dataRow(
                    'مبيعات (${a.salesCount})',
                    cash: a.salesCash,
                    bank: a.salesBank,
                    click: a.salesClick,
                    credit: a.salesCredit,
                    total: total(a.salesCash, a.salesBank, a.salesClick,
                        a.salesCredit),
                    color: AppColors.success,
                    canViewDetails: canViewDetails),

                // Receipt vouchers — customers paying off old invoices.
                _dataRow(
                    'سندات قبض (${a.receiptCount})',
                    cash: a.receiptCash,
                    bank: a.receiptBank,
                    click: a.receiptClick,
                    credit: null,
                    total: a.receiptCash + a.receiptBank + a.receiptClick,
                    color: AppColors.success,
                    canViewDetails: canViewDetails),

                // Subtotal — total inflow (income) per channel.
                _dataRow('إجمالى الدخل',
                    cash: a.openingBalance + a.totalIncomeCash,
                    bank: a.totalIncomeBank,
                    click: a.totalIncomeClick,
                    credit: a.salesCredit,
                    total: a.openingBalance +
                        a.totalIncomeCash +
                        a.totalIncomeBank +
                        a.totalIncomeClick +
                        a.salesCredit,
                    emphasis: true,
                    canViewDetails: canViewDetails,
                    rowBackground:
                        AppColors.primary.withValues(alpha: 0.04)),

                // Returns per channel — negative outflow.
                _dataRow(
                    'مرتجعات مبيعات (${a.returnsCount})',
                    cash: a.returnsCash,
                    bank: a.returnsBank,
                    click: a.returnsClick,
                    credit: a.returnsCredit,
                    total: a.returnsCash +
                        a.returnsBank +
                        a.returnsClick +
                        a.returnsCredit,
                    color: AppColors.error,
                    prefix: '-',
                    canViewDetails: canViewDetails),

                // Expenses — usually cash, but bank expenses supported.
                _dataRow(
                    'مصروفات (${a.expensesCount})',
                    cash: a.expensesCash,
                    bank: a.expensesBank,
                    click: a.expensesClick,
                    credit: null,
                    total: a.expensesCash +
                        a.expensesBank +
                        a.expensesClick,
                    color: AppColors.error,
                    prefix: '-',
                    canViewDetails: canViewDetails),

                // Payment vouchers — supplier settlements, etc.
                _dataRow(
                    'سندات صرف (${a.paymentCount})',
                    cash: a.paymentCash,
                    bank: a.paymentBank,
                    click: a.paymentClick,
                    credit: null,
                    total: a.paymentCash +
                        a.paymentBank +
                        a.paymentClick,
                    color: AppColors.error,
                    prefix: '-',
                    canViewDetails: canViewDetails),

                // Subtotal — total outflow per channel.
                _dataRow('إجمالى الخصم',
                    cash: a.totalOutflowCash,
                    bank: a.totalOutflowBank,
                    click: a.totalOutflowClick,
                    credit: a.returnsCredit,
                    total: a.totalOutflowCash +
                        a.totalOutflowBank +
                        a.totalOutflowClick +
                        a.returnsCredit,
                    color: AppColors.error,
                    prefix: '-',
                    emphasis: true,
                    canViewDetails: canViewDetails,
                    rowBackground: AppColors.error.withValues(alpha: 0.04)),

                // The row the accountant cares about most — system
                // expected balance per channel after all inflows and
                // outflows are applied.
                _dataRow('المتوقع (نظام)',
                    cash: a.systemCash,
                    bank: a.systemBank,
                    click: a.systemClick,
                    credit: a.systemCreditNet,
                    total: a.systemCash +
                        a.systemBank +
                        a.systemClick +
                        a.systemCreditNet,
                    emphasis: true,
                    color: AppColors.primary,
                    canViewDetails: canViewDetails,
                    rowBackground:
                        AppColors.primary.withValues(alpha: 0.08)),
              ],
            ),

            // ── Expenses detail (collapsible) ─────────────────────
            if (canViewDetails && a.expensesList.isNotEmpty) ...[
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 6),
                  childrenPadding:
                      const EdgeInsets.only(right: 12, bottom: 8),
                  title: Text(
                    'تفصيل المصروفات (${a.expensesList.length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  children: a.expensesList.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsBold.caretLeft,
                              size: 10, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(e.description,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(3),
                              border:
                                  Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              e.safeType == 'bank'
                                  ? 'بنك'
                                  : (e.safeType == 'click'
                                      ? 'كليك'
                                      : 'نقد'),
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.textMuted),
                            ),
                          ),
                          Text(
                            _fmt(e.amount),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.error,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            // ── Stats strip ───────────────────────────────────────
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                _statChip(
                    'إجمالى فواتير',
                    '${a.salesCount + a.returnsCount}',
                    PhosphorIconsBold.receipt),
                if (a.tableSalesCount > 0)
                  _statChip('طاولات', '${a.tableSalesCount}',
                      PhosphorIconsBold.table),
                if (a.tableSalesCount > 0)
                  _statChip('كاونتر', '${a.counterSalesCount}',
                      PhosphorIconsBold.storefront),
                _statChip('مرتجعات', '${a.returnsCount}',
                    PhosphorIconsBold.arrowUDownLeft),
                _statChip('سندات قبض', '${a.receiptCount}',
                    PhosphorIconsBold.arrowDown),
                _statChip('سندات صرف', '${a.paymentCount}',
                    PhosphorIconsBold.arrowUp),
                _statChip('مصروفات', '${a.expensesCount}',
                    PhosphorIconsBold.wallet),
              ],
            ),

            // ── Credit advisory ───────────────────────────────────
            if (a.salesCredit > 0 || a.returnsCredit > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(PhosphorIconsBold.info,
                        size: 14, color: AppColors.info),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'عمود "آجل" عرض فقط — لا يُطلب جرد فعلى له '
                        '(تحرك على ذمم العملاء بدون حركة نقدية).',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _hhmm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _statChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textMuted),
          const SizedBox(width: 3),
          Text('$label:',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textMuted)),
          const SizedBox(width: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildReconciliationSection(bool canViewDetails, PosClosingState state) {
    if (!canViewDetails) {
      return Card(
        // PicPos chrome: بطاقة مسطحة بحدود بدل اللون الرمادي الخام.
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('جرد النقدية الفعلي', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _actualCashController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'أدخل المبلغ النقدي الفعلي (كاش)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (v) => ref.read(posClosingControllerProvider.notifier).updateActualCash(double.tryParse(v) ?? 0),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      // PicPos chrome: بطاقة مسطحة بحدود بدل اللون الرمادي الخام.
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.scales, color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text('المطابقة - أدخل المبالغ الفعلية', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            _buildReconciliationRow('النقدى الفعلى', _actualCashController, state.cashVariance, PhosphorIconsBold.money, AppColors.primary, state.isRevealed),
            const SizedBox(height: 12),
            _buildReconciliationRow('البنك الفعلى', _actualCardController, state.bankVariance, PhosphorIconsBold.creditCard, AppColors.info, state.isRevealed),
            const SizedBox(height: 12),
            _buildReconciliationRow('كليك الفعلى', _actualClickController, state.clickVariance, PhosphorIconsBold.deviceMobile, AppColors.warning, state.isRevealed),
            const SizedBox(height: 16),
            if (!state.isRevealed)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => ref.read(posClosingControllerProvider.notifier).revealResults(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text('إظهار النتائج والمطابقة'),
                ),
              ),
            if (state.isRevealed) _buildTotalVarianceStatus(state.totalVariance),
          ],
        ),
      ),
    );
  }

  Widget _buildReconciliationRow(String label, TextEditingController controller, double variance, IconData icon, Color color, bool isRevealed) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
        Expanded(
          flex: 3,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '0.00',
              suffixText: AppConstants.currencySymbolEn,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) {
              final val = double.tryParse(v) ?? 0;
              final notifier =
                  ref.read(posClosingControllerProvider.notifier);
              if (controller == _actualCashController) {
                notifier.updateActualCash(val);
              } else if (controller == _actualCardController) {
                notifier.updateActualBank(val);
              } else if (controller == _actualClickController) {
                notifier.updateActualClick(val);
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        if (isRevealed)
          SizedBox(
            width: 80,
            child: Column(
              children: [
                const Text('الفرق', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                Text(
                  '${variance > 0 ? '+' : ''}${variance.toStringAsFixed(AppConstants.decimalPlaces)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: variance.abs() < 0.001 ? AppColors.success : (variance < 0 ? AppColors.error : AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTotalVarianceStatus(double totalVar) {
    final color = totalVar.abs() < 0.001 ? AppColors.success : (totalVar < 0 ? AppColors.error : AppColors.warning);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            totalVar.abs() < 0.001 ? PhosphorIconsBold.checkCircle : (totalVar < 0 ? PhosphorIconsBold.warningCircle : PhosphorIconsBold.info),
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            totalVar.abs() < 0.001
                ? 'المطابقة تمام ✓'
                : (totalVar < 0 ? 'نقص: ${totalVar.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}' : 'زيادة: +${totalVar.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildNonAdminClosingSection(PosClosingState closingState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('اختر طريقة إغلاق الوردية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('إغلاق سريع'),
              selected: _selectedMethod == 'quick',
              selectedColor: AppColors.warning.withValues(alpha: 0.2),
              avatar: _selectedMethod == 'quick' ? const Icon(PhosphorIconsBold.lightning, size: 16) : null,
              onSelected: (_) {
                setState(() => _selectedMethod = 'quick');
                ref.read(posClosingControllerProvider.notifier).setClosingMethod('quick');
              },
            ),
            ChoiceChip(
              label: const Text('بطاقة MSR'),
              selected: _selectedMethod == 'msr_card',
              selectedColor: AppColors.info.withValues(alpha: 0.2),
              avatar: _selectedMethod == 'msr_card' ? const Icon(PhosphorIconsBold.creditCard, size: 16) : null,
              onSelected: (_) {
                setState(() => _selectedMethod = 'msr_card');
                ref.read(posClosingControllerProvider.notifier).setClosingMethod('msr_card');
              },
            ),
            ChoiceChip(
              label: const Text('كلمة مرور المدير'),
              selected: _selectedMethod == 'admin_password',
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              avatar: _selectedMethod == 'admin_password' ? const Icon(PhosphorIconsBold.lock, size: 16) : null,
              onSelected: (_) {
                setState(() => _selectedMethod = 'admin_password');
                ref.read(posClosingControllerProvider.notifier).setClosingMethod('admin_password');
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Show input based on selected method
        if (_selectedMethod == 'msr_card') ...[
          Card(
            // PicPos chrome: بطاقة مسطحة بحدود بلون القناة بدل الظل الافتراضي.
            elevation: 0,
            color: AppColors.info.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(PhosphorIconsBold.creditCard, color: AppColors.info, size: 20),
                      SizedBox(width: 8),
                      Text('مرر بطاقة MSR', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.info)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _msrCardController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'كود البطاقة',
                      prefixIcon: const Icon(PhosphorIconsBold.creditCard),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      hintText: 'مرر البطاقة أو أدخل الكود',
                    ),
                    onSubmitted: (_) => _handleClosingAction(false, closingState),
                  ),
                ],
              ),
            ),
          ),
        ],

        if (_selectedMethod == 'admin_password') ...[
          Card(
            // PicPos chrome: بطاقة مسطحة بحدود بلون القناة بدل الظل الافتراضي.
            elevation: 0,
            color: AppColors.primary.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(PhosphorIconsBold.lock, color: AppColors.primary, size: 20),
                      SizedBox(width: 8),
                      Text('أدخل كلمة سر المدير', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'كلمة سر المدير',
                      prefixIcon: const Icon(PhosphorIconsBold.lock),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _handleClosingAction(false, closingState),
                  ),
                ],
              ),
            ),
          ),
        ],

        if (_selectedMethod == 'quick') ...[
          Card(
            // PicPos chrome: بطاقة مسطحة بحدود بلون القناة بدل الظل الافتراضي.
            elevation: 0,
            color: AppColors.warning.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.lightning, color: AppColors.warning, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم إغلاق الوردية بدون جرد. يمكن للمدير مراجعة الفروقات لاحقاً.',
                      style: TextStyle(color: AppColors.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAdminMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success),
      ),
      child: const Row(
        children: [
          Icon(PhosphorIconsBold.shieldCheck, color: AppColors.success),
          SizedBox(width: 8),
          Expanded(child: Text('أنت مدير النظام - لا تحتاج كلمة مرور', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Future<void> _handleClosingAction(bool isAdmin, PosClosingState state) async {
    if (state.isProcessing) return;

    // Validation for non-admin users based on selected method
    if (!isAdmin) {
      if (_selectedMethod == null) {
        if (mounted) showPosToast(context, ref, 'اختر طريقة إغلاق الوردية', type: PosNotificationType.warning);
        return;
      }
      if (_selectedMethod == 'admin_password' && _passwordController.text.isEmpty) {
        if (mounted) showPosToast(context, ref, 'أدخل كلمة سر المدير', type: PosNotificationType.warning);
        return;
      }
      if (_selectedMethod == 'msr_card' && _msrCardController.text.isEmpty) {
        if (mounted) showPosToast(context, ref, 'مرر بطاقة MSR أو أدخل الكود', type: PosNotificationType.warning);
        return;
      }
    }

    // For admin (normal) flow, show the bank amount warning
    if (isAdmin || _selectedMethod == 'normal') {
      if (state.actualCardAmount == 0 && state.cardIncome > 0 && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Row(children: [Icon(PhosphorIconsBold.warning, color: AppColors.warning), SizedBox(width: 8), Text('تنبيه — مبلغ البنك')]),
              content: const Text('يوجد تحصيل بطاقة/كليك ولم تُدخل مبلغ البنك الفعلي.\nهل تريد المتابعة بقيمة صفر؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا، أريد إدخال المبلغ')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
                  child: const Text('نعم، متابعة بدون بنك'),
                ),
              ],
            ),
          ),
        );
        if (proceed != true) return;
      }
    }

    try {
      await ref.read(posClosingControllerProvider.notifier).handleClosing(
        password: _passwordController.text,
        cardCode: _msrCardController.text,
      );

      if (mounted) {
        // GAP-24: warn if variance JE failed (non-blocking — shift is already closed)
        final finalState = ref.read(posClosingControllerProvider);
        if (finalState.varianceJeWarning != null && finalState.varianceJeWarning!.abs() > 0.01) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Row(children: [
                  Icon(PhosphorIconsBold.warning, color: AppColors.warning),
                  SizedBox(width: 8),
                  Text('تحذير محاسبي'),
                ]),
                content: Text(
                  'تم إغلاق الوردية بنجاح، لكن لم يُسجَّل قيد فرق الخزينة '
                  '(${finalState.varianceJeWarning!.toStringAsFixed(2)}).\n'
                  'تأكد من إعداد حسابات فائض/عجز الخزينة في الربط المحاسبي.',
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('حسناً'),
                  ),
                ],
              ),
            ),
          );
        }
        Navigator.pop(context); // Close dialog
        ref.read(authProvider.notifier).logout();
        showPosToast(context, ref, 'تم إغلاق الوردية وطباعة التقرير بنجاح', type: PosNotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        showPosToast(context, ref, '$e', type: PosNotificationType.error);
      }
    }
  }
}
