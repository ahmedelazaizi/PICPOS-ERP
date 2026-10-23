import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart';

/// Dialog for selecting product packaging unit (UOM) in POS
/// Only shown for products that have multiple units defined (e.g. carton, box, piece)
class UnitSelectionDialog extends StatelessWidget {
  final String productName;
  final List<ProductUnit> units;

  const UnitSelectionDialog({
    super.key,
    required this.productName,
    required this.units,
  });

  /// Shows the dialog and returns the selected ProductUnit, or null if cancelled/base unit
  static Future<ProductUnit?> show(
    BuildContext context, {
    required String productName,
    required List<ProductUnit> units,
  }) {
    return showDialog<ProductUnit>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: UnitSelectionDialog(
          productName: productName,
          units: units,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.package, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('اختر وحدة البيع'),
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              productName,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            ...units.map((unit) => _UnitCard(unit: unit)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('إلغاء'), style: GoogleFonts.cairo()),
        ),
      ],
    );
  }
}

class _UnitCard extends StatelessWidget {
  final ProductUnit unit;

  const _UnitCard({required this.unit});

  @override
  Widget build(BuildContext context) {
    final isBase = unit.isBaseUnit;

    return Card(
      elevation: isBase ? 0 : 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isBase ? AppColors.border : AppColors.primary.withValues(alpha: 0.3),
          width: isBase ? 1 : 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.pop(context, unit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                isBase ? PhosphorIconsBold.cube : PhosphorIconsBold.package,
                color: isBase ? AppColors.textMuted : AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.unitName,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (!isBase && unit.quantityInBase > 1)
                      Text(
                        tr('{p0} قطعة', {'p0': unit.quantityInBase.toStringAsFixed(0)}),
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (unit.salePrice > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unit.salePrice.toStringAsFixed(AppConstants.decimalPlaces),
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.success,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
