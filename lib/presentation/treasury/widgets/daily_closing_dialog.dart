import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../widgets/permission_guard.dart';
import 'package:ural_erp/core/constants/app_constants.dart';

import '../../../data/providers/providers.dart';

import 'package:ural_erp/l10n/app_localizations.dart';

class DailyClosingDialog extends ConsumerStatefulWidget {
  final SafeData safe;

  const DailyClosingDialog({super.key, required this.safe});

  @override
  ConsumerState<DailyClosingDialog> createState() => _DailyClosingDialogState();
}

class _DailyClosingDialogState extends ConsumerState<DailyClosingDialog> {
  final cashController = TextEditingController();
  final bankController = TextEditingController();
  final clickController = TextEditingController();
  final notesController = TextEditingController();
  double difference = 0.0;

  // Daily summary data
  double _totalReceipts = 0;
  double _totalPayments = 0;
  double _totalExpenses = 0;
  int _transactionCount = 0;
  bool _summaryLoaded = false;

  @override
  void initState() {
    super.initState();
    cashController.addListener(_calculateDifference);
    bankController.addListener(_calculateDifference);
    clickController.addListener(_calculateDifference);
    _loadDailySummary();
  }

  Future<void> _loadDailySummary() async {
    try {
      final repo = ref.read(treasuryRepositoryProvider);
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      // Query today's transactions for this safe via repository
      final transactions = await repo.getSafeTransactionsForDate(
        widget.safe.id,
        startOfDay,
      );

      double receipts = 0;
      double payments = 0;
      double expenses = 0;

      for (final tx in transactions) {
        if (tx.transactionType == 'receipt') {
          receipts += tx.amount;
        } else if (tx.transactionType == 'payment' || tx.transactionType == 'withdrawal') {
          if (tx.category == 'expense') {
            expenses += tx.amount;
          } else {
            payments += tx.amount;
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalReceipts = receipts;
          _totalPayments = payments;
          _totalExpenses = expenses;
          _transactionCount = transactions.length;
          _summaryLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('[DailyClosing] Failed to load summary: $e');
      if (mounted) setState(() => _summaryLoaded = true);
    }
  }

  double get _actualTotal {
    final cash = double.tryParse(cashController.text) ?? 0.0;
    final bank = double.tryParse(bankController.text) ?? 0.0;
    final click = double.tryParse(clickController.text) ?? 0.0;
    return cash + bank + click;
  }

  void _calculateDifference() {
    setState(() {
      difference = _actualTotal - widget.safe.balance;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final numberFormat = NumberFormat('#,##0.00', 'ar');

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEE5A24).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              PhosphorIconsBold.lockKey,
              color: Color(0xFFEE5A24),
            ),
          ),
          const SizedBox(width: 12),
          Text(localizations.dailyClosingTitle(widget.safe.name)),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ═══════════════════════════════════════════
              // Daily Summary Report
              // ═══════════════════════════════════════════
              PermissionGuard(
                permission: PermissionCodes.viewDailyClosingDetails,
                fallback: const SizedBox.shrink(),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(PhosphorIconsBold.chartBar, size: 16, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text(
                            'ملخص اليوم',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                          ),
                        ],
                      ),
                      const Divider(height: 16),

                      // System Balance
                      _buildSummaryRow(
                        'رصيد النظام',
                        numberFormat.format(widget.safe.balance),
                        AppColors.primary,
                        PhosphorIconsBold.wallet,
                        isBold: true,
                      ),
                      const SizedBox(height: 8),

                      if (_summaryLoaded) ...[
                        _buildSummaryRow(
                          'التحصيلات (إيرادات)',
                          '+${numberFormat.format(_totalReceipts)}',
                          AppColors.success,
                          PhosphorIconsBold.arrowDown,
                        ),
                        const SizedBox(height: 4),
                        _buildSummaryRow(
                          'المدفوعات (مصروفات)',
                          '-${numberFormat.format(_totalPayments + _totalExpenses)}',
                          AppColors.error,
                          PhosphorIconsBold.arrowUp,
                        ),
                        const SizedBox(height: 4),
                        _buildSummaryRow(
                          'عدد العمليات',
                          '$_transactionCount عملية',
                          AppColors.textMuted,
                          PhosphorIconsBold.listNumbers,
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ═══════════════════════════════════════════
              // Actual Count Inputs
              // ═══════════════════════════════════════════
              const Text(
                'العد الفعلي:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 10),

              // Cash Input
              _buildAmountInput(
                controller: cashController,
                label: 'الكاش (نقدي)',
                hintLabel: 'المبلغ النقدي الفعلي',
                icon: PhosphorIconsBold.money,
                color: AppColors.success,
              ),
              const SizedBox(height: 10),

              // Bank Input
              _buildAmountInput(
                controller: bankController,
                label: 'البنك (تحويل/شبكة)',
                hintLabel: 'مبلغ البنك الفعلي',
                icon: PhosphorIconsBold.creditCard,
                color: AppColors.info,
              ),
              const SizedBox(height: 10),

              // Click Input
              _buildAmountInput(
                controller: clickController,
                label: 'كليك',
                hintLabel: 'مبلغ الكليك الفعلي',
                icon: PhosphorIconsBold.cursorClick,
                color: const Color(0xFF7E57C2),
              ),
              const SizedBox(height: 14),

              // Total Summary
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'إجمالي العد الفعلي:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${numberFormat.format(_actualTotal)} ${AppConstants.currencySymbol}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // Difference Display
              if (difference != 0) ...[
                const SizedBox(height: 10),
                PermissionGuard(
                  permission: PermissionCodes.viewDailyClosingDetails,
                  fallback: const SizedBox.shrink(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: difference < 0
                          ? AppColors.error.withValues(alpha: 0.1)
                          : AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          difference < 0
                              ? PhosphorIconsBold.warning
                              : PhosphorIconsBold.checkCircle,
                          color: difference < 0
                              ? AppColors.error
                              : AppColors.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          difference < 0 ? 'عجز: ' : 'زيادة: ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: difference < 0
                                ? AppColors.error
                                : AppColors.success,
                          ),
                        ),
                        Text(
                          '${numberFormat.format(difference.abs())} ${AppConstants.currencySymbol}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: difference < 0
                                ? AppColors.error
                                : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات الإقفال',
                  hintText: 'اكتب أي ملاحظات بخصوص العجز/الزيادة أو الترحيل...',
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 6),
              Text(
                localizations.closingNote,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            final cashAmount = double.tryParse(cashController.text) ?? 0;
            final bankAmount = double.tryParse(bankController.text) ?? 0;
            final clickAmount = double.tryParse(clickController.text) ?? 0;
            final total = cashAmount + bankAmount + clickAmount;

            if (total == 0 &&
                cashController.text.isEmpty &&
                bankController.text.isEmpty &&
                clickController.text.isEmpty) {
              AppToast.show(context, localizations.enterValidAmount);
              return;
            }

            try {
              final repo = ref.read(treasuryRepositoryProvider);

              await repo.closeSafe(
                widget.safe.id,
                cashAmount: cashAmount,
                bankAmount: bankAmount,
                notes: notesController.text,
              );

              // Log activity
              try {
                final user = ref.read(authProvider).user;
                final activityLogRepo = ref.read(activityLogRepositoryProvider);
                await activityLogRepo.logActivity(
                  userId: user?.id,
                  userName: user?.displayName ?? 'مستخدم',
                  action: 'daily_closing',
                  entityType: 'safe',
                  entityId: widget.safe.id,
                  description:
                      'إقفال يومي — خزينة: ${widget.safe.name} | كاش: $cashAmount | بنك: $bankAmount | كليك: $clickAmount | فرق: $difference',
                  amount: total,
                );
              } catch (e) {
                debugPrint('[ActivityLog] Error: $e');
              }

              if (context.mounted) {
                Navigator.pop(context);
                AppToast.show(
                  context,
                  localizations.closingSuccess(widget.safe.name),
                );
              }
            } catch (e) {
              if (context.mounted) {
                AppToast.show(context, 'Error: $e');
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEE5A24),
          ),
          icon: const Icon(PhosphorIconsBold.lockKey, size: 18),
          label: Text(localizations.confirmCloseAndReset),
        ),
      ],
    );
  }

  Widget _buildAmountInput({
    required TextEditingController controller,
    required String label,
    required String hintLabel,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: hintLabel,
              suffixText: AppConstants.currencySymbol,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.left,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color color, IconData icon, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: isBold ? null : AppColors.textMuted)),
          ],
        ),
        Text(
          '$value ${value.contains('عملية') ? '' : AppConstants.currencySymbol}',
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 15 : 12,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    cashController.dispose();
    bankController.dispose();
    clickController.dispose();
    notesController.dispose();
    super.dispose();
  }
}
