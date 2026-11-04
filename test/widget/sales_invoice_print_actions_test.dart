// حوارُ تفاصيل فاتورة البيع يفرّق «طباعة الفاتورة» عن «طباعة المرتجع».
//
// الجولة الحيّة 2026-11-04: زرُّ «طباعة» الوحيد في تفاصيل SINV-7 المرتجَعة
// طبع الفاتورةَ الأصليّة. فالمقيسُ هنا: زرُّ المرتجع يظهر متى كان للفاتورة
// مرتجعٌ مرحَّل وحدَه، وزرُّ الفاتورة ينادي مسارَ الفاتورة لا غيره.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/invoice_entity.dart';
import 'package:picpos_erp/presentation/sales_invoices_picpos/screens/sales_invoice_print_actions.dart';

InvoiceEntity _invoice(int id, String number, InvoiceStatus status) =>
    InvoiceEntity(
      id: id,
      invoiceNumber: number,
      type: InvoiceType.sale,
      invoiceDate: DateTime(2026, 11, 3),
      lines: const [],
      subtotal: 6.99,
      total: 6.99,
      paid: 6.99,
      status: status,
    );

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  testWidgets('فاتورةٌ بلا مرتجع ⇒ زرُّ الفاتورة وحدَه', (tester) async {
    var invoicePrints = 0;
    await tester.pumpWidget(_host(SalesInvoicePrintActions(
      invoice: _invoice(8, 'SINV-6', InvoiceStatus.paid),
      returnedAmount: 0,
      onPrintInvoice: () => invoicePrints++,
    )));

    expect(find.byKey(const Key('sales_invoice_print_invoice')), findsOneWidget);
    expect(find.byKey(const Key('sales_invoice_print_return')), findsNothing);

    await tester.tap(find.byKey(const Key('sales_invoice_print_invoice')));
    expect(invoicePrints, 1);
  });

  testWidgets('فاتورةٌ مرتجَعة ⇒ زرّان منفصلان بتسميتين', (tester) async {
    var invoicePrints = 0;
    await tester.pumpWidget(_host(SalesInvoicePrintActions(
      invoice: _invoice(9, 'SINV-7', InvoiceStatus.returned),
      returnedAmount: 6.99,
      onPrintInvoice: () => invoicePrints++,
    )));

    final invoiceBtn = find.byKey(const Key('sales_invoice_print_invoice'));
    final returnBtn = find.byKey(const Key('sales_invoice_print_return'));
    expect(invoiceBtn, findsOneWidget);
    expect(returnBtn, findsOneWidget);
    expect(find.descendant(of: invoiceBtn, matching: find.text('طباعة الفاتورة')),
        findsOneWidget);
    expect(find.descendant(of: returnBtn, matching: find.text('طباعة المرتجع')),
        findsOneWidget);

    await tester.tap(invoiceBtn);
    expect(invoicePrints, 1, reason: 'زرُّ الفاتورة لا يطبع المرتجع');
  });
}
