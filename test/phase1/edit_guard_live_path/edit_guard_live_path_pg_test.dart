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
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import '../../integration_pg/_support/pg_fixture.dart';

void main() {
  late PgTestFixture fixture;
  late ProviderContainer container;
  late AppDatabase db;
  late int userId, warehouseId, safeId, productId;
  setUp(() async {
    fixture = await bootPgTestSchema();
    db = fixture.db;
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
    final role = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'phase1c-pg', isSystemRole: const Value(false)));
    final permission = await (db.select(db.permissions)
      ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))..limit(1)).getSingle();
    await db.addPermissionToRole(role, permission.id);
    userId = await db.createUser(username: 'phase1c_pg', password: 'test-only',
      displayName: 'phase1c', roleId: role);
    warehouseId = (await db.getDefaultWarehouse())!.id;
    safeId = (await db.getDefaultSafeByType('cash'))!.id;
    await db.openShift(userId, 0);
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PHASE1C', name: 'phase1c', salePrice: const Value(8),
      costPrice: const Value(5), trackInventory: const Value(true)));
    await db.adjustStock(productId: productId, warehouseId: warehouseId,
      quantity: 8, type: 'in', unitCost: 5, notes: 'opening');
  });
  tearDown(() async { container.dispose(); await fixture.tearDown(); });

  Future<int> count(String table, int id) async => (await db.customSelect(
    'SELECT COUNT(*) n FROM $table WHERE reference_id=?',
    variables: [Variable<int>(id)]).getSingle()).read<int>('n');

  test('PostgreSQL repository edit rejects a live return before new postings', () async {
    final sale = await SalesTransactionOrchestrator(db,
      container.read(accountingServiceProvider)).completeSalesTransaction(SaleRequest(
        items: [CartItemEntity(productId: productId, productName: 'phase1c',
          productCode: 'PHASE1C', quantity: 2, unitPrice: 8)],
        warehouseId: warehouseId, userId: userId, paymentMethod: 'cash',
        paidAmount: 16, cashSafeId: safeId, taxEnabled: false));
    expect(sale.isSuccess, isTrue, reason: sale.errorMessage);
    final invoice = (await db.getSalesInvoiceById(sale.invoiceId!))!;
    final line = (await db.getSalesInvoiceItems(invoice.id)).first;
    final product = (await db.getProductById(productId))!;
    await container.read(returnsRepositoryProvider).processSalesReturn(
      invoice: invoice, returnQuantities: {line.id: 1}, productCache: {
        productId: ProductEntity(id: product.id, name: product.name, code: product.code,
          salePrice: product.salePrice, costPrice: product.costPrice,
          currentStock: product.currentStock, minStock: product.minStock,
          trackInventory: product.trackInventory),
      }, reason: 'phase1c', userId: userId, userName: 'phase1c_pg', isFullReturn: false);
    final before = [for (final table in ['journal_entries','stock_movements','safe_transactions'])
      await count(table, invoice.id)];
    await expectLater(container.read(salesRepositoryProvider).updateFullSalesInvoice(
      invoiceId: invoice.id, userId: userId, warehouseId: warehouseId,
      paid: 16, paymentMethod: 'cash',
      items: [CartItemEntity(productId: productId, productName: 'phase1c',
        productCode: 'PHASE1C', quantity: 2, unitPrice: 8)]),
      throwsA(isA<StateError>().having((e) => e.message, 'message',
        'لا يمكن تعديل فاتورة عليها مرتجع. ألغِ المرتجع أو حرّر فاتورة بديلة.')));
    expect([for (final table in ['journal_entries','stock_movements','safe_transactions'])
      await count(table, invoice.id)], before);
  });
}
