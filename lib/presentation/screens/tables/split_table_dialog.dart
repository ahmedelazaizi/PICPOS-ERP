import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database_barrel.dart';
import '../../../domain/repositories/restaurant_repository.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../../data/providers/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Specialized dialog for splitting table orders by quantities
class SplitTableDialog extends StatefulWidget {
  final RestaurantTable sourceTable;
  final List<RestaurantTable> targetTables;
  final IRestaurantRepository restaurantRepo;

  const SplitTableDialog({
    super.key,
    required this.sourceTable,
    required this.targetTables,
    required this.restaurantRepo,
  });

  @override
  State<SplitTableDialog> createState() => _SplitTableDialogState();
}

class _SplitTableDialogState extends State<SplitTableDialog> {
  RestaurantTable? _selectedTarget;
  List<TableOrderItem> _orderItems = [];
  final Map<int, double> _quantitiesToMove = {}; // itemId -> qty
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOrderItems();
  }

  Future<void> _loadOrderItems() async {
    final order =
        await widget.restaurantRepo.getActiveOrderForTable(widget.sourceTable.id);
    if (order != null && mounted) {
      final items = await widget.restaurantRepo.getTableOrderItems(order.id);
      setState(() {
        _orderItems = items;
        // Default split quantity is 0
        for (final item in items) {
          _quantitiesToMove[item.id] = 0;
        }
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.columns, color: AppColors.info),
            const SizedBox(width: 8),
            Text('تقسيم طلب ${widget.sourceTable.name}'),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 500,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'اختر الأصناف والكميات المراد نقلها:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 3,
                      child: ListView.separated(
                        itemCount: _orderItems.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (ctx, idx) {
                          final item = _orderItems[idx];
                          final currentSplitQty =
                              _quantitiesToMove[item.id] ?? 0;

                          return Consumer(
                            builder: (ctx, ref, _) {
                              return FutureBuilder<ProductEntity?>(
                                future: ref
                                    .read(productRepositoryProvider)
                                    .getProductById(item.productId),
                                builder: (ctx, snap) {
                                  final product = snap.data;
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      product?.name ?? 'صنف #${item.productId}',
                                    ),
                                    subtitle: Text(
                                      'الكل: ${item.quantity.toStringAsFixed(0)} وحدة',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            PhosphorIconsBold.minus,
                                            size: 16,
                                          ),
                                          onPressed: currentSplitQty > 0
                                              ? () => setState(
                                                    () => _quantitiesToMove[
                                                        item.id] = currentSplitQty - 1,
                                                  )
                                              : null,
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            currentSplitQty.toStringAsFixed(0),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            PhosphorIconsBold.plus,
                                            size: 16,
                                          ),
                                          onPressed: currentSplitQty < item.quantity
                                              ? () => setState(
                                                    () => _quantitiesToMove[
                                                        item.id] = currentSplitQty + 1,
                                                  )
                                              : null,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    const Text(
                      'اختر الطاولة الهدف (نقل إلى):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 2,
                      child: ListView.separated(
                        itemCount: widget.targetTables.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, idx) {
                          final table = widget.targetTables[idx];
                          final isSelected = _selectedTarget?.id == table.id;
                          return ListTile(
                            leading: Icon(
                              PhosphorIconsBold.circlesThree,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.success,
                            ),
                            title: Text(table.name),
                            selected: isSelected,
                            selectedTileColor: AppColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            onTap: () => setState(() => _selectedTarget = table),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: _selectedTarget == null || !_hasAnythingToMove()
                ? null
                : () => Navigator.pop(context, {
                      'target': _selectedTarget,
                      'itemQuantities': _getFinalQuantities(),
                    }),
            icon: const Icon(PhosphorIconsBold.arrowRight),
            label: const Text('إتمام التقسيم'),
          ),
        ],
      ),
    );
  }

  bool _hasAnythingToMove() {
    return _quantitiesToMove.values.any((qty) => qty > 0);
  }

  Map<int, double> _getFinalQuantities() {
    final result = <int, double>{};
    _quantitiesToMove.forEach((id, qty) {
      if (qty > 0) result[id] = qty;
    });
    return result;
  }
}
