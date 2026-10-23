// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — E-02 · sales-invoices form DISPLAY must equal the SAVED total
// ═══════════════════════════════════════════════════════════════════════════
//
// Root cause: SalesInvoicesFormState.grandTotal used
//     subtotal - discount + calculatedTax
// where calculatedTax = Σ(line tax on the line net after the LINE discount
// only). The invoice-level `discount` was subtracted from the grand total but
// NEVER reduced the VAT base, so the DISPLAYED tax/total were computed on a
// higher base than the SAVED tax/total. The save path
// (completeSalesTransaction / CalculateInvoiceTotalsUseCase) applies the
// invoice discount to the tax base (net-base VAT), so the cashier saw/collected
// a higher amount than the system recorded.
//
// Worked example (the finding's): one line price 1000 qty 1, no line discount,
// tax 14% enabled, invoice discount 100.
//   • BEFORE fix (buggy display): tax = 1000×0.14 = 140; total = 1000-100+140 = 1040.
//   • AFTER fix (net-base, == saved): net = (1000-100)=900; tax = 900×0.14 = 126;
//     total = 900+126 = 1026.
//
// Invariant locked: the form getters run through the SAME engine as the save
// path, so grandTotal/calculatedTax == CalculateInvoiceTotalsUseCase for the
// same inputs. These assertions FAIL on the pre-fix code (1040 / 140).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'package:picpos_erp/presentation/screens/sales_invoices/sales_invoices_notifier.dart';

void main() {
  group('E-02 — sales-invoices form display is net-base (display == saved)', () {
    test(
        'line 1000, no line discount, tax 14%, invoice discount 100 → '
        'grandTotal == 1026 and calculatedTax == 126 (NOT 1040 / 140)', () {
      final state = SalesInvoicesFormState(
        cart: [
          SalesCartItem(
            productId: 1,
            productName: 'منتج E02',
            productCode: 'E02-01',
            quantity: 1,
            unitPrice: 1000,
            taxRate: 14,
            taxEnabled: true,
          ),
        ],
        discount: 100,
      );

      // The invoice-level discount reduces the VAT base (net-base VAT).
      expect(state.calculatedTax, closeTo(126.0, 0.001),
          reason: 'tax must be on the net after the invoice discount '
              '(900 × 14% = 126), not the pre-discount 140');
      expect(state.grandTotal, closeTo(1026.0, 0.001),
          reason: 'total must be net + net-base tax (900 + 126 = 1026), '
              'not 1000 - 100 + 140 = 1040');
    });

    test('form getters match CalculateInvoiceTotalsUseCase for the same inputs',
        () {
      final state = SalesInvoicesFormState(
        cart: [
          SalesCartItem(
            productId: 1,
            productName: 'منتج E02',
            productCode: 'E02-01',
            quantity: 1,
            unitPrice: 1000,
            taxRate: 14,
            taxEnabled: true,
          ),
        ],
        discount: 100,
      );

      // Same inputs, run directly through the authoritative save-path engine.
      final expected = CalculateInvoiceTotalsUseCase().execute(
        items: const [
          CartItemEntity(
            productId: 1,
            productName: 'منتج E02',
            productCode: 'E02-01',
            quantity: 1,
            unitPrice: 1000,
            taxRate: 14,
          ),
        ],
        invoiceDiscountPercent: 10, // 100 / 1000 × 100
        taxPercent: 0,
        taxEnabled: true,
      );

      expect(state.calculatedTax, closeTo(expected.taxAmount, 0.001));
      expect(state.grandTotal, closeTo(expected.total, 0.001));
      // Sanity: the authoritative engine really produces the net-base numbers.
      expect(expected.taxAmount, closeTo(126.0, 0.001));
      expect(expected.total, closeTo(1026.0, 0.001));
    });

    test(
        'exempt line (taxEnabled=false) + invoice discount → zero VAT, '
        'total = net only (no phantom tax)', () {
      final state = SalesInvoicesFormState(
        cart: [
          SalesCartItem(
            productId: 2,
            productName: 'منتج معفى',
            productCode: 'E02-02',
            quantity: 1,
            unitPrice: 1000,
            taxRate: 14, // product rate present, but the line is toggled exempt
            taxEnabled: false,
          ),
        ],
        discount: 100,
      );

      expect(state.calculatedTax, closeTo(0.0, 0.001),
          reason: 'an exempt line must contribute zero VAT even with a rate set');
      expect(state.grandTotal, closeTo(900.0, 0.001),
          reason: 'net after the invoice discount, no tax: 1000 - 100 = 900');
    });
  });
}
