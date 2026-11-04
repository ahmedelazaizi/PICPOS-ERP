// «مرتجع سريع» في شاشة البيع السريع — عيبُ التحقّق الحيّ final3 (2026-11-03):
// بعد اختيار `SINV-7` (6.99) وتأكيد المرتجع كان عمودُ الفاتورة يعرض سلّةَ
// البيع الفارغة، والشبكةُ/حقلُ المسح يرفضان صنفَ الفاتورة نفسَه (`20004`).
//
// هذا الملفّ يقيس المنطقَ الذي صار يقود «سلّة المرتجع» على فاتورة بيعٍ
// حقيقيّة في قاعدة اختبار (‏ScenarioWorld) — نفسُ دوالّ الشاشة لا نسخٌ منها:
//  • `buildQuickReturnLines` (‏اختيارُ الفاتورة ← سطورُها بالمتاح للإرجاع)،
//  • `addProductToQuickReturn` (‏البطاقة/الباركود ضمن ما بيع فعلاً وإلّا رفض)،
//  • `setQuickReturnLineQty` (‏تعديلُ الكميّة مسقوفاً بالمتاح)،
//  • `quickReturnQuantitiesOf` + `computeIsFullReturn` ثم
//    `processSalesReturn` — فتتطابق القيودُ والمخزونُ والخزنة مع مرتجع شاشة
//    مرتجعات المبيعات (‏`ScenarioWorld.returnItems`).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/pos_picpos/screens/picpos_pos_screen.dart'
    as picpos;
import 'package:picpos_erp/presentation/pos_picpos/state/pos_return_mode.dart';

import 'scenario_world.dart';

/// ما يفعله `_showQuickReturn` بعد اختيار الفاتورة — بالدوالّ نفسِها.
Future<({PosReturnMode mode, Map<int, ProductEntity> cache, SalesInvoiceData invoice})>
    _openQuickReturn(ScenarioWorld w, int invoiceId) async {
  final returnsRepo = w.container.read(returnsRepositoryProvider);
  final invoice = (await w.db.getSalesInvoiceById(invoiceId))!;
  final items = await returnsRepo.getSalesInvoiceItems(invoiceId);
  final products = await w.container
      .read(productRepositoryProvider)
      .getProductsByIds(items.map((i) => i.productId).toSet().toList());
  final returned = await returnsRepo.getReturnedQuantitiesForInvoice(invoiceId);
  final lines = picpos.buildQuickReturnLines(
      items: items, products: products, returnedBaseByProduct: returned);
  final mode = PosReturnMode.fromLines(
    invoiceId: invoice.id,
    lines: lines,
    invoiceTotal: invoice.total,
    invoiceDeliveryFee: invoice.deliveryFee,
  );
  return (mode: mode, cache: {for (final p in products) p.id: p}, invoice: invoice);
}

/// ما يفعله `_processQuickReturnSave` — بلا سبب ولا `isDamaged`، كما في الشاشة.
Future<bool> _saveQuickReturn(ScenarioWorld w,
    ({PosReturnMode mode, Map<int, ProductEntity> cache, SalesInvoiceData invoice}) r,
    PosReturnMode mode) {
  return w.container.read(returnsRepositoryProvider).processSalesReturn(
        invoice: r.invoice,
        returnQuantities: picpos.quickReturnQuantitiesOf(mode),
        productCache: r.cache,
        userId: w.userId,
        userName: 'مستخدم السيناريو',
        isFullReturn: picpos.computeIsFullReturn(mode),
      );
}

Future<int> _count(ScenarioWorld w, String table) async =>
    (await w.db.customSelect('select count(*) c from $table').getSingle())
        .data['c'] as int;

