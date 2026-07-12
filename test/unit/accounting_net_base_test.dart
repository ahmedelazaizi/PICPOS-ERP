import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/financial_utils.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'package:ural_erp/services/costing_method_service.dart';

/// Spec 137 — accounting tier (BUG-C02, BUG-H01, BUG-M07, BUG-M04, BUG-L03).
///
/// Policy (owner-confirmed 2026-06-25): VAT is computed on the NET base after
/// BOTH line-level and invoice-level discounts, and the POS tax toggle
/// (taxEnabled=false / taxPercent=0) must produce ZERO tax — even when a line
/// carries a per-product taxRate.
void main() {
  group('CalculateInvoiceTotalsUseCase — net-base tax (C02/H01)', () {
    final useCase = CalculateInvoiceTotalsUseCase();

    test('BUG-C02: per-line taxed item with tax disabled => zero tax', () {
      // qty 10 @ 10 = 100; product carries 16% VAT but the cashier turned tax
      // off, so the cart-level taxPercent passed in is 0.
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'سلعة',
          productCode: 'P1',
          quantity: 10,
          unitPrice: 10.0,
          taxRate: 16,
        ),
      ];

      final r = useCase.execute(items: items, taxPercent: 0, taxEnabled: false);

      expect(r.taxAmount, 0.0);
      expect(r.total, 100.0);
    });

    test('BUG-H01: per-line tax recomputed on net AFTER invoice discount', () {
      // qty 10 @ 100 = 1000, 10% line product tax, 10% invoice discount.
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'سلعة',
          productCode: 'P1',
          quantity: 10,
          unitPrice: 100.0,
          taxRate: 10,
        ),
      ];

      final r = useCase.execute(
        items: items,
        invoiceDiscountPercent: 10,
        taxEnabled: true,
      );

      expect(r.subtotal, 1000.0);
      expect(r.invoiceDiscount, closeTo(100.0, 0.001)); // 10% of 1000
      // tax on net 900, not on pre-discount 1000
      expect(r.taxAmount, closeTo(90.0, 0.001));
      expect(r.total, closeTo(990.0, 0.001));
    });

    test('per-line rates preserved: one exempt + one taxed, with invoice discount', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'معفى',
          productCode: 'P1',
          quantity: 1,
          unitPrice: 100.0,
          taxRate: 0, // exempt
        ),
        const CartItemEntity(
          productId: 2,
          productName: 'خاضع',
          productCode: 'P2',
          quantity: 1,
          unitPrice: 100.0,
          taxRate: 10,
        ),
      ];

      // subtotal 200, 50% invoice discount => net 100, each line net 50.
      final r = useCase.execute(
        items: items,
        invoiceDiscountPercent: 50,
        taxEnabled: true,
      );

      expect(r.subtotal, 200.0);
      expect(r.invoiceDiscount, closeTo(100.0, 0.001));
      // only the taxed line: 50 * 10% = 5 ; exempt line contributes 0
      expect(r.taxAmount, closeTo(5.0, 0.001));
      expect(r.total, closeTo(105.0, 0.001));
    });

    test('per-line net-base tax decomposition sums to the header tax (P2: SUM(lines)==header)', () {
      // Mixed rates + line discount + invoice discount. The orchestrator saves
      // per-line taxAmount on sales_invoice_items using the SAME two-pass
      // formula; this pins that the per-line decomposition sums exactly to the
      // invoice-header taxAmount, so line-level VAT reports reconcile.
      const a = CartItemEntity(
        productId: 1, productName: 'A', productCode: 'A',
        quantity: 1, unitPrice: 100.0, taxRate: 16, discountPercent: 10,
      );
      const b = CartItemEntity(
        productId: 2, productName: 'B', productCode: 'B',
        quantity: 1, unitPrice: 100.0, taxRate: 5, discountPercent: 10,
      );
      final r = useCase.execute(
        items: [a, b],
        invoiceDiscountPercent: 7,
        taxEnabled: true,
      );

      // Replicate the orchestrator two-pass per line (same formula).
      double round(double v) => (v * 1000).roundToDouble() / 1000;
      const afterItemDiscounts = (100 - 10) + (100 - 10); // 180
      final invoiceDiscount = round(afterItemDiscounts * 0.07); // 12.6
      final ratio = (afterItemDiscounts - invoiceDiscount) / afterItemDiscounts;
      final taxA = round((100 - 10) * ratio * 0.16);
      final taxB = round((100 - 10) * ratio * 0.05);

      expect(round(taxA + taxB), closeTo(r.taxAmount, 0.0005));
    });

    test('BUG-L03: changeFor/remainingFor are rounded to 3dp', () {
      final items = [
        const CartItemEntity(
          productId: 1,
          productName: 'سلعة',
          productCode: 'P1',
          quantity: 1,
          unitPrice: 100.0,
        ),
      ];
      final r = useCase.execute(items: items); // total 100

      expect(r.changeFor(100.0001), 0.0);
      expect(r.remainingFor(99.9999), 0.0);
    });
  });

  group('Sales-invoice form discount reaches the save path (P1)', () {
    test('absolute global discount reproduces the displayed total when saved', () {
      // The commercial sales-invoice form shows an ABSOLUTE discount via
      // FinancialUtils.calculateInvoiceTotals; the save path (orchestrator /
      // CalculateInvoiceTotalsUseCase) takes a PERCENT. Converting amount->percent
      // at full precision must reproduce the same grand total (display == saved).
      const items = [
        CartItemEntity(
          productId: 1, productName: 'A', productCode: 'A',
          quantity: 2, unitPrice: 100.0, taxRate: 16,
        ),
      ];
      const discount = 30.0; // absolute amount entered in the form
      const subtotal = 200.0;

      final form = FinancialUtils.calculateInvoiceTotals(
        items: const [(quantity: 2.0, unitPrice: 100.0, taxRatePercent: 16.0)],
        globalDiscountAmount: discount,
      );

      const discountPercent = subtotal > 0 ? (discount / subtotal * 100) : 0.0;
      final saved = CalculateInvoiceTotalsUseCase().execute(
        items: items,
        invoiceDiscountPercent: discountPercent,
        taxEnabled: true,
      );

      expect(saved.total, closeTo(form.grandTotal, 0.001));
      // and the discount is actually applied (not dropped to the undiscounted total)
      expect(saved.total, lessThan(232.0));
    });
  });

  group('FinancialUtils.calculateInvoiceTotals — net-base tax (M07)', () {
    test('BUG-M07: global discount applied BEFORE tax', () {
      final r = FinancialUtils.calculateInvoiceTotals(
        items: const [
          (quantity: 10.0, unitPrice: 100.0, taxRatePercent: 10.0),
        ],
        globalDiscountAmount: 100.0, // 10% of 1000
      );

      expect(r.subtotal, 1000.0);
      expect(r.totalTax, closeTo(90.0, 0.001)); // tax on net 900
      expect(r.grandTotal, closeTo(990.0, 0.001));
    });
  });

  group('CostingMethodService — WAC rounding (M04)', () {
    test('BUG-M04: weighted-average cost is rounded to 3dp', () {
      // (3*1.0 + 1*1.001) / 4 = 4.001/4 = 1.00025 -> 1.000 at 3dp
      final wac = CostingMethodService.calculateCost(
        method: CostingMethod.weightedAverage,
        currentStock: 3,
        currentCost: 1.0,
        purchaseQty: 1,
        purchaseUnitCost: 1.001,
      );

      expect(wac, 1.0);
    });
  });
}
