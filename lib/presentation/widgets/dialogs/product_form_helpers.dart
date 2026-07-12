// ═══════════════════════════════════════════════════════════════════════════
// PRODUCT FORM HELPERS — ISS-13 Shared UI Building Blocks
// ═══════════════════════════════════════════════════════════════════════════
//
// Shared widget helpers used by both AddProductDialog and ProductEditDialog.
// Extracted to eliminate code duplication (ISS-13: Unify Product Dialogs).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Shared building blocks for product add/edit forms.
///
/// This class provides static widget builders used by both
/// [AddProductDialog] and [ProductEditDialog] to ensure consistent
/// styling and eliminate code duplication.
class ProductFormHelpers {
  ProductFormHelpers._();

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
