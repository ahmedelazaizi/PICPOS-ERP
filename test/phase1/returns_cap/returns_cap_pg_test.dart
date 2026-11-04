@Tags(['pg'])
library;

import 'dart:isolate';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/treasury_repository_impl.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/services/accounting_service.dart';

import '../../integration_pg/_support/pg_fixture.dart';

void main() {
  late PgTestFixture fixture;
  late ProviderContainer container;
  late int userId;
  late int warehouseId;
  late int safeId;
  late int productId;
  late int invoiceId;

  setUp(() async {
    fixture = await bootPgTestSchema();
    final db = fixture.db;
    await db.syncDefaultAccounts();
    final roleId = await db
        .into(db.roles)
        .insert(
          RolesCompanion.insert(
            name: 'returns-cap-pg',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'returns-cap-pg',
      password: 'pg-test-only',
      displayName: 'Returns cap PG',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    safeId = (await db.getDefaultSafeByType('cash'))!.id;
    await db.adjustSafeBalance(safeId, 2000);
    await db.openShift(userId, 0);
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RET-CAP-PG',
        name: 'Returns cap PG',
        salePrice: const Value(100),
        costPrice: const Value(60),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 20,
      type: 'purchase',
      unitCost: 60,
    );
    invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'RET-CAP-PG-ORIGINAL',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 500,
      discount: 0,
      tax: 0,
      total: 500,
      paid: 500,
      paymentMethod: 'cash',
      cashSafeId: safeId,
      items: [
        SalesInvoiceItemsCompanion(
          productId: Value(productId),
          quantity: const Value(5),
          unitPrice: const Value(100),
          discount: const Value(0),
          total: const Value(500),
          costPrice: const Value(60),
        ),
      ],
    );
    container = _createReturnsCapContainer(db);
  });

  tearDown(() async {
    container.dispose();
    await fixture.tearDown();
  });

  test('cumulative sales-return cap is enforced on PostgreSQL', () async {
    final db = fixture.db;
    final repository = container.read(returnsRepositoryProvider);
    final invoice = (await db.getSalesInvoiceById(invoiceId))!;
    final line = (await db.getSalesInvoiceItems(invoiceId)).single;
    final product = (await db.getProductById(productId))!;
    final entity = ProductEntity(
      id: product.id,
      name: product.name,
      code: product.code,
      salePrice: product.salePrice,
      costPrice: product.costPrice,
      currentStock: product.currentStock,
      minStock: product.minStock,
      trackInventory: product.trackInventory,
    );

    Future<Object> process(double quantity) async {
      try {
        return await repository.processSalesReturn(
          invoice: invoice,
          returnQuantities: {line.id: quantity},
          productCache: {productId: entity},
          userId: userId,
          userName: 'PG tester',
        );
      } on Exception catch (error) {
        return error;
      }
    }

    expect(await process(3), isTrue);
    expect('${await process(3)}', contains('المتاح للإرجاع'));
    expect(await db.getAlreadyReturnedQty(invoiceId, productId), 3);
  });

  test(
    'concurrent returns from isolated PostgreSQL connections stay under cap',
    () async {
      final request = (
        invoiceId: invoiceId,
        productId: productId,
        userId: userId,
      );
      final results = await Future.wait([
        _runReturnAttemptInIsolate(request),
        _runReturnAttemptInIsolate(request),
      ]);

      expect(results.where((result) => result == 'accepted'), hasLength(1));
      expect(
        results.where((result) => result.startsWith('rejected:')),
        hasLength(1),
      );
      expect(await fixture.db.getAlreadyReturnedQty(invoiceId, productId), 3);
    },
  );
}

ProviderContainer _createReturnsCapContainer(AppDatabase database) =>
    ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        accountingServiceProvider.overrideWith(
          (ref) => AccountingService(
            ref.watch(accountingRepositoryProvider),
            ref.watch(partiesRepositoryProvider),
            TreasuryRepositoryImpl(database, ref),
            ref.watch(productRepositoryProvider),
            ref.watch(inventoryRepositoryProvider),
            ref.watch(settingsRepositoryProvider),
            ref.watch(auditRepositoryProvider),
          ),
        ),
      ],
    );

typedef _PgSalesReturnRequest = ({int invoiceId, int productId, int userId});

// Top-level on purpose: a closure created inside `main()` would capture the
// test's ProviderContainer/DB (not sendable across isolates). This one only
// carries the primitive [request].
Future<String> _runReturnAttemptInIsolate(_PgSalesReturnRequest request) =>
    Isolate.run(() => _attemptPgSalesReturn(request));

Future<String> _attemptPgSalesReturn(_PgSalesReturnRequest request) async {
  final database = openExtraPgConnection();
  final providerContainer = _createReturnsCapContainer(database);
  try {
    return await _submitPgSalesReturn(database, providerContainer, request);
  } on Exception catch (error) {
    if (!error.toString().contains('المتاح للإرجاع')) rethrow;
    return 'rejected: $error';
  } finally {
    providerContainer.dispose();
    await database.close();
  }
}

Future<String> _submitPgSalesReturn(
  AppDatabase database,
  ProviderContainer providerContainer,
  _PgSalesReturnRequest request,
) async {
  final invoice = (await database.getSalesInvoiceById(request.invoiceId))!;
  final item = (await database.getSalesInvoiceItems(request.invoiceId)).single;
  final entity = await _loadPgProductEntity(database, request.productId);
  final accepted = await providerContainer
      .read(returnsRepositoryProvider)
      .processSalesReturn(
        invoice: invoice,
        returnQuantities: {item.id: 3},
        productCache: {request.productId: entity},
        userId: request.userId,
        userName: 'PG concurrent tester',
      );
  return accepted ? 'accepted' : 'not_accepted';
}

Future<ProductEntity> _loadPgProductEntity(
  AppDatabase database,
  int productId,
) async {
  final product = (await database.getProductById(productId))!;
  return ProductEntity(
    id: product.id,
    name: product.name,
    code: product.code,
    salePrice: product.salePrice,
    costPrice: product.costPrice,
    currentStock: product.currentStock,
    minStock: product.minStock,
    trackInventory: product.trackInventory,
  );
}
