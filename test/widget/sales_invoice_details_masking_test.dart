// AUTHZ-002 / AUTHZ-004 / AUTHZ-007 (audit 2026-10-23): the sales-invoice
// "View details" dialog must obey the same figure rule as the list:
//   figures = sales_view AND sales_amounts_view (system admin bypasses);
//   profit margin additionally needs products_cost_view or dashboard_profit.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/constants/app_constants.dart' hide InvoiceStatus;
import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/invoice_entity.dart';
import 'package:picpos_erp/presentation/widgets/sales_invoice_figures.dart';

InvoiceEntity _invoice() => InvoiceEntity(
      id: 1,
      invoiceNumber: 'S-1',
      type: InvoiceType.sale,
      lines: const [],
      invoiceDate: DateTime(2026, 1, 1),
      subtotal: 4321.11,
      discountAmount: 0,
      taxAmount: 0,
      total: 9876.54,
      paid: 1234.56,
      status: InvoiceStatus.partial,
    );

SalesInvoiceItemWithProduct _line() => db.SalesInvoiceItemWithProduct(
      item: const db.SalesInvoiceItem(
        id: 1,
        invoiceId: 1,
        productId: 5,
        quantity: 3,
        unitPrice: 777.77,
        total: 2333.31,
        discount: 0,
        costPrice: 0,
        sortOrder: 0,
        taxRate: 0,
        taxAmount: 0,
        unitName: 'قطعة',
        quantityInBase: 3,
        rowVersion: 1,
      ),
      product: null,
    );

void main() {
  Future<void> pump(WidgetTester tester, Widget w, List<String> perms) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))),
    ));
    await tester.pump();
    await tester.pump();
    // Ahem test font is wider than the real one: ignore layout overflow.
    while (tester.takeException() != null) {}
  }

  const secrets = ['9876.54', '1234.56', '4321.11', '777.77', '2333.31'];
  bool anySecret() => secrets.any((s) =>
      find.textContaining(s).evaluate().isNotEmpty);

  Widget body() => Column(children: [
        SalesInvoiceItemsTable(items: [InvoiceItemRow(name: _line().displayName, unit: _line().item.unitName, quantity: _line().item.quantity, unitPrice: _line().item.unitPrice, total: _line().item.total)]),
        SalesInvoiceTotalsBlock(invoice: _invoice()),
      ]);

  group('AUTHZ-002: details dialog money blocks', () {
    for (final perms in <List<String>>[
      const ['pos_access', 'sales_create'],
      const ['sales_view'], // AUTHZ-004
      const ['sales_amounts_view'],
    ]) {
      testWidgets('no amounts for $perms', (tester) async {
        await pump(tester, body(), perms);
        expect(anySecret(), isFalse);
        // quantities / names stay visible
        expect(find.text(3.toStringAsFixed(AppConstants.decimalPlaces)), findsOneWidget);
      });
    }

    testWidgets('sales_view + sales_amounts_view shows amounts',
        (tester) async {
      await pump(tester, body(), const ['sales_view', 'sales_amounts_view']);
      expect(find.textContaining('777.77'), findsOneWidget);
      expect(find.textContaining('9,876.54'), findsOneWidget);
    });

    testWidgets('system admin shows amounts', (tester) async {
      await pump(tester, body(), const ['system_admin']);
      expect(find.textContaining('777.77'), findsOneWidget);
    });
  });

  group('AUTHZ-007: profit margin', () {
    Widget gate() => const SalesInvoiceMarginGate(child: Text('MARGIN'));

    testWidgets('cashier (view + amounts, no cost/profit) sees no margin',
        (tester) async {
      await pump(tester, gate(), const ['sales_view', 'sales_amounts_view']);
      expect(find.text('MARGIN'), findsNothing);
    });

    testWidgets('cost-view alone (no sales figures) sees no margin',
        (tester) async {
      await pump(tester, gate(), const ['products_cost_view']);
      expect(find.text('MARGIN'), findsNothing);
    });

    testWidgets('figures + products_cost_view sees margin', (tester) async {
      await pump(tester, gate(),
          const ['sales_view', 'sales_amounts_view', 'products_cost_view']);
      expect(find.text('MARGIN'), findsOneWidget);
    });

    testWidgets('figures + dashboard_profit sees margin', (tester) async {
      await pump(tester, gate(),
          const ['sales_view', 'sales_amounts_view', 'dashboard_profit']);
      expect(find.text('MARGIN'), findsOneWidget);
    });
  });

  group('structural: dialogs route money through the gated widgets', () {
    final src = File(
            'lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart')
        .readAsStringSync();

    test('PicPos details dialog has no raw invoice money', () {
      expect(src.contains('SalesInvoiceTotalsBlock('), isTrue);
      expect(src.contains('SalesInvoiceItemsTable('), isTrue);
      expect(src.contains('SalesInvoiceMarginGate('), isTrue);
      for (final raw in ['invoice.subtotal', 'invoice.paid', 'invoice.discountAmount', 'item.item.unitPrice', 'item.item.total']) {
        expect(src.contains(raw), isFalse,
            reason: 'raw $raw in the details dialog bypasses the mask');
      }
    });
  });
}
