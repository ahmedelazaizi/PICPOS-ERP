import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../pos/providers/pos_notification_provider.dart';
import '../../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../pos/providers/pos_closing_controller.dart';
import '../../../data/providers/quick_sale_policy_providers.dart';
import '../../../domain/models/quick_sale_policy.dart';

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
  /// يسجّل الخروج تلقائياً بعد إغلاق ناجح. الافتراضي `true` — ده سلوك الديالوج
  /// من الأصل وكل مستدعياته القديمة معتمدة عليه.
  ///
  /// ── ليه بقى قابل للإطفاء ─────────────────────────────────────────────────
  /// الديالوج كان بيفترض إن «إغلاق الوردية» = «انتهت الجلسة»، فبينادي
  /// `logout()` بلا شرط. الافتراض ده صح لمسار تسجيل الخروج، وغلط لمسار **تحويل
  /// المستخدم**: هناك إغلاق الوردية خطوة وسط في تسليم التِل، والخروج لشاشة
  /// الدخول هو بالظبط اللي التحويل موجود عشان يمنعه.
  final bool logoutAfterClose;

  const PicposCashierClosingDialog({super.key, this.logoutAfterClose = true});

  @override
  ConsumerState<PicposCashierClosingDialog> createState() =>
      _PicposCashierClosingDialogState();

  /// Static helper to show the dialog
  static Future<void> show(
    BuildContext context, {
    bool logoutAfterClose = true,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          PicposCashierClosingDialog(logoutAfterClose: logoutAfterClose),
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
           Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr('توجد أكثر من وردية مفتوحة — اختر الوردية المراد مطابقتها وإغلاقها'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          ...closingState.selectableShifts.map(
            (s) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(PhosphorIconsBold.cashRegister,
                    color: AppColors.primary),
                title: Text(tr('وردية رقم {p0} — كاشير #{p1}', {'p0': s.id, 'p1': s.userId})),
                subtitle: Text(
                    tr('بدأت: {p0} — رصيد افتتاحي: {p1}', {'p0': fmt(s.startTime), 'p1': s.openingBalance.toStringAsFixed(AppConstants.decimalPlaces)})),
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
    // تسخينُ سياسة البيع السريع: `_blindClose` تُقرأ متزامناً من البناء
    // فلا تحتمل `await`. وبلا مراقبٍ تبقى `null` فيظهر المتوقَّعُ للكاشير
    // قبل العدّ ولو كان «الإغلاق الأعمى» مضاءً — وهو يجعل الفرقَ صفراً
    // على الورق دائماً.
    ref.watch(quickSalePolicyProvider);

    final authState = ref.watch(authProvider);
    final perms = ref.watch(currentUserPermissionsProvider).value ?? [];
    // مدير النظام بس هو اللي بيتجاوز صلاحية عرض تفاصيل الإقفال. قبل كده كانت
    // `isAdmin || isManager`، وهي بتتحدد بمطابقة اسم الدور — فـ«مدير فرع»
    // كان بيعدّي بلا صلاحية.
    final isAdmin = authState.hasSystemAdminBypass;
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
               Text(
                tr('إغلاق الوردية'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
                  ?  Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              PhosphorIconsBold.warningCircle,
                              size: 48,
                              color: AppColors.warning,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              tr('لا توجد وردية مفتوحة لإغلاقها'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                             Text(
                              tr('افتح وردية جديدة من شاشة البيع السريع قبل محاولة إغلاقها. القيم التي تظهر هنا تُحسب فقط على معاملات الوردية الحالية لتمنع اختلاط أرقام ورديات سابقة.'),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : (closingState.error != null)
                      ? Center(child: Text(tr('خطأ في تحميل البيانات: {p0}', {'p0': closingState.error}), style: const TextStyle(color: AppColors.error)))
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
                              authState.user?.displayName ?? tr('غير معروف'),
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
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton.icon(
            onPressed: closingState.isLoading || closingState.needsShiftSelection || (!isAdmin && _selectedMethod == null) ? null : () => _handleClosingAction(isAdmin, closingState),
            icon: closingState.isProcessing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(PhosphorIconsBold.signOut),
            label:  Text(tr('تأكيد إغلاق الوردية')),
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

  // ignore: unused_element
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
        h(tr('البند')),
        h(tr('نقد'), bg: AppColors.primary.withValues(alpha: 0.08)),
        h(tr('بنك'), bg: AppColors.info.withValues(alpha: 0.08)),
        h(tr('كليك'), bg: AppColors.warning.withValues(alpha: 0.08)),
        h(tr('آجل'), bg: AppColors.textMuted.withValues(alpha: 0.08)),
        h(tr('الإجمالى')),
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
        ? tr('بدون وقت بدء مسجل')
        : tr('بدأت الساعة {p0} — الآن {p1}', {'p0': _hhmm(expensesStart), 'p1': _hhmm(DateTime.now())});

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
                    tr('ملخص وردية {cashierName}', {'cashierName': cashierName}),
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
                _dataRow(tr('رصيد افتتاحى'),
                    cash: a.openingBalance,
                    bank: 0,
                    click: 0,
                    credit: null,
                    total: a.openingBalance,
                    color: AppColors.info,
                    canViewDetails: canViewDetails),

                // Sales per channel — always a positive inflow.
                _dataRow(
                    tr('مبيعات ({p0})', {'p0': a.salesCount}),
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
                    tr('سندات قبض ({p0})', {'p0': a.receiptCount}),
                    cash: a.receiptCash,
                    bank: a.receiptBank,
                    click: a.receiptClick,
                    credit: null,
                    total: a.receiptCash + a.receiptBank + a.receiptClick,
                    color: AppColors.success,
                    canViewDetails: canViewDetails),

                // Subtotal — total inflow (income) per channel.
                _dataRow(tr('إجمالى الدخل'),
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
                    tr('مرتجعات مبيعات ({p0})', {'p0': a.returnsCount}),
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
                    tr('مصروفات ({p0})', {'p0': a.expensesCount}),
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
                    tr('سندات صرف ({p0})', {'p0': a.paymentCount}),
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
                _dataRow(tr('إجمالى الخصم'),
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
                _dataRow(tr('المتوقع (نظام)'),
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
                      const EdgeInsetsDirectional.only(start: 12, bottom: 8),
                  title: Text(
                    tr('تفصيل المصروفات ({p0})', {'p0': a.expensesList.length}),
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
                            margin: const EdgeInsetsDirectional.only(end: 6),
                            decoration: BoxDecoration(
                              color: context.picposField,
                              borderRadius: BorderRadius.circular(3),
                              border:
                                  Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              e.safeType == 'bank'
                                  ? tr('بنك')
                                  : (e.safeType == 'click'
                                      ? tr('كليك')
                                      : tr('نقد')),
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
                    tr('إجمالى فواتير'),
                    '${a.salesCount + a.returnsCount}',
                    PhosphorIconsBold.receipt),
                if (a.tableSalesCount > 0)
                  _statChip(tr('طاولات'), '${a.tableSalesCount}',
                      PhosphorIconsBold.table),
                if (a.tableSalesCount > 0)
                  _statChip(tr('كاونتر'), '${a.counterSalesCount}',
                      PhosphorIconsBold.storefront),
                _statChip(tr('مرتجعات'), '${a.returnsCount}',
                    PhosphorIconsBold.arrowUDownLeft),
                _statChip(tr('سندات قبض'), '${a.receiptCount}',
                    PhosphorIconsBold.arrowDown),
                _statChip(tr('سندات صرف'), '${a.paymentCount}',
                    PhosphorIconsBold.arrowUp),
                _statChip(tr('مصروفات'), '${a.expensesCount}',
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
                child:  Row(
                  children: [
                    const Icon(PhosphorIconsBold.info,
                        size: 14, color: AppColors.info),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('عمود "آجل" عرض فقط — لا يُطلب جرد فعلى له (تحرك على ذمم العملاء بدون حركة نقدية).'),
                        style: const TextStyle(
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
        color: context.picposField,
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

  /// هل الإغلاقُ أعمى؟ — §٤ `blind`.
  ///
  /// ⚠️ **الافتراضُ `true` وهو سلوكُ الحوار المشحون**: الأرقامُ مخفيّةٌ حتّى
  /// «إظهار النتائج». وإطفاءُ المِزلاج يكشفها قبل العدّ — وهو ما يجعل الفرقَ
  /// دائماً صفراً على الورق، فالكاشيرُ يكتب ما يراه لا ما عدّه.
  ///
  /// ⚠️ **ولا `revealResults()` في `initState`**: تلك كتابةٌ في مزوِّدٍ أثناء
  /// البناء. والشرطُ هنا يعطي نفسَ الأثر بلا طفرةِ حالة.
  bool get _blindClose {
    final policy = ref.read(quickSalePolicyProvider).asData?.value;
    return policy == null ||
        policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'blind'));
  }

  Widget _buildReconciliationSection(bool canViewDetails, PosClosingState state) {
    // الكشفُ إمّا بضغطةِ الكاشير، وإمّا لأنّ السياسةَ لا تُخفي أصلاً.
    final revealed = state.isRevealed || !_blindClose;
    if (!canViewDetails) {
      return Card(
        // PicPos chrome: بطاقة مسطحة بحدود بدل اللون الرمادي الخام.
        elevation: 0,
        color: context.picposField,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
               Text(tr('جرد النقدية الفعلي'), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _actualCashController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: tr('أدخل المبلغ النقدي الفعلي (كاش)'),
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
      color: context.picposField,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
             Row(
              children: [
                const Icon(PhosphorIconsBold.scales, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(tr('المطابقة - أدخل المبالغ الفعلية'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            _buildReconciliationRow(tr('النقدى الفعلى'), _actualCashController, state.cashVariance, PhosphorIconsBold.money, AppColors.primary, revealed),
            const SizedBox(height: 12),
            _buildReconciliationRow(tr('البنك الفعلى'), _actualCardController, state.bankVariance, PhosphorIconsBold.creditCard, AppColors.info, revealed),
            const SizedBox(height: 12),
            _buildReconciliationRow(tr('كليك الفعلى'), _actualClickController, state.clickVariance, PhosphorIconsBold.deviceMobile, AppColors.warning, revealed),
            const SizedBox(height: 16),
            if (!revealed)
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
                  child:  Text(tr('إظهار النتائج والمطابقة')),
                ),
              ),
            if (revealed) _buildTotalVarianceStatus(state.totalVariance),
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
                 Text(tr('الفرق'), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
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
                ? tr('المطابقة تمام ✓')
                : (totalVar < 0 ? tr('نقص: {p0} {p1}', {'p0': totalVar.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}) : tr('زيادة: +{p0} {p1}', {'p0': totalVar.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn})),
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
         Text(tr('اختر طريقة إغلاق الوردية'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        // ── طريقتان لا ثلاث (طلبُ المالك 2026-08-14) ─────────────────────
        //
        // «الإغلاقُ بالبطاقة أو الباسورد — دمجٌ بكبسةٍ واحدة»: شريحةٌ واحدةٌ
        // بمدخلٍ واحدٍ يجرّبهما معاً عبر `authenticateByPasswordOrCard`، ثم
        // يفحص `pos_shift_close`. والفحصُ بالصلاحية يسدّ ثغرةً مقيسة: مسارُ
        // `msr_card` القديم كان يقبل بطاقةَ **أيّ** مستخدمٍ مسجَّل بلا فحصِ
        // دورٍ إطلاقاً، فيُغلق أيُّ كاشيرٍ ورديتَه بفرقٍ صفر.
        //
        // و«إغلاق سريع» خلف إعداد: هو الطريقُ الوحيدُ بلا أيّ مصادقة.
        Wrap(
          spacing: 8,
          children: [
            if (ref.watch(posQuickCloseEnabledProvider).value ?? true)
              ChoiceChip(
                label:  Text(tr('إغلاق سريع')),
                selected: _selectedMethod == 'quick',
                selectedColor: AppColors.warning.withValues(alpha: 0.2),
                avatar: _selectedMethod == 'quick' ? const Icon(PhosphorIconsBold.lightning, size: 16) : null,
                onSelected: (_) {
                  setState(() => _selectedMethod = 'quick');
                  ref.read(posClosingControllerProvider.notifier).setClosingMethod('quick');
                },
              ),
            ChoiceChip(
              label:  Text(tr('بطاقة أو كلمة مرور')),
              selected: _selectedMethod == 'card_or_password',
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              avatar: _selectedMethod == 'card_or_password'
                  ? const Icon(PhosphorIconsBold.lockKey, size: 16)
                  : null,
              onSelected: (_) {
                setState(() => _selectedMethod = 'card_or_password');
                ref
                    .read(posClosingControllerProvider.notifier)
                    .setClosingMethod('card_or_password');
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── مدخلٌ واحدٌ للبطاقة وكلمة المرور ─────────────────────────────
        //
        // كان حقلَين في شريحتَين: تمريرُ بطاقةٍ في حقلٍ وكتابةُ باسوردٍ في
        // آخر. والمالكُ طلب «كبسةً واحدة»، والمحرّكُ يقبلهما معاً سلفاً في
        // `authenticateByPasswordOrCard` — فالمطلوبُ كان وصلاً لا بناءً.
        //
        // ⚠️ الحقلُ **غيرُ مخفيّ الحروف**: قارئُ MSR يكتب بسرعةٍ وينهي
        // بـEnter، وإخفاءُ الحروف يمنع الكاشيرَ من رؤية أن القارئ أدخل
        // نصّاً مشوَّهاً. ومن يكتب كلمةَ مرورٍ يدوياً هو مسؤولٌ واقفٌ عند
        // الجهاز لحظةً واحدة، لا جلسةً مفتوحة.
        if (_selectedMethod == 'card_or_password') ...[
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
                   Row(
                    children: [
                      const Icon(PhosphorIconsBold.lockKey,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('مرّر البطاقة أو أدخل كلمة المرور'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _msrCardController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: tr('البطاقة أو كلمة المرور'),
                      prefixIcon: const Icon(PhosphorIconsBold.lockKey),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      hintText: tr('مرّر البطاقة، أو اكتب كلمة المرور واضغط Enter'),
                    ),
                    onSubmitted: (_) =>
                        _handleClosingAction(false, closingState),
                  ),
                  const SizedBox(height: 8),
                   Text(
                    tr('يُقبل من يملك صلاحية إغلاق الوردية.'),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
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
            child:  Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.lightning, color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('سيتم إغلاق الوردية بدون جرد. يمكن للمدير مراجعة الفروقات لاحقاً.'),
                      style: const TextStyle(color: AppColors.warning, fontSize: 12),
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
      child:  Row(
        children: [
          const Icon(PhosphorIconsBold.shieldCheck, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('أنت مدير النظام - لا تحتاج كلمة مرور'), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  /// يطلب سببَ الفرق — `null` تعني إلغاءً أو سبباً فارغاً.
  ///
  /// حقلٌ حرٌّ لا قائمةُ أسبابٍ جاهزة: قائمةٌ قصيرةٌ تدفع الكاشيرَ لاختيار
  /// أقربِ بندٍ لا لوصفِ ما حدث، فتُنتج بياناتٍ مرتّبةً بلا معنى.
  Future<String?> _promptVarianceReason(
    double difference,
    double limit,
  ) async {
    final controller = TextEditingController();
    final shortfall = difference < 0;
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(children: [
            const Icon(PhosphorIconsBold.warning, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(shortfall ? tr('عجزٌ في الدرج') : tr('زيادةٌ في الدرج')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('الفرق {p0} يتجاوز الحدَّ المسموح {p1}.\nاكتب سببَ الفرق ليُحفَظ مع الوردية.', {'p0': difference.abs().toStringAsFixed(AppConstants.decimalPlaces), 'p1': limit.toStringAsFixed(0)}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration:  InputDecoration(
                  labelText: tr('سبب الفرق'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isEmpty) return;
                Navigator.pop(ctx, v);
              },
              child:  Text(tr('تأكيد')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return (reason == null || reason.trim().isEmpty) ? null : reason;
  }

  Future<void> _handleClosingAction(bool isAdmin, PosClosingState state) async {
    if (state.isProcessing) return;

    // Validation for non-admin users based on selected method
    if (!isAdmin) {
      if (_selectedMethod == null) {
        if (mounted) showPosToast(context, ref, tr('اختر طريقة إغلاق الوردية'), type: PosNotificationType.warning);
        return;
      }
      if (_selectedMethod == 'admin_password' && _passwordController.text.isEmpty) {
        if (mounted) showPosToast(context, ref, tr('أدخل كلمة سر المدير'), type: PosNotificationType.warning);
        return;
      }
      // الشريحتان القديمتان اندمجتا في `card_or_password` — والحقلُ الواحدُ
      // هو `_msrCardController`، فالتحقّقُ عليه. (‏`msr_card` باقٍ في الشرط
      // لأن حوارَ UralCash ما زال يرسله وقيمتَه محفوظةٌ في صفوفٍ تاريخية.)
      if ((_selectedMethod == 'msr_card' ||
              _selectedMethod == 'card_or_password') &&
          _msrCardController.text.isEmpty) {
        if (mounted) {
          showPosToast(context, ref, tr('مرّر البطاقة أو أدخل كلمة المرور'),
              type: PosNotificationType.warning);
        }
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
              title:  Row(children: [const Icon(PhosphorIconsBold.warning, color: AppColors.warning), const SizedBox(width: 8), Text(tr('تنبيه — مبلغ البنك'))]),
              content:  Text(tr('يوجد تحصيل بطاقة/كليك ولم تُدخل مبلغ البنك الفعلي.\nهل تريد المتابعة بقيمة صفر؟')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child:  Text(tr('لا، أريد إدخال المبلغ'))),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
                  child:  Text(tr('نعم، متابعة بدون بنك')),
                ),
              ],
            ),
          ),
        );
        if (proceed != true) return;
      }
    }

    // §٤ `diffmax` — فرقٌ فوق الحدّ لا يمرّ بلا سببٍ مكتوب.
    //
    // ⚠️ **بالقيمة المطلقة**: العجزُ ٢٥ يحتاج سبباً كما تحتاجه الزيادةُ
    // ٢٥، وإهمالُ الإشارة يُعفي العجزَ — وهو الأخطرُ محاسبيّاً: المالُ
    // الناقصُ يمرّ بلا تفسير. والمنطقُ في `quickSaleShiftDiffNeedsReason`.
    String? varianceReason;
    // `await` لا قراءةً باردة: هذه دالّةٌ غيرُ متزامنةٍ أصلاً، والقراءةُ
    // الباردةُ ترجع `null` قبل أن يسخن المزوِّدُ فيمرّ الفرقُ بلا سبب.
    final diffPolicy = await ref.read(quickSalePolicyProvider.future);
    if (mounted) {
      final limit = quickSaleShiftDiffLimit(diffPolicy);
      // ⚠️ **أكبرُ القنوات لا مجموعُها.** المجموعُ يُقاصّ: عجزٌ نقديٌّ −٣٠٠
      // وفائضُ بنكٍ +٣٠٠ يعطيان صفراً فيمرّ الإغلاقُ بلا سبب — بينما
      // `closeShiftWithAudit` تُرحّل **النقديَّ وحدَه**، فتخرج ٣٠٠ من الدرج
      // ومن الدفاتر بلا تفسير. (‏بلاغُ التدقيق المحاسبيّ 2026-08-30)
      final governing = quickSaleGoverningShiftDiff(
        cash: state.cashVariance,
        bank: state.bankVariance,
        click: state.clickVariance,
      );
      if (quickSaleShiftDiffNeedsReason(
        difference: governing,
        limit: limit,
      )) {
        varianceReason = await _promptVarianceReason(
          governing,
          limit!,
        );
        // إلغاءٌ أو سببٌ فارغ ⇒ لا تُغلَق الوردية. والسكوتُ هنا كان
        // سيجعل الحدَّ زينةً: يُعرَض ثمّ يُتخطّى بضغطةِ «إلغاء».
        if (varianceReason == null) return;
        if (!mounted) return;
      }
    }

    // §٤ `xrep`.
    final printReport = diffPolicy.isOn(
      kQuickSaleRows.firstWhere((r) => r.id == 'xrep'),
    );
    try {
      await ref.read(posClosingControllerProvider.notifier).handleClosing(
        password: _passwordController.text,
        cardCode: _msrCardController.text,
        varianceReason: varianceReason,
        printReport: printReport,
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
                title:  Row(children: [
                  const Icon(PhosphorIconsBold.warning, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Text(tr('تحذير محاسبي')),
                ]),
                content: Text(
                  tr('تم إغلاق الوردية بنجاح، لكن لم يُسجَّل قيد فرق الخزينة ({p0}).\nتأكد من إعداد حسابات فائض/عجز الخزينة في الربط المحاسبي.', {'p0': finalState.varianceJeWarning!.toStringAsFixed(2)}),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child:  Text(tr('حسناً')),
                  ),
                ],
              ),
            ),
          );
        }
        if (!mounted) return;
        Navigator.pop(context); // Close dialog
        // مسار تحويل المستخدم بيمرّر `false`: الوردية اتقفلت واتصفّت، والجلسة
        // الجاية هتتحدّد من ديالوج التحويل — الخروج هنا كان بيقطع المسار ويودّي
        // الكاشير لشاشة الدخول.
        if (widget.logoutAfterClose) {
          ref.read(authProvider.notifier).logout();
        }
        // الرسالةُ تقول ما وقع: الورديّةُ أُغلقت دائماً، والتقريرُ طُبع إن
        // ردّ الحوارُ بالقبول — وإلغاؤه كان يُحسَب نجاحاً (2026-09-02).
        final reportPrinted = finalState.reportPrinted;
        showPosToast(
          context,
          ref,
          !printReport
              ? tr('تم إغلاق الوردية بنجاح')
              : reportPrinted == false
                  ? tr('تم إغلاق الوردية — وأُلغيت طباعة التقرير')
                  : tr('تم إغلاق الوردية وطباعة التقرير بنجاح'),
          type: reportPrinted == false
              ? PosNotificationType.warning
              : PosNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showPosToast(context, ref, '$e', type: PosNotificationType.error);
      }
    }
  }
}
