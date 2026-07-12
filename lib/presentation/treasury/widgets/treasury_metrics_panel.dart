import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import 'receipt_voucher_dialog.dart';
import 'payment_voucher_dialog.dart';
import '../../widgets/permission_guard.dart';

import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../data/providers/providers.dart';
import '../../../core/constants/app_constants.dart';

class TreasuryMetricsPanel extends ConsumerWidget {
  const TreasuryMetricsPanel({super.key});

  void _showReceiptVoucherDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ReceiptVoucherDialog(),
    );
  }

  void _showPaymentVoucherDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PaymentVoucherDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalBalance = ref.watch(totalCashBalanceProvider);
    final localizations = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              PhosphorIconsBold.wallet,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.totalTreasuryBalance,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 4),
              totalBalance.when(
                data: (balance) => Text(
                  '${NumberFormat('#,##0.00', 'ar').format(balance)} ${AppConstants.currencySymbolEn}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                loading: () => const Text(
                  '...',
                  style: TextStyle(color: Colors.white, fontSize: 32),
                ),
                error: (e, s) => Text(
                  '0.00 ${AppConstants.currencySymbolEn}',
                  style: const TextStyle(color: Colors.white, fontSize: 32),
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            children: [
              // Receipt Voucher - Requires permission
              PermissionGuard(
                permission: PermissionCodes.treasuryReceiptsCreate,
                allowManagerOverride: true,
                actionName: 'إنشاء سند قبض',
                child: ElevatedButton.icon(
                  onPressed: () => _showReceiptVoucherDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  icon: const Icon(PhosphorIconsBold.plus),
                  label: Text(localizations.receiptVoucher),
                ),
              ),
              const SizedBox(height: 8),
              // Payment Voucher - Requires permission
              PermissionGuard(
                permission: PermissionCodes.treasuryPaymentsCreate,
                allowManagerOverride: true,
                actionName: 'إنشاء سند صرف',
                child: OutlinedButton.icon(
                  onPressed: () => _showPaymentVoucherDialog(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                  icon: const Icon(PhosphorIconsBold.minus),
                  label: Text(localizations.paymentVoucher),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
