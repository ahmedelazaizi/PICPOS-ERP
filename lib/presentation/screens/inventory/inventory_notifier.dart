import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/providers/inventory_providers.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../core/utils/uuid_v7.dart';

class InventoryState {
  final bool showLowStockOnly;
  final int? selectedCategoryId;
  final String searchQuery;
  final int? selectedMovementProductId;
  final int? selectedWarehouseId;

  InventoryState({
    this.showLowStockOnly = false,
    this.selectedCategoryId,
    this.searchQuery = '',
    this.selectedMovementProductId,
    this.selectedWarehouseId,
  });

  InventoryState copyWith({
    bool? showLowStockOnly,
    int? selectedCategoryId,
    bool clearCategory = false,
    String? searchQuery,
    int? selectedMovementProductId,
    bool clearMovementProduct = false,
    int? selectedWarehouseId,
    bool clearWarehouse = false,
  }) {
    return InventoryState(
      showLowStockOnly: showLowStockOnly ?? this.showLowStockOnly,
      selectedCategoryId: clearCategory
          ? null
          : (selectedCategoryId ?? this.selectedCategoryId),
      searchQuery: searchQuery ?? this.searchQuery,
      selectedMovementProductId: clearMovementProduct
          ? null
          : (selectedMovementProductId ?? this.selectedMovementProductId),
      selectedWarehouseId: clearWarehouse
          ? null
          : (selectedWarehouseId ?? this.selectedWarehouseId),
    );
  }
}

class InventoryNotifier extends Notifier<InventoryState> {
  late final InventoryRepository _repository;

  @override
  InventoryState build() {
    _repository = ref.watch(inventoryRepositoryProvider);
    return InventoryState();
  }

  void toggleLowStock(bool value) {
    state = state.copyWith(showLowStockOnly: value);
  }

  void setCategory(int? categoryId) {
    if (categoryId == null) {
      state = state.copyWith(clearCategory: true);
    } else {
      state = state.copyWith(selectedCategoryId: categoryId);
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setMovementProduct(int? productId) {
    if (productId == null) {
      state = state.copyWith(clearMovementProduct: true);
    } else {
      state = state.copyWith(selectedMovementProductId: productId);
    }
  }

  void setWarehouse(int? warehouseId) {
    if (warehouseId == null) {
      state = state.copyWith(clearWarehouse: true);
    } else {
      state = state.copyWith(selectedWarehouseId: warehouseId);
    }
  }

  Future<void> adjustStock({
    required int productId,
    required double quantity,
    required String adjustmentType,
    String? notes,
    required double currentStock,
  }) async {
    final double adjustedQty;
    final String movementType;

    if (adjustmentType == 'opening') {
      adjustedQty = quantity - currentStock;
      movementType = 'opening_stock';
    } else if (adjustmentType == 'waste') {
      adjustedQty = -quantity;
      movementType = 'waste';
    } else if (adjustmentType == 'damage') {
      adjustedQty = -quantity;
      movementType = 'damage';
    } else {
      adjustedQty = adjustmentType == 'add' ? quantity : -quantity;
      movementType = 'adjustment';
    }

    // ── Client mode: also queue to server (fire-and-forget) ──
    final warehouseId = ref.read(activeWarehouseIdProvider).value ?? 1;

    // Spec 135 BUG-A: mint ONE event gid here and thread the SAME value
    // into both the server submit and the local write, so the client's
    // autoposted JE and the server's autoposted JE converge on one
    // deterministic globalId (dedup on next pull) instead of each side
    // minting a colliding ...ref0... id (PG 23505) or a random divergent one.
    final adjustmentEventGid = UuidV7.generate();

    ClientWriteInterceptor.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: adjustedQty,
      type: movementType,
      notes: notes,
      adjustmentEventGid: adjustmentEventGid,
    ).catchError((_) => false);

    // ALWAYS adjust locally so UI reflects the change immediately
    await _repository.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: adjustedQty,
      notes: notes,
      type: movementType,
      adjustmentEventGid: adjustmentEventGid,
    );

    // Spec 150 BUG-1: the POS grid watches posGridProductsProvider (a bounded
    // DB-side stream), not the legacy allProductsProvider. In client mode the
    // write routes through the interceptor and the Drift table doesn't change
    // until the next pull, so nothing re-emits — invalidate so the new stock
    // level shows on the grid right away.
    ref.invalidate(posGridProductsProvider);
  }
}

final inventoryNotifierProvider =
    NotifierProvider.autoDispose<InventoryNotifier, InventoryState>(
      InventoryNotifier.new,
    );
