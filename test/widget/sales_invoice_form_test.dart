// Spec 090 — widget tests for the extracted SalesInvoiceForm.
//
// These do NOT exercise the save path (that would require a full
// Riverpod + Drift fake harness). They cover the structural pieces unique
// to the new pattern:
//   1. Form mounts in a Scaffold without throwing (replaces the freezing
//      AlertDialog + StatefulBuilder + PopScope path).
//   2. Cancel with empty items pops immediately — no UnsavedChangesDialog
//      (proves the explicit-cancel guard works without PopScope).
//   3. isReturnMode toggle flips the header title.
//   4. editQuotation mode shows only Cancel + "حفظ التعديلات".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/quotation_entity.dart';
import 'package:picpos_erp/presentation/screens/widgets/sales_invoices/sales_invoice_form.dart';

// Typed no-op callbacks. Using the public typedefs from the form ensures
// the parameter list stays in sync with the production widget — a function
// declaration would drop that typedef binding and force us to re-type all
// params by hand, so the typed-variable form is deliberate here.
// ignore: prefer_function_declarations_over_variables
final SalesInvoiceSaveQuotationCallback _noopSaveQuotation = ({
  required dialogContext,
  required existingId,
  required existingNumber,
  required customerId,
  required notes,
  required invoiceItems,
  required subtotal,
  required discount,
  required tax,
  required total,
}) async {};

// ignore: prefer_function_declarations_over_variables
final SalesInvoiceSaveInvoiceCallback _noopSaveInvoice = ({
  required dialogContext,
  required customerId,
  required paymentMethod,
  required notes,
  required invoiceItems,
  required subtotal,
  required discount,
  required tax,
  required total,
  required paid,
  required isReturnMode,
  required printAfterSave,
  required taxEnabled,
  convertingQuotationId,
  required products,
  warehouseId,
  costCenterId,
}) async {};

Widget _hostForm({QuotationEntity? editQuotation}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SalesInvoiceForm(
          customers: const [],
          initialProducts: const [],
          categories: const [],
          warehouses: const [],
          costCenters: const [],
          systemTaxRate: 0.14,
          editQuotation: editQuotation,
          onSaveQuotation: _noopSaveQuotation,
          onSaveInvoice: _noopSaveInvoice,
        ),
      ),
    ),
  );
}

QuotationEntity _quotation({String number = 'Q-1'}) => QuotationEntity(
      id: 1,
      quotationNumber: number,
      warehouseId: 1,
      userId: 1,
      quotationDate: DateTime(2026, 5, 23),
      validityDate: DateTime(2026, 6, 23),
      subtotal: 0,
      discount: 0,
      tax: 0,
      total: 0,
      status: 'draft',
    );

void main() {
  testWidgets('SalesInvoiceForm — new-invoice mode renders the 4-button action set', (tester) async {
    await tester.pumpWidget(_hostForm());
    await tester.pumpAndSettle();

    expect(find.text('فاتورة مبيعات جديدة'), findsOneWidget);
    expect(find.text('حفظ مسودة عرض أسعار'), findsOneWidget);
    expect(find.text('حفظ وطباعة'), findsOneWidget);
    expect(find.text('حفظ الفاتورة (F12)'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'إلغاء'), findsOneWidget);
  });

  testWidgets('SalesInvoiceForm — Cancel with empty items pops immediately (no UnsavedChangesDialog)', (tester) async {
    bool didDismiss = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(builder: (ctx) {
              return ElevatedButton(
                onPressed: () async {
                  await Navigator.of(ctx).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: SalesInvoiceForm(
                          customers: const [],
                          initialProducts: const [],
                          categories: const [],
                          warehouses: const [],
                          costCenters: const [],
                          systemTaxRate: 0.14,
                          onSaveQuotation: _noopSaveQuotation,
                          onSaveInvoice: _noopSaveInvoice,
                        ),
                      ),
                    ),
                  );
                  didDismiss = true;
                },
                child: const Text('open'),
              );
            }),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة مبيعات جديدة'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
    await tester.pumpAndSettle();

    expect(find.text('فاتورة مبيعات جديدة'), findsNothing);
    expect(
      find.text('يوجد تغييرات غير محفوظة. هل أنت متأكد من مغادرة هذه الصفحة؟ سيتم فقدان التغييرات.'),
      findsNothing,
    );
    expect(didDismiss, isTrue);
  });

  testWidgets('SalesInvoiceForm — isReturnMode toggle updates header', (tester) async {
    await tester.pumpWidget(_hostForm());
    await tester.pumpAndSettle();

    expect(find.text('فاتورة مبيعات جديدة'), findsOneWidget);

    await tester.tap(find.text('مرتجع مبيعات').first);
    await tester.pumpAndSettle();

    expect(find.text('فاتورة مبيعات جديدة'), findsNothing);
    // After the toggle, "مرتجع مبيعات" appears in both the segment and header.
    expect(find.text('مرتجع مبيعات'), findsWidgets);
  });

  testWidgets('SalesInvoiceForm — editQuotation mode shows only Cancel + حفظ التعديلات', (tester) async {
    await tester.pumpWidget(_hostForm(editQuotation: _quotation(number: 'Q-42')));
    await tester.pumpAndSettle();

    expect(find.text('تعديل عرض سعر #Q-42'), findsOneWidget);
    expect(find.text('حفظ التعديلات'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'إلغاء'), findsOneWidget);

    expect(find.text('حفظ مسودة عرض أسعار'), findsNothing);
    expect(find.text('حفظ وطباعة'), findsNothing);
    expect(find.text('حفظ الفاتورة (F12)'), findsNothing);
  });
}
