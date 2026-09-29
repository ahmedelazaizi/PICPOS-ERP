import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/repositories/inventory_repository.dart';
import '../../../../data/providers/providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../domain/entities/product_entity.dart';

class TransferItemModel {
  final ProductEntity product;
  double quantity;
  final double costPrice; // Resolved from inventory_balances.averageCost

  TransferItemModel({required this.product, this.quantity = 1, double? costPrice})
      : costPrice = costPrice ?? product.costPrice;
}

class StockTransferState {
  final bool isLoading;
  final String? error;

  const StockTransferState({this.isLoading = false, this.error});

  StockTransferState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return StockTransferState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class StockTransferNotifier extends Notifier<StockTransferState> {
  late final InventoryRepository _inventoryRepo;

  @override
  StockTransferState build() {
    _inventoryRepo = ref.watch(inventoryRepositoryProvider);
    return const StockTransferState();
  }

  Future<int?> getDefaultWarehouseId() async {
    try {
      final warehouse = await _inventoryRepo.getDefaultWarehouse();
      return warehouse?.id;
    } catch (e) {
      logger.error(
        'Failed to get default warehouse',
        e,
        null,
        'STOCK_TRANSFER',
      );
      return null;
    }
  }

  /// Get the warehouse-specific average cost for a product
  /// Falls back to product.costPrice if no balance record exists
  Future<double> getProductWarehouseCost(int productId, int warehouseId) async {
    try {
      return await _inventoryRepo.getProductWarehouseCost(productId, warehouseId);
    } catch (e) {
      logger.error('Failed to get warehouse cost', e, null, 'STOCK_TRANSFER');
      return 0;
    }
  }

  Future<bool> saveTransfer({
    required int fromWarehouseId,
    required int toWarehouseId,
    required String notes,
    required List<TransferItemModel> items,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final inventoryService = ref.read(inventoryServiceProvider);
      final userId = ref.read(authProvider).user?.id;

      final transferItems = items
          .map(
            (item) => {'productId': item.product.id, 'quantity': item.quantity},
          )
          .toList();

      await inventoryService.transferStock(
        fromWarehouseId: fromWarehouseId,
        toWarehouseId: toWarehouseId,
        items: transferItems,
        notes: notes.isEmpty ? tr('تحويل مخزني') : notes,
        userId: userId,
      );

      // Log activity for audit trail
      try {
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? tr('مستخدم'),
          action: 'stock_adjust',
          entityType: 'stock',
          description: tr('تحويل مخزني: {p0} أصناف من مخزن {fromWarehouseId} إلى مخزن {toWarehouseId}', {'p0': items.length, 'fromWarehouseId': fromWarehouseId, 'toWarehouseId': toWarehouseId}),
        );
      } catch (_) {}

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, st) {
      logger.error('Failed to execute stock transfer', e, st, 'STOCK_TRANSFER');
      state = state.copyWith(isLoading: false, error: tr('حدث خطأ: {e}', {'e': e}));
      return false;
    }
  }
}

final stockTransferControllerProvider =
    NotifierProvider<StockTransferNotifier, StockTransferState>(
      StockTransferNotifier.new,
    );
