// S-03 — pure rules of the server price/discount guard.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/services/api/server_price_discount_guard.dart';

void main() {
  const product = GuardProduct(
    costPrice: 60,
    basePrices: [100, 90, 0, 0, 0],
    unitPrices: [1100],
  );
  const policy = GuardPolicy(capPercent: 15);

  GuardLine line({
    double price = 100,
    double discount = 0,
    double qty = 1,
    double inBase = 1,
  }) =>
      GuardLine(
        productId: 1,
        quantity: qty,
        unitPrice: price,
        discountPercent: discount,
        quantityInBase: inBase,
      );

  List<GuardViolation> run(
    List<GuardLine> lines, {
    Set<String> perms = const {},
    GuardPolicy pol = policy,
    double header = 0,
    bool isReturn = false,
    bool hasInvoice = true,
    bool strict = false,
  }) =>
      evaluateSalePriceDiscount(
        lines: lines,
        products: {1: product},
        permissions: perms,
        policy: pol,
        headerDiscount: header,
        isReturn: isReturn,
        hasInvoice: hasInvoice,
        strictCatalogPrice: strict,
      );

  group('sale lines', () {
    test('ordinary cashier sale at catalog price, discount within cap passes', () {
      expect(run([line(discount: 15)], header: 15), isEmpty);
    });

    test('other price levels, sub-unit price and rounding tolerance pass', () {
      expect(run([line(price: 90)], strict: true), isEmpty);
      expect(run([line(price: 1100, inBase: 12)], strict: true), isEmpty);
      expect(run([line(price: 1200, inBase: 12)], strict: true), isEmpty);
      expect(run([line(price: 100.01)], strict: true), isEmpty);
    });

    test('strict: off-catalog price needs pos_price_edit', () {
      final v = run([line(price: 80)], strict: true);
      expect(v.single.kind, GuardViolationKind.priceNotCatalog);
      expect(v.single.requiredPermission, PermissionCodes.posPriceEdit);
      expect(
          run([line(price: 80)],
              strict: true, perms: {PermissionCodes.posPriceEdit}),
          isEmpty);
    });

    test('relaxed (handler mode): offer price above cost passes, below cost is refused',
        () {
      expect(run([line(price: 75)]), isEmpty);
      final v = run([line(price: 50)]);
      expect(v.single.kind, GuardViolationKind.priceBelowCost);
      expect(
          run([line(price: 50)], perms: {PermissionCodes.posPriceEdit}), isEmpty);
    });

    test('cost is scaled by the sale unit factor', () {
      // carton of 12 costs 720: 700 is below cost although 700 > 60.
      expect(run([line(price: 700, inBase: 12)]).single.kind,
          GuardViolationKind.priceBelowCost);
    });

    test('unknown product is skipped, not rejected', () {
      expect(
        evaluateSalePriceDiscount(
          lines: [line(price: 1)],
          products: const {},
          permissions: const {},
          policy: policy,
          headerDiscount: 0,
        ),
        isEmpty,
      );
    });
  });

  group('discounts', () {
    test('line discount above the cap is refused; equality passes', () {
      expect(run([line(discount: 15)], header: 15), isEmpty);
      final v = run([line(discount: 40)], header: 40);
      expect(v.map((e) => e.kind),
          contains(GuardViolationKind.lineDiscountOverCap));
      expect(v.first.requiredPermission, PermissionCodes.posDiscount);
    });

    test('invoice-level discount is judged on the base after line discounts', () {
      // 10% line (10) + 10 invoice discount on a base of 90 = 11.1% → ok.
      expect(run([line(discount: 10)], header: 20), isEmpty);
      // header 60 on a gross of 100 → 60% invoice discount.
      final v = run([line()], header: 60);
      expect(v.single.kind, GuardViolationKind.invoiceDiscountOverCap);
    });

    test("user's own percent limit replaces the global cap", () {
      const pol = GuardPolicy(capPercent: 15, userMaxDiscount: 30);
      expect(run([line(discount: 25)], pol: pol, header: 25), isEmpty);
      expect(run([line(discount: 35)], pol: pol, header: 35), isNotEmpty);
    });

    test("user's amount limit applies to the total discount", () {
      const pol = GuardPolicy(
          capPercent: 50, userMaxDiscount: 10, userLimitIsPercent: false);
      expect(run([line()], pol: pol, header: 10), isEmpty);
      expect(run([line()], pol: pol, header: 12), isNotEmpty);
    });

    test('discounts are not judged on returns', () {
      expect(run([line(discount: 90)], isReturn: true, header: 90), isEmpty);
    });
  });

  group('returns', () {
    test('with an original invoice: any price passes', () {
      expect(run([line(price: 500)], isReturn: true), isEmpty);
    });

    test('without invoice: off-catalog price needs pos_return_price_edit', () {
      final v = run([line(price: 500)], isReturn: true, hasInvoice: false);
      expect(v.single.kind, GuardViolationKind.returnPriceNotCatalog);
      expect(v.single.requiredPermission, PermissionCodes.posReturnPriceEdit);
      // pos_price_edit is NOT a substitute.
      expect(
          run([line(price: 500)],
              isReturn: true,
              hasInvoice: false,
              perms: {PermissionCodes.posPriceEdit}),
          isNotEmpty);
      expect(
          run([line(price: 500)],
              isReturn: true,
              hasInvoice: false,
              perms: {PermissionCodes.posReturnPriceEdit}),
          isEmpty);
    });

    test('without invoice: catalog price passes', () {
      expect(
          run([line(price: 100)], isReturn: true, hasInvoice: false), isEmpty);
    });
  });
}
