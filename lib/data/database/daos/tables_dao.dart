// ---------------------------------------------------------------------------
// TABLES DAO - Restaurant Table and Section Operations
// ---------------------------------------------------------------------------

part of '../database.dart';

extension TablesDao on AppDatabase {
  // -----------------------------------------------------------------------
  // SECTIONS
  // -----------------------------------------------------------------------

  /// Get all active sections
  Future<List<TableSection>> getAllSections() {
    return (select(tableSections)..where((t) => t.isActive.equals(true))).get();
  }

  /// Watch all active sections
  Stream<List<TableSection>> watchAllSections() {
    return (select(
      tableSections,
    )..where((t) => t.isActive.equals(true))).watch();
  }

  /// Create a new section
  Future<int> createSection(String name) {
    return into(
      tableSections,
    ).insert(TableSectionsCompanion.insert(name: name));
  }

  /// Update section
  Future<void> updateSection(int id, String name) {
    return (update(tableSections)..where((t) => t.id.equals(id))).write(
      TableSectionsCompanion(name: Value(name)),
    );
  }

  /// Delete section (validate if empty first)
  Future<void> deleteSection(int id) async {
    // Check if any active tables exist in this section
    final tables =
        await (select(restaurantTables)
              ..where((t) => t.sectionId.equals(id))
              ..where((t) => t.isActive.equals(true)))
            .get();

    if (tables.isNotEmpty) {
      throw Exception('لا يمكن حذف القسم لأنه يحتوي على طاولات نشطة');
    }

    // Soft delete or hard delete? TableSection has isActive but CreateSection uses Insert.
    // Let's check TableSection definition.
    // Assuming hard delete is fine if we check constraints, OR use isActive if it exists.
    // Looking at defined tables earlier:
    // class TableSections extends Table { ... BoolColumn get isActive ... }
    // So soft delete is better.
    await (update(tableSections)..where((t) => t.id.equals(id))).write(
      const TableSectionsCompanion(isActive: Value(false)),
    );
  }

  // -----------------------------------------------------------------------
  // TABLES
  // -----------------------------------------------------------------------

  /// Watch tables for a specific section
  Stream<List<RestaurantTable>> watchTablesBySection(int sectionId) {
    return (select(restaurantTables)
          ..where((t) => t.sectionId.equals(sectionId))
          ..where((t) => t.isActive.equals(true)))
        .watch();
  }

  /// Watch all tables
  Stream<List<RestaurantTable>> watchAllTables() {
    return (select(
      restaurantTables,
    )..where((t) => t.isActive.equals(true))).watch();
  }

  /// Create a new table
  Future<int> createTable({
    required String name,
    int? sectionId,
    int capacity = 4,
  }) {
    return into(restaurantTables).insert(
      RestaurantTablesCompanion.insert(
        name: name,
        sectionId: Value(sectionId),
        capacity: Value(capacity),
      ),
    );
  }

