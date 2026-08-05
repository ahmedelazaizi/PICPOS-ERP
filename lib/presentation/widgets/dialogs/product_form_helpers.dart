// ═══════════════════════════════════════════════════════════════════════════
// PRODUCT FORM HELPERS — ISS-13 Shared UI Building Blocks
// ═══════════════════════════════════════════════════════════════════════════
//
// Shared widget helpers used by both AddProductDialog and ProductEditDialog.
// Extracted to eliminate code duplication (ISS-13: Unify Product Dialogs).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../core/tax/tax_rate_policy.dart';
import '../../../core/theme/app_colors.dart';

/// Shared building blocks for product add/edit forms.
///
/// This class provides static widget builders used by both
/// [AddProductDialog] and [ProductEditDialog] to ensure consistent
/// styling and eliminate code duplication.
class ProductFormHelpers {
  ProductFormHelpers._();

  /// سعر بيع وحدة التعبئة: المُدخَل يفوز، وفاضي/صفر/غير صالح = اشتق من
  /// `سعر الصنف × المعامل`.
  ///
  /// قبل كده كان الاشتقاق هو **الوحيد** الممكن: النموذجان بيكتبوا
  /// `salePrice * factor` دايماً، وصفّ الوحدة مكانش فيه حقل سعر أصلاً. يعني
  /// شوال السكر مجبَر على سعر الكيلو × ٥٠ — وده مش الواقع التجاري، والجملة
  /// دايماً أرخص للوحدة. العمود `product_units.sale_price` كان موجوداً
  /// ونقطة البيع بتحترمه (‏cart_item_tile.dart)، فالنقص كان في الواجهة وحدها.
  ///
  /// مستخرجة هنا لأن القاعدة بتتكرّر في **تلات** مواضع (الحفظ في نموذج
  /// التعديل، والحفظ في نموذج الإضافة، وحِمل السيرفر في نموذج الإضافة). لو
  /// اختلف أي واحد منهم عن التاني، السيرفر يخزّن سعراً والعميل يخزّن غيره
  /// وأول DeltaPull يدهس سعر المستخدم.
  static double resolveUnitSalePrice({
    required double? typedPrice,
    required double baseSalePrice,
    required double factor,
  }) {
    if (typedPrice != null && typedPrice > 0) return typedPrice;
    return baseSalePrice * factor;
  }

  /// Build a section header with icon and colored text.
  static Widget buildSectionHeader(
    String title,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// Build a compact text field with optional icon prefix.
  static Widget buildCompactTextField(
    TextEditingController controller,
    String label, {
    IconData? icon,
    bool isNumber = false,
    ValueChanged<String>? onChanged,
    bool enabled = true,
  }) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 13),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          prefixIcon: icon != null ? Icon(icon, size: 16) : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
      ),
    );
  }

  /// البند 4 (متطلبات العميل 2026-07-25) — حقل نسبة الضريبة كقائمة اختيار من
  /// السلّم القانوني، بدل حقل نصّي حرّ كان يقبل 37.5 أو 999 أو ‑16.
  ///
  /// Backed by the same [TaxRatePolicy] the server and the Excel importer
  /// enforce, so the three ingresses can't drift apart. A product whose stored
  /// rate predates the policy (legacy data) keeps its value as an extra,
  /// clearly-marked entry so opening the dialog can't silently rewrite it —
  /// the operator has to choose deliberately.
  static Widget buildTaxRateDropdown(
    TextEditingController controller, {
    String label = 'نسبة الضريبة %',
    IconData? icon,
    bool enabled = true,
    List<double>? allowedRates,
    ValueChanged<double>? onChanged,
  }) {
    final ladder = List<double>.from(allowedRates ?? TaxRatePolicy.defaultAllowedRates);
    final current = double.tryParse(controller.text.trim()) ?? 0;
    if (!TaxRatePolicy.isAllowed(current, allowed: ladder)) {
      ladder.add(current);
      ladder.sort();
    }

    String labelFor(double r) {
      if (r == 0) return 'معفي / صفر ٪';
      final txt = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
      return TaxRatePolicy.isAllowed(r, allowed: allowedRates ?? TaxRatePolicy.defaultAllowedRates)
          ? '$txt ٪'
          : '$txt ٪ (غير قياسية)';
    }

    return SizedBox(
      height: 48,
      child: DropdownButtonFormField<double>(
        initialValue: ladder.firstWhere(
          (r) => (r - current).abs() < 1e-6,
          orElse: () => 0,
        ),
        isDense: true,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          prefixIcon: icon != null ? Icon(icon, size: 16) : null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
        items: [
          for (final r in ladder)
            DropdownMenuItem<double>(
              value: r,
              child: Text(labelFor(r), style: const TextStyle(fontSize: 13)),
            ),
        ],
        onChanged: enabled
            ? (v) {
                if (v == null) return;
                controller.text =
                    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
                onChanged?.call(v);
              }
            : null,
      ),
    );
  }

  /// Build a mini text field for numeric inputs (smaller than compact).
  static Widget buildMiniTextField(
    TextEditingController controller,
    String label, {
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 12),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          isDense: true,
        ),
      ),
    );
  }

  /// Build a standard product info card with header and content.
  static Widget buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSectionHeader(title, icon, color),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  /// Build a save button row with cancel and save actions.
  static Widget buildActionButtons({
    required VoidCallback onCancel,
    required VoidCallback onSave,
    required bool isEditing,
    bool isLoading = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: isLoading ? null : onCancel,
          child: const Text('إلغاء'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: isLoading ? null : onSave,
          icon: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(isEditing
                  ? Icons.save
                  : Icons.add_circle_outline),
          label: Text(isEditing ? 'حفظ التعديلات' : 'إضافة الصنف'),
          style: ElevatedButton.styleFrom(
            backgroundColor: isEditing ? AppColors.warning : AppColors.success,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
