import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../domain/models/exchange_settlement.dart';
import 'picpos_pos_text.dart';
import '../../picpos_shell/picpos_surface.dart';

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
  /// [bg] الخلفية المصبوغة الفعلية — الألوان الدلالية تُقرأ عليها لا على الكرت.
  (String, Color) _difference(BuildContext context, Color bg) =>
      switch (direction) {
        ExchangeCashDirection.collect => (
            tr('يُحصَّل {p0}', {'p0': NumberUtils.formatCurrency(difference)}),
            PicPosText.readableOn(context, AppColors.success, on: bg),
          ),
        ExchangeCashDirection.refund => (
            tr('يُرَدّ {p0}', {'p0': NumberUtils.formatCurrency(difference)}),
            PicPosText.readableOn(context, AppColors.error, on: bg),
          ),
        ExchangeCashDirection.none => (tr('لا فرق'), context.picposSecondary),
      };

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.warning.withValues(alpha: 0.12);
    final bg = Color.alphaBlend(tint, context.picposCard);
    final (differenceLabel, differenceColor) = _difference(context, bg);
    final ink = PicPosText.readableOn(context, AppColors.warning, on: bg);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsBold.arrowsLeftRight, size: 16, color: ink),
              const SizedBox(width: 8),
              Text(tr('وضع الاستبدال'),
                  style: PicPosText.v(context, 13, color: ink)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  invoiceNumber,
                  overflow: TextOverflow.ellipsis,
                  style: PicPosText.v(context, 13, color: ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('المرتجع {p0}', {'p0': NumberUtils.formatCurrency(refundTotal)}),
                  overflow: TextOverflow.ellipsis,
                  style: PicPosText.v(context, 12, color: context.picposSecondary),
                ),
              ),
              Expanded(
                child: Text(
                  tr('البديل {p0}', {'p0': NumberUtils.formatCurrency(replacementTotal)}),
                  overflow: TextOverflow.ellipsis,
                  style: PicPosText.v(context, 12, color: context.picposSecondary),
                ),
              ),
              Expanded(
                child: Text(
                  differenceLabel,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: PicPosText.v(context, 12, color: differenceColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
