import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';

/// Result from Edit Cart Item Dialog
class EditCartItemResult {
  final double? newPrice;
  final String? note;
  final ProductUnit? selectedUnit;

  EditCartItemResult({this.newPrice, this.note, this.selectedUnit});
}

/// Dialog for editing a cart item (price and notes)
class EditCartItemDialog extends StatefulWidget {
  final Product product;
  final double currentPrice;
  final String? currentNote;
  final List<ProductUnit> availableUnits;
  final int? currentUnitId;
  final void Function(double? newPrice, String? note, ProductUnit? selectedUnit) onSave;
  final VoidCallback onDelete;

  const EditCartItemDialog({
    super.key,
    required this.product,
    required this.currentPrice,
    this.currentNote,
    this.availableUnits = const [],
    this.currentUnitId,
    required this.onSave,
    required this.onDelete,
  });

  /// Show the edit cart item dialog
  static Future<void> show({
    required BuildContext context,
    required Product product,
    required double currentPrice,
    String? currentNote,
    List<ProductUnit> availableUnits = const [],
    int? currentUnitId,
    required void Function(double? newPrice, String? note, ProductUnit? selectedUnit) onSave,
    required VoidCallback onDelete,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: EditCartItemDialog(
          product: product,
          currentPrice: currentPrice,
          currentNote: currentNote,
          availableUnits: availableUnits,
          currentUnitId: currentUnitId,
          onSave: (price, note, unit) {
            Navigator.pop(ctx);
            onSave(price, note, unit);
          },
          onDelete: () {
            Navigator.pop(ctx);
            onDelete();
          },
        ),
      ),
    );
  }

  @override
  State<EditCartItemDialog> createState() => _EditCartItemDialogState();
}

class _EditCartItemDialogState extends State<EditCartItemDialog> {
  late final TextEditingController _priceController;
  late final TextEditingController _noteController;
  ProductUnit? _selectedUnit;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.currentPrice.toStringAsFixed(AppConstants.decimalPlaces),
    );
    _noteController = TextEditingController(text: widget.currentNote ?? '');
    // Find current unit or null
    if (widget.currentUnitId != null && widget.availableUnits.isNotEmpty) {
      _selectedUnit = widget.availableUnits
          .where((u) => u.id == widget.currentUnitId)
          .firstOrNull;
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.pencilSimple, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Unit selector (only if product has multiple units)
          if (widget.availableUnits.length > 1) ...[
            DropdownButtonFormField<int>(
              initialValue: _selectedUnit?.id,
              decoration:  InputDecoration(
                labelText: tr('الوحدة'),
                prefixIcon: const Icon(PhosphorIconsBold.cube),
              ),
              items: widget.availableUnits.map((u) {
                return DropdownMenuItem<int>(
                  value: u.id,
                  child: Text(
                    tr('{p0} ({p1} قطعة) — {p2} {p3}', {'p0': u.unitName, 'p1': u.quantityInBase.toStringAsFixed(0), 'p2': u.salePrice.toStringAsFixed(AppConstants.decimalPlaces), 'p3': AppConstants.currencySymbolEn}),
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }).toList(),
              onChanged: (unitId) {
                if (unitId == null) return;
                final unit = widget.availableUnits.firstWhere((u) => u.id == unitId);
                setState(() {
                  _selectedUnit = unit;
                  _priceController.text = unit.salePrice.toStringAsFixed(AppConstants.decimalPlaces);
                });
              },
            ),
            const SizedBox(height: 16),
          ],
          // Custom price
          TextField(
            controller: _priceController,
            decoration: InputDecoration(
              labelText: tr('السعر'),
              prefixIcon: const Icon(PhosphorIconsBold.money),
              suffixText: AppConstants.currencySymbolEn,
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          // Note
          TextField(
            controller: _noteController,
            decoration:  InputDecoration(
              labelText: tr('ملاحظة'),
              prefixIcon: const Icon(PhosphorIconsBold.notepad),
              hintText: tr('مثال: بدون بصل...'),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr('إلغاء')),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          onPressed: widget.onDelete,
          child:  Text(tr('حذف')),
        ),
        FilledButton(
          onPressed: () {
            final newPrice = double.tryParse(_priceController.text);
            final note = _noteController.text.isEmpty
                ? null
                : _noteController.text;
            widget.onSave(newPrice, note, _selectedUnit);
          },
          child:  Text(tr('حفظ')),
        ),
      ],
    );
  }
}
