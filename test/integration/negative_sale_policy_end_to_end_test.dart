import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/repositories/sales_repository.dart';
import 'package:ural_erp/services/stock_shortage_policy_service.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late SalesTransactionOrchestrator orchestrator;
  late int branchId;
  late int warehouseId;
  late int userId;
  late int productId;

  const unitPrice = 10.0;
  const unitCost = 4.0;
  const saleQuantity = 3.0;

  setUp(() async {
    StockShortagePolicyService.resetCacheForTest();
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    orchestrator = SalesTransactionOrchestrator(
      db,
      container.read(accountingServiceProvider),
    );

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع سياسة المخزون'),
        );
    final warehouse = (await db.getDefaultWarehouse())!;
    warehouseId = warehouse.id;
    await (db.update(db.warehouses)..where((row) => row.id.equals(warehouseId)))
        .write(WarehousesCompanion(branchId: Value(branchId)));

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'كاشير سياسة المخزون',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'negative_policy_cashier',
      password: 'pw',
      displayName: 'Negative Policy Cashier',
      roleId: roleId,
    );
    await db.openShift(userId, 0);

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'NEG-POLICY',
        name: 'صنف سياسة السالب',
        salePrice: const Value(unitPrice),
        costPrice: const Value(unitCost),
        trackInventory: const Value(true),
        allowNegativeSale: const Value(false),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1,
      type: 'opening_stock',
      unitCost: unitCost,
    );
    await db.setSetting('enable_negative_sales', 'false');
  });

  tearDown(() async {
    StockShortagePolicyService.resetCacheForTest();
    container.dispose();
    await db.close();
  });

  CartItemEntity saleLine() => const CartItemEntity(
        productId: 0,
        productName: 'unused',
        productCode: 'unused',
        quantity: saleQuantity,
        unitPrice: unitPrice,
      ).copyWith(
        productId: productId,
        productName: 'صنف سياسة السالب',
        productCode: 'NEG-POLICY',
      );

  Future<void> expectNegativeStockAndBalancedEntry(int invoiceId) async {
    final balance = await (db.select(db.inventoryBalances)
          ..where((row) =>
              row.productId.equals(productId) &
              row.warehouseId.equals(warehouseId)))
        .getSingle();
    expect(balance.quantity, -2);

    final entries = await (db.select(db.journalEntries)
          ..where((row) => row.referenceId.equals(invoiceId)))
        .get();
    expect(entries, isNotEmpty);
    for (final entry in entries) {
      final lines = await (db.select(db.journalEntryLines)
            ..where((row) => row.entryId.equals(entry.id)))
          .get();
      final debit = lines.fold<double>(0, (sum, line) => sum + line.debit);
      final credit = lines.fold<double>(0, (sum, line) => sum + line.credit);
      expect(debit, closeTo(credit, 0.001));
    }
  }

  test('PicPos quick sale honors a per-branch allow-negative policy', () async {
    await db.setSetting(
      'stock_shortage_policy_per_branch',
      '{"$branchId":"allow_negative"}',
    );
    StockShortagePolicyService.resetCacheForTest();

    final result = await orchestrator.completeSalesTransaction(
      SaleRequest(
        items: [saleLine()],
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'cash',
        paidAmount: unitPrice * saleQuantity,
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.errorMessage);
    await expectNegativeStockAndBalancedEntry(result.invoiceId!);
  });

  test('sales invoice honors the global allow-negative policy', () async {
    await db.setSetting('stock_shortage_policy', 'allow_negative');
    StockShortagePolicyService.resetCacheForTest();

    final invoiceId = await orchestrator.createSalesInvoice(
      customerId: null,
      warehouseId: warehouseId,
      userId: userId,
      subtotal: unitPrice * saleQuantity,
      discount: 0,
      tax: 0,
      total: unitPrice * saleQuantity,
      paid: unitPrice * saleQuantity,
      paymentMethod: 'cash',
      items: [saleLine()],
    );

    await expectNegativeStockAndBalancedEntry(invoiceId);
  });

  test('legacy enable_negative_sales still allows the quick sale', () async {
    await db.setSetting('enable_negative_sales', 'true');
    StockShortagePolicyService.resetCacheForTest();

    final result = await orchestrator.completeSalesTransaction(
      SaleRequest(
        items: [saleLine()],
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'cash',
        paidAmount: unitPrice * saleQuantity,
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.errorMessage);
    await expectNegativeStockAndBalancedEntry(result.invoiceId!);
  });

  test('POS stock guard follows the resolved sale policy', () async {
    // Owner report: with the policy on «allow negative», the till still
    // raised the stock-balance prompt because the guard read only the legacy
    // `enable_negative_sales` key.
    await db.setSetting('stock_shortage_policy', 'allow_negative');
    StockShortagePolicyService.resetCacheForTest();
    expect(await container.read(enableNegativeSalesProvider.future), isTrue);

    await db.setSetting('stock_shortage_policy', 'block');
    StockShortagePolicyService.resetCacheForTest();
    container.invalidate(enableNegativeSalesProvider);
    expect(await container.read(enableNegativeSalesProvider.future), isFalse);
  });

  test('disabled shortage policy blocks overselling with Arabic feedback', () async {
    await db.setSetting('stock_shortage_policy', 'block');
    StockShortagePolicyService.resetCacheForTest();

    final result = await orchestrator.completeSalesTransaction(
      SaleRequest(
        items: [saleLine()],
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'cash',
        paidAmount: unitPrice * saleQuantity,
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('الكمية المتوفرة حالياً في المستودع'));
    expect(await db.select(db.salesInvoices).get(), isEmpty);
  });

  test('disabled shortage policy blocks an oversold sales invoice', () async {
    await db.setSetting('stock_shortage_policy', 'block');
    StockShortagePolicyService.resetCacheForTest();

    await expectLater(
      orchestrator.createSalesInvoice(
        customerId: null,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: unitPrice * saleQuantity,
        discount: 0,
        tax: 0,
        total: unitPrice * saleQuantity,
        paid: unitPrice * saleQuantity,
        paymentMethod: 'cash',
        items: [saleLine()],
      ),
      throwsA(predicate(
        (error) => error.toString().contains('الكمية المتوفرة حالياً في المستودع'),
      )),
    );
    expect(await db.select(db.salesInvoices).get(), isEmpty);
  });
}
