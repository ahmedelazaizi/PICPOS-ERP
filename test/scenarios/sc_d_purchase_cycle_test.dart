// سيناريو (د): دورة شراء — فاتورة لمورد ← مخزون بتكلفة صحيحة ← قيد متوازن ← سند صرف.
// سيناريو (هـ): مرتجع مشتريات.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';
import 'package:ural_erp/domain/usecases/treasury/create_voucher_usecase.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  late int supplier;

  setUp(() async {
    w = await ScenarioWorld.create();
    await w.grant(PermissionCodes.treasuryPaymentsCreate);
    // مخزون افتتاحي 10 بتكلفة 50 (لاختبار المتوسط المرجّح)
    product = await w.addProduct('D1', price: 100, cost: 50, stock: 10);
    supplier = await w.addSupplier('مورد الدورة');
  });
  tearDown(() => w.dispose());

  PurchasesRepository repo() => w.container.read(purchasesRepositoryProvider);

  Future<int> buy(double qty, double cost, {double paid = 0}) =>
      repo().createInvoice(CreatePurchaseInvoiceParams(
        supplierId: supplier,
        warehouseId: w.warehouseId,
        paid: paid,
        paymentMethod: paid > 0 ? 'cash' : 'credit',
        safeId: paid > 0 ? w.cashSafeId : null,
        userId: w.userId,
        items: [
          PurchaseItemParams(
              productId: product,
              quantity: qty,
              unitCost: cost,
              salePrice: 100,
              taxRate: 0,
              taxAmount: 0)
        ],
      ));

  test('(د) شراء آجل 10 × 60: مخزون 20، تكلفة متوسطة 55، المورد دائن 600',
      () async {
    final id = await buy(10, 60);

    expect(await w.stock(product), closeTo(20, kEps));
    expect(await w.whQty(product, w.warehouseId), closeTo(20, kEps));
    final p = (await w.db.getProductById(product))!;
    expect(p.costPrice, closeTo(55, kEps), reason: '(10×50 + 10×60) / 20');

    expect(await w.partyBalance(supplier), closeTo(600, kEps));
    // المخزون مدين 600 (القيمة المشتراة)، الموردون دائنون 600
    final lines = await w.linesOf('purchase_invoice', id);
    expect(lines.fold<double>(0, (s, l) => s + (l['debit'] as num)),
        closeTo(600, kEps));
    expect(lines.fold<double>(0, (s, l) => s + (l['credit'] as num)),
        closeTo(600, kEps));
    expect(await w.accountNet('113'), closeTo(600, kEps));
    expect(await w.accountNet('211'), closeTo(-600, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
  });

  test('(د) سند صرف للمورد 400 ثم الباقي: الرصيد 600 → 200 → 0', () async {
    await buy(10, 60);
    // تمويل الخزينة: بيع نقدي 6 × 100 = 600
    await w.sell([w.line(product, 6, 100)]);
    expect(await w.safeBalance(), closeTo(600, kEps));

    final vouchers =
        CreateVoucherUseCase(w.container.read(treasuryRepositoryProvider));
    await vouchers.createPayment(
        amount: 400,
        category: 'suppliers',
        safeId: w.cashSafeId,
        partyId: supplier,
        userId: w.userId);
    expect(await w.partyBalance(supplier), closeTo(200, kEps));
    expect(await w.safeBalance(), closeTo(200, kEps));
    expect(await w.accountNet('211'), closeTo(-200, kEps));

    await vouchers.createPayment(
        amount: 200,
        category: 'suppliers',
        safeId: w.cashSafeId,
        partyId: supplier,
        userId: w.userId);
    expect(await w.partyBalance(supplier), closeTo(0, kEps));
    expect(await w.safeBalance(), closeTo(0, kEps));
    expect(await w.accountNet('211'), closeTo(0, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
    expect(await w.db.getPartyBalanceMismatches(), isEmpty);
  });

  test('(د) شراء نقدي مدفوع بالكامل: لا التزام على المورد والخزينة تنقص', () async {
    await w.sell([w.line(product, 8, 100)]); // خزينة 800
    await buy(5, 60, paid: 300);
    expect(await w.partyBalance(supplier), closeTo(0, kEps));
    expect(await w.safeBalance(), closeTo(500, kEps));
    expect(await w.accountNet('211'), closeTo(0, kEps));
  });

  test('(هـ) مرتجع مشتريات 4 من 10: المخزون −4 والمورد 600 → 360', () async {
    final id = await buy(10, 60);
    final invoice = (await repo().getRawInvoiceById(id))!;
    final items = await repo().getInvoiceItemsWithProduct(id);
    final it = items.single;

    final refunded = await repo().processPurchaseReturn(
      invoice: invoice,
      reason: 'بضاعة تالفة',
      returnItems: [
        PurchaseReturnItem(
            itemId: it.item.id,
            productId: product,
            returnQuantity: 4,
            unitCost: it.item.unitCost,
            taxAmount: 0,
            originalQuantity: it.item.quantity,
            quantityInBase: it.item.quantityInBase)
      ],
    );

    expect(refunded, closeTo(240, kEps));
    expect(await w.stock(product), closeTo(16, kEps));
    expect(await w.whQty(product, w.warehouseId), closeTo(16, kEps));
    expect(await w.partyBalance(supplier), closeTo(360, kEps));
    expect(await w.accountNet('211'), closeTo(-360, kEps));
    expect(await w.accountNet('113'), closeTo(360, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
  });
}
