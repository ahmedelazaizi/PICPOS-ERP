import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart' show salesRepositoryProvider;
import '../../audit_repro/financial_statements/_fs_world.dart';

void main() {
  late ScenarioWorld world;
  late FsCycle cycle;
  var worldCreated = false;

  setUpAll(() async {
    world = await ScenarioWorld.create();
    worldCreated = true;
    cycle = FsCycle(world);
    await cycle.run(payroll: false, assets: false);
  });

  tearDownAll(() async {
    if (worldCreated) await world.dispose();
  });

  Future<double> netSales() async =>
      -(await world.accountNet('4121')) -
      (await world.accountNet('4212')) -
      (await world.accountNet('4211'));

  test('settlement and sale discounts use contra accounts without changing net revenue', () async {
    expect(await world.accountNet('6215'), closeTo(5, 0.005));
    expect(await world.accountNet('4316'), closeTo(-10, 0.005));
    expect(await world.accountNet('5205'), closeTo(0, 0.005));
    expect(await world.accountNet('4202'), closeTo(0, 0.005));

    final grossSalesCredit = -(await world.accountNet('4121'));
    final saleDiscount = await world.accountNet('4212');
    final returns = await world.accountNet('4211');
    expect(grossSalesCredit, closeTo(500, 0.005));
    expect(saleDiscount, closeTo(30, 0.005));
    expect(grossSalesCredit - saleDiscount - returns, closeTo(376.667, 0.01));
  });

  test('account-transfer vouchers use the same mapped settlement purposes', () async {
    final treasury = await world.db.getLeafAccountByPurpose('cash');
    final receivables = await world.db.getLeafAccountByPurpose('receivables');
    final payables = await world.db.getLeafAccountByPurpose('payables');
    expect(treasury, isNotNull);
    expect(receivables, isNotNull);
    expect(payables, isNotNull);
    final allowedBefore = await world.accountNet('6215');
    final purchaseBefore = await world.accountNet('4316');

    await world.db.createAccountTransferVoucher(
      isReceipt: true,
      amount: 20,
      discount: 2,
      treasuryAccountId: treasury!.id,
      beneficiaryAccountId: receivables!.id,
      category: 'customers',
      documentSafeId: world.cashSafeId,
    );
    await world.db.createAccountTransferVoucher(
      isReceipt: false,
      amount: 30,
      discount: 3,
      treasuryAccountId: treasury.id,
      beneficiaryAccountId: payables!.id,
      category: 'suppliers',
      documentSafeId: world.cashSafeId,
    );
    expect(await world.accountNet('6215') - allowedBefore, closeTo(2, 0.005));
    expect(await world.accountNet('4316') - purchaseBefore, closeTo(-3, 0.005));
  });

  test('inclusive-tax sale keeps net revenue after disclosure discount', () async {
    await world.db.setSetting('prices_include_tax', 'true');
    final before = await netSales();
    final sale = await world.sales.completeSalesTransaction(SaleRequest(
      items: [world.line(cycle.product, 1, 100)],
      warehouseId: world.warehouseId,
      userId: world.userId,
      paymentMethod: 'cash',
      paidAmount: 80,
      taxEnabled: true,
      taxPercent: 14,
      invoiceDiscountAmount: 20,
      pricesIncludeTax: true,
      cashSafeId: world.cashSafeId,
    ));
    expect(sale.isSuccess, isTrue, reason: sale.errorMessage);
    final invoice = (await world.db.getSalesInvoiceById(sale.invoiceId!))!;
    expect(await netSales() - before, closeTo(invoice.total - invoice.tax, 0.01));
    await world.db.setSetting('prices_include_tax', 'false');
  });

  test('editing a discounted credit invoice preserves the posting basis', () async {
    final before = await netSales();
    final discountBefore = await world.accountNet('4212');
    await world.container.read(salesRepositoryProvider).updateFullSalesInvoice(
      invoiceId: cycle.creditInvoice,
      userId: world.userId,
      customerId: cycle.customer,
      warehouseId: world.warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      notes: 'phase6a repost check',
      items: [world.line(cycle.product, 2, 100)],
    );
    expect(await netSales(), closeTo(before, 0.01));
    expect(await world.accountNet('4212'), closeTo(discountBefore, 0.005));
  });

  test('voiding a discounted invoice reverses every new posting line', () async {
    final result = await cycle.sale(
      [world.line(cycle.product, 1, 100)],
      method: 'cash',
      paid: 91.2,
      discountAmount: 20,
    );
    final beforeVoid = await netSales();
    await world.db.voidSalesInvoice(
      result.invoiceId!,
      reason: 'phase6a reversal check',
      deletedBy: world.userId,
    );
    expect(await netSales(), closeTo(beforeVoid - 80, 0.01));
  });
}
