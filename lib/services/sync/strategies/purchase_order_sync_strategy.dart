// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class PurchaseOrderSyncStrategy extends SyncStrategy {
  PurchaseOrderSyncStrategy(super.db);

  @override
  String get tableName => 'purchase_orders';

  @override
  String get apiEndpoint => '/api/purchase-orders';

  /// R5 — purchase order lifecycle (pending → received → invoiced /
  /// cancelled) is mutable and server-authoritative. `serverWins` is
  /// intentional, mirroring sales_order strategy.
  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.serverWins;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final orders = json['purchase_orders'] as List? ?? [];
    for (final o in orders) {
      await _syncSingleOrder(o as Map<String, dynamic>);
    }
    if (orders.isNotEmpty) {
      db.markTablesUpdated({db.purchaseOrders, db.purchaseOrderItems});
      debugPrint('[Sync] PurchaseOrders: ${orders.length} synced');
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  Future<void> _syncSingleOrder(Map<String, dynamic> map) async {
    final serverId = parseInt(map['id']);

    try {
      await db.transaction(() async {
        final existing = await (db.select(db.purchaseOrders)
          ..where((o) => o.id.equals(serverId))
          ..limit(1)
        ).getSingleOrNull();

        if (existing != null) {
          // Update mutable fields
          await (db.update(db.purchaseOrders)
            ..where((o) => o.id.equals(serverId))
          ).write(PurchaseOrdersCompanion(
            status: Value(map['status'] as String? ?? existing.status),
            convertedToInvoiceId: Value(parseIntNullable(map['convertedToInvoiceId'])),
          ));

          // Feature 006 #7: UPSERT + diff-delete on item id instead of the
          // previous wipe-and-reinsert. Closes the race where a local
          // change to one item briefly disappeared while the snapshot
          // refreshed. Snapshot is still authoritative — items absent
          // from it are deleted, scoped to this orderId.
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
              context: 'purchase_order_items order=$serverId (update path)',
            );
            await db.into(db.purchaseOrderItems).insertOnConflictUpdate(
              PurchaseOrderItemsCompanion(
                id: Value(itemId),
                orderId: Value(serverId),
                productId: Value(localProductId),
                quantity: Value(parseDouble(itemMap['quantity'])),
                unitCost: Value(parseDouble(itemMap['unitCost'])),
                discount: Value(parseDouble(itemMap['discount'])),
                total: Value(parseDouble(itemMap['total'])),
                receivedQuantity: Value(parseDouble(itemMap['receivedQuantity'])),
                taxRate: Value(parseDouble(itemMap['taxRate'])),
                taxAmount: Value(parseDouble(itemMap['taxAmount'])),
                notes: Value(itemMap['notes'] as String?),
              ),
            );
          }
          final localItems = await (db.select(db.purchaseOrderItems)
            ..where((i) => i.orderId.equals(serverId))
          ).get();
          for (final local in localItems) {
            if (!serverItemIds.contains(local.id)) {
              await (db.delete(db.purchaseOrderItems)
                    ..where((i) => i.id.equals(local.id))).go();
            }
          }
          return;
        }

        // New order — insert header + items
        await db.into(db.purchaseOrders).insertOnConflictUpdate(
          PurchaseOrdersCompanion(
            id: Value(serverId),
            orderNumber: Value(map['orderNumber'] as String? ?? 'PO-$serverId'),
            supplierId: Value(parseInt(map['supplierId'])),
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
            context: 'purchase_order_items order=$serverId (insert path)',
          );
          await db.into(db.purchaseOrderItems).insertOnConflictUpdate(
            PurchaseOrderItemsCompanion(
              id: Value(parseInt(itemMap['id'])),
              orderId: Value(serverId),
              productId: Value(localProductId),
              quantity: Value(parseDouble(itemMap['quantity'])),
              unitCost: Value(parseDouble(itemMap['unitCost'])),
              discount: Value(parseDouble(itemMap['discount'])),
              total: Value(parseDouble(itemMap['total'])),
              receivedQuantity: Value(parseDouble(itemMap['receivedQuantity'])),
              taxRate: Value(parseDouble(itemMap['taxRate'])),
              taxAmount: Value(parseDouble(itemMap['taxAmount'])),
              notes: Value(itemMap['notes'] as String?),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('[Sync] Error in PurchaseOrderSyncStrategy: $e');
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is PurchaseOrdersCompanion) {
      await db.into(db.purchaseOrders).insertOnConflictUpdate(record);
    }
  }
}