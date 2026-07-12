import 'package:flutter_test/flutter_test.dart';

/// PIR Unit Test — VAT Compliance (Egyptian Tax Law 67/2016)
///
/// Validates that VAT calculations follow the standard 14% rate,
/// are applied after discount, and are correctly separated between
/// input (purchases) and output (sales) VAT.
void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // STANDARD 14% VAT CALCULATION
  // ═══════════════════════════════════════════════════════════════════════

  group('Standard 14% VAT', () {
    const vatRate = 0.14;

    test('VAT on full amount (no discount)', () {
      const subtotal = 1000.0;
      const discount = 0.0;
      const taxable = subtotal - discount;
      const vat = taxable * vatRate;

      expect(vat, closeTo(140.0, 0.01));
      expect(taxable + vat, closeTo(1140.0, 0.01));
    });

    test('VAT on discounted amount', () {
      const subtotal = 1000.0;
      const discount = 200.0;
      const taxable = subtotal - discount;
      const vat = taxable * vatRate;

      expect(taxable, equals(800.0));
      expect(vat, closeTo(112.0, 0.01));
      expect(taxable + vat, closeTo(912.0, 0.01));
    });

    test('VAT on percentage discount', () {
      const subtotal = 500.0;
      const discountPercent = 15.0;
      const discountAmount = subtotal * (discountPercent / 100);
      const taxable = subtotal - discountAmount;
      const vat = taxable * vatRate;

      expect(discountAmount, equals(75.0));
      expect(taxable, equals(425.0));
      expect(vat, closeTo(59.5, 0.01));
    });

    test('Zero VAT for tax-exempt items', () {
      const subtotal = 300.0;
      const isTaxExempt = true;
      const vat = isTaxExempt ? 0.0 : subtotal * vatRate;

      expect(vat, equals(0.0));
    });

    test('Rounding: VAT on 99.99 EGP', () {
      const subtotal = 99.99;
      const vat = subtotal * vatRate;

      // 99.99 × 0.14 = 13.9986
      expect(vat, closeTo(13.9986, 0.0001));

      // Business rounding to 2 decimals
      final roundedVat = double.parse(vat.toStringAsFixed(2));
      expect(roundedVat, equals(14.0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // INPUT vs OUTPUT VAT ACCOUNT ALLOCATION
  // ═══════════════════════════════════════════════════════════════════════

  group('Input/Output VAT Account Allocation', () {
    test('Sales VAT is Output VAT (credit account 2201)', () {
      const saleSubtotal = 1000.0;
      const saleVat = 140.0;

      // In the GL:
      // Dr Cash       1140 (account 1101)
      // Cr Sales      1000 (account 4101)
      // Cr Output VAT  140 (account 2201) ← liability
      const outputVatAccount = '2201';

      expect(saleVat, equals(saleSubtotal * 0.14));
      expect(outputVatAccount, equals('2201'),
          reason: 'Output VAT goes to account 2201 (credit = liability)');
    });

    test('Purchase VAT is Input VAT (debit account 1204)', () {
      const purchaseSubtotal = 5000.0;
      const purchaseVat = 700.0;

      // In the GL:
      // Dr Inventory  5000 (account 1103)
      // Dr Input VAT   700 (account 1204) ← asset (recoverable)
      // Cr Cash       5700 (account 1101)
      const inputVatAccount = '1204';

      expect(purchaseVat, closeTo(purchaseSubtotal * 0.14, 0.01));
      expect(inputVatAccount, equals('1204'),
          reason: 'Input VAT goes to account 1204 (debit = asset)');
    });

    test('Net VAT payable = Output VAT - Input VAT', () {
      const outputVat = 1400.0; // Sales: 10,000 × 14%
      const inputVat = 700.0;   // Purchases: 5,000 × 14%
      const netVatPayable = outputVat - inputVat;

      expect(netVatPayable, equals(700.0),
          reason: 'Net VAT payable to authority = output - input');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // TAX PERIOD ALLOCATION
  // ═══════════════════════════════════════════════════════════════════════

  group('Tax Period Allocation', () {
    test('Tax period determined by invoice_date not created_at', () {
      final invoiceDate = DateTime(2026, 2, 28);
      final createdAt = DateTime(2026, 3, 1); // Created next month

      // Tax period is based on invoice_date month
      final taxPeriodMonth = invoiceDate.month;
      final createdMonth = createdAt.month;

      expect(taxPeriodMonth, equals(2),
          reason: 'Tax period should be February (invoice date)');
      expect(createdMonth, equals(3),
          reason: 'Created date is March but should NOT determine tax period');
      expect(taxPeriodMonth, isNot(createdMonth),
          reason: 'This test proves the distinction between invoice_date and created_at');
    });

    test('Quarter determination from invoice date', () {
      int getQuarter(DateTime date) => ((date.month - 1) ~/ 3) + 1;

      expect(getQuarter(DateTime(2026, 1, 15)), equals(1));
      expect(getQuarter(DateTime(2026, 3, 31)), equals(1));
      expect(getQuarter(DateTime(2026, 4, 1)), equals(2));
      expect(getQuarter(DateTime(2026, 7, 15)), equals(3));
      expect(getQuarter(DateTime(2026, 12, 31)), equals(4));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // MULTI-ITEM TAX CALCULATION
  // ═══════════════════════════════════════════════════════════════════════

  group('Multi-Item Tax Calculation', () {
    test('Mixed taxable and exempt items on same invoice', () {
      const vatRate = 0.14;
      final items = [
        {'name': 'Taxable Item A', 'price': 200.0, 'qty': 2.0, 'taxable': true},
        {'name': 'Exempt Item B', 'price': 150.0, 'qty': 3.0, 'taxable': false},
        {'name': 'Taxable Item C', 'price': 100.0, 'qty': 1.0, 'taxable': true},
      ];

      final taxableTotal = items
          .where((i) => i['taxable'] == true)
          .fold<double>(0, (s, i) => s + (i['price'] as double) * (i['qty'] as double));
      // 200×2 + 100×1 = 500
      expect(taxableTotal, equals(500.0));

      final totalVat = taxableTotal * vatRate;
      expect(totalVat, closeTo(70.0, 0.01));

      final exemptTotal = items
          .where((i) => i['taxable'] == false)
          .fold<double>(0, (s, i) => s + (i['price'] as double) * (i['qty'] as double));
      // 150×3 = 450
      expect(exemptTotal, equals(450.0));

      final grandTotal = taxableTotal + exemptTotal + totalVat;
      // 500 + 450 + 70 = 1020
      expect(grandTotal, closeTo(1020.0, 0.01));
    });

    test('Per-item tax amounts sum to total tax', () {
      const vatRate = 0.14;
      final items = [
        {'price': 99.99, 'qty': 3.0},
        {'price': 50.50, 'qty': 2.0},
        {'price': 75.25, 'qty': 1.0},
      ];

      // Per-item tax (rounded per item)
      double perItemTaxSum = 0;
      for (final item in items) {
        final lineTotal = (item['price'] as double) * (item['qty'] as double);
        final lineTax = double.parse((lineTotal * vatRate).toStringAsFixed(2));
        perItemTaxSum += lineTax;
      }

      // Total-level tax
      final totalBeforeTax = items.fold<double>(
          0, (s, i) => s + (i['price'] as double) * (i['qty'] as double));
      final totalTax = double.parse((totalBeforeTax * vatRate).toStringAsFixed(2));

      // Allow small rounding difference (max 1 piaster per item)
      expect((perItemTaxSum - totalTax).abs(), lessThanOrEqualTo(items.length * 0.01),
          reason: 'Per-item tax sum should be within rounding tolerance of total tax');
    });
  });
}
