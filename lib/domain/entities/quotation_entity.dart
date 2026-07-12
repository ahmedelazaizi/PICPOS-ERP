class QuotationItemEntity {
  final int id;
  final int quotationId;
  final int productId;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double total;
  final double taxRate;
  final double taxAmount;
  final String? note;
  final String? productName;
  final String? productCode;

  const QuotationItemEntity({
    required this.id,
    required this.quotationId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.total,
    required this.taxRate,
    required this.taxAmount,
    this.note,
    this.productName,
    this.productCode,
  });
}

class QuotationEntity {
  final int id;
  final String quotationNumber;
  final int? customerId;
  final int warehouseId;
  final int userId;
  final DateTime quotationDate;
  final DateTime validityDate;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String? notes;
  final String status;

  // Joined fields
  final String? customerName;
  final String? userName;

  // Relations
  final List<QuotationItemEntity> items;

  const QuotationEntity({
    required this.id,
    required this.quotationNumber,
    this.customerId,
    required this.warehouseId,
    required this.userId,
    required this.quotationDate,
    required this.validityDate,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    this.notes,
    required this.status,
    this.customerName,
    this.userName,
    this.items = const [],
  });
}
