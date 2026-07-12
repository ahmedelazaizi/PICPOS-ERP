part of '../database.dart';

// ---------------------------------------------------------------------------
// KITCHEN DAO (Kitchen Display System Operations)
// ---------------------------------------------------------------------------

extension KitchenDao on AppDatabase {
  // ---------------------------------------------------------------------------
  // WORK ORDER CRUD
  // ---------------------------------------------------------------------------

  /// Create a new work order with items
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
  }) async {
    return transaction(() async {
      // Insert work order
      final workOrderId = await into(workOrders).insert(
        WorkOrdersCompanion.insert(
          orderNumber: orderNumber,
          station: Value(station),
          priority: Value(priority),
          tableOrderId: Value(tableOrderId),
          invoiceId: Value(invoiceId),
          customerName: Value(customerName),
          notes: Value(notes),
          createdBy: Value(createdBy),
        ),
      );

      // Insert work order items
      for (final item in items) {
        await into(workOrderItems).insert(
          WorkOrderItemsCompanion.insert(
            workOrderId: workOrderId,
            productId: item.productId,
            productName: item.productName,
            quantity: item.quantity,
            notes: Value(item.notes),
          ),
        );
      }

      return workOrderId;
    });
  }

  /// Generate next order number
  Future<String> generateWorkOrderNumber() async {
    final now = DateTime.now();
    final prefix = 'WO${now.day.toString().padLeft(2, '0')}';

    // Get count of orders today
    final today = DateTime(now.year, now.month, now.day);
    final count =
        await (selectOnly(workOrders)
              ..addColumns([workOrders.id.count()])
              ..where(workOrders.createdAt.isBiggerOrEqual(Variable(today))))
            .map((row) => row.read(workOrders.id.count()) ?? 0)
            .getSingle();

    return '$prefix-${(count + 1).toString().padLeft(3, '0')}';
  }

  // ---------------------------------------------------------------------------
  // WATCH STREAMS (for real-time KDS display)
  // ---------------------------------------------------------------------------

  /// Watch all pending orders (for KDS main display)
  Stream<List<WorkOrder>> watchPendingOrders() {
    return (select(workOrders)
          ..where((o) => o.status.isIn(['pending', 'preparing']))
          ..orderBy([
            // Cluster 030 / Bug B: PostgreSQL rejects `CAST(boolean AS
            // bigint)` (which Drift emits for `.equals(...).cast<int>()`).
            // Use a portable CASE WHEN expression that works on both
            // SQLite and PG so the KDS query stops crashing on the server.
            (o) => OrderingTerm(
              expression: const CustomExpression<int>(
                  "CASE WHEN priority = 'urgent' THEN 1 ELSE 0 END"),
              mode: OrderingMode.desc,
            ),
            (o) => OrderingTerm.asc(o.createdAt),
          ]))
        .watch();
  }

  /// Watch orders that are ready (for POS/waiter notification)
  Stream<List<WorkOrder>> watchReadyOrders() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    return (select(workOrders)
          ..where((o) => o.status.equals('ready'))
          ..where((o) => o.createdAt.isBiggerOrEqualValue(startOfDay))
          ..orderBy([(o) => OrderingTerm.desc(o.preparedAt)]))
        .watch();
  }

  /// Watch orders by station
  Stream<List<WorkOrder>> watchOrdersByStation(String station) {
    return (select(workOrders)
          ..where((o) => o.status.isIn(['pending', 'preparing']))
          ..where((o) => o.station.equals(station))
          ..orderBy([
            // Cluster 030 / Bug B: PostgreSQL rejects `CAST(boolean AS
            // bigint)` (which Drift emits for `.equals(...).cast<int>()`).
            // Use a portable CASE WHEN expression that works on both
            // SQLite and PG so the KDS query stops crashing on the server.
            (o) => OrderingTerm(
              expression: const CustomExpression<int>(
                  "CASE WHEN priority = 'urgent' THEN 1 ELSE 0 END"),
              mode: OrderingMode.desc,
            ),
            (o) => OrderingTerm.asc(o.createdAt),
          ]))
        .watch();
  }

  /// Watch order items for a work order
  Stream<List<WorkOrderItem>> watchOrderItems(int workOrderId) {
    return (select(
      workOrderItems,
    )..where((i) => i.workOrderId.equals(workOrderId))).watch();
  }

  // ---------------------------------------------------------------------------
  // STATUS UPDATES
  // ---------------------------------------------------------------------------

  /// Update work order status
  Future<void> updateWorkOrderStatus(int orderId, String newStatus) async {
    final updateData = WorkOrdersCompanion(
      status: Value(newStatus),
      preparedAt: newStatus == 'ready'
          ? Value(DateTime.now())
          : const Value.absent(),
      servedAt: newStatus == 'served'
          ? Value(DateTime.now())
          : const Value.absent(),
    );

    await (update(
      workOrders,
    )..where((o) => o.id.equals(orderId))).write(updateData);
  }

  /// Mark single item as ready
  Future<void> markItemReady(int itemId) async {
    await (update(workOrderItems)..where((i) => i.id.equals(itemId))).write(
      WorkOrderItemsCompanion(
        status: const Value('ready'),
        completedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Start preparing an item
  Future<void> startPreparing(int itemId, {int? assignedTo}) async {
    await (update(workOrderItems)..where((i) => i.id.equals(itemId))).write(
      WorkOrderItemsCompanion(
        status: const Value('preparing'),
        startedAt: Value(DateTime.now()),
        assignedTo: Value(assignedTo),
      ),
    );
  }

  /// Check if all items in order are ready
  Future<bool> areAllItemsReady(int workOrderId) async {
    final pendingCount =
        await (selectOnly(workOrderItems)
              ..addColumns([workOrderItems.id.count()])
              ..where(workOrderItems.workOrderId.equals(workOrderId))
              ..where(workOrderItems.status.isNotIn(['ready'])))
            .map((row) => row.read(workOrderItems.id.count()) ?? 0)
            .getSingle();

    return pendingCount == 0;
  }

  // ---------------------------------------------------------------------------
  // STATISTICS & REPORTING
  // ---------------------------------------------------------------------------

  /// Get average preparation time (in minutes)
  Future<double> getAveragePrepTime() async {
    final recentOrders =
        await (select(workOrders)
              ..where((o) => o.status.equals('served'))
              ..where((o) => o.preparedAt.isNotNull())
              ..orderBy([(o) => OrderingTerm.desc(o.createdAt)])
              ..limit(50))
            .get();

    if (recentOrders.isEmpty) return 0;

    double totalMinutes = 0;
    int count = 0;
    for (final order in recentOrders) {
      if (order.preparedAt != null) {
        final diff = order.preparedAt!.difference(order.createdAt).inMinutes;
        totalMinutes += diff;
        count++;
      }
    }

    return count > 0 ? totalMinutes / count : 0;
  }

  /// Get orders count by status for today
  Future<Map<String, int>> getTodayOrderStats() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final orders = await (select(
      workOrders,
    )..where((o) => o.createdAt.isBiggerOrEqual(Variable(startOfDay)))).get();

    final stats = <String, int>{
      'pending': 0,
      'preparing': 0,
      'ready': 0,
      'served': 0,
      'cancelled': 0,
    };

    for (final order in orders) {
      stats[order.status] = (stats[order.status] ?? 0) + 1;
    }

    return stats;
  }

  // ---------------------------------------------------------------------------
  // KITCHEN STATIONS
  // ---------------------------------------------------------------------------

  /// Get today's orders count per station
  Future<Map<String, int>> getOrdersPerStation() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final orders = await (select(workOrders)
          ..where((o) => o.createdAt.isBiggerOrEqual(Variable(startOfDay))))
        .get();

    final perStation = <String, int>{};
    for (final order in orders) {
      perStation[order.station] = (perStation[order.station] ?? 0) + 1;
    }
    return perStation;
  }

  /// Get slowest items by average preparation time (top 10)
  Future<List<Map<String, dynamic>>> getSlowestItems() async {
    final results = await customSelect('''
      SELECT woi.product_name, 
             AVG(
               CASE WHEN woi.completed_at IS NOT NULL AND woi.started_at IS NOT NULL
               THEN (julianday(woi.completed_at) - julianday(woi.started_at)) * 1440
               ELSE NULL END
             ) as avg_minutes,
             COUNT(*) as total_count
      FROM work_order_items woi
      WHERE woi.completed_at IS NOT NULL
      GROUP BY woi.product_name
      HAVING AVG(
        CASE WHEN woi.completed_at IS NOT NULL AND woi.started_at IS NOT NULL
        THEN (julianday(woi.completed_at) - julianday(woi.started_at)) * 1440
        ELSE NULL END
      ) IS NOT NULL
      ORDER BY avg_minutes DESC
      LIMIT 10
    ''').get();

    return results.map((row) => {
      'name': row.read<String>('product_name'),
      'avgMinutes': row.read<double>('avg_minutes'),
      'count': row.read<int>('total_count'),
    }).toList();
  }

  /// Get today's order distribution by hour (for peak hours chart)
  Future<Map<int, int>> getOrdersByHour() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final orders = await (select(workOrders)
          ..where((o) => o.createdAt.isBiggerOrEqual(Variable(startOfDay))))
        .get();

    final byHour = <int, int>{};
    for (final order in orders) {
      final hour = order.createdAt.hour;
      byHour[hour] = (byHour[hour] ?? 0) + 1;
    }
    return byHour;
  }

  /// Get queue depth (count of pending+preparing orders) per station
  Future<Map<String, int>> getQueueDepth() async {
    final orders = await (select(workOrders)
          ..where((o) => o.status.isIn(['pending', 'preparing'])))
        .get();

    final queueMap = <String, int>{};
    for (final order in orders) {
      queueMap[order.station] = (queueMap[order.station] ?? 0) + 1;
    }
    return queueMap;
  }

  /// Estimate wait time for a given order (in minutes)
  /// Based on: avg prep time × number of orders ahead of this one in the same station
  Future<int> estimateWaitTime(int orderId) async {
    final order = await (select(workOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingleOrNull();
    if (order == null) return 0;

    // Count orders ahead (same station, created before this one, still pending/preparing)
    final ordersAhead = await (select(workOrders)
          ..where((o) => o.station.equals(order.station))
          ..where((o) => o.status.isIn(['pending', 'preparing']))
          ..where((o) => o.createdAt.isSmallerThanValue(order.createdAt)))
        .get();

    final avgPrepTime = await getAveragePrepTime();
    final avg = avgPrepTime > 0 ? avgPrepTime : 10.0; // default 10 min if no data
    return ((ordersAhead.length + 1) * avg).ceil();
  }

  /// Get all active kitchen stations
  Future<List<KitchenStation>> getActiveStations() async {
    return (select(kitchenStations)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm.asc(s.displayOrder)]))
        .get();
  }

  /// Watch kitchen stations
  Stream<List<KitchenStation>> watchStations() {
    return (select(kitchenStations)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm.asc(s.displayOrder)]))
        .watch();
  }

  // ---------------------------------------------------------------------------
  // CATEGORY → STATION MAPPING (Raw SQL — table not in Drift annotation)
  // ---------------------------------------------------------------------------

  /// Get the station code for a product category (returns 'kitchen' as default)
  Future<String> getStationForCategory(int categoryId) async {
    final result = await customSelect(
      'SELECT ks.code FROM category_station_mappings csm '
      'JOIN kitchen_stations ks ON ks.id = csm.station_id '
      'WHERE csm.category_id = ?',
      variables: [Variable.withInt(categoryId)],
    ).getSingleOrNull();
    return result?.read<String>('code') ?? 'kitchen';
  }

  /// Get all category-to-station mappings (for settings UI)
  Future<List<Map<String, dynamic>>> getAllCategoryStationMappings() async {
    final result = await customSelect(
      'SELECT csm.id, csm.category_id, csm.station_id FROM category_station_mappings csm',
    ).get();
    return result.map((r) => {
      'id': r.read<int>('id'),
      'categoryId': r.read<int>('category_id'),
      'stationId': r.read<int>('station_id'),
    }).toList();
  }

  /// Set a category → station mapping (upsert)
  Future<void> setCategoryStationMapping(int categoryId, int stationId) async {
    // Remove existing mapping for this category
    await customStatement(
      'DELETE FROM category_station_mappings WHERE category_id = ?',
      [Variable.withInt(categoryId)],
    );
    // Insert new mapping
    await customStatement(
      'INSERT INTO category_station_mappings (category_id, station_id) VALUES (?, ?)',
      [Variable.withInt(categoryId), Variable.withInt(stationId)],
    );
  }

  /// Remove a category → station mapping
  Future<void> removeCategoryStationMapping(int categoryId) async {
    await customStatement(
      'DELETE FROM category_station_mappings WHERE category_id = ?',
      [Variable.withInt(categoryId)],
    );
  }

}

// ---------------------------------------------------------------------------
// DATA CLASSES
// ---------------------------------------------------------------------------

/// Data class for creating work order items
class WorkOrderItemData {
  final int productId;
  final String productName;
  final double quantity;
  final String? notes;

  WorkOrderItemData({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.notes,
  });
}
