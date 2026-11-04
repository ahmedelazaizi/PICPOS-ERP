@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/data/repositories/treasury_repository_impl.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';

import '../../integration_pg/_support/pg_fixture.dart';

void main() {
  test('PostgreSQL live sale and settlement discounts use mapped accounts',
      timeout: const Timeout(Duration(minutes: 5)), () async {
    final fixture = await bootPgTestSchema();
    addTearDown(fixture.tearDown);
    final db = fixture.db;
    await db.syncDefaultAccounts();
    final container = ProviderContainer(overrides: [
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
    addTearDown(container.dispose);

    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'phase6a-pg', isSystemRole: const Value(false)));
    final userId = await db.createUser(
        username: 'phase6a_pg', password: 'test-only', displayName: 'phase6a', roleId: roleId);
    final warehouseId = (await db.getDefaultWarehouse())!.id;
    final safeId = (await db.getDefaultSafeByType('cash'))!.id;
    await db.openShift(userId, 0);
    final productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PHASE6A-PG',
      name: 'phase6a pg',
      salePrice: const Value(100),
      costPrice: const Value(60),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
        productId: productId, warehouseId: warehouseId, quantity: 2,
        type: 'in', unitCost: 60, notes: 'phase6a pg opening');

    final sale = await SalesTransactionOrchestrator(
            db, container.read(accountingServiceProvider))
        .completeSalesTransaction(SaleRequest(
      items: [CartItemEntity(
          productId: productId, productName: 'phase6a', productCode: 'PHASE6A-PG',
          quantity: 1, unitPrice: 100)],
      warehouseId: warehouseId,
      userId: userId,
      paymentMethod: 'cash',
      paidAmount: 91.2,
      taxEnabled: true,
      taxPercent: 14,
      invoiceDiscountAmount: 20,
      cashSafeId: safeId,
    ));
    expect(sale.isSuccess, isTrue, reason: sale.errorMessage);

    final customerId = await db.insertParty(
        PartiesCompanion.insert(name: 'phase6a customer', isCustomer: const Value(true)));
    await db.createReceiptVoucher(
      amount: 50,
      discount: 5,
      category: 'customers',
      partyId: customerId,
      safeId: safeId,
      userId: userId,
      description: 'phase6a settlement',
    );

    Future<double> net(String code) async {
      final row = await db.customSelect(
        'SELECT COALESCE(SUM(l.debit-l.credit),0) n FROM journal_entry_lines l '
        'JOIN journal_entries e ON e.id=l.entry_id JOIN accounts a ON a.id=l.account_id '
        'WHERE e.is_deleted=FALSE AND a.code LIKE ?',
        variables: [Variable<String>('$code%')],
      ).getSingle();
      return row.read<double>('n');
    }

    expect(await net('4121'), closeTo(-100, 0.005));
    expect(await net('4212'), closeTo(20, 0.005));
    expect(await net('6215'), closeTo(5, 0.005));
    expect(await net('5205'), closeTo(0, 0.005));
    expect(await net('4202'), closeTo(0, 0.005));
    expect(-(await net('4121')) - await net('4212'), closeTo(80, 0.005));
  });
}
