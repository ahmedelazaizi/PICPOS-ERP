import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import '../../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld world;
  late int productId;

  setUp(() async {
    world = await ScenarioWorld.create();
    productId = await world.addProduct('LIVE-EDIT', price: 6.99, cost: 4.25, stock: 5);
  });

  tearDown(() => world.dispose());

  test('sales invoice screen repository edit reposts cost and stock', () async {
    final sale = await world.sell([world.line(productId, 2, 6.99)]);
    final cashBeforeEdit = await world.safeBalance();
    final originalEntry = await world.db.customSelect(
      "SELECT id FROM journal_entries WHERE reference_type IN ('sale','sales_invoice','cash_sale','credit_sale') AND reference_id=? AND is_deleted=0 ORDER BY id LIMIT 1",
      variables: [Variable<int>(sale.invoiceId!)],
    ).getSingle();
    final productBeforeEdit = await world.db.getProductById(productId);
    expect(productBeforeEdit!.currentStock, 3);

    await world.container.read(salesRepositoryProvider).updateFullSalesInvoice(
      invoiceId: sale.invoiceId!,
      userId: world.userId,
      warehouseId: world.warehouseId,
      paid: 13.98,
      paymentMethod: 'cash',
      items: [world.line(productId, 3, 6.99)],
    );

    final postedCosts = await world.db.customSelect(
      "SELECT a.code, SUM(l.debit) debit, SUM(l.credit) credit "
      "FROM journal_entries e JOIN journal_entry_lines l ON l.entry_id=e.id "
      "JOIN accounts a ON a.id=l.account_id "
      "WHERE e.reference_type='sale' AND e.reference_id=? AND e.is_deleted=0 "
      "GROUP BY a.code",
      variables: [Variable<int>(sale.invoiceId!)],
    ).get();
    final cogs = postedCosts.singleWhere((row) => row.data['code'] == '5211');
    final inventory = postedCosts.singleWhere((row) => row.data['code'] == '1136');
    expect((cogs.data['debit'] as num).toDouble(), closeTo(12.75, kEps));
    expect((inventory.data['credit'] as num).toDouble(), closeTo(12.75, kEps));
    final oldEntry = await world.db.customSelect(
      'SELECT is_deleted FROM journal_entries WHERE id=?',
      variables: [Variable<int>(originalEntry.read<int>('id'))],
    ).getSingle();
    final reversals = await world.db.customSelect(
      "SELECT COUNT(*) count FROM journal_entries WHERE reference_type='reversal' AND reference_id=? AND is_deleted=0",
      variables: [Variable<int>(originalEntry.read<int>('id'))],
    ).getSingle();
    expect(oldEntry.read<int>('is_deleted'), 0);
    expect(reversals.read<int>('count'), 1);

    final originalMoves = await world.db.customSelect(
      "SELECT COUNT(*) count FROM stock_movements WHERE product_id=? AND reference_id=? AND movement_type='sale'",
      variables: [Variable<int>(productId), Variable<int>(sale.invoiceId!)],
    ).getSingle();
    expect((originalMoves.data['count'] as int), 1);
    final editMoves = await world.db.customSelect(
      "SELECT COALESCE(SUM(quantity),0) quantity FROM stock_movements "
      "WHERE product_id=? AND reference_id=? AND movement_type IN ('edit_reversal','edit_adjustment')",
      variables: [Variable<int>(productId), Variable<int>(sale.invoiceId!)],
    ).getSingle();
    expect((editMoves.data['quantity'] as num).toDouble(), closeTo(-1, kEps));
    expect(await world.stock(productId), closeTo(2, kEps));
    expect(await world.whQty(productId, world.warehouseId), closeTo(2, kEps));
    expect(await world.safeBalance(), closeTo(cashBeforeEdit, kEps));
    expect(await world.accountNet('111-00001'), closeTo(await world.safeBalance(), kEps));
    final accounts = await world.db.customSelect(
      'SELECT a.code,a.balance,COALESCE(SUM(CASE WHEN e.is_deleted=0 THEN l.debit-l.credit ELSE 0 END),0) ledger '
      'FROM accounts a LEFT JOIN journal_entry_lines l ON l.account_id=a.id '
      'LEFT JOIN journal_entries e ON e.id=l.entry_id GROUP BY a.id,a.code,a.balance',
    ).get();
    for (final account in accounts) {
      expect(
        (account.data['balance'] as num).toDouble(),
        closeTo((account.data['ledger'] as num).toDouble(), kEps),
        reason: 'GL account ${account.data['code']} must equal active journal lines',
      );
    }
  });

  test('unchanged repository edit adds no journal entries or stock movements', () async {
    final sale = await world.sell([world.line(productId, 2, 6.99)]);
    Future<int> rowCount(String table) async =>
        (await world.db.customSelect(
          'SELECT COUNT(*) count FROM $table WHERE reference_id=?',
          variables: [Variable<int>(sale.invoiceId!)],
        ).getSingle()).read<int>('count');

    final entriesBefore = await rowCount('journal_entries');
    final movementsBefore = await rowCount('stock_movements');
    await world.container.read(salesRepositoryProvider).updateFullSalesInvoice(
      invoiceId: sale.invoiceId!,
      userId: world.userId,
      warehouseId: world.warehouseId,
      paid: 13.98,
      paymentMethod: 'cash',
      items: [world.line(productId, 2, 6.99)],
    );
    expect(await rowCount('journal_entries'), entriesBefore);
    expect(await rowCount('stock_movements'), movementsBefore);
  });

  test('reducing repository-edited quantity restores stock and reprices COGS', () async {
    final sale = await world.sell([world.line(productId, 3, 6.99)]);
    await world.container.read(salesRepositoryProvider).updateFullSalesInvoice(
      invoiceId: sale.invoiceId!,
      userId: world.userId,
      warehouseId: world.warehouseId,
      paid: 6.99,
      paymentMethod: 'cash',
      items: [world.line(productId, 1, 6.99)],
    );
    expect(await world.stock(productId), closeTo(4, kEps));
    expect(await world.whQty(productId, world.warehouseId), closeTo(4, kEps));
    expect(await world.accountNet('5211'), closeTo(4.25, kEps));
    expect(await world.accountNet('1136'), closeTo(-4.25, kEps));
  });

  test('edited quantity snapshots WAC before returning the old stock', () async {
    final sale = await world.sell([world.line(productId, 2, 6.99)]);
    await (world.db.update(world.db.products)
          ..where((row) => row.id.equals(productId)))
        .write(const ProductsCompanion(costPrice: Value(7)));
    await world.container.read(salesRepositoryProvider).updateFullSalesInvoice(
      invoiceId: sale.invoiceId!,
      userId: world.userId,
      warehouseId: world.warehouseId,
      paid: 13.98,
      paymentMethod: 'cash',
      items: [world.line(productId, 3, 6.99)],
    );
    final editedLine = await world.db.customSelect(
      'SELECT cost_price FROM sales_invoice_items WHERE invoice_id=?',
      variables: [Variable<int>(sale.invoiceId!)],
    ).getSingle();
    expect((editedLine.data['cost_price'] as num).toDouble(), closeTo(7, kEps));
  });

  test('credit invoice edit reposts receivable and WAC cost', () async {
    final customerId = await world.addCustomer('credit live edit');
    final sale = await world.sell(
      [world.line(productId, 2, 6.99)],
      customerId: customerId,
      method: 'credit',
      paid: 0,
    );
    await world.container.read(salesRepositoryProvider).updateFullSalesInvoice(
      invoiceId: sale.invoiceId!,
      userId: world.userId,
      customerId: customerId,
      warehouseId: world.warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      items: [world.line(productId, 3, 6.99)],
    );
    expect(await world.partyBalance(customerId), closeTo(20.97, kEps));
    expect(await world.accountNet('1121'), closeTo(20.97, kEps));
    expect(await world.accountNet('5211'), closeTo(12.75, kEps));
    expect(await world.accountNet('1136'), closeTo(-12.75, kEps));
    expect(await world.stock(productId), closeTo(2, kEps));
    expect(await world.whQty(productId, world.warehouseId), closeTo(2, kEps));
  });

  test('discounted inclusive-tax edit keeps gross, tax, GL and inventory aligned', () async {
    await world.db.setSetting('prices_include_tax', 'true');
    final customerId = await world.addCustomer('inclusive tax edit');
    final originalLine = CartItemEntity(
      productId: productId,
      productName: 'LIVE-EDIT',
      productCode: 'LIVE-EDIT',
      quantity: 1,
      unitPrice: 115,
      taxRate: 15,
    );
    final sale = await world.sales.completeSalesTransaction(SaleRequest(
      items: [originalLine],
      customerId: customerId,
      warehouseId: world.warehouseId,
      userId: world.userId,
      paymentMethod: 'credit',
      paidAmount: 0,
      taxEnabled: true,
      taxPercent: 15,
      pricesIncludeTax: true,
      invoiceDiscountAmount: 10,
    ));
    expect(sale.isSuccess, isTrue, reason: sale.errorMessage);

    await world.container.read(salesRepositoryProvider).updateFullSalesInvoice(
      invoiceId: sale.invoiceId!,
      userId: world.userId,
      customerId: customerId,
      warehouseId: world.warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      items: [originalLine.copyWith(quantity: 2)],
    );

    final edited = (await world.db.getSalesInvoiceById(sale.invoiceId!))!;
    expect(edited.total, closeTo(220, kEps));
    expect(edited.subtotal, closeTo(201.3, kEps));
    expect(edited.tax, closeTo(28.7, kEps));
    expect(edited.discount, closeTo(10, kEps));
    expect(await world.accountNet('1121'), closeTo(220, kEps));
    expect(await world.partyBalance(customerId), closeTo(220, kEps));
    expect(await world.accountNet('5211'), closeTo(8.5, kEps));
    expect(await world.accountNet('1136'), closeTo(-8.5, kEps));
    expect(await world.stock(productId), closeTo(3, kEps));
    expect(await world.whQty(productId, world.warehouseId), closeTo(3, kEps));
  });
}
