// C1 — the PicPos sales/purchase invoice form on the owner's reference
// layout: page header (title + number + status chip), header-field card,
// search/add bar, lines table, totals + payment, collapsible «تفاصيل إضافية»,
// bottom action bar.
//
// Measured here:
//   • renders sales AND purchase in RTL + LTR, light + dark, at 1366×768 with
//     zero overflow reports;
//   • every action-bar button reaches the SAME handler it did before the
//     redesign (approve → onSave print=false · save&print → onSave print=true
//     · draft → onSaveDraft · A4 → onPreviewA4 · back → onCancel), and F9
//     still saves;
//   • C2: the «حساب المبيعات» field (sales only) offers the given revenue
//     accounts, defaults to the mapped one (handed over as `null`), and a
//     different choice is handed over before onSave.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/picpos_invoice_draft.dart';
import 'package:picpos_erp/presentation/invoice_form_picpos/picpos_invoice_form.dart';

const _parties = [PicPosPartyOption(id: 7, name: 'شركة النور')];
const _products = [
  PicPosProductOption(
    id: 1,
    name: 'ورق طباعة A4',
    salePrice: 60,
    costPrice: 40,
    taxRate: 14,
    barcode: '6221',
  ),
];
const _warehouses = [
  PicPosWarehouseOption(id: 2, name: 'الرئيسي', branchName: 'الفرع الرئيسي'),
];
const _revenue = [
  PicPosNamedOption(id: 41, name: '4121 — مبيعات محلية'),
  PicPosNamedOption(id: 42, name: '4122 — مبيعات تصدير'),
];

class _Calls {
  final saves = <bool>[];
  int drafts = 0;
  int previews = 0;
  int cancels = 0;
  final revenue = <int?>[];
}

