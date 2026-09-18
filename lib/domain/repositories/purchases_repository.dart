import '../entities/invoice_entity.dart';
import '../../data/database/database.dart' show PurchaseInvoiceItemWithProduct, PurchaseInvoiceData;
/// Purchases repository interface
///
/// Defines contract for purchase operations. Implementations in data layer.
abstract class PurchasesRepository {
  /// Create a new purchase invoice
  Future<int> createInvoice(CreatePurchaseInvoiceParams params);

  /// Get invoice by ID
  Future<InvoiceEntity?> getInvoiceById(int id);

  /// Watch all purchase invoices
  Stream<List<InvoiceEntity>> watchInvoices();

  /// Watch invoices by date range
  Stream<List<InvoiceEntity>> watchInvoicesByDateRange(
    DateTime start,
    DateTime end,
  );

  /// Record payment for invoice
  Future<void> recordPayment(int invoiceId, double amount, {int? userId});

  /// Update purchase invoice
  Future<void> updateInvoice(UpdatePurchaseInvoiceParams params);

  /// Get purchases report by date range
  Future<List<InvoiceEntity>> getPurchasesReport(DateTime start, DateTime end);

  /// Get purchases by supplier
  Future<List<InvoiceEntity>> getPurchasesBySupplier(int supplierId);

  /// Delete purchase invoice (Legacy - redirects to void)
  Future<void> deleteInvoice(int invoiceId);

  /// Void purchase invoice (ISS-05)
  Future<void> voidInvoice(int invoiceId, {String? reason});

  /// Get purchase invoice items with product data
  Future<List<PurchaseInvoiceItemWithProduct>> getInvoiceItemsWithProduct(
    int invoiceId,
  );

  /// Process purchase return — ISS-01: encapsulate return logic behind repository
  /// Returns the total return amount
  Future<double> processPurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> returnItems,
    /// سببُ المردود من القائمة الثابتة — يُكتَب في `PurchaseReturns.reason`.
    /// اختياريٌّ في العقد لأنّ منادين أقدمَ لا يمرّرونه؛ والواجهةُ تفرضه.
    String? reason,
  });

  /// Feature 015 — Edit a previously-posted purchase return.
  ///
  /// Atomically reverses every side-effect of the original return (stock
  /// movements, WAC, supplier balance, safe-transactions memo, cash refund,
  /// journal entry, invoice status) and re-posts a fresh return with
  /// [newReturnItems]. Audit trail is preserved via append-only
  /// compensating rows + a flipped journal entry — never silent mutation.
  ///
  /// Period gate: if [invoice].invoiceDate falls inside a closed fiscal
  /// year or monthly period, throws the same Arabic message
  /// `processPurchaseReturn` uses (Feature 014).
  ///
  /// Returns the new total return amount.
  Future<double> editPurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> newReturnItems,
  });

  /// Get raw purchase invoice by ID (drift type)
  Future<PurchaseInvoiceData?> getRawInvoiceById(int id);
}

/// Parameters for creating a purchase invoice
class CreatePurchaseInvoiceParams {
  final int supplierId;
  final int warehouseId;
  final List<PurchaseItemParams> items;
  final double paid;
  final String paymentMethod;
  final String? notes;
  final String? supplierInvoiceNumber;
  final DateTime? date;
  final int? costCenterId;
  final int? safeId;
  final int? userId;
  final String? createdByUsername;

  /// Client issue ح-1 (2026-07-25): invoice-level discount. The form has always
  /// collected it and shown a net «الصافي النهائى», but it had nowhere to go —
  /// the header stored the GROSS total, so the difference became a phantom
  /// payable on the supplier that could never be settled.
  final double discount;

  const CreatePurchaseInvoiceParams({
    required this.supplierId,
    required this.warehouseId,
    required this.items,
    required this.paid,
    this.paymentMethod = 'cash',
    this.notes,
    this.supplierInvoiceNumber,
    this.date,
    this.costCenterId,
    this.safeId,
    this.userId,
    this.createdByUsername,
    this.discount = 0,
  });
}

