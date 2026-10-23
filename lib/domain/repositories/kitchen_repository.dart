import 'package:picpos_erp/data/database/database.dart';

/// Repository interface for Kitchen Display System (KDS) operations.
///
/// Abstracts the `KitchenDao` extension to follow Clean Architecture.
abstract class KitchenRepository {
  // ── Work Order CRUD ───────────────────────────────────────────────────

  /// Create a new work order with items.
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
  });

  /// Generate next order number.
  Future<String> generateWorkOrderNumber();

  // ── Watch Streams (real-time KDS display) ─────────────────────────────

  /// Watch all pending orders (for KDS main display).
  Stream<List<WorkOrder>> watchPendingOrders();

  /// Watch orders that are ready (for POS/waiter notification).
  Stream<List<WorkOrder>> watchReadyOrders();

  /// Watch orders by station.
  Stream<List<WorkOrder>> watchOrdersByStation(String station);

  /// Watch order items for a work order.
  Stream<List<WorkOrderItem>> watchOrderItems(int workOrderId);

  // ── Status Updates ────────────────────────────────────────────────────

  /// Update work order status.
  Future<void> updateWorkOrderStatus(int orderId, String newStatus);

  /// Mark single item as ready.
  Future<void> markItemReady(int itemId);

  /// Start preparing an item.
  Future<void> startPreparing(int itemId, {int? assignedTo});

  /// Check if all items in order are ready.
  Future<bool> areAllItemsReady(int workOrderId);

  // ── Statistics & Reporting ────────────────────────────────────────────

  /// Get average preparation time (in minutes).
  Future<double> getAveragePrepTime();

  /// Get orders count by status for today.
  Future<Map<String, int>> getTodayOrderStats();

  /// Get today's orders count per station.
  Future<Map<String, int>> getOrdersPerStation();

  /// Get slowest items by average preparation time (top 10).
  Future<List<Map<String, dynamic>>> getSlowestItems();

  /// Get today's order distribution by hour.
  Future<Map<int, int>> getOrdersByHour();

  /// Get queue depth per station.
  Future<Map<String, int>> getQueueDepth();

  /// Estimate wait time for a given order (in minutes).
  Future<int> estimateWaitTime(int orderId);

  // ── Kitchen Stations ──────────────────────────────────────────────────

  /// Get all active kitchen stations.
  Future<List<KitchenStation>> getActiveStations();

  /// Watch kitchen stations.
  Stream<List<KitchenStation>> watchStations();

  /// Get the station code for a product category.
  Future<String> getStationForCategory(int categoryId);

  /// Get all category-to-station mappings.
  Future<List<Map<String, dynamic>>> getAllCategoryStationMappings();

  /// Set a category → station mapping (upsert).
  Future<void> setCategoryStationMapping(int categoryId, int stationId);

  /// Remove a category → station mapping.
  Future<void> removeCategoryStationMapping(int categoryId);

  /// Create a new kitchen station.
  Future<int> createStation({required String name, required String code});

  /// Delete a kitchen station by ID.
  Future<void> deleteStation(int stationId);
}
