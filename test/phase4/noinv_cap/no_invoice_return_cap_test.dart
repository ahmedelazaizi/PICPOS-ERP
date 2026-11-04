import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart'
    show SaleResult;

import '../../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld world;

  setUp(() async {
    world = await ScenarioWorld.create();
    await world.db.setSetting('enable_negative_sales', 'true');
  });

  tearDown(() async => world.dispose());

  Future<int> addTrackedProduct(String code) =>
      world.addProduct(code, price: 10, cost: 4);

  Future<SaleResult> noInvoiceReturn(
    int productId,
    double quantity, {
    double quantityInBase = 1,
  }) =>
      world.sales.completeSalesTransaction(SaleRequest(
        items: [
          world.line(productId, quantity, 10)
              .copyWith(quantityInBase: quantityInBase),
        ],
        warehouseId: world.warehouseId,
        userId: world.userId,
        paymentMethod: 'cash',
        paidAmount: quantity * 10,
        cashAmount: quantity * 10,
        taxEnabled: false,
        isReturn: true,
        saleType: 'return',
        cashSafeId: world.cashSafeId,
      ));

  test('excess return is rejected before invoice, journal, stock, or safe effects', () async {
    final product = await addTrackedProduct('NOINV-CAP-01');
    await world.sell([world.line(product, 5, 10)]);
    final stock = await world.stock(product);
    final safe = await world.safeBalance();
    final invoices = (await world.db.select(world.db.salesInvoices).get()).length;
    final journals = (await world.db.select(world.db.journalEntries).get()).length;
    final movements = (await world.db.select(world.db.stockMovements).get()).length;
    final safeTransactions = (await world.db.select(world.db.safeTransactions).get()).length;

    final returnAttempt = await noInvoiceReturn(product, 7);

    expect(returnAttempt.isSuccess, isFalse);
    expect(returnAttempt.errorMessage, contains('المتاح: 5'));
    expect(await world.stock(product), stock);
    expect(await world.safeBalance(), safe);
    expect((await world.db.select(world.db.salesInvoices).get()).length, invoices);
    expect((await world.db.select(world.db.journalEntries).get()).length, journals);
    expect((await world.db.select(world.db.stockMovements).get()).length, movements);
    expect((await world.db.select(world.db.safeTransactions).get()).length, safeTransactions);
  });

  test('return equal to net sold quantity remains valid', () async {
    final product = await addTrackedProduct('NOINV-CAP-02');
    await world.sell([world.line(product, 5, 10)]);

    final returnAttempt = await noInvoiceReturn(product, 5);

    expect(returnAttempt.isSuccess, isTrue, reason: returnAttempt.errorMessage);
  });

  test('a prior no-invoice return reduces the amount available for the next return', () async {
    final product = await addTrackedProduct('NOINV-CAP-03');
    await world.sell([world.line(product, 5, 10)]);

    final first = await noInvoiceReturn(product, 3);
    final second = await noInvoiceReturn(product, 3);

    expect(first.isSuccess, isTrue, reason: first.errorMessage);
    expect(second.isSuccess, isFalse);
    expect(second.errorMessage, contains('المتاح: 2'));
  });

  test('sales and returns compare quantities in base units', () async {
    final product = await addTrackedProduct('NOINV-CAP-UOM');
    await world.sell([
      world.line(product, 2, 10).copyWith(quantityInBase: 3),
    ]);

    final returnAttempt = await noInvoiceReturn(
      product,
      3,
      quantityInBase: 2,
    );

    expect(returnAttempt.isSuccess, isTrue, reason: returnAttempt.errorMessage);
  });

  test('service products are excluded from the quantity cap', () async {
    final product = await addTrackedProduct('NOINV-CAP-SERVICE');
    await (world.db.update(world.db.products)
          ..where((row) => row.id.equals(product)))
        .write(const ProductsCompanion(productType: Value('service')));

    final returnAttempt = await noInvoiceReturn(product, 7);

    expect(returnAttempt.isSuccess, isTrue, reason: returnAttempt.errorMessage);
  });

  test('a product never sold has zero returnable quantity', () async {
    final product = await addTrackedProduct('NOINV-CAP-04');

    final returnAttempt = await noInvoiceReturn(product, 1);

    expect(returnAttempt.isSuccess, isFalse);
    expect(returnAttempt.errorMessage, contains('المتاح: 0'));
  });

  test('an earlier invoice-linked return reduces no-invoice return availability', () async {
    final product = await addTrackedProduct('NOINV-CAP-INV');
    final sale = await world.sell([world.line(product, 5, 10)]);
    await world.returnItems(sale.invoiceId!, product, 2);
    final returnAttempt = await noInvoiceReturn(product, 4);

    expect(returnAttempt.isSuccess, isFalse);
    expect(returnAttempt.errorMessage, contains('المتاح: 3'));
  });

  test('inventory-untracked products are excluded from the quantity cap', () async {
    final product = await addTrackedProduct('NOINV-CAP-05');
    await (world.db.update(world.db.products)
          ..where((row) => row.id.equals(product)))
        .write(const ProductsCompanion(trackInventory: Value(false)));

    final returnAttempt = await noInvoiceReturn(product, 7);

    expect(returnAttempt.isSuccess, isTrue, reason: returnAttempt.errorMessage);
  });
}
