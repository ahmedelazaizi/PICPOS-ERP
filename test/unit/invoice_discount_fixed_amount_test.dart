// بند ٦ — المرحلة ب: خصمُ الفاتورة بمبلغٍ ثابت قائمٌ بذاته بجانب النسبة.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/settings_providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';
import 'package:picpos_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';

CartItemEntity _item(double price,
        {double qty = 1, double discountPercent = 0, int id = 1}) =>
    CartItemEntity(
      productId: id,
      productName: 'p$id',
      productCode: 'p$id',
      unitPrice: price,
      quantity: qty,
      discountPercent: discountPercent,
    );

void main() {
  final uc = CalculateInvoiceTotalsUseCase();

  group('CalculateInvoiceTotalsUseCase — مبلغ ثابت', () {
    test('10.00 على أساس 100 ⇒ يُخصم 10.00 بالضبط (لا 9.99)', () {
      final t = uc.execute(items: [_item(100)], invoiceDiscountAmount: 10.00);
      expect(t.invoiceDiscount, 10.00);
      expect(t.total, 90.00);
    });

    test('الأساس = المجموع − خصومات الأصناف', () {
      // 200 − 20% سطر (40) = 160؛ مبلغ 25 ⇒ 135.
      final t = uc.execute(
        items: [_item(200, discountPercent: 20)],
        invoiceDiscountAmount: 25,
      );
      expect(t.invoiceDiscount, 25);
      expect(t.totalDiscount, 65);
      expect(t.total, 135);
    });

    test('يُقصّ عند الحد الأقصى للمجموع (لا إجمالي سالب)', () {
      final t = uc.execute(items: [_item(50)], invoiceDiscountAmount: 80);
      expect(t.invoiceDiscount, 50);
      expect(t.total, 0);
    });

    test('القصُّ بعد خصم الأصناف: أساس 160 ومبلغ 500 ⇒ 160', () {
      final t = uc.execute(
        items: [_item(200, discountPercent: 20)],
        invoiceDiscountAmount: 500,
      );
      expect(t.invoiceDiscount, 160);
      expect(t.total, 0);
    });

    test('المبلغ يتقدّم على النسبة إن اجتمعا', () {
      final t = uc.execute(
        items: [_item(100)],
        invoiceDiscountPercent: 50,
        invoiceDiscountAmount: 10,
      );
      expect(t.invoiceDiscount, 10);
    });

    test('مبلغ صفر/سالب ⇒ لا خصم، والنسبة وحدها كما كانت', () {
      expect(uc.execute(items: [_item(100)], invoiceDiscountAmount: 0).invoiceDiscount, 0);
      expect(uc.execute(items: [_item(100)], invoiceDiscountAmount: -5).invoiceDiscount, 0);
      expect(uc.execute(items: [_item(100)], invoiceDiscountPercent: 12.5).invoiceDiscount, 12.5);
    });

    test('الضريبة تُحسب على الصافي بعد المبلغ كما بعد النسبة المكافئة', () {
      final byAmount = uc.execute(
        items: [_item(100)],
        invoiceDiscountAmount: 10,
        taxPercent: 14,
      );
      final byPercent = uc.execute(
        items: [_item(100)],
        invoiceDiscountPercent: 10,
        taxPercent: 14,
      );
      expect(byAmount.taxAmount, byPercent.taxAmount);
      expect(byAmount.total, byPercent.total);
      expect(byAmount.total, closeTo(102.6, 1e-9)); // (100−10)×1.14
    });

    test('قاعدة صفر (سلة بخصم أسطر كامل) ⇒ لا قسمة ولا خصم', () {
      final t = uc.execute(
        items: [_item(100, discountPercent: 100)],
        invoiceDiscountAmount: 10,
      );
      expect(t.invoiceDiscount, 0);
    });
  });

  group('CartState / CartController', () {
    late ProviderContainer container;
    late CartController cart;
    CartState read() => container.read(cartControllerProvider);

    setUp(() {
      container = ProviderContainer(overrides: [
        posDefaultTaxRateProvider.overrideWith((ref) async => 0.0),
      ]);
      cart = container.read(cartControllerProvider.notifier);
      addTearDown(container.dispose);
      cart.state = read().copyWith(items: [_item(100)]);
    });

    test('setInvoiceDiscountAmount(10) ⇒ الإجمالي 90.00 والنسبة المخزَّنة 0', () {
      cart.setInvoiceDiscountAmount(10);
      expect(read().invoiceDiscountAmount, 10);
      expect(read().discountPercent, 0);
      expect(read().totals.invoiceDiscount, 10.00);
      expect(read().total, 90.00);
      expect(read().hasInvoiceDiscount, isTrue);
    });

    test('الأساس يتغيّر: المبلغ يثبت (لا يعاد حسابه كنسبة)', () {
      cart.setInvoiceDiscountAmount(10);
      cart.state = read().copyWith(items: [_item(100), _item(100, id: 2)]);
      expect(read().totals.invoiceDiscount, 10); // لم يصبح 20
      expect(read().total, 190);
    });

    test('الأساس ينكمش دون المبلغ ⇒ يُقصّ، ثم يعود كاملاً عند الزيادة', () {
      cart.setInvoiceDiscountAmount(10);
      cart.state = read().copyWith(items: [_item(6)]);
      expect(read().totals.invoiceDiscount, 6);
      expect(read().total, 0);
      expect(read().invoiceDiscountAmount, 10); // الحالة لم تُقصّ
      cart.state = read().copyWith(items: [_item(40)]);
      expect(read().totals.invoiceDiscount, 10);
    });

    test('الدورة نسبة ↔ مبلغ: كلٌّ يُصفّر الآخر', () {
      cart.setDiscount(20);
      expect(read().totals.invoiceDiscount, 20);
      cart.setInvoiceDiscountAmount(10);
      expect(read().discountPercent, 0);
      expect(read().totals.invoiceDiscount, 10);
      cart.setDiscount(5);
      expect(read().invoiceDiscountAmount, isNull);
      expect(read().totals.invoiceDiscount, 5);
      cart.setInvoiceDiscountAmount(0); // إزالة
      expect(read().invoiceDiscountAmount, isNull);
      expect(read().hasInvoiceDiscount, isFalse);
      expect(read().totals.invoiceDiscount, 0);
    });

    test('copyWith لا يمسح المبلغ عرَضاً، ويمسحه بـnull صريح', () {
      cart.setInvoiceDiscountAmount(10);
      expect(read().copyWith(deliveryFee: 3).invoiceDiscountAmount, 10);
      expect(read().copyWith(invoiceDiscountAmount: null).invoiceDiscountAmount,
          isNull);
    });

    test('النسبة الفعلية = المبلغ ÷ الأساس، وبعد القصّ 100', () {
      cart.setInvoiceDiscountAmount(10);
      expect(read().effectiveInvoiceDiscountPercent, 10);
      expect(read().effectivePercentForAmount(25), 25);
      expect(read().effectivePercentForAmount(500), 100); // قُصّ عند الأساس
      expect(read().effectivePercentForAmount(0), 0);
    });

    test('سياسة السقف تقيس النسبة الفعلية: 10 على 100 مع سقف 10 مسموح، 10.01 لا', () {
      cart.setInvoiceDiscountAmount(10);
      expect(
        quickSaleDiscountAllowed(
            percent: read().effectivePercentForAmount(10), cap: 10),
        isTrue,
      );
      expect(
        quickSaleDiscountAllowed(
            percent: read().effectivePercentForAmount(10.01), cap: 10),
        isFalse,
      );
      // مبلغ يتجاوز الأساس يُقاس 100% لا المُدخل ⇒ مرفوض عند سقف 50.
      expect(
        quickSaleDiscountAllowed(
            percent: read().effectivePercentForAmount(1000), cap: 50),
        isFalse,
      );
    });

    test('نسبة فعلية بلا ضجيج عائم: 7 على 70 = 10 تماماً', () {
      cart.state = read().copyWith(items: [_item(70)]);
      expect(read().effectivePercentForAmount(7), 10);
      expect(
        quickSaleDiscountAllowed(
            percent: read().effectivePercentForAmount(7), cap: 10),
        isTrue,
      );
    });
  });
}
