/// البند 5 (المالك) — ضريبة الصنف كثلاث حالات صريحة بدل قائمة واحدة.
///
/// The old dropdown stored ONE value, `products.tax_rate`, and its
/// «معفي / صفر ٪» option wrote `0`. Every sale path reads that column as
/// `taxRate > 0 ? taxRate : companyDefault` (picpos_invoice_form,
/// CalculateInvoiceTotalsUseCase, SalesTransactionOrchestrator,
/// TableOrderTotals) — so `0` is also what "no item-specific rate" means.
///
/// ── Representation (unchanged for every downstream reader) ──────────────
///   exempt          → tax_rate = 0 · products.tax_exempt = 1
///   company default → tax_rate = 0 · products.tax_exempt = 0
///   custom rate r   → tax_rate = r · products.tax_exempt = 0
///
/// `tax_rate` is written exactly as the dropdown wrote it for the equivalent
/// choice, so invoices, VAT reports (GL-based) and e-invoicing (line
/// rate/amount; ETA subtype untouched) compute identically. `tax_exempt`
/// (raw column, v182) is read by NOTHING but the product dialogs: it only lets
/// the form reopen an exempt item as exempt instead of as "default".
///
/// ⚠️ Known pre-existing semantics, deliberately NOT changed here: because
/// `tax_rate = 0` falls back to the company default on the PicPos sale paths,
/// an item marked exempt is still taxed at the default rate there — exactly as
/// the old «معفي» dropdown option was. Making exemption real needs those
/// readers to honour `tax_exempt`; that is a calculation change, out of scope.
///
/// ── B3 (owner decision) — the two paragraphs above are SUPERSEDED ─────────
/// Every sale/return/table/POS/purchase path now resolves the line rate via
/// `effectiveItemTaxRate` (`effective_item_tax_rate.dart`): exempt → 0 %.
/// `tax_exempt` syncs with the product and e-invoices classify such lines as
/// exempt. Items with `tax_exempt = 0` compute exactly as before.
library;

import '../i18n/tr.dart';
import 'tax_rate_policy.dart';

enum ProductTaxMode { companyDefault, exempt, custom }

class ProductTaxChoice {
  const ProductTaxChoice._(this.mode, this.rate);

  const ProductTaxChoice.companyDefault()
      : this._(ProductTaxMode.companyDefault, null);
  const ProductTaxChoice.exempt() : this._(ProductTaxMode.exempt, null);
  const ProductTaxChoice.custom(double rate)
      : this._(ProductTaxMode.custom, rate);

  final ProductTaxMode mode;

  /// The item-specific rate (percent); non-null only for [ProductTaxMode.custom].
  final double? rate;

  /// Maps stored values to the three UI states. A positive `tax_rate` always
  /// wins: it is what every sale path applies, whatever the flag says.
  factory ProductTaxChoice.fromStored({
    required double taxRate,
    required bool taxExempt,
  }) {
    if (taxRate > 0) return ProductTaxChoice.custom(taxRate);
    return taxExempt
        ? const ProductTaxChoice.exempt()
        : const ProductTaxChoice.companyDefault();
  }

  /// Value for `products.tax_rate` — identical to the old dropdown's output.
  double get storedTaxRate => mode == ProductTaxMode.custom ? rate! : 0;

  /// Value for `products.tax_exempt`.
  bool get storedTaxExempt => mode == ProductTaxMode.exempt;

  @override
  bool operator ==(Object other) =>
      other is ProductTaxChoice && other.mode == mode && other.rate == rate;

  @override
  int get hashCode => Object.hash(mode, rate);

  @override
  String toString() => 'ProductTaxChoice($mode, $rate)';

  static const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

  static String _normalize(String raw) {
    final buf = StringBuffer();
    for (final ch in raw.trim().split('')) {
      final idx = _arabicDigits.indexOf(ch);
      buf.write(idx >= 0 ? '$idx' : ch);
    }
    return buf
        .toString()
        .replaceAll('٫', '.')
        .replaceAll('،', '.')
        .replaceAll(',', '.');
  }

  /// Strict parse of a typed rate: digits with at most two decimals, else null.
  static double? parseRate(String raw) {
    final s = _normalize(raw);
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) return null;
    return double.tryParse(s);
  }

  /// Validates a custom rate. Returns an error message or `null` when valid.
  ///
  /// Besides 0–100 / ≤2 decimals the rate must be on the configured
  /// [TaxRatePolicy] ladder — the same ladder the server API and the Excel
  /// importer enforce, so a rate saved here is never rejected on a mirror.
  /// [legacyRate] (the item's stored off-ladder rate) stays savable so
  /// reopening an old item never forces a change.
  static String? validateRate(
    String raw, {
    double? legacyRate,
    List<double>? allowed,
  }) {
    final s = _normalize(raw);
    if (s.isEmpty) return tr('أدخل نسبة الضريبة');
    if (RegExp(r'^\d+\.\d{3,}$').hasMatch(s)) {
      return tr('نسبة الضريبة: خانتان عشريتان كحد أقصى');
    }
    final value = parseRate(s);
    if (value == null || value > 100) {
      return tr('نسبة الضريبة يجب أن تكون رقماً بين 0 و100');
    }
    if (value == 0) {
      return tr('لنسبة 0٪ اختر «معفى من الضريبة» أو ألغِ «تفعيل الضريبة»');
    }
    final isLegacy =
        legacyRate != null && (legacyRate - value).abs() < 1e-6;
    if (!isLegacy && !TaxRatePolicy.isAllowed(value, allowed: allowed)) {
      final ladder = (allowed ?? TaxRatePolicy.activeRates)
          .where((r) => r > 0)
          .map(_fmt)
          .join(', ');
      return tr('النسبة {rate}٪ غير مسموح بها. النسب المتاحة: {ladder}٪',
          {'rate': _fmt(value), 'ladder': ladder});
    }
    return null;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// Text for the rate field when loading a stored rate.
  static String formatRate(double v) => _fmt(v);
}
