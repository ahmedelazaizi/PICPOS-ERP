import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import '../../scenarios/scenario_world.dart';

Future<void> _expectAccountBalancesMatchLedger(ScenarioWorld w) async {
  final rows = await w.db
      .customSelect(
        'SELECT a.code, a.balance, COALESCE(SUM(CASE WHEN e.id IS NOT NULL THEN l.debit - l.credit ELSE 0 END), 0) ledger '
        'FROM accounts a LEFT JOIN journal_entry_lines l ON l.account_id = a.id '
        'LEFT JOIN journal_entries e ON e.id = l.entry_id AND e.is_deleted = 0 '
        'GROUP BY a.id, a.code, a.balance',
      )
      .get();
  for (final row in rows) {
    expect(
      (row.data['balance'] as num).toDouble(),
      closeTo((row.data['ledger'] as num).toDouble(), kEps),
      reason:
          'GL account ${row.data['code']} balance differs from active journal sum',
    );
  }
}

void main() {
  late ScenarioWorld w;
  late int product;
  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('PHASE1', price: 10, cost: 4, stock: 5);
  });
  tearDown(() => w.dispose());

  Future<int> quickReturn({String method = 'cash', int? safeId}) async {
    await w.db.createSalesInvoice(
      customerId: null,
      warehouseId: w.warehouseId,
      userId: w.userId,
      subtotal: 10,
      discount: 0,
      tax: 0,
      total: 10,
      paid: 10,
      paymentMethod: method,
      cashSafeId: method == 'cash' ? (safeId ?? w.cashSafeId) : null,
      bankSafeId: method == 'bank' ? safeId : null,
      bankAmount: method == 'bank' ? 10 : 0,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: product,
          quantity: 1,
          unitPrice: 10,
          total: 10,
          costPrice: const Value(4),
        ),
      ],
    );
    return w.db.createSalesInvoice(
        customerId: null,
        warehouseId: w.warehouseId,
        userId: w.userId,
        subtotal: 10,
        discount: 0,
        tax: 0,
        total: 10,
        paid: 10,
        paymentMethod: method,
        saleType: 'return',
        cashSafeId: safeId ?? w.cashSafeId,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: product,
            quantity: 1,
            unitPrice: 10,
            total: 10,
            costPrice: const Value(4),
          ),
        ],
      );
  }

  test(
    'F03 quick cash return credits the actual linked drawer account',
    () async {
      await quickReturn();
      expect(await w.safeBalance(), closeTo(0, kEps));
      expect(await w.accountNet('111-00001'), closeTo(0, kEps));
      expect(await w.accountNet('1111'), closeTo(0, kEps));
      final drawer = await w.db
          .customSelect(
            'select balance from accounts where code = ?',
            variables: const [Variable<String>('111-00001')],
          )
          .getSingle();
      expect(
        (drawer.data['balance'] as num).toDouble(),
        closeTo(await w.safeBalance(), kEps),
      );
    },
  );

  test('F03 bank return does not change drawer ledger', () async {
    final bank = await w.db.getDefaultSafeByType('bank');
    expect(bank, isNotNull);
    await quickReturn(method: 'bank', safeId: bank!.id);
    expect(await w.safeBalance(), closeTo(0, kEps));
    expect(await w.accountNet('111-00001'), closeTo(0, kEps));
  });

  group('SP-02 invoice edits', () {
    SalesInvoiceItemsCompanion line(
      double qty,
      double price, {
      int? productId,
    }) => SalesInvoiceItemsCompanion.insert(
      invoiceId: 0,
      productId: productId ?? product,
      quantity: qty,
      unitPrice: price,
      total: qty * price,
      costPrice: const Value(4),
    );

    test(
      'editing unlocked posted cash invoice keeps GL, safe and stock aligned',
      () async {
        final sale = await w.sell([w.line(product, 2, 10)]);
        final original = await w.db
            .customSelect(
              "select id from journal_entries where reference_id = ? and reference_type in ('sale','sales_invoice','cash_sale','credit_sale') and is_deleted=0 limit 1",
              variables: [Variable<int>(sale.invoiceId!)],
            )
            .getSingle();
        await w.db.updateSalesInvoice(
          invoiceId: sale.invoiceId!,
          subtotal: 36,
          discount: 3.6,
          tax: 0,
          total: 32.4,
          paid: 32.4,
          paymentMethod: 'cash',
          items: [line(3, 12)],
          userId: w.userId,
        );
        final originalStillExists = await w.db
            .customSelect(
              'select is_deleted from journal_entries where id = ?',
              variables: [Variable<int>(original.data['id'] as int)],
            )
            .getSingle();
        final reversal = await w.db
            .customSelect(
              "select count(*) n from journal_entries where reference_type='reversal' and reference_id=? and is_deleted=0",
              variables: [Variable<int>(original.data['id'] as int)],
            )
            .getSingle();
        expect(originalStillExists.data['is_deleted'], 0);
        expect(reversal.data['n'], 1);
        expect(await w.accountNet('111'), closeTo(await w.safeBalance(), kEps));
        expect(await w.accountNet('4121'), closeTo(-36, kEps));
        expect(await w.accountNet('4212'), closeTo(3.6, kEps));
        expect(
          await w.accountNet('4121') + await w.accountNet('4212'),
          closeTo(-32.4, kEps),
        );
        expect(await w.accountNet('5211'), closeTo(12, kEps));
        expect(await w.stock(product), closeTo(2, kEps));
        await _expectAccountBalancesMatchLedger(w);
      },
    );

    test('unchanged invoice edit is idempotent in journal count', () async {
      final sale = await w.sell([w.line(product, 2, 10)]);
      final before = await w.db
          .customSelect(
            'select count(*) n from journal_entries where is_deleted=0',
          )
          .getSingle();
      await w.db.updateSalesInvoice(
        invoiceId: sale.invoiceId!,
        subtotal: 20,
        discount: 0,
        tax: 0,
        total: 20,
        paid: 20,
        paymentMethod: 'cash',
        items: [line(2, 10)],
        userId: w.userId,
      );
      final after = await w.db
          .customSelect(
            'select count(*) n from journal_entries where is_deleted=0',
          )
          .getSingle();
      expect(after.data['n'], before.data['n']);
    });

    test(
      'editing invoice after partial return is refused and preserves return state',
      () async {
        final sale = await w.sell([w.line(product, 2, 10)]);
        await w.returnItems(sale.invoiceId!, product, 1);
        final before = (await w.db.getSalesInvoiceById(sale.invoiceId!))!;
        await expectLater(
          w.db.updateSalesInvoice(
            invoiceId: sale.invoiceId!,
            subtotal: 10,
            discount: 0,
            tax: 0,
            total: 10,
            paid: 10,
            paymentMethod: 'cash',
            items: [line(1, 10)],
            userId: w.userId,
          ),
          throwsA(isA<StateError>()),
        );
        final after = (await w.db.getSalesInvoiceById(sale.invoiceId!))!;
        expect(after.status, before.status);
      },
    );

    test('editing credit invoice preserves AR and journal alignment', () async {
      final customer = await w.addCustomer('credit edit');
      final sale = await w.sell(
        [w.line(product, 2, 10)],
        customerId: customer,
        method: 'credit',
        paid: 0,
      );
      await w.db.updateSalesInvoice(
        invoiceId: sale.invoiceId!,
        subtotal: 30,
        discount: 0,
        tax: 0,
        total: 30,
        paid: 0,
        paymentMethod: 'credit',
        items: [line(3, 10)],
        userId: w.userId,
      );
      expect(
        await w.accountNet('1121'),
        closeTo(await w.partyBalance(customer), kEps),
      );
      expect(await w.accountNet('1121'), closeTo(30, kEps));
      expect(await w.accountNet('5211'), closeTo(12, kEps));
      await _expectAccountBalancesMatchLedger(w);
    });
  });
}
