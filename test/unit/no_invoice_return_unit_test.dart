// بند ٤ — المرتجع السريع بلا فاتورة: المنطق الخالص (بلا شاشة ولا قاعدة بيانات).
//
// السقف · الصلاحية · دمج السطور · الإجماليُّ الصافي · خطّة التسوية · الدرج.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/models/no_invoice_return_policy.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';
import 'package:picpos_erp/domain/usecases/sales/add_return_line_usecase.dart';
import 'package:picpos_erp/domain/usecases/sales/add_to_cart_usecase.dart';
import 'package:picpos_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'package:picpos_erp/domain/usecases/sales/cart_settlement_plan.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_cart_permissions.dart';

CartItemEntity sale(int id, double qty, double price) => CartItemEntity(
      productId: id,
      productName: 'p$id',
      productCode: 'c$id',
      quantity: qty,
      unitPrice: price,
    );

CartItemEntity ret(int id, double qty, double price) =>
    sale(id, qty, price).copyWith(itemType: CartItemType.returned);

void main() {
  group('سقف المرتجع بلا فاتورة', () {
    test('الافتراضيُّ ٥٠٠ عند غياب المفتاح', () {
      expect(noInvoiceReturnCap(const QuickSalePolicyValues({})),
          kNoInvoiceReturnCapDefault);
      expect(kNoInvoiceReturnCapDefault, 500);
    });

    test('القيمةُ المخزَّنة تُقرأ، والصفرُ مسموح', () {
      QuickSalePolicyValues v(String s) =>
          QuickSalePolicyValues({kNoInvoiceReturnCapKey: s});
      expect(noInvoiceReturnCap(v('250')), 250);
      expect(noInvoiceReturnCap(v('0')), 0);
    });

    test('الفاسدُ يعود للافتراض لا لـ«بلا حدّ»', () {
      QuickSalePolicyValues v(String s) =>
          QuickSalePolicyValues({kNoInvoiceReturnCapKey: s});
      for (final bad in ['abc', '-5', 'NaN', 'Infinity', '']) {
        expect(noInvoiceReturnCap(v(bad)), kNoInvoiceReturnCapDefault,
            reason: bad);
      }
    });

    test('الحكم: المساواةُ مسموحة وما فوقها يحتاج مسؤولاً', () {
      expect(judgeNoInvoiceReturn(returnValue: 500, cap: 500),
          NoInvoiceReturnVerdict.withinCap);
      expect(judgeNoInvoiceReturn(returnValue: 500.01, cap: 500),
          NoInvoiceReturnVerdict.needsManager);
      expect(judgeNoInvoiceReturn(returnValue: 0.01, cap: 0),
          NoInvoiceReturnVerdict.needsManager);
    });

    test('الكتابةُ ثم القراءةُ تعيدان القيمةَ', () {
      final written = writeNoInvoiceReturnCap(750);
      expect(noInvoiceReturnCap(QuickSalePolicyValues(written)), 750);
    });
  });

  group('صلاحية سعر المرتجع', () {
    test('كودٌ مستقلٌّ عن pos_price_edit', () {
      expect(PermissionCodes.posReturnPriceEdit, 'pos_return_price_edit');
      expect(PermissionCodes.posReturnPriceEdit,
          isNot(PermissionCodes.posPriceEdit));
    });

    test('الكودُ مسجَّلٌ في كتالوج الصلاحيات', () {
      expect(
        PermissionCodes.masterList
            .any((p) => p['code'] == PermissionCodes.posReturnPriceEdit),
        isTrue,
      );
    });

    test('مَن يملك سعرَ البيع لا يملك سعرَ المرتجع تلقائياً (والعكس)', () {
      const priceOnly = [PermissionCodes.posPriceEdit];
      const returnOnly = [PermissionCodes.posReturnPriceEdit];
      expect(canEditLinePriceCodes(priceOnly, isReturn: false), isTrue);
      expect(canEditLinePriceCodes(priceOnly, isReturn: true), isFalse);
      expect(canEditLinePriceCodes(returnOnly, isReturn: true), isTrue);
      expect(canEditLinePriceCodes(returnOnly, isReturn: false), isFalse);
    });

    test('مدير النظام يمرّ', () {
      expect(canEditReturnPriceCodes(const ['system_admin']), isTrue);
      expect(canEditReturnPriceCodes(const ['*']), isTrue);
      expect(canEditReturnPriceCodes(const []), isFalse);
    });
  });

  group('AddReturnLineUseCase', () {
    final uc = AddReturnLineUseCase();

    test('يضيف سطراً returned بكمية ١ وسعرٍ افتراضيّ', () {
      final cart = uc.execute(
        currentCart: const [],
        productId: 1,
        productName: 'a',
        productCode: 'a',
        unitPrice: 25,
      );
      expect(cart, hasLength(1));
      expect(cart.single.itemType, CartItemType.returned);
      expect(cart.single.quantity, 1);
      expect(cart.single.effectivePrice, 25);
    });

    test('مسحتان بنفس السعر ⇒ كمية ٢ في سطر واحد', () {
      var cart = <CartItemEntity>[];
      for (var i = 0; i < 2; i++) {
        cart = uc.execute(
            currentCart: cart,
            productId: 1,
            productName: 'a',
            productCode: 'a',
            unitPrice: 25);
      }
      expect(cart, hasLength(1));
      expect(cart.single.quantity, 2);
    });

    test('سعرٌ يدويٌّ مختلف ⇒ سطرٌ منفصل', () {
      var cart = uc.execute(
          currentCart: const [],
          productId: 1,
          productName: 'a',
          productCode: 'a',
          unitPrice: 25);
      cart = uc.execute(
          currentCart: cart,
          productId: 1,
          productName: 'a',
          productCode: 'a',
          unitPrice: 25,
          customPrice: 20);
      expect(cart, hasLength(2));
    });

    test('لا يندمج في سطر بيعٍ لنفس الصنف', () {
      final cart = uc.execute(
          currentCart: [sale(1, 3, 25)],
          productId: 1,
          productName: 'a',
          productCode: 'a',
          unitPrice: 25);
      expect(cart, hasLength(2));
      expect(cart.first.itemType, CartItemType.normal);
      expect(cart.first.quantity, 3);
      expect(cart.last.itemType, CartItemType.returned);
    });

    test('والبيعُ بعد مرتجعٍ لا يقلب سطرَ المرتجع بيعاً', () {
      final cart = AddToCartUseCase().execute(
        currentCart: [ret(1, 1, 25)],
        productId: 1,
        productName: 'a',
        productCode: 'a',
        unitPrice: 25,
      );
      expect(cart, hasLength(2));
      expect(cart.first.itemType, CartItemType.returned);
      expect(cart.first.quantity, 1);
      expect(cart.last.itemType, CartItemType.normal);
    });

    test('الصنفُ المعفى يُخزَّن بنسبة صفر', () {
      final cart = uc.execute(
          currentCart: const [],
          productId: 1,
          productName: 'a',
          productCode: 'a',
          unitPrice: 25,
          taxRate: 14,
          taxExempt: true);
      expect(cart.single.taxRate, 0);
      expect(cart.single.taxExempt, isTrue);
    });
  });

  group('الإجماليُّ الصافي للسلّة المختلطة', () {
    final calc = CalculateInvoiceTotalsUseCase();

    test('بيعٌ خالصٌ ومرتجعٌ خالصٌ يمرّان كما كانا (موجبان)', () {
      expect(calc.execute(items: [sale(1, 2, 10)]).total, 20);
      expect(calc.execute(items: [ret(1, 2, 10)]).total, 20);
    });

    test('مختلط: صافي = بيع − مرتجع', () {
      final t = calc.execute(items: [sale(1, 3, 10), ret(2, 1, 12)]);
      expect(t.total, 18);
      expect(t.subtotal, 18);
    });

    test('المرتجعُ يغلب ⇒ صافٍ سالب', () {
      final t = calc.execute(items: [sale(1, 1, 10), ret(2, 2, 12)]);
      expect(t.total, -14);
    });

    test('خصمُ الفاتورة على شقّ البيع وحدَه', () {
      final t = calc.execute(
        items: [sale(1, 1, 100), ret(2, 1, 50)],
        invoiceDiscountPercent: 10,
      );
      // بيع ١٠٠ − ١٠٪ = ٩٠، المرتجع ٥٠ بلا خصم ⇒ ٤٠.
      expect(t.total, 40);
    });

    test('الضريبة تُطرَح بنفس النسبة: (١٠٠ − ٥٠) × ١٫١٤', () {
      final t = calc.execute(
        items: [sale(1, 1, 100), ret(2, 1, 50)],
        taxPercent: 14,
      );
      expect(t.total, 57);
      expect(t.taxAmount, 7);
    });
  });

  group('خطّة التسوية', () {
    test('بيعٌ فقط', () {
      final p = planCartSettlement(items: [sale(1, 1, 10)]);
      expect(p.kind, CartSettlementKind.saleOnly);
      expect(p.hasReturn, isFalse);
      expect(p.cashToCollect, 10);
    });

    test('مرتجعٌ فقط: يُردّ نقداً بكامل قيمته', () {
      final p = planCartSettlement(items: [ret(1, 2, 15)]);
      expect(p.kind, CartSettlementKind.returnOnly);
      expect(p.returnTotal, 30);
      expect(p.net, -30);
      expect(p.cashToRefund, 30);
      expect(p.cashToCollect, 0);
    });

    test('مختلط صافيه موجب: يُقبض الصافي', () {
      final p = planCartSettlement(items: [sale(1, 5, 10), ret(2, 1, 12)]);
      expect(p.kind, CartSettlementKind.mixed);
      expect(p.saleTotal, 50);
      expect(p.returnTotal, 12);
      expect(p.cashToCollect, 38);
      expect(p.cashToRefund, 0);
    });

    test('مختلط صافيه سالب: يُردّ الفرقُ نقداً', () {
      final p = planCartSettlement(items: [sale(1, 1, 10), ret(2, 3, 12)]);
      expect(p.net, -26);
      expect(p.cashToRefund, 26);
    });

    test('الخصمُ ورسومُ التوصيل على البيع وحدَه', () {
      final p = planCartSettlement(
        items: [sale(1, 1, 100), ret(2, 1, 40)],
        invoiceDiscountAmount: 20,
        deliveryFee: 5,
      );
      expect(p.saleTotal, 85);
      expect(p.returnTotal, 40);
      expect(p.net, 45);
    });

    test('الضريبةُ تُحسَب على شقّ المرتجع بنفس النسبة', () {
      final p = planCartSettlement(
        items: [ret(1, 1, 100)],
        taxPercent: 14,
      );
      expect(p.returnTotal, 114);
    });

    test('تطابقُ الخطّة مع الإجماليّ المعروض في السلّة (مصدرٌ واحد)', () {
      final items = [sale(1, 3, 9.99), ret(2, 2, 4.5)];
      final shown = CalculateInvoiceTotalsUseCase()
          .execute(items: items, taxPercent: 14)
          .total;
      final plan = planCartSettlement(items: items, taxPercent: 14);
      expect(plan.net, closeTo(shown, 0.011));
    });
  });

  group('فتح الدرج', () {
    test('يُفتح عند قبضِ صافٍ موجب وإعدادُ drawer مضاء', () {
      final p = planCartSettlement(items: [sale(1, 5, 10), ret(2, 1, 12)]);
      expect(shouldKickDrawerForSettlement(p, drawerSettingOn: true), isTrue);
      expect(shouldKickDrawerForSettlement(p, drawerSettingOn: false), isFalse);
    });

    test('لا يُفتح عند ردِّ نقد (مرتجعٌ خالص أو صافٍ سالب)', () {
      final only = planCartSettlement(items: [ret(1, 2, 15)]);
      final neg = planCartSettlement(items: [sale(1, 1, 10), ret(2, 3, 12)]);
      expect(shouldKickDrawerForSettlement(only, drawerSettingOn: true),
          isFalse);
      expect(
          shouldKickDrawerForSettlement(neg, drawerSettingOn: true), isFalse);
    });
  });
}
