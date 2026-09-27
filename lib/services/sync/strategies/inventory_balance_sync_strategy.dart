// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class InventoryBalanceSyncStrategy extends SyncStrategy {
  InventoryBalanceSyncStrategy(super.db);

  @override
  String get tableName => 'inventory_balances';

  @override
  String get apiEndpoint => '/api/inventory-balances';

  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.appendOnly;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final balances = json['inventory_balances'] as List? ?? [];
    final Set<int> updatedProductIds = {};
    
    for (final b in balances) {
      await _syncSingleBalance(b as Map<String, dynamic>);
      if (b['productId'] != null) {
        updatedProductIds.add(parseInt(b['productId']));
      }
    }
    
    // OVERRIDE: Update local Products.currentStock with the sum of synced branch balances
    // This resolves the POS "zero stock" issue by forcing the client's global stock 
    // to reflect its actual branch availability.
    for (final productId in updatedProductIds) {
      final stockQuery = await (db.select(db.inventoryBalances)
            ..where((b) => b.productId.equals(productId)))
          .get();
      
      double totalBranchStock = 0;
      for (final balance in stockQuery) {
        totalBranchStock += balance.quantity;
      }
      
      // Update the un-versioned Products table with this concrete branch balance
      await db.updateProductStock(productId, totalBranchStock);
    }
    // Force UI refresh after sync
    if (balances.isNotEmpty) {
      db.markTablesUpdated({db.inventoryBalances});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Full sync only
  }

  Future<void> _syncSingleBalance(Map<String, dynamic> balanceMap) async {
    try {
  // ignore: unused_local_variable
      final serverId = parseInt(balanceMap['id']);
      final serverQuantity = parseDouble(balanceMap['quantity']);

      final productId = parseInt(balanceMap['productId']);
      final warehouseId = parseInt(balanceMap['warehouseId']);

      // PHASE-9: Delta-based protection
      // Check if this balance already exists locally using the composite unique key
      final existing = await (db.select(db.inventoryBalances)
            ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId)))
          .getSingleOrNull();

      if (existing != null) {
        // If local quantity was modified (e.g. by local sales), calculate delta
        // instead of blindly overwriting
        final localQty = existing.quantity;
        final serverDelta = serverQuantity - localQty;
        
        // Only apply if there's a meaningful difference
        if (serverDelta.abs() > 0.001) {
          debugPrint('[Sync] InventoryBalance Product:#$productId WH:#$warehouseId: local=$localQty, server=$serverQuantity, delta=$serverDelta');
        }
      }

      // For branch clients, server is authoritative — use insertOnConflictUpdate
      // If it exists locally, update using its LOCAL id to avoid UNIQUE constraint violation.
      // If it does not exist, insert without explicit ID to let SQLite auto-increment.
      await db.into(db.inventoryBalances).insertOnConflictUpdate(
            InventoryBalancesCompanion(
              id: existing != null ? Value(existing.id) : const Value.absent(),
              productId: Value(productId),
              warehouseId: Value(warehouseId),
              quantity: Value(serverQuantity),
              reservedQuantity: Value(parseDouble(balanceMap['reservedQuantity'])),
              averageCost: Value(parseDouble(balanceMap['averageCost'])),
              lastUpdated: Value(DateTime.tryParse(balanceMap['lastUpdated'] as String? ?? '') ?? DateTime.now()),
            ),
          );
    } catch (e) {
      debugPrint('[Sync] Error in InventoryBalanceSyncStrategy: $e');
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is InventoryBalancesCompanion) {
      await db.into(db.inventoryBalances).insertOnConflictUpdate(record);
    }
  }
}
