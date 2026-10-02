/// Same rules as the cloud (`server/lib/src/domain/tax.dart`) and the desktop
/// (`lib/core/tax/effective_item_tax_rate.dart`), so the device shows the
/// totals the server will accept. Shared package extraction: I-4.
library;

double effectiveItemTaxRate({required double rate, required bool exempt, required double companyDefault}) {
  if (exempt) return 0.0;
  return rate > 0 ? rate : companyDefault;
}

double round2(double v) => (v * 100).roundToDouble() / 100;

class CartLine {
  CartLine({required this.productGlobalId, required this.name, required this.unitPrice, required this.taxRate, this.quantity = 1});
  final String productGlobalId;
  final String name;
  final double unitPrice;
  final double taxRate;
  double quantity;
}

class Totals {
  const Totals(this.subtotal, this.tax, this.total);
  final double subtotal, tax, total;
}

Totals computeTotals(Iterable<CartLine> lines) {
  var sub = 0.0, tax = 0.0;
  for (final l in lines) {
    final net = round2(l.quantity * l.unitPrice);
    sub += net;
    tax += round2(net * l.taxRate / 100);
  }
  sub = round2(sub);
  tax = round2(tax);
  return Totals(sub, tax, round2(sub + tax));
}

/// Desktop parity: limit 0 = no limit; only a remaining amount > 0.01 counts.
bool exceedsCreditLimit({required double balance, required double creditLimit, required double remaining}) =>
    remaining > 0.01 && creditLimit > 0 && balance + remaining > creditLimit;
