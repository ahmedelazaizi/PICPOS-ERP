import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../domain/models/exchange_settlement.dart';
import 'picpos_pos_text.dart';

/// ترويسةُ وضع الاستبدال — الأرقامُ الثلاثة.
///
/// **الثلاثةُ تُمرَّر ولا تُشتقّ هنا:** الفرقُ واتّجاهُه يأتيان محسوبَين من
/// `settleExchange` عبر `PosExchangeMode.previewSettlement`، وهي نفسُ الدالّة
/// التي ينفّذها المستودع. واشتقاقُ الفرق في الودجت — ولو بطرحٍ بسيط — يُنشئ
/// حاسباً ثانياً يفترق عن الأوّل عند أوّل تقريب، وهو العطبُ الذي عرض «١٠٠»
/// وأخرج «١١٤» من الدرج.
class PicPosExchangeModeBanner extends StatelessWidget {
  final String invoiceNumber;
  final double refundTotal;
  final double replacementTotal;
  final ExchangeCashDirection direction;
  final double difference;

  const PicPosExchangeModeBanner({
    super.key,
    required this.invoiceNumber,
    required this.refundTotal,
    required this.replacementTotal,
    required this.direction,
    required this.difference,
  });

  /// نصُّ الفرق ولونُه — الاتّجاهُ يحمل الإشارةَ لا الرقم.
  (String, Color) get _difference => switch (direction) {
        ExchangeCashDirection.collect => (
            'يُحصَّل ${NumberUtils.formatCurrency(difference)}',
            AppColors.success,
          ),
        ExchangeCashDirection.refund => (
            'يُرَدّ ${NumberUtils.formatCurrency(difference)}',
            AppColors.error,
          ),
        ExchangeCashDirection.none => ('لا فرق', AppColors.textSecondary),
      };

  @override
  Widget build(BuildContext context) {
    final (differenceLabel, differenceColor) = _difference;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsBold.arrowsLeftRight,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Text('وضع الاستبدال',
                  style: PicPosText.v(13, color: AppColors.warning)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  invoiceNumber,
                  overflow: TextOverflow.ellipsis,
                  style: PicPosText.v(13, color: AppColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'المرتجع ${NumberUtils.formatCurrency(refundTotal)}',
                  overflow: TextOverflow.ellipsis,
                  style: PicPosText.v(12, color: AppColors.textSecondary),
                ),
              ),
              Expanded(
                child: Text(
                  'البديل ${NumberUtils.formatCurrency(replacementTotal)}',
                  overflow: TextOverflow.ellipsis,
                  style: PicPosText.v(12, color: AppColors.textSecondary),
                ),
              ),
              Expanded(
                child: Text(
                  differenceLabel,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: PicPosText.v(12, color: differenceColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
