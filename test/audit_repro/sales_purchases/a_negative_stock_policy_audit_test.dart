// تدقيق المبيعات والمخزون — (أ) فرض enable_negative_sales (2026-10-31).
//
// السياق: بيانات المالك: بيعت 13 وحدة من المنتج 178 و5 من 179 بمخزون صفر
// والإعداد enable_negative_sales='false' ومع ذلك نجح البيع.
//
// الحالات تثبت أن السياسة الفعّالة تسمح أو تمنع خصم مخزون الصنف، مع بقاء
// enable_negative_sales وعلم الصنف كاستثناءات سماح. الحالات المعتمدة هنا تعمل
// دائماً؛ بقية حالات التدقيق ما زالت موسومة skip.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';

import '../../scenarios/scenario_world.dart';

const kSkip = 'audit repro — pending owner approval';

void _log(String m) {
  // ignore: avoid_print
  print('[AUDIT-NEG] $m');
}

Future<String> _state(ScenarioWorld w, int p) async {
  final prod = (await w.db.getProductById(p))!;
  final bal = await w.db
      .customSelect('SELECT quantity q FROM inventory_balances WHERE product_id = ?',
          variables: [Variable<int>(p)])
      .get();
  final mv = await w.db
      .customSelect(
          'SELECT movement_type t, quantity q, unit_cost c, balance_after b '
          'FROM stock_movements WHERE product_id = ? ORDER BY id',
          variables: [Variable<int>(p)])
      .get();
  return 'current_stock=${prod.currentStock} inv_bal=${bal.map((e) => e.data['q']).toList()} '
      'movements=${mv.map((e) => e.data).toList()}';
}

