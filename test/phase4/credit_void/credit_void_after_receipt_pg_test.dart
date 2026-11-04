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
  late PgTestFixture fx;
  late AppDatabase db;
  late ProviderContainer container;
  late SalesTransactionOrchestrator sales;
  late int userId, warehouseId, safeId;

  setUp(() async {
    fx = await bootPgTestSchema();
    db = fx.db;
    await db.syncDefaultAccounts();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      accountingServiceProvider.overrideWith((ref) => AccountingService(
            ref.watch(accountingRepositoryProvider), ref.watch(partiesRepositoryProvider),
            TreasuryRepositoryImpl(db, ref), ref.watch(productRepositoryProvider),
            ref.watch(inventoryRepositoryProvider), ref.watch(settingsRepositoryProvider),
            ref.watch(auditRepositoryProvider),
          )),
    ]);
    sales = SalesTransactionOrchestrator(db, container.read(accountingServiceProvider));
    final roleId = await db.into(db.roles).insert(RolesCompanion.insert(name: 'pg-void', isSystemRole: const Value(false)));
    final perm = await (db.select(db.permissions)..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))..limit(1)).getSingle();
    await db.addPermissionToRole(roleId, perm.id);
    userId = await db.createUser(username: 'pg_void', password: 'pg-void-pw', displayName: 'pg', roleId: roleId);
    warehouseId = (await db.getDefaultWarehouse())!.id;
    safeId = (await db.getDefaultSafeByType('cash'))!.id;
    await db.openShift(userId, 0);
  });
  tearDown(() async { container.dispose(); await fx.tearDown(); });

  test('AUD-SP-04 PG partial receipt survives void as matching customer credit', () async {
    final customer = await db.insertParty(PartiesCompanion.insert(name: 'عميل PG', isCustomer: const Value(true)));
    final product = await db.insertProduct(ProductsCompanion.insert(
      code: 'PG-CREDIT-VOID', name: 'PG credit void', salePrice: const Value(100),
      costPrice: const Value(60), trackInventory: const Value(true)));
    await db.adjustStock(productId: product, warehouseId: warehouseId, quantity: 10, type: 'in', unitCost: 60, notes: 'opening');
    final result = await sales.completeSalesTransaction(SaleRequest(
      items: [CartItemEntity(productId: product, productName: 'P', productCode: 'P', quantity: 2, unitPrice: 100)],
      customerId: customer, warehouseId: warehouseId, userId: userId, paymentMethod: 'credit', paidAmount: 0,
      taxEnabled: false, cashSafeId: safeId));
    expect(result.isSuccess, isTrue, reason: result.errorMessage);
    final invoiceId = result.invoiceId!;
    await db.addSalesPayment(invoiceId: invoiceId, amount: 50, safeId: safeId, userId: userId);
    await db.voidSalesInvoice(invoiceId, deletedBy: userId);
    expect((await db.getPartyById(customer))!.balance, closeTo(-50, 0.005));
    expect((await db.getSafeById(safeId))!.balance, closeTo(50, 0.005));
    expect(await db.getPartyBalanceMismatches(), isEmpty);
    expect((await db.getProductById(product))!.currentStock, closeTo(10, 0.005));
    final unbalanced = await db.customSelect(
      'SELECT entry_id FROM journal_entry_lines GROUP BY entry_id '
      'HAVING ABS(SUM(debit) - SUM(credit)) > 0.005').get();
    expect(unbalanced, isEmpty);
  });
}