Future<_Calls> _pump(
  WidgetTester tester, {
  required PicPosInvoiceKind kind,
  TextDirection dir = TextDirection.rtl,
  Brightness brightness = Brightness.light,
  List<String>? overflows,
  PicPosInvoiceInitial? initial,
}) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final calls = _Calls();
  final previous = FlutterError.onError;
  if (overflows != null) {
    FlutterError.onError = (d) {
      final s = d.toString();
      if (s.contains('overflowed')) overflows.add(s.split('\n').first);
    };
  }
  try {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (context, child) =>
          Directionality(textDirection: dir, child: child!),
      home: Scaffold(
        body: PicPosInvoiceForm(
          kind: kind,
          parties: _parties,
          products: _products,
          warehouses: _warehouses,
          costCenters: const [PicPosNamedOption(id: 3, name: 'الإدارة')],
          systemTaxRate: 14,
          invoiceNumberPreview: 'INV-1042',
          userName: 'محمود',
          initialWarehouseId: 2,
          initial: initial,
          revenueAccounts: kind.isSales ? _revenue : const [],
          defaultRevenueAccountId: kind.isSales ? 41 : null,
          onRevenueAccountChanged: calls.revenue.add,
          onCancel: () => calls.cancels++,
          onSave: ({
            required partyId,
            required supplierInvoiceNumber,
            required date,
            required subtotal,
            required discount,
            required tax,
            required net,
            required paid,
            required notes,
            required items,
            required warehouseId,
            required costCenterId,
            required paymentMethod,
            required printAfterSave,
            required sourceOrderId,
          }) async =>
              calls.saves.add(printAfterSave),
          onSaveDraft: kind.isSales
              ? ({
                  required partyId,
                  required notes,
                  required items,
                  required subtotal,
                  required discount,
                  required tax,
                  required net,
                }) async =>
                  calls.drafts++
              : null,
          onPreviewA4: kind.isSales
              ? ({
                  required partyId,
                  required date,
                  required items,
                  required subtotal,
                  required discount,
                  required tax,
                  required net,
                  required paid,
                  required notes,
                }) async =>
                  calls.previews++
              : null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  } finally {
    if (overflows != null) FlutterError.onError = previous;
  }
  return calls;
}

PicPosInvoiceInitial _initial({String supplierInvoice = ''}) =>
    PicPosInvoiceInitial(
      partyId: 7,
      warehouseId: 2,
      supplierInvoiceNumber: supplierInvoice,
      lines: const [
        PicPosInvoiceLine(
          productId: 1,
          productName: 'ورق طباعة A4',
          quantity: 2,
          unitPrice: 60,
        ),
      ],
    );

Future<void> _addLine(WidgetTester tester) async {
  await tester.enterText(find.byKey(quickAddSearchKey), '6221');
  await tester.tap(find.text('إضافة'));
  await tester.pumpAndSettle();
}

void main() {
  group('1366×768 — RTL/LTR × light/dark × sales/purchase: no overflow', () {
    for (final kind in PicPosInvoiceKind.values) {
      for (final dir in TextDirection.values) {
        for (final b in Brightness.values) {
          testWidgets('${kind.name} ${dir.name} ${b.name}', (tester) async {
            final overflows = <String>[];
            await _pump(tester,
                kind: kind, dir: dir, brightness: b, overflows: overflows);
            // A line, and the collapsible details opened — the tallest state.
            await _addLine(tester);
            const toggle = Key('picpos_invoice_details_toggle');
            await tester.ensureVisible(find.byKey(toggle));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(toggle));
            await tester.pumpAndSettle();

            expect(overflows, isEmpty, reason: overflows.join('\n'));
            expect(find.byKey(const Key('picpos_invoice_status_chip')),
                findsOneWidget);
            expect(find.text('مسودة'), findsOneWidget);
            expect(find.text('INV-1042'), findsWidgets);
            expect(find.byKey(const Key('picpos_invoice_grand_total')),
                findsOneWidget);
            expect(find.text('ملاحظات على الفاتورة'), findsOneWidget,
                reason: 'notes live inside «تفاصيل إضافية»');
            expect(find.byKey(const Key('picpos_invoice_approve')),
                findsOneWidget);
            expect(find.byKey(const Key('picpos_invoice_back')), findsOneWidget);
            // Payment methods stay reachable.
            for (final m in ['نقدي', 'آجل', 'تحويل']) {
              expect(find.text(m), findsOneWidget);
            }
            expect(find.byKey(const Key('picpos_revenue_account_field')),
                kind.isSales ? findsOneWidget : findsNothing);
            expect(find.text('رقم فاتورة المورد'),
                kind.isSales ? findsNothing : findsOneWidget);
          });
        }
      }
    }
  });

  testWidgets('approve / save&print / back reach the same handlers',
      (tester) async {
    final calls =
        await _pump(tester, kind: PicPosInvoiceKind.sales, initial: _initial());
    // Edit mode keeps the honest «حفظ التعديلات» label.
    expect(find.text('حفظ التعديلات'), findsOneWidget);

    await tester.tap(find.byKey(const Key('picpos_invoice_approve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picpos_invoice_save_print')));
    await tester.pumpAndSettle();
    expect(calls.saves, [false, true]);

    await tester.tap(find.byKey(const Key('picpos_invoice_back')));
    await tester.pumpAndSettle();
    expect(calls.cancels, 1);
  });

  testWidgets('F9 still saves (keyboard shortcut unchanged)', (tester) async {
    final calls =
        await _pump(tester, kind: PicPosInvoiceKind.sales, initial: _initial());
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(calls.saves, [false]);
  });

  testWidgets('new sales invoice: draft → quotation handler, A4 → preview',
      (tester) async {
    final calls = await _pump(tester, kind: PicPosInvoiceKind.sales);
    expect(find.text('مراجعة واعتماد'), findsOneWidget);
    await _addLine(tester);

    await tester.tap(find.byKey(const Key('picpos_invoice_save_draft')));
    await tester.pumpAndSettle();
    expect(calls.drafts, 1);

    await tester.tap(find.byKey(const Key('picpos_invoice_preview_a4')));
    await tester.pumpAndSettle();
    expect(calls.previews, 1);
    expect(calls.saves, isEmpty);
  });

  testWidgets('purchase: no draft, supplier invoice no. still required',
      (tester) async {
    final calls = await _pump(tester,
        kind: PicPosInvoiceKind.purchase, initial: _initial());
    expect(find.byKey(const Key('picpos_invoice_save_draft')), findsNothing);
    expect(find.byKey(const Key('picpos_invoice_preview_a4')), findsNothing);

    await tester.tap(find.byKey(const Key('picpos_invoice_approve')));
    await tester.pumpAndSettle();
    expect(calls.saves, isEmpty,
        reason: 'the supplier-invoice-number rule must still block the save');
  });

  group('C2 — «حساب المبيعات»', () {
    testWidgets('default (mapped) account is handed over as null',
        (tester) async {
      final calls = await _pump(tester,
          kind: PicPosInvoiceKind.sales, initial: _initial());
      expect(find.text('4121 — مبيعات محلية'), findsOneWidget);
      await tester.tap(find.byKey(const Key('picpos_invoice_approve')));
      await tester.pumpAndSettle();
      expect(calls.revenue, [null]);
      expect(calls.saves, [false]);
    });

    testWidgets('a different revenue account is handed over before onSave',
        (tester) async {
      final calls = await _pump(tester,
          kind: PicPosInvoiceKind.sales, initial: _initial());
      await tester.tap(find.byKey(const Key('picpos_revenue_account_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4122 — مبيعات تصدير').last);
      await tester.pumpAndSettle();
      expect(find.text('4122 — مبيعات تصدير'), findsOneWidget);

      await tester.tap(find.byKey(const Key('picpos_invoice_approve')));
      await tester.pumpAndSettle();
      expect(calls.revenue, [42]);
      expect(calls.saves, [false]);
    });
  });
}
