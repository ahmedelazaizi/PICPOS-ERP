// SPEC 102 — Credit sales must be visible in the shift closing print report.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shift closing print pipeline carries credit sales to thermal report', () {
    final controller =
        File('lib/presentation/pos/providers/pos_closing_controller.dart')
            .readAsStringSync();
    final invoiceGenerator =
        File('lib/services/invoice_generator.dart').readAsStringSync();
    final thermal =
        File('lib/services/printing/thermal_receipt_generator.dart')
            .readAsStringSync();

    expect(controller, contains('creditSales: state.creditIncome'));
    expect(controller, contains('creditSalesCount: state.creditCount'));

    expect(invoiceGenerator, contains('double creditSales = 0'));
    expect(invoiceGenerator, contains('int creditSalesCount = 0'));
    expect(invoiceGenerator, contains('creditSales: creditSales'));
    expect(invoiceGenerator, contains('creditSalesCount: creditSalesCount'));

    expect(thermal, contains('double creditSales = 0'));
    expect(thermal, contains('int creditSalesCount = 0'));
    expect(thermal, contains('المبيعات الآجلة'));
    expect(thermal, contains('creditSales.toStringAsFixed'));
  });
}
