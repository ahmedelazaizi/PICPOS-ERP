import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  late int customer;

  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('C2', price: 100, cost: 60, stock: 50);
    customer = await w.addCustomer('عميل C2');
  });

  tearDown(() => w.dispose());

  test('إلغاء مستند مرتجع مستقل يعكس كل أثره ثم يرفض التكرار', () async {
    final sale = await w.sell([w.line(product, 5, 100)],
        customerId: customer, method: 'credit');
    final original = (await (w.db.select(w.db.salesInvoices)
          ..where((i) => i.id.equals(sale.invoiceId!)))
        .getSingle());
    final returnId = await w.db.createSalesInvoice(
      warehouseId: w.warehouseId,
      userId: w.userId,
      customerId: customer,
      subtotal: 200,
      discount: 0,
      tax: 0,
      total: 200,
      paid: 0,
      paymentMethod: 'credit',
      saleType: 'return',
      notes: localReturnLinkNote(original.id, originalGlobalId: original.globalId),
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: product,
          quantity: 2,
          unitPrice: 100,
          total: 200,
          costPrice: const Value(60),
        ),
      ],
    );

    expect(await w.stock(product), closeTo(47, kEps));
    expect(await w.safeBalance(), closeTo(0, kEps));

    await w.container.read(returnsRepositoryProvider).cancelSalesReturn(
          invoice: original,
          userId: w.userId,
          userName: 'مستخدم C2',
        );

    final cancelled = (await (w.db.select(w.db.salesInvoices)
          ..where((i) => i.id.equals(returnId)))
        .getSingle());
    expect(cancelled.status, 'voided');
    expect(cancelled.isDeleted, isTrue);
    expect((await (w.db.select(w.db.salesInvoices)
              ..where((i) => i.id.equals(original.id)))
            .getSingle())
        .status, 'completed');
    expect(await w.stock(product), closeTo(45, kEps));
    expect(await w.safeBalance(), closeTo(0, kEps));
    expect(await w.partyBalance(customer), closeTo(500, kEps));
    expect(await w.unbalancedEntries(), isEmpty);
    final trial = await w.trialBalanceTotals();
    expect(trial.debit, closeTo(trial.credit, kEps));

    await expectLater(
      w.container.read(returnsRepositoryProvider).cancelSalesReturn(
            invoice: (await (w.db.select(w.db.salesInvoices)
                  ..where((i) => i.id.equals(original.id)))
                .getSingle()),
            userId: w.userId,
            userName: 'مستخدم C2',
          ),
      throwsA(isA<StateError>()),
    );
  });
}
