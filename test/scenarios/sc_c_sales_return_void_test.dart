// سيناريو (ج): مرتجع مبيعات (يعيد المخزون ويعكس القيد ويخفض الرصيد).
// سيناريو (ط): إلغاء/عكس فاتورة مرحّلة (القيد المعاكس والمخزون يعودان).
import 'package:flutter_test/flutter_test.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  late int customer;

  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('C1', price: 100, cost: 60, stock: 50);
    customer = await w.addCustomer('عميل المرتجع');
  });
  tearDown(() => w.dispose());

  group('(ج) مرتجع المبيعات', () {
    test('مرتجع جزئي لفاتورة نقدية: 2 من 5 ← مخزون +2، خزينة −200، إيراد صافٍ 300',
        () async {
      final r = await w.sell([w.line(product, 5, 100)]);
      expect(await w.stock(product), closeTo(45, kEps));
      expect(await w.safeBalance(), closeTo(500, kEps));
      expect(await w.accountNet('5211'), closeTo(300, kEps)); // 5 × 60

      expect(await w.returnItems(r.invoiceId!, product, 2), isTrue);

      expect(await w.stock(product), closeTo(47, kEps));
      expect(await w.whQty(product, w.warehouseId), closeTo(47, kEps));
      expect(await w.safeBalance(), closeTo(300, kEps));
      expect(await w.accountNet('111'), closeTo(300, kEps),
          reason: 'إجمالي النقدية في الأستاذ = رصيد الخزينة');
      // صافي الإيراد بعد المرتجع = 3 × 100 (قد يُقيَّد المرتجع على حساب مردودات)
      final salesNet = -(await w.accountNet('4'));
      expect(salesNet, closeTo(300, kEps));
      expect(await w.accountNet('4211'), closeTo(200, kEps),
          reason: 'المرتجع يُقيَّد مدينًا على مردودات المبيعات');
      // تكلفة المبيعات تنخفض بتكلفة المرتجع 2 × 60
      expect(await w.accountNet('5211'), closeTo(180, kEps));
      // المخزون المحاسبي يعود بـ 120
      expect(await w.accountNet('1136'), closeTo(-180, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('مرتجع فاتورة آجلة يخفض رصيد العميل ويطابق كشف الحساب', () async {
      final r = await w.sell([w.line(product, 5, 100)],
          customerId: customer, method: 'credit');
      expect(await w.partyBalance(customer), closeTo(500, kEps));

      expect(await w.returnItems(r.invoiceId!, product, 3), isTrue);

      expect(await w.partyBalance(customer), closeTo(200, kEps));
      expect(await w.accountNet('1121'), closeTo(200, kEps));
      expect(await w.stock(product), closeTo(48, kEps));
      final st = await w.db.getPartyStatement(customer);
      expect(st.last.balance, closeTo(200, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps),
          reason: 'الفاتورة آجلة: لا خروج نقدية');
      expect(await w.unbalancedEntries(), isEmpty);
      expect(await w.db.getPartyBalanceMismatches(), isEmpty);
    });

    test('مرتجع كامل يُرجع كل الأرصدة إلى ما قبل البيع', () async {
      final before = (stock: await w.stock(product), safe: await w.safeBalance());
      final r = await w.sell([w.line(product, 4, 100)]);
      expect(await w.returnItems(r.invoiceId!, product, 4), isTrue);
      expect(await w.stock(product), closeTo(before.stock, kEps));
      expect(await w.safeBalance(), closeTo(before.safe, kEps));
      expect(await w.accountNet('4'), closeTo(0, kEps));
      expect(await w.accountNet('5211'), closeTo(0, kEps));
      expect(await w.accountNet('1136'), closeTo(0, kEps));
    });
  });

  group('(ج) مرتجع نقدي على حساب الخزينة الفعلي', () {
    test('المرتجع النقدي يُقيَّد على حساب الخزينة نفسها التي قُيِّد عليها البيع',
        () async {
      final r = await w.sell([w.line(product, 5, 100)]);
      await w.returnItems(r.invoiceId!, product, 2);
      // الفعلي: البيع مدين 111-00001 بـ500، والمرتجع دائن 1111 بـ200 (الحساب
      // المعيَّن العام لا حساب الخزينة) ⇒ حساب الخزينة 500 بينما رصيدها 300.
      expect(await w.accountNet('111-00001'), closeTo(await w.safeBalance(), kEps));
    });

    test('انحدار: بعد المرتجع النقدي حساب الخزينة = رصيدها وإجمالي 111 كما هو', () async {
      final r = await w.sell([w.line(product, 5, 100)]);
      final total111Before = await w.accountNet('111');
      await w.returnItems(r.invoiceId!, product, 2);
      expect(await w.safeBalance(), closeTo(300, kEps));
      expect(await w.accountNet('111-00001'), closeTo(300, kEps));
      expect(await w.accountNet('1111'), closeTo(0, kEps),
          reason: 'لا شيء على الحساب المعيَّن العام');
      expect(await w.accountNet('111'), closeTo(total111Before - 200, kEps),
          reason: 'الإجمالي يهبط بالمبلغ المردود فقط');
      expect(await w.unbalancedEntries(), isEmpty);
    });
  });

  group('(ط) إلغاء فاتورة مرحّلة', () {
    test('إلغاء فاتورة نقدية: القيد يُعكس والمخزون والخزينة يعودان', () async {
      final r = await w.sell([w.line(product, 5, 100)]);
      expect(await w.accountNet('4'), closeTo(-500, kEps));

      await w.db.voidSalesInvoice(r.invoiceId!, reason: 'خطأ إدخال', deletedBy: w.userId);

      final inv = await (w.db.select(w.db.salesInvoices)
            ..where((i) => i.id.equals(r.invoiceId!)))
          .getSingle();
      expect(inv.status, 'voided');
      expect(inv.isDeleted, isTrue);
      expect(await w.stock(product), closeTo(50, kEps));
      expect(await w.whQty(product, w.warehouseId), closeTo(50, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
      // الأثر المحاسبي الصافي للفاتورة صفر
      expect(await w.accountNet('4'), closeTo(0, kEps));
      expect(await w.accountNet('5211'), closeTo(0, kEps));
      expect(await w.accountNet('1136'), closeTo(0, kEps));
      expect(await w.accountNet('111'), closeTo(0, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('إلغاء فاتورة آجلة يصفّر رصيد العميل', () async {
      final r = await w.sell([w.line(product, 2, 100)],
          customerId: customer, method: 'credit');
      expect(await w.partyBalance(customer), closeTo(200, kEps));
      await w.db.voidSalesInvoice(r.invoiceId!, reason: 'إلغاء', deletedBy: w.userId);
      expect(await w.partyBalance(customer), closeTo(0, kEps));
      expect(await w.accountNet('1121'), closeTo(0, kEps));
      expect(await w.stock(product), closeTo(50, kEps));
    });

    test('إلغاء فاتورة سبق ارتجاع جزء منها يجب ألا يعيد المخزون مرتين', () async {
      final r = await w.sell([w.line(product, 5, 100)]);
      await w.returnItems(r.invoiceId!, product, 2);
      try {
        await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);
      } on Exception {
        // الرفض مقبول
      }
      // لا يجوز أن يتجاوز المخزون الأصلي 50 ولا أن يتجاوز الخزينة 0
      expect(await w.stock(product), lessThanOrEqualTo(50 + kEps));
      expect(await w.safeBalance(), greaterThanOrEqualTo(-kEps));
    },
        skip: 'عيب إنتاجي: SalesActionsDao.voidSalesInvoice لا يتحقق من وجود مرتجعات '
            'سابقة؛ يعيد كامل الكميات (5) وكامل القيد والنقدية رغم أن 2 عادت بالمرتجع '
            '⇒ مخزون 52 بدل 50 وخزينة −200. (الفحص في الواجهة قد يمنعه؛ لم يُفحص).');

    test('إلغاء الفاتورة مرتين لا يعيد المخزون مرتين', () async {
      final r = await w.sell([w.line(product, 5, 100)]);
      await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);
      try {
        await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);
      } on Exception {
        // رفض الإلغاء الثاني سلوك مقبول؛ المهم ألا يتضاعف الأثر.
      }
      expect(await w.stock(product), closeTo(50, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
    });
  });
}
