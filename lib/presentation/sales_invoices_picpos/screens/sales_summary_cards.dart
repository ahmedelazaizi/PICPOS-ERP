// ignore_for_file: library_private_types_in_public_api
// منسوخ من lib/presentation/screens/widgets/sales_invoices/sales_summary_cards.dart
// — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
part of 'sales_invoices_picpos_screen.dart';

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
      AppKpiCard(
        icon: PhosphorIconsBold.shoppingCart,
        // البند 2: الصفة صريحة حتى لا يُقارَن الرقم بمبلغ بدون ضريبة.
        label: 'إجمالي المبيعات (شامل الضريبة)',
        value: '${totalAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
        color: AppColors.info,
        style: KpiStyle.gradient,
      ),
      Tooltip(
        message: hasReceiptVouchers
            ? 'مدفوعات الفواتير: ${totalPaid.toStringAsFixed(AppConstants.decimalPlaces)}\n'
                'سندات القبض: ${receiptVouchersTotal.toStringAsFixed(AppConstants.decimalPlaces)}'
            : 'مدفوعات الفواتير',
        child: AppKpiCard(
          icon: PhosphorIconsBold.wallet,
          label: 'المحصّل',
          value:
              '${collected.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
          color: AppColors.success,
          style: KpiStyle.gradient,
        ),
      ),
      // Returns card — when present, makes the المتبقي formula explicit
      // (المتبقي = الإجمالي − المحصل − المرتجعات).
      AppKpiCard(
        icon: PhosphorIconsBold.arrowUUpLeft,
        label: 'إجمالي المرتجعات',
        value: '${totalReturns.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
        color: AppColors.error,
        style: KpiStyle.gradient,
      ),
      AppKpiCard(
        icon: PhosphorIconsBold.clock,
        label: 'المتبقي',
        value: '${totalRemaining.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
        color: AppColors.warning,
        style: KpiStyle.gradient,
      ),
      // البند 2 — «فصل المرتجعات وظهور صافي المبيعات». بطاقة «إجمالي
      // المرتجعات» كانت موجودة أصلاً؛ الناقص كان النتيجة نفسها.
      AppKpiCard(
        icon: PhosphorIconsBold.equals,
        label: 'صافي المبيعات',
        value: '${(totalAmount - totalReturns).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
        color: AppColors.primary,
        style: KpiStyle.gradient,
      ),
      AppKpiCard(
        icon: PhosphorIconsBold.receipt,
        label: 'عدد الفواتير',
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
