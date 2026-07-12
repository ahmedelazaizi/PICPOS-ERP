/// Invoice entity for domain layer
///
/// Pure domain entity - no Drift or UI dependencies
library;
import '../../data/database/database.dart';

class InvoiceEntity {
  final int? id;
  final String invoiceNumber;
  final InvoiceType type;
  final int? partyId;
  final String? partyName;
  final DateTime invoiceDate;
  final List<InvoiceLineEntity> lines;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final double paid;
  final InvoiceStatus status;
  final String? notes;
  final String? paymentMethod;
  final double cashPaid;
  final double bankPaid;
  final double clickPaid;
  final int? sellerId;
  final String? sellerName;
  final DateTime? createdAt;
  final String? saleType;
  final int? warehouseId;
  final int? costCenterId;
  final bool isLocked;
  final String? originClientId;
  final int? branchId;

  const InvoiceEntity({
    this.id,
    required this.invoiceNumber,
    required this.type,
    this.partyId,
    this.partyName,
    this.sellerId,
    this.sellerName,
    this.paymentMethod,
    this.cashPaid = 0,
    this.bankPaid = 0,
    this.clickPaid = 0,
    required this.invoiceDate,
    required this.lines,
    required this.subtotal,
    this.discountAmount = 0,
    this.taxAmount = 0,
    required this.total,
    required this.paid,
    required this.status,
    this.notes,
    this.createdAt,
    this.saleType,
    this.warehouseId,
    this.costCenterId,
    this.isLocked = false,
    this.originClientId,
    this.branchId,
  });

  /// Remaining balance
  double get remaining => total - paid;

  /// Check if fully paid
  bool get isFullyPaid => remaining <= 0;

  /// Check if has any payment
  bool get hasPayment => paid > 0;

  InvoiceEntity copyWith({
    int? id,
    String? invoiceNumber,
    InvoiceType? type,
    int? partyId,
    String? partyName,
    DateTime? invoiceDate,
    List<InvoiceLineEntity>? lines,
    double? subtotal,
    double? discountAmount,
    double? taxAmount,
    double? total,
    double? paid,
    InvoiceStatus? status,
    String? notes,
    int? sellerId,
    String? sellerName,
    String? paymentMethod,
    double? cashPaid,
    double? bankPaid,
    double? clickPaid,
    DateTime? createdAt,
    String? saleType,
    int? warehouseId,
    int? costCenterId,
    bool? isLocked,
    String? originClientId,
    int? branchId,
  }) {
    return InvoiceEntity(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      type: type ?? this.type,
      partyId: partyId ?? this.partyId,
      partyName: partyName ?? this.partyName,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      lines: lines ?? this.lines,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      paid: paid ?? this.paid,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      cashPaid: cashPaid ?? this.cashPaid,
      bankPaid: bankPaid ?? this.bankPaid,
      clickPaid: clickPaid ?? this.clickPaid,
      createdAt: createdAt ?? this.createdAt,
      saleType: saleType ?? this.saleType,
      warehouseId: warehouseId ?? this.warehouseId,
      costCenterId: costCenterId ?? this.costCenterId,
      isLocked: isLocked ?? this.isLocked,
      originClientId: originClientId ?? this.originClientId,
      branchId: branchId ?? this.branchId,
    );
  }

  factory InvoiceEntity.fromSalesInvoice(SalesInvoiceData data) {
    return InvoiceEntity(
      id: data.id,
      invoiceNumber: data.invoiceNumber,
      type: InvoiceType.sale,
      partyId: data.customerId,
      invoiceDate: data.invoiceDate,
      lines: [], // Need separate fetch for lines if needed
      subtotal: data.subtotal,
      discountAmount: data.discount,
      taxAmount: data.tax,
      total: data.total,
      paid: data.paid,
      sellerId: data.userId,
      paymentMethod: data.paymentMethod,
      cashPaid: data.cashPaid,
      bankPaid: data.bankPaid,
      clickPaid: data.clickPaid,
      status: _mapStatus(data.status),
      notes: data.notes,
      createdAt: data.createdAt,
      saleType: data.saleType,
      warehouseId: data.warehouseId,
      branchId: data.branchId,
      costCenterId: data.costCenterId,
      isLocked: data.isLocked,
      originClientId: data.originClientId,
    );
  }

  factory InvoiceEntity.fromPurchaseInvoice(PurchaseInvoiceData data) {
    // Prefer the internal sequential invoice number (e.g. PINV-1) over the
    // supplier-provided paper reference for every UI-facing display. The
    // supplier's number may be long/ugly (legacy rows still carry values
    // like `PUR-1776769934680` because the old form pre-filled it from
    // `DateTime.now().millisecondsSinceEpoch`), and the user asked for the
    // short form everywhere. Falls back to the supplier reference only if
    // the internal number somehow ended up blank, or to `PUR-<id>` as a
    // last-resort defensive placeholder.
    final internal = data.invoiceNumber.trim();
    final resolved = internal.isNotEmpty
        ? internal
        : (data.supplierInvoiceNumber ?? 'PUR-${data.id}');
    return InvoiceEntity(
      id: data.id,
      invoiceNumber: resolved,
      type: InvoiceType.purchase,
      partyId: data.supplierId,
      invoiceDate: data.invoiceDate,
      lines: [], // Need separate fetch for lines if needed
      subtotal: data.subtotal,
      total: data.total,
      paid: data.paid,
      status: _mapStatus(data.status),
      notes: data.notes,
      createdAt: data.createdAt,
      warehouseId: data.warehouseId,
      branchId: data.branchId,
      costCenterId: data.costCenterId,
      isLocked: data.isLocked,
    );
  }

  static InvoiceStatus _mapStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'paid':
      case 'completed':
        return InvoiceStatus.paid;
      case 'partial':
        return InvoiceStatus.partial;
      case 'cancelled':
        return InvoiceStatus.cancelled;
      case 'draft':
        return InvoiceStatus.draft;
      case 'returned':
        return InvoiceStatus.returned;
      case 'partial_return':
        return InvoiceStatus.partialReturn;
      default:
        return InvoiceStatus.pending;
    }
  }
}

/// Invoice line item
class InvoiceLineEntity {
  final int? id;
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double discountPercent;
  final double total;

  const InvoiceLineEntity({
    this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.discountPercent = 0,
    required this.total,
  });
}

/// Invoice type enum
enum InvoiceType { sale, purchase, saleReturn, purchaseReturn }

/// Invoice status enum. `returned` means the invoice was fully refunded
/// via the returns-screen flow; `partialReturn` means part of it was.
enum InvoiceStatus { draft, pending, partial, paid, cancelled, returned, partialReturn }
