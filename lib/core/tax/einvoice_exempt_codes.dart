/// B3 (owner decision) — e-invoice classification of a «معفى» line.
///
/// An exempt line is NOT zero-rated: authorities report the two separately.
///
/// * ETA (Egypt): tax type `T1` with subtype `V003` — «سلعة معفاة / Exempt
///   Goods» in the seeded `tax_subtypes` reference (`e_invoicing_dao.dart`).
/// * JoFotara (Jordan, UBL): tax category `E` (exempt) — `Z` would be
///   zero-rated, `S` standard.
library;

/// ETA VAT subtype for exempt goods/services.
const String kEtaExemptTaxSubtype = 'V003';

/// JoFotara / UBL tax-category code for an exempt line.
const String kJofotaraExemptTaxCategory = 'E';

/// A line is classified exempt only when its product is flagged
/// `tax_exempt` AND the line actually carries no tax. A historical line sold
/// with tax before the flag drove money keeps its original classification —
/// declaring a taxed line "exempt" would contradict its own amount.
bool isExemptEInvoiceLine({
  required bool productExempt,
  required double lineTaxAmount,
}) =>
    productExempt && lineTaxAmount.abs() < 0.005;
