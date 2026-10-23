// B3 (owner decision) — an item marked «معفى من الضريبة» is taxed at 0 %
// everywhere. One rule (`effectiveItemTaxRate`) feeds every pure engine;
// non-exempt items must compute exactly as before.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/tax/effective_item_tax_rate.dart';
import 'package:picpos_erp/core/tax/einvoice_exempt_codes.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/models/picpos_invoice_draft.dart';
import 'package:picpos_erp/domain/models/table_order_totals.dart';
import 'package:picpos_erp/domain/usecases/sales/add_to_cart_usecase.dart';
import 'package:picpos_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';

CartItemEntity _line({
  required int id,
  double rate = 0,
  bool exempt = false,
  double price = 100,
}) =>
    CartItemEntity(
      productId: id,
      productName: 'p$id',
      productCode: 'c$id',
      quantity: 1,
      unitPrice: price,
      taxRate: rate,
      taxExempt: exempt,
    );

void main() {
  group('effectiveItemTaxRate', () {
    test('exempt → 0 whatever the item rate or company default', () {
      expect(effectiveItemTaxRate(rate: 0, exempt: true, companyDefault: 14),
          0);
      expect(effectiveItemTaxRate(rate: 16, exempt: true, companyDefault: 14),
          0);
    });

    test('default item (rate 0, not exempt) → company default', () {
      expect(effectiveItemTaxRate(rate: 0, exempt: false, companyDefault: 14),
          14);
    });

    test('custom rate wins over the company default', () {
      expect(effectiveItemTaxRate(rate: 16, exempt: false, companyDefault: 14),
          16);
    });

    test('paths without a company default (companyDefault: 0) keep the item '
        'rate as-is', () {
      expect(effectiveItemTaxRate(rate: 0, exempt: false, companyDefault: 0),
          0);
      expect(effectiveItemTaxRate(rate: 5, exempt: false, companyDefault: 0),
          5);
    });
  });

  group('CalculateInvoiceTotalsUseCase', () {
    final uc = CalculateInvoiceTotalsUseCase();

    test('exempt line adds no tax; default and custom lines unchanged', () {
      final t = uc.execute(
        items: [
          _line(id: 1, exempt: true),
          _line(id: 2),
          _line(id: 3, rate: 16),
        ],
        taxPercent: 14,
      );
      // 0 + 14 + 16
      expect(t.taxAmount, closeTo(30, 0.001));
      expect(t.total, closeTo(330, 0.001));
    });

    test('regression: no exempt flag → identical to the old fallback rule',
        () {
      final t = uc.execute(
        items: [_line(id: 2), _line(id: 3, rate: 16)],
        taxPercent: 14,
      );
      expect(t.taxAmount, closeTo(30, 0.001));
      expect(t.total, closeTo(230, 0.001));
    });
  });

  group('cart helpers', () {
    test('AddToCartUseCase stores an exempt line at rate 0 / tax 0', () {
      final cart = AddToCartUseCase().execute(
        currentCart: const [],
        productId: 1,
        productName: 'p',
        productCode: 'c',
        unitPrice: 100,
        taxRate: 16,
        taxExempt: true,
      );
      expect(cart.single.taxExempt, isTrue);
      expect(cart.single.taxRate, 0);
      expect(cart.single.taxAmount, 0);
      expect(cart.single.calculatedTaxAmount, 0);
    });

    test('applyTaxExemptProductIds flags only the listed products', () {
      final out = applyTaxExemptProductIds(
        [_line(id: 1, rate: 16), _line(id: 2, rate: 16)],
        {1},
      );
      expect(out[0].taxExempt, isTrue);
      expect(out[0].taxRate, 0);
      expect(out[1].taxExempt, isFalse);
      expect(out[1].taxRate, 16);
    });

    test('empty exempt set returns the same list instance', () {
      final items = [_line(id: 1)];
      expect(identical(applyTaxExemptProductIds(items, {}), items), isTrue);
    });
  });

  group('TableOrderTotals', () {
    test('exempt line falls OUT of the order rate; others fall back to it',
        () {
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 1, unitPrice: 100, taxExempt: true),
          TableOrderLine(quantity: 1, unitPrice: 100),
          TableOrderLine(quantity: 1, unitPrice: 100, taxRate: 16),
        ],
        taxEnabled: true,
        taxPercent: 14,
      );
      expect(t.taxAmount, closeTo(30, 0.001));
      expect(t.total, closeTo(330, 0.001));
      expect(t.lineTotals.first, closeTo(100, 0.001));
    });
  });

  group('PicPos invoice line', () {
    test('exempt option carries the flag; the line taxes nothing', () {
      const p = PicPosProductOption(
        id: 1,
        name: 'n',
        salePrice: 100,
        costPrice: 50,
        taxExempt: true,
      );
      final rate = effectiveItemTaxRate(
          rate: p.taxRate, exempt: p.taxExempt, companyDefault: 14);
      final line = PicPosInvoiceLine(
        productId: p.id,
        productName: p.name,
        quantity: 1,
        unitPrice: 100,
        taxRate: rate,
        taxEnabled: rate > 0,
      );
      expect(line.taxAmount, 0);
    });
  });

  group('e-invoice exempt classification', () {
    test('exempt product with a tax-free line → exempt', () {
      expect(isExemptEInvoiceLine(productExempt: true, lineTaxAmount: 0),
          isTrue);
    });

    test('historical taxed line keeps its classification', () {
      expect(isExemptEInvoiceLine(productExempt: true, lineTaxAmount: 14),
          isFalse);
    });

    test('non-exempt product never classified exempt', () {
      expect(isExemptEInvoiceLine(productExempt: false, lineTaxAmount: 0),
          isFalse);
    });

    test('codes: ETA V003 (exempt goods), JoFotara E', () {
      expect(kEtaExemptTaxSubtype, 'V003');
      expect(kJofotaraExemptTaxCategory, 'E');
    });
  });
}
