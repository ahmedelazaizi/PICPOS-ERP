// تدقيق المرتجعات والاستبدال والإلغاء والتعديل والتحصيل (2026-10-31).
// الاختبارات تؤكد **السلوك المحاسبي الصحيح**؛ فما يفشل منها استنساخ عيب.
//   flutter test test/audit_repro/sales_purchases --run-skipped
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/exchange_repository_impl.dart';
import 'package:picpos_erp/data/repositories/returns_repository_impl.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';

import '../../scenarios/scenario_world.dart';

const kSkip = 'audit repro — pending owner approval';

void _log(String m) {
  // ignore: avoid_print
  print('[AUDIT-RET] $m');
}

Future<ProductEntity> _entity(ScenarioWorld w, int id) async {
  final p = (await w.db.getProductById(id))!;
  return ProductEntity(
      id: p.id,
      name: p.name,
      code: p.code,
      salePrice: p.salePrice,
      costPrice: p.costPrice,
      currentStock: p.currentStock,
      minStock: p.minStock,
      trackInventory: p.trackInventory);
}

/// مرتجع من فاتورة بكمية [qty] للسطر الأول الذي يحمل [productId]؛ يعيد النجاح
/// أو نص الاستثناء.
Future<Object> _ret(ScenarioWorld w, int invoiceId, int productId, double qty,
    {bool full = false}) async {
  try {
    final items = await w.db.getSalesInvoiceItems(invoiceId);
    final it = items.firstWhere((i) => i.productId == productId);
    return await w.container.read(returnsRepositoryProvider).processSalesReturn(
          invoice: (await w.db.getSalesInvoiceById(invoiceId))!,
          returnQuantities: {it.id: qty},
          productCache: {productId: await _entity(w, productId)},
          reason: 'تدقيق',
          userId: w.userId,
          userName: 'مدقق',
          isFullReturn: full,
        );
  } catch (e) {
    return 'EXC: $e';
  }
}

Future<int> _noInvoiceReturn(ScenarioWorld w, int productId, double qty, double price) {
  final total = qty * price;
  return w.sales.createSalesInvoice(
    customerId: null,
    warehouseId: w.warehouseId,
    userId: w.userId,
    subtotal: total,
    discount: 0,
    tax: 0,
    total: total,
    paid: total,
    paymentMethod: 'cash',
    saleType: 'return',
    cashSafeId: w.cashSafeId,
    items: [
      CartItemEntity(
          productId: productId,
          productName: 'p$productId',
          productCode: 'c$productId',
          quantity: qty,
          unitPrice: price),
    ],
  );
}

/// كل قيود المرتجعات (reference_type يبدأ بـ sales_return) مجمّعة بالكود.
Future<Map<String, double>> _netByRefPrefix(ScenarioWorld w, String refPrefix) async {
  final rows = await w.db.customSelect(
      'SELECT a.code c, SUM(l.debit - l.credit) n FROM journal_entry_lines l '
      'JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id '
      'WHERE e.is_deleted = 0 AND e.reference_type LIKE ? GROUP BY a.code',
      variables: [Variable<String>('$refPrefix%')]).get();
  return {for (final r in rows) r.data['c'] as String: (r.data['n'] as num).toDouble()};
}

Future<String> _refs(ScenarioWorld w) async {
  final r = await w.db
      .customSelect('SELECT id, reference_type rt, reference_id rid, is_deleted d FROM journal_entries ORDER BY id')
      .get();
  return r.map((e) => '${e.data['id']}:${e.data['rt']}/${e.data['rid']}${e.data['d'] == 1 ? '(del)' : ''}').join(' ');
}

Future<double> _wac(ScenarioWorld w, int p) async => (await w.db.getProductById(p))!.costPrice;

Future<double> _invValue(ScenarioWorld w, int p) async {
  final pr = (await w.db.getProductById(p))!;
  return pr.currentStock * pr.costPrice;
}

