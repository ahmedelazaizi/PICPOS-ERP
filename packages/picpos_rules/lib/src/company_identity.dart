/// Company identity on printed documents — the same rules as the desktop
/// `lib/domain/printing/company_identity.dart` and the sales-receipt header
/// of `lib/services/printing/thermal_receipt_generator.dart`:
/// - Arabic document: Arabic name is the main line, English name a secondary
///   line below (skipped when empty or identical).
/// - English document: English name is the main line when present.
/// - CR next to the tax number: «س.ت: …» / "CR: …"; empty → nothing.
/// Desktop integration of this package is a follow-up (ARCHITECTURE-I §14).
library;

/// U+200E LEFT-TO-RIGHT MARK.
const String kLrm = '\u200E';

/// Keeps Latin digits/dashes of a value in order inside Arabic text (desktop
/// `ltrIsolate`: LRM on both sides — LRI is not honoured by every renderer).
String ltrIsolate(String value) => value.isEmpty ? value : '$kLrm$value$kLrm';

bool _isEnglish(String locale) => locale == 'en';

String _clean(String? v) => (v ?? '').trim();

/// Main company name in the document language.
String companyMainName({required String nameAr, String? nameEn, String locale = 'ar'}) {
  final en = _clean(nameEn);
  if (_isEnglish(locale) && en.isNotEmpty) return en;
  return nameAr;
}

/// Secondary line — the English name under the Arabic one; `''` if not needed.
String companySecondaryName({required String nameAr, String? nameEn, String locale = 'ar'}) {
  final en = _clean(nameEn);
  if (_isEnglish(locale) || en.isEmpty) return '';
  if (en == nameAr.trim()) return '';
  return en;
}

/// «س.ت: 123» / "CR: 123" — `''` when there is no number.
String companyCrLine(String? crNumber, {String locale = 'ar'}) {
  final cr = _clean(crNumber);
  if (cr.isEmpty) return '';
  return '${_isEnglish(locale) ? 'CR' : 'س.ت'}: ${ltrIsolate(cr)}';
}

/// «الرقم الضريبي: …» / "Tax No.: …" — `''` when there is no number.
String companyTaxLine(String? taxId, {String locale = 'ar'}) {
  final tax = _clean(taxId);
  if (tax.isEmpty) return '';
  return '${_isEnglish(locale) ? 'Tax No.' : 'الرقم الضريبي'}: ${ltrIsolate(tax)}';
}

/// The identity block of a thermal receipt header, in print order: main
/// name, secondary name, address, phone, then one line with tax number and CR
/// joined by `  ·  ` (desktop `ThermalReceiptGenerator._buildHeader`: the CR
/// prints even without a tax number because each value carries its own label).
List<String> companyHeaderLines({
  required String nameAr,
  String? nameEn,
  String? address,
  String? phone,
  String? taxId,
  String? crNumber,
  String locale = 'ar',
}) {
  final tax = companyTaxLine(taxId, locale: locale);
  final cr = companyCrLine(crNumber, locale: locale);
  return [
    companyMainName(nameAr: nameAr, nameEn: nameEn, locale: locale),
    companySecondaryName(nameAr: nameAr, nameEn: nameEn, locale: locale),
    _clean(address),
    ltrIsolate(_clean(phone)),
    [if (tax.isNotEmpty) tax, if (cr.isNotEmpty) cr].join('  ·  '),
  ].where((l) => l.trim().isNotEmpty).toList();
}
