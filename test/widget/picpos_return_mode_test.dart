import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/returnable_line.dart';
import 'package:ural_erp/presentation/pos_picpos/state/pos_return_mode.dart';

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

    test('السعرُ من الفاتورة لا من شاشة الأصناف', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [l]);
      expect(mode.unitPriceOf(l.invoiceItemId), 12.5);
    });
  });
}
