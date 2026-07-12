import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/providers/providers.dart';
import '../../../core/utils/financial_utils.dart';
import '../../../domain/usecases/purchases/save_purchase_usecase.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/entities/invoice_entity.dart';
import '../../../services/costing_method_service.dart';

/// Cart item for purchase invoices
class PurchaseCartItem {
  final int productId;
  final String productName;
  final String productCode;
  double quantity;
  double unitCost;
  double salePrice;
  double taxRate;
  String? batchNumber;
  DateTime? expiryDate;
  int? selectedUnitId;
  String? selectedUnitName;
  double quantityInBase; // conversion factor (1 for base unit)

  PurchaseCartItem({
    required this.productId,
    required this.productName,
    required this.productCode,
    this.quantity = 1,
    this.unitCost = 0,
    this.salePrice = 0,
    this.taxRate = 0,
    this.batchNumber,
    this.expiryDate,
    this.selectedUnitId,
    this.selectedUnitName,
    this.quantityInBase = 1,
  });

  double get taxAmount => FinancialUtils.calculateTaxAmount(
    FinancialUtils.calculateLineSubtotal(quantity, unitCost),
    taxRate,
  );
  double get total => FinancialUtils.calculateLineNetTotal(
    quantity: quantity,
    unitPrice: unitCost,
    taxRatePercent: taxRate,
  );
  /// Quantity converted to base units for stock movement
  double get baseQuantity => quantity * quantityInBase;
  /// Cost per base unit for WAC calculation
  double get baseCost => quantityInBase > 0 ? unitCost / quantityInBase : unitCost;

  PurchaseCartItem copyWith({
    double? quantity,
    double? unitCost,
    double? salePrice,
    double? taxRate,
    String? batchNumber,
    DateTime? expiryDate,
    int? selectedUnitId,
    String? selectedUnitName,
    double? quantityInBase,
  }) {
    return PurchaseCartItem(
      productId: productId,
      productName: productName,
      productCode: productCode,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      salePrice: salePrice ?? this.salePrice,
      taxRate: taxRate ?? this.taxRate,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      selectedUnitId: selectedUnitId ?? this.selectedUnitId,
      selectedUnitName: selectedUnitName ?? this.selectedUnitName,
      quantityInBase: quantityInBase ?? this.quantityInBase,
    );
  }
}

/// State for the purchases form
class PurchasesFormState {
  final List<PurchaseCartItem> cart;
  final int? selectedSupplierId;
  final int? selectedWarehouseId;
  final bool isLoading;
  final bool isEditMode;
  final int? editingInvoiceId;
  final String editingInvoiceNumber;
  final String supplierInvoiceNumber;
  final double paidAmount;

  PurchasesFormState({
    this.cart = const [],
    this.selectedSupplierId,
    this.selectedWarehouseId,
    this.isLoading = false,
    this.isEditMode = false,
    this.editingInvoiceId,
    this.editingInvoiceNumber = '',
    this.supplierInvoiceNumber = '',
    this.paidAmount = 0,
  });

  // BUG-M03: round the summed (already per-line-rounded) subtotal so the
  // line-vs-invoice rounding strategy is consistent (round per line, then sum).
  double get subtotal => FinancialUtils.round(cart.fold(
        0.0,
        (sum, item) =>
            sum +
            FinancialUtils.calculateLineSubtotal(item.quantity, item.unitCost),
      ));
  double get totalTax => cart.fold(0.0, (sum, item) => sum + item.taxAmount);
  double get tax => totalTax; // Alias for UI
  double get grandTotal => FinancialUtils.round(subtotal + totalTax);

  PurchasesFormState copyWith({
    List<PurchaseCartItem>? cart,
    int? selectedSupplierId,
    int? selectedWarehouseId,
    bool? isLoading,
    bool? isEditMode,
    int? editingInvoiceId,
    String? editingInvoiceNumber,
    String? supplierInvoiceNumber,
    double? paidAmount,
  }) {
    return PurchasesFormState(
      cart: cart ?? this.cart,
      selectedSupplierId: selectedSupplierId ?? this.selectedSupplierId,
      selectedWarehouseId: selectedWarehouseId ?? this.selectedWarehouseId,
      isLoading: isLoading ?? this.isLoading,
      isEditMode: isEditMode ?? this.isEditMode,
      editingInvoiceId: editingInvoiceId ?? this.editingInvoiceId,
      editingInvoiceNumber: editingInvoiceNumber ?? this.editingInvoiceNumber,
      supplierInvoiceNumber:
          supplierInvoiceNumber ?? this.supplierInvoiceNumber,
      paidAmount: paidAmount ?? this.paidAmount,
    );
  }
}