void main() {
  late ScenarioWorld w;
  late int almond; // «لوز انصاص» — الكود 20004 كما في التحقّق الحيّ.
  late int unsold;

  setUp(() async {
    w = await ScenarioWorld.create();
    almond = await w.addProduct('20004', price: 6.99, cost: 4, stock: 10);
    unsold = await w.addProduct('30005', price: 3, cost: 1, stock: 10);
  });
  tearDown(() => w.dispose());

  test('اختيار الفاتورة يحمّل بنودها بالكميّات القابلة للإرجاع', () async {
    final sale = await w.sell([w.line(almond, 1, 6.99)]);
    final r = await _openQuickReturn(w, sale.invoiceId!);

    expect(r.mode.linesByItemId, hasLength(1));
    final line = r.mode.linesByItemId.values.single;
    expect(line.productId, almond);
    expect(line.availableQty, closeTo(1, kEps));
    // الكميّاتُ تبدأ صفراً (قرارُ المالك)، و«تحديد الكلّ» يملؤها بالمتاح.
    expect(r.mode.requestedQty[line.invoiceItemId], 0);
    final full = picpos.setQuickReturnLineQty(
        r.mode, line.invoiceItemId, line.availableQty)!;
    expect(full.refundTotal, closeTo(6.99, kEps));
  });

  test('البطاقة/الباركود 20004 يضيف ضمن ما بيع، والصنفُ غير المباع يُرفض برسالة',
      () async {
    final sale = await w.sell([w.line(almond, 2, 6.99)]);
    final r = await _openQuickReturn(w, sale.invoiceId!);
    final scanned = (await w.container
        .read(productRepositoryProvider)
        .getProductByCode('20004'))!;

    final first = picpos.addProductToQuickReturn(r.mode, scanned.id);
    expect(first.outcome, picpos.QuickReturnAddOutcome.added);
    final itemId = first.line!.invoiceItemId;
    expect(first.mode.requestedQty[itemId], 1);
    // نسخةٌ جديدة — الأصلُ لم يتغيّر، فالمزوِّدُ يُخطر المراقبين.
    expect(identical(first.mode, r.mode), isFalse);
    expect(r.mode.requestedQty[itemId], 0);

    final second = picpos.addProductToQuickReturn(first.mode, scanned.id);
    expect(second.mode.requestedQty[itemId], 2);
    final third = picpos.addProductToQuickReturn(second.mode, scanned.id);
    expect(third.outcome, picpos.QuickReturnAddOutcome.exhausted);
    expect(third.mode.requestedQty[itemId], 2);

    final foreign = picpos.addProductToQuickReturn(second.mode, unsold);
    expect(foreign.outcome, picpos.QuickReturnAddOutcome.notInInvoice);
  });

  test('تعديل الكميّة مسقوفٌ بالمتاح، والصفرُ يستبعد السطر', () async {
    final sale = await w.sell([w.line(almond, 3, 6.99)]);
    final r = await _openQuickReturn(w, sale.invoiceId!);
    final itemId = r.mode.linesByItemId.keys.single;

    final two = picpos.setQuickReturnLineQty(r.mode, itemId, 2)!;
    expect(two.requestedQty[itemId], 2);
    expect(picpos.setQuickReturnLineQty(two, itemId, 4), isNull);
    expect(picpos.setQuickReturnLineQty(two, itemId, 0)!.requestedQty[itemId], 0);
  });

  test('مرتجعٌ سابق يُنقص المتاح عند فتح المرتجع السريع ثانيةً', () async {
    final sale = await w.sell([w.line(almond, 3, 6.99)]);
    expect(await w.returnItems(sale.invoiceId!, almond, 1), isTrue);
    final r = await _openQuickReturn(w, sale.invoiceId!);
    expect(r.mode.linesByItemId.values.single.availableQty, closeTo(2, kEps));
  });

  group('إتمام المرتجع السريع = مرتجع شاشة مرتجعات المبيعات محاسبياً', () {
    Future<Map<String, num>> snapshot(ScenarioWorld x, int pid) async => {
          'stock': await x.stock(pid),
          'whQty': await x.whQty(pid, x.warehouseId),
          'safe': await x.safeBalance(),
          'acc111': await x.accountNet('111'),
          'acc4211': await x.accountNet('4211'),
          'acc5211': await x.accountNet('5211'),
          'acc1136': await x.accountNet('1136'),
          'journal_entries': await _count(x, 'journal_entries'),
          'stock_movements': await _count(x, 'stock_movements'),
          'safe_transactions': await _count(x, 'safe_transactions'),
        };

    test('مرتجعٌ جزئيّ نقديّ: قيود ومخزون وخزنة متطابقة', () async {
      final sale = await w.sell([w.line(almond, 3, 6.99)]);
      final r = await _openQuickReturn(w, sale.invoiceId!);
      var mode = picpos.addProductToQuickReturn(r.mode, almond).mode;
      mode = picpos.addProductToQuickReturn(mode, almond).mode;
      expect(await _saveQuickReturn(w, r, mode), isTrue);
      final quick = await snapshot(w, almond);

      final ref = await ScenarioWorld.create();
      try {
        final pid = await ref.addProduct('20004', price: 6.99, cost: 4, stock: 10);
        await ref.addProduct('30005', price: 3, cost: 1, stock: 10);
        final s2 = await ref.sell([ref.line(pid, 3, 6.99)]);
        expect(await ref.returnItems(s2.invoiceId!, pid, 2), isTrue);
        final screen = await snapshot(ref, pid);
        for (final k in screen.keys) {
          expect(quick[k]!.toDouble(), closeTo(screen[k]!.toDouble(), kEps),
              reason: k);
        }
      } finally {
        await ref.dispose();
      }

      expect(quick['stock']!.toDouble(), closeTo(9, kEps)); // 10 − 3 + 2
      expect(quick['safe']!.toDouble(), closeTo(6.99, kEps)); // 20.97 − 13.98
      expect(quick['acc4211']!.toDouble(), closeTo(13.98, kEps));
      expect(quick['acc5211']!.toDouble(), closeTo(4, kEps)); // 12 − 8
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('مرتجعٌ كامل (6.99): الفاتورة تُختم مرتجعة والخزنة تعود صفراً', () async {
      final sale = await w.sell([w.line(almond, 1, 6.99)]);
      final r = await _openQuickReturn(w, sale.invoiceId!);
      final mode = picpos.addProductToQuickReturn(r.mode, almond).mode;
      expect(picpos.computeIsFullReturn(mode), isTrue);
      expect(await _saveQuickReturn(w, r, mode), isTrue);

      expect(await w.stock(almond), closeTo(10, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
      expect(await w.accountNet('4211'), closeTo(6.99, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
      expect((await w.db.getSalesInvoiceById(sale.invoiceId!))!.status,
          'returned');
    });
  });
}
