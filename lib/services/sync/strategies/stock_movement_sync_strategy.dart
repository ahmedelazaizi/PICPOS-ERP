// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

/// Pulls stock movements from the server into the local DB.
/// These are the raw movement records (purchase, sale, transfer, adjustment, etc.)
class StockMovementSyncStrategy extends SyncStrategy {
  StockMovementSyncStrategy(super.db);

  @override
  String get tableName => 'stock_movements';

  @override
  String get apiEndpoint => '/api/stock-movements';

  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.appendOnly;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final list = json['stock_movements'] as List? ?? [];
    for (final item in list) {
      await _syncSingle(item as Map<String, dynamic>);
    }
    // Force UI refresh after sync
    if (list.isNotEmpty) {
      db.markTablesUpdated({db.stockMovements});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Server-side incremental not yet implemented
  }

  Future<void> _syncSingle(Map<String, dynamic> m) async {
    try {
      final serverId = parseInt(m['id']);

      // Skip if already exists
      final existing = await (db.select(db.stockMovements)
            ..where((s) => s.id.equals(serverId)))
          .getSingleOrNull();
      if (existing != null) return;

      // Issue 11 (Feature 018): remap server productId → local id (see
      // sales_sync_strategy for full reasoning).
      final localProductId = await db.resolveItemFk(
        'products',
        parseInt(m['productId']),
        context: 'stock_movements movement=$serverId',
      );
      await db.into(db.stockMovements).insertOnConflictUpdate(
        StockMovementsCompanion(
          id: Value(serverId),
          productId: Value(localProductId),
          warehouseId: Value(parseInt(m['warehouseId'])),
          movementType: Value(m['movementType'] as String? ?? 'adjustment'),
          quantity: Value(parseDouble(m['quantity'])),
          unitCost: Value(parseDouble(m['unitCost'])),
          balanceAfter: Value(parseDouble(m['balanceAfter'])),
          referenceType: Value(m['referenceType'] as String?),
          referenceId: Value(parseIntNullable(m['referenceId'])),
          userId: Value(parseIntNullable(m['userId'])),
          branchId: Value(parseIntNullable(m['branchId'])),
          notes: Value(m['notes'] as String?),
          createdAt: Value(
            DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Sync] Error in StockMovementSyncStrategy: $e');
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is StockMovementsCompanion) {
      await db.into(db.stockMovements).insertOnConflictUpdate(record);
    }
  }
}