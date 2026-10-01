import 'package:flutter/material.dart';
import 'package:ural_erp/core/i18n/tr.dart';

import '../../../core/tax/product_tax_choice.dart';

/// البند 5 (المالك) — حالة ضريبة الصنف في نموذجَي الإضافة والتعديل.
///
/// Replaces the tax-rate dropdown with «معفى من الضريبة» + «تفعيل الضريبة» /
/// «نسبة الضريبة %». Exempt and a custom rate are mutually exclusive; with
/// neither ticked the item uses the company default. The stored values are
/// the dropdown's — see [ProductTaxChoice] for the representation.
class ProductTaxController extends ChangeNotifier {
  ProductTaxController([
    ProductTaxChoice initial = const ProductTaxChoice.companyDefault(),
  ]) {
    load(initial);
  }

  final TextEditingController rateController = TextEditingController();

  bool _exempt = false;
  bool _customEnabled = false;

  /// A stored rate that is off the configured ladder (legacy data). It stays
  /// savable so reopening an old item never forces a change.
  double? _legacyRate;

  bool get exempt => _exempt;
  bool get customEnabled => _customEnabled;

  /// Maps stored values (`products.tax_rate` + `products.tax_exempt`) onto
  /// the controls.
  void loadStored({required double taxRate, required bool taxExempt}) =>
      load(ProductTaxChoice.fromStored(taxRate: taxRate, taxExempt: taxExempt));

  void load(ProductTaxChoice choice) {
    _exempt = choice.mode == ProductTaxMode.exempt;
    _customEnabled = choice.mode == ProductTaxMode.custom;
    _legacyRate = choice.rate;
    rateController.text =
        choice.rate != null ? ProductTaxChoice.formatRate(choice.rate!) : '';
    notifyListeners();
  }

  void setExempt(bool value) {
    _exempt = value;
    if (value) _customEnabled = false;
    notifyListeners();
  }

  void setCustomEnabled(bool value) {
    _customEnabled = value;
    if (value) _exempt = false;
    notifyListeners();
  }

  void onRateChanged() => notifyListeners();

  /// Error for the rate field, or `null` (always `null` while disabled).
  String? get rateError => _customEnabled
      ? ProductTaxChoice.validateRate(rateController.text,
          legacyRate: _legacyRate)
      : null;

  /// The validated choice, or `null` while the custom rate is invalid.
  ProductTaxChoice? get choice {
    if (_exempt) return const ProductTaxChoice.exempt();
    if (!_customEnabled) return const ProductTaxChoice.companyDefault();
    if (rateError != null) return null;
    return ProductTaxChoice.custom(
        ProductTaxChoice.parseRate(rateController.text)!);
  }

  @override
  void dispose() {
    rateController.dispose();
    super.dispose();
  }
}

/// The tax controls. Theme colors only; direction follows the ambient
/// [Directionality] (the dialogs are RTL, English UI is LTR).
class ProductTaxFields extends StatelessWidget {
  const ProductTaxFields({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final ProductTaxController controller;
  final bool enabled;

  static const exemptKey = ValueKey('product_tax_exempt');
  static const enableKey = ValueKey('product_tax_enable');
  static const rateKey = ValueKey('product_tax_rate');

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final rateEnabled = enabled && controller.customEnabled;
        return Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _check(
              key: exemptKey,
              value: controller.exempt,
              label: tr('معفى من الضريبة'),
              onChanged: controller.setExempt,
            ),
            _check(
              key: enableKey,
              value: controller.customEnabled,
              label: tr('تفعيل الضريبة'),
              onChanged: controller.setCustomEnabled,
            ),
            SizedBox(
              width: 170,
              child: TextField(
                key: rateKey,
                controller: controller.rateController,
                enabled: rateEnabled,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 13),
                onChanged: (_) => controller.onRateChanged(),
                decoration: InputDecoration(
                  labelText: tr('نسبة الضريبة %'),
                  labelStyle: const TextStyle(fontSize: 12),
                  hintText: controller.customEnabled
                      ? null
                      : tr('النسبة الافتراضية للشركة'),
                  hintStyle: const TextStyle(fontSize: 11),
                  errorText: controller.rateError,
                  errorMaxLines: 3,
                  prefixIcon: const Icon(Icons.percent, size: 16),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _check({
    required Key key,
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            key: key,
            value: value,
            onChanged: enabled ? (v) => onChanged(v ?? false) : null,
          ),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
