import '../../repositories/purchases_repository.dart';

/// Use case for creating a purchase invoice
///
/// Handles the complete purchase flow:
/// 1. Validate supplier and items
/// 2. Create invoice record
/// 3. Update inventory (add stock)
/// 4. Record stock movements
/// 5. Update supplier balance if credit purchase
class CreatePurchaseUseCase {
  final PurchasesRepository _repository;

  CreatePurchaseUseCase(this._repository);

  /// Execute the purchase creation
  Future<PurchaseResult> execute(PurchaseRequest request) async {
    // 1. Validate request
    final validation = _validate(request);
    if (!validation.isValid) {
      return PurchaseResult.failure(validation.error!);
    }

    // 2. Calculate totals
    final totals = _calculateTotals(request.items);

    try {
      // 3. Create the invoice
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
                ),
              )
              .toList(),
          paid: request.paidAmount,
          notes: request.notes,
        ),
      );

      return PurchaseResult.success(invoiceId: invoiceId, totals: totals);
    } catch (e) {
      return PurchaseResult.failure('فشل في حفظ فاتورة الشراء: $e');
    }
  }

  PurchaseTotals _calculateTotals(List<PurchaseItemInput> items) {
    double subtotal = 0;
    for (final item in items) {
      subtotal += item.quantity * item.unitCost;
    }
    return PurchaseTotals(subtotal: subtotal, itemCount: items.length);
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
  final int supplierId;
  final List<PurchaseItemInput> items;
  final double paidAmount;
  final int warehouseId;
  final String? notes;

  const PurchaseRequest({
    required this.supplierId,
    required this.items,
    required this.paidAmount,
    this.warehouseId = 1,
    this.notes,
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
  });

  double get total => quantity * unitCost;
}

/// Purchase totals
class PurchaseTotals {
  final double subtotal;
  final int itemCount;

  const PurchaseTotals({required this.subtotal, required this.itemCount});

  double get total => subtotal;
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
