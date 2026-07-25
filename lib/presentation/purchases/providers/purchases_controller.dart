// ignore_for_file: avoid_dynamic_calls
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/providers.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/entities/purchases_state.dart';
import '../../../domain/repositories/purchases_repository.dart';
import '../../../services/client_write_interceptor.dart';

export '../../../domain/entities/purchases_state.dart';

/// Purchases controller - Riverpod 3.x Notifier pattern
class PurchasesController extends Notifier<PurchasesState> {
  @override
  PurchasesState build() {
    return PurchasesState.initial();
  }

  void addToCart(Product product) {
    final existingIndex = state.cart.indexWhere(
      (i) => i.productId == product.id,
    );

    if (existingIndex >= 0) {
      // Update existing item
      final existing = state.cart[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + 1);
      final newCart = [...state.cart];
      newCart[existingIndex] = updated;
      state = state.copyWith(cart: newCart);
    } else {
      // Add new item
      final newItem = PurchaseCartItemEntity(
        productId: product.id,
        productName: product.name,
        productCode: product.code,
        quantity: 1,
        unitCost: product.costPrice,
        taxRate: product.taxRate,
      );
      state = state.copyWith(cart: [...state.cart, newItem]);
    }

    logger.info(
      'Added to purchase cart: ${product.name}',
      correlationId: 'PURCHASES',
    );
  }

  void updateTaxRate(int index, double rate) {
    if (index < 0 || index >= state.cart.length) return;

    final updated = state.cart[index].copyWith(taxRate: rate);
    final newCart = [...state.cart];
    newCart[index] = updated;
    state = state.copyWith(cart: newCart);
  }

  void removeFromCart(int index) {
    if (index < 0 || index >= state.cart.length) return;

    final newCart = [
      ...state.cart.sublist(0, index),
      ...state.cart.sublist(index + 1),
    ];
    state = state.copyWith(cart: newCart);
  }

  void updateQuantity(int index, double quantity) {
    if (index < 0 || index >= state.cart.length) return;
    if (quantity <= 0) {
      removeFromCart(index);
      return;
    }

    final updated = state.cart[index].copyWith(quantity: quantity);
    final newCart = [...state.cart];
    newCart[index] = updated;
    state = state.copyWith(cart: newCart);
  }

  void updateUnitCost(int index, double cost) {
    if (index < 0 || index >= state.cart.length) return;

    final updated = state.cart[index].copyWith(unitCost: cost);
    final newCart = [...state.cart];
    newCart[index] = updated;
    state = state.copyWith(cart: newCart);
  }

  void updateBatch(int index, {String? batchNumber, DateTime? expiryDate}) {
    if (index < 0 || index >= state.cart.length) return;

    final updated = state.cart[index].copyWith(
      batchNumber: batchNumber,
      expiryDate: expiryDate,
    );
    final newCart = [...state.cart];
    newCart[index] = updated;
    state = state.copyWith(cart: newCart);
  }

  void setSupplier(int? id, String? name) {
    state = state.copyWith(selectedSupplierId: id, selectedSupplierName: name);
  }

  void setWarehouse(int? id) {
    state = state.copyWith(selectedWarehouseId: id);
  }

  void setPaid(double amount) {
    state = state.copyWith(paid: amount);
  }

  void setNotes(String? notes) {
    state = state.copyWith(notes: notes);
  }

  /// Load invoice for editing
  Future<void> loadForEdit({
    required int invoiceId,
    required int supplierId,
    required String? supplierName,
    required double paid,
    required String? notes,
    required List<dynamic> items, // PurchaseInvoiceItemWithProduct list
  }) async {
    clearForm();

    // Create cart items from invoice items
    final cartItems = <PurchaseCartItemEntity>[];
    for (final item in items) {
      cartItems.add(
        PurchaseCartItemEntity(
          productId: item.productId,
          productName: item.productName ?? 'منتج',
          productCode: '',
          quantity: item.quantity,
          unitCost: item.unitCost,
          batchNumber: item.batchNumber,
          expiryDate: item.expiryDate,
        ),
      );
    }

    state = state.copyWith(
      cart: cartItems,
      selectedSupplierId: supplierId,
      selectedSupplierName: supplierName,
      selectedWarehouseId:
          ref.read(activeWarehouseIdProvider).value ?? 1,
      paid: paid,
      notes: notes,
      editingInvoiceId: invoiceId,
    );

    logger.info(
      'Loaded invoice $invoiceId for editing with ${cartItems.length} items',
      correlationId: 'PURCHASES',
    );
  }

  void clearForm() {
    state = PurchasesState.initial();
  }

