/// Cart helpers on top of the shared rules package `picpos_rules` (the same
/// code the cloud gate runs — tax, totals, pricing, credit limit), so the
/// device shows the totals the server will accept.
library;

import 'package:picpos_rules/picpos_rules.dart';

export 'package:picpos_rules/picpos_rules.dart';

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
