import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import '../../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('EDIT-GUARD', price: 8, cost: 5, stock: 8);
  });
  tearDown(() => w.dispose());

  Future<List<int>> counts(int invoiceId) async => [
    for (final table in ['journal_entries', 'stock_movements', 'safe_transactions'])
      (await w.db.customSelect('SELECT COUNT(*) n FROM $table WHERE reference_id=?',
        variables: [Variable<int>(invoiceId)]).getSingle()).read<int>('n'),
  ];

  Future<void> edit(int invoiceId, {required int? customerId, required String method, required double paid}) =>
      w.container.read(salesRepositoryProvider).updateFullSalesInvoice(
        invoiceId: invoiceId, userId: w.userId, customerId: customerId,
        warehouseId: w.warehouseId, paid: paid, paymentMethod: method,
        items: [w.line(product, 2, 8)],
      );

  test('rejects repository edit after live partial cash return without postings', () async {
    final sale = await w.sell([w.line(product, 2, 8)]);
    expect(await w.returnItems(sale.invoiceId!, product, 1), isTrue);
    final before = await counts(sale.invoiceId!);
    await expectLater(edit(sale.invoiceId!, customerId: null, method: 'cash', paid: 16),
      throwsA(isA<StateError>().having((e) => e.message, 'message',
        'لا يمكن تعديل فاتورة عليها مرتجع. ألغِ المرتجع أو حرّر فاتورة بديلة.')));
    expect(await counts(sale.invoiceId!), before);
  });

  test('rejects repository edit after a live partial credit return', () async {
    final customer = await w.addCustomer('credit return guard');
    final sale = await w.sell([w.line(product, 2, 8)], customerId: customer, method: 'credit', paid: 0);
    expect(await w.returnItems(sale.invoiceId!, product, 1), isTrue);
    final before = await counts(sale.invoiceId!);
    await expectLater(edit(sale.invoiceId!, customerId: customer, method: 'credit', paid: 0),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('لا يمكن تعديل فاتورة عليها مرتجع'))));
    expect(await counts(sale.invoiceId!), before);
  });

  test('cancelled return does not block repository edit', () async {
    final sale = await w.sell([w.line(product, 2, 8)]);
    await w.returnItems(sale.invoiceId!, product, 1);
    await w.container.read(returnsRepositoryProvider).cancelSalesReturn(
      invoice: (await w.db.getSalesInvoiceById(sale.invoiceId!))!,
      userId: w.userId,
      userName: 'scenario_user',
    );
    await edit(sale.invoiceId!, customerId: null, method: 'cash', paid: 16.01);
  });

  test('repository edit without a return still reverses and reposts', () async {
    final sale = await w.sell([w.line(product, 2, 8)]);
    final before = await counts(sale.invoiceId!);
    await edit(sale.invoiceId!, customerId: null, method: 'cash', paid: 16.01);
    expect((await w.db.getSalesInvoiceById(sale.invoiceId!))!.paid, 16.01);
    expect((await counts(sale.invoiceId!))[0], greaterThan(before[0]));
  });
}
