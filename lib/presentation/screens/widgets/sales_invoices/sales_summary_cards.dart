// ignore_for_file: library_private_types_in_public_api
part of '../../sales_invoices_screen.dart';

/// كارت مبلغ في شريط الإجماليات — محجوب بـ`sales_amounts_view`.
///
/// تمويه صفوف الجدول وسيبان الإجماليات فوقه كان بيسرّب نفس البيانات مجمّعة،
/// فالكروت لازم تتحجب بنفس الكود. الكارت نفسه فاضل ظاهر بعنوانه — الرقم بس
/// هو اللي بيتموّه، عشان المستخدم يعرف إن فيه بيانات مش إنها صفر.
@visibleForTesting
Widget buildMaskedAmountKpiCard({
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  AppKpiCard card(String v) => AppKpiCard(
        icon: icon,
        label: label,
        value: v,
        color: color,
        style: KpiStyle.gradient,
      );
  return PermissionGuard(
    permission: PermissionCodes.salesAmountsView,
    fallback: card(kMaskedValuePlaceholder),
    child: card(value),
  );
}

class SalesSummaryRow extends ConsumerWidget {
  const SalesSummaryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAmount = ref.watch(salesInvoicesControllerProvider.select((s) => s.totalAmount));
    final totalPaid = ref.watch(salesInvoicesControllerProvider.select((s) => s.totalPaid));
    // Issue 10 — receipt vouchers in the same filter set, summed in.
    final receiptVouchersTotal = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.receiptVouchersTotal));
    final totalRemaining = ref.watch(salesInvoicesControllerProvider.select((s) => s.totalRemaining));
    final totalReturns = ref.watch(salesInvoicesControllerProvider.select((s) => s.totalReturns));
    final invoiceCount = ref.watch(salesInvoicesControllerProvider.select((s) => s.invoiceCount));

    // المحصّل = مدفوعات الفواتير + سندات القبض (Issue 10).
    final collected = totalPaid + receiptVouchersTotal;
    final hasReceiptVouchers = receiptVouchersTotal > 0;

    final cards = <Widget>[
      buildMaskedAmountKpiCard(
        icon: PhosphorIconsBold.shoppingCart,
        // البند 2: الصفة صريحة حتى لا يُقارَن الرقم بمبلغ بدون ضريبة.
        label: tr('إجمالي المبيعات (شامل الضريبة)'),
        value: '${totalAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
        color: AppColors.info,
      ),
      Tooltip(
        // الـtooltip بيفصّل مدفوعات الفواتير وسندات القبض — نفس المبالغ،
        // فبيتحجب مع الكارت لا قبله.
        message: hasReceiptVouchers
            ? 'مدفوعات الفواتير: ${totalPaid.toStringAsFixed(AppConstants.decimalPlaces)}\n'
                'سندات القبض: ${receiptVouchersTotal.toStringAsFixed(AppConstants.decimalPlaces)}'
            : tr('مدفوعات الفواتير'),
        child: buildMaskedAmountKpiCard(
          icon: PhosphorIconsBold.wallet,
          label: tr('المحصّل'),
          value:
              '${collected.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          color: AppColors.success,
        ),
      ),
      // Returns card — when present, makes the المتبقي formula explicit
      // (المتبقي = الإجمالي − المحصل − المرتجعات).
      buildMaskedAmountKpiCard(
        icon: PhosphorIconsBold.arrowUUpLeft,
        label: tr('إجمالي المرتجعات'),
        value: '${totalReturns.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
        color: AppColors.error,
      ),
      buildMaskedAmountKpiCard(
        icon: PhosphorIconsBold.clock,
        label: tr('المتبقي'),
        value: '${totalRemaining.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
        color: AppColors.warning,
      ),
      // البند 2 — «فصل المرتجعات وظهور صافي المبيعات». بطاقة «إجمالي
      // المرتجعات» كانت موجودة أصلاً؛ الناقص كان النتيجة نفسها.
      buildMaskedAmountKpiCard(
        icon: PhosphorIconsBold.equals,
        label: tr('صافي المبيعات'),
        value: '${(totalAmount - totalReturns).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
        color: AppColors.primary,
      ),
      AppKpiCard(
        icon: PhosphorIconsBold.receipt,
        label: tr('عدد الفواتير'),
        value: '$invoiceCount',
        color: AppColors.primary,
        style: KpiStyle.gradient,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          // البند 2 — ستّ بطاقات الآن (أُضيفت «صافي المبيعات»).
          final perRow = w >= 1200
              ? 6
              : w >= 900
                  ? 4
                  : w >= 600
                      ? 3
                      : 2;
          const spacing = 10.0;
          final cardWidth = (w - (perRow - 1) * spacing) / perRow;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: cards
                .map((c) => SizedBox(
                      width: cardWidth,
                      height: 72,
                      child: c,
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