/// Provider for purchase invoices list
final purchaseInvoicesProvider = StreamProvider<List<InvoiceEntity>>((
  ref,
) {
  final repo = ref.watch(purchasesRepositoryProvider);
  return repo.watchInvoices();
});

/// Provider for purchase invoices with supplier info
final purchasesWithSupplierProvider = FutureProvider<List<dynamic>>((
  ref,
) async {
  final repo = ref.read(purchasesRepositoryProvider);
  final invoices = await repo.getPurchasesReport(
    DateTime(2020),
    DateTime(2050),
  ); // Generic fetch for now as it was doing a plain select
  return invoices;
});

/// Purchases form notifier using Riverpod Notifier
class PurchasesFormNotifier extends Notifier<PurchasesFormState> {
  ActivityLogger get _logger => ref.read(activityLoggerProvider);

  @override
  PurchasesFormState build() => PurchasesFormState();

  // --- Cart Management (Index-based for UI) ---

  void addToCart(ProductEntity product) {
    final existingIndex = state.cart.indexWhere(
      (item) => item.productId == product.id,
    );

    if (existingIndex != -1) {
      final updatedCart = List<PurchaseCartItem>.from(state.cart);
      updatedCart[existingIndex] = updatedCart[existingIndex].copyWith(
        quantity: updatedCart[existingIndex].quantity + 1,
      );
      state = state.copyWith(cart: updatedCart);
    } else {
      final newItem = PurchaseCartItem(
        productId: product.id,
        productName: product.name,
        productCode: product.code,
        unitCost: product.costPrice,
        salePrice: product.salePrice,
      );
      state = state.copyWith(cart: [...state.cart, newItem]);
    }
  }

