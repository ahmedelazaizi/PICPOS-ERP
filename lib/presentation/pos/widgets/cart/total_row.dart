import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';

/// Total row widget with auto-scaling fonts
class TotalRow extends StatelessWidget {
  final String label;
  final double value;
  final Color? valueColor;
  final bool isTotal;
  final String? suffix;
  final double scaleFactor;
  final Widget? trailing;

  const TotalRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.isTotal = false,
    this.scaleFactor = 1.0,
    this.suffix,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final labelSize = (isTotal ? 14.0 : 12.0) * scaleFactor;
    final valueSize = (isTotal ? 16.0 : 13.0) * scaleFactor;

    return Container(
      margin: EdgeInsets.symmetric(vertical: 2 * scaleFactor),
      padding: EdgeInsets.symmetric(
        horizontal: 8 * scaleFactor,
        vertical: 6 * scaleFactor,
      ),
      decoration: BoxDecoration(
        color: isTotal
            ? AppColors.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8 * scaleFactor),
        border: isTotal
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.2))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: labelSize,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  color: isTotal ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
              if (suffix != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    suffix!,
                    style: TextStyle(
                      fontSize: labelSize * 0.9,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 6 * scaleFactor,
              vertical: 2 * scaleFactor,
            ),
            decoration: BoxDecoration(
              color: isTotal
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(4 * scaleFactor),
              border: Border.all(
                color:
                    (valueColor ??
                            (isTotal ? AppColors.primary : AppColors.border))
                        .withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              '${value.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: isTotal ? FontWeight.w900 : FontWeight.bold,
                color:
                    valueColor ??
                    (isTotal ? AppColors.primary : AppColors.textPrimary),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
