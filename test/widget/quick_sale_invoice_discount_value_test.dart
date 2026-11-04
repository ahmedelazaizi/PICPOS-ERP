// خصم الفاتورة بالقيمة بجانب النسبة (بند ٦ — المرحلة ب): الحوارُ يمرّر المبلغَ
// **كما أُدخل** (بلا تحويل إلى نسبةٍ مقرَّبة)، والقصُّ عند القاعدة في الحساب.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_cart_permissions.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_invoice_discount_dialog.dart';

void main() {
  /// يفتح الحوارَ ويُعيد مقبضاً لنتيجته.
  Future<Future<PicPosInvoiceDiscountChoice?> Function()> open(
    WidgetTester tester, {
    required double base,
    double current = 0,
  }) async {
    Future<PicPosInvoiceDiscountChoice?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => result = showPicPosInvoiceDiscountDialog(context,
                  base: base, currentPercent: current),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result!;
  }

  testWidgets('وضع القيمة: 10.00 تُمرَّر مبلغاً كما أُدخلت لا نسبة', (tester) async {
    final res = await open(tester, base: 100);
    await tester.tap(find.textContaining('قيمة').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10.00');
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    final r = (await res())!;
    expect(r.amount, 10.0);
    expect(r.percent, isNull);
  });

  testWidgets('قيمة لا تقبل نسبةً مقرَّبة: 9.99 على قاعدة 333 تبقى 9.99', (tester) async {
    final res = await open(tester, base: 333);
    await tester.tap(find.textContaining('قيمة').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9.99');
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect((await res())!.amount, 9.99);
  });

  testWidgets('وضع النسبة يبقى كما كان', (tester) async {
    final res = await open(tester, base: 200);
    await tester.enterText(find.byType(TextField), '15');
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    final r = (await res())!;
    expect(r.percent, 15);
    expect(r.amount, isNull);
  });

  testWidgets('القيمةُ فوق القاعدة تُمرَّر كما هي (القصُّ في الحساب لا الحوار)',
      (tester) async {
    final res = await open(tester, base: 50);
    await tester.tap(find.textContaining('قيمة').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '80');
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    expect((await res())!.amount, 80);
  });

  testWidgets('«إزالة الخصم» ⇒ نسبة ٠، والإغلاقُ بلا تطبيق ⇒ null', (tester) async {
    var res = await open(tester, base: 200, current: 10);
    await tester.tap(find.text('إزالة الخصم'));
    await tester.pumpAndSettle();
    final r = (await res())!;
    expect(r.percent, 0);
    expect(r.amount, isNull);

    res = await open(tester, base: 200, current: 10);
    await tester.tapAt(const Offset(2, 2)); // الحاجز
    await tester.pumpAndSettle();
    expect(await res(), isNull);
  });

  test('المبلغ المُدخل يُخصم تماماً من قاعدة بخصم أسطر', () {
    // سطران: ١٠٠ + ١٠٠، خصمُ سطرٍ ٢٠٪ ⇒ قاعدة الفاتورة ١٨٠.
    final items = [
      const CartItemEntity(
        productId: 1, productName: 'a', productCode: 'a', unitPrice: 100,
        quantity: 1, discountPercent: 20,
      ),
      const CartItemEntity(
        productId: 2, productName: 'b', productCode: 'b', unitPrice: 100,
        quantity: 1,
      ),
    ];
    final after = CalculateInvoiceTotalsUseCase()
        .execute(items: items, invoiceDiscountAmount: 45);
    expect(after.invoiceDiscount, 45);
    expect(after.total, 135);
  });
}
