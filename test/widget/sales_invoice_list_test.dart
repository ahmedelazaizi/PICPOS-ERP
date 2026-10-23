// ═══════════════════════════════════════════════════════════════════════════
// Day 10 — Sales Invoice List Widget Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests invoice list rendering through a lightweight test widget that
// accepts a List<InvoiceEntity> and a search query — no Riverpod or DB
// providers needed. Verifies: count display, search filtering, and empty
// state rendering.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/invoice_entity.dart';

// ── Test-double invoice list widget ──────────────────────────────────────

class _InvoiceListView extends StatelessWidget {
  final List<InvoiceEntity> invoices;
  final String searchQuery;

  const _InvoiceListView({
    required this.invoices,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final filtered = searchQuery.isEmpty
        ? invoices
        : invoices
            .where((inv) => inv.invoiceNumber
                .toLowerCase()
                .contains(searchQuery.toLowerCase()))
            .toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد فواتير',
          key: Key('empty_state'),
        ),
      );
    }

    return Column(
      children: [
        Text(
          'عدد الفواتير: ${filtered.length}',
          key: const Key('invoice_count'),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) => ListTile(
              key: Key('invoice_${filtered[i].invoiceNumber}'),
              title: Text(filtered[i].invoiceNumber),
              subtitle: Text(
                  '${filtered[i].total.toStringAsFixed(2)} ${filtered[i].paymentMethod ?? ''}'),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Factory for test invoices ─────────────────────────────────────────────

InvoiceEntity _makeInvoice(String number, double total) => InvoiceEntity(
      invoiceNumber: number,
      type: InvoiceType.sale,
      invoiceDate: DateTime(2026, 4, 1),
      lines: const [],
      subtotal: total,
      total: total,
      paid: total,
      status: InvoiceStatus.paid,
      paymentMethod: 'cash',
    );

List<InvoiceEntity> _makeInvoices(int count) =>
    List.generate(count, (i) => _makeInvoice('INV-${i + 1}', (i + 1) * 10.0));

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  Widget buildApp(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  group('Day 10 — Sales Invoice List Widget Tests', () {
    // ── Test 8: list renders the correct count of invoices ────────────────
    testWidgets('قائمة الفواتير تعرض 20 فاتورة بشكل صحيح', (tester) async {
      final invoices = _makeInvoices(20);

      await tester.pumpWidget(buildApp(
        _InvoiceListView(invoices: invoices),
      ));
      await tester.pump();

      expect(find.byKey(const Key('invoice_count')), findsOneWidget);
      expect(find.text('عدد الفواتير: 20'), findsOneWidget);
      // Scroll is lazy — just verify first item is visible
      expect(find.byKey(const Key('invoice_INV-1')), findsOneWidget);
    });

    // ── Test 9: search by number returns the correct single result ────────
    testWidgets('بحث برقم الفاتورة يُرجع نتيجة صحيحة', (tester) async {
      final invoices = _makeInvoices(20);

      await tester.pumpWidget(buildApp(
        const _InvoiceListView(
          invoices: [
            // Inline since const needed — use builder-less approach
          ],
        ),
      ));

      // Use non-const approach with search
      await tester.pumpWidget(buildApp(
        _InvoiceListView(invoices: invoices, searchQuery: 'INV-5'),
      ));
      await tester.pump();

      expect(find.text('عدد الفواتير: 1'), findsOneWidget);
      expect(find.byKey(const Key('invoice_INV-5')), findsOneWidget);
      // Other invoices should not appear
      expect(find.byKey(const Key('invoice_INV-1')), findsNothing);
    });

    // ── Test 10: empty invoice list shows empty state ─────────────────────
    testWidgets('قائمة فواتير فارغة تُظهر رسالة الحالة الفارغة',
        (tester) async {
      await tester.pumpWidget(buildApp(
        const _InvoiceListView(invoices: []),
      ));
      await tester.pump();

      expect(find.byKey(const Key('empty_state')), findsOneWidget);
      expect(find.text('لا توجد فواتير'), findsOneWidget);
      expect(find.byKey(const Key('invoice_count')), findsNothing);
    });
  });
}
