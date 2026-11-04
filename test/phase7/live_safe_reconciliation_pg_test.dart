@Tags(['pg'])
library;

// تكافؤ PostgreSQL لاختبار المرحلة 7: تيار `safes` الحيّ ومطابقة الخزائن
// يتبعان كل خطوة (بيع نقدي ← سند صرف 10 ← سند قبض 10).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/data/repositories/treasury_repository_impl.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';

import '../integration_pg/_support/pg_fixture.dart';

void main() {
  test('PostgreSQL: safe watchers and reconcileSafes follow every live step',
      timeout: const Timeout(Duration(minutes: 5)), () async {
    final fixture = await bootPgTestSchema();
    addTearDown(fixture.tearDown);
    final db = fixture.db;
    await db.syncDefaultAccounts();
    final app = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      branchScopeProvider
          .overrideWith((ref) async => const BranchScope.fullAccess()),
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
    addTearDown(app.dispose);

    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'phase7-pg', isSystemRole: const Value(false)));
    final userId = await db.createUser(
        username: 'phase7_pg', password: 'test-only', displayName: 'phase7', roleId: roleId);
    final warehouseId = (await db.getDefaultWarehouse())!.id;
    final safeId = (await db.getDefaultSafeByType('cash'))!.id;
    // الورديّة على فرع الدرج: `drawerMovementAllowed` يسأل عن فرع الخزنة،
    // وصندوقُ بذر PG مربوطٌ بفرع بينما المستخدمُ هنا بلا `user_branch_access`.
    await db.openShift(userId, 0,
        branchId: (await db.getSafeById(safeId))!.branchId);
    final productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PHASE7-PG',
      name: 'phase7 pg',
      salePrice: const Value(100),
      costPrice: const Value(60),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
        productId: productId, warehouseId: warehouseId, quantity: 2,
        type: 'in', unitCost: 60, notes: 'phase7 pg opening');
    final customerId = await db.insertParty(
        PartiesCompanion.insert(name: 'phase7 customer', isCustomer: const Value(true)));

    app.listen(scopedSafesProvider, (_, _) {});
    app.listen(dashboardCashBalanceProvider, (_, _) {});
    await app.read(scopedSafesProvider.future);
    final treasury = app.read(treasuryRepositoryProvider);

    final steps = <String, Future<void> Function()>{
      'cash sale': () async {
        final r = await SalesTransactionOrchestrator(
                db, app.read(accountingServiceProvider))
            .completeSalesTransaction(SaleRequest(
          items: [CartItemEntity(
              productId: productId, productName: 'phase7', productCode: 'PHASE7-PG',
              quantity: 1, unitPrice: 100)],
          warehouseId: warehouseId,
          userId: userId,
          paymentMethod: 'cash',
          paidAmount: 100,
          taxEnabled: false,
          cashSafeId: safeId,
        ));
        expect(r.isSuccess, isTrue, reason: r.errorMessage);
      },
      'cash expense 10': () => treasury.createPaymentVoucher(
          amount: 10, category: 'other_expense', safeId: safeId, userId: userId),
      'cash receipt 10': () => treasury.createReceiptVoucher(
          amount: 10, category: 'customers', partyId: customerId,
          safeId: safeId, userId: userId),
    };

    final mismatches = <String>[];
    for (final step in steps.entries) {
      await step.value();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      final stored = (await db.getSafeById(safeId))!.balance;
      final watched = (await app.read(scopedSafesProvider.future))
          .singleWhere((s) => s.id == safeId)
          .balance;
      if ((watched - stored).abs() > 0.005) {
        mismatches.add('${step.key} / scopedSafesProvider: $watched vs $stored');
      }
      final card = app.read(dashboardCashBalanceProvider).value;
      if (card == null || (card - stored).abs() > 0.005) {
        mismatches.add('${step.key} / dashboard cash card: $card vs $stored');
      }
      for (final d in await app.read(reconciliationServiceProvider).reconcileSafes()) {
        mismatches.add('${step.key} / reconcileSafes: stored=${d.cachedValue} '
            'calculated=${d.calculatedValue}');
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });
}
