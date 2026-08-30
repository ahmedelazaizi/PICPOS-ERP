import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/presentation/pos/widgets/pos_edit_invoice_dialog.dart';

/// `PosEditInvoiceDialog` must open for EVERY payment method the POS can write.
///
/// ── The bug this pins ────────────────────────────────────────────────────
/// `DropdownButtonFormField` asserts its value is among its items. The method
/// map held only {cash, transfer, credit, multiple}, while the checkout dialog
/// writes `card`, `click` and `mixed` — so the pencil icon in the previous-
/// invoices dialog threw for every bank and split sale, on BOTH tills. That is
/// why this is a shared fix, not a PicPos feature.
void main() {
  SalesInvoiceData invoiceWith(String paymentMethod) => SalesInvoiceData(
        id: 1,
        invoiceNumber: 'POS-1',
        warehouseId: 1,
        userId: 1,
        invoiceDate: DateTime(2026, 1, 1),
        subtotal: 100,
        discount: 0,
        tax: 0,
        total: 100,
        paid: 100,
        roundingAdjustment: 0,
        cashPaid: paymentMethod == 'cash' ? 100 : 0,
        bankPaid: paymentMethod == 'card' || paymentMethod == 'transfer'
            ? 100
            : 0,
        clickPaid: paymentMethod == 'click' ? 100 : 0,
        paymentMethod: paymentMethod,
        saleType: 'default',
        status: 'completed',
        deliveryFee: 0,
        isLocked: true,
        isDeleted: false,
        updatedAt: DateTime(2026, 1, 1),
        rowVersion: 1,
        createdAt: DateTime(2026, 1, 1),
      );

  Future<void> pump(WidgetTester tester, String paymentMethod) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PosEditInvoiceDialog(invoice: invoiceWith(paymentMethod)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Every value the app can actually store, plus garbage.
  const methods = [
    'cash',
    'card',
    'transfer',
    'click',
    'credit',
    'multiple',
    'mixed',
    'bank',
    'something-unmapped',
  ];

  for (final method in methods) {
    testWidgets('opens without asserting for paymentMethod="$method"',
        (tester) async {
      await pump(tester, method);

      expect(tester.takeException(), isNull,
          reason: 'the dropdown must be able to render its own value');
      expect(find.text('تعديل فاتورة #POS-1'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  }

  testWidgets('preselects بطاقة for a card invoice', (tester) async {
    await pump(tester, 'card');
    expect(find.text('بطاقة (بنك)'), findsWidgets);
  });

  testWidgets('normalises the stored "mixed" spelling to متعدد',
      (tester) async {
    // The checkout dialog maps its 'multiple' chip to 'mixed' before saving.
    // Both spellings are understood downstream, so the dropdown normalises
    // rather than adding a second synonymous entry.
    await pump(tester, 'mixed');
    expect(find.text('متعدد'), findsWidgets);
  });

  testWidgets('shows an unknown stored value rather than hiding it',
      (tester) async {
    // Surfacing the raw string tells whoever files the bug what the column
    // actually holds.
    await pump(tester, 'something-unmapped');
    expect(find.textContaining('غير معروف'), findsWidgets);
  });

  testWidgets('offers card and click, which used to be missing entirely',
      (tester) async {
    await pump(tester, 'cash');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('بطاقة (بنك)'), findsWidgets);
    expect(find.text('كليك'), findsWidgets);
  });
}
