import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'MC1-EXP', name: 'Expiry stock',
      trackInventory: const Value(true), trackExpiry: const Value(true),
    ));
  });
  tearDown(() => db.close());

  Future<double> binTotal() async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(quantity), 0) AS total FROM location_stock '
      'WHERE product_id = ? AND warehouse_id = ?',
      variables: [Variable<int>(productId), Variable<int>(warehouseId)],
    ).getSingle();
    return (row.data['total'] as num).toDouble();
  }

  test('backfill is repeatable and preserves warehouse totals and journals', () async {
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 12, type: 'purchase');
    final journalsBefore = await db.customSelect(
      'SELECT COUNT(*) AS n FROM journal_entries',
    ).getSingle();
    await db.backfillWarehouseLocations();
    await db.backfillWarehouseLocations();
    final journalsAfter = await db.customSelect(
      'SELECT COUNT(*) AS n FROM journal_entries',
    ).getSingle();
    final bins = await db.customSelect(
      'SELECT COUNT(*) AS n FROM warehouse_locations '
      'WHERE warehouse_id = ? AND is_default = 1',
      variables: [Variable<int>(warehouseId)],
    ).getSingle();
    expect((bins.data['n'] as num).toInt(), 1);
    expect(await binTotal(), 12);
    expect(journalsAfter.data['n'], journalsBefore.data['n']);
    expect(await db.warehouseBinDiscrepancies(), isEmpty);
  });

  test('moving stock between bins is zero-net for warehouse and GL', () async {
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 8, type: 'purchase');
    final defaultBin = (await db.warehouseLocations(warehouseId))
        .singleWhere((location) => location['is_default'] == 1);
    final newBinId = await db.saveWarehouseLocation(
      warehouseId: warehouseId, binCode: 'A-1', aisle: 'A',
    );
    final journalsBefore = await db.customSelect(
      'SELECT COUNT(*) AS n FROM journal_entries',
    ).getSingle();
    await db.enableWarehouseBins();
    await db.moveStockBetweenBins(
      fromLocationId: (defaultBin['id'] as num).toInt(),
      toLocationId: newBinId, productId: productId, quantity: 3,
    );
    await db.backfillWarehouseLocations();
    expect(await binTotal(), 8);
    final destination = await db.customSelect(
      'SELECT quantity FROM location_stock WHERE location_id = ?',
      variables: [Variable<int>(newBinId)],
    ).getSingle();
    expect(destination.data['quantity'], 3);
    expect(await db.warehouseBinDiscrepancies(), isEmpty);
    final journalsAfter = await db.customSelect(
      'SELECT COUNT(*) AS n FROM journal_entries',
    ).getSingle();
    expect(journalsAfter.data['n'], journalsBefore.data['n']);
    final movements = await db.customSelect(
      "SELECT SUM(quantity) AS net, COUNT(*) AS n FROM stock_movements "
      "WHERE movement_type = 'bin_move'",
    ).getSingle();
    expect(movements.data['net'], 0);
    expect(movements.data['n'], 2);
  });

  test('bin moves reject while locations are disabled', () async {
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 5, type: 'purchase');
    final defaultId = (await db.warehouseLocations(warehouseId)).single['id'] as int;
    final otherId = await db.saveWarehouseLocation(
        warehouseId: warehouseId, binCode: 'WAITING');
    await expectLater(db.moveStockBetweenBins(
        fromLocationId: defaultId, toLocationId: otherId,
        productId: productId, quantity: 2), throwsStateError);
    expect(await binTotal(), 5);
    expect(await db.warehouseBinDiscrepancies(), isEmpty);
  });

  test('existing SQLite stock is backfilled when v195 schema is ensured', () async {
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 7, type: 'purchase');
    await db.customStatement('DELETE FROM location_stock');
    await db.customStatement('DELETE FROM warehouse_locations');
    await db.customStatement('UPDATE stock_movements SET location_id = NULL');
    await db.ensureWarehouseLocationsSchema();
    expect(await binTotal(), 7);
    expect(await db.warehouseBinDiscrepancies(), isEmpty);
    final historic = await db.customSelect(
        'SELECT location_id FROM stock_movements WHERE product_id = ?',
        variables: [Variable<int>(productId)]).getSingle();
    expect(historic.data['location_id'], isNull);
  });

  test('new warehouse immediately has a DEFAULT bin', () async {
    final newId = await db.insertWarehouse(
        WarehousesCompanion.insert(name: 'Second warehouse'));
    final bins = await db.warehouseLocations(newId);
    expect(bins.where((bin) => bin['is_default'] == 1), hasLength(1));
    expect(bins.single['bin_code'], 'DEFAULT');
  });

  test('occupied bin cannot be deactivated', () async {
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 4, type: 'purchase');
    final source = (await db.warehouseLocations(warehouseId)).single;
    final occupiedId = await db.saveWarehouseLocation(
        warehouseId: warehouseId, binCode: 'OCCUPIED');
    await db.enableWarehouseBins();
    await db.moveStockBetweenBins(fromLocationId: source['id'] as int,
        toLocationId: occupiedId, productId: productId, quantity: 2);
    await expectLater(db.deactivateWarehouseLocation(occupiedId), throwsStateError);
  });

  test('FEFO issues from occupied bins without negative bin quantities', () async {
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 8, type: 'purchase');
    final earliest = await db.insertBatch(ProductBatchesCompanion.insert(
        productId: productId, warehouseId: warehouseId,
        batchNumber: 'EARLY', expiryDate: DateTime.now().add(const Duration(days: 10)),
        quantity: const Value(4)));
    await db.insertBatch(ProductBatchesCompanion.insert(
        productId: productId, warehouseId: warehouseId,
        batchNumber: 'LATE', expiryDate: DateTime.now().add(const Duration(days: 30)),
        quantity: const Value(4)));
    await db.enableWarehouseBins();
    final defaultId = (await db.warehouseLocations(warehouseId)).single['id'] as int;
    final rackId = await db.saveWarehouseLocation(
        warehouseId: warehouseId, binCode: 'A-01');
    await db.moveStockBetweenBins(fromLocationId: defaultId,
        toLocationId: rackId, productId: productId, batchId: earliest, quantity: 4);
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: -5, type: 'sale');
    final rows = await db.customSelect(
        'SELECT quantity FROM location_stock WHERE product_id = ?',
        variables: [Variable<int>(productId)]).get();
    expect(rows.every((row) => (row.data['quantity'] as num) >= -0.000001), isTrue);
    expect(await binTotal(), 3);
    expect(await db.warehouseBinDiscrepancies(), isEmpty);
  });

  test('transfer carries lot to destination and reconciles both warehouses', () async {
    final destination = await db.insertWarehouse(
        WarehousesCompanion.insert(name: 'Lot destination'));
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 6, type: 'purchase');
    await db.insertBatch(ProductBatchesCompanion.insert(
        productId: productId, warehouseId: warehouseId,
        batchNumber: 'TRANSIT-LOT', expiryDate: DateTime.now().add(const Duration(days: 40)),
        quantity: const Value(6)));
    await db.enableWarehouseBins();
    await db.transferStock(fromWarehouseId: warehouseId, toWarehouseId: destination,
        items: [{'productId': productId, 'quantity': 2.0}]);
    final movedLots = await db.getProductBatches(productId);
    expect(movedLots.singleWhere((lot) => lot.warehouseId == destination).batchNumber,
        'TRANSIT-LOT');
    expect(movedLots.singleWhere((lot) => lot.warehouseId == destination).quantity, 2);
    expect(await binTotal(), 4);
    final destinationStock = await db.customSelect(
        'SELECT SUM(quantity) AS total FROM location_stock WHERE warehouse_id = ? '
        'AND product_id = ?', variables: [Variable<int>(destination), Variable<int>(productId)]).getSingle();
    expect(destinationStock.data['total'], 2);
    expect(await db.warehouseBinDiscrepancies(), isEmpty);
  });

  test('purchase posting rejects tracked expiry without both fields', () async {
    final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'Batch supplier',
            isSupplier: const Value(true)));
    await expectLater(db.createPurchaseInvoice(
      supplierId: supplierId, warehouseId: warehouseId,
      invoiceDate: DateTime.now(), paid: 0, paymentMethod: 'credit',
      supplierInvoiceNumber: 'MC1-NO-LOT',
      items: [PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0, productId: productId, quantity: 2,
          unitCost: 5, total: 10)],
    ), throwsStateError);
    await expectLater(db.createPurchaseInvoice(
      supplierId: supplierId, warehouseId: warehouseId,
      invoiceDate: DateTime.now(), paid: 0, paymentMethod: 'credit',
      supplierInvoiceNumber: 'MC1-NO-BATCH',
      items: [PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0, productId: productId, quantity: 2,
          unitCost: 5, total: 10,
          expiryDate: Value(DateTime.now().add(const Duration(days: 30))))],
    ), throwsStateError);
    expect(await binTotal(), 0);
  });

  test('valid-lot blocking defaults off until operator enables it', () async {
    expect(await db.getSettingValue('block_issue_without_valid_batch'), isNot('true'));
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 3, type: 'purchase');
    await db.enableWarehouseBins();
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: -1, type: 'sale');
    expect(await binTotal(), 2);
  });

  test('strict expiry issues exclude expired lots and fail closed', () async {
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: 6, type: 'purchase');
    final expiredId = await db.insertBatch(ProductBatchesCompanion.insert(
      productId: productId, warehouseId: warehouseId,
      batchNumber: 'EXPIRED', expiryDate: DateTime.now().subtract(const Duration(days: 2)),
      quantity: const Value(3),
    ));
    final validId = await db.insertBatch(ProductBatchesCompanion.insert(
      productId: productId, warehouseId: warehouseId,
      batchNumber: 'VALID', expiryDate: DateTime.now().add(const Duration(days: 30)),
      quantity: const Value(3),
    ));
    await db.enableWarehouseBins();
    await db.setSetting('block_issue_without_valid_batch', 'true');
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
        quantity: -2, type: 'sale');
    final lots = await db.getProductBatches(productId);
    expect(lots.firstWhere((lot) => lot.id == expiredId).quantity, 3);
    expect(lots.firstWhere((lot) => lot.id == validId).quantity, 1);
    expect(await binTotal(), 4);
    await expectLater(
      db.adjustStock(productId: productId, warehouseId: warehouseId,
          quantity: -2, type: 'sale'),
      throwsStateError,
    );
    expect(await binTotal(), 4);
    expect(await db.warehouseBinDiscrepancies(), isEmpty);
  });
}
