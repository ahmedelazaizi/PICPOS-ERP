import '../../repositories/purchases_repository.dart';

/// Use case for saving (creating or updating) a purchase invoice
///
/// Handles the complete purchase flow:
/// 1. Validate supplier and items
/// 2. Create or update invoice record via Repository
class SavePurchaseUseCase {
  final PurchasesRepository _repository;

  SavePurchaseUseCase(this._repository);

  /// Execute the purchase save (create or update)
  Future<PurchaseResult> execute(PurchaseRequest request) async {
    // 1. Validate request
    final validation = _validate(request);
    if (!validation.isValid) {
      return PurchaseResult.failure(validation.error!);
    }

    // 2. Calculate totals internally to return to the UI (so UI doesn't have to duplicate)
    final totals = _calculateTotals(request.items);

    try {
      if (request.invoiceId != null && request.isEditMode) {
        // Update existing
        await _repository.updateInvoice(
          UpdatePurchaseInvoiceParams(
            invoiceId: request.invoiceId!,
            supplierId: request.supplierId,
            warehouseId: request.warehouseId,
            items: request.items
                .map(
                  (item) => PurchaseItemParams(
                    productId: item.productId,
                    quantity: item.quantity,
                    unitCost: item.unitCost,
                    salePrice: item.salePrice,
                    taxRate: item.taxRate,
                    taxAmount: item.taxAmount,
                    batchNumber: item.batchNumber,
                    expiryDate: item.expiryDate,
                    unitName: item.unitName,
                    quantityInBase: item.quantityInBase,
                  ),
                )
                .toList(),
            paid: request.paidAmount,
            notes: request.notes,
            supplierInvoiceNumber: request.supplierInvoiceNumber,
            userId: request.userId,
          ),
        );

        return PurchaseResult.success(
          invoiceId: request.invoiceId!,
          totals: totals,
        );
      } else {
        // Create new
        final invoiceId = await _repository.createInvoice(
          CreatePurchaseInvoiceParams(
            supplierId: request.supplierId,
            warehouseId: request.warehouseId,
            items: request.items
                .map(
                  (item) => PurchaseItemParams(
                    productId: item.productId,
                    quantity: item.quantity,
                    unitCost: item.unitCost,
                    salePrice: item.salePrice,
                    taxRate: item.taxRate,
                    taxAmount: item.taxAmount,
                    batchNumber: item.batchNumber,
                    expiryDate: item.expiryDate,
                    unitName: item.unitName,
                    quantityInBase: item.quantityInBase,
                  ),
                )
                .toList(),
            paid: request.paidAmount,
            notes: request.notes,
            supplierInvoiceNumber: request.supplierInvoiceNumber,
          ),
        );

        return PurchaseResult.success(invoiceId: invoiceId, totals: totals);
      }
    } catch (e) {
      return PurchaseResult.failure('فشل في حفظ فاتورة الشراء: $e');
    }
  }

  PurchaseTotals _calculateTotals(List<PurchaseItemInput> items) {
    double subtotal = 0;
    double taxTotal = 0;
    for (final item in items) {
      subtotal += item.quantity * item.unitCost;
      taxTotal += item.taxAmount;
    }
    return PurchaseTotals(
      subtotal: subtotal,
      tax: taxTotal,
      total: subtotal + taxTotal,
      itemCount: items.length,
    );
  }

  ValidationResult _validate(PurchaseRequest request) {
    if (request.items.isEmpty) {
      return const ValidationResult.invalid('لا توجد منتجات في الفاتورة');
    }

    if (request.supplierId <= 0) {
      return const ValidationResult.invalid('يرجى اختيار مورد');
    }

    for (final item in request.items) {
      if (item.quantity <= 0) {
        return const ValidationResult.invalid('الكمية يجب أن تكون أكبر من صفر');
      }
      if (item.unitCost < 0) {
        return const ValidationResult.invalid(
          'سعر التكلفة لا يمكن أن يكون سالباً',
        );
      }
    }

    return const ValidationResult.valid();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REQUEST / RESPONSE CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Purchase request data
class PurchaseRequest {
  final int? invoiceId;
  final bool isEditMode;
  final int supplierId;
  final List<PurchaseItemInput> items;
  final double paidAmount;
  final int warehouseId;
  final String? notes;
  final String? supplierInvoiceNumber;

  /// Acting user — the `purchases_edit` gate in `updatePurchaseInvoice` is
  /// evaluated against this id. Required for edits; ignored on create.
  final int? userId;

  const PurchaseRequest({
    this.invoiceId,
    this.isEditMode = false,
    required this.supplierId,
    required this.items,
    required this.paidAmount,
    this.warehouseId = 1,
    this.notes,
    this.supplierInvoiceNumber,
    this.userId,
  });
}

/// Item input for purchase
class PurchaseItemInput {
  final int productId;
  final String productName;
  final double quantity;
  final double unitCost;
  final double salePrice;
  final double taxRate;
  final double taxAmount;
  final String? batchNumber;
  final DateTime? expiryDate;
  final String? unitName;
  final double quantityInBase;

  const PurchaseItemInput({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.salePrice,
    required this.taxRate,
    required this.taxAmount,
    this.batchNumber,
    this.expiryDate,
    this.unitName,
    this.quantityInBase = 1.0,
  });

  double get total => (quantity * unitCost) + taxAmount;
}

/// Purchase totals
class PurchaseTotals {
  final double subtotal;
  final double tax;
  final double total;
  final int itemCount;

  const PurchaseTotals({
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.itemCount,
  });
}

/// Purchase result
sealed class PurchaseResult {
  const PurchaseResult();

  factory PurchaseResult.success({
    required int invoiceId,
    required PurchaseTotals totals,
  }) = PurchaseSuccess;

  factory PurchaseResult.failure(String error) = PurchaseFailure;

  bool get isSuccess => this is PurchaseSuccess;
  bool get isFailure => this is PurchaseFailure;

  int? get invoiceId =>
      this is PurchaseSuccess ? (this as PurchaseSuccess).invoiceId : null;
  String? get errorMessage =>
      this is PurchaseFailure ? (this as PurchaseFailure).error : null;
}

class PurchaseSuccess extends PurchaseResult {
  @override
  final int invoiceId;
  final PurchaseTotals totals;

  const PurchaseSuccess({required this.invoiceId, required this.totals});
}

class PurchaseFailure extends PurchaseResult {
  final String error;
  const PurchaseFailure(this.error);
}

/// Validation result
class ValidationResult {
  final bool isValid;
  final String? error;

  const ValidationResult.valid() : isValid = true, error = null;
  const ValidationResult.invalid(this.error) : isValid = false;
}
