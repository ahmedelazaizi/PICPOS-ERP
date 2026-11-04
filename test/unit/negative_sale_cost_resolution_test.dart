// بند 11: حل تكلفة البيع بالسالب (تكلفة الصنف ← متوسط الشراء ← سؤال) +
// حسم اتجاه قيد «تسوية تكلفة مخزون سالب» عند وصول الشراء.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sale_cost_resolver.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.setSetting('enable_negative_sales', 'true');
  });

  tearDown(() => db.close());

  var seq = 0;
  Future<int> product({double cost = 0}) => db.insertProduct(
        ProductsCompanion.insert(
          code: 'NSC-${seq++}-${DateTime.now().microsecondsSinceEpoch}',
          name: 'Negative sale product',
          costPrice: Value(cost),
          trackInventory: const Value(true),
        ),
      );

  Future<int> supplier() => db.into(db.parties).insert(
        PartiesCompanion.insert(
            name: 'NSC supplier', isSupplier: const Value(true)),
      );

  Future<int> purchase(int productId, double qty, double unitCost) async {
    final wh = (await db.getDefaultWarehouse())!;
    return db.createPurchaseInvoice(
      supplierId: await supplier(),
      warehouseId: wh.id,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitCost: unitCost,
          total: qty * unitCost,
        ),
      ],
      paid: 0,
      paymentMethod: 'credit',
    );
  }

  Future<int> userId() async {
    final u = await (db.select(db.users)..limit(1)).getSingleOrNull();
    return u?.id ??
        db.into(db.users).insert(UsersCompanion.insert(
            username: 'nsc-user',
            passwordHash: 'x',
            displayName: 'NSC'));
  }

  /// بيع 3 وحدات من رصيد صفر ⇒ سالب. [cost] = تكلفة مؤقتة في السطر.
  Future<int> sellNegative(int productId, {double? cost}) async {
    final wh = (await db.getDefaultWarehouse())!;
    return db.createSalesInvoice(
      invoiceNumber: 'NSC-${seq++}-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: wh.id,
      userId: await userId(),
      subtotal: 30,
      discount: 0,
      tax: 0,
      total: 30,
      paid: 30,
      paymentMethod: 'cash',
      deferAutoPost: true,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 3,
          unitPrice: 10,
          total: 30,
          costPrice: cost == null ? const Value.absent() : Value(cost),
        ),
      ],
    );
  }

  Future<double> snapshot(int invoiceId) async =>
      (await (db.select(db.salesInvoiceItems)
                ..where((i) => i.invoiceId.equals(invoiceId)))
              .getSingle())
          .costPrice;

  group('SaleCostResolver', () {
    test('الافتراضي الموحّد عند غياب المفتاح هو warn', () async {
      expect(kDefaultZeroCostPolicy, 'warn');
      expect(await SaleCostResolver(db).policy(), 'warn');
    });

    test('تكلفة الصنف أولاً ثم متوسط الشراء ثم لا شيء', () async {
      final resolver = SaleCostResolver(db);
      final withCost = await product(cost: 4);
      expect((await resolver.resolve(productId: withCost)).source,
          SaleCostSource.productCost);

      final bought = await product();
      await purchase(bought, 2, 10);
      await purchase(bought, 2, 20);
      // أصفر تكلفة الصنف ليختبر مسار المتوسط وحده.
      await (db.update(db.products)..where((p) => p.id.equals(bought)))
          .write(const ProductsCompanion(costPrice: Value(0)));
      final avg = await resolver.resolve(productId: bought);
      expect(avg.source, SaleCostSource.purchaseAverage);
      expect(avg.cost, closeTo(15, 0.001));

      final never = await product();
      final none = await resolver.resolve(productId: never);
      expect(none.source, SaleCostSource.none);
      expect(none.isKnown, isFalse);
    });
  });

  group('createSalesInvoice — بيع بالسالب', () {
    test('بلا تكلفة معروفة وblock صريحة ⇒ CostRequiredException (سؤال لا رفض أخرس)',
        () async {
      await db.setSetting('zero_cost_policy', 'block');
      final p = await product();
      await expectLater(
          sellNegative(p),
          throwsA(isA<CostRequiredException>()
              .having((e) => e.productId, 'productId', p)));
    });

    test('التكلفة المؤقتة المُدخلة تُحفظ لقطةً وعلى الصنف', () async {
      final p = await product();
      final id = await sellNegative(p, cost: 7);
      expect(await snapshot(id), closeTo(7, 0.001));
      expect((await db.getProductById(p))!.costPrice, closeTo(7, 0.001));
    });

    test('متوسط الشراء يُستخدم تلقائياً دون سؤال ولا يُستعمل سعر البيع',
        () async {
      final p = await product();
      await purchase(p, 2, 10);
      await purchase(p, 2, 20);
      await (db.update(db.products)..where((pr) => pr.id.equals(p)))
          .write(const ProductsCompanion(costPrice: Value(0)));
      final id = await sellNegative(p);
      expect(await snapshot(id), closeTo(15, 0.001)); // لا 10 (سعر البيع)
    });

    test('تكلفة الصنف الموجودة تتقدّم على السؤال', () async {
      final p = await product(cost: 6);
      final id = await sellNegative(p);
      expect(await snapshot(id), closeTo(6, 0.001));
    });

    test('الافتراضي (بلا مفتاح) يحفظ بتكلفة صفر بلا استثناء', () async {
      final p = await product();
      final id = await sellNegative(p);
      expect(await snapshot(id), 0);
    });

    for (final policy in ['warn', 'allow']) {
      test('$policy يحفظ بتكلفة صفر بلا استثناء', () async {
        await db.setSetting('zero_cost_policy', policy);
        final p = await product();
        final id = await sellNegative(p);
        expect(await snapshot(id), 0);
      });
    }
  });

  group('قيد تسوية تكلفة مخزون سالب — الاتجاه', () {
    /// يبيع بالسالب بتكلفة [saleCost] ثم يشتري بـ[buyCost] ويعيد
    /// (مدين COGS، دائن COGS، مدين مخزون، دائن مخزون) لقيد التسوية.
    Future<List<double>> adjustmentFor(double saleCost, double buyCost) async {
      final wh = (await db.getDefaultWarehouse())!;
      final p = await product(cost: saleCost);
      await db.adjustStock(
        productId: p,
        warehouseId: wh.id,
        quantity: -2,
        type: 'sale',
        referenceType: 'sale',
        referenceId: 9000,
        postAdjustmentJournal: false,
      );
      final invoiceId = await purchase(p, 3, buyCost);
      final entry = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('negative_stock_cost_adjustment') &
                e.referenceId.equals(invoiceId)))
          .getSingle();
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(entry.id)))
          .get();
      final cogs = (await db.getAccountByPurpose('cogs'))!.id;
      final inv = (await db.getAccountByPurpose('inventory'))!.id;
      double sum(int acc, double Function(JournalEntryLine) f) => lines
          .where((l) => l.accountId == acc)
          .fold<double>(0, (s, l) => s + f(l));
      return [
        sum(cogs, (l) => l.debit),
        sum(cogs, (l) => l.credit),
        sum(inv, (l) => l.debit),
        sum(inv, (l) => l.credit),
      ];
    }

    test('تكلفة الشراء أعلى من تكلفة البيع ⇒ مدين COGS / دائن المخزون', () async {
      // 2 وحدة مكشوفة × (12 − 10) = 4 تكلفة بضاعة إضافية.
      final r = await adjustmentFor(10, 12);
      expect(r[0], closeTo(4, 0.001), reason: 'Dr COGS');
      expect(r[1], 0);
      expect(r[2], 0);
      expect(r[3], closeTo(4, 0.001), reason: 'Cr Inventory');
    });

    test('تكلفة الشراء أقل ⇒ دائن COGS / مدين المخزون', () async {
      final r = await adjustmentFor(10, 8);
      expect(r[0], 0);
      expect(r[1], closeTo(4, 0.001), reason: 'Cr COGS');
      expect(r[2], closeTo(4, 0.001), reason: 'Dr Inventory');
      expect(r[3], 0);
    });
  });
}
