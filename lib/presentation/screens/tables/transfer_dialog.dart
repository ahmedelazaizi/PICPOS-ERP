import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database_barrel.dart';
import '../../../domain/repositories/restaurant_repository.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../../data/providers/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dialog for transferring orders between tables
/// Supports both full transfer and partial (selected items) transfer
class TransferDialog extends StatefulWidget {
  final RestaurantTable sourceTable;
  final List<RestaurantTable> availableTables;
  final IRestaurantRepository restaurantRepo;

  const TransferDialog({
    super.key,
    required this.sourceTable,
    required this.availableTables,
    required this.restaurantRepo,
  });

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  RestaurantTable? _selectedTarget;
  List<TableOrderItem> _orderItems = [];
  Set<int> _selectedItemIds = {};
  bool _transferAll = true;
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
        _selectedItemIds = items.map((e) => e.id).toSet();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.arrowsLeftRight, color: AppColors.info),
          const SizedBox(width: 8),
          Text(tr('نقل من {p0}', {'p0': widget.sourceTable.name})),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 450,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Transfer mode toggle
                  SwitchListTile(
                    title:  Text(tr('نقل كل الأصناف')),
                    subtitle: Text(
                      _transferAll
                          ? tr('سيتم نقل جميع الأصناف')
                          : tr('اختر الأصناف للنقل'),
                    ),
                    value: _transferAll,
                    onChanged: (val) => setState(() {
                      _transferAll = val;
                      if (val) {
                        _selectedItemIds = _orderItems.map((e) => e.id).toSet();
                      }
                    }),
                    activeTrackColor: AppColors.primary,
                  ),
                  const Divider(),

                  // Partial order item selection
                  if (!_transferAll) ...[
                     Text(
                      tr('اختر الأصناف للنقل:'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 2,
                      child: ListView.builder(
                        itemCount: _orderItems.length,
                        itemBuilder: (ctx, idx) {
                          final item = _orderItems[idx];
                          return Consumer(
                            builder: (ctx, ref, _) {
                              return FutureBuilder<ProductEntity?>(
                                future: ref
                                    .read(productRepositoryProvider)
                                    .getProductById(item.productId),
                                builder: (ctx, snap) {
                                  final product = snap.data;
                                  return CheckboxListTile(
                                    dense: true,
                                    title: Text(
                                      product?.name ?? tr('صنف #{p0}', {'p0': item.productId}),
                                    ),
                                    subtitle: Text(
                                      '${item.quantity.toStringAsFixed(0)} × ${item.unitPrice.toStringAsFixed(2)}',
                                    ),
                                    value: _selectedItemIds.contains(item.id),
                                    onChanged: (val) => setState(() {
                                      if (val == true) {
                                        _selectedItemIds.add(item.id);
                                      } else {
                                        _selectedItemIds.remove(item.id);
                                      }
                                    }),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(),
                  ],

                  // Target table selection
                   Text(
                    tr('اختر الطاولة الهدف:'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    flex: _transferAll ? 3 : 2,
                    child: ListView.separated(
                      itemCount: widget.availableTables.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final table = widget.availableTables[idx];
                        final isSelected = _selectedTarget?.id == table.id;
                        return ListTile(
                          leading: Icon(
                            PhosphorIconsBold.circlesThree,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.success,
                          ),
                          title: Text(table.name),
                          subtitle: Text(tr('السعة: {p0} أشخاص', {'p0': table.capacity})),
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
          child:  Text(tr('إلغاء')),
        ),
        ElevatedButton.icon(
          onPressed: _selectedTarget == null || _selectedItemIds.isEmpty
              ? null
              : () => Navigator.pop(context, {
                  'target': _selectedTarget,
                  'itemIds': _selectedItemIds.toList(),
                  'transferAll': _transferAll,
                }),
          icon: const Icon(PhosphorIconsBold.arrowRight),
          label: Text(
            _transferAll ? tr('نقل الكل') : tr('نقل {p0} صنف', {'p0': _selectedItemIds.length}),
          ),
        ),
      ],
    );
  }
}
