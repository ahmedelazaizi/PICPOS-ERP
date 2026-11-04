// R2: تعديل فاتورة شراء غطّت مخزوناً سالباً يجب أن يعيد احتساب قيد
// «تسوية تكلفة مخزون سالب» (negative_stock_cost_adjustment) لا أن يتركه بالمبلغ القديم.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int whId;
  late int productId;
  late int supplierId;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.setSetting('enable_negative_sales', 'true');
    whId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'R2E-${DateTime.now().microsecondsSinceEpoch}',
      name: 'R2 edit product',
      costPrice: const Value(10),
      trackInventory: const Value(true),
    ));
    // بيع بالسالب (وحدتان) بتكلفة 10 دون قيد مخزون.
    await db.adjustStock(
      productId: productId,
      warehouseId: whId,
      quantity: -2,
      type: 'sale',
      referenceType: 'sale',
      referenceId: 9000,
      postAdjustmentJournal: false,
    );
    supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'R2 supplier', isSupplier: const Value(true)));
    userId = (await db
            .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
            .getSingle())
        .read<int>('id');
  });

  tearDown(() => db.close());

  List<PurchaseInvoiceItemsCompanion> lines(double qty, double cost) => [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitCost: cost,
          total: qty * cost,
        ),
      ];

  Future<int> create(double qty, double cost) => db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: whId,
        items: lines(qty, cost),
        paid: 0,
        paymentMethod: 'credit',
      );

  Future<void> edit(int id, double qty, double cost) =>
      db.updatePurchaseInvoice(
        invoiceId: id,
        supplierId: supplierId,
        warehouseId: whId,
        items: lines(qty, cost),
        paid: 0,
        paymentMethod: 'credit',
        userId: userId,
      );

  Future<double> net(String purpose) async {
    final acc = (await db.getAccountByPurpose(purpose))!.id;
    final ls = await (db.select(db.journalEntryLines)
          ..where((l) => l.accountId.equals(acc)))
        .get();
    return ls.fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  Future<int> count(String type, int id) async => (await (db.select(
              db.journalEntries)
            ..where(
                (e) => e.referenceType.equals(type) & e.referenceId.equals(id)))
          .get())
      .length;

  test('تعديل التكلفة والكمية يعيد احتساب التسوية ولا يكرر العكس', () async {
    final id = await create(3, 12); // تسوية 2 × (12 − 10) = 4
    expect(await net('cogs'), closeTo(4, 0.001));
    expect(await net('inventory'), closeTo(36 - 4, 0.001));

    await edit(id, 4, 15); // تسوية 2 × (15 − 10) = 10
    expect(await net('cogs'), closeTo(10, 0.001), reason: 'COGS');
    expect(await net('inventory'), closeTo(60 - 10, 0.001), reason: 'Inventory');
    expect(await count('negative_stock_cost_adjustment', id), 1);

    await edit(id, 3, 11); // تسوية 2 × (11 − 10) = 2
    expect(await net('cogs'), closeTo(2, 0.001));
    expect(await net('inventory'), closeTo(33 - 2, 0.001));
    expect(await count('negative_stock_cost_adjustment', id), 1);

    // إعادة التعديل بنفس القيم لا تغيّر الصافي (لا عكس مكرر).
    await edit(id, 3, 11);
    expect(await net('cogs'), closeTo(2, 0.001));
    expect(await net('inventory'), closeTo(33 - 2, 0.001));
    expect(await count('negative_stock_cost_adjustment', id), 1);

    // الإلغاء بعد التعديل يصفّر الأثر كاملاً (يعكس التسوية الحالية مرة واحدة).
    await db.voidPurchaseInvoice(id, reason: 'R2');
    expect(await net('cogs'), closeTo(0, 0.001));
    expect(await net('inventory'), closeTo(0, 0.001));
    expect(await count('negative_stock_cost_adjustment_void', id), 1);
  });

  test('تعديل التكلفة إلى تكلفة البيع يلغي التسوية', () async {
    final id = await create(3, 12);
    await edit(id, 3, 10); // لا فرق ⇒ لا تسوية
    expect(await net('cogs'), closeTo(0, 0.001));
    expect(await net('inventory'), closeTo(30, 0.001));
    expect(await count('negative_stock_cost_adjustment', id), 0);
  });
}
