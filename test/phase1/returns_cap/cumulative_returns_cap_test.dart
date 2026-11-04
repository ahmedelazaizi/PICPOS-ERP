import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';
import 'package:picpos_erp/services/api/api_purchase_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

import '../../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld world;
  late int productId;

  Future<Object> returnSales(int invoiceId, double quantity) async {
    try {
      return await world.returnItems(invoiceId, productId, quantity);
    } on Exception catch (error) {
      return error;
    }
  }

  Future<int> buy(double quantity, int supplierId) async {
    return world.container
        .read(purchasesRepositoryProvider)
        .createInvoice(
          CreatePurchaseInvoiceParams(
            supplierId: supplierId,
            warehouseId: world.warehouseId,
            paid: 0,
            paymentMethod: 'credit',
            userId: world.userId,
            items: [
              PurchaseItemParams(
                productId: productId,
                quantity: quantity,
                unitCost: 60,
                salePrice: 100,
                taxRate: 0,
                taxAmount: 0,
              ),
            ],
          ),
        );
  }

  Future<Object> returnPurchase(int invoiceId, double quantity) async {
    final repository = world.container.read(purchasesRepositoryProvider);
    final invoice = (await repository.getRawInvoiceById(invoiceId))!;
    final line = (await repository.getInvoiceItemsWithProduct(
      invoiceId,
    )).single;
    try {
      return await repository.processPurchaseReturn(
        invoice: invoice,
        returnItems: [
          PurchaseReturnItem(
            itemId: line.item.id,
            productId: line.item.productId,
            returnQuantity: quantity,
            unitCost: line.item.unitCost,
            taxAmount: line.item.taxAmount * quantity / line.item.quantity,
            originalQuantity: line.item.quantity,
            quantityInBase: line.item.quantityInBase,
          ),
        ],
      );
    } on Exception catch (error) {
      return error;
    }
  }

  setUp(() async {
    StockShortagePolicyService.resetCacheForTest();
    world = await ScenarioWorld.create();
    productId = await world.addProduct('RET-CAP', stock: 40);
  });

  tearDown(() async {
    StockShortagePolicyService.resetCacheForTest();
    await world.dispose();
  });

  test('2+2+2 from five rejects the last return without side effects', () async {
    final sale = await world.sell([world.line(productId, 5, 100)]);
    expect(await returnSales(sale.invoiceId!, 2), isTrue);
    expect(await returnSales(sale.invoiceId!, 2), isTrue);

    final stockBefore = await world.stock(productId);
    final safeBefore = await world.safeBalance();
    final movesBefore = await world.db
        .customSelect(
          "SELECT COUNT(*) AS n FROM stock_movements WHERE reference_type = 'sales_return' AND reference_id = ?",
          variables: [Variable<int>(sale.invoiceId!)],
        )
        .getSingle();
    final journalsBefore = await world.db
        .customSelect(
          "SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'sales_return' AND reference_id = ? AND is_deleted = 0",
          variables: [Variable<int>(sale.invoiceId!)],
        )
        .getSingle();
    final cashRowsBefore = await world.db
        .customSelect(
          "SELECT COUNT(*) AS n FROM safe_transactions WHERE reference_type = 'sales_return' AND reference_id = ? AND category = 'sales_return'",
          variables: [Variable<int>(sale.invoiceId!)],
        )
        .getSingle();

    final rejected = await returnSales(sale.invoiceId!, 2);
    expect('$rejected', contains('المتاح للإرجاع'));
    expect(await world.stock(productId), stockBefore);
    expect(await world.safeBalance(), safeBefore);
    expect(
      (await world.db
              .customSelect(
                "SELECT COUNT(*) AS n FROM stock_movements WHERE reference_type = 'sales_return' AND reference_id = ?",
                variables: [Variable<int>(sale.invoiceId!)],
              )
              .getSingle())
          .read<int>('n'),
      movesBefore.read<int>('n'),
    );
    expect(
      (await world.db
              .customSelect(
                "SELECT COUNT(*) AS n FROM journal_entries WHERE reference_type = 'sales_return' AND reference_id = ? AND is_deleted = 0",
                variables: [Variable<int>(sale.invoiceId!)],
              )
              .getSingle())
          .read<int>('n'),
      journalsBefore.read<int>('n'),
    );
    expect(
      (await world.db
              .customSelect(
                "SELECT COUNT(*) AS n FROM safe_transactions WHERE reference_type = 'sales_return' AND reference_id = ? AND category = 'sales_return'",
                variables: [Variable<int>(sale.invoiceId!)],
              )
              .getSingle())
          .read<int>('n'),
      cashRowsBefore.read<int>('n'),
    );
  });

  test('a second full return of five is rejected', () async {
    final sale = await world.sell([world.line(productId, 5, 100)]);
    expect(await returnSales(sale.invoiceId!, 5), isTrue);
    expect(
      '${await returnSales(sale.invoiceId!, 5)}',
      contains('المتاح للإرجاع'),
    );
  });

  test(
    'legitimate partial returns 2 then 3 complete the sold quantity',
    () async {
      final sale = await world.sell([world.line(productId, 5, 100)]);
      expect(await returnSales(sale.invoiceId!, 2), isTrue);
      expect(await returnSales(sale.invoiceId!, 3), isTrue);
      expect(
        await world.db.getAlreadyReturnedQty(sale.invoiceId!, productId),
        5,
      );
    },
  );

  test(
    'discount and tax refunds cannot exceed the sale value or quantity',
    () async {
      final sale = await world.sales.completeSalesTransaction(
        SaleRequest(
          items: [
            CartItemEntity(
              productId: productId,
              productName: 'خصم وضريبة',
              productCode: 'RET-CAP',
              quantity: 2,
              unitPrice: 100,
              taxRate: 14,
            ),
          ],
          warehouseId: world.warehouseId,
          userId: world.userId,
          paymentMethod: 'cash',
          paidAmount: 205.2,
          discountPercent: 10,
          taxEnabled: true,
          taxPercent: 14,
          cashSafeId: world.cashSafeId,
        ),
      );
      expect(sale.isSuccess, isTrue, reason: sale.errorMessage);
      expect(await returnSales(sale.invoiceId!, 1), isTrue);
      expect(await returnSales(sale.invoiceId!, 1), isTrue);
      final cashBeforeExcessAttempt = await world.safeBalance();
      final stockBeforeExcessAttempt = await world.stock(productId);

      expect(
        '${await returnSales(sale.invoiceId!, 1)}',
        contains('المتاح للإرجاع'),
      );
      expect(await world.safeBalance(), cashBeforeExcessAttempt);
      expect(await world.stock(productId), stockBeforeExcessAttempt);
      expect(cashBeforeExcessAttempt, closeTo(0, kEps));
    },
  );

  test('UOM returns are capped in base units and remain valid', () async {
    final sale = await world.sell([
      CartItemEntity(
        productId: productId,
        productName: 'صندوق من عشر وحدات',
        productCode: 'RET-CAP',
        quantity: 2,
        unitPrice: 100,
        quantityInBase: 10,
      ),
    ]);

    expect(await returnSales(sale.invoiceId!, 1), isTrue);
    expect(await returnSales(sale.invoiceId!, 1), isTrue);
    expect(
      await world.db.getAlreadyReturnedQty(sale.invoiceId!, productId),
      20,
    );
    final stockAfterValidReturns = await world.stock(productId);
    expect(
      '${await returnSales(sale.invoiceId!, 1)}',
      contains('المتاح للإرجاع'),
    );
    expect(await world.stock(productId), stockAfterValidReturns);
  });

  test(
    'cancelling a return restores the quantity available for return',
    () async {
      final sale = await world.sell([world.line(productId, 5, 100)]);
      expect(await returnSales(sale.invoiceId!, 2), isTrue);
      await world.container
          .read(returnsRepositoryProvider)
          .cancelSalesReturn(
            invoice: (await world.db.getSalesInvoiceById(sale.invoiceId!))!,
            userId: world.userId,
            userName: 'مدقق',
          );
      expect(await returnSales(sale.invoiceId!, 5), isTrue);
    },
  );

  test('concurrent returns cannot exceed the sold quantity', () async {
    final sale = await world.sell([world.line(productId, 3, 100)]);
    final results = await Future.wait([
      returnSales(sale.invoiceId!, 2),
      returnSales(sale.invoiceId!, 2),
    ]);
    expect(results.where((result) => result == true), hasLength(1));
    final rejected = results.whereType<Exception>().single;
    expect(rejected.toString(), contains('المتاح للإرجاع'));
    expect(await world.db.getAlreadyReturnedQty(sale.invoiceId!, productId), 2);
  });

  test('purchase returns 6 then 6 from ten reject the second return', () async {
    final supplierId = await world.addSupplier('مورد سقف المرتجع');
    final invoiceId = await buy(10, supplierId);
    await buy(10, supplierId); // enough remaining stock to reach the cap check

    expect(await returnPurchase(invoiceId, 6), isA<double>());
    final stockAfterAcceptedReturn = await world.stock(productId);
    final rejected = await returnPurchase(invoiceId, 6);
    expect('$rejected', contains('كمية الإرجاع'));
    expect(await world.stock(productId), stockAfterAcceptedReturn);
    expect(await world.db.getPurchaseReturnedQtyByProduct(invoiceId), {
      productId: 6,
    });
  });

  test('concurrent purchase returns cannot exceed the sold quantity', () async {
    final supplierId = await world.addSupplier('مورد تزامن سقف المرتجع');
    final invoiceId = await buy(10, supplierId);
    await buy(10, supplierId);

    final results = await Future.wait([
      returnPurchase(invoiceId, 6),
      returnPurchase(invoiceId, 6),
    ]);
    expect(results.whereType<double>(), hasLength(1));
    final rejected = results.whereType<Exception>().single;
    expect(rejected.toString(), contains('كمية الإرجاع'));
    expect(await world.db.getPurchaseReturnedQtyByProduct(invoiceId), {
      productId: 6,
    });
  });

  test('purchase API applies the same cumulative cap', () async {
    await world.grant(PermissionCodes.purchasesReturnCreate);
    final supplierId = await world.addSupplier('مورد API سقف المرتجع');
    final invoiceId = await buy(10, supplierId);
    await buy(10, supplierId);
    final invoice = (await world.container
        .read(purchasesRepositoryProvider)
        .getRawInvoiceById(invoiceId))!;
    final handler = ApiPurchaseHandler(world.db, {});

    Future<Response> post(String globalId) => handler.postPurchaseReturn(
      Request(
        'POST',
        Uri.parse('http://localhost/api/purchases/return'),
        headers: {'Content-Type': 'application/json'},
        context: {ApiUserCtx.userIdKey: world.userId},
        body: jsonEncode({
          'purchaseId': invoiceId,
          'purchaseGlobalId': invoice.globalId,
          'invoiceNumber': invoice.invoiceNumber,
          'globalId': globalId,
          'warehouseId': world.warehouseId,
          'userId': world.userId,
          'totalReturn': 360,
          'items': [
            {'productId': productId, 'returnQuantity': 6, 'unitCost': 60},
          ],
        }),
      ),
    );

    expect((await post('purchase-return-cap-one')).statusCode, 200);
    final rejected = await post('purchase-return-cap-two');
    expect(rejected.statusCode, isNot(200));
    expect(await world.db.getPurchaseReturnedQtyByProduct(invoiceId), {
      productId: 6,
    });
  });
}
