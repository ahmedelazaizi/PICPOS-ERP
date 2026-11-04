@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fixture;
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int safeId;
  late int productId;

  setUp(() async {
    fixture = await bootPgTestSchema();
    db = fixture.db;
    await db.syncDefaultAccounts();
    final role = await db
        .into(db.roles)
        .insert(
          RolesCompanion.insert(
            name: 'phase1-pg',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'phase1-pg',
      password: 'pg-test-only',
      displayName: 'PG test',
      roleId: role,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    safeId = (await db.getDefaultSafeByType('cash'))!.id;
    await db.openShift(userId, 0);
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'PHASE1-PG',
        name: 'Phase 1 PG',
        salePrice: const Value(10),
        costPrice: const Value(4),
        trackInventory: const Value(true),
      ),
    );
  });

  tearDown(() async => fixture.tearDown());

  test(
    'AUD-F03 quick cash return credits the same linked safe account on PostgreSQL',
    () async {
      await db.createSalesInvoice(
        customerId: null,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 10,
        discount: 0,
        tax: 0,
        total: 10,
        paid: 10,
        paymentMethod: 'cash',
        saleType: 'return',
        cashSafeId: safeId,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1,
            unitPrice: 10,
            total: 10,
            costPrice: const Value(4),
          ),
        ],
      );
      final safe = (await db.getSafeById(safeId))!;
      final account = await db.getAccountById(safe.linkedAccountId!);
      final linkedBalance = await db
          .customSelect(
            'select balance from accounts where id = ?',
            variables: [Variable<int>(safe.linkedAccountId!)],
          )
          .getSingle();
      final genericCash = await db.getAccountByCode('1111');
      expect(
        (linkedBalance.data['balance'] as num).toDouble(),
        closeTo(-10, 0.005),
      );
      expect(account!.code, '111-00001');
      expect((genericCash!.balance), closeTo(0, 0.005));
      expect(safe.balance, closeTo(-10, 0.005));
    },
  );
}
