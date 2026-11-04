part of 'api_purchase_handler.dart';

extension _ApiPurchaseHandlerHelpers on ApiPurchaseHandler {
  /// Resolve client warehouse IDs and enforce declared-branch ownership.
  Future<int> _resolveWarehouseId(
    int clientWarehouseId, {
    int? branchId,
  }) async {
    final existing =
        await (db.select(db.warehouses)
              ..where((warehouse) => warehouse.id.equals(clientWarehouseId)))
            .getSingleOrNull();
    if (existing == null) {
      throw Exception(
        'Strict Mapping Violation: Warehouse ID $clientWarehouseId not found on server.',
      );
    }
    // L4 (2026-04-28): enforce declared-branch ownership to prevent cross-branch writes.
    if (branchId != null &&
        existing.branchId != null &&
        existing.branchId != branchId) {
      throw Exception(
        'Authorization Error: warehouse $clientWarehouseId belongs to branch '
        '${existing.branchId} but client declared branch $branchId. '
        'Cross-branch operation denied.',
      );
    }
    return clientWarehouseId;
  }
}
