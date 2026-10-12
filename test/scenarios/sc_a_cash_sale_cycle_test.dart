// سيناريو (أ): دورة بيع نقدي كاملة — منتج بكمية وسعر وتكلفة ← فاتورة نقدية عبر
// SalesTransactionOrchestrator ← قيد متوازن + نقص مخزون + زيادة خزينة + ترقيم تسلسلي.
import 'package:flutter_test/flutter_test.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;

  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('A1', price: 100, cost: 60, stock: 50);
  });
  tearDown(() => w.dispose());

  test('(أ) بيع 3 × 100 نقداً: قيد 300/180، مخزون 47، خزينة 300', () async {
    final before = await w.journalTotals();
    final r = await w.sell([w.line(product, 3, 100)]);

    // الفاتورة نفسها
    final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
    expect(inv.total, closeTo(300, kEps));
    expect(inv.paid, closeTo(300, kEps));
    expect(inv.status, isNot('voided'));

    // القيد: مدين نقدية 300 + تكلفة مبيعات 180 / دائن مبيعات 300 + مخزون 180
    final lines = await w.linesOf('sales_invoice', r.invoiceId!);
    double dr(String code) => lines
        .where((l) => l['code'] == code)
        .fold(0.0, (s, l) => s + (l['debit'] as num));
    double cr(String code) => lines
        .where((l) => l['code'] == code)
        .fold(0.0, (s, l) => s + (l['credit'] as num));
    expect(dr('111-00001'), closeTo(300, kEps), reason: 'الخزينة مدينة بالمقبوض');
    expect(cr('4121'), closeTo(300, kEps), reason: 'إيراد المبيعات');
    expect(dr('5211'), closeTo(180, kEps), reason: 'تكلفة المبيعات = 3 × 60');
    expect(cr('1136'), closeTo(180, kEps), reason: 'خروج مخزون بالتكلفة');

    final after = await w.journalTotals();
    expect(after.debit - before.debit, closeTo(480, kEps));
    expect(after.credit - before.credit, closeTo(480, kEps));
    expect(await w.unbalancedEntries(), isEmpty);

    // المخزون (الصنف + رصيد المخزن) والخزينة
    expect(await w.stock(product), closeTo(47, kEps));
    expect(await w.whQty(product, w.warehouseId), closeTo(47, kEps));
    expect(await w.safeBalance(), closeTo(300, kEps));
  });

  test('(أ) أرقام الفواتير تسلسلية بلا فجوات ولا تكرار', () async {
    final ids = <int>[];
    final numbers = <String>[];
    for (var i = 0; i < 3; i++) {
      final r = await w.sell([w.line(product, 1, 100)]);
      ids.add(r.invoiceId!);
      numbers.add((await w.db.getSalesInvoiceById(r.invoiceId!))!.invoiceNumber);
    }
    expect(numbers, ['SINV-1', 'SINV-2', 'SINV-3']);
    expect(ids.toSet(), hasLength(3));
    expect(await w.stock(product), closeTo(47, kEps));
    expect(await w.safeBalance(), closeTo(300, kEps));
  });

  test('(أ) بيع بضريبة 14%: الإجمالي 342 والضريبة 42 تُقيَّد دائنة', () async {
    final r = await w.sell([w.line(product, 3, 100)], tax: true, paid: 342);
    final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
    expect(inv.tax, closeTo(42, kEps));
    expect(inv.total, closeTo(342, kEps));
    expect(await w.safeBalance(), closeTo(342, kEps));
    final lines = await w.linesOf('sales_invoice', r.invoiceId!);
    final vat = lines
        .where((l) => l['code'] == '2121')
        .fold(0.0, (s, l) => s + (l['credit'] as num));
    expect(vat, closeTo(42, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
  });
}
