/// Ported verbatim from `lib/core/tax/effective_item_tax_rate.dart` (ural_erp).
/// Keep in sync until the shared `picpos_domain` package exists (I-4);
/// `test/domain_test.dart` pins the behaviour.
library;

double effectiveItemTaxRate({
  required double rate,
  required bool exempt,
  required double companyDefault,
}) {
  if (exempt) return 0.0;
  return rate > 0 ? rate : companyDefault;
}

double round2(double v) => (v * 100).roundToDouble() / 100;

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
  LineTotals(this.net, this.tax);
  final double net;
  final double tax;
  double get total => round2(net + tax);
}

class DocTotals {
  DocTotals(this.lines, this.subtotal, this.discount, this.tax, this.total);
  final List<LineTotals> lines;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
}

/// I-1 pricing model: tax-exclusive unit prices, per-line discount amount,
/// tax per line on (qty * price - discount), 2-dp rounding per line.
/// Tax-inclusive companies and header discounts are an I-2 item.
DocTotals computeTotals(List<LineInput> lines) {
  final out = <LineTotals>[];
  var sub = 0.0, disc = 0.0, tax = 0.0;
  for (final l in lines) {
    final gross = round2(l.quantity * l.unitPrice);
    final net = round2(gross - l.discount);
    final t = round2(net * l.taxRate / 100);
    out.add(LineTotals(net, t));
    sub += gross;
    disc += l.discount;
    tax += t;
  }
  sub = round2(sub);
  disc = round2(disc);
  tax = round2(tax);
  return DocTotals(out, sub, disc, tax, round2(sub - disc + tax));
}
