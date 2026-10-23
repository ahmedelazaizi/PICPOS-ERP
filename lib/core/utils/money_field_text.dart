import 'package:picpos_erp/core/constants/app_constants.dart';

/// Text for a price/cost/margin input populated from a stored `double`.
///
/// Rounds to [decimals] (default: the company currency's decimal places) and
/// strips trailing zeros, so binary-float noise such as `0.27999999999999997`
/// shows as `0.28`. Display only: the stored value and money rounding are
/// untouched.
String moneyFieldText(double value, {int? decimals}) {
  if (value.isNaN || value.isInfinite) return '0';
  final fixed = value.toStringAsFixed(decimals ?? AppConstants.decimalPlaces);
  final trimmed = fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
      : fixed;
  return (trimmed.isEmpty || trimmed == '-0') ? '0' : trimmed;
}

/// `price.fieldText` — same as `toString()` for call sites, minus float noise.
extension MoneyFieldTextX on double {
  String get fieldText => moneyFieldText(this);
}
