// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

class ProductBarcodeSyncStrategy extends SyncStrategy {
  ProductBarcodeSyncStrategy(super.db);

  @override
  String get tableName => 'product_barcodes';

  @override
  String get apiEndpoint => '/api/product-barcodes';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final barcodes = json['product_barcodes'] as List;
    for (final b in barcodes) {
      await db.into(db.productBarcodes).insertOnConflictUpdate(
        ProductBarcodesCompanion(
          id: Value(parseInt(b['id'])),
          productId: Value(parseInt(b['productId'])),
          barcode: Value(b['barcode'] as String),
          isPrimary: Value(parseBool(b['isPrimary'], false)),
        ),
      );
    }
    // Force UI refresh after sync
    if (barcodes.isNotEmpty) {
      db.markTablesUpdated({db.productBarcodes});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Usually handled correctly via full snapshot for fast reference
  }

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.productBarcodes).insertOnConflictUpdate(record as ProductBarcodesCompanion);
  }
}