  void removeFromCart(int index) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<PurchaseCartItem>.from(state.cart);
    updatedCart.removeAt(index);
    state = state.copyWith(cart: updatedCart);
  }

  void updateQuantity(int index, double quantity) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<PurchaseCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(quantity: quantity);
    state = state.copyWith(cart: updatedCart);
  }

  void updateUnitCost(int index, double cost) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<PurchaseCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(unitCost: cost);
    state = state.copyWith(cart: updatedCart);
  }

  void updateSalePrice(int index, double price) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<PurchaseCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(salePrice: price);
    state = state.copyWith(cart: updatedCart);
  }

  void updateTaxRate(int index, double taxRate) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<PurchaseCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(taxRate: taxRate);
    state = state.copyWith(cart: updatedCart);
  }

  void updateBatchNumber(int index, String? batch) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<PurchaseCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(batchNumber: batch);
    state = state.copyWith(cart: updatedCart);
  }

  void updateExpiryDate(int index, DateTime? expiry) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<PurchaseCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(expiryDate: expiry);
    state = state.copyWith(cart: updatedCart);
  }

  /// Update the selected unit for a purchase cart item
  void updateItemUnit(int index, {
    required int unitId,
    required String unitName,
    required double quantityInBase,
    required double unitCostPrice,
  }) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<PurchaseCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(
      selectedUnitId: unitId,
      selectedUnitName: unitName,
      quantityInBase: quantityInBase,
      unitCost: unitCostPrice,
    );
    state = state.copyWith(cart: updatedCart);
  }

  // --- Form State ---

  void selectSupplier(int? supplierId) {
    state = state.copyWith(selectedSupplierId: supplierId);
  }

  void selectWarehouse(int? warehouseId) {
    state = state.copyWith(selectedWarehouseId: warehouseId);
  }

  void updateSupplierInvoiceNumber(String number) {
    state = state.copyWith(supplierInvoiceNumber: number);
  }

  void updatePaidAmount(double amount) {
    state = state.copyWith(paidAmount: amount);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void clearForm() {
    state = PurchasesFormState();
  }

  // --- Business Logic ---

  Future<void> loadInvoiceForEdit(PurchaseInvoiceData invoice) async {
    setLoading(true);
    try {
      final purchasesRepo = ref.read(purchasesRepositoryProvider);
      final items = await purchasesRepo.getInvoiceItemsWithProduct(invoice.id);

      final cartItems = items
          .map(
            (i) => PurchaseCartItem(
              productId: i.product.id,
              productName: i.product.name,
              productCode: i.product.code,
              quantity: i.item.quantity,
              unitCost: i.item.unitCost,
              salePrice: i.product.salePrice,
              taxRate: i.item.taxRate,
              batchNumber: i.item.batchNumber,
              expiryDate: i.item.expiryDate,
            ),
          )
          .toList();

      state = state.copyWith(
        cart: cartItems,
        selectedSupplierId: invoice.supplierId,
        selectedWarehouseId: invoice.warehouseId,
        isEditMode: true,
        editingInvoiceId: invoice.id,
        editingInvoiceNumber: invoice.invoiceNumber,
        supplierInvoiceNumber: invoice.supplierInvoiceNumber ?? '',
        paidAmount: invoice.paid,
        isLoading: false,
      );
    } catch (e) {
      setLoading(false);
      rethrow;
    }
  }

  Future<bool> saveInvoice({
    required double paid,
    String? notes,
    required String supplierInvoiceNumber,
  }) async {
    try {
      setLoading(true);
      final auth = ref.read(authProvider);
      final user = auth.user;

      if (state.selectedSupplierId == null) {
        setLoading(false);
        throw Exception('يرجى اختيار المورد');
      }
      if (state.cart.isEmpty) throw Exception('يرجى إضافة أصناف');

      // selectedSupplierId is guaranteed non-null after the guard above.
      final supplierId = state.selectedSupplierId!;

      final partiesRepo = ref.read(partiesRepositoryProvider);
      final supplier = await partiesRepo.getPartyById(supplierId);
      final supplierName = supplier?.name ?? 'مورد غير معروف';

      final repository = ref.read(purchasesRepositoryProvider);
      final useCase = SavePurchaseUseCase(repository);

      final requestItems = state.cart
          .map(
            (item) => PurchaseItemInput(
              productId: item.productId,
              productName: item.productName,
              quantity: item.quantity,
              unitCost: item.unitCost,
              salePrice: item.salePrice,
              taxRate: item.taxRate,
              taxAmount: item.taxAmount,
              batchNumber: item.batchNumber,
              expiryDate: item.expiryDate,
            ),
          )
          .toList();

      final request = PurchaseRequest(
        invoiceId: state.isEditMode ? state.editingInvoiceId : null,
        isEditMode: state.isEditMode,
        supplierId: supplierId,
        items: requestItems,
        paidAmount: paid,
        warehouseId: state.selectedWarehouseId ?? ref.read(activeWarehouseIdProvider).value ?? 1,
        notes: notes?.isEmpty ?? true ? null : notes,
        supplierInvoiceNumber: supplierInvoiceNumber.isEmpty
            ? null
            : supplierInvoiceNumber,
      );

      final result = await useCase.execute(request);

      if (result.isSuccess) {
        final success = result as PurchaseSuccess;

        // Audit Trail
        _logger.log(
          userId: user?.id,
          userName: user?.displayName ?? 'System',
          action: state.isEditMode ? 'edit_purchase' : 'create_purchase',
          entityType: 'invoice',
          entityId: success.invoiceId,
          description: state.isEditMode
              ? 'تعديل فاتورة شراء #${state.editingInvoiceNumber} من $supplierName بقيمة ${state.grandTotal.toStringAsFixed(AppConstants.decimalPlaces)}'
              : 'إنشاء فاتورة شراء من $supplierName بقيمة ${state.grandTotal.toStringAsFixed(AppConstants.decimalPlaces)}',
          amount: state.grandTotal,
        );

        // Update product prices based on costing method setting
        final productRepo = ref.read(productRepositoryProvider);
        final costingMethod = await CostingMethodService.load(ref.read(settingsRepositoryProvider));
        for (final item in state.cart) {
          final product = await productRepo.getProductById(item.productId);
          if (product != null &&
              (item.unitCost != product.costPrice ||
                  item.salePrice != product.salePrice)) {
            // Calculate cost based on configured method
            // CRITICAL: Use base-unit quantities and costs for WAC
            final newCost = CostingMethodService.calculateCost(
              method: costingMethod,
              currentStock: product.currentStock,
              currentCost: product.costPrice,
              purchaseQty: item.baseQuantity,
              purchaseUnitCost: item.baseCost,
            );
            await productRepo.updateProductPrices(
              item.productId,
              costPrice: newCost,
              salePrice: item.salePrice,
            );

            // Log price override if cost changed
            if (item.unitCost != product.costPrice) {
              _logger.logPriceOverride(
                user?.id ?? 0,
                user?.displayName ?? 'System',
                item.productName,
                product.costPrice,
                newCost,
              );
            }
          }
        }

        setLoading(false);
        return true;
      } else {
        throw Exception((result as PurchaseFailure).error);
      }
    } catch (e) {
      setLoading(false);
      rethrow;
    }
  }
}

final purchasesFormProvider =
    NotifierProvider<PurchasesFormNotifier, PurchasesFormState>(() {
      return PurchasesFormNotifier();
    });
