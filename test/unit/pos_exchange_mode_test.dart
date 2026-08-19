// وضعُ الاستبدال — الحالةُ الخالصة.
//
// **يلفّ `PosReturnMode` ولا ينسخه.** حسابُ المرتجع وسياجُ الكمية وقبولُ
// الصنف كلُّها مُختبَرةٌ هناك، ونسخةٌ ثانيةٌ من حسابِ مالٍ هي العطبُ المتكرّرُ
// في هذه السلسلة: رقمٌ يُعرَض على الكاشير وآخرُ يُنفَّذ على الدرج.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/exchange_settlement.dart';
import 'package:ural_erp/domain/models/returnable_line.dart';
import 'package:ural_erp/presentation/pos_picpos/state/pos_exchange_mode.dart';

PosExchangeMode _mode() => PosExchangeMode.fromLines(
      invoiceId: 7,
      invoiceTotal: 100,
      lines: const [
        ReturnableLine(
          invoiceItemId: 1,
          productId: 11,
          productName: 'صنفٌ سليم',
          soldQty: 2,
          alreadyReturnedQty: 0,
          unitPrice: 25,
          lineTotal: 50,
        ),
        ReturnableLine(
          invoiceItemId: 2,
          productId: 22,
          productName: 'صنفٌ معيب',
          soldQty: 2,
          alreadyReturnedQty: 0,
          unitPrice: 25,
          lineTotal: 50,
        ),
      ],
    );

void main() {
  group('وضعُ الاستبدال — الحالة', () {
    test('الأرقامُ الثلاثةُ من `settleExchange` لا بحسابٍ محلّيّ', () {
      final mode = _mode();
      mode.setQty(1, 2); // مرتجعٌ بـ50

      final preview = mode.previewSettlement(replacementTotal: 130);
      final expected = settleExchange(returnTotal: 50, saleTotal: 130);

      expect(preview.direction, expected.direction);
      expect(preview.amount, expected.amount);
      expect(preview.direction, ExchangeCashDirection.collect);
      expect(preview.amount, 80);
    });

    test('البديلُ الأرخصُ يقلب الاتّجاه إلى ردٍّ لا إلى سالب', () {
      final mode = _mode()..setQty(1, 2);
      final preview = mode.previewSettlement(replacementTotal: 20);
      expect(preview.direction, ExchangeCashDirection.refund);
      expect(preview.amount, 30, reason: 'المبلغُ موجبٌ دائماً — الإشارةُ في الاتّجاه');
    });

    test('التساوي لا يحرّك الدرج', () {
      final mode = _mode()..setQty(1, 2);
      expect(mode.previewSettlement(replacementTotal: 50).direction,
          ExchangeCashDirection.none);
    });

    test('وسمُ العيب يُضبط لكلّ سطرٍ ويُقلَب', () {
      final mode = _mode();
      expect(mode.isDamaged(2), isFalse);
      mode.setDamaged(2, true);
      expect(mode.isDamaged(2), isTrue);
      expect(mode.isDamaged(1), isFalse, reason: 'الوسمُ للسطر لا للنداء كلِّه');
      mode.setDamaged(2, false);
      expect(mode.isDamaged(2), isFalse);
    });

    test('سطرٌ موسومٌ بكميةٍ صفرٍ لا يدخل الوسومَ المؤثّرة', () {
      final mode = _mode();
      mode.setQty(1, 1);
      mode.setDamaged(2, true); // موسومٌ لكن كميّتُه صفر
      expect(mode.effectiveDamagedItemIds, isEmpty,
          reason: 'وسمٌ بلا كميةٍ يُتلف صنفاً لم يُرتجَع أصلاً');

      mode.setQty(2, 1);
      expect(mode.effectiveDamagedItemIds, {2});
    });

    test('سطرٌ لا وجودَ له لا يُوسَم', () {
      final mode = _mode();
      mode.setDamaged(999, true);
      expect(mode.isDamaged(999), isFalse);
    });

    test('«فيه اختيارُ مرتجع» شرطُ الحفظ لا مجرّدُ فتحِ الوضع', () {
      final mode = _mode();
      expect(mode.hasReturnSelection, isFalse);
      mode.setQty(1, 1);
      expect(mode.hasReturnSelection, isTrue);
      mode.clearQty(1);
      expect(mode.hasReturnSelection, isFalse);
    });

    test('سياجُ الكمية موروثٌ من شقّ المرتجع لا مُعادٌ كتابتُه', () {
      final mode = _mode();
      expect(mode.setQty(1, 99), isFalse,
          reason: 'أكثرُ من المُباع — يرفضه `PosReturnMode` نفسُه');
      expect(mode.hasReturnSelection, isFalse);
    });

    test('كمياتُ الإرجاع المؤثّرةُ تُسقط الأصفار', () {
      final mode = _mode();
      mode.setQty(1, 2);
      expect(mode.effectiveReturnQuantities, {1: 2.0});
    });
  });
}
