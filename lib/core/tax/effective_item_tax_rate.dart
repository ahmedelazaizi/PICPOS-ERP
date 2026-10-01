/// B3 (owner decision) — the ONE rule for an item's effective tax rate.
///
/// An item marked «معفى من الضريبة» (`products.tax_exempt = 1`) is taxed at
/// 0 % everywhere: sales, POS, returns, quotations, orders, tables and
/// purchases (input VAT 0). Every other item keeps the long-standing
/// semantics: a positive item rate wins, otherwise the company default.
///
/// Paths that historically applied NO company default (they read the item
/// rate as-is) pass `companyDefault: 0`, which reproduces their old result
/// exactly for non-exempt items.
library;

/// Returns the percent rate to apply to a line.
///
/// * [exempt] → `0`, whatever [rate] or [companyDefault] say.
/// * [rate] `> 0` → [rate] (custom item rate).
/// * otherwise → [companyDefault].
double effectiveItemTaxRate({
  required double rate,
  required bool exempt,
  required double companyDefault,
}) {
  if (exempt) return 0.0;
  return rate > 0 ? rate : companyDefault;
}