void main() {
  late ScenarioWorld w;
  late int q; // سعر 100 / تكلفة 60
  late int sup;

  PurchasesRepository repo() => w.container.read(purchasesRepositoryProvider);
  Future<int> buy(int product, double qty, double cost) =>
      repo().createInvoice(CreatePurchaseInvoiceParams(
        supplierId: sup,
        warehouseId: w.warehouseId,
        paid: 0,
        paymentMethod: 'credit',
        userId: w.userId,
        items: [
          PurchaseItemParams(
              productId: product,
              quantity: qty,
              unitCost: cost,
              salePrice: 100,
              taxRate: 0,
              taxAmount: 0)
        ],
      ));

  setUp(() async {
    StockShortagePolicyService.resetCacheForTest();
    w = await ScenarioWorld.create();
    sup = await w.addSupplier('مورد');
    q = await w.addProduct('Q', price: 100, cost: 60);
    await buy(q, 50, 60); // رصيد 50 بتكلفة 60 عبر شراء (يظهر في 1136)
  });
  tearDown(() async {
    StockShortagePolicyService.resetCacheForTest();
    await w.dispose();
  });

  group('RET مرتجع من فاتورة', () {
    test('RET-01 مرتجع كامل لبيع نقدي 2×100: 4211 مدين 200 / نقدية دائن 200 · 1136/5211 = 120',
        skip: kSkip, () async {
      final r = await w.sell([w.line(q, 2, 100)]);
      final ok = await _ret(w, r.invoiceId!, q, 2, full: true);
      final je = await _netByRefPrefix(w, 'sales_return');
      _log('RET-01 ok=$ok je=$je stock=${await w.stock(q)} safe=${await w.safeBalance()} refs=${await _refs(w)}');
      expect(ok, isTrue);
      expect(je['4211'], closeTo(200, kEps));
      expect(je['1136'], closeTo(120, kEps));
      expect(je['5211'], closeTo(-120, kEps));
      expect(await w.stock(q), closeTo(50, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('RET-02 مرتجعات متعددة تتجاوز المباع: بيع 5 ثم مرتجع 5 ثم مرتجع 5 آخر ⇒ يجب رفض الثاني',
        skip: kSkip, () async {
      final r = await w.sell([w.line(q, 5, 100)]);
      final a = await _ret(w, r.invoiceId!, q, 5);
      final already = await w.db.getAlreadyReturnedQty(r.invoiceId!, q);
      final b = await _ret(w, r.invoiceId!, q, 5);
      final je = await _netByRefPrefix(w, 'sales_return');
      _log('RET-02 first=$a alreadyReturned(after first)=$already second=$b stock=${await w.stock(q)} '
          'safe=${await w.safeBalance()} je=$je');
      expect(a, isTrue);
      expect(already, closeTo(5, kEps), reason: 'getAlreadyReturnedQty لا يرى المرتجع الأول');
      expect(b, isNot(true), reason: 'مرتجع ثانٍ يُعيد 5 وحدات لم تُبَع ويُخرج 500 نقداً');
      expect(await w.stock(q), closeTo(50, kEps));
    });

    test('RET-03 مرتجع جزئي متعدد 2 ثم 2 ثم 2 من 5 ⇒ الثالث يُرفض', skip: kSkip, () async {
      final r = await w.sell([w.line(q, 5, 100)]);
      final res = [
        await _ret(w, r.invoiceId!, q, 2),
        await _ret(w, r.invoiceId!, q, 2),
        await _ret(w, r.invoiceId!, q, 2),
      ];
      final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      _log('RET-03 results=$res status=${inv.status} stock=${await w.stock(q)} safe=${await w.safeBalance()}');
      expect(res[2], isNot(true));
    });

    test('RET-04 المرتجع يعكس تكلفة البيع الأصلية (60) لا WAC الحالية بعد شراء بـ 90', skip: kSkip,
        () async {
      final r = await w.sell([w.line(q, 2, 100)]);
      await buy(q, 48, 90); // 48 @60 + 48 @90 ⇒ WAC 75
      final wacBefore = await _wac(w, q);
      final ok = await _ret(w, r.invoiceId!, q, 2);
      final je = await _netByRefPrefix(w, 'sales_return');
      _log('RET-04 ok=$ok wacBefore=$wacBefore wacAfter=${await _wac(w, q)} je=$je '
          'stock=${await w.stock(q)} gl1136=${await w.accountNet('1136')} invValue=${await _invValue(w, q)}');
      expect(je['5211'], closeTo(-120, kEps));
      expect(await w.accountNet('1136'), closeTo(await _invValue(w, q), 0.05),
          reason: 'رصيد 1136 في الأستاذ = الكمية × WAC');
    });

    test('RET-05 مرتجع من بيع بخصم سطر 10%: المردود 90 للوحدة لا 100', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(SaleRequest(
          items: [
            CartItemEntity(
                productId: q, productName: 'q', productCode: 'q', quantity: 2, unitPrice: 100,
                discountPercent: 10)
          ],
          warehouseId: w.warehouseId,
          userId: w.userId,
          paymentMethod: 'cash',
          paidAmount: 180,
          taxEnabled: false,
          cashSafeId: w.cashSafeId));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final ok = await _ret(w, r.invoiceId!, q, 1);
      final je = await _netByRefPrefix(w, 'sales_return');
      _log('RET-05 ok=$ok je=$je safe=${await w.safeBalance()}');
      expect(await w.safeBalance(), closeTo(90, kEps));
      expect(je['4211'], closeTo(90, kEps));
    });

    test('RET-06 مرتجع فاتورة بخصم فاتورة 10% وضريبة 14% (2×100): المردود 102.6 ', skip: kSkip,
        () async {
      final r = await w.sales.completeSalesTransaction(SaleRequest(
          items: [
            CartItemEntity(
                productId: q, productName: 'q', productCode: 'q', quantity: 2, unitPrice: 100,
                taxRate: 14)
          ],
          warehouseId: w.warehouseId,
          userId: w.userId,
          paymentMethod: 'cash',
          paidAmount: 205.2,
          discountPercent: 10,
          taxEnabled: true,
          taxPercent: 14,
          cashSafeId: w.cashSafeId));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final ok = await _ret(w, r.invoiceId!, q, 1);
      final je = await _netByRefPrefix(w, 'sales_return');
      _log('RET-06 ok=$ok je=$je safe=${await w.safeBalance()} sale=${await w.linesOf('sales_invoice', r.invoiceId!)}');
      expect(await w.safeBalance(), closeTo(102.6, kEps));
      expect(je['2121'], closeTo(12.6, kEps));
      expect(je['4211'], closeTo(90, kEps));
    });

    test('RET-07 مرتجع من بيع آجل: يخفّض الذمة لا الصندوق', skip: kSkip, () async {
      final c = await w.addCustomer('ع');
      final r = await w.sell([w.line(q, 2, 100)], customerId: c, method: 'credit', paid: 0);
      final ok = await _ret(w, r.invoiceId!, q, 1);
      final je = await _netByRefPrefix(w, 'sales_return');
      _log('RET-07 ok=$ok party=${await w.partyBalance(c)} safe=${await w.safeBalance()} je=$je');
      expect(await w.partyBalance(c), closeTo(100, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
      expect(await w.accountNet('1121'), closeTo(100, kEps));
    });

    test('RET-08 سباق مرتجعين متزامنين (2+2 من 3) ⇒ ينجح واحد', skip: kSkip, () async {
      final r = await w.sell([w.line(q, 3, 100)]);
      final res = await Future.wait([
        _ret(w, r.invoiceId!, q, 2),
        _ret(w, r.invoiceId!, q, 2),
      ]);
      _log('RET-08 results=$res stock=${await w.stock(q)} safe=${await w.safeBalance()}');
      expect(res.where((x) => x == true).length, 1);
    });
  });

  group('NOINV مرتجع بلا فاتورة', () {
    test('NOINV-01 بيانات المالك: بيع 5، مرتجع بلا فاتورة 7، بلا مشتريات وتكلفة 4', skip: kSkip,
        () async {
      final p = await w.addProduct('P699', price: 6.99, cost: 4, stock: 0);
      await w.db.setSetting('enable_negative_sales', 'true');
      final s = await w.sell([w.line(p, 5, 6.99)]);
      final stockBefore = await w.stock(p);
      final journalBefore = (await w.db.select(w.db.journalEntries).get()).length;
      // القرار المعتمد: رفض التجاوز قبل إنشاء المرتجع أو أي أثر تابع له.
      await expectLater(
        _noInvoiceReturn(w, p, 7, 6.99),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('المتاح: 5'),
        )),
      );
      _log('NOINV-01 sale=${await w.linesOf('sales_invoice', s.invoiceId!)} '
          'stock=${await w.stock(p)} safe=${await w.safeBalance()}');
      expect(await w.stock(p), closeTo(stockBefore, kEps));
      expect((await w.db.select(w.db.journalEntries).get()).length, journalBefore);
    });

    test('NOINV-02 صنف بتكلفة صفر لم يُشترَ: يُرفض المرتجع قبل إنشاء أي أثر',
        skip: kSkip, () async {
      final p = await w.addProduct('Z', price: 6.99, cost: 0, stock: 0);
      // تكلفة الصنف صفر لا تعفيه من سقف الكمية؛ لم يُبع، لذا يُرفض بلا أثر.
      final stockBefore = await w.stock(p);
      await expectLater(
        _noInvoiceReturn(w, p, 7, 6.99),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('المتاح: 0'),
        )),
      );
      expect(await w.stock(p), closeTo(stockBefore, kEps));
      expect(await w.linesOf('sales_return', 0), isEmpty);
    });

    test('NOINV-04 المسار الحي يرفض 7 بعد بيع 5 قبل أي أثر',
        skip: kSkip, () async {
      final p = await w.addProduct('P699b', price: 6.99, cost: 4, stock: 0);
      await w.db.setSetting('enable_negative_sales', 'true');
      final s = await w.sell([w.line(p, 5, 6.99)]);
      final stockBefore = await w.stock(p);
      final safeBefore = await w.safeBalance();
      final journalBefore = (await w.db.select(w.db.journalEntries).get()).length;
      final invoiceBefore = (await w.db.select(w.db.salesInvoices).get()).length;
      final r = await w.sales.completeSalesTransaction(SaleRequest(
          items: [w.line(p, 7, 6.99)],
          warehouseId: w.warehouseId,
          userId: w.userId,
          paymentMethod: 'cash',
          paidAmount: 48.93,
          cashAmount: 48.93,
          bankAmount: 0,
          taxEnabled: false,
          isReturn: true,
          saleType: 'return',
          cashSafeId: w.cashSafeId));
      expect(r.isSuccess, isFalse);
      expect(r.errorMessage, contains('المتاح: 5'));
      expect(await w.stock(p), closeTo(stockBefore, kEps));
      expect(await w.safeBalance(), closeTo(safeBefore, kEps));
      expect((await w.db.select(w.db.journalEntries).get()).length, journalBefore);
      expect((await w.db.select(w.db.salesInvoices).get()).length, invoiceBefore);
      _log('NOINV-04 sale=${await w.linesOf('sales_invoice', s.invoiceId!)} '
          'rejection=${r.errorMessage} stock=${await w.stock(p)} safe=${await w.safeBalance()}');
    });

    test('NOINV-03 المرتجع ضمن صافي المباع يبقي القيد متوازناً',
        skip: kSkip, () async {
      await w.sell([w.line(q, 1, 100)]);
      final ret = await _noInvoiceReturn(w, q, 1, 100);
      final je = await w.linesOf('sales_return', ret);
      _log('NOINV-03 je=$je refs=${await _refs(w)} safe=${await w.safeBalance()} stock=${await w.stock(q)}');
      expect(je, isNotEmpty);
      expect(await w.unbalancedEntries(), isEmpty);
    });
  });

  group('EXC استبدال', () {
    test('EXC-01 استبدال 1×Q(100/60) بـ 1×R(150/90): صافٍ +50 نقداً، COGS صافٍ +30', skip: kSkip,
        () async {
      final rP = await w.addProduct('R', price: 150, cost: 90);
      await buy(rP, 10, 90);
      final sale = await w.sell([w.line(q, 1, 100)]);
      final inv = (await w.db.getSalesInvoiceById(sale.invoiceId!))!;
      final item = (await w.db.getSalesInvoiceItems(inv.id)).single;
      final ex = ExchangeRepositoryImpl(
        w.db,
        w.container.read(returnsRepositoryProvider) as ReturnsRepositoryImpl,
        w.sales,
      );
      final res = await ex.processExchange(
        originalInvoice: inv,
        returnQuantities: {item.id: 1},
        returnProductCache: {q: await _entity(w, q)},
        replacementItems: [w.line(rP, 1, 150)],
        warehouseId: w.warehouseId,
        userId: w.userId,
        userName: 'مدقق',
        taxEnabled: false,
      );
      _log('EXC-01 refunded=${res.cashRefunded} collected=${res.cashCollected} safe=${await w.safeBalance()} '
          'stockQ=${await w.stock(q)} stockR=${await w.stock(rP)} 4121=${await w.accountNet('4121')} '
          '4211=${await w.accountNet('4211')} 5211=${await w.accountNet('5211')} 1136=${await w.accountNet('1136')}');
      expect(await w.safeBalance(), closeTo(150, kEps));
      expect(await w.accountNet('5211'), closeTo(90, kEps));
      expect(await w.stock(q), closeTo(50, kEps));
      expect(await w.stock(rP), closeTo(9, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });
  });

  group('VOID إلغاء', () {
    test('VOID-01 إلغاء فاتورة نقدية: صفر في كل شيء', skip: kSkip, () async {
      final r = await w.sell([w.line(q, 2, 100)]);
      await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);
      _log('VOID-01 safe=${await w.safeBalance()} stock=${await w.stock(q)} 4121=${await w.accountNet('4121')} '
          '5211=${await w.accountNet('5211')} refs=${await _refs(w)}');
      expect(await w.safeBalance(), closeTo(0, kEps));
      expect(await w.stock(q), closeTo(50, kEps));
      expect(await w.accountNet('4121'), closeTo(0, kEps));
      expect(await w.accountNet('5211'), closeTo(0, kEps));
    });

    test('VOID-02 إلغاء فاتورة آجلة بعد تحصيل 50: الخزنة = الأستاذ والعميل = حسابه', skip: kSkip,
        () async {
      final c = await w.addCustomer('ع');
      final r = await w.sell([w.line(q, 2, 100)], customerId: c, method: 'credit', paid: 0);
      await w.db.addSalesPayment(invoiceId: r.invoiceId!, amount: 50, safeId: w.cashSafeId, userId: w.userId);
      Object res = true;
      try {
        await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);
      } catch (e) {
        res = 'EXC: $e';
      }
      final glCash = await w.accountNet('111');
      _log('VOID-02 void=$res party=${await w.partyBalance(c)} ar1121=${await w.accountNet('1121')} '
          'safe=${await w.safeBalance()} gl111=$glCash 4121=${await w.accountNet('4121')} '
          'mismatch=${await w.db.getPartyBalanceMismatches()}');
      expect(await w.safeBalance(), closeTo(glCash, kEps));
      expect(await w.partyBalance(c), closeTo(await w.accountNet('1121'), kEps));
      expect(await w.accountNet('4121'), closeTo(0, kEps));
    });

    test('VOID-03 إلغاء بعد مرتجع جزئي ⇒ يُرفض', skip: kSkip, () async {
      final r = await w.sell([w.line(q, 2, 100)]);
      await _ret(w, r.invoiceId!, q, 1);
      Object res = true;
      try {
        await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);
      } catch (e) {
        res = 'EXC: $e';
      }
      _log('VOID-03 void=$res stock=${await w.stock(q)} safe=${await w.safeBalance()}');
      expect(res, isNot(true));
    });
  });

  group('EDIT تعديل فاتورة مرحّلة', () {
    SalesInvoiceItemsCompanion item(int p, double qty, double price, double cost) =>
        SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: p,
            quantity: qty,
            unitPrice: price,
            total: qty * price,
            costPrice: Value(cost));

    test('EDIT-01 تعديل الكمية 2→3 (إجمالي 300): القيد والتكلفة يتبعان', skip: kSkip, () async {
      final r = await w.sell([w.line(q, 2, 100)]);
      final inv0 = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      Object res = true;
      try {
        await w.db.updateSalesInvoice(
            invoiceId: r.invoiceId!,
            subtotal: 300,
            discount: 0,
            tax: 0,
            total: 300,
            paid: 300,
            paymentMethod: 'cash',
            items: [item(q, 3, 100, 60)],
            userId: w.userId);
      } catch (e) {
        res = 'EXC: $e';
      }
      _log('EDIT-01 isLocked=${inv0.isLocked} res=$res stock=${await w.stock(q)} safe=${await w.safeBalance()} '
          '4121=${await w.accountNet('4121')} 5211=${await w.accountNet('5211')} 111=${await w.accountNet('111')} '
          'refs=${await _refs(w)}');
      if (res == true) {
        expect(await w.accountNet('4121'), closeTo(-300, kEps));
        expect(await w.accountNet('5211'), closeTo(180, kEps));
        expect(await w.safeBalance(), closeTo(await w.accountNet('111'), kEps));
      }
    });

    test('EDIT-02 استبدال الصنف بصنف أغلى تكلفةً والإجمالي ثابت: COGS يجب أن يتحدّث', skip: kSkip,
        () async {
      final rP = await w.addProduct('R', price: 100, cost: 90);
      await buy(rP, 10, 90);
      final r = await w.sell([w.line(q, 2, 100)]);
      Object res = true;
      try {
        await w.db.updateSalesInvoice(
            invoiceId: r.invoiceId!,
            subtotal: 200,
            discount: 0,
            tax: 0,
            total: 200,
            paid: 200,
            paymentMethod: 'cash',
            items: [item(rP, 2, 100, 90)],
            userId: w.userId);
      } catch (e) {
        res = 'EXC: $e';
      }
      _log('EDIT-02 res=$res stockQ=${await w.stock(q)} stockR=${await w.stock(rP)} '
          '5211=${await w.accountNet('5211')} 1136=${await w.accountNet('1136')} refs=${await _refs(w)}');
      if (res == true) expect(await w.accountNet('5211'), closeTo(180, kEps));
    });

    test('EDIT-03 تعديل فاتورة عليها مرتجع ⇒ يجب الرفض', skip: kSkip, () async {
      final r = await w.sell([w.line(q, 2, 100)]);
      await _ret(w, r.invoiceId!, q, 1);
      Object res = true;
      try {
        await w.db.updateSalesInvoice(
            invoiceId: r.invoiceId!,
            subtotal: 200,
            discount: 0,
            tax: 0,
            total: 200,
            paid: 200,
            paymentMethod: 'cash',
            items: [item(q, 2, 100, 60)],
            userId: w.userId);
      } catch (e) {
        res = 'EXC: $e';
      }
      final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      _log('EDIT-03 res=$res status=${inv.status} stock=${await w.stock(q)}');
      expect(res, isNot(true));
    });
  });

  test('EDIT-04 سلسلة: مرتجع 1 ⇒ تعديل (يمسح partial_return) ⇒ إلغاء ⇒ هل يُعكس المرتجع مرتين؟',
      skip: kSkip, () async {
    final r = await w.sell([w.line(q, 2, 100)]);
    await _ret(w, r.invoiceId!, q, 1);
    await expectLater(
      w.db.updateSalesInvoice(
          invoiceId: r.invoiceId!,
          subtotal: 200,
          discount: 0,
          tax: 0,
          total: 200,
          paid: 200,
          paymentMethod: 'cash',
          items: [
            SalesInvoiceItemsCompanion.insert(
                invoiceId: 0, productId: q, quantity: 2, unitPrice: 100, total: 200,
                costPrice: const Value(60))
          ],
          userId: w.userId),
      throwsA(isA<StateError>()),
    );
    final preserved = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
    expect(preserved.status, 'partial_return');
    Object res = true;
    try {
      await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);
    } catch (e) {
      res = 'EXC: $e';
    }
    _log('EDIT-04 void=$res stock=${await w.stock(q)} safe=${await w.safeBalance()} '
        '111=${await w.accountNet('111')} 4121=${await w.accountNet('4121')} 4211=${await w.accountNet('4211')}');
    expect(res, isNot(true), reason: 'الفاتورة عليها مرتجع؛ يجب ألا يُسمح بإلغائها');
  });

  group('RCV التحصيل اللاحق', () {
    test('RCV-01 فاتورة آجلة 200 وتحصيل 120 ثم 80: مدفوعة والعميل صفر', skip: kSkip, () async {
      final c = await w.addCustomer('ع');
      final r = await w.sell([w.line(q, 2, 100)], customerId: c, method: 'credit', paid: 0);
      await w.db.addSalesPayment(invoiceId: r.invoiceId!, amount: 120, safeId: w.cashSafeId, userId: w.userId);
      await w.db.addSalesPayment(invoiceId: r.invoiceId!, amount: 80, safeId: w.cashSafeId, userId: w.userId);
      final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      _log('RCV-01 paid=${inv.paid} status=${inv.status} party=${await w.partyBalance(c)} '
          'safe=${await w.safeBalance()} 1121=${await w.accountNet('1121')}');
      expect(inv.status, 'paid');
      expect(await w.partyBalance(c), closeTo(0, kEps));
      expect(await w.accountNet('1121'), closeTo(0, kEps));
    });

    test('RCV-02 تحصيل زائد 250 على فاتورة 200 ⇒ يجب الرفض', () async {
      final c = await w.addCustomer('ع');
      final r = await w.sell([w.line(q, 2, 100)], customerId: c, method: 'credit', paid: 0);
      final safeBefore = await w.safeBalance();
      final partyBefore = await w.partyBalance(c);
      final arBefore = await w.accountNet('1121');
      Object res = true;
      try {
        await w.db.addSalesPayment(invoiceId: r.invoiceId!, amount: 250, safeId: w.cashSafeId, userId: w.userId);
      } catch (e) {
        res = 'EXC: $e';
      }
      final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      _log('RCV-02 res=$res paid=${inv.paid} total=${inv.total} party=${await w.partyBalance(c)}');
      expect(res, isNot(true));
      expect(inv.paid, closeTo(0, kEps));
      expect(await w.partyBalance(c), closeTo(partyBefore, kEps));
      expect(await w.safeBalance(), closeTo(safeBefore, kEps));
      expect(await w.accountNet('1121'), closeTo(arBefore, kEps));
    });

    test('RCV-03 تحصيل سالب −50 مباشرة على الـDAO ⇒ يجب الرفض', () async {
      final c = await w.addCustomer('ع');
      final r = await w.sell([w.line(q, 2, 100)], customerId: c, method: 'credit', paid: 0);
      final safeBefore = await w.safeBalance();
      final partyBefore = await w.partyBalance(c);
      Object res = true;
      try {
        await w.db.addSalesPayment(invoiceId: r.invoiceId!, amount: -50, safeId: w.cashSafeId, userId: w.userId);
      } catch (e) {
        res = 'EXC: $e';
      }
      final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      _log('RCV-03 res=$res paid=${inv.paid} party=${await w.partyBalance(c)} safe=${await w.safeBalance()}');
      expect(res, isNot(true));
      expect(inv.paid, closeTo(0, kEps));
      expect(await w.partyBalance(c), closeTo(partyBefore, kEps));
      expect(await w.safeBalance(), closeTo(safeBefore, kEps));
    });

    test('RCV-04 SalesRepository.recordPayment يرفض خفض paid دون حركة مالية',
        () async {
      final c = await w.addCustomer('ع');
      final r = await w.sell([w.line(q, 2, 100)], customerId: c, method: 'credit', paid: 0);
      await w.db.addSalesPayment(invoiceId: r.invoiceId!, amount: 150, safeId: w.cashSafeId, userId: w.userId);
      final safeBefore = await w.safeBalance();
      final partyBefore = await w.partyBalance(c);
      final arBefore = await w.accountNet('1121');
      final journalsBefore = (await w.db.select(w.db.journalEntries).get()).length;
      Object result = true;
      try {
        await w.container.read(salesRepositoryProvider).recordPayment(r.invoiceId!, 20, userId: w.userId);
      } catch (e) {
        result = 'EXC: $e';
      }
      final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      _log('RCV-04 result=$result paid=${inv.paid} status=${inv.status} party=${await w.partyBalance(c)} '
          'safe=${await w.safeBalance()} 1121=${await w.accountNet('1121')}');
      expect(result, isNot(true));
      expect(inv.paid, closeTo(150, kEps), reason: 'paid يجب ألا يتغير بلا حركة مقابلة');
      expect(await w.partyBalance(c), closeTo(partyBefore, kEps));
      expect(await w.safeBalance(), closeTo(safeBefore, kEps));
      expect(await w.accountNet('1121'), closeTo(arBefore, kEps));
      expect((await w.db.select(w.db.journalEntries).get()).length, journalsBefore);
    });
  });
}
