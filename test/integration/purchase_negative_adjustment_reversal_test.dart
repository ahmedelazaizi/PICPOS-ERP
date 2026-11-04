// R2: إلغاء فاتورة شراء غطّت مخزوناً سالباً يجب أن يعكس أيضاً قيد
// «تسوية تكلفة مخزون سالب» (negative_stock_cost_adjustment) المرتبط بها.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.setSetting('enable_negative_sales', 'true');
  });

  tearDown(() => db.close());

  Future<int> purchaseCoveringNegative() async {
    final wh = (await db.getDefaultWarehouse())!;
    final p = await db.insertProduct(ProductsCompanion.insert(
      code: 'R2-${DateTime.now().microsecondsSinceEpoch}',
      name: 'R2 product',
      costPrice: const Value(10),
      trackInventory: const Value(true),
    ));
    // بيع بالسالب (وحدتان) بتكلفة 10 دون قيد مخزون.
    await db.adjustStock(
      productId: p,
      warehouseId: wh.id,
      quantity: -2,
      type: 'sale',
      referenceType: 'sale',
      referenceId: 9000,
      postAdjustmentJournal: false,
    );
    final supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'R2 supplier', isSupplier: const Value(true)));
    // شراء 3 بتكلفة 12 ⇒ تسوية 2 × (12 − 10) = 4.
    return db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: wh.id,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: p,
          quantity: 3,
          unitCost: 12,
          total: 36,
        ),
      ],
      paid: 0,
      paymentMethod: 'credit',
    );
  }

  Future<double> net(String purpose) async {
    final acc = (await db.getAccountByPurpose(purpose))!.id;
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.accountId.equals(acc)))
        .get();
    return lines.fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  Future<List<dynamic>> adjustmentEntries(int id) =>
      (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('negative_stock_cost_adjustment') &
                e.referenceId.equals(id)))
          .get();

  test('إلغاء الشراء يصفّر أثر تسوية السالب على COGS والمخزون', () async {
    final id = await purchaseCoveringNegative();
    expect(await adjustmentEntries(id), hasLength(1));
    expect(await net('cogs'), closeTo(4, 0.001));

    await db.voidPurchaseInvoice(id, reason: 'R2');

    expect(await net('cogs'), closeTo(0, 0.001), reason: 'COGS');
    expect(await net('inventory'), closeTo(0, 0.001), reason: 'Inventory');
  });

  test('إعادة استدعاء الإلغاء لا تعكس التسوية مرتين', () async {
    final id = await purchaseCoveringNegative();
    await db.voidPurchaseInvoice(id, reason: 'R2');
    // الفاتورة الملغاة لا تُرى ثانيةً ⇒ الاستدعاء الثاني no-op.
    await db.voidPurchaseInvoice(id, reason: 'R2 again');

    expect(await net('cogs'), closeTo(0, 0.001));
    expect(await net('inventory'), closeTo(0, 0.001));
    final reversals = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('negative_stock_cost_adjustment_void') &
              e.referenceId.equals(id)))
        .get();
    expect(reversals, hasLength(1));
  });
}
