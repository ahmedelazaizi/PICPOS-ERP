@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

import '../../integration_pg/_support/pg_fixture.dart';

void main() {
  late PgTestFixture fixture;
  late AppDatabase secondConnection;
  late int userId;
  late int warehouseId;
  late int cashSafeId;
  late int productId;

  setUp(() async {
    fixture = await bootPgTestSchema();
    final db = fixture.db;
    await db.syncDefaultAccounts();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'noinv-cap-pg', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'noinv-cap-pg',
      password: 'pg-test-only',
      displayName: 'No invoice return PG',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    cashSafeId = (await db.getDefaultSafeByType('cash'))!.id;
    await db.adjustSafeBalance(cashSafeId, 1000);
    await db.openShift(userId, 0);
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'NOINV-CAP-PG',
        name: 'No invoice return PG',
        salePrice: const Value(10),
        costPrice: const Value(4),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 5,
      type: 'purchase',
      unitCost: 4,
    );
    await db.createSalesInvoice(
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 50,
      discount: 0,
      tax: 0,
      total: 50,
      paid: 50,
      paymentMethod: 'cash',
      cashSafeId: cashSafeId,
      items: [
        SalesInvoiceItemsCompanion(
          productId: Value(productId),
          quantity: const Value(5),
          unitPrice: const Value(10),
          total: const Value(50),
          costPrice: const Value(4),
        ),
      ],
    );
    secondConnection = openExtraPgConnection();
  });

  tearDown(() async {
    await secondConnection.close();
    await fixture.tearDown();
  });

  test('concurrent no-invoice returns of 3+3 from net sold 5 accept exactly one', () async {
    final returnOutcomes = await Future.wait([
      _attemptReturn(fixture.db, userId, warehouseId, cashSafeId, productId),
      _attemptReturn(secondConnection, userId, warehouseId, cashSafeId, productId),
    ]);

    expect(returnOutcomes.where((outcome) => outcome == 'accepted'), hasLength(1));
    expect(returnOutcomes.where((outcome) => outcome.startsWith('rejected:')), hasLength(1));
    final returnRows = await (fixture.db.select(fixture.db.salesInvoices)
          ..where((invoice) => invoice.saleType.equals('return')))
        .get();
    expect(returnRows, hasLength(1));
    final returnItems = await fixture.db.getSalesInvoiceItems(returnRows.single.id);
    expect(returnItems.single.quantity, 3);
  });
}

Future<String> _attemptReturn(
  AppDatabase db,
  int userId,
  int warehouseId,
  int cashSafeId,
  int productId,
) async {
  try {
    await db.createSalesInvoice(
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 30,
      discount: 0,
      tax: 0,
      total: 30,
      paid: 30,
      paymentMethod: 'cash',
      cashSafeId: cashSafeId,
      saleType: 'return',
      items: [
        SalesInvoiceItemsCompanion(
          productId: Value(productId),
          quantity: const Value(3),
          unitPrice: const Value(10),
          total: const Value(30),
          costPrice: const Value(4),
        ),
      ],
    );
    return 'accepted';
  } on StateError catch (error) {
    if (!error.message.contains('المتاح: 2')) rethrow;
    return 'rejected: $error';
  }
}
