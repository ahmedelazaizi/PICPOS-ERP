import '../../../core/tax/effective_item_tax_rate.dart';
import '../../../core/utils/financial_utils.dart';
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

    final subtotal = items.fold<double>(0, (sum, item) => sum + item.subtotal);
    final itemDiscounts = items.fold<double>(
      0,
      (sum, item) => sum + item.discountAmount,
    );
    final invoiceDiscountBase = FinancialUtils.round(subtotal - itemDiscounts);
    final invoiceDiscount = FinancialUtils.round(
      invoiceDiscountBase * (invoiceDiscountPercent / 100),
    );
    final totals = FinancialUtils.calculateInvoiceTotals(
      items: items
          .map(
            (item) => (
              quantity: item.quantity,
              unitPrice: item.effectivePrice,
              taxRatePercent: taxEnabled
                  ? effectiveItemTaxRate(
                      rate: item.taxRate,
                      exempt: item.taxExempt,
                      companyDefault: taxPercent,
                    )
                  : 0.0,
            ),
          )
          .toList(),
      globalDiscountAmount: invoiceDiscount,
      lineDiscountAmounts: items.map((item) => item.discountAmount).toList(),
    );
    final taxAmount = taxEnabled ? totals.totalTax : 0.0;
    final total = totals.grandTotal;

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
