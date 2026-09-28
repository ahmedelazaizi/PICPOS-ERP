import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../../data/providers/inventory_providers.dart';
import '../../../../domain/entities/product_entity.dart';

class PosLowStockIndicator extends ConsumerWidget {
  const PosLowStockIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStockAsync = ref.watch(lowStockProductsProvider);
    
    return lowStockAsync.when(
      data: (lowStockItems) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: lowStockItems.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Container(
                    key: const ValueKey('pos_low_stock_indicator'),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange, width: 2),
                    ),
                    child: TextButton.icon(
                      onPressed: () =>
                          _showLowStockDialog(context, lowStockItems),
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            PhosphorIconsBold.warning,
                            color: Colors.orange,
                            size: 18,
                          ),
                          PositionedDirectional(
                            start: -10,
                            top: -10,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${lowStockItems.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      label: const Text(
                        'تنبيه مخزون',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.orange.withValues(alpha: 0.15),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        ),
                      ),
                    ),
                  ),
          ),
      error: (e, _) => const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
    );
  }

  void _showLowStockDialog(BuildContext context, List<ProductEntity> items) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: Colors.orange),
              const SizedBox(width: 8),
              Text('أصناف وصلت الحد الأدنى (${items.length})'),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final product = items[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    PhosphorIconsBold.package,
                    color: Colors.orange,
                  ),
                  title: Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('الكود: ${product.code}'),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'المتبقي: ${product.currentStock.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'الحد الأدنى: ${product.minStock.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }
}
