import '../../../core/utils/number_utils.dart';
import '../../entities/cart_item_entity.dart';

/// Use case for calculating invoice totals
///
/// Pure business logic - no UI or database dependencies
class CalculateInvoiceTotalsUseCase {
  /// Execute the use case
  ///
  /// Returns calculated totals for the given cart items
  InvoiceTotals execute({
    required List<CartItemEntity> items,
    double invoiceDiscountPercent = 0,
    double taxPercent = 0,
    bool taxEnabled = true,
  }) {
    if (items.isEmpty) {
      return const InvoiceTotals.empty();
    }

    // Spec 137 (BUG-C02 / BUG-H01): tax is NOT taken from the stored
    // item.taxAmount / item.calculatedTaxAmount field — that value is gross
    // and goes stale on quantity merge. It is recomputed below on the NET
    // base (after BOTH line and invoice discounts) and gated by taxEnabled,
    // matching the owner-confirmed policy and the sales-invoice path.
    double subtotal = 0;
    double itemDiscounts = 0;
    for (final item in items) {
      subtotal += item.subtotal;
      itemDiscounts += item.discountAmount;
    }

    // Apply invoice-level discount to the post-line-discount base.
    final afterItemDiscounts = subtotal - itemDiscounts;
    final invoiceDiscount = NumberUtils.roundCurrency(
      afterItemDiscounts * (invoiceDiscountPercent / 100),
    );
    final afterAllDiscounts = afterItemDiscounts - invoiceDiscount;

    // Ratio that scales each line net down to the invoice-discounted net,
    // so per-line tax rates are preserved while tax lands on the net base.
    final discountRatio =
        afterItemDiscounts > 0 ? (afterAllDiscounts / afterItemDiscounts) : 0.0;

    double taxAmount = 0;
    if (taxEnabled) {
      for (final item in items) {
        final lineNet = item.totalBeforeTax * discountRatio;
        final lineRate = item.taxRate > 0 ? item.taxRate : taxPercent;
        taxAmount += NumberUtils.roundCurrency(lineNet * (lineRate / 100));
      }
    }
    taxAmount = NumberUtils.roundCurrency(taxAmount);

    final total = NumberUtils.roundCurrency(afterAllDiscounts + taxAmount);

    return InvoiceTotals(
      itemCount: items.length,
      quantityTotal: items.fold(0, (sum, item) => sum + item.quantity),
      subtotal: NumberUtils.roundCurrency(subtotal),
      itemDiscounts: NumberUtils.roundCurrency(itemDiscounts),
      invoiceDiscount: invoiceDiscount,
      totalDiscount: NumberUtils.roundCurrency(itemDiscounts + invoiceDiscount),
      taxAmount: taxAmount,
      total: total,
    );
  }
}

/// Invoice totals result
class InvoiceTotals {
  final int itemCount;
  final double quantityTotal;
  final double subtotal;
  final double itemDiscounts;
  final double invoiceDiscount;
  final double totalDiscount;
  final double taxAmount;
  final double total;

  const InvoiceTotals({
    required this.itemCount,
    required this.quantityTotal,
    required this.subtotal,
    required this.itemDiscounts,
    required this.invoiceDiscount,
    required this.totalDiscount,
    required this.taxAmount,
    required this.total,
  });

  const InvoiceTotals.empty()
    : itemCount = 0,
      quantityTotal = 0,
      subtotal = 0,
      itemDiscounts = 0,
      invoiceDiscount = 0,
      totalDiscount = 0,
      taxAmount = 0,
      total = 0;

  /// Calculate change for given payment
  double changeFor(double paid) =>
      NumberUtils.roundCurrency(paid > total ? paid - total : 0);

  /// Calculate remaining balance
  double remainingFor(double paid) =>
      NumberUtils.roundCurrency(paid >= total ? 0 : total - paid);
}