void main() {
  late ScenarioWorld w;
  late int p178; // صنف بلا أي رصيد (لم يُشترَ قط)

  setUp(() async {
    StockShortagePolicyService.resetCacheForTest();
    w = await ScenarioWorld.create();
    await w.db.setSetting('enable_negative_sales', 'false');
    p178 = await w.addProduct('P178', price: 10, cost: 6);
  });
  tearDown(() async {
    StockShortagePolicyService.resetCacheForTest();
    await w.dispose();
  });

  group('AUD-NEG enable_negative_sales=false', () {
    test('NEG-01 لا مفاتيح سياسة نقص: بيع 13 بمخزون صفر يُرفض (الخط الأساس)',
        skip: kSkip, () async {
      final r = await w.sellRaw([w.line(p178, 13, 10)]);
      _log('NEG-01 success=${r.isSuccess} err=${r.errorMessage} | ${await _state(w, p178)}');
      expect(r.isSuccess, isFalse);
      expect(await w.stock(p178), closeTo(0, kEps));
    });

    test('NEG-02 سياسة «نقص الخامات» العامة = allow_negative تتجاوز الإعداد false', () async {
      await w.db.setSetting('stock_shortage_policy', 'allow_negative');
      final r = await w.sellRaw([w.line(p178, 13, 10)]);
      _log('NEG-02 success=${r.isSuccess} err=${r.errorMessage} | ${await _state(w, p178)}');
      expect(r.isSuccess, isTrue);
      expect(await w.stock(p178), closeTo(-13, kEps));
      final movement = await w.db.customSelect(
        'SELECT unit_cost FROM stock_movements WHERE product_id = ? AND movement_type = ?',
        variables: [Variable<int>(p178), const Variable<String>('sale')],
      ).getSingle();
      expect((movement.data['unit_cost'] as num).toDouble(), closeTo(6, kEps));
      final cogs = await w.db.customSelect(
        'SELECT SUM(l.debit - l.credit) amount FROM journal_entry_lines l '
        'JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id '
        "WHERE e.reference_type = 'sales_invoice' AND e.reference_id = ? AND a.code = '5211'",
        variables: [Variable<int>(r.invoiceId!)],
      ).getSingle();
      expect((cogs.data['amount'] as num).toDouble(), closeTo(78, kEps));
    });

    test('NEG-03 خريطة الطرفيات فارغة "{}" (بعد إزالة تخصيص طرفية) ⇒ الافتراضي allowNegative', () async {
      await w.db.setSetting('stock_shortage_policy_per_terminal', '{}');
      final r = await w.sellRaw([w.line(p178, 13, 10)]);
      _log('NEG-03 success=${r.isSuccess} err=${r.errorMessage} | ${await _state(w, p178)}');
      expect(r.isSuccess, isTrue);
      expect(await w.stock(p178), closeTo(-13, kEps));
    });

    test('NEG-04 تخصيص لفرع آخر فقط {"999":"block"} ⇒ فرعنا يرث allowNegative', () async {
      await w.db.setSetting('stock_shortage_policy_per_branch', '{"999":"block"}');
      final r = await w.sellRaw([w.line(p178, 5, 10)]);
      _log('NEG-04 success=${r.isSuccess} err=${r.errorMessage} | ${await _state(w, p178)}');
      expect(r.isSuccess, isTrue);
      expect(await w.stock(p178), closeTo(-5, kEps));
    });

    test('NEG-05 تحديث السياسة إلى block يسري فوراً بعد الكتابة الخارجية', () async {
      await w.db.setSetting('stock_shortage_policy', 'allow_negative');
      final p2 = await w.addProduct('P179', price: 10, cost: 6);
      await w.sellRaw([w.line(p2, 1, 10)]); // يملأ الكاش بـ allowNegative
      // المدير (أو المزامنة) يكتب block مباشرة في settings دون saveGlobal:
      await w.db.setSetting('stock_shortage_policy', 'block');
      final r = await w.sellRaw([w.line(p178, 5, 10)]);
      _log('NEG-05 success=${r.isSuccess} err=${r.errorMessage} | ${await _state(w, p178)}');
      expect(r.isSuccess, isFalse, reason: 'الكاش الساكن _cachedGlobal ما زال allowNegative');
    });

    test('NEG-06 علم الصنف allow_negative_sale=1 يتجاوز الإعداد (سلوك مقصود — للتوثيق)',
        skip: kSkip, () async {
      await (w.db.update(w.db.products)..where((t) => t.id.equals(p178)))
          .write(const ProductsCompanion(allowNegativeSale: Value(true)));
      final r = await w.sellRaw([w.line(p178, 13, 10)]);
      _log('NEG-06 success=${r.isSuccess} | ${await _state(w, p178)}');
      // توثيق: نتوقّع النجاح هنا (علم الصنف أقوى من الإعداد العام بالتصميم)
      expect(r.isSuccess, isTrue);
    });

    test('NEG-07 صنف track_inventory=0: يُباع بلا حدّ ولا حركة مخزون ولا تكلفة',
        skip: kSkip, () async {
      await (w.db.update(w.db.products)..where((t) => t.id.equals(p178)))
          .write(const ProductsCompanion(trackInventory: Value(false)));
      final r = await w.sellRaw([w.line(p178, 13, 10)]);
      _log('NEG-07 success=${r.isSuccess} | ${await _state(w, p178)} '
          'JE=${r.isSuccess ? await w.linesOf('sales_invoice', r.invoiceId!) : '-'}');
      expect(r.isSuccess, isTrue);
    });

    test('NEG-08 الكمية > الرصيد (رصيد 3، بيع 13) تُرفض', skip: kSkip, () async {
      final p = await w.addProduct('P3', price: 10, cost: 6, stock: 3);
      final r = await w.sellRaw([w.line(p, 13, 10)]);
      _log('NEG-08 success=${r.isSuccess} err=${r.errorMessage} | ${await _state(w, p)}');
      expect(r.isSuccess, isFalse);
      expect(await w.stock(p), closeTo(3, kEps));
    });

    test('NEG-09 سطران لنفس الصنف (2+2) برصيد 3 ⇒ يُرفض الثاني والفاتورة كلها تتراجع',
        skip: kSkip, () async {
      final p = await w.addProduct('P3b', price: 10, cost: 6, stock: 3);
      final r = await w.sellRaw([w.line(p, 2, 10), w.line(p, 2, 10)]);
      _log('NEG-09 success=${r.isSuccess} err=${r.errorMessage} | ${await _state(w, p)}');
      expect(r.isSuccess, isFalse);
      expect(await w.stock(p), closeTo(3, kEps));
    });
  });
}
