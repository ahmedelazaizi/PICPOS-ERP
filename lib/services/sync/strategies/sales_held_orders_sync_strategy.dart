// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class SalesHeldOrdersSyncStrategy extends SyncStrategy {
  SalesHeldOrdersSyncStrategy(super.db);

  @override
  String get tableName => 'held_orders';

  @override
  String get apiEndpoint => '/api/sales/held';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final orders = json['held_orders'] as List;
    for (final b in orders) {
      try {
        await db.into(db.heldOrders).insertOnConflictUpdate(
          HeldOrdersCompanion(
            id: Value(parseInt(b['id'])),
            holdNumber: Value(b['holdNumber'] as String? ?? 'HOLD-${b['id']}'),
            subtotal: Value(parseDouble(b['subtotal'])),
            discount: Value(parseDouble(b['discount'])),
            discountIsPercent: Value(b['discountIsPercent'] == true || b['discountIsPercent'] == 'true'),
            note: Value(b['note'] as String?),
            userId: Value(parseIntNullable(b['userId'])),
            customerId: Value(parseIntNullable(b['customerId'])),
            customerName: Value(b['customerName'] as String?),
            createdAt: Value(DateTime.parse(b['createdAt'] as String)),
          ),
        );
      } catch (e) {
        debugPrint('[Sync] ⚠️ Error syncing held_order syncFromJson: $e');
      }
    }
    // Force UI refresh after sync
    if (orders.isNotEmpty) {
      db.markTablesUpdated({db.heldOrders});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Using Snapshot sync
  }

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.heldOrders).insertOnConflictUpdate(record as HeldOrdersCompanion);
  }
}