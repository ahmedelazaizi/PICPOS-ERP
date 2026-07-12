/// Requisition Item entity for domain layer
///
/// Pure domain entity - no Drift or UI dependencies
class StockRequisitionItemEntity {
  final int id;
  final int requisitionId;
  final int productId;
  final double quantity;
  final double fulfilledQuantity;
  final String? notes;

  const StockRequisitionItemEntity({
    required this.id,
    required this.requisitionId,
    required this.productId,
    required this.quantity,
    this.fulfilledQuantity = 0.0,
    this.notes,
  });

  StockRequisitionItemEntity copyWith({
    int? id,
    int? requisitionId,
    int? productId,
    double? quantity,
    double? fulfilledQuantity,
    String? notes,
  }) {
    return StockRequisitionItemEntity(
      id: id ?? this.id,
      requisitionId: requisitionId ?? this.requisitionId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      fulfilledQuantity: fulfilledQuantity ?? this.fulfilledQuantity,
      notes: notes ?? this.notes,
    );
  }
}
