import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/returnable_line.dart';

ReturnableLine line({double sold = 10, double returned = 0}) => ReturnableLine(
      invoiceItemId: 1,
      productId: 1,
      productName: 'صنف',
      soldQty: sold,
      alreadyReturnedQty: returned,
      unitPrice: 5,
    );

void main() {
  test('المتاح = المباع − المرتجع سلفاً', () {
    expect(line(sold: 10, returned: 3).availableQty, 7);
  });

  test('المتاح لا ينزل تحت الصفر', () {
    // إرجاعٌ زائدٌ تاريخيٌّ لا يجعل المتاحَ سالباً فيُقلب لرصيدٍ وهميّ.
    expect(line(sold: 10, returned: 12).availableQty, 0);
  });

  test('طلبٌ يساوي المتاحَ مقبول', () {
    expect(line(sold: 10, returned: 3).isReturnRequestValid(7), isTrue);
  });

  test('طلبٌ يتجاوز المتاحَ مرفوض', () {
    expect(line(sold: 10, returned: 3).isReturnRequestValid(7.5), isFalse);
  });

  test('طلبٌ بصفرٍ أو أقلَّ مرفوض', () {
    expect(line().isReturnRequestValid(0), isFalse);
    expect(line().isReturnRequestValid(-1), isFalse);
  });

  test('يحتمل فرقَ الفاصلة العائمة', () {
    // ٠٫١+٠٫٢ = ٠٫٣٠٠٠٠٠٠٠٠٠٠٠٠٠٠٤ — ولا يجوز أن يُرفض إرجاعُ الكامل.
    const l = ReturnableLine(
      invoiceItemId: 1, productId: 1, productName: 'ص',
      soldQty: 0.3, alreadyReturnedQty: 0.1 + 0.2 - 0.3, unitPrice: 1,
    );
    expect(l.isReturnRequestValid(0.3), isTrue);
  });
}
