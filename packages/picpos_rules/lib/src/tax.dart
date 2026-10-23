/// Tax and document totals. `effectiveItemTaxRate` is the desktop rule
/// `lib/core/tax/effective_item_tax_rate.dart` (picpos_erp); `computeTotals`
/// follows desktop `FinancialUtils.calculateInvoiceTotals`
/// (lib/core/utils/financial_utils.dart) for line discounts and both pricing
/// modes.
library;

double effectiveItemTaxRate({
  required double rate,
  required bool exempt,
  required double companyDefault,
}) {
  if (exempt) return 0.0;
  return rate > 0 ? rate : companyDefault;
}

/// Desktop `FinancialUtils.round`: normalise float noise, then round half away
/// from zero to [decimals] places.
double roundDp(double v, [int decimals = 2]) {
  var f = 1.0;
  for (var i = 0; i < decimals; i++) {
    f *= 10;
  }
  final n = double.parse(v.toStringAsFixed(10));
  return (n * f).round() / f;
}

double round2(double v) => roundDp(v, 2);

class LineInput {
  LineInput({
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
  });
  final double quantity;
  final double unitPrice;
  final double discount;
  final double taxRate;
}

class LineTotals {
  LineTotals(this.gross, this.discount, this.net, this.tax, this.total);
  final double gross;
  final double discount;

  /// Line amount excluding tax, after the line discount.
  final double net;
  final double tax;
  final double total;
}

class DocTotals {
  DocTotals(this.lines, this.subtotal, this.discount, this.net, this.tax, this.total);
  final List<LineTotals> lines;

  /// Σ qty × price as entered (tax-inclusive when the company prices include tax).
  final double subtotal;
  final double discount;

  /// Σ line net excluding tax.
  final double net;
  final double tax;
  final double total;
}

/// Per line: gross = r(qty × price); discount clamped to [0, gross];
/// amount = r(gross − discount).
/// - tax-exclusive: net = amount, tax = r(net × rate / 100)
/// - tax-inclusive: net = r(amount / (1 + rate / 100)), tax = r(amount − net)
/// - rate ≤ 0: tax = 0
/// Document: tax = r(Σ line tax), total = r(Σ net + tax).
/// Header discounts are not used by the mobile flow.
DocTotals computeTotals(
  List<LineInput> lines, {
  bool pricesIncludeTax = false,
  int decimals = 2,
}) {
  double r(double v) => roundDp(v, decimals);
  final out = <LineTotals>[];
  var sub = 0.0, disc = 0.0, net = 0.0, tax = 0.0;
  for (final l in lines) {
    final gross = r(l.quantity * l.unitPrice);
    final d = r(l.discount.clamp(0, gross < 0 ? 0 : gross).toDouble());
    final amount = r(gross - d);
    double lineNet, lineTax;
    if (l.taxRate <= 0) {
      lineNet = amount;
      lineTax = 0;
    } else if (pricesIncludeTax) {
      lineNet = r(amount / (1 + l.taxRate / 100));
      lineTax = r(amount - lineNet);
    } else {
      lineNet = amount;
      lineTax = r(amount * l.taxRate / 100);
    }
    out.add(LineTotals(gross, d, lineNet, lineTax, r(lineNet + lineTax)));
    sub += gross;
    disc += d;
    net += lineNet;
    tax += lineTax;
  }
  tax = r(tax);
  return DocTotals(out, r(sub), r(disc), r(net), tax, r(net + tax));
}
