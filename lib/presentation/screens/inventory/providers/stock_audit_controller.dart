import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/providers/providers.dart';
import '../../../../core/logging/app_logger.dart';

class StockAuditState {
  final bool isLoading;
  final String? error;

  const StockAuditState({this.isLoading = false, this.error});

  StockAuditState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return StockAuditState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class StockAuditNotifier extends Notifier<StockAuditState> {
  @override
  StockAuditState build() {
    return const StockAuditState();
  }

  Future<Product?> getProductDetails(int productId) async {
    final productRepo = ref.read(productRepositoryProvider);
    final product = await productRepo.getProductById(productId);
    if (product == null) return null;
    
    // Convert ProductEntity to database Product if necessary (though usually entities are preferred)
    // For now, let's assume the UI expects the database model as per current code
    // If the UI is updated to use entities, this can be simplified.
    return Product(
      id: product.id,
      globalId: product.id.toString(), // Entity ID fallback
      code: product.code,
      name: product.name,
      categoryId: product.categoryId,
      salePrice: product.salePrice,
      costPrice: product.costPrice,
      currentStock: product.currentStock,
      minStock: product.minStock,
      trackInventory: product.trackInventory,
      trackExpiry: product.trackExpiry,
      isSoldByWeight: product.isSoldByWeight,
      isActive: product.isActive,
      barcode: product.barcode,
      scalePluNumber: product.scalePluNumber,
      scaleType: product.scaleType ?? 'weight',
      taxRate: product.taxRate,
      isLocked: product.isLocked,
      allowNegativeSale: product.allowNegativeSale,
      defaultShelfDays: product.defaultShelfDays,
      alertDaysBefore: product.alertDaysBefore,
      priceTalabat: product.priceTalabat,
      priceCareem: product.priceCareem,
      priceAshyae: product.priceAshyae,
      wholesalePrice: product.wholesalePrice,
      productType: product.productType,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isKitchenSet: false,
      itemTaxType: 'T1',
      itemTaxSubtype: 'V009',
      sortOrder: 0,
      weightUnit: 'kg',
      rowVersion: 0,
      createdOnServer: product.createdOnServer,
    );
  }

  Future<void> startNewAudit() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = ref.read(authProvider).user;
      final inventoryRepo = ref.read(inventoryRepositoryProvider);

      await inventoryRepo.createStockAudit(userId: user?.id);

      try {
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مستخدم',
          action: 'start_audit',
          entityType: 'stock',
          description: 'بدء جرد جديد',
        );
      } catch (_) {}

      state = state.copyWith(isLoading: false);
    } catch (e, st) {
      logger.error('Failed to start new audit', e, st, 'STOCK_AUDIT');
      state = state.copyWith(isLoading: false, error: 'حدث خطأ: $e');
    }
  }

  Future<String?> scanBarcode(String barcode, int auditId) async {
    if (barcode.isEmpty) return null;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final productRepo = ref.read(productRepositoryProvider);
      final inventoryRepo = ref.read(inventoryRepositoryProvider);
      
      final product =
          await productRepo.getProductByBarcode(barcode) ??
          await productRepo.getProductByCode(barcode);

      if (product == null) {
        state = state.copyWith(isLoading: false);
        return 'الصنف غير موجود';
      }

      final existingItems = await inventoryRepo.getAuditItems(auditId);
      final existing = existingItems.firstWhere(
        (i) => i.productId == product.id,
        orElse: () => StockAuditItem(
          id: 0,
          auditId: auditId,
          productId: product.id,
          expectedQuantity: product.currentStock,
          actualQuantity: 0,
          difference: 0,
          scannedAt: DateTime.now(),
        ),
      );

      await inventoryRepo.saveAuditItem(
        auditId: auditId,
        productId: product.id,
        expectedQuantity: product.currentStock,
        actualQuantity: existing.actualQuantity + 1,
      );

      state = state.copyWith(isLoading: false);
      return null; // success
    } catch (e, st) {
      logger.error('Failed to scan barcode', e, st, 'STOCK_AUDIT');
      state = state.copyWith(isLoading: false, error: 'حدث خطأ: $e');
      return 'حدث خطأ: $e';
    }
  }

  Future<void> updateCount(StockAuditItem item, double newValue) async {
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .saveAuditItem(
            auditId: item.auditId,
            productId: item.productId,
            expectedQuantity: item.expectedQuantity,
            actualQuantity: newValue,
          );
    } catch (e, st) {
      logger.error('Failed to update count', e, st, 'STOCK_AUDIT');
    }
  }

  Future<bool> finalizeAudit(int auditId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final inventoryRepo = ref.read(inventoryRepositoryProvider);
      await inventoryRepo.finalizeAudit(auditId);

      try {
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مستخدم',
          action: 'finalize_audit',
          entityType: 'stock',
          entityId: auditId,
          description: 'اعتماد جرد رقم $auditId وتحديث المخزون',
        );
      } catch (_) {}

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, st) {
      logger.error('Failed to finalize audit', e, st, 'STOCK_AUDIT');
      state = state.copyWith(isLoading: false, error: 'حدث خطأ: $e');
      return false;
    }
  }
}

final stockAuditControllerProvider =
    NotifierProvider<StockAuditNotifier, StockAuditState>(
      StockAuditNotifier.new,
    );
