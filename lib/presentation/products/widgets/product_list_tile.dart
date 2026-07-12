import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart';
import '../../../../../../core/constants/app_constants.dart';

/// Product list tile widget
///
/// Displays a single product with stock status, price, and action buttons
class ProductListTile extends StatelessWidget {
  final Product product;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const ProductListTile({
    super.key,
    required this.product,
    this.onEdit,
    this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLowStock =
        product.trackInventory &&
        product.currentStock <= product.minStock &&
        product.currentStock > 0;
    final isOutOfStock = product.trackInventory && product.currentStock <= 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onTap ?? onEdit,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Product image/icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
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
                        color: AppColors.primary,
                      ),
              ),

              const SizedBox(width: 12),

              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          product.code,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (product.isSoldByWeight) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            PhosphorIconsBold.scales,
                            size: 14,
                            color: AppColors.info,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Stock badge
              if (product.trackInventory)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isOutOfStock
                        ? AppColors.error.withValues(alpha: 0.1)
                        : isLowStock
                        ? AppColors.warning.withValues(alpha: 0.1)
                        : AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    product.currentStock.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isOutOfStock
                          ? AppColors.error
                          : isLowStock
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                  ),
                ),

              const SizedBox(width: 12),

              // Price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${product.salePrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '?????: ${product.costPrice.toStringAsFixed(AppConstants.decimalPlaces)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 8),

              // Actions
              PopupMenuButton<String>(
                icon: const Icon(PhosphorIconsBold.dotsThree),
                onSelected: (value) {
                  if (value == 'edit') onEdit?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(PhosphorIconsBold.pencilSimple, size: 18),
                        SizedBox(width: 8),
                        Text('?????'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          PhosphorIconsBold.trash,
                          size: 18,
                          color: AppColors.error,
                        ),
                        SizedBox(width: 8),
                        Text('???', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
