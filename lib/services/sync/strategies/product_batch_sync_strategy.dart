// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class ProductBatchSyncStrategy extends SyncStrategy {
  ProductBatchSyncStrategy(super.db);

  @override
  String get tableName => 'product_batches';

  @override
  String get apiEndpoint => '/api/product-batches';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final batches = json['product_batches'] as List? ?? [];
    for (final b in batches) {
      final map = b as Map<String, dynamic>;
      await db.into(db.productBatches).insertOnConflictUpdate(
        ProductBatchesCompanion(
          id: Value(parseInt(map['id'])),
          productId: Value(parseInt(map['productId'])),
          warehouseId: Value(parseInt(map['warehouseId'])),
          batchNumber: Value(map['batchNumber'] as String? ?? ''),
          productionDate: Value(DateTime.tryParse(map['productionDate']?.toString() ?? '')),
          expiryDate: Value(DateTime.tryParse(map['expiryDate']?.toString() ?? '') ?? DateTime.now()),
          quantity: Value(parseDouble(map['quantity'])),
          initialQuantity: Value(parseDouble(map['initialQuantity'])),
          unitCost: Value(parseDouble(map['unitCost'])),
          purchaseInvoiceId: Value(parseIntNullable(map['purchaseInvoiceId'])),
          status: Value(map['status'] as String? ?? 'active'),
          createdAt: Value(DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now()),
        ),
      );
    }
    if (batches.isNotEmpty) {
      db.markTablesUpdated({db.productBatches});
      debugPrint('[Sync] ProductBatches: ${batches.length} synced');
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    if (record is ProductBatchesCompanion) {
      await db.into(db.productBatches).insertOnConflictUpdate(record);
    }
  }
}