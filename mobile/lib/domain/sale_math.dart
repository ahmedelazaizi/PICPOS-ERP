/// Cart helpers on top of the shared pricing rules (`pricing.dart`, same
/// code and fixture as the cloud), so the device shows the totals the server
/// will accept.
library;

import 'pricing.dart';

export 'pricing.dart';

class CartLine {
  CartLine({
    required this.productGlobalId,
    required this.name,
    required this.unitPrice,
    required this.taxRate,
    this.quantity = 1,
  });
  final String productGlobalId;
  final String name;

  /// Price as entered (tax-inclusive when the company prices include tax).
  double unitPrice;
  final double taxRate;
  double quantity;

  LineInput toInput() => LineInput(quantity: quantity, unitPrice: unitPrice, discount: 0, taxRate: taxRate);
}

DocTotals cartTotals(Iterable<CartLine> lines, {bool pricesIncludeTax = false, int decimals = 2}) =>
    computeTotals([for (final l in lines) l.toInput()], pricesIncludeTax: pricesIncludeTax, decimals: decimals);

/// Desktop parity: limit 0 = no limit; only a remaining amount > 0.01 counts.
bool exceedsCreditLimit({required double balance, required double creditLimit, required double remaining}) =>
    remaining > 0.01 && creditLimit > 0 && balance + remaining > creditLimit;
