import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart';
import '../../../../../../core/constants/app_constants.dart';

/// Product card widget for grid display
class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image or Icon
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: product.imageData != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            product.imageData!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(
                          PhosphorIconsBold.package,
                          size: 32,
                          color: AppColors.primary,
                        ),
                ),
              ),
              const SizedBox(height: 8),

              // Name
              Text(
                product.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // Code
              Text(
                product.code,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const Spacer(),

              // Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${product.salePrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // Stock indicator
                  _buildStockIndicator(),
                ],
              ),

              // Action buttons
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onEdit != null)
                      IconButton(
                        icon: const Icon(PhosphorIconsBold.pencil, size: 18),
                        color: AppColors.primary,
                        onPressed: onEdit,
                        visualDensity: VisualDensity.compact,
                      ),
                    if (onDelete != null)
                      IconButton(
                        icon: const Icon(PhosphorIconsBold.trash, size: 18),
                        color: AppColors.error,
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockIndicator() {
    final isLowStock = product.currentStock <= product.minStock;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLowStock
            ? AppColors.error.withValues(alpha: 0.1)
            : AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        product.currentStock.toStringAsFixed(0),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isLowStock ? AppColors.error : AppColors.success,
        ),
      ),
    );
  }
}
