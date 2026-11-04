@Tags(['pg'])
@Timeout(Duration(minutes: 6))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/data/repositories/treasury_repository_impl.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import '../../integration_pg/_support/pg_fixture.dart';

void main() {
  late PgTestFixture fixture;
  late ProviderContainer container;
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int safeId;
  late int productId;

  setUp(() async {
    fixture = await bootPgTestSchema();
    db = fixture.db;
    await db.customSelect('SELECT 1').get();
    await db.syncDefaultAccounts();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      accountingServiceProvider.overrideWith((ref) => AccountingService(
            ref.watch(accountingRepositoryProvider),
            ref.watch(partiesRepositoryProvider),
            TreasuryRepositoryImpl(db, ref),
            ref.watch(productRepositoryProvider),
            ref.watch(inventoryRepositoryProvider),
            ref.watch(settingsRepositoryProvider),
            ref.watch(auditRepositoryProvider),
          )),
    ]);
    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'phase1b-pg', isSystemRole: const Value(false)),
    );
    final permission = await (db.select(db.permissions)
          ..where((row) => row.code.equals(PermissionCodes.voidPaidInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(roleId, permission.id);
    userId = await db.createUser(
      username: 'phase1b_pg',
      password: 'phase1b-pg-test-only',
      displayName: 'phase1b',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    safeId = (await db.getDefaultSafeByType('cash'))!.id;
    await db.openShift(userId, 0);
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PHASE1B-PG',
      name: 'phase1b pg product',
      salePrice: const Value(6.99),
      costPrice: const Value(4.25),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 5,
      type: 'in',
      unitCost: 4.25,
      notes: 'opening stock',
    );
  });

  tearDown(() async {
    container.dispose();
    await fixture.tearDown();
  });

  test('PostgreSQL screen repository edit preserves cost and stock', () async {
    final sales = SalesTransactionOrchestrator(
      db,
      container.read(accountingServiceProvider),
    );
    final original = await sales.completeSalesTransaction(SaleRequest(
      items: [CartItemEntity(
        productId: productId,
        productName: 'phase1b pg product',
        productCode: 'PHASE1B-PG',
        quantity: 2,
        unitPrice: 6.99,
      )],
      warehouseId: warehouseId,
      userId: userId,
      paymentMethod: 'cash',
      paidAmount: 13.98,
      cashSafeId: safeId,
      taxEnabled: false,
    ));
    expect(original.isSuccess, isTrue, reason: original.errorMessage);

    await container.read(salesRepositoryProvider).updateFullSalesInvoice(
      invoiceId: original.invoiceId!,
      userId: userId,
      warehouseId: warehouseId,
      paid: 13.98,
      paymentMethod: 'cash',
      items: [CartItemEntity(
        productId: productId,
        productName: 'phase1b pg product',
        productCode: 'PHASE1B-PG',
        quantity: 3,
        unitPrice: 6.99,
      )],
    );

    final cogs = await db.customSelect(
      "SELECT COALESCE(SUM(l.debit),0) amount FROM journal_entries e "
      "JOIN journal_entry_lines l ON l.entry_id=e.id JOIN accounts a ON a.id=l.account_id "
      "WHERE e.reference_type='sale' AND e.reference_id=? AND e.is_deleted=false AND a.code='5211'",
      variables: [Variable<int>(original.invoiceId!)],
    ).getSingle();
    final inventory = await db.customSelect(
      "SELECT COALESCE(SUM(l.credit),0) amount FROM journal_entries e "
      "JOIN journal_entry_lines l ON l.entry_id=e.id JOIN accounts a ON a.id=l.account_id "
      "WHERE e.reference_type='sale' AND e.reference_id=? AND e.is_deleted=false AND a.code='1136'",
      variables: [Variable<int>(original.invoiceId!)],
    ).getSingle();
    final product = await db.getProductById(productId);
    final balance = await db.customSelect(
      'SELECT quantity FROM inventory_balances WHERE product_id=? AND warehouse_id=?',
      variables: [Variable<int>(productId), Variable<int>(warehouseId)],
    ).getSingle();
    expect((cogs.data['amount'] as num).toDouble(), closeTo(12.75, 0.005));
    expect((inventory.data['amount'] as num).toDouble(), closeTo(12.75, 0.005));
    expect(product!.currentStock, closeTo(2, 0.005));
    expect((balance.data['quantity'] as num).toDouble(), closeTo(2, 0.005));
  });
}
