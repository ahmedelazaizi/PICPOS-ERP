// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class SalesOrderSyncStrategy extends SyncStrategy {
  SalesOrderSyncStrategy(super.db);

  @override
  String get tableName => 'sales_orders';

  @override
  String get apiEndpoint => '/api/sales-orders';

  /// R5 / SYNC_ARCHITECTURE §3.2 — sales orders are transactional but
  /// their *status* (pending → confirmed → invoiced → cancelled) is
  /// mutable, and the server is authoritative on which lifecycle stage
  /// applies. `serverWins` is intentional: local optimistic edits to
  /// status should be overwritten by the server's truth.
  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.serverWins;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final orders = json['sales_orders'] as List? ?? [];
    for (final o in orders) {
      await _syncSingleOrder(o as Map<String, dynamic>);
    }
    if (orders.isNotEmpty) {
      db.markTablesUpdated({db.salesOrders, db.salesOrderItems});
      debugPrint('[Sync] SalesOrders: ${orders.length} synced');
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  Future<void> _syncSingleOrder(Map<String, dynamic> map) async {
    final serverId = parseInt(map['id']);

    try {
      await db.transaction(() async {
        final existing = await (db.select(db.salesOrders)
          ..where((o) => o.id.equals(serverId))
          ..limit(1)
        ).getSingleOrNull();

        if (existing != null) {
          // Update mutable fields
          await (db.update(db.salesOrders)
            ..where((o) => o.id.equals(serverId))
          ).write(SalesOrdersCompanion(
            status: Value(map['status'] as String? ?? existing.status),
            convertedToInvoiceId: Value(parseIntNullable(map['convertedToInvoiceId'])),
          ));

          // Feature 006 #7: UPSERT + diff-delete on item id instead of the
          // previous wipe-and-reinsert. Same race fix as the purchase
          // order strategy — snapshot is still authoritative for this order.
          final items = map['items'] as List? ?? [];
          final serverItemIds = <int>{};
          for (final item in items) {
            final itemMap = item as Map<String, dynamic>;
            final itemId = parseInt(itemMap['id']);
            serverItemIds.add(itemId);
            // Issue 11 (Feature 018): remap server productId → local id.
            final localProductId = await db.resolveItemFk(
              'products',
              parseInt(itemMap['productId']),
              context: 'sales_order_items order=$serverId',
            );
            await db.into(db.salesOrderItems).insertOnConflictUpdate(
              SalesOrderItemsCompanion(
                id: Value(itemId),
                orderId: Value(serverId),
                productId: Value(localProductId),
                quantity: Value(parseDouble(itemMap['quantity'])),
                unitPrice: Value(parseDouble(itemMap['unitPrice'])),
                discount: Value(parseDouble(itemMap['discount'])),
                total: Value(parseDouble(itemMap['total'])),
                deliveredQuantity: Value(parseDouble(itemMap['deliveredQuantity'])),
                taxRate: Value(parseDouble(itemMap['taxRate'])),
                taxAmount: Value(parseDouble(itemMap['taxAmount'])),
                notes: Value(itemMap['notes'] as String?),
              ),
            );
          }
          final localItems = await (db.select(db.salesOrderItems)
            ..where((i) => i.orderId.equals(serverId))
          ).get();
          for (final local in localItems) {
            if (!serverItemIds.contains(local.id)) {
              await (db.delete(db.salesOrderItems)
                    ..where((i) => i.id.equals(local.id))).go();
            }
          }
          return;
        }

        // New order — insert header + items
        await db.into(db.salesOrders).insertOnConflictUpdate(
          SalesOrdersCompanion(
            id: Value(serverId),
            orderNumber: Value(map['orderNumber'] as String? ?? 'SO-$serverId'),
            customerId: Value(parseIntNullable(map['customerId'])),
            warehouseId: Value(parseInt(map['warehouseId'], 1)),
            orderDate: Value(DateTime.tryParse(map['orderDate']?.toString() ?? '') ?? DateTime.now()),
            expectedDate: Value(DateTime.tryParse(map['expectedDate']?.toString() ?? '')),
            subtotal: Value(parseDouble(map['subtotal'])),
            discount: Value(parseDouble(map['discount'])),
            tax: Value(parseDouble(map['tax'])),
            total: Value(parseDouble(map['total'])),
            status: Value(map['status'] as String? ?? 'draft'),
            notes: Value(map['notes'] as String?),
            costCenterId: Value(parseIntNullable(map['costCenterId'])),
            convertedToInvoiceId: Value(parseIntNullable(map['convertedToInvoiceId'])),
            createdAt: Value(DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now()),
          ),
        );

        final items = map['items'] as List? ?? [];
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          // Issue 11 (Feature 018): remap server productId → local id.
          final localProductId = await db.resolveItemFk(
            'products',
            parseInt(itemMap['productId']),
            context: 'sales_order_items order=$serverId',
          );
          await db.into(db.salesOrderItems).insertOnConflictUpdate(
            SalesOrderItemsCompanion(
              id: Value(parseInt(itemMap['id'])),
              orderId: Value(serverId),
              productId: Value(localProductId),
              quantity: Value(parseDouble(itemMap['quantity'])),
              unitPrice: Value(parseDouble(itemMap['unitPrice'])),
              discount: Value(parseDouble(itemMap['discount'])),
              total: Value(parseDouble(itemMap['total'])),
              deliveredQuantity: Value(parseDouble(itemMap['deliveredQuantity'])),
              taxRate: Value(parseDouble(itemMap['taxRate'])),
              taxAmount: Value(parseDouble(itemMap['taxAmount'])),
              notes: Value(itemMap['notes'] as String?),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('[Sync] Error in SalesOrderSyncStrategy: $e');
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is SalesOrdersCompanion) {
      await db.into(db.salesOrders).insertOnConflictUpdate(record);
    }
  }
}