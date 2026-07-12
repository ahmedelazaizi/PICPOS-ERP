// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class SalesHeldOrderItemsSyncStrategy extends SyncStrategy {
  SalesHeldOrderItemsSyncStrategy(super.db);

  @override
  String get tableName => 'held_order_items';

  @override
  String get apiEndpoint => '/api/sales/held-items';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final items = json['held_order_items'] as List;
    for (final b in items) {
      try {
        // Issue 11 (Feature 018): remap server productId → local id.
        final localProductId = await db.resolveItemFk(
          'products',
          parseInt(b['productId']),
          context: 'held_order_items held=${b['heldOrderId']}',
        );
        await db.into(db.heldOrderItems).insertOnConflictUpdate(
          HeldOrderItemsCompanion(
            id: Value(parseInt(b['id'])),
            heldOrderId: Value(parseInt(b['heldOrderId'])),
            productId: Value(localProductId),
            quantity: Value(parseDouble(b['quantity'])),
            unitPrice: Value(parseDouble(b['unitPrice'])),
            customPrice: Value(b['customPrice'] != null ? parseDouble(b['customPrice']) : null),
            note: Value(b['note'] as String?),
          ),
        );
      } catch (e) {
        debugPrint('[Sync] ⚠️ Error syncing held_order_item syncFromJson: $e');
      }
    }
    // Force UI refresh after sync
    if (items.isNotEmpty) {
      db.markTablesUpdated({db.heldOrderItems});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Snapshot sync
  }

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.heldOrderItems).insertOnConflictUpdate(record as HeldOrderItemsCompanion);
  }
}