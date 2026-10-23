import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/returnable_line.dart';
import 'package:picpos_erp/presentation/pos_picpos/state/pos_return_mode.dart';

void main() {
  const l = ReturnableLine(
    invoiceItemId: 5, productId: 9, productName: 'لوز',
    soldQty: 4, alreadyReturnedQty: 1, unitPrice: 12.5,
  );

  group('PosReturnMode', () {
    test('الكميّاتُ تبدأ صفراً — قرارُ المالك', () {
      // البدءُ بالكامل يُغري بحفظٍ سريعٍ يُرجع ما لم يُحضره العميل.
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.requestedQty[l.invoiceItemId], 0);
    });

    test('لا يقبل صنفاً خارجَ الفاتورة', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.canAcceptProduct(9), isTrue);
      expect(mode.canAcceptProduct(404), isFalse);
    });

    test('لا يقبل كميةً تتجاوز المتاح', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.setQty(l.invoiceItemId, 3), isTrue);   // المتاح ٣
      expect(mode.setQty(l.invoiceItemId, 3.5), isFalse);
    });

    test('لا تسقط تحت المقارنة الساذجة: متبقٍّ صفرٌ مُشبَّعٌ لكن السماحُ يقبل ٠٫٠٠٠٥', () {
      // remaining = soldQty - alreadyReturnedQty = 0 بالضبط ⇒ availableQty
      // مُشبَّعةٌ إلى صفر (قيمةُ عرض)، لكنّ isReturnRequestValid تسمح بما
      // دون remaining + 0.001 — فتقبل ٠٫٠٠٠٥ بينما المقارنةُ الساذجةُ
      // `qty > availableQty(=0)` ترفضها.
      const zeroRemaining = ReturnableLine(
        invoiceItemId: 12, productId: 23, productName: 'كاجو',
        soldQty: 3, alreadyReturnedQty: 3, unitPrice: 1,
      );
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [zeroRemaining]);
      expect(mode.setQty(zeroRemaining.invoiceItemId, 0.0005), isTrue);
    });

    test('لا تسقط تحت المقارنة الساذجة: كميةٌ داخلَ سماح ٠٫٠٠١ فوق المتبقّي الموجب', () {
      // المتبقّي هنا 3 (نظيفٌ غيرُ مُشبَّع). المقارنةُ الساذجةُ
      // `qty > availableQty(=3)` ترفض 3.0005، بينما isReturnRequestValid
      // (‏٣ + سماح ٠٫٠٠١) تقبلها.
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.setQty(l.invoiceItemId, 3.0005), isTrue);
    });

    test('السعرُ من الفاتورة لا من شاشة الأصناف', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.unitPriceOf(l.invoiceItemId), 12.5);
    });

    test('clearQty تُصفِّر سطراً محدَّداً ولا تلمس غيرَه', () {
      const other = ReturnableLine(
        invoiceItemId: 7, productId: 3, productName: 'سكر',
        soldQty: 2, alreadyReturnedQty: 0, unitPrice: 5,
      );
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l, other]);
      expect(mode.setQty(l.invoiceItemId, 2), isTrue);
      expect(mode.setQty(other.invoiceItemId, 1), isTrue);

      mode.clearQty(l.invoiceItemId);

      expect(mode.requestedQty[l.invoiceItemId], 0);
      expect(mode.requestedQty[other.invoiceItemId], 1);
    });

    test('clearQty على itemId غير موجود بلا أثر ولا استثناء', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(() => mode.clearQty(999), returnsNormally);
      expect(mode.requestedQty.containsKey(999), isFalse);
    });
  });
}