  /// Update table status and refresh timer
  Future<void> updateTableStatus(int tableId, String status) {
    return (update(restaurantTables)..where((t) => t.id.equals(tableId))).write(
      RestaurantTablesCompanion(
        status: Value(status),
        lastStatusAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update table info
  Future<void> updateTableInfo(
    int tableId, {
    String? name,
    int? sectionId,
    int? capacity,
  }) {
    return (update(restaurantTables)..where((t) => t.id.equals(tableId))).write(
      RestaurantTablesCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        sectionId: sectionId != null ? Value(sectionId) : const Value.absent(),
        capacity: capacity != null ? Value(capacity) : const Value.absent(),
      ),
    );
  }

  /// Check if table has order history
  Future<bool> tableHasOrders(int tableId) async {
    final orderCount =
        await (selectOnly(tableOrders)
              ..addColumns([tableOrders.id.count()])
              ..where(tableOrders.tableId.equals(tableId)))
            .map((row) => row.read(tableOrders.id.count())!)
            .getSingle();
    return orderCount > 0;
  }

  /// Delete table (with order history check and soft-delete)
  Future<void> deleteTable(int tableId) async {
    // Check for order history before allowing deletion
    final hasOrders = await tableHasOrders(tableId);
    if (hasOrders) {
      throw Exception(
        'لا يمكن حذف هذه الطاولة - لديها سجل طلبات سابق. يمكنك إلغاء تنشيطها بديلاً عن ذلك.',
      );
    }

    // Soft delete - mark as inactive
    await (update(restaurantTables)..where((t) => t.id.equals(tableId))).write(
      const RestaurantTablesCompanion(isActive: Value(false)),
    );
  }

  // -----------------------------------------------------------------------
  // TABLE ORDERS
  // -----------------------------------------------------------------------

  /// Get active order for a table
  Future<TableOrder?> getActiveOrderForTable(int tableId) {
    return (select(tableOrders)
          ..where((o) => o.tableId.equals(tableId))
          ..where(
            (o) => o.status.equals('open') | o.status.equals('bill_requested'),
          ))
        .getSingleOrNull();
  }

  /// Watch active order for a table
  Stream<TableOrder?> watchActiveOrderForTable(int tableId) {
    return (select(tableOrders)
          ..where((o) => o.tableId.equals(tableId))
          ..where(
            (o) => o.status.equals('open') | o.status.equals('bill_requested'),
          ))
        .watchSingleOrNull();
  }

  /// Create a new table order
  Future<int> createTableOrder(int tableId, {int? userId}) async {
    return transaction(() async {
      // Mark table as occupied
      await updateTableStatus(tableId, 'occupied');

      return into(tableOrders).insert(
        TableOrdersCompanion.insert(
          tableId: tableId,
          userId: Value(userId),
          openedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// Add item to table order
  Future<void> addOrUpdateTableOrderItem({
    required int orderId,
    required int productId,
    required double quantity,
    required double unitPrice,
  }) async {
    return transaction(() async {
      final existing =
          await (select(tableOrderItems)
                ..where((i) => i.tableOrderId.equals(orderId))
                ..where((i) => i.productId.equals(productId)))
              .getSingleOrNull();

      if (existing != null) {
        final newQty = existing.quantity + quantity;
        await (update(
          tableOrderItems,
        )..where((i) => i.id.equals(existing.id))).write(
          TableOrderItemsCompanion(
            quantity: Value(newQty),
            total: Value(newQty * unitPrice),
          ),
        );
      } else {
        await into(tableOrderItems).insert(
          TableOrderItemsCompanion.insert(
            tableOrderId: orderId,
            productId: productId,
            quantity: quantity,
            unitPrice: unitPrice,
            total: quantity * unitPrice,
          ),
        );
      }

      // Update order total
      await _updateTableOrderTotal(orderId);
    });
  }

  /// Remove item from table order by product ID
  Future<void> removeTableOrderItem(int orderId, int productId) async {
    return transaction(() async {
      await (delete(tableOrderItems)
            ..where((i) => i.tableOrderId.equals(orderId))
            ..where((i) => i.productId.equals(productId)))
          .go();

      await _updateTableOrderTotal(orderId);
    });
  }

  /// Remove item from table order by item ID
  Future<void> removeTableOrderItemById(int orderItemId) async {
    return transaction(() async {
      final item = await (select(
        tableOrderItems,
      )..where((i) => i.id.equals(orderItemId))).getSingleOrNull();
      if (item != null) {
        await (delete(
          tableOrderItems,
        )..where((i) => i.id.equals(orderItemId))).go();
        await _updateTableOrderTotal(item.tableOrderId);
      }
    });
  }

  /// Update order total based on items
  Future<void> _updateTableOrderTotal(int orderId) async {
    final items = await (select(
      tableOrderItems,
    )..where((i) => i.tableOrderId.equals(orderId))).get();
    final total = items.fold(0.0, (sum, item) => sum + item.total);

    await (update(tableOrders)..where((o) => o.id.equals(orderId))).write(
      TableOrdersCompanion(total: Value(total)),
    );
  }

  /// Get items for a table order
  Future<List<TableOrderItem>> getTableOrderItems(int orderId) {
    return (select(
      tableOrderItems,
    )..where((i) => i.tableOrderId.equals(orderId))).get();
  }

  /// Close/Cancel table order
  Future<void> closeTableOrder(int orderId, int tableId) async {
    await transaction(() async {
      await (update(tableOrders)..where((o) => o.id.equals(orderId))).write(
        TableOrdersCompanion(
          status: const Value('closed'),
          closedAt: Value(DateTime.now()),
        ),
      );

      await updateTableStatus(tableId, 'available');
    });
  }

  /// Request bill for table.
  ///
  /// طلبُ الفاتورة صفةٌ للطلب لا للطاولة — الطاولةُ تبقى على حالتها الحالية.
  /// كانت هذه الدالّةُ تضع الطاولةَ على `'billing'`، وهي إحدى الحالات
  /// الثمانِ التي شُطبت من مفردات الطاولة في v154؛ تركُها كان يُعيد حالةً
  /// ميتةً إلى الجدول من باب الطباعة. `tableId` لم يعد له مستعملٌ هنا بعد
  /// حذف نداء `updateTableStatus` الوحيد الذي احتاجه.
  Future<void> requestTableBill(int orderId) async {
    await (update(tableOrders)..where((o) => o.id.equals(orderId))).write(
      const TableOrdersCompanion(status: Value('bill_requested')),
    );
  }

  /// Clear all items in a table order
  Future<void> clearTableOrderItems(int orderId) async {
    await transaction(() async {
      await (delete(
        tableOrderItems,
      )..where((i) => i.tableOrderId.equals(orderId))).go();
      await _updateTableOrderTotal(orderId);
    });
  }

  /// Transfer an active order from one table to another
  Future<void> transferTableOrder(int fromTableId, int toTableId) async {
    await transaction(() async {
      // 1. Get active order for source table
      final order = await getActiveOrderForTable(fromTableId);
      if (order == null) {
        throw Exception('No active order found on source table');
      }

      // 2. Check if target table is available
      final targetTable = await (select(
        restaurantTables,
      )..where((t) => t.id.equals(toTableId))).getSingle();
      if (targetTable.status != 'available') {
        throw Exception('Target table is not available');
      }

      // 3. Update order's tableId
      await (update(tableOrders)..where((o) => o.id.equals(order.id))).write(
        TableOrdersCompanion(tableId: Value(toTableId)),
      );

      // 4. Update table statuses
      await updateTableStatus(fromTableId, 'available');
      await updateTableStatus(
        toTableId,
        order.status == 'bill_requested' ? 'billing' : 'occupied',
      );
    });
  }

  /// 3.4: Partial transfer - move specific items (and quantities) from one table order to another
  Future<void> partialTransferTableOrder({
    required int sourceTableId,
    required int targetTableId,
    required Map<int, double> itemQuantities, // Map of itemId -> quantityToMove
  }) async {
    await transaction(() async {
      // 1. Get active order for source table
      final sourceOrder = await getActiveOrderForTable(sourceTableId);
      if (sourceOrder == null) {
        throw Exception('No active order found on source table');
      }

      // 2. Get or create order for target table
      var targetOrder = await getActiveOrderForTable(targetTableId);
      if (targetOrder == null) {
        // Create new order for target table
        final targetOrderId = await into(tableOrders).insert(
          TableOrdersCompanion.insert(
            tableId: targetTableId,
            openedAt: Value(DateTime.now()),
          ),
        );
        targetOrder = await (select(
          tableOrders,
        )..where((o) => o.id.equals(targetOrderId))).getSingle();
        await updateTableStatus(targetTableId, 'occupied');
      }

      // 3. Move/Split selected items to target order
      for (final entry in itemQuantities.entries) {
        final itemId = entry.key;
        final qtyToMove = entry.value;

        final item = await (select(
          tableOrderItems,
        )..where((i) => i.id.equals(itemId))).getSingleOrNull();
        if (item != null &&
            item.tableOrderId == sourceOrder.id &&
            qtyToMove > 0) {
          final double finalQtyToMove = qtyToMove > item.quantity
              ? item.quantity
              : qtyToMove;
          final bool moveFullItem = finalQtyToMove == item.quantity;

          // Check if same product exists in target order
          final existingInTarget =
              await (select(tableOrderItems)
                    ..where((i) => i.tableOrderId.equals(targetOrder!.id))
                    ..where((i) => i.productId.equals(item.productId)))
                  .getSingleOrNull();

          if (existingInTarget != null) {
            // Merge quantities into existing target item
            final newTargetQty = existingInTarget.quantity + finalQtyToMove;
            await (update(
              tableOrderItems,
            )..where((i) => i.id.equals(existingInTarget.id))).write(
              TableOrderItemsCompanion(
                quantity: Value(newTargetQty),
                total: Value(newTargetQty * existingInTarget.unitPrice),
              ),
            );

            if (moveFullItem) {
              await (delete(
                tableOrderItems,
              )..where((i) => i.id.equals(itemId))).go();
            } else {
              // Deduct from source item
              final newSourceQty = item.quantity - finalQtyToMove;
              await (update(
                tableOrderItems,
              )..where((i) => i.id.equals(itemId))).write(
                TableOrderItemsCompanion(
                  quantity: Value(newSourceQty),
                  total: Value(newSourceQty * item.unitPrice),
                ),
              );
            }
          } else {
            if (moveFullItem) {
              // Move full item record to target order
              await (update(
                tableOrderItems,
              )..where((i) => i.id.equals(itemId))).write(
                TableOrderItemsCompanion(tableOrderId: Value(targetOrder.id)),
              );
            } else {
              // Split: Create new item in target, deduct from source
              await into(tableOrderItems).insert(
                TableOrderItemsCompanion.insert(
                  tableOrderId: targetOrder.id,
                  productId: item.productId,
                  quantity: finalQtyToMove,
                  unitPrice: item.unitPrice,
                  total: finalQtyToMove * item.unitPrice,
                ),
              );

              final newSourceQty = item.quantity - finalQtyToMove;
              await (update(
                tableOrderItems,
              )..where((i) => i.id.equals(itemId))).write(
                TableOrderItemsCompanion(
                  quantity: Value(newSourceQty),
                  total: Value(newSourceQty * item.unitPrice),
                ),
              );
            }
          }
        }
      }

      // 4. Update both order totals
      await _updateTableOrderTotal(sourceOrder.id);
      await _updateTableOrderTotal(targetOrder.id);

      // 5. Check if source order has remaining items
      final remainingItems = await getTableOrderItems(sourceOrder.id);
      if (remainingItems.isEmpty) {
        // Close source order and free table
        await closeTableOrder(sourceOrder.id, sourceTableId);
      }
    });
  }

  /// Merge an order from one table into another active order
  Future<void> mergeTableOrders(int sourceTableId, int targetTableId) async {
    return transaction(() async {
      final sourceOrder = await getActiveOrderForTable(sourceTableId);
      final targetOrder = await getActiveOrderForTable(targetTableId);

      if (sourceOrder == null) {
        throw Exception('No active order on source table');
      }
      if (targetOrder == null) {
        throw Exception('No active order on target table');
      }

      final sourceItems = await getTableOrderItems(sourceOrder.id);

      for (final item in sourceItems) {
        // لا بحثَ عن متشابهٍ في الهدف ولا جمعَ كميّات: البندُ يُنقل كما هو
        // موسوماً بمصدره. جمعُ الكميّات يمحو أصلَ الصنف فيسقط فكُّ الدمج
        // والطباعةُ المجمَّعة ونسبةُ الصنف إلى نادله.
        await (update(tableOrderItems)..where((i) => i.id.equals(item.id)))
            .write(TableOrderItemsCompanion(
          tableOrderId: Value(targetOrder.id),
          sourceTableOrderId: Value(item.sourceTableOrderId ?? sourceOrder.id),
        ));
      }

      // Mark source order as merged
      await (update(
        tableOrders,
      )..where((o) => o.id.equals(sourceOrder.id))).write(
        TableOrdersCompanion(
          status: const Value('closed'),
          mergedToId: Value(targetOrder.id),
          closedAt: Value(DateTime.now()),
        ),
      );

      // Update both totals
      await _updateTableOrderTotal(sourceOrder.id); // Should be 0
      await _updateTableOrderTotal(targetOrder.id);

      // Release source table
      await updateTableStatus(sourceTableId, 'available');
    });
  }

  // ---------------------------------------------------------------------------
  // RESERVATION METHODS
  // ---------------------------------------------------------------------------

  /// Watch all reservations for a specific table
  Stream<List<TableReservation>> watchReservationsForTable(int tableId) {
    return (select(tableReservations)
          ..where((r) => r.tableId.equals(tableId))
          ..where((r) => r.status.isIn(['pending', 'confirmed']))
          ..orderBy([(r) => OrderingTerm.asc(r.reservationTime)]))
        .watch();
  }

  /// Watch all pending/confirmed reservations
  Stream<List<TableReservation>> watchActiveReservations() {
    return (select(tableReservations)
          ..where((r) => r.status.isIn(['pending', 'confirmed']))
          ..orderBy([(r) => OrderingTerm.asc(r.reservationTime)]))
        .watch();
  }

  /// Watch today's reservations
  Stream<List<TableReservation>> watchTodayReservations() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(tableReservations)
          ..where(
            (r) => r.reservationTime.isBiggerOrEqual(Variable(startOfDay)),
          )
          ..where((r) => r.reservationTime.isSmallerThan(Variable(endOfDay)))
          ..orderBy([(r) => OrderingTerm.asc(r.reservationTime)]))
        .watch();
  }

  /// Create a new reservation
  Future<int> createReservation({
    required int tableId,
    required String customerName,
    String? customerPhone,
    required DateTime reservationTime,
    int partySize = 2,
    String? notes,
  }) async {
    return transaction(() async {
      // Update table status to reserved
      await updateTableStatus(tableId, 'reserved');

      return into(tableReservations).insert(
        TableReservationsCompanion.insert(
          tableId: tableId,
          customerName: customerName,
          customerPhone: Value(customerPhone),
          reservationTime: reservationTime,
          partySize: Value(partySize),
          notes: Value(notes),
          status: const Value('pending'),
        ),
      );
    });
  }

  /// Update reservation status
  Future<void> updateReservationStatus(int reservationId, String status) async {
    await (update(tableReservations)..where((r) => r.id.equals(reservationId)))
        .write(TableReservationsCompanion(status: Value(status)));
  }

  /// Cancel a reservation and free the table
  Future<void> cancelReservation(int reservationId) async {
    return transaction(() async {
      final reservation = await (select(
        tableReservations,
      )..where((r) => r.id.equals(reservationId))).getSingle();

      // Update reservation status
      await updateReservationStatus(reservationId, 'cancelled');

      // Check if table has other reservations, if not make it available
      final otherReservations =
          await (select(tableReservations)
                ..where((r) => r.tableId.equals(reservation.tableId))
                ..where((r) => r.id.equals(reservationId).not())
                ..where((r) => r.status.isIn(['pending', 'confirmed'])))
              .get();

      if (otherReservations.isEmpty) {
        await updateTableStatus(reservation.tableId, 'available');
      }
    });
  }

  /// Seat guests from a reservation (mark as seated and open order)
  Future<int> seatReservation(int reservationId, {int? userId}) async {
    return transaction(() async {
      final reservation = await (select(
        tableReservations,
      )..where((r) => r.id.equals(reservationId))).getSingle();

      // Update reservation status to seated
      await updateReservationStatus(reservationId, 'seated');

      // Create a table order (which marks table as occupied)
      return createTableOrder(reservation.tableId, userId: userId);
    });
  }

  /// Get active reservation for a table (if any)
  Future<TableReservation?> getActiveReservationForTable(int tableId) {
    return (select(tableReservations)
          ..where((r) => r.tableId.equals(tableId))
          ..where((r) => r.status.isIn(['pending', 'confirmed']))
          ..orderBy([(r) => OrderingTerm.asc(r.reservationTime)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Delete a reservation
  Future<void> deleteReservation(int reservationId) async {
    await (delete(
      tableReservations,
    )..where((r) => r.id.equals(reservationId))).go();
  }
}
