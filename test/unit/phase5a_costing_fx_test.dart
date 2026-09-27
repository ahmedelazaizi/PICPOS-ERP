import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/costing_method_service.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  Future<int> actorId() async {
    final user = await (db.select(db.users)..limit(1)).getSingleOrNull();
    return user?.id ?? db.into(db.users).insert(UsersCompanion.insert(
      username: 'phase5a-${DateTime.now().microsecondsSinceEpoch}',
      passwordHash: 'phase5a-test-hash',
      displayName: 'Phase 5a',
    ));
  }

  Future<int> trackedProduct({double cost = 0}) => db.insertProduct(
        ProductsCompanion.insert(
          code: 'P5A-${DateTime.now().microsecondsSinceEpoch}',
          name: 'Phase 5a product',
          costPrice: Value(cost),
          trackInventory: const Value(true),
        ),
      );

  Future<int> deferredSale(int productId) async {
    final warehouse = (await db.getDefaultWarehouse())!;
    final userId = await actorId();
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouse.id,
      quantity: 2,
      type: 'initial',
      unitCost: 0,
    );
    return db.createSalesInvoice(
      invoiceNumber: 'P5A-SALE-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouse.id,
      userId: userId,
      subtotal: 20,
      discount: 0,
      tax: 0,
      total: 20,
      paid: 20,
      paymentMethod: 'cash',
      deferAutoPost: true,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 2,
          unitPrice: 10,
          total: 20,
        ),
      ],
    );
  }

  test('weighted average is the only costing method and valuation formula', () {
    expect(CostingMethod.values, [CostingMethod.weightedAverage]);
    expect(
      CostingMethodService.calculateCost(
        method: CostingMethod.weightedAverage,
        currentStock: 10,
        currentCost: 8,
        purchaseQty: 10,
        purchaseUnitCost: 12,
      ),
      10,
    );
  });

  test('purchase return movement retains the original unit cost', () async {
    final warehouse = (await db.getDefaultWarehouse())!;
    final productId = await trackedProduct(cost: 11);
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouse.id,
      quantity: 2,
      type: 'initial',
      unitCost: 7.5,
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouse.id,
      quantity: -2,
      type: 'purchase_return',
      referenceType: 'purchase_return',
      referenceId: 901,
      unitCost: 7.5,
    );
    final movement = await (db.select(db.stockMovements)
          ..where((m) => m.referenceType.equals('purchase_return') &
              m.referenceId.equals(901)))
        .getSingle();
    expect(movement.unitCost, closeTo(7.5, 0.001));
  });

  test('negative-stock receipt posts the cost adjustment entry', () async {
    await db.setSetting('enable_negative_sales', 'true');
    final warehouse = (await db.getDefaultWarehouse())!;
    final productId = await trackedProduct();
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouse.id,
      quantity: -2,
      type: 'sale',
      referenceType: 'sale',
      referenceId: 902,
      postAdjustmentJournal: false,
    );
    final supplierId = await db.into(db.parties).insert(
      PartiesCompanion.insert(name: 'Phase 5a supplier', isSupplier: const Value(true)),
    );
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouse.id,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 3,
          unitCost: 12,
          total: 36,
        ),
      ],
      paid: 0,
      paymentMethod: 'credit',
    );
    final adjustment = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('negative_stock_cost_adjustment') &
              e.referenceId.equals(invoiceId)))
        .getSingleOrNull();
    expect(adjustment, isNotNull);
    final lines = await (db.select(db.journalEntryLines)
          ..where((line) => line.entryId.equals(adjustment!.id)))
        .get();
    expect(lines.fold<double>(0, (sum, line) => sum + line.debit),
        closeTo(24, 0.001));
  });

  test('warn logs zero-cost sales and query returns the line', () async {
    await db.setSetting('zero_cost_policy', 'warn');
    DiagnosticLogger.enableTestMode();
    final productId = await trackedProduct();
    final invoiceId = await deferredSale(productId);
    final invoice = await db.getSalesInvoiceById(invoiceId);
    await db.autoPostCashSale(invoice!);

    final logs = DiagnosticLogger.testLog;
    expect(logs.any((line) => line.contains('invoiceId=$invoiceId') &&
        line.contains('productId=$productId') && line.contains('qty=2.0')), isTrue);
    final lines = await db.listZeroCostSalesLines(
      from: DateTime.now().subtract(const Duration(minutes: 1)),
      to: DateTime.now().add(const Duration(minutes: 1)),
    );
    expect(lines.any((line) => line.data['invoice_id'] == invoiceId), isTrue);
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('sale') &
              e.referenceId.equals(invoiceId)))
        .get();
    final cogs = await db.getAccountByPurpose('cogs');
    final cogsLines = await (db.select(db.journalEntryLines)
          ..where((line) => line.accountId.equals(cogs!.id) &
              line.entryId.isIn(entries.map((e) => e.id))))
        .get();
    expect(cogsLines, isEmpty);
  });

  test('block rejects a zero-cost sale before posting', () async {
    await db.setSetting('zero_cost_policy', 'warn');
    final productId = await trackedProduct();
    final invoiceId = await deferredSale(productId);
    await db.setSetting('zero_cost_policy', 'block');
    final invoice = await db.getSalesInvoiceById(invoiceId);
    await expectLater(db.autoPostCashSale(invoice!), throwsA(isA<Exception>()));
  });
}
