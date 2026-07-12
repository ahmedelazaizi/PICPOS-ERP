import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../data/providers/providers.dart';

/// Reusable warehouse dropdown for invoices and inventory screens.
/// Shows all active warehouses and allows selection.
class WarehouseDropdown extends ConsumerWidget {
  final int? selectedWarehouseId;
  final ValueChanged<int?> onChanged;
  final String? filterType; // null = show all, 'raw_materials', 'finished_goods', etc.
  final bool showLabel;

  const WarehouseDropdown({
    super.key,
    this.selectedWarehouseId,
    required this.onChanged,
    this.filterType,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(allWarehousesProvider);

    return warehousesAsync.when(
      data: (warehouses) {
        final filtered = filterType != null
            ? warehouses.where((w) => w.type == filterType).toList()
            : warehouses;

        if (filtered.isEmpty) {
          return const SizedBox.shrink();
        }

        // Auto-select first if none selected
        final effectiveId = selectedWarehouseId ??
            filtered.firstWhere((w) => w.isDefault, orElse: () => filtered.first).id;

        return DropdownButtonFormField<int>(
          initialValue: filtered.any((w) => w.id == effectiveId) ? effectiveId : null,
          decoration: InputDecoration(
            labelText: showLabel ? 'المخزن' : null,
            prefixIcon: const Icon(PhosphorIconsBold.warehouse, size: 20),
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: filtered.map((w) {
            final typeLabel = _warehouseTypeLabel(w.type);
            return DropdownMenuItem<int>(
              value: w.id,
              child: Text(
                typeLabel.isNotEmpty ? '${w.name} ($typeLabel)' : w.name,
                style: const TextStyle(fontSize: 13),
              ),
            );
          }).toList(),
          onChanged: (val) => onChanged(val),
        );
      },
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, s) => const SizedBox.shrink(),
    );
  }

  String _warehouseTypeLabel(String type) {
    switch (type) {
      case 'raw_materials':
        return 'خامات';
      case 'finished_goods':
        return 'منتج تام';
      case 'retail':
        return 'بيع';
      default:
        return '';
    }
  }
}