  Future<int?> saveInvoice() async {
    if (state.cart.isEmpty || state.selectedSupplierId == null) {
      state = state.copyWith(error: 'يرجى اختيار مورد وإضافة منتجات');
      return null;
    }

    state = state.copyWith(isProcessing: true, error: null);

    try {
      final items = state.cart
          .map(
            (item) => PurchaseItemParams(
              productId: item.productId,
              quantity: item.quantity,
              unitCost: item.unitCost,
              salePrice: 0, // Not used in simple purchase
              taxRate: item.taxRate,
              taxAmount: item.taxAmount,
              batchNumber: item.batchNumber,
              expiryDate: item.expiryDate,
            ),
          )
          .toList();

      int invoiceId;
      final warehouseId =
          state.selectedWarehouseId ?? ref.read(activeWarehouseIdProvider).value ?? 1;

      final purchasesRepo = ref.read(purchasesRepositoryProvider);

      if (state.isEditing && state.editingInvoiceId != null) {
        // ── Client mode: route update to server ──
        // The per-line map must carry EVERY field putPurchase reads. It
        // previously sent only productId/name/quantity/unitCost/total, so a
        // client-mode edit zeroed taxRate/taxAmount and dropped
        // batchNumber/expiryDate/unitName/quantityInBase on the server copy.
        final editUser = ref.read(authProvider).user;
        final serverUpdated = await ClientWriteInterceptor.updatePurchase(
          invoiceId: state.editingInvoiceId!,
          supplierId: state.selectedSupplierId!,
          items: state.cart
              .map(
                (item) => <String, dynamic>{
                  'productId': item.productId,
                  'productName': item.productName,
                  'quantity': item.quantity,
                  'unitCost': item.unitCost,
                  'total': item.total,
                  'taxRate': item.taxRate,
                  'taxAmount': item.taxAmount,
                  'batchNumber': item.batchNumber,
                  'expiryDate': item.expiryDate?.toIso8601String(),
                  // NOTE: this screen's cart model (PurchaseCartItemEntity)
                  // carries no UOM, so unitName/quantityInBase are omitted and
                  // the server applies its defaults (null / 1.0) — identical to
                  // what the local `items` path below does. The UOM-aware edit
                  // path is purchase_invoice_crud.dart.
                },
              )
              .toList(),
          paid: state.paid,
          notes: state.notes,
          warehouseId: warehouseId,
          userId: editUser?.id,
        );
        if (!serverUpdated) {
          // Not in client mode or server handled it — write locally
          await purchasesRepo.updateInvoice(
            UpdatePurchaseInvoiceParams(
              invoiceId: state.editingInvoiceId!,
              supplierId: state.selectedSupplierId!,
              warehouseId: warehouseId,
              items: items,
              paid: state.paid,
              notes: state.notes,
              userId: editUser?.id,
            ),
          );
        }
        invoiceId = state.editingInvoiceId!;
        logger.info(
          'Purchase invoice updated: $invoiceId',
          correlationId: 'PURCHASES',
        );
      } else {
        // ── Client mode: route to server ──
        final currentUser = ref.read(authProvider).user;
        final serverInvoiceId = await ClientWriteInterceptor.createPurchase(
          supplierId: state.selectedSupplierId!,
          items: state.cart
              .map(
                (item) => <String, dynamic>{
                  'productId': item.productId,
                  'productName': item.productName,
                  'quantity': item.quantity,
                  'unitCost': item.unitCost,
                  'total': item.total,
                },
              )
              .toList(),
          paid: state.paid,
          notes: state.notes,
          userId: currentUser?.id,
        );
        if (serverInvoiceId != null) {
          invoiceId = serverInvoiceId;
        } else {
          // Create new invoice locally
          invoiceId = await purchasesRepo.createInvoice(
            CreatePurchaseInvoiceParams(
              supplierId: state.selectedSupplierId!,
              warehouseId: warehouseId,
              items: items,
              paid: state.paid,
              notes: state.notes,
            ),
          );
        }
        logger.info(
          'Purchase invoice created: $invoiceId',
          correlationId: 'PURCHASES',
        );
      }


      // NOTE: Accounting entry is created INSIDE the DAO's createPurchaseInvoice() transaction.
      // Do NOT call generatePurchaseAccountingEntry here — that would create DUPLICATE journal entries.
      // The DAO inline posting uses dynamic account resolution and referenceType 'purchase_invoice'.

      // Log activity for audit trail (#13)
      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? 'مجهول',
        action: state.isEditing ? 'update_purchase' : 'add_purchase',
        entityType: 'purchase',
        entityId: invoiceId,
        description:
            '${state.isEditing ? 'تعديل' : 'إضافة'} فاتورة شراء رقم $invoiceId من ${state.selectedSupplierName}',
        amount: state.total,
      );

      clearForm();
      state = state.copyWith(isProcessing: false);
      return invoiceId;
    } catch (e, stack) {
      logger.error('Failed to save purchase invoice', e, stack, 'PURCHASES');
      state = state.copyWith(
        isProcessing: false,
        error: 'فشل حفظ الفاتورة: $e',
      );
      return null;
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }


}

/// Provider for purchases controller - Riverpod 3.x NotifierProvider
final purchasesControllerProvider =
    NotifierProvider<PurchasesController, PurchasesState>(
      PurchasesController.new,
    );