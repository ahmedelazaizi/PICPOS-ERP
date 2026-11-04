import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import '../../helpers/fleet_harness.dart';

const _skip = 'audit repro — pending owner approval';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  late int userId;
  late int mainWarehouseId;
  late int mainProductId;
  late int localProductId;
  late String productGlobalId;
  setUp(() async {
    fleet = await Fleet.startMain();
    await Fleet.grantPermissions(fleet.main.db, 'كاشير', [
      PermissionCodes.salesReturnCreate,
      PermissionCodes.salesDelete,
      PermissionCodes.voidPaidInvoice,
    ]);
    userId = fleet.userIds['cashier']!;
    final warehouse = (await fleet.main.db.getDefaultWarehouse())!;
    mainWarehouseId = warehouse.id;
    productGlobalId = 'fleet-audit-stock-1';
    await fleet.main.db.insertProduct(ProductsCompanion.insert(
      code: 'FLEET-AUDIT-1', name: 'Fleet audit item',
      salePrice: const Value(10), costPrice: const Value(5),
      trackInventory: const Value(true), globalId: Value(productGlobalId),
    ));
    final mainProduct = (await (fleet.main.db.select(fleet.main.db.products)
          ..where((row) => row.globalId.equals(productGlobalId)))
        .getSingle());
    mainProductId = mainProduct.id;
    await fleet.main.db.adjustStock(productId: mainProductId,
        warehouseId: mainWarehouseId, quantity: 10, type: 'purchase', unitCost: 5);
    expect((await fleet.installClient(fleet.cashier, 'cashier', kCashPw)).ok, isTrue,
        reason: '${fleet.cashier.report}');
    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    final localProduct = await (fleet.cashier.db.select(fleet.cashier.db.products)
          ..where((row) => row.globalId.equals(productGlobalId)))
        .getSingle();
    localProductId = localProduct.id;
    expect(await fleet.cashier.db.getProductById(localProductId), isNotNull);
  });
  tearDown(() => fleet.dispose());

  test('client HTTP sale-return-void POSTs reach main and restore stock',
      skip: _skip, () async {
    final localWarehouse = (await fleet.cashier.db.getDefaultWarehouse())!;

    Future<int?> sell({required String globalId}) => ClientWriteInterceptor.submitSale({
      'invoiceNumber': 'FLEET-SAME-NO',
      'globalId': globalId,
      'subtotal': 10.0, 'discount': 0.0, 'tax': 0.0,
      'total': 10.0, 'paid': 10.0, 'paymentMethod': 'cash',
      'warehouseId': localWarehouse.id, 'branchId': fleet.branch1,
      'userId': userId,
      'items': [
        {'productId': localProductId, 'productGlobalId': productGlobalId,
         'quantity': 1.0, 'unitPrice': 10.0, 'discount': 0.0,
         'total': 10.0, 'costPrice': 5.0},
      ],
    });

    final saleA = await sell(globalId: 'fleet-sale-a');
    final saleB = await sell(globalId: 'fleet-sale-b');
    expect(saleA, isNotNull);
    expect(saleB, isNotNull);
    final sameNumberRows = await (fleet.main.db.select(fleet.main.db.salesInvoices)
          ..where((row) => row.invoiceNumber.equals('FLEET-SAME-NO')))
        .get();
    expect(sameNumberRows.map((row) => row.globalId).toSet(),
        {'fleet-sale-a', 'fleet-sale-b'});

    final retId = await ClientWriteInterceptor.submitSalesReturn({
      'invoiceNumber': 'FLEET-RET-1', 'globalId': 'fleet-return-a',
      'originalInvoiceId': saleA, 'subtotal': 10.0, 'discount': 0.0,
      'tax': 0.0, 'total': 10.0, 'paid': 0.0, 'paymentMethod': 'cash',
      'warehouseId': localWarehouse.id, 'branchId': fleet.branch1,
      'userId': userId,
      'items': [
        {'productId': localProductId, 'productGlobalId': productGlobalId,
         'quantity': 1.0, 'unitPrice': 10.0, 'discount': 0.0,
         'total': 10.0, 'costPrice': 5.0},
      ],
    });
    expect(retId, isNotNull);

    expect(await ClientWriteInterceptor.submitVoidSalesInvoice(
      salesId: saleB!, salesGlobalId: 'fleet-sale-b',
      invoiceNumber: 'FLEET-SAME-NO', reason: 'audit fleet void',
      globalId: 'fleet-void-b', userId: userId,
    ), isTrue);

    final allServerInvoices = await fleet.main.db.select(fleet.main.db.salesInvoices).get();
    final serverReturn = allServerInvoices.singleWhere((row) => row.globalId == 'fleet-return-a');
    final voided = allServerInvoices.singleWhere((row) => row.globalId == 'fleet-sale-b');
    final mainProduct = await fleet.main.db.getProductById(mainProductId);
    final mainMovements = await (fleet.main.db.select(fleet.main.db.stockMovements)
          ..where((row) => row.productId.equals(mainProductId)))
        .get();
    final mainMoves = await fleet.main.db.select(fleet.main.db.safeTransactions).get();
    final mainJournals = await fleet.main.db.select(fleet.main.db.journalEntries).get();
    final mainAccounts = await fleet.main.db.select(fleet.main.db.accounts).get();
    final mainBalances = mainAccounts.where((a) => a.balance != 0)
        .map((a) => '${a.code}:${a.balance}').toSet();

    expect(serverReturn.saleType, 'return');
    expect(voided.status, 'voided');
    expect(mainProduct!.currentStock, 10);
    expect(sameNumberRows.length, 2);
    expect(await fleet.cashier.db.select(fleet.cashier.db.syncOutbox).get(), isEmpty);
    // ignore: avoid_print
    print('[AUDIT-FLEET-SALE-RET-VOID] sameNumberRows=${sameNumberRows.length} '
        'returnId=$retId voidStatus=${voided.status} stock=${mainProduct.currentStock} '
        'stockMovements=${mainMovements.length} safeTx=${mainMoves.length} '
        'journalEntries=${mainJournals.length} accounts.balance=$mainBalances');
  });
}
