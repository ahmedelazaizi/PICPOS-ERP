import '../database/database.dart';
import '../../domain/repositories/kitchen_repository.dart';

/// Implementation of [KitchenRepository] using Drift DAO.
class KitchenRepositoryImpl implements KitchenRepository {
  final AppDatabase _db;

  KitchenRepositoryImpl(this._db);

  // ── Work Order CRUD ───────────────────────────────────────────────────

  @override
  Future<int> createWorkOrder({
    required String orderNumber,
    required List<WorkOrderItemData> items,
    String station = 'kitchen',
    String priority = 'normal',
    int? tableOrderId,
    int? invoiceId,
    String? customerName,
    String? notes,
    int? createdBy,
  }) =>
      _db.createWorkOrder(
        orderNumber: orderNumber,
        items: items,
        station: station,
        priority: priority,
        tableOrderId: tableOrderId,
        invoiceId: invoiceId,
        customerName: customerName,
        notes: notes,
        createdBy: createdBy,
      );

  @override
  Future<String> generateWorkOrderNumber() =>
      _db.generateWorkOrderNumber();

  // ── Watch Streams ─────────────────────────────────────────────────────

  @override
  Stream<List<WorkOrder>> watchPendingOrders() =>
      _db.watchPendingOrders();

  @override
  Stream<List<WorkOrder>> watchReadyOrders() =>
      _db.watchReadyOrders();

  @override
  Stream<List<WorkOrder>> watchOrdersByStation(String station) =>
      _db.watchOrdersByStation(station);

  @override
  Stream<List<WorkOrderItem>> watchOrderItems(int workOrderId) =>
      _db.watchOrderItems(workOrderId);

  // ── Status Updates ────────────────────────────────────────────────────

  @override
  Future<void> updateWorkOrderStatus(int orderId, String newStatus) =>
      _db.updateWorkOrderStatus(orderId, newStatus);

  @override
  Future<void> markItemReady(int itemId) => _db.markItemReady(itemId);

  @override
  Future<void> startPreparing(int itemId, {int? assignedTo}) =>
      _db.startPreparing(itemId, assignedTo: assignedTo);

  @override
  Future<bool> areAllItemsReady(int workOrderId) =>
      _db.areAllItemsReady(workOrderId);

  // ── Statistics & Reporting ────────────────────────────────────────────

  @override
  Future<double> getAveragePrepTime() => _db.getAveragePrepTime();

  @override
  Future<Map<String, int>> getTodayOrderStats() => _db.getTodayOrderStats();

  @override
  Future<Map<String, int>> getOrdersPerStation() => _db.getOrdersPerStation();

  @override
  Future<List<Map<String, dynamic>>> getSlowestItems() =>
      _db.getSlowestItems();

  @override
  Future<Map<int, int>> getOrdersByHour() => _db.getOrdersByHour();

  @override
  Future<Map<String, int>> getQueueDepth() => _db.getQueueDepth();

  @override
  Future<int> estimateWaitTime(int orderId) =>
      _db.estimateWaitTime(orderId);

  // ── Kitchen Stations ──────────────────────────────────────────────────

  @override
  Future<List<KitchenStation>> getActiveStations() =>
      _db.getActiveStations();

  @override
  Stream<List<KitchenStation>> watchStations() => _db.watchStations();

  @override
  Future<String> getStationForCategory(int categoryId) =>
      _db.getStationForCategory(categoryId);

  @override
  Future<List<Map<String, dynamic>>> getAllCategoryStationMappings() =>
      _db.getAllCategoryStationMappings();

  @override
  Future<void> setCategoryStationMapping(int categoryId, int stationId) =>
      _db.setCategoryStationMapping(categoryId, stationId);

  @override
  Future<void> removeCategoryStationMapping(int categoryId) =>
      _db.removeCategoryStationMapping(categoryId);

  @override
  Future<int> createStation({required String name, required String code}) async {
    return _db.into(_db.kitchenStations).insert(
      KitchenStationsCompanion.insert(name: name, code: code),
    );
  }

  @override
  Future<void> deleteStation(int stationId) async {
    await (_db.delete(_db.kitchenStations)
          ..where((s) => s.id.equals(stationId)))
        .go();
  }
}
