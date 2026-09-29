import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/repositories/inventory_repository.dart';
import '../../../../domain/repositories/i_products_repository.dart';
import '../../../../data/providers/providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../domain/entities/product_entity.dart';
import 'package:drift/drift.dart' show Value;

class BondItemModel {
  final ProductEntity product;
  final String categoryName;
  final String supplierName;
  double quantity;
  double costPrice;
  double salePrice;

  BondItemModel({
    required this.product,
    required this.categoryName,
    required this.supplierName,
    this.quantity = 0,
    required this.costPrice,
    required this.salePrice,
  });
}

class InventoryBondsState {
  final bool isLoading;
  final String? error;

  const InventoryBondsState({this.isLoading = false, this.error});

  InventoryBondsState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return InventoryBondsState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class InventoryBondsNotifier extends Notifier<InventoryBondsState> {
  late final InventoryRepository _inventoryRepo;
  late final IProductRepository _productRepo;

  @override
  InventoryBondsState build() {
    _inventoryRepo = ref.watch(inventoryRepositoryProvider);
    _productRepo = ref.watch(productRepositoryProvider);
    return const InventoryBondsState();
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
        'INVENTORY_BONDS',
      );
      return null;
    }
  }

  Future<BondItemModel?> getProductDetailsForBond(ProductEntity product) async {
    try {
      Category? category;
      Party? supplier;

      final categories = await _productRepo.getCategories();
      if (product.categoryId != null) {
        try {
          category = categories.firstWhere(
            (c) => c.id == product.categoryId,
          );
        } catch (_) {
          // not found
        }
      }

      final suppliers = await _productRepo.getSuppliers();
      if (product.supplierId != null) {
        try {
          supplier = suppliers.firstWhere(
            (s) => s.id == product.supplierId,
          );
        } catch (_) {
          // not found
        }
      }

      return BondItemModel(
        product: product,
        categoryName: category?.name ?? tr('غير مصنف'),
        supplierName: supplier?.name ?? tr('لا يوجد'),
        costPrice: product.costPrice,
        salePrice: product.salePrice,
        quantity: 0,
      );
    } catch (e) {
      logger.error(
        'Failed to get product details for bond',
        e,
        null,
        'INVENTORY_BONDS',
      );
      return null;
    }
  }

  Future<bool> saveBond({
    required String bondType,
    required int warehouseId,
    required String notes,
    required List<BondItemModel> items,
    required DateTime date,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final inventoryService = ref.read(inventoryServiceProvider);
      final userId = ref.read(authProvider).user?.id;

      final bondItems = items.map((item) {
        return InventoryBondItemsCompanion.insert(
          bondId: 0,
          productId: item.product.id,
          quantity: item.quantity,
          unitCost: Value(item.costPrice),
        );
      }).toList();

      if (bondType == 'opening') {
        await inventoryService.createOpeningBalanceBond(
          items: bondItems,
          warehouseId: warehouseId,
          notes: notes.isEmpty ? tr('رصيد افتتاحي') : notes,
          userId: userId,
        );
      } else {
        await inventoryService.createAddingBond(
          items: bondItems,
          warehouseId: warehouseId,
          notes: notes.isEmpty ? tr('سند إضافة') : notes,
          userId: userId,
          date: date,
        );
      }

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, st) {
      logger.error('Failed to save bond', e, st, 'INVENTORY_BONDS');
      state = state.copyWith(
        isLoading: false,
        error: tr('حدث خطأ أثناء حفظ السند: {e}', {'e': e}),
      );
      return false;
    }
  }
}

final inventoryBondsControllerProvider =
    NotifierProvider<InventoryBondsNotifier, InventoryBondsState>(
      InventoryBondsNotifier.new,
    );
