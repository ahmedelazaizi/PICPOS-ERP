// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

class ProductUnitSyncStrategy extends SyncStrategy {
  ProductUnitSyncStrategy(super.db);

  @override
  String get tableName => 'productUnits';

  @override
  String get apiEndpoint => '/api/product-units';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final items = json['product_units'] as List;
    for (final u in items) {
      await db.into(db.productUnits).insertOnConflictUpdate(
        ProductUnitsCompanion(
          id: Value(parseInt(u['id'])),
          productId: Value(parseInt(u['productId'])),
          unitName: Value(u['unitName'] as String),
          barcode: Value(u['barcode'] as String?),
          quantityInBase: Value(parseDouble(u['quantityInBase'], 1.0)),
          salePrice: Value(parseDouble(u['salePrice'])),
          costPrice: Value(parseDouble(u['costPrice'])),
          isDefaultPurchase: Value(parseBool(u['isDefaultPurchase'])),
          isDefaultSale: Value(parseBool(u['isDefaultSale'])),
          isBaseUnit: Value(parseBool(u['isBaseUnit'])),
          sortOrder: Value(parseInt(u['sortOrder'])),
        ),
      );
    }
    // Force UI refresh after sync
    if (items.isNotEmpty) {
      db.markTablesUpdated({db.productUnits});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db
        .into(db.productUnits)
        .insertOnConflictUpdate(record as ProductUnitsCompanion);
  }
}