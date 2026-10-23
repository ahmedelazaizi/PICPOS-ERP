// سيناريو (ج): مرتجع مبيعات (يعيد المخزون ويعكس القيد ويخفض الرصيد).
// سيناريو (ط): إلغاء/عكس فاتورة مرحّلة (القيد المعاكس والمخزون يعودان).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/models/return_original_link.dart';

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

  /// قراءة الصف مباشرة: getSalesInvoiceById يرشّح الملغاة (is_deleted) فيعيد null بعد الإلغاء.
  Future<SalesInvoiceData?> rowOf(int id) => (w.db.select(w.db.salesInvoices)
        ..where((i) => i.id.equals(id)))
      .getSingleOrNull();

  /// لقطة كل ما يجب ألا يتغير عند رفض الإلغاء: المخزون والخزينة والقيود والحركات.
  Future<({double stock, double safe, int entries, int moves, int safeTx, double debit, double credit})>
      snapshot() async {
    Future<int> count(String table) async =>
        (await w.db.customSelect('select count(*) c from $table').getSingle())
            .data['c'] as int;
    final t = await w.journalTotals();
    return (
      stock: await w.stock(product),
      safe: await w.safeBalance(),
      entries: await count('journal_entries'),
      moves: await count('stock_movements'),
      safeTx: await count('safe_transactions'),
      debit: t.debit,
      credit: t.credit,
    );
  }

  /// «إلغاء المرتجع» كما تنادِيه شاشة سجل مرتجعات المبيعات (على الفاتورة الأصلية).
  Future<void> cancelReturn(int invoiceId) async {
    final invoice = (await rowOf(invoiceId))!;
    await w.container.read(returnsRepositoryProvider).cancelSalesReturn(
          invoice: invoice,
          userId: w.userId,
          userName: 'مستخدم السيناريو',
        );
  }

  /// كـ`w.returnItems` لكن مرتجعًا كاملًا (الحالة تصبح `returned`).
  Future<bool> fullReturn(int invoiceId, int productId, double qty) async {
    final it = (await w.db.getSalesInvoiceItems(invoiceId))
        .firstWhere((i) => i.productId == productId);
    final p = (await w.db.getProductById(productId))!;
    return w.container.read(returnsRepositoryProvider).processSalesReturn(
          invoice: (await rowOf(invoiceId))!,
          returnQuantities: {it.id: qty},
          productCache: {
            productId: ProductEntity(
                id: p.id,
                name: p.name,
                code: p.code,
                salePrice: p.salePrice,
                costPrice: p.costPrice,
                currentStock: p.currentStock,
                minStock: p.minStock,
                trackInventory: p.trackInventory)
          },
          reason: 'سيناريو',
          userId: w.userId,
          userName: 'مستخدم السيناريو',
          isFullReturn: true,
        );
  }

  /// مستند مرتجع مستقل (الشكل الذي ينشئه معالج API وPOS): `saleType='return'`
  /// مربوط بالأصل بنص `notes` (المعرّف العالمي + الرقم). يعيد معرّفه.
  Future<int> returnDocFor(int originalId, {required double qty}) async {
    final orig = (await rowOf(originalId))!;
    return w.db.createSalesInvoice(
      warehouseId: w.warehouseId,
      userId: w.userId,
      subtotal: qty * 100,
      discount: 0,
      tax: 0,
      total: qty * 100,
      paid: qty * 100,
      paymentMethod: 'cash',
      saleType: 'return',
      notes: localReturnLinkNote(orig.id, originalGlobalId: orig.globalId),
      items: [
        SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: product,
            quantity: qty,
            unitPrice: 100,
            total: qty * 100,
            costPrice: const Value(60)),
      ],
    );
  }

  /// صف مرتجع بملاحظة ربط معيّنة (لاختبار مطابقة الربط فقط، بلا أثر مخزني).
  var retRowSeq = 0;
  Future<void> insertReturnRow(String note) => w.db.into(w.db.salesInvoices).insert(
      SalesInvoicesCompanion.insert(
          invoiceNumber: 'RETROW-${++retRowSeq}',
          warehouseId: w.warehouseId,
          userId: w.userId,
          invoiceDate: DateTime.now(),
          total: const Value(100),
          saleType: const Value('return'),
          notes: Value(note)));

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

    test('إلغاء فاتورة سبق ارتجاع جزء منها يُرفض ولا يغيّر المخزون ولا الخزينة ولا القيود',
        () async {
      final r = await w.sell([w.line(product, 5, 100)]);
      await w.returnItems(r.invoiceId!, product, 2);
      final before = await snapshot();
      expect(before.stock, closeTo(47, kEps));
      expect(before.safe, closeTo(300, kEps));

      await expectLater(
        w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId),
        throwsA(isA<SalesVoidBlockedException>()
            .having((e) => e.message, 'message', kSalesVoidHasReturnMessage)),
      );

      expect(await snapshot(), before, reason: 'الرفض قبل أي كتابة');
      final inv = await rowOf(r.invoiceId!);
      expect(inv!.status, 'partial_return');
      expect(inv.isDeleted, isFalse);
    });

    test('مرتجع جزئي ثم إلغاء المرتجع ثم إلغاء الفاتورة ينجح: مخزون 50 وخزينة 0 وعميل 0',
        () async {
      final r = await w.sell([w.line(product, 5, 100)], customerId: customer);
      await w.returnItems(r.invoiceId!, product, 2);
      await expectLater(w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId),
          throwsA(isA<SalesVoidBlockedException>()));

      await cancelReturn(r.invoiceId!);
      // إلغاء المرتجع يعيد الأصل إلى completed ويُعيد الأرصدة لما بعد البيع.
      expect((await rowOf(r.invoiceId!))!.status, 'completed');
      expect(await w.stock(product), closeTo(45, kEps));
      expect(await w.safeBalance(), closeTo(500, kEps));

      await w.db.voidSalesInvoice(r.invoiceId!, reason: 'بعد إلغاء المرتجع', deletedBy: w.userId);

      final inv = await rowOf(r.invoiceId!);
      expect(inv!.status, 'voided');
      expect(await w.stock(product), closeTo(50, kEps));
      expect(await w.whQty(product, w.warehouseId), closeTo(50, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
      expect(await w.partyBalance(customer), closeTo(0, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('آجل: مرتجع جزئي ثم إلغاء المرتجع ثم الفاتورة يصفّر العميل ويعيد المخزون', () async {
      final r = await w.sell([w.line(product, 5, 100)],
          customerId: customer, method: 'credit');
      await w.returnItems(r.invoiceId!, product, 2);
      expect(await w.partyBalance(customer), closeTo(300, kEps));
      await expectLater(w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId),
          throwsA(isA<SalesVoidBlockedException>()));
      expect(await w.partyBalance(customer), closeTo(300, kEps));

      await cancelReturn(r.invoiceId!);
      await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);

      // ⚠️ عيب سابق خارج النطاق: cancelSalesReturn يعيد الذمم في الأستاذ (1121)
      // لكن لا يعيد parties.balance لبيع آجل (يبقى 300 بدل 500) فيخرج العميل -200
      // بعد الإلغاء؛ لذا لا أثبّت رصيد العميل هنا، وأثبّت الأستاذ والمخزون فقط.
      expect(await w.stock(product), closeTo(50, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
      expect(await w.accountNet('1121'), closeTo(0, kEps));
    });

    test('مرتجع كامل (returned) يمنع الإلغاء، وبعد إلغاء المرتجع يُلغى', () async {
      final r = await w.sell([w.line(product, 4, 100)]);
      expect(await fullReturn(r.invoiceId!, product, 4), isTrue);
      expect((await rowOf(r.invoiceId!))!.status, 'returned');
      final before = await snapshot();

      await expectLater(
        w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId),
        throwsA(isA<SalesVoidBlockedException>()
            .having((e) => e.message, 'message', kSalesVoidHasReturnMessage)),
      );
      expect(await snapshot(), before);

      await cancelReturn(r.invoiceId!);
      await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);
      expect(await w.stock(product), closeTo(50, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
    });

    test('إلغاء مستند saleType=return مباشرة يُرفض ولا يضاعف المخزون', () async {
      final r = await w.sell([w.line(product, 5, 100)]);
      final doc = await returnDocFor(r.invoiceId!, qty: 2);
      final before = await snapshot();

      await expectLater(
        w.db.voidSalesInvoice(doc, deletedBy: w.userId),
        throwsA(isA<SalesVoidBlockedException>()
            .having((e) => e.message, 'message', kSalesVoidReturnDocMessage)),
      );
      expect(await snapshot(), before, reason: 'لا +2 إضافية في المخزون');
      expect((await rowOf(doc))!.isDeleted, isFalse);
    });

    test('أصل له صف مرتجع مربوط حيّ (الشكل المستقل) يُرفض حتى لو الحالة completed', () async {
      final r = await w.sell([w.line(product, 5, 100)]);
      final doc = await returnDocFor(r.invoiceId!, qty: 2);
      expect((await rowOf(r.invoiceId!))!.status, 'completed',
          reason: 'تجهيزة: الحالة وحدها لا تدل — هذا ما يغطيه فحص الصف المربوط');
      final before = await snapshot();
      await expectLater(w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId),
          throwsA(isA<SalesVoidBlockedException>()));
      expect(await snapshot(), before);

      // مرتجع محذوف (غير حيّ) لا يمنع.
      await (w.db.update(w.db.salesInvoices)..where((i) => i.id.equals(doc)))
          .write(const SalesInvoicesCompanion(isDeleted: Value(true)));
      await w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId);
      expect((await rowOf(r.invoiceId!))!.status, 'voided');
    });

    test('الربط بالمعرّف العالمي حاسم؛ والرقم الاحتياطي لا يطابق #10 مع #1 ولا فاتورة أخرى',
        () async {
      final a = await w.sell([w.line(product, 2, 100)]);
      final b = await w.sell([w.line(product, 2, 100)]);
      final invA = (await rowOf(a.invoiceId!))!;
      // صفوف مرتجع مربوطة بفاتورة أخرى (الرقم ×10، أو gid غريب) لا تمنع A ولا B.
      await insertReturnRow(localReturnLinkNote(invA.id * 10, originalGlobalId: 'other-gid'));
      await insertReturnRow(localReturnLinkNote(invA.id * 10));
      await insertReturnRow(localReturnLinkNote(invA.id, originalGlobalId: 'other-gid'));
      await w.db.voidSalesInvoice(a.invoiceId!, deletedBy: w.userId);
      await w.db.voidSalesInvoice(b.invoiceId!, deletedBy: w.userId);

      // صيغة قديمة بلا gid (رقم فقط) تمنع.
      final c = await w.sell([w.line(product, 2, 100)]);
      final invC = (await rowOf(c.invoiceId!))!;
      await insertReturnRow(localReturnLinkNote(invC.id));
      await expectLater(w.db.voidSalesInvoice(c.invoiceId!, deletedBy: w.userId),
          throwsA(isA<SalesVoidBlockedException>()));
    });

    test('انحدار: فاتورة بلا مرتجعات (نقدي وآجل) تُلغى كما كانت، ومرتجع فاتورة أخرى لا يمنعها',
        () async {
      final other = await w.sell([w.line(product, 3, 100)]);
      await w.returnItems(other.invoiceId!, product, 1); // مرتجع على فاتورة مختلفة

      final cash = await w.sell([w.line(product, 5, 100)]);
      final credit = await w.sell([w.line(product, 2, 100)],
          customerId: customer, method: 'credit');
      expect(await w.safeBalance(), closeTo(300 - 100 + 500, kEps)); // 700 قبل الإلغاء

      await w.db.voidSalesInvoice(cash.invoiceId!, reason: 'نقدي', deletedBy: w.userId);
      await w.db.voidSalesInvoice(credit.invoiceId!, reason: 'آجل', deletedBy: w.userId);

      for (final id in [cash.invoiceId!, credit.invoiceId!]) {
        final inv = await rowOf(id);
        expect(inv!.status, 'voided');
        expect(inv.isDeleted, isTrue);
      }
      // بقي أثر الفاتورة الأخرى فقط: بيع 3 − مرتجع 1 = مخزون 48، خزينة 200.
      expect(await w.stock(product), closeTo(48, kEps));
      expect(await w.safeBalance(), closeTo(200, kEps));
      expect(await w.partyBalance(customer), closeTo(0, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });

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
