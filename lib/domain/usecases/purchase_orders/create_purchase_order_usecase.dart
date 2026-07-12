import '../../repositories/purchase_orders_repository.dart';
import '../../../data/database/database.dart' show PurchaseOrderItemsCompanion;

/// Use case: Create a purchase order with validation.
///
/// Validates supplier and items, then delegates to the repository.
/// Also supports converting an approved PO into a purchase invoice.
class CreatePurchaseOrderUseCase {
  final PurchaseOrdersRepository _repo;

  const CreatePurchaseOrderUseCase(this._repo);

  /// Creates a new purchase order.
  Future<int> execute({
    required int supplierId,
    required int warehouseId,
    required DateTime orderDate,
    required List<PurchaseOrderItemsCompanion> items,
    DateTime? expectedDate,
    String? notes,
    int? costCenterId,
  }) async {
    if (supplierId <= 0) {
      throw ArgumentError('المورد غير صحيح');
    }
    if (warehouseId <= 0) {
      throw ArgumentError('المستودع غير صحيح');
    }
    if (items.isEmpty) {
      throw ArgumentError('يجب إضافة صنف واحد على الأقل');
    }

    return _repo.createPurchaseOrder(
      supplierId: supplierId,
      warehouseId: warehouseId,
      orderDate: orderDate,
      items: items,
      expectedDate: expectedDate,
      notes: notes,
      costCenterId: costCenterId,
    );
  }

  /// Converts an approved PO into a purchase invoice.
  Future<int> convertToInvoice(int orderId) async {
    if (orderId <= 0) {
      throw ArgumentError('أمر الشراء غير صحيح');
    }
    return _repo.convertPOToInvoice(orderId);
  }

  /// Updates PO status (draft → sent → confirmed → received → cancelled).
  Future<void> updateStatus(int orderId, String newStatus) async {
    const validStatuses = [
      'draft',
      'sent',
      'confirmed',
      'received',
      'cancelled',
    ];
    if (!validStatuses.contains(newStatus)) {
      throw ArgumentError('حالة غير صالحة: $newStatus');
    }
    return _repo.updatePurchaseOrderStatus(orderId, newStatus);
  }
}
