/// DTO for a single item in a sale sync request
class SyncSaleItem {
  final int productId;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double taxRate;
  final double taxAmount;
  final double total;
  final String? note;
  final double costPrice;
  // SAL-2: sale-unit → base-unit conversion factor. Without threading this
  // to the server, createSalesInvoice defaults it to 1.0 and under-decrements
  // physical stock on every non-base-unit (carton/box) sale.
  final double quantityInBase;

  SyncSaleItem({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
    this.note,
    required this.costPrice,
    this.quantityInBase = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'discount': discount,
    'taxRate': taxRate,
    'taxAmount': taxAmount,
    'total': total,
    'note': note,
    'costPrice': costPrice,
    'quantityInBase': quantityInBase,
  };
}

/// DTO for the full sale synchronization request
class SyncSaleRequest {
  final String invoiceNumber;
  final int? customerId;
  final int warehouseId;
  final int userId;
  final int? branchId;
  final int? costCenterId;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paid;
  final String paymentMethod;
  final double deliveryFee;
  final String? notes;
  final double? cashAmount;
  final double? bankAmount;
  final String saleType;
  final List<SyncSaleItem> items;
  final String? clientIpSuffix;
  final DateTime? invoiceDate;

  // Ad-hoc customer info (POS-4)
  final String? adhocCustomerName;
  final String? adhocCustomerPhone;
  final String? adhocCustomerNote;

  SyncSaleRequest({
    required this.invoiceNumber,
    this.customerId,
    required this.warehouseId,
    required this.userId,
    this.branchId,
    this.costCenterId,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paid,
    required this.paymentMethod,
    this.deliveryFee = 0,
    this.notes,
    this.cashAmount,
    this.bankAmount,
    this.saleType = 'default',
    required this.items,
    this.clientIpSuffix,
    this.invoiceDate,
    this.adhocCustomerName,
    this.adhocCustomerPhone,
    this.adhocCustomerNote,
  });

  Map<String, dynamic> toJson() => {
    'invoiceNumber': invoiceNumber,
    'customerId': customerId,
    'warehouseId': warehouseId,
    'userId': userId,
    'branchId': branchId,
    'costCenterId': costCenterId,
    'subtotal': subtotal,
    'discount': discount,
    'tax': tax,
    'total': total,
    'paid': paid,
    'paymentMethod': paymentMethod,
    'deliveryFee': deliveryFee,
    'notes': notes,
    'cashAmount': cashAmount,
    'bankAmount': bankAmount,
    'saleType': saleType,
    'items': items.map((i) => i.toJson()).toList(),
    'clientIpSuffix': clientIpSuffix,
    'invoiceDate': invoiceDate?.toIso8601String(),
    'adhocCustomerName': adhocCustomerName,
    'adhocCustomerPhone': adhocCustomerPhone,
    'adhocCustomerNote': adhocCustomerNote,
  };
}