/// Parameters for a purchase item
class PurchaseItemParams {
  final int productId;
  final double quantity;
  final double unitCost;
  final double salePrice;
  final double taxRate;
  final double taxAmount;
  final String? batchNumber;
  final DateTime? expiryDate;
  final String? unitName; // NEW: Display name of the selected unit
  // UOM: conversion factor from selected unit to base unit
  final double quantityInBase; // e.g. 24 for carton=24 pieces

  /// خصمُ هذا السطر **مبلغاً** — قرارُ المالك 2026-09-18 على تصميم فاتورة
  /// المشتريات: الخصمُ لكلّ صنف.
  ///
  /// ⚠️ **وهو مبلغٌ على السطر كلِّه لا على الوحدة**، فلا يُقسَم على
  /// `quantityInBase` كما تُقسَم [unitCost]. والمحرّكُ يوزّعه عبر
  /// `resolvePurchaseLineNets` قبل أن يصل التكلفةَ وحركةَ المخزون ومتوسّطَ
  /// التكلفة.
  final double discount;

  const PurchaseItemParams({
    required this.productId,
    required this.quantity,
    required this.unitCost,
    required this.salePrice,
    required this.taxRate,
    required this.taxAmount,
    this.batchNumber,
    this.expiryDate,
    this.unitName,
    this.quantityInBase = 1.0,
    this.discount = 0,
  });

  /// Stock quantity in base units (e.g., 3 cartons × 24 = 72 pieces)
  double get stockQuantity => quantity * quantityInBase;

  /// قيمةُ السطر قبل الخصم والضريبة.
  double get grossSubtotal => quantity * unitCost;

  /// الخصمُ المطبَّقُ فعلاً — محصورٌ في [0, grossSubtotal].
  ///
  /// خصمٌ أكبرُ من قيمة السطر كان سيُنتج `total` سالباً يُخزَّن كما هو.
  double get appliedDiscount {
    if (discount <= 0) return 0.0;
    return discount > grossSubtotal ? grossSubtotal : discount;
  }

  double get total => (grossSubtotal - appliedDiscount) + taxAmount;
}

/// Parameters for updating a purchase invoice
class UpdatePurchaseInvoiceParams {
  final int invoiceId;
  final int? supplierId;
  final int? warehouseId;
  final List<PurchaseItemParams>? items;
  final double? paid;
  final String? notes;
  final String? supplierInvoiceNumber;
  final String? paymentMethod;
  final int? costCenterId;

  /// Caller's userId — the ONLY gate on purchase-invoice editing.
  /// `purchases_edit` is checked against it in `updatePurchaseInvoice`;
  /// a null value is denied, so every call site MUST supply it.
  final int? userId;

  /// ح-1 — invoice-level discount on EDIT. Null keeps whatever the stored
  /// header already holds, so a caller that doesn't collect a discount can't
  /// silently wipe one.
  final double? discount;

  const UpdatePurchaseInvoiceParams({
    required this.invoiceId,
    this.supplierId,
    this.warehouseId,
    this.items,
    this.paid,
    this.notes,
    this.supplierInvoiceNumber,
    this.paymentMethod,
    this.costCenterId,
    this.userId,
    this.discount,
  });
}

/// Data class for purchase return items
class PurchaseReturnItem {
  final int itemId;
  final int productId;
  final double returnQuantity;
  final double unitCost;
  final double taxAmount;
  final double originalQuantity;
  final double quantityInBase; // B1: UOM conversion factor

  const PurchaseReturnItem({
    required this.itemId,
    required this.productId,
    required this.returnQuantity,
    required this.unitCost,
    required this.taxAmount,
    required this.originalQuantity,
    this.quantityInBase = 1.0,
  });
}
