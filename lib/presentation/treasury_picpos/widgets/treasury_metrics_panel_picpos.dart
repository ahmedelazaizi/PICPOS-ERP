// لوحُ مقاييس الخزينة بهويّة PicPos — **فوركٌ بقرار المالك 2026-08-22**
// («انسخه إلى PicPos ولا تشارك تعديلاتِ PicPos على UralCash»).
//
// المصدر: `treasury/widgets/treasury_metrics_panel.dart`، ويبقى بلا مساسٍ
// لشاشة UralCash.
//
// **الجديدُ من التصميم:** شريطُ تقسيمِ الرصيد (`trSplit`) — نقديٌّ وبنكيٌّ
// بنسبتَيهما. والأصلُ يعرض المجموعَ وحدَه.
//
// ⚠️ **وحرّاسُ السندَين نُقلا كما هما** (`treasury_receipts_create` و
// `treasury_payments_create` بـ`allowManagerOverride`). حذفُ حارسٍ أثناء
// النسخ هو بالضبط فئةُ العطب التي وُجد `picpos_permission_parity_test`
// لأجلها — ومُقاسةٌ هنا في `picpos_treasury_metrics_test`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../domain/models/picpos_treasury_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../treasury/widgets/receipt_voucher_dialog.dart';
import '../../treasury/widgets/payment_voucher_dialog.dart';
import '../../widgets/permission_guard.dart';

import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../data/providers/providers.dart';
import '../../../core/constants/app_constants.dart';

class TreasuryMetricsPanelPicpos extends ConsumerWidget {
  const TreasuryMetricsPanelPicpos({super.key});

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

/// شريطُ تقسيم الرصيد — `trSplit` في التصميم.
///
/// ⚠️ **الأرقامُ تُعرَض دائماً، والشريطُ لا.** مجموعٌ صفريٌّ أو سالبٌ (‏صندوقٌ
/// مسحوبٌ عليه، أو نظامٌ لم يبدأ) لا يُرسم له شريطٌ — قسمةُ الكسور عليه تعطي
/// `NaN` في Dart لا استثناءً، فينفجر في طبقة الرسم بعيداً عن سببه. راجع
/// [PicPosTreasurySplit.hasBar].
@visibleForTesting
class PicPosTreasurySplitBar extends StatelessWidget {
  const PicPosTreasurySplitBar({super.key, required this.split});

  final PicPosTreasurySplit split;

  static const _colors = <String, Color>{
    'cash': AppColors.success,
    'bank': AppColors.info,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (split.hasBar) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final s in split.slices)
                    if (s.fraction > 0)
                      Expanded(
                        flex: (s.fraction * 1000).round(),
                        child: ColoredBox(
                          color: _colors[s.kind] ?? AppColors.textMuted,
                          child: const SizedBox.expand(),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            for (final s in split.slices)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _colors[s.kind] ?? AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    s.label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.valueLabel,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  // النسبةُ تُخفى حين لا شريط: «‏0%» على مجموعٍ سالبٍ تُقرأ
                  // خطأً كأن الرصيدَ صفر.
                  if (split.hasBar) ...[
                    const SizedBox(width: 6),
                    Text(
                      s.percentLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ],
    );
  }
}
