import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;

  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('C4', price: 100, cost: 60, stock: 50);
  });

  tearDown(() => w.dispose());

  test('تقرير الإلغاء بعد المرتجع يعرض التاريخي الحي ويستبعد السليم', () async {
    final noReturn = await w.sell([w.line(product, 1, 100)]);
    await w.db.voidSalesInvoice(noReturn.invoiceId!, deletedBy: w.userId);

    final historical = await w.sell([w.line(product, 3, 100)]);
    await w.returnItems(historical.invoiceId!, product, 1);
    // تجاوز الحارس هنا مقصود لبناء حالة تاريخية: تعديل الحالة مباشرة لا ينفذ أي أثر مالي.
    await (w.db.update(
      w.db.salesInvoices,
    )..where((invoice) => invoice.id.equals(historical.invoiceId!))).write(
      const SalesInvoicesCompanion(
        status: Value('voided'),
        isDeleted: Value(true),
      ),
    );

    final cancelledReturn = await w.sell([w.line(product, 2, 100)]);
    await w.returnItems(cancelledReturn.invoiceId!, product, 1);
    final cancelledInvoice =
        (await (w.db.select(w.db.salesInvoices)..where(
              (invoice) => invoice.id.equals(cancelledReturn.invoiceId!),
            ))
            .getSingle());
    await w.container
        .read(returnsRepositoryProvider)
        .cancelSalesReturn(
          invoice: cancelledInvoice,
          userId: w.userId,
          userName: 'مستخدم السيناريو',
        );
    await w.db.voidSalesInvoice(
      cancelledReturn.invoiceId!,
      deletedBy: w.userId,
    );

    final report = await w.db.voidedAfterReturnReport();
    expect(report.map((row) => row.invoiceId), contains(historical.invoiceId));
    expect(
      report.map((row) => row.invoiceId),
      isNot(contains(noReturn.invoiceId)),
    );
    expect(
      report.map((row) => row.invoiceId),
      isNot(contains(cancelledReturn.invoiceId)),
    );

    final row = report.singleWhere(
      (item) => item.invoiceId == historical.invoiceId,
    );
    expect(row.invoiceNumber, isNotEmpty);
    expect(row.total, closeTo(300, kEps));
    expect(row.returnedQuantity, closeTo(1, kEps));
    expect(row.returnedValue, closeTo(100, kEps));
    expect(row.imbalanceIndicators, isNotEmpty);
  });
}
