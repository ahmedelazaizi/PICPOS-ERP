import '../../data/database/database.dart';

abstract class IRestaurantRepository {
  Stream<List<TableSection>> watchAllSections();
  Future<List<TableSection>> getAllSections();
  Future<int> createSection(String name);
  Future<bool> updateSection(int id, String name);
  Future<void> deleteSection(int id);

  Stream<List<RestaurantTable>> watchTablesInSection(int sectionId);
  Future<List<RestaurantTable>> getAllTables();
  Future<int> createTable({
    required String name,
    required int capacity,
    required int sectionId,
  });
  Future<bool> updateTable({
    required int id,
    required String name,
    required int capacity,
    required int sectionId,
  });
  Future<void> deleteTable(int id);
  Future<void> updateTableStatus(int id, String status);
  Future<void> updateTablePosition(int id, double x, double y);

  Future<TableReservation?> getActiveReservationForTable(int tableId);
  Future<void> createReservation({
    required int tableId,
    required String customerName,
    String? customerPhone,
    required DateTime reservationTime,
    required int partySize,
    String? notes,
  });
  Future<void> cancelReservation(int id);
  Future<void> seatReservation(int id, {int? userId});

  Future<void> transferTableOrder(int sourceTableId, int targetTableId);
  Future<void> partialTransferTableOrder({
    required int sourceTableId,
    required int targetTableId,
    required Map<int, double> itemQuantities,
  });

  Future<TableOrder?> getActiveOrderForTable(int tableId);
  Future<List<TableOrderItem>> getTableOrderItems(int orderId);

  Future<int> createTableOrder(int tableId, {int? userId});
  Future<void> finalizeTableOrder(int orderId, int tableId);
  Future<void> mergeTableOrders(int sourceTableId, int targetTableId);

  // Table order item operations (used by TablePosScreen)
  Future<void> addOrUpdateTableOrderItem({
    required int orderId,
    required int productId,
    required double quantity,
    required double unitPrice,
  });
  Future<void> clearTableOrderItems(int orderId);
}
