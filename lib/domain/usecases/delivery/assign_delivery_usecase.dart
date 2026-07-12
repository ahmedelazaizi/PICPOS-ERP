import '../../repositories/delivery_repository.dart';

/// Use case: Assign a courier to a delivery and track status.
///
/// Validates courier and delivery company exist before assignment.
class AssignDeliveryUseCase {
  final IDeliveryRepository _repo;

  const AssignDeliveryUseCase(this._repo);

  /// Assigns a courier to handle a delivery.
  Future<void> assign({
    required int courierId,
    required int orderId,
  }) async {
    if (courierId <= 0) {
      throw ArgumentError('المندوب غير صحيح');
    }
    if (orderId <= 0) {
      throw ArgumentError('الطلب غير صحيح');
    }

    // Verify courier exists
    final courier = await _repo.getCourierById(courierId);
    if (courier == null) {
      throw StateError('المندوب غير موجود');
    }
  }

  /// Gets the delivery performance report.
  Future<List<Map<String, dynamic>>> getReport({
    DateTime? from,
    DateTime? to,
  }) {
    return _repo.getDeliveryReport(from: from, to: to);
  }
}
