// قسمةُ مردود المشتريات بين ذمّة المورّد والنقد — الصيغةُ الواحدة.
//
// ═══ ما يُقاس ═══
//
// القسمةُ كانت مكتوبةً بيدها في خمسة مواضع، والواجهةُ كانت ستصير سادسة:
// قرارُ المالك 2026-09-18 أنّ «طريقة التسوية» **مرآةٌ مشتقّة** لا قائمةُ
// اختيار. ومرآةٌ تحسب بنفسها ليست مرآة.
//
// فتُقاس الصيغةُ هنا مباشرةً بحالاتها الأربع، ويُقاس حدُّها الشاذّ الذي
// يُنتج ذمّةً **تزيد** بمردود.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/purchase_return_settlement.dart';

PurchaseReturnSettlement _s({
  required double net,
  double vat = 0,
  required double total,
  required double paid,
}) =>
    resolvePurchaseReturnSettlement(
      returnNet: net,
      returnVat: vat,
      invoiceTotal: total,
      invoicePaid: paid,
    );

void main() {
  test('فاتورةٌ غيرُ مسدَّدةٍ ⇒ الذمّةُ وحدَها', () {
    final s = _s(net: 100, total: 900, paid: 0);
    expect(s.apPortion, 100);
    expect(s.cashPortion, 0);
    expect(s.methodLabel, 'تخفيض ذمة المورد');
    expect(s.remainingBefore, 900);
    expect(s.remainingAfter, 800);
  });

  test('وفاتورةٌ مسدَّدةٌ بالكامل ⇒ نقدٌ وحدَه', () {
    final s = _s(net: 100, total: 900, paid: 900);
    expect(s.apPortion, 0);
    expect(s.cashPortion, 100);
    expect(s.methodLabel, 'استرداد نقدي');
    expect(s.remainingAfter, 0);
  });

  test('ومسدَّدةٌ جزئيّاً ومردودٌ يتجاوز المتبقّي ⇒ الرِّجلان معاً', () {
    // ⚠️ **وهذه هي الحالةُ التي تُسقط قائمةَ الاختيار.** «طريقة التسوية»
    // كقائمةٍ مفردةٍ لا تعرف أن تقول «الاثنان»، فيختار المستخدمُ واحدةً
    // ويفعل المحرّكُ الاثنتين.
    final s = _s(net: 500, total: 900, paid: 700);
    expect(s.remainingBefore, 200);
    expect(s.apPortion, 200);
    expect(s.cashPortion, 300);
    expect(s.methodLabel, 'تخفيض ذمة المورد + استرداد نقدي');
    expect(s.remainingAfter, 0);
  });

  test('والضريبةُ تدخل القسمةَ — الرصيدُ مخزَّنٌ إجماليّاً', () {
    final s = _s(net: 100, vat: 14, total: 900, paid: 850);
    expect(s.gross, 114);
    expect(s.remainingBefore, 50);
    expect(s.apPortion, 50);
    expect(s.cashPortion, 64,
        reason: 'قسمةُ الصافي وحدَه تترك الضريبةَ بلا رِجْلٍ تحملها');
  });

  test('ودفعةٌ زائدةٌ لا تُنتج ذمّةً تزيد بمردود', () {
    // متبقٍّ سالبٌ بلا `clamp` يجعل `apPortion` سالبةً، فيُزاد ما نَدين به
    // للمورّد عند ردِّ بضاعةٍ إليه — عكسُ المعنى تماماً.
    final s = _s(net: 100, total: 900, paid: 1000);
    expect(s.remainingBefore, 0);
    expect(s.apPortion, 0);
    expect(s.cashPortion, 100);
    expect(s.remainingAfter, 0);
  });

  test('ومردودٌ صفرٌ ⇒ لا تسوية', () {
    final s = _s(net: 0, total: 900, paid: 0);
    expect(s.apPortion, 0);
    expect(s.cashPortion, 0);
    expect(s.methodLabel, 'لا تسوية');
  });

  test('والرِّجلان تجمعان الإجماليَّ بالبناء', () {
    // خاصّيّةٌ يعتمد عليها `autoPostPurchaseReturn`: مجموعُهما = المردودُ
    // شاملَ الضريبة، فلا حاجةَ لتقسيطِ ضريبةٍ منفصلٍ في القيد.
    for (final (total, paid) in const [
      (900.0, 0.0),
      (900.0, 450.0),
      (900.0, 900.0),
      (900.0, 1200.0),
    ]) {
      final s = _s(net: 300, vat: 42, total: total, paid: paid);
      expect(s.apPortion + s.cashPortion, closeTo(s.gross, 1e-9),
          reason: 'الرِّجلان لا تجمعان الإجماليَّ عند total=$total paid=$paid');
    }
  });
}
