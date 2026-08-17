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
  /// [taxRate] كسريّةٌ — حضورُ الحجز يفتح طلباً، فيلزمه ما يلزم الفتح.
  Future<void> seatReservation(int id, {int? userId, double taxRate = 0});

  Future<void> transferTableOrder(int sourceTableId, int targetTableId);
  Future<void> partialTransferTableOrder({
    required int sourceTableId,
    required int targetTableId,
    required Map<int, double> itemQuantities,
  });

  Future<TableOrder?> getActiveOrderForTable(int tableId);
  Future<List<TableOrderItem>> getTableOrderItems(int orderId);

  /// [taxRate] نسبةُ الضريبة كسريّةً (0.16) لقطةً من `pos_default_tax_rate`.
  /// المستدعي يقرأ الإعدادَ ويمرّره — طلبٌ بلا نسبةٍ لا يقبل تفعيلَ الضريبة.
  Future<int> createTableOrder(int tableId, {int? userId, double taxRate = 0});
  Future<void> mergeTableOrders(int sourceTableId, int targetTableId);

  // Table order item operations (used by TablePosScreen)
  /// [taxRate] نسبةُ ضريبة الصنف مئويّةً (16) منسوخةً عن `Products.taxRate`.
  Future<void> addOrUpdateTableOrderItem({
    required int orderId,
    required int productId,
    required double quantity,
    required double unitPrice,
    double taxRate = 0,
  });
  Future<void> clearTableOrderItems(int orderId);
}
