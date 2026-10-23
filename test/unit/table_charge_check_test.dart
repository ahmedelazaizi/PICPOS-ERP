// الفحصُ القبليُّ الذي يمنع «ما يُشحَن ≠ ما يُسجَّل».
//
// المسارُ الحيُّ يقارن `cartState.total` (محرّكُ الفاتورة: ضريبةٌ فوق،
// خصومُ سلّةٍ وعروضٍ تحت) بـ`TableSessionService.amountDue` (محرّكُ الطلب:
// مجموعُ الأسطر ناقصَ خصم الطلب ناقصَ المدفوع). هذه الاختباراتُ تُثبت أن
// الفرقَ يُكتشَف بدقّة `AppConstants.decimalPlaces` لا بمقارنة `double`
// ساذجة.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/table_charge_check.dart';

void main() {
  test('التطابقُ التامُّ لا يُنتج فرقاً', () {
    expect(checkTableCharge(charged: 100, expected: 100), isNull);
  });

  test('فرقٌ دون دقّة العملة لا يُعدّ فرقاً', () {
    // ٠٫١+٠٫٢ لا تساوي ٠٫٣ في حساب الفاصلة العائمة. المقارنةُ بوحداتٍ
    // صحيحةٍ هي ما يمنع رفضَ تحصيلٍ سليمٍ لفرقٍ لا وجود له.
    final sum = <double>[0.1, 0.2].fold<double>(0, (a, b) => a + b);
    expect(sum == 0.3, isFalse, reason: 'خطأُ IEEE-754 قائمٌ فعلاً');
    expect(checkTableCharge(charged: sum, expected: 0.3), isNull);
  });

  test('الضريبةُ المضافةُ فوق تُكتشَف', () {
    // ١٦٪ على ١٠٠ — الحالةُ التي كانت تُرحَّل ثم تُرفض بعد الترحيل.
    final mismatch = checkTableCharge(charged: 116, expected: 100);
    expect(mismatch, isNotNull);
    expect(mismatch!.difference, 16);
    expect(mismatch.message, contains('116.000'));
    expect(mismatch.message, contains('100.000'));
    expect(mismatch.message, contains('16.000'));
  });

  test('الصنفُ المحذوفُ يُنتج نقصاً سالبَ الإشارة', () {
    // صنفٌ حُذف يُتخطّى من السلّة فتُشحَن أقلَّ من المستحقّ، وكان ذلك
    // يترك `paidAmount` بين الصفر والإجمالي: لا الإغلاقُ يقبل ولا الإلغاء.
    final mismatch = checkTableCharge(charged: 70, expected: 100);
    expect(mismatch, isNotNull);
    expect(mismatch!.difference, -30);
  });

  test('فرقُ مليمٍ واحدٍ يُكتشَف — لا يُبتلع', () {
    expect(checkTableCharge(charged: 100.001, expected: 100), isNotNull);
  });
}
