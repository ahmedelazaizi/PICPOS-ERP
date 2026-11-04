// بند ٤ — المرتجع السريع بلا فاتورة: المسارُ الحقيقيّ كاملاً على قاعدة اختبار.
//
// سلّة (CartController) ← خطّة التسوية ← CheckoutController ← المنسّق ← DAO.
// يقيس: المخزون (+qty)، التكلفة (WAC الحاليّ)، القيد (sales_return متوازن)،
// الصندوق/الوردية (نقد خارج، ويتقاصّ مع البيع في السلّة المختلطة)، الضريبة،
// السقف (من القاعدة)، وغياب الوردية (لا يُحفَظ شيء).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/errors/app_exceptions.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/providers/quick_sale_policy_providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/models/no_invoice_return_policy.dart';
import 'package:picpos_erp/domain/usecases/sales/cart_settlement_plan.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/presentation/pos/providers/checkout_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int userId;
  late int warehouseId;
  late int idA; // سعر ١٠٠ · تكلفة ٤٠
  late int idB; // سعر ٥٠ · تكلفة ٢٠

  Future<int> mkProduct(String code, double price, double cost,
      {double stock = 100}) async {
    final id = await db.insertProduct(ProductsCompanion.insert(
      code: code,
      name: 'صنف $code',
      salePrice: Value(price),
      costPrice: Value(cost),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: id,
      warehouseId: warehouseId,
      quantity: stock,
      type: 'purchase',
      unitCost: cost,
      notes: 'رصيد',
    );
    return id;
  }

  Future<int> seedPriorSale({
    required int productId,
    required double quantity,
    required double price,
    double taxPercent = 0,
  }) async {
    final subtotal = quantity * price;
    final tax = subtotal * taxPercent / 100;
    final total = subtotal + tax;
    final cashSafe = (await db.getDefaultSafeByType('cash'))!;
    return db.createSalesInvoice(
      warehouseId: warehouseId,
      userId: userId,
      subtotal: subtotal,
      discount: 0,
      tax: tax,
      total: total,
      paid: total,
      paymentMethod: 'cash',
      cashSafeId: cashSafe.id,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: quantity,
          unitPrice: price,
          total: subtotal,
          taxRate: Value(taxPercent),
          taxAmount: Value(tax),
          costPrice: const Value(40),
        ),
      ],
    );
  }

  ProductEntity entity(int id, String code, double price, double cost) =>
      ProductEntity(
        id: id,
        code: code,
        name: 'صنف $code',
        salePrice: price,
        costPrice: cost,
        currentStock: 100,
        minStock: 0,
        trackInventory: true,
      );

  late ProductEntity pa;
  late ProductEntity pb;

  Future<void> boot({bool shift = true}) async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = (await db.getDefaultWarehouse())!.id;
    // `CheckoutController` يقرأ `authState.originalUser?.id ?? 1` ⇒ المستخدمُ ١.
    userId = (await db.select(db.users).get()).first.id;
    expect(userId, 1, reason: 'الاختبارُ يفترض أنّ المستخدمَ الافتراضيّ ١');
    idA = await mkProduct('A', 100, 40);
    idB = await mkProduct('B', 50, 20);
    pa = entity(idA, 'A', 100, 40);
    pb = entity(idB, 'B', 50, 20);
    if (shift) await db.openShift(userId, 0);
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) => db),
      branchScopeProvider
          .overrideWith((ref) async => const BranchScope.fullAccess()),
      posDefaultTaxRateProvider.overrideWith((ref) async => 0.16),
    ]);
  }

  tearDown(() async {
    SyncInterceptor.instance = null;
    container.dispose();
    await db.close();
  });

  CartController cartCtl() => container.read(cartControllerProvider.notifier);
  CartState cartState() => container.read(cartControllerProvider);
  CheckoutController checkout() =>
      container.read(checkoutControllerProvider.notifier);

  CartSettlementPlan planNow() {
    final s = cartState();
    return planCartSettlement(
      items: s.items,
      invoiceDiscountPercent: s.discountPercent,
      invoiceDiscountAmount: s.invoiceDiscountAmount,
      taxPercent: s.taxEnabled ? s.taxRate * 100 : 0,
      taxEnabled: s.taxEnabled,
      deliveryFee: s.deliveryFee,
    );
  }

  Future<double> stockOf(int id) async =>
      (await db.getProductById(id))!.currentStock;

  Future<List<SalesInvoiceData>> invoices() =>
      (db.select(db.salesInvoices)..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  Future<({double debit, double credit, bool hasLine})> journalOf(
      int invoiceId, String refType, double lineAmount) async {
    final entries = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceId.equals(invoiceId) &
              e.referenceType.equals(refType)))
        .get();
    var d = 0.0, c = 0.0;
    var has = false;
    for (final e in entries) {
      for (final l in await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(e.id)))
          .get()) {
        d += l.debit;
        c += l.credit;
        if ((l.debit - lineAmount).abs() < 0.005 ||
            (l.credit - lineAmount).abs() < 0.005) {
          has = true;
        }
      }
    }
    expect(entries, isNotEmpty, reason: 'قيد $refType غائب للمستند $invoiceId');
    return (debit: d, credit: c, hasLine: has);
  }

  /// مجموعُ أرصدة الخزائن النقدية — الأثرُ الماديُّ في الدرج.
  Future<double> cashBalance() async => (await (db.select(db.safes)
            ..where((s) => s.safeType.equals('cash')))
          .get())
      .fold<double>(0, (s, e) => s + e.balance);

  Future<ShiftClosingAggregates> aggregates() => db.getShiftClosingAggregates(
        userId: userId,
        includeAllUsers: false,
        shiftStart: DateTime.now().subtract(const Duration(hours: 1)),
      );

  group('مرتجع خالص بلا فاتورة', () {
    setUp(() => boot());

    test('مخزون +qty · تكلفة WAC · قيد sales_return متوازن · نقد خارج', () async {
      // البيع السابق يجعل هذا اختباراً لمرتجع مشروع، لا لمخزون شراء غير مباع.
      await seedPriorSale(productId: idA, quantity: 2, price: 100);
      final cashBefore = await cashBalance();
      cartCtl().addReturnItem(pa, quantity: 2);
      final plan = planNow();
      expect(plan.kind, CartSettlementKind.returnOnly);
      expect(plan.returnTotal, 200);

      final ok = await checkout().processNoInvoiceReturnSettlement(plan: plan);
      expect(ok, isTrue, reason: container.read(checkoutControllerProvider).error);

      final all = await invoices();
      expect(all, hasLength(2), reason: 'بيع التاريخ والمرتجع');
      final inv = all.singleWhere((invoice) => invoice.saleType == 'return');
      expect(inv.saleType, 'return');
      expect(inv.invoiceNumber.startsWith(AppDatabase.defaultSalesReturnPrefix), isTrue);
      expect(inv.total, 200);
      expect(inv.paid, 200);
      expect(inv.paymentMethod, 'cash');

      // المخزون يزيد، ومتوسّط التكلفة لا يتميّع.
      expect(await stockOf(idA), 100); // بيع ٢ ثم مرتجع ٢
      expect((await db.getProductById(idA))!.costPrice, closeTo(40, 1e-9));

      // التكلفةُ تُختم على السطر من WAC الحاليّ.
      final item = (await (db.select(db.salesInvoiceItems)
                ..where((i) => i.invoiceId.equals(inv.id)))
              .get())
          .single;
      expect(item.costPrice, 40);
      expect(item.quantity, 2);

      // القيدُ: sales_return متوازن وفيه تكلفةُ البضاعة المرتجعة (٢×٤٠ = ٨٠).
      final je = await journalOf(inv.id, 'sales_return', 80);
      expect(je.debit, closeTo(je.credit, 1e-9));
      expect(je.hasLine, isTrue, reason: 'سطرُ عكس التكلفة ٨٠ غائب');

      // الصندوق: حركةٌ نقديةٌ واحدةٌ خارجةٌ في الوردية.
      final tx = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('sales_invoice') &
                t.referenceId.equals(inv.id)))
          .get();
      expect(tx, hasLength(1));
      expect(tx.single.transactionType, 'payment', reason: 'نقدٌ خارج');
      expect(tx.single.category, 'return');
      expect(tx.single.amount, 200);
      expect(await cashBalance(), cashBefore - 200,
          reason: 'رصيدُ الخزنة النقدية ينقص بقيمة الرد');
      final agg = await aggregates();
      expect(agg.returnsCash, 200);
      expect(agg.salesCash, 200); // بيع التاريخ الممهد للمرتجع

      // السلّة فُرِّغت.
      expect(cartState().items, isEmpty);
    });

    test('سعرٌ يدويٌّ يُحفَظ كما أُدخل (وتكلفةُ WAC لا تتأثّر)', () async {
      // نبيع الكمية أولاً كي يختبر السيناريو السعر لا رفض الصافي.
      await seedPriorSale(productId: idA, quantity: 1, price: 70);
      cartCtl().addReturnItem(pa, quantity: 1, price: 70);
      final ok =
          await checkout().processNoInvoiceReturnSettlement(plan: planNow());
      expect(ok, isTrue);
      final inv = (await invoices())
          .singleWhere((invoice) => invoice.saleType == 'return');
      expect(inv.total, 70);
      final item = (await (db.select(db.salesInvoiceItems)
                ..where((i) => i.invoiceId.equals(inv.id)))
              .get())
          .single;
      expect(item.unitPrice, 70);
      expect(item.costPrice, 40);
    });

    test('الضريبة ١٤٪: الإجمالي ١١٤ والضريبة ١٤ والقيد متوازن', () async {
      // بيع خاضع للضريبة يثبت استحقاق الوحدة قبل اختبار قيد المرتجع.
      await seedPriorSale(productId: idA, quantity: 1, price: 100, taxPercent: 14);
      cartCtl()
        ..toggleTax(true)
        ..setTaxRate(0.14)
        ..addReturnItem(pa, quantity: 1);
      final plan = planNow();
      expect(plan.returnTotal, 114);

      final ok = await checkout().processNoInvoiceReturnSettlement(plan: plan);
      expect(ok, isTrue, reason: container.read(checkoutControllerProvider).error);
      final inv = (await invoices())
          .singleWhere((invoice) => invoice.saleType == 'return');
      expect(inv.total, 114);
      expect(inv.tax, closeTo(14, 1e-9));
      final je = await journalOf(inv.id, 'sales_return', 14);
      expect(je.debit, closeTo(je.credit, 1e-9));
      expect(je.hasLine, isTrue, reason: 'سطرُ عكس الضريبة ١٤ غائب');
    });
  });

  group('سلّة مختلطة', () {
    setUp(() => boot());

    test('صافٍ موجب: البيع الحالي يتقاصّ مع المرتجع المشروع (١٥٠ − ١٠٠ = ٥٠)', () async {
      // البيع السابق يثبت صافي وحدة المرتجع؛ نتحقق من أثر السلة الحالية وحده.
      await seedPriorSale(productId: idA, quantity: 1, price: 100);
      final aggBefore = await aggregates();
      cartCtl()
        ..addItem(pb, quantity: 3) // ١٥٠
        ..addReturnItem(pa, quantity: 1); // ١٠٠
      final plan = planNow();
      expect(plan.kind, CartSettlementKind.mixed);
      expect(plan.net, 50);
      expect(cartState().total, 50, reason: 'الإجماليُّ المعروض = الصافي');

      final ok = await checkout().processNoInvoiceReturnSettlement(plan: plan);
      expect(ok, isTrue, reason: container.read(checkoutControllerProvider).error);

      final all = await invoices();
      expect(all, hasLength(3), reason: 'بيع التاريخ وبيع السلة والمرتجع');
      final saleInv = all.firstWhere((i) => i.saleType != 'return' && i.total == 150);
      final retInv = all.firstWhere((i) => i.saleType == 'return');
      expect(saleInv.total, 150);
      expect(retInv.total, 100);
      expect(retInv.invoiceNumber.startsWith(AppDatabase.defaultSalesReturnPrefix), isTrue);
      expect(saleInv.invoiceNumber.startsWith(AppDatabase.defaultSalesReturnPrefix), isFalse,
          reason: 'البيعُ لا يُقلَب مرتجعاً');

      expect(await stockOf(idB), 97); // −٣
      expect(await stockOf(idA), 100); // بيع التاريخ ١ ثم ردّها ١

      final agg = await aggregates();
      expect(
        (agg.salesCash - aggBefore.salesCash) -
            (agg.returnsCash - aggBefore.returnsCash),
        50,
        reason: 'صافي النقد لسلة البيع/المرتجع الحالية',
      );
      expect(container.read(checkoutControllerProvider).lastInvoiceId,
          saleInv.id,
          reason: 'الطباعةُ تتبع فاتورةَ البيع');
      expect(cartState().items, isEmpty);
    });

    test('صافٍ سالب: يُردّ الفرق نقداً (بيع ٥٠ − مرتجع ١٠٠ = −٥٠)', () async {
      // نهيئ وحدة مباعة مسبقاً، ونقيس صافي أثر السلة الحالية فقط.
      await seedPriorSale(productId: idA, quantity: 1, price: 100);
      final aggBefore = await aggregates();
      cartCtl()
        ..addItem(pb, quantity: 1)
        ..addReturnItem(pa, quantity: 1);
      final plan = planNow();
      expect(plan.net, -50);
      expect(plan.cashToRefund, 50);
      expect(cartState().signedTotal, -50);

      final ok = await checkout().processNoInvoiceReturnSettlement(plan: plan);
      expect(ok, isTrue);
      final agg = await aggregates();
      expect(
        (agg.returnsCash - aggBefore.returnsCash) -
            (agg.salesCash - aggBefore.salesCash),
        50,
      );
    });

    test('فشلُ البيع (مخزون) لا يترك أثراً: لا مرتجعَ ولا فاتورة والسلّة كما هي',
        () async {
      await db.saveSettings({
        'enable_negative_sales': 'false',
        'pos_negative_stock_policy': '0',
      });
      cartCtl()
        ..addItem(pb.copyWith(currentStock: 1000), quantity: 500) // يفوق الرصيد
        ..addReturnItem(pa, quantity: 1);
      final ok =
          await checkout().processNoInvoiceReturnSettlement(plan: planNow());
      expect(ok, isFalse);
      expect(await invoices(), isEmpty, reason: 'لا مستند محفوظ');
      expect(await stockOf(idA), 100, reason: 'المرتجعُ لم يُحفَظ');
      expect(cartState().items, hasLength(2), reason: 'السلّة لم تُمسّ');
      expect(container.read(checkoutControllerProvider).error, isNotNull);
    });
  });

  group('السقف يُقرأ من القاعدة', () {
    setUp(() => boot());

    test('غيابُ المفتاح ⇒ الافتراضيّ ٥٠٠', () async {
      final policy = await container.read(quickSalePolicyProvider.future);
      expect(noInvoiceReturnCap(policy), 500);
    });

    test('المحفوظ يسري: ٢٠٠ ⇒ مرتجعٌ بـ٢٥٠ يحتاج مسؤولاً و١٥٠ لا يحتاج', () async {
      await db.saveSettings(writeNoInvoiceReturnCap(200));
      final policy = await container.read(quickSalePolicyProvider.future);
      final cap = noInvoiceReturnCap(policy);
      expect(cap, 200);
      expect(judgeNoInvoiceReturn(returnValue: 250, cap: cap),
          NoInvoiceReturnVerdict.needsManager);
      expect(judgeNoInvoiceReturn(returnValue: 150, cap: cap),
          NoInvoiceReturnVerdict.withinCap);
    });
  });

  group('بلا وردية', () {
    setUp(() => boot(shift: false));

    test('يُرمى ShiftRequiredException ولا يُحفَظ شيء', () async {
      cartCtl().addReturnItem(pa, quantity: 1);
      await expectLater(
        checkout().processNoInvoiceReturnSettlement(plan: planNow()),
        throwsA(isA<ShiftRequiredException>()),
      );
      expect(await invoices(), isEmpty);
      expect(await stockOf(idA), 100);
      expect(cartState().items, hasLength(1));
      expect(container.read(checkoutControllerProvider).isProcessing, isFalse,
          reason: 'لا يبقى المعالِج معلَّقاً بعد الاستثناء');
    });
  });
}
