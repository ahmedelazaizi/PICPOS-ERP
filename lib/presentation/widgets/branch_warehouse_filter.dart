import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../data/providers/manufacturing_providers.dart';
import '../../data/providers/inventory_providers.dart';
import '../../data/providers/repository_providers.dart';

/// Reusable region + branch + warehouse filter dropdowns for report screens.
/// When a region is selected, the branch dropdown only shows branches in that region.
/// When a branch is selected, the warehouse dropdown only shows
/// warehouses belonging to that branch.
class BranchWarehouseFilterBar extends ConsumerWidget {
  final int? selectedRegionId;
  final int? selectedBranchId;
  final int? selectedWarehouseId;
  final void Function(int?)? onRegionChanged;
  final ValueChanged<int?> onBranchChanged;
  final ValueChanged<int?> onWarehouseChanged;

  const BranchWarehouseFilterBar({
    super.key,
    this.selectedRegionId,
    this.onRegionChanged,
    required this.selectedBranchId,
    required this.selectedWarehouseId,
    required this.onBranchChanged,
    required this.onWarehouseChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regionsAsync = ref.watch(allRegionsProvider);
    final allBranchesAsync = ref.watch(branchListProvider);
    // When a region is selected, use the region-scoped branch list; otherwise all branches
    final branchesAsync = selectedRegionId != null
        ? ref.watch(regionBranchesProvider(selectedRegionId!))
        : allBranchesAsync;
    final warehousesAsync = ref.watch(warehouseListProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ─── Region Filter ───
        SizedBox(
          width: 160,
          child: regionsAsync.when(
            data: (regions) {
              if (regions.isEmpty) return const SizedBox.shrink();
              return DropdownButtonFormField<int?>(
                initialValue: regions.any((r) => r.id == selectedRegionId) ? selectedRegionId : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'المنطقة',
                  isDense: true,
                  prefixIcon: Icon(PhosphorIconsBold.mapPin, size: 16),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل المناطق')),
                  ...regions.map((r) => DropdownMenuItem<int?>(
                        value: r.id,
                        child: Text(r.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) {
                  if (onRegionChanged != null) onRegionChanged!(v);
                  // Reset branch and warehouse when region changes
                  onBranchChanged(null);
                  onWarehouseChanged(null);
                },
              );
            },
            loading: () => const SizedBox(width: 160, child: LinearProgressIndicator()),
            error: (_, e) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 12),
        // ─── Branch Filter ───
        SizedBox(
          width: 160,
          child: branchesAsync.when(
            data: (branches) {
              if (branches.isEmpty) return const SizedBox.shrink();
              // Reset value if it's not in the filtered list
              final effectiveBranch = branches.any((b) => b.id == selectedBranchId) ? selectedBranchId : null;
              return DropdownButtonFormField<int?>(
                initialValue: effectiveBranch,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'الفرع',
                  isDense: true,
                  prefixIcon: Icon(PhosphorIconsBold.buildings, size: 16),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل الفروع')),
                  ...branches.map((b) => DropdownMenuItem<int?>(
                        value: b.id,
                        child: Text(b.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) {
                  onBranchChanged(v);
                  // Reset warehouse when branch changes
                  onWarehouseChanged(null);
                },
              );
            },
            loading: () => const SizedBox(width: 160, child: LinearProgressIndicator()),
            error: (_, e) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 12),
        // ─── Warehouse Filter (cascading) ───
        SizedBox(
          width: 160,
          child: warehousesAsync.when(
            data: (allWarehouses) {
              // Filter warehouses by selected branch
              final warehouses = selectedBranchId != null
                  ? allWarehouses.where((w) => w.branchId == selectedBranchId).toList()
                  : allWarehouses;
              // Reset value if it's not in the filtered list
              final effectiveValue = warehouses.any((w) => w.id == selectedWarehouseId)
                  ? selectedWarehouseId
                  : null;
              return DropdownButtonFormField<int?>(
                initialValue: effectiveValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'المخزن',
                  isDense: true,
                  prefixIcon: Icon(PhosphorIconsBold.warehouse, size: 16),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('كل المخازن')),
                  ...warehouses.map((w) => DropdownMenuItem<int?>(
                        value: w.id,
                        child: Text(w.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: onWarehouseChanged,
              );
            },
            loading: () => const SizedBox(width: 160, child: LinearProgressIndicator()),
            error: (_, e) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  /// Helper: given a selected branch, returns all warehouse IDs for that branch.
  /// Use this for filtering records by branch (warehouseId IN branchWarehouseIds).
  static Future<Set<int>> getBranchWarehouseIds(WidgetRef ref, int branchId) async {
    final warehouses = await ref.read(warehouseListProvider.future);
    return warehouses.where((w) => w.branchId == branchId).map((w) => w.id).toSet();
  }

  /// Feature 017 — Helper: given a selected region, returns every warehouse
  /// id that belongs to a branch in that region. Lets screens whose DAO
  /// methods only accept `warehouseIds` (no `regionId` parameter) honour
  /// the region filter without changing the DAO signature.
  static Future<Set<int>> getRegionWarehouseIds(WidgetRef ref, int regionId) async {
    final ids = await ref.read(regionRepositoryProvider).getWarehouseIdsForRegion(regionId);
    return ids.toSet();
  }
}
