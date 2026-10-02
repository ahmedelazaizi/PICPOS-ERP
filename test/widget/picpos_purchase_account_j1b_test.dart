// J1b — the «حساب المشتريات» field on the PicPos PURCHASE invoice form.
//
//   • purchase only (sales shows none), defaults to the mapped account (handed
//     over as `null`), a different choice is handed over before onSave;
//   • an edited invoice opens on its stored account;
//   • renders in RTL + LTR, light + dark at 1366×768 with no overflow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_invoice_draft.dart';
import 'package:ural_erp/presentation/invoice_form_picpos/picpos_invoice_form.dart';

const _accounts = [
  PicPosNamedOption(id: 51, name: '1136 — مخزون البضاعة للبيع'),
  PicPosNamedOption(id: 52, name: '5211 — المشتريات'),
  PicPosNamedOption(id: 53, name: '5299 — المشتريات الخارجية'),
];
const _field = Key('picpos_purchase_account_field');

class _Calls {
  final saves = <bool>[];
  final accounts = <int?>[];
}

Future<_Calls> _pump(
  WidgetTester tester, {
  PicPosInvoiceKind kind = PicPosInvoiceKind.purchase,
  TextDirection dir = TextDirection.rtl,
  Brightness brightness = Brightness.light,
  List<String>? overflows,
  int? storedAccountId,
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
          parties: const [PicPosPartyOption(id: 7, name: 'شركة النور')],
          products: const [
            PicPosProductOption(
              id: 1,
              name: 'ورق طباعة A4',
              salePrice: 60,
              costPrice: 40,
              taxRate: 14,
              barcode: '6221',
            ),
          ],
          warehouses: const [
            PicPosWarehouseOption(
                id: 2, name: 'الرئيسي', branchName: 'الفرع الرئيسي'),
          ],
          costCenters: const [],
          systemTaxRate: 14,
          invoiceNumberPreview: 'PINV-1',
          initialWarehouseId: 2,
          initial: const PicPosInvoiceInitial(
            partyId: 7,
            warehouseId: 2,
            supplierInvoiceNumber: 'S-1',
            lines: [
              PicPosInvoiceLine(
                productId: 1,
                productName: 'ورق طباعة A4',
                quantity: 2,
                unitPrice: 60,
              ),
            ],
          ),
          purchaseAccounts: _accounts,
          defaultPurchaseAccountId: 51,
          initialPurchaseAccountId: storedAccountId,
          onPurchaseAccountChanged: calls.accounts.add,
          onCancel: () {},
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
        ),
      ),
    ));
    await tester.pumpAndSettle();
  } finally {
    if (overflows != null) FlutterError.onError = previous;
  }
  return calls;
}

void main() {
  for (final dir in TextDirection.values) {
    for (final b in Brightness.values) {
      testWidgets('field renders, no overflow — ${dir.name} ${b.name}',
          (tester) async {
        final overflows = <String>[];
        await _pump(tester, dir: dir, brightness: b, overflows: overflows);
        expect(find.byKey(_field), findsOneWidget);
        expect(find.text('حساب المشتريات'), findsWidgets);
        expect(find.text('1136 — مخزون البضاعة للبيع'), findsOneWidget);
        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }
  }

  testWidgets('sales form has no purchase-account field', (tester) async {
    await _pump(tester, kind: PicPosInvoiceKind.sales);
    expect(find.byKey(_field), findsNothing);
  });

  testWidgets('default (mapped) account is handed over as null',
      (tester) async {
    final calls = await _pump(tester);
    await tester.tap(find.byKey(const Key('picpos_invoice_approve')));
    await tester.pumpAndSettle();
    expect(calls.accounts, [null]);
    expect(calls.saves, [false]);
  });

  testWidgets('choosing external purchases is handed over before onSave',
      (tester) async {
    final calls = await _pump(tester);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5299 — المشتريات الخارجية').last);
    await tester.pumpAndSettle();
    expect(find.text('5299 — المشتريات الخارجية'), findsOneWidget);

    await tester.tap(find.byKey(const Key('picpos_invoice_approve')));
    await tester.pumpAndSettle();
    expect(calls.accounts, [53]);
    expect(calls.saves, [false]);
  });

  testWidgets('an edited invoice opens on its stored account', (tester) async {
    final calls = await _pump(tester, storedAccountId: 52);
    expect(find.text('5211 — المشتريات'), findsOneWidget);
    await tester.tap(find.byKey(const Key('picpos_invoice_approve')));
    await tester.pumpAndSettle();
    expect(calls.accounts, [52]);
  });
}
