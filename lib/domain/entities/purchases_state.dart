/// Purchase state and entities for purchase flow
/// Separated from controller for cleaner testing
library;

/// Purchase cart item entity
class PurchaseCartItemEntity {
  final int productId;
  final String productName;
  final String productCode;
  final double quantity;
  final double unitCost;
  final double taxRate;
  final String? batchNumber;
  final DateTime? expiryDate;

  const PurchaseCartItemEntity({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    required this.unitCost,
    this.taxRate = 0,
    this.batchNumber,
    this.expiryDate,
  });

  double get subtotal => quantity * unitCost;
  double get taxAmount => subtotal * (taxRate / 100);
  double get total => subtotal + taxAmount;

  PurchaseCartItemEntity copyWith({
    int? productId,
    String? productName,
    String? productCode,
    double? quantity,
    double? unitCost,
    double? taxRate,
    String? batchNumber,
    DateTime? expiryDate,
  }) {
    return PurchaseCartItemEntity(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productCode: productCode ?? this.productCode,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      taxRate: taxRate ?? this.taxRate,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }
}

/// Purchases state
class PurchasesState {
  final List<PurchaseCartItemEntity> cart;
  final int? selectedSupplierId;
  final String? selectedSupplierName;
  final int? selectedWarehouseId;
  final double paid;
  final String? notes;
  final int? editingInvoiceId;
  final bool isProcessing;
  final String? error;

  const PurchasesState({
    this.cart = const [],
    this.selectedSupplierId,
    this.selectedSupplierName,
    this.selectedWarehouseId,
    this.paid = 0,
    this.notes,
    this.editingInvoiceId,
    this.isProcessing = false,
    this.error,
  });

  factory PurchasesState.initial() => const PurchasesState();

  double get subtotal => cart.fold(0, (sum, item) => sum + item.total);
  double get total => subtotal;
  double get remaining => total - paid;
  bool get isEditing => editingInvoiceId != null;

  PurchasesState copyWith({
    List<PurchaseCartItemEntity>? cart,
    int? selectedSupplierId,
    String? selectedSupplierName,
    int? selectedWarehouseId,
    double? paid,
    String? notes,
    int? editingInvoiceId,
    bool? isProcessing,
    String? error,
  }) {
    return PurchasesState(
      cart: cart ?? this.cart,
      selectedSupplierId: selectedSupplierId ?? this.selectedSupplierId,
      selectedSupplierName: selectedSupplierName ?? this.selectedSupplierName,
      selectedWarehouseId: selectedWarehouseId ?? this.selectedWarehouseId,
      paid: paid ?? this.paid,
      notes: notes ?? this.notes,
      editingInvoiceId: editingInvoiceId ?? this.editingInvoiceId,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
    );
  }

  PurchasesState clearSupplier() {
    return PurchasesState(
      cart: cart,
      selectedSupplierId: null,
      selectedSupplierName: null,
      paid: paid,
      notes: notes,
      editingInvoiceId: editingInvoiceId,
      isProcessing: isProcessing,
      error: error,
    );
  }
}
