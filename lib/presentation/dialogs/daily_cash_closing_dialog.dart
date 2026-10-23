import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/providers/providers.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:picpos_erp/core/constants/app_constants.dart';

/// Daily Cash Closing Dialog
class DailyCashClosingDialog extends ConsumerStatefulWidget {
  const DailyCashClosingDialog({super.key});

  @override
  ConsumerState<DailyCashClosingDialog> createState() =>
      _DailyCashClosingDialogState();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const DailyCashClosingDialog(),
    );
  }
}

class _DailyCashClosingDialogState
    extends ConsumerState<DailyCashClosingDialog> {
  final _actualCashController = TextEditingController();
  final _actualBankController = TextEditingController();
  double _totalSales = 0;
  double _cashSales = 0;
  double _bankSales = 0;
  double _totalExpenses = 0;
  int _invoiceCount = 0;
  bool _isLoading = true;
  DateTime? _lastClosingTime; // وقت آخر إقفال
  String? _lastClosingUser; // اسم من أقفل آخر مرة

  @override
  void initState() {
    super.initState();
    _loadDayData();
  }

  @override
  void dispose() {
    _actualCashController.dispose();
    _actualBankController.dispose();
    super.dispose();
  }

  Future<void> _loadDayData() async {
    try {
      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      final salesRepo = ref.read(salesRepositoryProvider);
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      // جلب آخر إقفال (أحدث واحد)
      final lastClosing = await treasuryRepo.getLastClosingTransaction();

      // الحساب يبدأ من آخر إقفال أو بداية اليوم (أيهما أحدث)
      DateTime sinceTime;
      if (lastClosing != null && lastClosing.createdAt.isAfter(startOfDay)) {
        sinceTime = lastClosing.createdAt;
      } else {
        sinceTime = startOfDay;
      }

      // استخراج اسم المستخدم من وصف آخر إقفال
      String? lastUser;
      if (lastClosing != null) {
        final desc = lastClosing.description ?? '';
        // i18n-ignore: persisted and parsed
        final userMatch = RegExp(r'المستخدم: (.+?) \|').firstMatch(desc);
        if (userMatch != null) {
          lastUser = userMatch.group(1);
        }
      }

      // الفواتير من بعد آخر إقفال فقط
      final invoices = await salesRepo.getInvoicesSince(sinceTime);

      // المصروفات من بعد آخر إقفال فقط
      final allTransactions = await treasuryRepo.getTransactionsSince(sinceTime);
      final transactions = allTransactions.where((t) => t.category != 'daily_closing').toList();

      double sales = 0;
      double cashSales = 0;
      double bankSales = 0;
      double expenses = 0;

      for (final inv in invoices) {
        sales += inv.total;

        final method = inv.paymentMethod.toLowerCase();

        if (method == 'cash') {
          cashSales += inv.paid;
        } else if (method == 'card' ||
            method == 'transfer' ||
            method == 'click') {
          bankSales += inv.paid;
        } else if (method == 'credit') {
          // Credit/deferred — not counted in cash or bank
        } else if (method == 'mixed') {
          cashSales += inv.cashPaid;
          bankSales += inv.bankPaid;
        }
      }

      for (final trans in transactions) {
        if (trans.transactionType == 'payment' && trans.category == 'expense') {
          expenses += trans.amount;
        }
      }

      setState(() {
        _totalSales = sales;
        _cashSales = cashSales;
        _bankSales = bankSales;
        _invoiceCount = invoices.length;
        _totalExpenses = expenses;
        _lastClosingTime = lastClosing?.createdAt;
        _lastClosingUser = lastUser;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _performClosing() async {
    final actualCash = double.tryParse(_actualCashController.text) ?? 0;
    final actualBank = double.tryParse(_actualBankController.text) ?? 0;
    final cashDifference = actualCash - _cashSales;
    final bankDifference = actualBank - _bankSales;

    try {
      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      final now = DateTime.now();
      // voucherNumber يشمل التاريخ والوقت ليكون فريداً لكل إقفال
      final dateTimeStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

      // الحصول على بيانات المستخدم الحالي
      final authState = ref.read(authProvider);
      final currentUser = authState.user;
      final currentUserId = currentUser?.id ?? 1;
      final currentUserName =
          currentUser?.displayName ?? currentUser?.username ?? tr('مستخدم');

      // Get terminal-specific safe from POS settings, fallback to system default
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final posCashSafeIdStr = await settingsRepo.getSetting('pos_cash_safe_id');
      final posBankSafeIdStr = await settingsRepo.getSetting('pos_bank_safe_id');
      final posCashSafeId = int.tryParse(posCashSafeIdStr ?? '');
      final posBankSafeId = int.tryParse(posBankSafeIdStr ?? '');

      // Use terminal-specific safe if configured, otherwise fallback to default
      final cashSafe = posCashSafeId != null
          ? await treasuryRepo.getSafeById(posCashSafeId)
          : await treasuryRepo.getDefaultSafeByType('cash');
      final bankSafe = posBankSafeId != null
          ? await treasuryRepo.getSafeById(posBankSafeId)
          : await treasuryRepo.getDefaultSafeByType('bank');

      // Create closing transaction for cash.
      // transactionType = 'withdrawal': createSafeTransaction() deducts
      // _cashSales from the safe balance (→ 0). balanceAfter: 0 reflects
      // the correct post-transaction safe balance in the report.
      if (cashSafe != null) {
        await treasuryRepo.createSafeTransaction(
          voucherNumber: 'CLO-CASH-$dateTimeStr',
          safeId: cashSafe.id,
          transactionType: 'withdrawal',
          category: 'daily_closing',
          amount: _cashSales,
          balanceAfter: 0,
          referenceType: 'daily_closing',
          description: // i18n-ignore: persisted and parsed
              'المستخدم: $currentUserName | إقفال الكاش | المسجل: ${_cashSales.toStringAsFixed(AppConstants.decimalPlaces)} | الفعلي: ${actualCash.toStringAsFixed(AppConstants.decimalPlaces)} | الفرق: ${cashDifference >= 0 ? '+' : ''}${cashDifference.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          userId: currentUserId,
        );
      }

      // Create closing transaction for bank.
      if (bankSafe != null) {
        await treasuryRepo.createSafeTransaction(
          voucherNumber: 'CLO-BANK-$dateTimeStr',
          safeId: bankSafe.id,
          transactionType: 'withdrawal',
          category: 'daily_closing',
          amount: _bankSales,
          balanceAfter: 0,
          referenceType: 'daily_closing',
          description: // i18n-ignore: persisted and parsed
              'المستخدم: $currentUserName | إقفال البنك | المسجل: ${_bankSales.toStringAsFixed(AppConstants.decimalPlaces)} | الفعلي: ${actualBank.toStringAsFixed(AppConstants.decimalPlaces)} | الفرق: ${bankDifference >= 0 ? '+' : ''}${bankDifference.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          userId: currentUserId,
        );
      }

      if (mounted) {
        final authNotifier = ref.read(authProvider.notifier);

        Navigator.pop(context);

        AppToast.show(
          context,
          tr('تم الإقفال ✓ بواسطة {currentUserName} | كاش: {p0}', {'currentUserName': currentUserName, 'p0': _cashSales.toStringAsFixed(AppConstants.decimalPlaces)}),
          type: ToastType.success,
        );

        await Future.delayed(const Duration(seconds: 1));
        authNotifier.logout();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final currentUserName =
        authState.user?.displayName ?? authState.user?.username ?? tr('مستخدم');
    final canViewDetails = ref.watch(
      hasPermissionProvider(PermissionCodes.viewDailyClosingDetails),
    );
    final showDetails = canViewDetails.when(
      data: (v) => v,
      error: (_, _) => false,
      loading: () => false,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                PhosphorIconsBold.money,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
             Text(tr('الإقفال اليومي')),
          ],
        ),
        content: _isLoading
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ===== معلومات الوردية =====
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  PhosphorIconsBold.user,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tr('الكاشير: {currentUserName}', {'currentUserName': currentUserName}),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  PhosphorIconsBold.clock,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _lastClosingTime != null
                                      ? tr('من: {p0}{p1}', {'p0': DateFormat('yyyy/MM/dd HH:mm').format(_lastClosingTime!), 'p1': _lastClosingUser != null ? ' ($_lastClosingUser)' : ''})
                                      : tr('من: بداية اليوم (أول إقفال)'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Summary cards (only for managers)
                      if (showDetails) ...[
                        _SummaryCard(
                          icon: PhosphorIconsBold.receipt,
                          label: tr('عدد الفواتير'),
                          value: '$_invoiceCount',
                          color: AppColors.info,
                        ),
                        _SummaryCard(
                          icon: PhosphorIconsBold.chartLineUp,
                          label: tr('إجمالي المبيعات'),
                          value:
                              '${_totalSales.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                          color: AppColors.success,
                        ),
                        if (_totalExpenses > 0)
                          _SummaryCard(
                            icon: PhosphorIconsBold.arrowCircleUp,
                            label: tr('المصروفات'),
                            value:
                                '-${_totalExpenses.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                            color: AppColors.error,
                          ),
                        const Divider(height: 24),
                      ],

                      // ===== قسم الكاش =====
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                             Row(
                              children: [
                                const Icon(
                                  PhosphorIconsBold.money,
                                  color: AppColors.warning,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  tr('الكاش'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (showDetails)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                   Text(tr('المسجل (من الفواتير):')),
                                  Text(
                                    '${_cashSales.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                            if (showDetails) const SizedBox(height: 8),
                            TextField(
                              controller: _actualCashController,
                              decoration: InputDecoration(
                                labelText: tr('الجرد الفعلي للكاش'),
                                prefixIcon: const Icon(PhosphorIconsBold.money),
                                suffixText: AppConstants.currencySymbolEn,
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_actualCashController.text.isNotEmpty &&
                                showDetails) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                   Text(tr('الفرق عن المُسجل:')),
                                  Text(
                                    '${(double.tryParse(_actualCashController.text) ?? 0) - _cashSales >= 0 ? '+' : ''}${((double.tryParse(_actualCashController.text) ?? 0) - _cashSales).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          ((double.tryParse(
                                                            _actualCashController
                                                                .text,
                                                          ) ??
                                                          0) -
                                                      _cashSales)
                                                  .abs() <
                                              0.01
                                          ? AppColors.success
                                          : (((double.tryParse(
                                                              _actualCashController
                                                                  .text,
                                                            ) ??
                                                            0) -
                                                        _cashSales) <
                                                    0
                                                ? AppColors.error
                                                : AppColors.warning),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ===== قسم البنك =====
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.info.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                             Row(
                              children: [
                                const Icon(
                                  PhosphorIconsBold.bank,
                                  color: AppColors.info,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  tr('البنك (بطاقة/تحويل)'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (showDetails)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                   Text(tr('المسجل (من الفواتير):')),
                                  Text(
                                    '${_bankSales.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                            if (showDetails) const SizedBox(height: 8),
                            TextField(
                              controller: _actualBankController,
                              decoration: InputDecoration(
                                labelText: tr('الجرد الفعلي للبنك'),
                                prefixIcon: const Icon(PhosphorIconsBold.bank),
                                suffixText: AppConstants.currencySymbolEn,
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_actualBankController.text.isNotEmpty &&
                                showDetails) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                   Text(tr('الفرق عن المُسجل:')),
                                  Text(
                                    '${(double.tryParse(_actualBankController.text) ?? 0) - _bankSales >= 0 ? '+' : ''}${((double.tryParse(_actualBankController.text) ?? 0) - _bankSales).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          ((double.tryParse(
                                                            _actualBankController
                                                                .text,
                                                          ) ??
                                                          0) -
                                                      _bankSales)
                                                  .abs() <
                                              0.01
                                          ? AppColors.success
                                          : (((double.tryParse(
                                                              _actualBankController
                                                                  .text,
                                                            ) ??
                                                            0) -
                                                        _bankSales) <
                                                    0
                                                ? AppColors.error
                                                : AppColors.warning),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // إجمالي الفوارق (managers only)
                      if (showDetails &&
                          (_actualCashController.text.isNotEmpty ||
                              _actualBankController.text.isNotEmpty))
                        Builder(
                          builder: (context) {
                            final actualCash =
                                double.tryParse(_actualCashController.text) ??
                                0;
                            final actualBank =
                                double.tryParse(_actualBankController.text) ??
                                0;
                            final totalActualDiff =
                                (actualCash - _cashSales) +
                                (actualBank - _bankSales);
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: totalActualDiff.abs() < 0.01
                                    ? AppColors.success.withValues(alpha: 0.1)
                                    : AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                   Text(
                                    tr('إجمالي الفرق عن المُسجل:'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${totalActualDiff >= 0 ? '+' : ''}${totalActualDiff.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: totalActualDiff.abs() < 0.01
                                          ? AppColors.success
                                          : (totalActualDiff < 0
                                                ? AppColors.error
                                                : AppColors.warning),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 16),

                      // Notes
                      TextField(
                        decoration:  InputDecoration(
                          labelText: tr('ملاحظات (اختياري)'),
                          prefixIcon: const Icon(PhosphorIconsBold.notepad),
                        ),
                        onChanged: (v) {},
                      ),
                    ],
                  ),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
          FilledButton.icon(
            onPressed: _actualCashController.text.isEmpty
                ? null
                : _performClosing,
            icon: const Icon(PhosphorIconsBold.checkCircle),
            label:  Text(tr('تأكيد الإقفال')),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
