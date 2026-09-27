import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart';

void main() {
  testWidgets('SalesInvoicesPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const SalesInvoicesPicposScreen(), isA<Widget>());
  });
}
