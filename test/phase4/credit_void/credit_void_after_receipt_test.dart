import 'package:flutter_test/flutter_test.dart';
import '../../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  late int customer;

  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('CREDIT-VOID', price: 100, cost: 60, stock: 10);
    customer = await w.addCustomer('عميل رصيد دائن');
  });
  tearDown(() => w.dispose());

  Future<int> sellCredit() async => (await w.sell(
        [w.line(product, 2, 100)], customerId: customer, method: 'credit', paid: 0,
      )).invoiceId!;

  Future<void> cancel(int id) => w.db.voidSalesInvoice(id, deletedBy: w.userId);

  Future<void> expectFullyReversed() async {
    expect(await w.stock(product), closeTo(10, kEps));
    expect(await w.whQty(product, w.warehouseId), closeTo(10, kEps));
    expect(await w.accountNet('4'), closeTo(0, kEps));
    expect(await w.accountNet('5211'), closeTo(0, kEps));
    expect(await w.accountNet('1136'), closeTo(0, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
  }

  test('AUD-SP-04 full collection remains a customer credit after void', () async {
    final id = await sellCredit();
    await w.db.addSalesPayment(invoiceId: id, amount: 200, safeId: w.cashSafeId, userId: w.userId);
    await cancel(id);
    expect(await w.partyBalance(customer), closeTo(-200, kEps));
    expect(await w.accountNet('1121'), closeTo(-200, kEps));
    expect(await w.safeBalance(), closeTo(200, kEps));
    expect(await w.accountNet('111'), closeTo(200, kEps));
    expect(await w.db.getPartyBalanceMismatches(), isEmpty);
    await expectFullyReversed();
  });

  test('AUD-SP-04 multiple partial receipts remain customer credit after void', () async {
    final id = await sellCredit();
    await w.db.addSalesPayment(invoiceId: id, amount: 50, safeId: w.cashSafeId, userId: w.userId);
    await w.db.addSalesPayment(invoiceId: id, amount: 30, safeId: w.cashSafeId, userId: w.userId);
    await cancel(id);
    expect(await w.partyBalance(customer), closeTo(-80, kEps));
    expect(await w.accountNet('1121'), closeTo(-80, kEps));
    expect(await w.safeBalance(), closeTo(80, kEps));
    expect(await w.db.getPartyBalanceMismatches(), isEmpty);
    await expectFullyReversed();
  });

  test('AUD-SP-04 repeated void is idempotent across ledgers and stock', () async {
    final id = await sellCredit();
    await w.db.addSalesPayment(invoiceId: id, amount: 50, safeId: w.cashSafeId, userId: w.userId);
    await cancel(id);
    final beforeTotals = await w.journalTotals();
    final before = (
      party: await w.partyBalance(customer),
      ar: await w.accountNet('1121'),
      cash: await w.safeBalance(),
      stock: await w.stock(product),
      entries: (await w.db.select(w.db.journalEntries).get()).length,
      movements: (await w.db.select(w.db.stockMovements).get()).length,
      safeTransactions: (await w.db.select(w.db.safeTransactions).get()).length,
    );
    await expectLater(cancel(id), throwsA(isA<Exception>()));
    final afterTotals = await w.journalTotals();
    expect(await w.partyBalance(customer), before.party);
    expect(await w.accountNet('1121'), before.ar);
    expect(await w.safeBalance(), before.cash);
    expect(await w.stock(product), before.stock);
    expect((await w.db.select(w.db.journalEntries).get()).length, before.entries);
    expect((await w.db.select(w.db.stockMovements).get()).length, before.movements);
    expect((await w.db.select(w.db.safeTransactions).get()).length, before.safeTransactions);
    expect(afterTotals.debit, beforeTotals.debit);
    expect(afterTotals.credit, beforeTotals.credit);
  });

  test('credit void without receipts clears receivable', () async {
    final id = await sellCredit();
    await cancel(id);
    expect(await w.partyBalance(customer), closeTo(0, kEps));
    expect(await w.accountNet('1121'), closeTo(0, kEps));
    expect(await w.safeBalance(), closeTo(0, kEps));
    await expectFullyReversed();
  });

  test('invoice with return remains blocked from void', () async {
    final r = await w.sell([w.line(product, 2, 100)]);
    await w.returnItems(r.invoiceId!, product, 1);
    await expectLater(cancel(r.invoiceId!), throwsA(isA<Exception>()));
  });

  test('cash invoice void behavior remains unchanged', () async {
    final r = await w.sell([w.line(product, 2, 100)]);
    await cancel(r.invoiceId!);
    expect(await w.safeBalance(), closeTo(0, kEps));
    expect(await w.stock(product), closeTo(10, kEps));
    expect(await w.accountNet('4'), closeTo(0, kEps));
    expect(await w.accountNet('5211'), closeTo(0, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
  });
}
